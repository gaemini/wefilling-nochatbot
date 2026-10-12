#!/usr/bin/env node
// LOCAL ONLY: verify own reactions without writing a self-notification.
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

const host = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) {
  throw new Error('Local Firestore emulator required');
}

const projectId = 'demo-snapshot-reactions';
admin.initializeApp({projectId});
const db = admin.firestore();
const ft = require('firebase-functions-test')();
const snapshot = require('../lib/snapshot');
const status = ft.wrap(snapshot.getSnapshotReactionStatus);
const react = ft.wrap(snapshot.toggleSnapshotReaction);
const context = (uid) => ({auth: {uid, token: {}}});
const ownerId = 'snapshot-owner';
const viewerId = 'snapshot-viewer';
const snapshotId = '11111111-1111-4111-8111-111111111111';
const ref = db.collection('snapshots').doc(snapshotId);

async function main() {
  await db.collection('users').doc(ownerId).set({nickname: 'Owner'});
  await db.collection('users').doc(viewerId).set({nickname: 'Viewer'});
  await ref.set({
    ownerId,
    status: 'active',
    visibility: 'public',
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 3600000),
    reactionCounts: {},
  });

  assert.equal((await status({snapshotId}, context(ownerId))).reacted, false);
  assert.equal((await react({snapshotId, reaction: '❤️'}, context(ownerId))).created, true);
  assert.equal((await status({snapshotId}, context(ownerId))).reacted, true);
  assert.equal((await ref.get()).get('reactionCounts.❤️'), 1);
  assert.equal((await db.collection('notifications').get()).size, 0);

  assert.equal((await react({snapshotId, reaction: '❤️'}, context(ownerId))).created, false);
  assert.equal((await ref.get()).get('reactionCounts.❤️'), 1);

  assert.equal((await status({snapshotId}, context(viewerId))).reacted, false);
  assert.equal((await react({snapshotId, reaction: '❤️'}, context(viewerId))).created, true);
  assert.equal((await ref.get()).get('reactionCounts.❤️'), 2);
  const notifications = await db.collection('notifications').get();
  assert.equal(notifications.size, 1);
  assert.equal(notifications.docs[0].get('userId'), ownerId);
  console.log('snapshot own/other reaction emulator checks passed');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}).finally(async () => {
  ft.cleanup();
  await admin.app().delete();
});
