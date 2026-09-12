#!/usr/bin/env node

/*
 * Narrow repair for nicknameSearchTokens only.
 *
 * Dry-run is the default. Apply requires both an explicit project and an
 * identical confirmation value:
 *   npm run repair:nickname-search-tokens -- --project PROJECT_ID
 *   npm run repair:nickname-search-tokens -- --project PROJECT_ID \
 *     --confirm-project PROJECT_ID --apply
 *
 * No nickname or raw UID is printed. This script deliberately does not touch
 * nickname claims, registration state, searchability, or any profile field.
 */
const crypto = require('crypto');
const admin = require('firebase-admin');
const {normalizeLegacyStoredNickname} = require('../lib/nickname_claims');
const {evaluateSearchableUser} = require('../lib/searchable_user_policy');
const {buildUserSearchTokens} = require('../lib/user_search_index');

function argument(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? String(process.argv[index + 1] || '').trim() : '';
}

const projectId = argument('--project');
const confirmedProjectId = argument('--confirm-project');
const apply = process.argv.includes('--apply');
if (!projectId || projectId.includes('/') || projectId.length > 100) {
  throw new Error('--project with an exact Firebase project ID is required');
}
if (apply && confirmedProjectId !== projectId) {
  throw new Error('--apply requires matching --confirm-project');
}

admin.initializeApp({projectId});
const db = admin.firestore();
const uidHash = (uid) => crypto.createHash('sha256')
  .update(`${projectId}:${uid}`).digest('hex').slice(0, 12);

function sameStrings(left, right) {
  return left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

async function main() {
  const snapshot = await db.collection('users').get();
  const repairs = [];
  let searchableUsers = 0;
  let obsoleteTokens = 0;
  let missingTokens = 0;

  for (const document of snapshot.docs) {
    const data = document.data();
    if (!evaluateSearchableUser(document.id, data).searchable) continue;
    searchableUsers++;

    let nickname;
    try {
      nickname = normalizeLegacyStoredNickname(data.nickname).nickname;
    } catch (_) {
      continue;
    }
    const expected = buildUserSearchTokens(nickname);
    const current = Array.isArray(data.nicknameSearchTokens)
      ? data.nicknameSearchTokens.filter((value) => typeof value === 'string')
      : [];
    if (sameStrings(current, expected)) continue;

    const currentSet = new Set(current);
    const expectedSet = new Set(expected);
    obsoleteTokens += current.filter((value) => !expectedSet.has(value)).length;
    missingTokens += expected.filter((value) => !currentSet.has(value)).length;
    repairs.push({
      ref: document.ref,
      tokens: expected,
      uidFingerprint: uidHash(document.id),
    });
  }

  if (apply) {
    for (let offset = 0; offset < repairs.length; offset += 300) {
      const batch = db.batch();
      repairs.slice(offset, offset + 300).forEach((repair) => {
        // A normal array value replaces the field. FieldValue.arrayUnion is
        // intentionally never used here.
        batch.update(repair.ref, {nicknameSearchTokens: repair.tokens});
      });
      await batch.commit();
    }
  }

  process.stdout.write(`${JSON.stringify({
    mode: apply ? 'apply' : 'dry-run',
    projectId,
    scannedUsers: snapshot.size,
    searchableUsers,
    repairedUsers: apply ? repairs.length : 0,
    pendingRepairs: apply ? 0 : repairs.length,
    obsoleteTokens,
    missingTokens,
    uidFingerprints: repairs.map((repair) => repair.uidFingerprint),
  }, null, 2)}\n`);
}

main().catch((error) => {
  console.error(error && error.message ? error.message : 'repair failed');
  process.exitCode = 1;
});
