#!/usr/bin/env node

/*
 * 학기별 To-do 원본 데이터를 비파괴적으로 배포한다.
 *
 * Usage:
 *   npm run seed-semester:dry-run
 *   npm run seed-semester:apply
 *
 * ADC가 필요하며, 대상 프로젝트를 잘못 선택하지 않도록 JSON의 projectId와
 * 현재 인증 프로젝트를 모두 확인한다. 기존에 없는 문서에는 createdAt을,
 * 모든 병합 문서에는 updatedAt을 서버 시간으로 기록한다.
 */
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');

const apply = process.argv.includes('--apply');
const dataPath = path.join(__dirname, 'data', 'semester_2026_fall.json');
const seed = JSON.parse(fs.readFileSync(dataPath, 'utf8'));

if (admin.apps.length === 0) {
  admin.initializeApp({projectId: seed.projectId});
}

const db = admin.firestore();
const Timestamp = admin.firestore.Timestamp;
const FieldValue = admin.firestore.FieldValue;
const audiences = ['exchange', 'korean'];

function weekDocumentId(weekNumber) {
  return `week_${String(weekNumber).padStart(2, '0')}`;
}

function audienceTaskDocumentId(sourceTaskId, audience) {
  return `${sourceTaskId}_${audience}`;
}

function timestamp(value, field) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`Invalid ${field}: ${value}`);
  }
  return Timestamp.fromDate(date);
}

function validate() {
  if (seed.projectId !== 'flutterproject3-af322') {
    throw new Error(`Unexpected projectId: ${seed.projectId}`);
  }
  if (!seed.semester?.id || !Array.isArray(seed.weeks)) {
    throw new Error('semester.id and weeks are required.');
  }
  if (seed.weeks.length !== seed.semester.totalWeeks) {
    throw new Error('weeks count must match semester.totalWeeks.');
  }
  const weekNumbers = new Set();
  const semesterStart = new Date(seed.semester.startDate);
  for (const week of seed.weeks) {
    const expectedWeekId = weekDocumentId(week.weekNumber);
    if (week.id !== expectedWeekId) {
      throw new Error(`Week ${week.weekNumber} id must be ${expectedWeekId}.`);
    }
    if (weekNumbers.has(week.weekNumber)) {
      throw new Error(`Duplicate weekNumber: ${week.weekNumber}`);
    }
    weekNumbers.add(week.weekNumber);
    const start = new Date(week.startDate);
    const end = new Date(week.endDate);
    const startKst = new Date(start.getTime() + 9 * 60 * 60 * 1000);
    const endKst = new Date(end.getTime() + 9 * 60 * 60 * 1000);
    if (week.weekNumber === 1) {
      if (start.getTime() !== semesterStart.getTime() || endKst.getUTCDay() !== 0) {
        throw new Error('Week 1 must start with the semester and end on Sunday.');
      }
    } else if (startKst.getUTCDay() !== 1 || endKst.getUTCDay() !== 0) {
      throw new Error(`Week ${week.weekNumber} must run Monday through Sunday.`);
    }
    const durationDays = Math.round((end.getTime() - start.getTime() + 1000) / 86400000);
    if (week.weekNumber > 1 && durationDays !== 7) {
      throw new Error(`Week ${week.weekNumber} must contain seven calendar days.`);
    }
    for (const task of week.tasks || []) {
      if (!task.id || !task.title?.ko || !task.title?.en) {
        throw new Error(`Invalid task in week ${week.weekNumber}`);
      }
      if (!['required', 'recommendation', 'notice'].includes(task.type)) {
        throw new Error(`Invalid task type: ${task.type}`);
      }
      if (!Array.isArray(task.targetAudiences) || task.targetAudiences.length === 0) {
        throw new Error(`Missing targetAudiences: ${task.id}`);
      }
      if (task.targetAudiences.some((item) => !audiences.includes(item))) {
        throw new Error(`Invalid target audience: ${task.id}`);
      }
    }
  }
}

function documentPlan() {
  const semester = seed.semester;
  const semesterRef = db.collection('semesters').doc(semester.id);
  const documents = [{
    ref: semesterRef,
    data: {
      name: semester.title,
      title: semester.title,
      startDate: timestamp(semester.startDate, 'semester.startDate'),
      endDate: timestamp(semester.endDate, 'semester.endDate'),
      totalWeeks: semester.totalWeeks,
      status: semester.status,
      currentWeekOverride: semester.currentWeekOverride ?? null,
      schemaVersion: 1,
    },
  }];

  for (const week of seed.weeks) {
    const weekRef = semesterRef
      .collection('weeks')
      .doc(weekDocumentId(week.weekNumber));
    documents.push({
      ref: weekRef,
      data: {
        weekNumber: week.weekNumber,
        startDate: timestamp(week.startDate, `week ${week.weekNumber} startDate`),
        endDate: timestamp(week.endDate, `week ${week.weekNumber} endDate`),
        isPublished: week.isPublished === true,
        schemaVersion: 1,
      },
    });
    for (const task of week.tasks || []) {
      for (const audience of [...new Set(task.targetAudiences)]) {
        documents.push({
          ref: weekRef
            .collection('tasks')
            .doc(audienceTaskDocumentId(task.id, audience)),
          data: {
            sourceTaskId: task.id,
            audience,
            title: task.title,
            description: task.description || {ko: '', en: ''},
            type: task.type,
            targetAudiences: [audience],
            sortOrder: task.sortOrder,
            isActive: task.isActive !== false,
            actionType: task.actionType || 'none',
            actionValue: task.actionValue || '',
            carryOver: task.carryOver === true,
            dueDate: task.dueDate ? timestamp(task.dueDate, `${task.id}.dueDate`) : null,
            schemaVersion: 2,
          },
        });
      }
    }
  }
  return documents;
}

