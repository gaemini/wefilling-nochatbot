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
const after = argument('--after');
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
  const repairFingerprints = [];
  let cursor = after;
  let scannedUsers = 0;
  let searchableUsers = 0;
  let obsoleteTokens = 0;
  let missingTokens = 0;

  let appliedRepairs = 0;
  let skippedChangedUsers = 0;
  let alreadyCurrentAtApply = 0;
  let missingAtApply = 0;
  let pendingRepairs = 0;
  while (true) {
    let query = db.collection('users')
      .orderBy(admin.firestore.FieldPath.documentId()).limit(100);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    if (snapshot.empty) break;
    scannedUsers += snapshot.size;
    const repairs = [];
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
      uidFingerprint: uidHash(document.id),
    });
    repairFingerprints.push(uidHash(document.id));
    }
    pendingRepairs += repairs.length;
    if (apply) {
    // Each write re-reads and re-evaluates the latest profile in a transaction.
    // A nickname/privacy change after the dry-run scan can therefore never be
    // overwritten with tokens calculated from the stale snapshot.
    for (let offset = 0; offset < repairs.length; offset += 20) {
      const outcomes = await Promise.all(
        repairs.slice(offset, offset + 20).map((repair) =>
          db.runTransaction(async (transaction) => {
            const latestSnapshot = await transaction.get(repair.ref);
            if (!latestSnapshot.exists) return 'missing';
            const latestData = latestSnapshot.data() || {};
            if (!evaluateSearchableUser(
              latestSnapshot.id,
              latestData,
            ).searchable) {
              return 'changed';
            }

            let latestNickname;
            try {
              latestNickname = normalizeLegacyStoredNickname(
                latestData.nickname,
              ).nickname;
            } catch (_) {
              return 'changed';
            }
            const latestExpected = buildUserSearchTokens(latestNickname);
            const latestCurrent = Array.isArray(
              latestData.nicknameSearchTokens,
            ) ? latestData.nicknameSearchTokens.filter(
                (value) => typeof value === 'string',
              ) : [];
            if (sameStrings(latestCurrent, latestExpected)) return 'current';

            // A normal array replaces only the derived token field.
            transaction.update(repair.ref, {
              nicknameSearchTokens: latestExpected,
            });
            return 'updated';
          }),
        ),
      );
      outcomes.forEach((outcome) => {
        if (outcome === 'updated') appliedRepairs++;
        if (outcome === 'changed') skippedChangedUsers++;
        if (outcome === 'current') alreadyCurrentAtApply++;
        if (outcome === 'missing') missingAtApply++;
      });
    }
    }
    cursor = snapshot.docs[snapshot.docs.length - 1].id;
    process.stderr.write(`${JSON.stringify({mode: apply ? 'apply' : 'dry-run',
      scannedUsers, appliedRepairs, resumeAfter: cursor})}\n`);
    if (snapshot.size < 100) break;
  }

  process.stdout.write(`${JSON.stringify({
    mode: apply ? 'apply' : 'dry-run',
    projectId,
    scannedUsers,
    startedAfter: after || null,
    lastCursor: cursor || null,
    searchableUsers,
    repairedUsers: appliedRepairs,
    pendingRepairs: apply ? 0 : pendingRepairs,
    skippedChangedUsers,
    alreadyCurrentAtApply,
    missingAtApply,
    obsoleteTokens,
    missingTokens,
    uidFingerprints: repairFingerprints,
  }, null, 2)}\n`);
}

main().catch((error) => {
  console.error(error && error.message ? error.message : 'repair failed');
  process.exitCode = 1;
});
