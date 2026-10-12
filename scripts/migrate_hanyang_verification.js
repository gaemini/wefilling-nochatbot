#!/usr/bin/env node

const admin = require('firebase-admin');

const EXPECTED_PROJECT = 'flutterproject3-af322';
const apply = process.argv.includes('--apply');
const projectArg = process.argv.find((arg) => arg.startsWith('--project='));
const projectId = projectArg ? projectArg.slice('--project='.length) : EXPECTED_PROJECT;

if (projectId !== EXPECTED_PROJECT) {
  throw new Error(`Unexpected project: ${projectId}`);
}

admin.initializeApp({projectId});
const db = admin.firestore();

function normalized(value) {
  return String(value || '').trim().toLowerCase();
}

function validHanyangEmail(value) {
  return /^[^\s@]+@hanyang\.ac\.kr$/.test(normalized(value));
}

function deleted(data) {
  return data.isDeleted === true ||
    data.deleted === true ||
    data.disabled === true ||
    data.isSuspended === true ||
    data.deletedAt != null ||
    ['deleted', 'suspended'].includes(String(data.status || '')) ||
    ['deleted', 'suspended'].includes(String(data.accountStatus || '')) ||
    data.registrationStatus === 'deleted';
}

async function main() {
  const users = await db.collection('users').get();
  const candidates = users.docs.filter((doc) => {
    const data = doc.data();
    return !deleted(data) && validHanyangEmail(data.hanyangEmail);
  });
  const repairs = candidates.filter((doc) => {
    const data = doc.data();
    return data.hanyangEmailVerified !== true ||
      data.schoolVerificationSchemaVersion !== 3;
  });

  console.log(JSON.stringify({
    projectId,
    mode: apply ? 'apply' : 'dry-run',
    scanned: users.size,
    validHanyangUsers: candidates.length,
    needsRepair: repairs.length,
  }, null, 2));

  if (!apply || repairs.length === 0) return;

  const writer = db.bulkWriter();
  let completed = 0;
  let failed = 0;
  writer.onWriteResult(() => completed++);
  writer.onWriteError((error) => {
    failed++;
    console.error('Write failed', error.documentRef.path, error.code);
    return error.failedAttempts < 3;
  });

  for (const doc of repairs) {
    const data = doc.data();
    writer.update(doc.ref, {
      hanyangEmail: normalized(data.hanyangEmail),
      hanyangEmailVerified: true,
      ...(data.hanyangEmailVerifiedAt == null
        ? {hanyangEmailVerifiedAt: admin.firestore.FieldValue.serverTimestamp()}
        : {}),
      schoolVerificationMethod: String(data.schoolVerificationMethod || '').trim() ||
        'legacy_hanyang_email',
      schoolVerificationSchemaVersion: 3,
      schoolVerificationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await writer.close();
  console.log(JSON.stringify({completed, failed}, null, 2));
  if (failed > 0) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