function taskSourceId(documentId, data) {
  const explicit = data.sourceTaskId?.toString().trim();
  if (explicit) return explicit;
  const audience = data.audience?.toString();
  if (audiences.includes(audience) && documentId.endsWith(`_${audience}`)) {
    return documentId.slice(0, -(`_${audience}`.length));
  }
  return documentId;
}

function taskAudiences(data) {
  const values = Array.isArray(data.targetAudiences)
    ? data.targetAudiences.filter((value) => audiences.includes(value))
    : [];
  if (values.length > 0) return [...new Set(values)];
  if (audiences.includes(data.audience)) return [data.audience];
  // 구형 문서에 공개 대상 필드가 없으면 누락시키지 않고 두 유형으로 보존한다.
  return audiences;
}

async function migrationPlan() {
  const semesterRef = db.collection('semesters').doc(seed.semester.id);
  const documents = [];
  const cleanup = new Map();

  for (const week of seed.weeks) {
    const canonicalId = weekDocumentId(week.weekNumber);
    const legacyId = `week_${week.weekNumber}`;
    const sourceIds = [...new Set([canonicalId, legacyId])];

    for (const sourceId of sourceIds) {
      const sourceWeekRef = semesterRef.collection('weeks').doc(sourceId);
      const [weekSnapshot, taskSnapshot] = await Promise.all([
        sourceWeekRef.get(),
        sourceWeekRef.collection('tasks').get(),
      ]);
      const canonicalWeekRef = semesterRef.collection('weeks').doc(canonicalId);

      if (weekSnapshot.exists && sourceId !== canonicalId) {
        documents.push({ref: canonicalWeekRef, data: weekSnapshot.data() || {}});
      }

      for (const taskSnapshotDocument of taskSnapshot.docs) {
        const data = taskSnapshotDocument.data();
        const sourceTaskId = taskSourceId(taskSnapshotDocument.id, data);
        for (const audience of taskAudiences(data)) {
          documents.push({
            ref: canonicalWeekRef
              .collection('tasks')
              .doc(audienceTaskDocumentId(sourceTaskId, audience)),
            data: {
              ...data,
              sourceTaskId,
              audience,
              targetAudiences: [audience],
              schemaVersion: 2,
            },
          });
        }

        const isCanonicalAudienceDocument =
          sourceId === canonicalId &&
          audiences.some(
            (audience) =>
              taskSnapshotDocument.id ===
              audienceTaskDocumentId(sourceTaskId, audience),
          );
        if (!isCanonicalAudienceDocument) {
          cleanup.set(
            taskSnapshotDocument.ref.path,
            taskSnapshotDocument.ref,
          );
        }
      }

      if (weekSnapshot.exists && sourceId !== canonicalId) {
        cleanup.set(sourceWeekRef.path, sourceWeekRef);
      }
    }
  }

  return {documents, cleanup: [...cleanup.values()]};
}

function mergeDocumentPlans(...plans) {
  const merged = new Map();
  for (const plan of plans) {
    for (const entry of plan) {
      const previous = merged.get(entry.ref.path);
      merged.set(entry.ref.path, {
        ref: entry.ref,
        data: {...(previous?.data || {}), ...entry.data},
      });
    }
  }
  return [...merged.values()];
}

async function commitDeletes(references) {
  let batch = db.batch();
  let writes = 0;
  for (const reference of references) {
    batch.delete(reference);
    writes += 1;
    if (writes === 450) {
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }
  }
  if (writes > 0) await batch.commit();
}

async function run() {
  validate();
  const migration = await migrationPlan();
  // 실데이터를 먼저 보존하고, 관리 원본(seed)을 마지막에 적용한다.
  const documents = mergeDocumentPlans(migration.documents, documentPlan());
  const existing = await db.getAll(...documents.map((entry) => entry.ref));
  const existingPaths = new Set(existing.filter((snapshot) => snapshot.exists).map((snapshot) => snapshot.ref.path));
  const summary = {
    projectId: seed.projectId,
    semesterId: seed.semester.id,
    weeks: seed.weeks.length,
    logicalTasks: seed.weeks.reduce((sum, week) => sum + (week.tasks || []).length, 0),
    audienceTasks: seed.weeks.reduce(
      (sum, week) =>
        sum +
        (week.tasks || []).reduce(
          (taskSum, task) => taskSum + new Set(task.targetAudiences).size,
          0,
        ),
      0,
    ),
    creates: documents.filter((entry) => !existingPaths.has(entry.ref.path)).length,
    merges: documents.filter((entry) => existingPaths.has(entry.ref.path)).length,
    legacyDeletes: migration.cleanup.length,
    apply,
  };
  console.log(JSON.stringify(summary, null, 2));
  if (!apply) {
    console.log('Dry-run only. Use --apply to write.');
    return;
  }

  let batch = db.batch();
  let writes = 0;
  for (const entry of documents) {
    batch.set(entry.ref, {
      ...entry.data,
      updatedAt: FieldValue.serverTimestamp(),
      ...(!existingPaths.has(entry.ref.path) ? {createdAt: FieldValue.serverTimestamp()} : {}),
    }, {merge: true});
    writes += 1;
    if (writes === 450) {
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }
  }
  if (writes > 0) await batch.commit();
  await commitDeletes(migration.cleanup);
  console.log(`Semester seed deployed: ${seed.semester.id}`);
}

run().catch((error) => {
  console.error('Semester seed failed:', error);
  process.exitCode = 1;
});
