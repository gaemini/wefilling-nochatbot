#!/usr/bin/env node

/*
 * One-time admin reconciliation for users/{uid}.friendsCount and orphaned
 * friendship cleanup. A friendship whose participant profile is missing or
 * inactive cannot appear in the app and must not inflate either counter.
 * It is never imported by the app or Cloud Functions runtime.
 *
 * Dry run (default): npm run migrate:friend-counts
 * Apply after reviewing output: npm run migrate:friend-counts -- --apply
 */
const admin = require('firebase-admin');
const {isSearchableUser} = require('../lib/searchable_user_policy');

admin.initializeApp();
const db = admin.firestore();
const apply = process.argv.includes('--apply');

function isActiveUser(data) {
  const status = String(data.status || data.accountStatus || '')
    .trim().toLowerCase();
  const registrationStatus = String(data.registrationStatus || '')
    .trim().toLowerCase();
  return data.isDeleted !== true &&
    data.deleted !== true &&
    data.deleting !== true &&
    data.deletedAt == null &&
    status !== 'deleted' &&
    registrationStatus !== 'deleted' &&
    registrationStatus !== 'deleting';
}

async function main() {
  const [usersSnapshot, friendshipsSnapshot] = await Promise.all([
    db.collection('users').get(),
    db.collection('friendships').get(),
  ]);

  const activeUsers = new Map();
  for (const userDoc of usersSnapshot.docs) {
    const data = userDoc.data();
    if (!isActiveUser(data)) continue;
    activeUsers.set(userDoc.id, data);
  }

  const visibleUsers = new Set(
    Array.from(activeUsers.entries())
      .filter(([uid, data]) => isSearchableUser(uid, data))
      .map(([uid]) => uid),
  );
  const friendIdsByOwner = new Map(
    Array.from(activeUsers.keys(), (uid) => [uid, new Set()]),
  );
  const invalidFriendships = [];

  for (const friendshipDoc of friendshipsSnapshot.docs) {
    const uids = friendshipDoc.get('uids');
    if (!Array.isArray(uids) || uids.length !== 2 ||
        typeof uids[0] !== 'string' || typeof uids[1] !== 'string' ||
        uids[0] === uids[1] ||
        !activeUsers.has(uids[0]) || !activeUsers.has(uids[1])) {
      invalidFriendships.push({id: friendshipDoc.id, uids});
      continue;
    }
    // 친구 목록은 상대 프로필이 실제 노출 가능한 경우에만 행을 만든다.
    // Set을 사용해 레거시 중복 관계 문서도 숫자를 부풀리지 않게 한다.
    if (visibleUsers.has(uids[1])) friendIdsByOwner.get(uids[0]).add(uids[1]);
    if (visibleUsers.has(uids[0])) friendIdsByOwner.get(uids[1]).add(uids[0]);
  }

  const changes = [];
  for (const [uid, friendIds] of friendIdsByOwner.entries()) {
    const expectedCount = friendIds.size;
    const currentValue = activeUsers.get(uid).friendsCount;
    const currentCount = typeof currentValue === 'number'
      ? Math.max(0, Math.trunc(currentValue))
      : null;
    if (currentCount !== expectedCount) {
      changes.push({uid, from: currentCount, to: expectedCount});
    }
  }

  if (apply) {
    for (let offset = 0; offset < changes.length; offset += 400) {
      const batch = db.batch();
      for (const change of changes.slice(offset, offset + 400)) {
        batch.update(db.collection('users').doc(change.uid), {
          friendsCount: change.to,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    for (let offset = 0; offset < invalidFriendships.length; offset += 400) {
      const batch = db.batch();
      for (const invalid of invalidFriendships.slice(offset, offset + 400)) {
        batch.delete(db.collection('friendships').doc(invalid.id));
      }
      await batch.commit();
    }
  }

  process.stdout.write(`${JSON.stringify({
    mode: apply ? 'apply' : 'dry-run',
    scannedUsers: usersSnapshot.size,
    activeUsers: activeUsers.size,
    visibleUsers: visibleUsers.size,
    scannedFriendships: friendshipsSnapshot.size,
    changedUsers: changes.length,
    deletedInvalidFriendships: apply ? invalidFriendships.length : 0,
    changes,
    invalidFriendships,
  }, null, 2)}\n`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
