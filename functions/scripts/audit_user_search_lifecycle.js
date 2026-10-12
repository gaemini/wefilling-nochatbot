#!/usr/bin/env node

/*
 * Safe production audit/repair for users + Auth + nicknameClaims.
 *
 * Dry-run is the default. Apply requires both an explicit project and an
 * identical confirmation value:
 *   node scripts/audit_user_search_lifecycle.js --project PROJECT_ID
 *   node scripts/audit_user_search_lifecycle.js --project PROJECT_ID \
 *     --confirm-project PROJECT_ID --apply
 *
 * Output contains only aggregate counts and one-way UID fingerprints.
 */
const crypto = require('crypto');
const admin = require('firebase-admin');
const {normalizeLegacyStoredNickname} = require('../lib/nickname_claims');
const {buildUserSearchTokens} = require('../lib/user_search_index');
const {evaluateSearchableUser} = require('../lib/searchable_user_policy');

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

async function authUsersById(ids) {
  const users = new Map();
  for (let offset = 0; offset < ids.length; offset += 100) {
    const result = await admin.auth().getUsers(
      ids.slice(offset, offset + 100).map((uid) => ({uid})),
    );
    result.users.forEach((user) => users.set(user.uid, user));
  }
  return users;
}

function sameStrings(left, right) {
  return left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

function setIfDifferent(update, data, key, value) {
  const current = data[key];
  const equal = Array.isArray(value)
    ? Array.isArray(current) && sameStrings(current, value)
    : current === value;
  if (!equal) update[key] = value;
}

async function main() {
  const [users, claims] = await Promise.all([
    pagedCollection(db.collection('users')),
    pagedCollection(db.collection('nicknameClaims')),
  ]);
  const authUsers = await authUsersById(users.map((doc) => doc.id));
  const userById = new Map(users.map((doc) => [doc.id, doc]));
  const claimByKey = new Map(claims.map((doc) => [doc.id, doc]));
  const canonicalOwners = new Map();
  for (const document of users) {
    const data = document.data();
    const unavailable = data.isDeleted === true || data.deleted === true ||
      data.deletedAt != null ||
      ['deleted', 'deleting', 'suspended'].includes(
        String(data.status || data.accountStatus || '').trim().toLowerCase(),
      );
    if (unavailable || !authUsers.has(document.id)) continue;
    try {
      const identity = normalizeLegacyStoredNickname(document.get('nickname'));
      const owners = canonicalOwners.get(identity.nicknameKey) || [];
      owners.push(document.id);
      canonicalOwners.set(identity.nicknameKey, owners);
    } catch (_) {
      // Classified by the shared policy below.
    }
  }

  const counts = {
    scannedUsers: users.length,
    authPresent: authUsers.size,
    authMissing: users.length - authUsers.size,
    searchableBeforeRepair: 0,
    searchableAfterRepair: 0,
    deletedOrDisabled: 0,
    incompleteRegistration: 0,
    unnamedOrInvalidNickname: 0,
    nicknameKeyRepair: 0,
    tokenRepair: 0,
    socialEmailVerificationRepair: 0,
    quarantinedMissingAuth: 0,
    quarantinedDirectoryProfile: 0,
    duplicateNicknameKeys: 0,
    scannedClaims: claims.length,
    orphanClaims: 0,
    mismatchedClaims: 0,
    missingClaims: 0,
    appliedUserWrites: 0,
    appliedClaimWrites: 0,
    appliedClaimDeletes: 0,
  };
  const fingerprints = {
    authMissing: [],
    quarantined: [],
    repaired: [],
    orphanClaimOwners: [],
  };
  for (const owners of canonicalOwners.values()) {
    if (owners.length > 1) counts.duplicateNicknameKeys++;
  }

  const userWrites = [];
  const claimWrites = [];
  const claimDeletes = [];
  for (const document of users) {
    const data = document.data();
    const authUser = authUsers.get(document.id);
    const before = evaluateSearchableUser(document.id, data);
    if (before.searchable) counts.searchableBeforeRepair++;
    if (before.reason === 'deleted_or_disabled') counts.deletedOrDisabled++;
    if (before.reason === 'incomplete_registration') {
      counts.incompleteRegistration++;
    }
    if (['missing_nickname', 'sentinel_nickname', 'invalid_nickname',
      'nickname_key_mismatch'].includes(before.reason)) {
      counts.unnamedOrInvalidNickname++;
    }

    const update = {};
    if (!authUser) {
      fingerprints.authMissing.push(uidHash(document.id));
      const alreadyDeleted = before.reason === 'deleted_or_disabled';
      setIfDifferent(update, data, 'searchable', false);
      setIfDifferent(update, data, 'nicknameSearchTokens', []);
      setIfDifferent(update, data, 'interests', []);
      setIfDifferent(update, data, 'preferredActivities', []);
      if (!alreadyDeleted) {
        setIfDifferent(update, data, 'deleting', false);
        setIfDifferent(update, data, 'isDeleted', true);
        setIfDifferent(update, data, 'deleted', true);
        setIfDifferent(update, data, 'status', 'deleted');
        setIfDifferent(update, data, 'registrationStatus', 'deleted');
        if (data.deletedAt == null) {
          update.deletedAt = admin.firestore.FieldValue.serverTimestamp();
        }
        counts.quarantinedMissingAuth++;
      }
    } else {
      const providerIds = authUser.providerData.map((item) => item.providerId);
      const socialVerified = providerIds.includes('google.com') ||
        providerIds.includes('apple.com');
      const registration = String(data.registrationStatus || '').trim();
      if (!registration && data.emailVerified !== true && socialVerified) {
        setIfDifferent(update, data, 'emailVerified', true);
        counts.socialEmailVerificationRepair++;
      }
      let identity = null;
      try {
        identity = normalizeLegacyStoredNickname(data.nickname);
      } catch (_) {
        // A signed-in account without a valid Wefilling ID remains available
        // for onboarding but is quarantined from all people directories.
      }
      if (identity) {
        if (String(data.nicknameKey || '').trim() !== identity.nicknameKey) {
          setIfDifferent(update, data, 'nicknameKey', identity.nicknameKey);
          counts.nicknameKeyRepair++;
        }
        const expectedTokens = buildUserSearchTokens(identity.nickname);
        const currentTokens = Array.isArray(data.nicknameSearchTokens)
          ? data.nicknameSearchTokens.filter((value) => typeof value === 'string')
          : [];
        if (!sameStrings(currentTokens, expectedTokens)) {
          setIfDifferent(
            update,
            data,
            'nicknameSearchTokens',
            expectedTokens,
          );
          counts.tokenRepair++;
        }
        const owners = canonicalOwners.get(identity.nicknameKey) || [];
        const claim = claimByKey.get(identity.nicknameKey);
        if (owners.length === 1 && !claim) {
          counts.missingClaims++;
          claimWrites.push({
            ref: db.collection('nicknameClaims').doc(identity.nicknameKey),
            data: {
              ownerUid: document.id,
              nicknameKey: identity.nicknameKey,
              nickname: identity.nickname,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
          });
        }
      } else {
        setIfDifferent(update, data, 'searchable', false);
        setIfDifferent(update, data, 'nicknameSearchTokens', []);
        if (Object.keys(update).length > 0) {
          counts.quarantinedDirectoryProfile++;
        }
      }
    }
    if (Object.keys(update).length > 0) {
      update.searchLifecycleAuditedAt =
        admin.firestore.FieldValue.serverTimestamp();
      userWrites.push({ref: document.ref, data: update});
      fingerprints.repaired.push(uidHash(document.id));
    }
  }

  for (const claim of claims) {
    const ownerUid = String(claim.get('ownerUid') || '').trim();
    const owner = userById.get(ownerUid);
    if (!owner || !authUsers.has(ownerUid)) {
      counts.orphanClaims++;
      fingerprints.orphanClaimOwners.push(uidHash(ownerUid || claim.id));
      claimDeletes.push(claim.ref);
      continue;
    }
    let expectedKey = '';
    try {
      expectedKey = normalizeLegacyStoredNickname(owner.get('nickname')).nicknameKey;
    } catch (_) {
      // Invalid owner identity cannot retain a public nickname claim.
    }
    if (!expectedKey || expectedKey !== claim.id) {
      counts.mismatchedClaims++;
      claimDeletes.push(claim.ref);
    }
  }

  if (apply) {
    for (let offset = 0; offset < userWrites.length; offset += 100) {
      const batch = db.batch();
      userWrites.slice(offset, offset + 100)
        .forEach((write) => batch.update(write.ref, write.data));
      await batch.commit();
      counts.appliedUserWrites +=
        userWrites.slice(offset, offset + 100).length;
    }
    for (let offset = 0; offset < claimWrites.length; offset += 300) {
      const batch = db.batch();
      claimWrites.slice(offset, offset + 300)
        .forEach((write) => batch.create(write.ref, write.data));
      await batch.commit();
      counts.appliedClaimWrites +=
        claimWrites.slice(offset, offset + 300).length;
    }
    for (let offset = 0; offset < claimDeletes.length; offset += 300) {
      const batch = db.batch();
      claimDeletes.slice(offset, offset + 300)
        .forEach((ref) => batch.delete(ref));
      await batch.commit();
      counts.appliedClaimDeletes +=
        claimDeletes.slice(offset, offset + 300).length;
    }
  }

  // Predict the post-repair directory without printing any profile data.
  for (const document of users) {
    const pending = userWrites.find((write) => write.ref.path === document.ref.path);
    const projected = pending ? {...document.data(), ...pending.data} : document.data();
    // Server timestamps are irrelevant to policy evaluation.
    if (evaluateSearchableUser(document.id, projected).searchable &&
        authUsers.has(document.id)) {
      counts.searchableAfterRepair++;
    }
  }
  process.stdout.write(`${JSON.stringify({
    mode: apply ? 'apply' : 'dry-run',
    projectId,
    counts,
    fingerprints,
  }, null, 2)}\n`);
}

main().catch((error) => {
  console.error(error && error.message ? error.message : 'audit failed');
  process.exitCode = 1;
});
