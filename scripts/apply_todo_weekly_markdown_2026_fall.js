#!/usr/bin/env node

/*
 * Applies the reviewed 2026 fall weekly To-do Markdown files without running
 * the legacy semester seed/migration script.
 *
 * Usage:
 *   node apply_todo_weekly_markdown_2026_fall.js
 *   node apply_todo_weekly_markdown_2026_fall.js --apply
 *   node apply_todo_weekly_markdown_2026_fall.js --rollback <backup.json>
 */

const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');

const projectId = 'flutterproject3-af322';
const semesterId = '2026_fall';
const apply = process.argv.includes('--apply');
const rollbackIndex = process.argv.indexOf('--rollback');
const rollbackPath = rollbackIndex >= 0 ? process.argv[rollbackIndex + 1] : null;
const repoRoot = path.resolve(__dirname, '..');
const sourceFiles = {
  ko: path.join(repoRoot, 'Wefilling_Todo_Weekly_KO.md'),
  en: path.join(repoRoot, 'Wefilling_Todo_Weekly_EN.md'),
  zh: path.join(repoRoot, 'Wefilling_Todo_Weekly_ZH.md'),
};
const managedFields = [
  'sourceTaskId',
  'audience',
  'title',
  'description',
  'type',
  'targetAudiences',
  'sortOrder',
  'isActive',
  'actionType',
  'actionValue',
  'carryOver',
  'schemaVersion',
];

if (admin.apps.length === 0) {
  admin.initializeApp({projectId});
}

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function weekDocumentId(weekNumber) {
  return `week_${String(weekNumber).padStart(2, '0')}`;
}

function parseWeekHeading(line, language) {
  const pattern = language === 'en'
    ? /^##\s+Week\s+(\d+)\s+·\s+(\d{4}-\d{2}-\d{2})\s+~\s+(\d{4}-\d{2}-\d{2})/
    : language === 'zh'
      ? /^##\s+第\s*(\d+)\s*周\s+·\s+(\d{4}-\d{2}-\d{2})\s+~\s+(\d{4}-\d{2}-\d{2})/
      : /^##\s+(\d+)주차\s+·\s+(\d{4}-\d{2}-\d{2})\s+~\s+(\d{4}-\d{2}-\d{2})/;
  const match = line.match(pattern);
  return match
    ? {weekNumber: Number(match[1]), startDate: match[2], endDate: match[3]}
    : null;
}

function parseAudience(line, language) {
  const isAudienceLine = language === 'en'
    ? line.startsWith('- Audience:')
    : language === 'zh'
      ? line.startsWith('- 适用群体:')
      : line.startsWith('- 대상 구분:');
  if (!isAudienceLine) return null;
  const shared = language === 'en'
    ? line.includes('International and Korean')
    : language === 'zh'
      ? line.includes('外国学生与韩国学生')
      : line.includes('외국인·한국 학생 공통');
  return shared ? ['exchange', 'korean'] : ['exchange'];
}

