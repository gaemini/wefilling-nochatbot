#!/usr/bin/env node

/*
 * One-time admin migration. It is intentionally never imported by the app or
 * Cloud Functions runtime. Run `npm run build` first, then use dry-run output
 * before applying:
 *   npm run migrate:nicknames
 *   npm run migrate:nicknames -- --apply
 */
const admin = require('firebase-admin');
const {normalizeNickname} = require('../lib/nickname_claims');
const {buildUserSearchTokens} = require('../lib/user_search_index');

admin.initializeApp();
const db = admin.firestore();
const apply = process.argv.includes('--apply');

async function main() {
  const users = await db.collection('users').get();
  const grouped = new Map();
  const invalid = [];
  const searchable = [];

  const isUnavailable = (data) => {
    const status = String(data.status || data.accountStatus || '')
      .trim().toLowerCase();
    const registrationStatus = String(data.registrationStatus || '')
      .trim().toLowerCase();
    return data.isDeleted === true || data.deleted === true ||
      data.disabled === true || data.isSuspended === true ||
      data.deletedAt != null || status === 'deleted' ||
      status === 'suspended' || registrationStatus === 'deleted';
  };

  for (const doc of users.docs) {
    const data = doc.data();
    if (isUnavailable(data)) continue;
    const displayName = String(data.nickname || data.displayName || '').trim();
    if (displayName) {
      searchable.push({
        uid: doc.id,
        tokens: buildUserSearchTokens(displayName),
      });
    }
    try {
      const identity = normalizeNickname(data.nickname);
      const entries = grouped.get(identity.nicknameKey) || [];
      entries.push({uid: doc.id, nickname: identity.nickname});
      grouped.set(identity.nicknameKey, entries);
    } catch (_) {
      invalid.push({uid: doc.id, nickname: String(data.nickname || '')});
    }
  }

  const conflicts = [];
  const unique = [];
  for (const [nicknameKey, entries] of grouped.entries()) {
    if (entries.length !== 1) {
      conflicts.push({nicknameKey, users: entries});
    } else {
      unique.push({nicknameKey, ...entries[0]});
    }
  }

  // Never reserve a key involved in a normalized collision. Existing claims
  // that disagree with the unique UID are reported and never overwritten.
  const writable = [];
  for (const entry of unique) {
    const claim = await db.collection('nicknameClaims')
      .doc(entry.nicknameKey)
      .get();
    if (claim.exists && claim.get('ownerUid') !== entry.uid) {
      const ownerUid = String(claim.get('ownerUid') || '');
      const owner = ownerUid
        ? await db.collection('users').doc(ownerUid).get()
        : null;
      if (owner?.exists && !isUnavailable(owner.data() || {})) {
        conflicts.push({
          nicknameKey: entry.nicknameKey,
          users: [entry],
          existingClaimOwnerUid: ownerUid,
        });
        continue;
      }
    }
    writable.push(entry);
  }

  if (apply) {
    // Search token arrays are larger than claim documents. Keep each commit
    // comfortably below the Firestore request-size limit.
    for (let offset = 0; offset < searchable.length; offset += 25) {
      const batch = db.batch();
      for (const entry of searchable.slice(offset, offset + 25)) {
        batch.set(db.collection('users').doc(entry.uid), {
          nicknameSearchTokens: entry.tokens,
        }, {merge: true});
      }
      await batch.commit();
    }
    for (let offset = 0; offset < writable.length; offset += 400) {
      const batch = db.batch();
      for (const entry of writable.slice(offset, offset + 400)) {
        const claimRef = db.collection('nicknameClaims').doc(entry.nicknameKey);
        const userRef = db.collection('users').doc(entry.uid);
        batch.set(claimRef, {
          ownerUid: entry.uid,
          nicknameKey: entry.nicknameKey,
          nickname: entry.nickname,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        batch.set(userRef, {
          nickname: entry.nickname,
          nicknameKey: entry.nicknameKey,
        }, {merge: true});
      }
      await batch.commit();
    }
  }

  process.stdout.write(`${JSON.stringify({
    mode: apply ? 'apply' : 'dry-run',
    scannedUsers: users.size,
    searchableProfiles: searchable.length,
    writableClaims: writable.length,
    conflicts,
    invalid,
  }, null, 2)}\n`);
  if (conflicts.length > 0) process.exitCode = 2;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
