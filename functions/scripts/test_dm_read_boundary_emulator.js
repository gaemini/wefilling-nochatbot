#!/usr/bin/env node
// Local-only: real transactions and production callable/trigger handlers.
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || '')) {
  throw Error('Local Firestore emulator required');
}
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: 'demo-chat-delivery'});
const index = require('../lib/index');
const dm = require('../lib/dm_chat');
const policy = require('../lib/dm_read_policy');
const ft = require('firebase-functions-test')();
const db = admin.firestore();
const run = Date.now();
const alice = `boundaryAlice${run}`;
const bob = `boundaryBob${run}`;
const room = db.collection('conversations').doc(`boundary-A-${run}`);
const other = db.collection('conversations').doc(`boundary-B-${run}`);
const user = db.collection('users').doc(bob);
const create = ft.wrap(index.onDMMessageCreated);
const read = ft.wrap(index.onDMMessageRead);
const mark = ft.wrap(dm.markDMConversationReadBoundedSecure);
const cleanup = ft.wrap(dm.onDMReceiptCleanupRequested);
const context = (id, kind) => ({eventId: `boundary-${run}-${id}-${kind}`,
  params: {conversationId: room.id, messageId: id}});
async function send(id, counted = true) {
  const ref = room.collection('messages').doc(id);
  await ref.set({senderId: alice, text: id, isRead: false,
    // Old client's wildly wrong clock must not determine the read boundary.
    createdAt: admin.firestore.Timestamp.fromMillis(id === 'old' ? 9999999999999 : 1)});
  const snap = await ref.get();
  if (counted) await create(snap, context(id, 'create'));
  return ref.get();
}
async function flush(target) {
  const before = await room.get();
  const result = await mark({conversationId: room.id, throughMessageId: target,
    deferReceipts: true}, {auth: {uid: bob, token: {}}});
  const after = await room.get();
  return {before, after, result};
}
async function counts(a, total) {
  assert.equal((await room.get()).get(`unreadCount.${bob}`), a);
  assert.equal((await user.get()).get('dmUnreadTotal'), total);
  assert.equal((await other.get()).get(`unreadCount.${bob}`), 7);
}
async function main() {
  await db.collection('users').doc(alice).set({nickname: alice});
  await user.set({nickname: bob, dmUnreadTotal: 7});
  await room.set({participants: [alice, bob], unreadCount: {[bob]: 0}});
  await other.set({participants: [alice, bob], unreadCount: {[bob]: 7}});
  const late = await send('late-create', false);
  const old = await send('old');
  assert(old.get('receiptCreatedAt').isEqual(old.createTime));
  const newer = await send('newer');
  await counts(2, 9);
  const first = await flush('old');
  assert.equal(first.result.boundedRead, true);
  assert.equal(first.result.readThroughAtSeconds, old.createTime.seconds);
  assert.equal(first.result.readThroughAtNanos, old.createTime.nanoseconds);
  assert(first.after.get(`lastReadAtBy.${bob}`).isEqual(old.createTime));
  assert.equal((await old.ref.get()).get('isRead'), false); // deliberately delay worker
  await counts(2, 9); // newer boundary cannot be cleared by old request
  await cleanup(first);
  const oldRead = await old.ref.get();
  assert.equal(oldRead.get('isRead'), true);
  assert.equal((await newer.ref.get()).get('isRead'), false);
  await read({before: old, after: oldRead}, context('old', 'read'));
  await read({before: old, after: oldRead}, context('old', 'read'));
  await counts(1, 8);
  // Creation arriving after the read watermark cannot resurrect count or push.
  await create(late, context('late-create', 'create'));
  await counts(1, 8);
  // A second room update never changes A's watermark/counter.
  const second = await flush('newer');
  await counts(0, 7);
  const afterExit = await send('after-exit');
  await counts(1, 8);
  await cleanup(second);
  await read({before: newer, after: await newer.ref.get()}, context('newer', 'read'));
  await counts(1, 8); // old receipt must not subtract after-exit
  await flush('old'); // late older request cannot move watermark backward
  assert((await room.get()).get(`lastReadAtBy.${bob}`).isEqual(newer.createTime));
  assert.equal((await afterExit.ref.get()).get('isRead'), false);
  await counts(1, 8);
  await assert.rejects(mark({conversationId: room.id, throughMessageId: 'absent'},
    {auth: {uid: bob, token: {}}}));
  await assert.rejects(mark({conversationId: room.id, throughMessageId: 'old'},
    {auth: {uid: 'outsider', token: {}}}));
  await assert.rejects(mark({conversationId: room.id, throughMessageId: 'old',
    readerId: alice}, {auth: {uid: bob, token: {}}}));
  // Rolling deployment: a nonzero old counter has no trusted upper bound.
  await room.update({lastUnreadCreatedAtBy: admin.firestore.FieldValue.delete()});
  await afterExit.ref.update({receiptCreatedAt: admin.firestore.FieldValue.delete(),
    unreadCountedFor: admin.firestore.FieldValue.delete()});
  const legacyBefore = await afterExit.ref.get();
  const rollingNew = await send('rolling-new');
  assert.equal((await room.get()).get(`lastUnreadCreatedAtBy.${bob}`), undefined);
  const legacyFlush = await flush('after-exit');
  await counts(2, 9);
  await cleanup(legacyFlush);
  await read({before: legacyBefore, after: await afterExit.ref.get()},
    context('after-exit', 'legacy-read'));
  await counts(1, 8);
  assert.equal((await rollingNew.ref.get()).get('isRead'), false);
  const t = new admin.firestore.Timestamp(100, 123456000);
  assert(policy.dmCovered(t, t));
  assert(!policy.dmCovered(new admin.firestore.Timestamp(100, 123457000), t));
  assert(policy.dmNotificationBoundary(t) < Math.floor(t.toMillis()));
  const futureToken = new admin.firestore.Timestamp(9999999999, 999999999);
  assert(policy.dmTimeCompare(policy.nextDMReceiptToken(futureToken), futureToken) > 0);
  console.log('PASS: bounded read, delayed worker/create, exact precision, two rooms, duplicate receipts, exit and stale requests');
}
main().then(() => {ft.cleanup(); process.exit(0);}).catch(e => {
  console.error(e); process.exit(1);
});