function parseMarkdown(filePath, language) {
  invariant(fs.existsSync(filePath), `Missing source file: ${filePath}`);
  const lines = fs.readFileSync(filePath, 'utf8').split(/\r?\n/);
  const tasks = [];
  let week = null;

  for (let index = 0; index < lines.length; index += 1) {
    const parsedWeek = parseWeekHeading(lines[index], language);
    if (parsedWeek) {
      week = parsedWeek;
      continue;
    }
    const heading = lines[index].match(/^###\s+(.+)$/);
    if (!heading) continue;
    invariant(week != null, `Task heading before week in ${filePath}:${index + 1}`);

    const title = heading[1].trim();
    const descriptionLines = [];
    let audience = null;
    let type = null;
    let id = null;
    let actionValue = '';
    let cursor = index + 1;
    let collectingDescription = false;

    for (; cursor < lines.length; cursor += 1) {
      const line = lines[cursor];
      if (/^##\s|^###\s/.test(line)) break;
      if (!line.trim()) {
        continue;
      }
      if (line.startsWith('- ')) {
        const parsedAudience = parseAudience(line, language);
        if (parsedAudience) audience = parsedAudience;
        const metadata = line.match(/`(required|recommendation|notice)`\)\s+·\s+ID:\s+`([^`]+)`/);
        if (metadata) {
          type = metadata[1];
          id = metadata[2];
        }
        const link = line.match(/\[link\]\((https:\/\/[^)]+)\)/i);
        if (link) actionValue = link[1];
        continue;
      }
      collectingDescription = true;
      descriptionLines.push(line.trim());
    }

    invariant(id, `Missing ID for ${title} in ${filePath}`);
    invariant(type, `Missing type for ${id} in ${filePath}`);
    invariant(audience, `Missing audience for ${id} in ${filePath}`);
    invariant(descriptionLines.length > 0, `Missing description for ${id} in ${filePath}`);
    tasks.push({
      id,
      weekNumber: week.weekNumber,
      startDate: week.startDate,
      endDate: week.endDate,
      title,
      description: descriptionLines.join('\n'),
      type,
      audiences: audience,
      actionValue,
    });
  }

  invariant(tasks.length === 30, `${language} must contain 30 tasks; got ${tasks.length}`);
  return tasks;
}

function taskKey(task) {
  return `${task.weekNumber}:${task.id}`;
}

function sameArray(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function buildLogicalTasks() {
  const parsed = Object.fromEntries(
    Object.entries(sourceFiles).map(([language, filePath]) => [
      language,
      parseMarkdown(filePath, language),
    ]),
  );
  const maps = Object.fromEntries(
    Object.entries(parsed).map(([language, tasks]) => [
      language,
      new Map(tasks.map((task) => [taskKey(task), task])),
    ]),
  );
  const koKeys = [...maps.ko.keys()];
  invariant(new Set(koKeys).size === 30, 'Korean task IDs must be unique per week.');

  const logicalTasks = [];
  for (const key of koKeys) {
    const localized = {
      ko: maps.ko.get(key),
      en: maps.en.get(key),
      zh: maps.zh.get(key),
    };
    invariant(localized.en && localized.zh, `Missing localized task: ${key}`);
    for (const language of ['en', 'zh']) {
      const candidate = localized[language];
      invariant(candidate.type === localized.ko.type, `Type mismatch: ${key} (${language})`);
      invariant(
        sameArray(candidate.audiences, localized.ko.audiences),
        `Audience mismatch: ${key} (${language})`,
      );
      invariant(
        candidate.startDate === localized.ko.startDate &&
          candidate.endDate === localized.ko.endDate,
        `Week date mismatch: ${key} (${language})`,
      );
      invariant(
        candidate.actionValue === localized.ko.actionValue,
        `Link mismatch: ${key} (${language})`,
      );
    }
    logicalTasks.push({
      id: localized.ko.id,
      weekNumber: localized.ko.weekNumber,
      startDate: localized.ko.startDate,
      endDate: localized.ko.endDate,
      type: localized.ko.type,
      audiences: localized.ko.audiences,
      actionValue: localized.ko.actionValue,
      title: {
        ko: localized.ko.title,
        en: localized.en.title,
        zh_Hans: localized.zh.title,
        zh: localized.zh.title,
      },
      description: {
        ko: localized.ko.description,
        en: localized.en.description,
        zh_Hans: localized.zh.description,
        zh: localized.zh.description,
      },
    });
  }
  return logicalTasks.sort(
    (left, right) => left.weekNumber - right.weekNumber || left.id.localeCompare(right.id),
  );
}

function pickManaged(data) {
  return Object.fromEntries(
    managedFields.filter((field) => Object.hasOwn(data, field)).map((field) => [field, data[field]]),
  );
}

function normalized(value) {
  if (Array.isArray(value)) return value.map(normalized);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, normalized(value[key])]),
    );
  }
  return value;
}

function sameManagedData(existing, desired) {
  return JSON.stringify(normalized(pickManaged(existing))) ===
    JSON.stringify(normalized(pickManaged(desired)));
}

function encodeFirestore(value) {
  if (value instanceof admin.firestore.Timestamp) {
    return {$timestamp: value.toDate().toISOString()};
  }
  if (Array.isArray(value)) return value.map(encodeFirestore);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, encodeFirestore(item)]),
    );
  }
  return value;
}

function decodeFirestore(value) {
  if (Array.isArray(value)) return value.map(decodeFirestore);
  if (value && typeof value === 'object') {
    if (Object.keys(value).length === 1 && value.$timestamp) {
      return admin.firestore.Timestamp.fromDate(new Date(value.$timestamp));
    }
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, decodeFirestore(item)]),
    );
  }
  return value;
}

async function validateSemester(logicalTasks) {
  const semesterRef = db.collection('semesters').doc(semesterId);
  const semesterSnapshot = await semesterRef.get();
  invariant(semesterSnapshot.exists, `Missing semester: ${semesterId}`);
  invariant(semesterSnapshot.get('status') === 'active', `${semesterId} is not active.`);
  invariant(semesterSnapshot.get('totalWeeks') === 16, `${semesterId} must have 16 weeks.`);

  const weekSnapshots = await Promise.all(
    Array.from({length: 16}, (_, index) =>
      semesterRef.collection('weeks').doc(weekDocumentId(index + 1)).get()),
  );
  const weekMap = new Map();
  for (const snapshot of weekSnapshots) {
    invariant(snapshot.exists, `Missing week: ${snapshot.ref.path}`);
    const number = snapshot.get('weekNumber');
    invariant(snapshot.get('isPublished') === true, `Week ${number} is not published.`);
    weekMap.set(number, snapshot);
  }

  for (const task of logicalTasks) {
    const weekSnapshot = weekMap.get(task.weekNumber);
    invariant(weekSnapshot, `Missing week ${task.weekNumber}`);
    const start = weekSnapshot.get('startDate').toDate();
    const end = weekSnapshot.get('endDate').toDate();
    const dateInKst = (date) => new Date(date.getTime() + 9 * 60 * 60 * 1000)
      .toISOString().slice(0, 10);
    invariant(dateInKst(start) === task.startDate, `Start date mismatch for week ${task.weekNumber}`);
    invariant(dateInKst(end) === task.endDate, `End date mismatch for week ${task.weekNumber}`);
  }
  return {semesterSnapshot, weekMap};
}

function buildDocuments(logicalTasks) {
  const documents = [];
  const orderByWeek = new Map();
  for (const task of logicalTasks) {
    // Keep the existing operator-managed 10/20/30 ordering intact and append
    // this reviewed guide set in its own deterministic range.
    const nextOrder = (orderByWeek.get(task.weekNumber) || 90) + 10;
    orderByWeek.set(task.weekNumber, nextOrder);
    for (const audience of task.audiences) {
      const ref = db
        .collection('semesters').doc(semesterId)
        .collection('weeks').doc(weekDocumentId(task.weekNumber))
        .collection('tasks').doc(`${task.id}_${audience}`);
      documents.push({
        ref,
        logicalId: task.id,
        weekNumber: task.weekNumber,
        data: {
          sourceTaskId: task.id,
          audience,
          title: task.title,
          description: task.description,
          type: task.type,
          targetAudiences: [audience],
          sortOrder: nextOrder,
          isActive: true,
          actionType: task.actionValue ? 'externalUrl' : 'none',
          actionValue: task.actionValue,
          // Weeks 1-3 are explicitly historical in the reviewed source.
          carryOver: task.type === 'required' && task.weekNumber > 3,
          schemaVersion: 2,
        },
      });
    }
  }
  return documents;
}

async function scanExistingIds(logicalTasks) {
  const expected = new Set(logicalTasks.map((task) => task.id));
  const locations = new Map();
  for (let weekNumber = 1; weekNumber <= 16; weekNumber += 1) {
    const snapshot = await db
      .collection('semesters').doc(semesterId)
      .collection('weeks').doc(weekDocumentId(weekNumber))
      .collection('tasks').get();
    for (const document of snapshot.docs) {
      const data = document.data();
      const sourceTaskId = (data.sourceTaskId || '').toString().trim();
      const matchedId = expected.has(sourceTaskId)
        ? sourceTaskId
        : [...expected].find((id) => document.id === id || document.id.startsWith(`${id}_`));
      if (!matchedId) continue;
      if (!locations.has(matchedId)) locations.set(matchedId, []);
      locations.get(matchedId).push({weekNumber, path: document.ref.path});
    }
  }
  return locations;
}

async function createPlan(logicalTasks, documents) {
  const existingIds = await scanExistingIds(logicalTasks);
  const snapshots = await db.getAll(...documents.map((entry) => entry.ref));
  const plan = [];
  for (let index = 0; index < documents.length; index += 1) {
    const entry = documents[index];
    const snapshot = snapshots[index];
    const locations = existingIds.get(entry.logicalId) || [];
    const wrongWeek = locations.some((location) => location.weekNumber !== entry.weekNumber);
    if (wrongWeek) {
      plan.push({...entry, snapshot, status: 'hold', reason: 'same ID exists in another week'});
    } else if (!snapshot.exists) {
      plan.push({...entry, snapshot, status: 'create'});
    } else if (sameManagedData(snapshot.data(), entry.data)) {
      plan.push({...entry, snapshot, status: 'unchanged'});
    } else {
      plan.push({...entry, snapshot, status: 'hold', reason: 'existing document differs'});
    }
  }
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
  const filePath = path.join(directory, `todo_${semesterId}_${stamp}.json`);
  const backup = {
    projectId,
    semesterId,
    createdAt: new Date().toISOString(),
    documents: plan
      .filter((entry) => entry.status === 'create')
      .map((entry) => ({
        path: entry.ref.path,
        existed: entry.snapshot.exists,
        before: entry.snapshot.exists ? encodeFirestore(entry.snapshot.data()) : null,
        appliedManagedData: entry.data,
      })),
  };
  fs.writeFileSync(filePath, `${JSON.stringify(backup, null, 2)}\n`, {flag: 'wx'});
  return filePath;
}

async function applyCreates(plan) {
  const creates = plan.filter((entry) => entry.status === 'create');
  if (creates.length === 0) return;
  const batch = db.batch();
  for (const entry of creates) {
    batch.create(entry.ref, {
      ...entry.data,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
}

async function verify(documents) {
  const snapshots = await db.getAll(...documents.map((entry) => entry.ref));
  const failures = [];
  for (let index = 0; index < documents.length; index += 1) {
    const entry = documents[index];
    const snapshot = snapshots[index];
    if (!snapshot.exists || !sameManagedData(snapshot.data(), entry.data)) {
      failures.push(entry.ref.path);
    }
  }
  return failures;
}

async function rollback(filePath) {
  invariant(filePath, '--rollback requires a backup path.');
  const absolutePath = path.resolve(process.cwd(), filePath);
  const backup = JSON.parse(fs.readFileSync(absolutePath, 'utf8'));
  invariant(backup.projectId === projectId, 'Backup project mismatch.');
  invariant(backup.semesterId === semesterId, 'Backup semester mismatch.');
  const conflicts = [];
  const batch = db.batch();
  for (const record of backup.documents) {
    const ref = db.doc(record.path);
    const current = await ref.get();
    if (!record.existed) {
      if (!current.exists) continue;
      if (!sameManagedData(current.data(), record.appliedManagedData)) {
        conflicts.push(record.path);
        continue;
      }
      batch.delete(ref);
    } else {
      batch.set(ref, decodeFirestore(record.before), {merge: false});
    }
  }
  invariant(conflicts.length === 0, `Rollback conflicts:\n${conflicts.join('\n')}`);
  await batch.commit();
  console.log(JSON.stringify({rolledBack: backup.documents.length, backup: absolutePath}, null, 2));
}

async function run() {
  if (rollbackIndex >= 0) {
    await rollback(rollbackPath);
    return;
  }

  const logicalTasks = buildLogicalTasks();
  await validateSemester(logicalTasks);
  const documents = buildDocuments(logicalTasks);
  const plan = await createPlan(logicalTasks, documents);
  const summary = summarize(plan);
  console.log(JSON.stringify({
    projectId,
    semesterId,
    sourceLogicalTasks: logicalTasks.length,
    audienceDocuments: documents.length,
    summary,
    entries: plan.map((entry) => ({
      status: entry.status,
      path: entry.ref.path,
      ...(entry.reason ? {reason: entry.reason} : {}),
    })),
  }, null, 2));

  if (!apply) {
    console.log('Dry-run only. Use --apply after reviewing the plan.');
    return;
  }

  const backupPath = writeBackup(plan);
  await applyCreates(plan);
  const failures = await verify(documents);
  invariant(failures.length === 0, `Post-apply verification failed:\n${failures.join('\n')}`);
  console.log(JSON.stringify({applied: summary.create, backupPath, verified: documents.length}, null, 2));
}

run().catch((error) => {
  console.error('Weekly To-do apply failed:', error);
  process.exitCode = 1;
});
