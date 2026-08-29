#!/usr/bin/env node

/*
 * One-time admin reconciliation for users/{uid}.friendsCount.
 * It is never imported by the app or Cloud Functions runtime.
 *
 * Dry run (default): npm run migrate:friend-counts
 * Apply after reviewing output: npm run migrate:friend-counts -- --apply
 */
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();
const apply = process.argv.includes('--apply');

function isActiveUser(data) {
  return data.isDeleted !== true &&
    data.deleted !== true &&
    data.registrationStatus !== 'deleted';
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

  const counts = new Map(
    Array.from(activeUsers.keys(), (uid) => [uid, 0]),
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
    counts.set(uids[0], counts.get(uids[0]) + 1);
    counts.set(uids[1], counts.get(uids[1]) + 1);
  }

  const changes = [];
  for (const [uid, expectedCount] of counts.entries()) {
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
  }

  process.stdout.write(`${JSON.stringify({
    mode: apply ? 'apply' : 'dry-run',
    scannedUsers: usersSnapshot.size,
    activeUsers: activeUsers.size,
    scannedFriendships: friendshipsSnapshot.size,
    changedUsers: changes.length,
    changes,
    invalidFriendships,
  }, null, 2)}\n`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
