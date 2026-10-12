#!/usr/bin/env node

/*
 * Adds Simplified Chinese fields to the existing 2026 fall operator To-dos.
 * It never creates language-specific Firestore collections and never touches
 * user progress or personal To-dos.
 *
 * Usage:
 *   node apply_todo_zh_hans_2026_fall.js
 *   node apply_todo_zh_hans_2026_fall.js --apply
 *   node apply_todo_zh_hans_2026_fall.js --rollback <backup.json>
 */

const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');

const projectId = 'flutterproject3-af322';
const semesterId = '2026_fall';
const apply = process.argv.includes('--apply');
const rollbackIndex = process.argv.indexOf('--rollback');
const rollbackPath = rollbackIndex >= 0 ? process.argv[rollbackIndex + 1] : null;
const seedPath = path.join(__dirname, 'data', 'semester_2026_fall.json');
const translationPath = path.join(
  __dirname,
  'data',
  'semester_2026_fall_zh_Hans.json',
);
const languageKeys = ['zh_Hans', 'zh', 'zh_Hans_CN'];

if (admin.apps.length === 0) admin.initializeApp({projectId});
const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function weekDocumentId(weekNumber) {
  return `week_${String(weekNumber).padStart(2, '0')}`;
}

function readJson(filePath) {
  invariant(fs.existsSync(filePath), `Missing data file: ${filePath}`);
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function sourceIndex() {
  const seed = readJson(seedPath);
  const translation = readJson(translationPath);
  invariant(seed.projectId === projectId, 'Seed project mismatch.');
  invariant(translation.projectId === projectId, 'Translation project mismatch.');
  invariant(translation.semesterId === semesterId, 'Translation semester mismatch.');
  invariant(translation.language === 'zh_Hans', 'Unexpected translation language.');

  const sources = new Map();
  for (const week of seed.weeks || []) {
    invariant(week.id === weekDocumentId(week.weekNumber), `Invalid seed week ${week.id}`);
    for (const task of week.tasks || []) {
      invariant(!sources.has(task.id), `Duplicate seed task: ${task.id}`);
      sources.set(task.id, {
        weekNumber: week.weekNumber,
        koTitle: task.title?.ko || '',
        enTitle: task.title?.en || '',
        koDescription: task.description?.ko || '',
        enDescription: task.description?.en || '',
      });
    }
  }

  const translations = new Map();
  for (const week of translation.weeks || []) {
    invariant(
      week.id === weekDocumentId(week.weekNumber),
      `Invalid translation week ${week.id}`,
    );
    for (const task of week.tasks || []) {
      invariant(!translations.has(task.id), `Duplicate translation task: ${task.id}`);
      invariant(task.title?.trim(), `Missing Chinese title: ${task.id}`);
      invariant(task.description?.trim(), `Missing Chinese description: ${task.id}`);
      translations.set(task.id, {
        weekNumber: week.weekNumber,
        title: task.title.trim(),
        description: task.description.trim(),
      });
    }
  }

  invariant(sources.size === 37, `Expected 37 source tasks; got ${sources.size}`);
  invariant(
    translations.size === sources.size,
    `Chinese/source task count mismatch: ${translations.size}/${sources.size}`,
  );
  for (const [id, source] of sources) {
    const translated = translations.get(id);
    invariant(translated, `Missing Chinese task: ${id}`);
    invariant(
      translated.weekNumber === source.weekNumber,
      `Chinese week mismatch: ${id}`,
    );
  }
  for (const id of translations.keys()) {
    invariant(sources.has(id), `Unknown Chinese task: ${id}`);
  }
  return {sources, translations};
}

function localizedValue(map, key) {
  const value = map && Object.hasOwn(map, key) ? map[key] : undefined;
  return value == null ? '' : value.toString().trim();
}

function chineseState(data) {
  return {
    title: Object.fromEntries(
      languageKeys.map((key) => [key, localizedValue(data.title, key)]),
    ),
    description: Object.fromEntries(
      languageKeys.map((key) => [key, localizedValue(data.description, key)]),
    ),
  };
}

function hasAnyChinese(state) {
  return Object.values(state.title).some(Boolean) ||
    Object.values(state.description).some(Boolean);
}

function matchesChinese(state, desired) {
  const titleValues = [state.title.zh_Hans, state.title.zh];
  const descriptionValues = [state.description.zh_Hans, state.description.zh];
  const cnTitleMatches = !state.title.zh_Hans_CN ||
    state.title.zh_Hans_CN === desired.title;
  const cnDescriptionMatches = !state.description.zh_Hans_CN ||
    state.description.zh_Hans_CN === desired.description;
  return titleValues.every((value) => value === desired.title) &&
    descriptionValues.every((value) => value === desired.description) &&
    cnTitleMatches && cnDescriptionMatches;
}

function sourceMatches(data, source) {
  return data.title?.ko === source.koTitle &&
    data.title?.en === source.enTitle &&
    data.description?.ko === source.koDescription &&
    data.description?.en === source.enDescription;
}

function previousField(map, key) {
  return {
    exists: Boolean(map && Object.hasOwn(map, key)),
    value: map && Object.hasOwn(map, key) ? map[key] : null,
  };
}

function backupFields(data) {
  return {
    title: Object.fromEntries(languageKeys.map((key) => [key, previousField(data.title, key)])),
    description: Object.fromEntries(
      languageKeys.map((key) => [key, previousField(data.description, key)]),
    ),
  };
}

async function createPlan(index) {
  const semester = await db.doc(`semesters/${semesterId}`).get();
  invariant(semester.exists, `Missing semester: ${semesterId}`);
  invariant(semester.get('status') === 'active', `${semesterId} is not active.`);

  const plan = [];
  const seenSourceIds = new Set();
  for (let weekNumber = 1; weekNumber <= 16; weekNumber += 1) {
    const weekRef = db.doc(
      `semesters/${semesterId}/weeks/${weekDocumentId(weekNumber)}`,
    );
    const week = await weekRef.get();
    invariant(week.exists, `Missing week: ${week.ref.path}`);
    invariant(week.get('isPublished') === true, `Week ${weekNumber} is not published.`);
    const tasks = await weekRef.collection('tasks').get();
    for (const task of tasks.docs) {
      const data = task.data();
      const sourceTaskId = (data.sourceTaskId || '').toString();
      const source = index.sources.get(sourceTaskId);
      if (!source) continue;
      seenSourceIds.add(sourceTaskId);
      const desired = index.translations.get(sourceTaskId);
      const state = chineseState(data);
      if (source.weekNumber !== weekNumber) {
        plan.push({task, data, desired, status: 'hold', reason: 'week mismatch'});
      } else if (!sourceMatches(data, source)) {
        plan.push({task, data, desired, status: 'hold', reason: 'Korean/English source changed'});
      } else if (matchesChinese(state, desired)) {
        plan.push({task, data, desired, status: 'unchanged'});
      } else if (hasAnyChinese(state)) {
        plan.push({task, data, desired, status: 'hold', reason: 'existing Chinese differs'});
      } else {
        plan.push({task, data, desired, status: 'update'});
      }
    }
  }
  const missing = [...index.sources.keys()].filter((id) => !seenSourceIds.has(id));
  invariant(missing.length === 0, `Missing live tasks: ${missing.join(', ')}`);
  invariant(plan.length === 69, `Expected 69 live documents; got ${plan.length}`);
  return plan;
}

function summarize(plan) {
  const summary = {create: 0, update: 0, unchanged: 0, hold: 0, failed: 0};
  for (const entry of plan) summary[entry.status] += 1;
  return summary;
}

function writeBackup(plan) {
  const directory = path.join(__dirname, 'backups');
  fs.mkdirSync(directory, {recursive: true});
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const filePath = path.join(directory, `todo_${semesterId}_zh_${stamp}.json`);
  const documents = plan
    .filter((entry) => entry.status === 'update')
    .map((entry) => ({
      path: entry.task.ref.path,
      previous: backupFields(entry.data),
      applied: entry.desired,
    }));
  fs.writeFileSync(filePath, `${JSON.stringify({
    projectId,
    semesterId,
    createdAt: new Date().toISOString(),
    documents,
  }, null, 2)}\n`, {flag: 'wx'});
  return filePath;
}

function chineseUpdate(entry) {
  const update = {
    'title.zh_Hans': entry.desired.title,
    'title.zh': entry.desired.title,
    'description.zh_Hans': entry.desired.description,
    'description.zh': entry.desired.description,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (entry.data.title && Object.hasOwn(entry.data.title, 'zh_Hans_CN')) {
    update['title.zh_Hans_CN'] = entry.desired.title;
  }
  if (entry.data.description && Object.hasOwn(entry.data.description, 'zh_Hans_CN')) {
    update['description.zh_Hans_CN'] = entry.desired.description;
  }
  return update;
}

async function applyPlan(plan) {
  const updates = plan.filter((entry) => entry.status === 'update');
  if (updates.length === 0) return;
  const batch = db.batch();
  for (const entry of updates) {
    batch.update(
      entry.task.ref,
      chineseUpdate(entry),
      {lastUpdateTime: entry.task.updateTime},
    );
  }
  await batch.commit();
}

async function verifyAllTasksHaveChinese() {
  const missing = [];
  let checked = 0;
  for (let weekNumber = 1; weekNumber <= 16; weekNumber += 1) {
    const snapshot = await db.collection(
      `semesters/${semesterId}/weeks/${weekDocumentId(weekNumber)}/tasks`,
    ).get();
    for (const task of snapshot.docs) {
      checked += 1;
      const data = task.data();
      if (!localizedValue(data.title, 'zh_Hans') ||
          !localizedValue(data.title, 'zh') ||
          !localizedValue(data.description, 'zh_Hans') ||
          !localizedValue(data.description, 'zh')) {
        missing.push(task.ref.path);
      }
    }
  }
  return {checked, missing};
}

function rollbackValue(record) {
  const update = {updatedAt: FieldValue.serverTimestamp()};
  for (const section of ['title', 'description']) {
    for (const key of languageKeys) {
      const previous = record.previous[section][key];
      update[`${section}.${key}`] = previous.exists
        ? previous.value
        : FieldValue.delete();
    }
  }
  return update;
}

async function rollback(filePath) {
  invariant(filePath, '--rollback requires a backup path.');
  const absolutePath = path.resolve(process.cwd(), filePath);
  const backup = readJson(absolutePath);
  invariant(backup.projectId === projectId, 'Backup project mismatch.');
  invariant(backup.semesterId === semesterId, 'Backup semester mismatch.');
  const snapshots = await db.getAll(...backup.documents.map((record) => db.doc(record.path)));
  const conflicts = [];
  for (let index = 0; index < backup.documents.length; index += 1) {
    const record = backup.documents[index];
    const snapshot = snapshots[index];
    if (!snapshot.exists || !matchesChinese(chineseState(snapshot.data()), record.applied)) {
      conflicts.push(record.path);
    }
  }
  invariant(conflicts.length === 0, `Rollback conflicts:\n${conflicts.join('\n')}`);
  const batch = db.batch();
  for (let index = 0; index < backup.documents.length; index += 1) {
    batch.update(
      snapshots[index].ref,
      rollbackValue(backup.documents[index]),
      {lastUpdateTime: snapshots[index].updateTime},
    );
  }
  await batch.commit();
  console.log(JSON.stringify({rolledBack: backup.documents.length, backup: absolutePath}, null, 2));
}

async function run() {
  if (rollbackIndex >= 0) {
    await rollback(rollbackPath);
    return;
  }
  const index = sourceIndex();
  const plan = await createPlan(index);
  const summary = summarize(plan);
  console.log(JSON.stringify({
    projectId,
    semesterId,
    translations: index.translations.size,
    documents: plan.length,
    summary,
    holds: plan
      .filter((entry) => entry.status === 'hold')
      .map((entry) => ({path: entry.task.ref.path, reason: entry.reason})),
  }, null, 2));
  if (!apply) {
    console.log('Dry-run only. Use --apply after reviewing the plan.');
    return;
  }
  invariant(summary.hold === 0, 'Resolve held documents before applying.');
  const backupPath = writeBackup(plan);
  await applyPlan(plan);
  const verification = await verifyAllTasksHaveChinese();
  invariant(
    verification.missing.length === 0,
    `Chinese verification failed:\n${verification.missing.join('\n')}`,
  );
  console.log(JSON.stringify({
    updated: summary.update,
    backupPath,
    verifiedTaskDocuments: verification.checked,
  }, null, 2));
}

run().catch((error) => {
  console.error('Simplified Chinese To-do apply failed:', error);
  process.exitCode = 1;
});
