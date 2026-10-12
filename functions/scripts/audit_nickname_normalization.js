#!/usr/bin/env node

/*
 * Read-only production audit for the nickname policy v2 rollout.
 * This script has no apply mode and performs no writes.
 *
 *   npm run audit:nickname-normalization -- --project PROJECT_ID
 */
const admin = require('firebase-admin');
const {
  normalizeLegacyStoredNickname,
  normalizeNickname,
} = require('../lib/nickname_claims');
const {buildUserSearchTokens} = require('../lib/user_search_index');

function argument(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? String(process.argv[index + 1] || '').trim() : '';
}

const projectId = argument('--project');
if (!projectId || projectId.includes('/') || projectId.length > 100) {
  throw new Error('--project with an exact Firebase project ID is required');
}

admin.initializeApp({projectId});
const db = admin.firestore();

async function pagedCollection(collection) {
  const documents = [];
  let cursor = null;
  while (true) {
    let query = collection
      .orderBy(admin.firestore.FieldPath.documentId()).limit(100);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    documents.push(...page.docs);
    if (page.size < 100) break;
    cursor = page.docs[page.docs.length - 1].id;
  }
  return documents;
}

async function authUserIds(ids) {
  const found = new Set();
  for (let offset = 0; offset < ids.length; offset += 100) {
    const result = await admin.auth().getUsers(
      ids.slice(offset, offset + 100).map((uid) => ({uid})),
    );
    result.users.forEach((user) => found.add(user.uid));
  }
  return found;
}

function isUnavailable(data) {
  const status = String(data.status || data.accountStatus || '')
    .trim().toLowerCase();
  const registration = String(data.registrationStatus || '')
    .trim().toLowerCase();
  return data.isDeleted === true || data.deleted === true ||
    data.disabled === true || data.isSuspended === true ||
    data.deleting === true || data.deletedAt != null ||
    ['deleted', 'deleting', 'disabled', 'suspended'].includes(status) ||
    ['deleted', 'deleting'].includes(registration);
}

function isComplete(data) {
  const registration = String(data.registrationStatus || '')
    .trim().toLowerCase();
  const signupState = String(data.signupState || '').trim().toLowerCase();
  return registration === 'complete' ||
    (registration === '' && data.emailVerified === true &&
      signupState !== 'authcreated' && signupState !== 'profilepending');
}

function sameStrings(left, right) {
  return left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

async function main() {
  const [users, claims] = await Promise.all([
    pagedCollection(db.collection('users')),
    pagedCollection(db.collection('nicknameClaims')),
  ]);
  const authIds = await authUserIds(users.map((document) => document.id));
  const userById = new Map(users.map((document) => [document.id, document]));
  const claimByKey = new Map(claims.map((document) => [document.id, document]));
  const targetOwners = new Map();
  const candidates = [];

  const counts = {
    scannedUsers: users.length,
    activeCompletedUsers: 0,
    whitespaceNicknames: 0,
    convertibleWhitespaceNicknames: 0,
    collisionKeys: 0,
    collisionUsers: 0,
    invalidLegacyNicknames: 0,
    missingClaims: 0,
    scannedClaims: claims.length,
    orphanClaims: 0,
    mismatchedClaims: 0,
    searchIndexMismatches: 0,
    excludedDeletedOrSuspended: 0,
    excludedIncomplete: 0,
    excludedMissingAuth: 0,
    excludedEmptyShells: 0,
    actualAppliedUsers: 0,
  };

  for (const document of users) {
    const data = document.data();
    const nickname = String(data.nickname || '').trim();
    if (isUnavailable(data)) {
      counts.excludedDeletedOrSuspended++;
      continue;
    }
    if (!authIds.has(document.id)) {
      counts.excludedMissingAuth++;
      continue;
    }
    if (!isComplete(data)) {
      if (!nickname) counts.excludedEmptyShells++;
      else counts.excludedIncomplete++;
      continue;
    }
    if (!nickname) {
      counts.excludedEmptyShells++;
      continue;
    }

    counts.activeCompletedUsers++;
    let currentIdentity = null;
    try {
      currentIdentity = normalizeLegacyStoredNickname(nickname);
    } catch (_) {
      // Strict normalization below may still make a whitespace nickname valid.
    }
    let targetIdentity = null;
    try {
      targetIdentity = normalizeNickname(nickname);
    } catch (_) {
      counts.invalidLegacyNicknames++;
    }
    const hasWhitespace = /\s/u.test(nickname);
    if (hasWhitespace) {
      counts.whitespaceNicknames++;
      if (targetIdentity) {
        counts.convertibleWhitespaceNicknames++;
        candidates.push({uid: document.id, targetIdentity});
      }
    }
    const groupingIdentity = targetIdentity || currentIdentity;
    if (groupingIdentity) {
      const owners = targetOwners.get(groupingIdentity.nicknameKey) || [];
      owners.push(document.id);
      targetOwners.set(groupingIdentity.nicknameKey, owners);
    }

    const storedKey = String(data.nicknameKey || '').trim();
    const expectedCurrentKey = storedKey || currentIdentity?.nicknameKey || '';
    const claim = expectedCurrentKey ? claimByKey.get(expectedCurrentKey) : null;
    if (!claim) counts.missingClaims++;
    else if (String(claim.get('ownerUid') || '') !== document.id) {
      counts.mismatchedClaims++;
    }

    const indexedNickname = targetIdentity?.nickname || currentIdentity?.nickname;
    if (indexedNickname) {
      const expectedTokens = buildUserSearchTokens(indexedNickname);
      const currentTokens = Array.isArray(data.nicknameSearchTokens)
        ? data.nicknameSearchTokens.filter((value) => typeof value === 'string')
        : [];
      if (!sameStrings(currentTokens, expectedTokens)) {
        counts.searchIndexMismatches++;
      }
    }
  }

  const candidateIds = new Set(candidates.map((candidate) => candidate.uid));
  for (const owners of targetOwners.values()) {
    if (owners.length < 2 || !owners.some((uid) => candidateIds.has(uid))) {
      continue;
    }
    counts.collisionKeys++;
    counts.collisionUsers += owners.length;
  }

  for (const claim of claims) {
    const ownerUid = String(claim.get('ownerUid') || '').trim();
    const owner = userById.get(ownerUid);
    if (!owner || !authIds.has(ownerUid) || isUnavailable(owner.data())) {
      counts.orphanClaims++;
      continue;
    }
    const storedKey = String(owner.get('nicknameKey') || '').trim();
    if (storedKey && storedKey !== claim.id &&
        String(claim.get('nicknameKey') || claim.id) !== storedKey) {
      counts.mismatchedClaims++;
    }
  }

  process.stdout.write(`${JSON.stringify({
    mode: 'dry-run',
    projectId,
    nicknamePolicyVersion: 2,
    counts,
    note: 'Read-only audit. No user, claim, or search data was changed.',
  }, null, 2)}\n`);
}

main().catch((error) => {
  console.error(error && error.message ? error.message : 'audit failed');
  process.exitCode = 1;
});
