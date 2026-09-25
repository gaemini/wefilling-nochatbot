#!/usr/bin/env node
// Local-only: freeze IDs, ownership rules and at-least-once counter handlers.
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const host = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^127\.0\.0\.1:\d+$/.test(host)) throw Error('Local emulator required');
const projectId = 'demo-chat-delivery';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId});
const functions = require('../lib/index');
const ft = require('firebase-functions-test')();
const db = admin.firestore();
const run = Date.now();
const owner = `pushOwner${run}`;
const other = `pushOther${run}`;
const root = `projects/${projectId}/databases/(default)/documents`;
const enc = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const token = uid => `${enc({alg: 'none', typ: 'JWT'})}.${enc({sub: uid,
  user_id: uid, aud: projectId, iss: `https://securetoken.google.com/${projectId}`,
  iat: Math.floor(Date.now()/1000), exp: Math.floor(Date.now()/1000)+3600,
  firebase: {sign_in_provider: 'password'}})}.`;
async function writeAs(uid, collection, id, fields) {
  const response = await fetch(`http://${host}/v1/${root}:commit`, {
    method: 'POST', headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token(uid)}`},
    body: JSON.stringify({writes: [{update: {name: `${root}/${collection}/${id}`, fields},
      updateMask: {fieldPaths: Object.keys(fields)}}]}),
  });
  return response.status;
}
async function main() {
  await db.collection('users').doc(owner).set({nickname: 'Owner', notificationUnreadTotal: 0, dmUnreadTotal: 7});
  const notifications = db.collection('notifications');
  const old = notifications.doc(`visible-${run}`);
  const unrelated = notifications.doc(`other-${run}`);
  const newest = notifications.doc(`new-${run}`);
  const value = {userId: owner, type: 'meetup_participant_left', actorId: other,
    isRead: false, createdAt: admin.firestore.Timestamp.now()};
  await old.set(value);
  await unrelated.set({...value, userId: other});
  const frozen = await notifications.where('userId', '==', owner).where('isRead', '==', false).get();
  await newest.set(value); // Arrives while the original snapshot is processed.
  const batch = db.batch();
  frozen.docs.forEach(doc => batch.update(doc.ref, {isRead: true}));
  await batch.commit();
  assert.equal((await old.get()).get('isRead'), true);
  assert.equal((await newest.get()).get('isRead'), false);
  assert.equal((await unrelated.get()).get('isRead'), false);
  const create = ft.wrap(functions.onNotificationCreated);
  const context = {eventId: `delayed-push-${run}`, params: {notificationId: old.id}};
  const createdSnapshot = await old.get();
  await create(createdSnapshot, context);
  await create(createdSnapshot, context);
  const user = await db.collection('users').doc(owner).get();
  assert.equal(user.get('notificationUnreadTotal'), 0);
  assert.equal(user.get('dmUnreadTotal'), 7);
  const reminder = db.collection('todoNotificationDeliveries').doc(`reminder-${run}`);
  await reminder.set({userId: owner, todoIds: ['a', 'b'], isRead: false, status: 'sent'});
  assert.equal(await writeAs(other, reminder.parent.id, reminder.id, {isRead: {booleanValue: true}}), 403);
  assert.equal(await writeAs(owner, reminder.parent.id, reminder.id, {status: {stringValue: 'changed'}}), 403);
  assert.equal(await writeAs(owner, reminder.parent.id, reminder.id, {isRead: {booleanValue: true}}), 200);
  assert.equal(await writeAs(owner, reminder.parent.id, reminder.id, {isRead: {booleanValue: false}}), 403);
  assert.deepEqual((await reminder.get()).get('todoIds'), ['a', 'b']);
  // Capture actual envelopes; never send test notifications to FCM.
  const messaging = admin.messaging();
  const originalSend = messaging.send;
  const pushes = [];
  messaging.send = async message => { pushes.push(message); return 'local-test'; };
  try {
    const ad = db.collection('ad_banners').doc(`ad-${run}`);
    const absent = await ad.get();
    await ad.set({title: 'First', updatedAt: admin.firestore.Timestamp.fromMillis(1)});
    const first = await ad.get();
    const changeAd = ft.wrap(functions.onAdBannerChanged);
    const context = {params: {bannerId: ad.id}, eventId: `ad-${run}`};
    await changeAd({before: absent, after: first}, context);
    const stamped = await ad.get();
    assert.equal(stamped.get('notificationVersion'), pushes[0].data.notificationVersion);
    await changeAd({before: first, after: stamped}, context);
    assert.equal(pushes.length, 1); // Metadata self-write must not send again.
    await ad.update({title: 'Second'}); // Console edit leaves updatedAt unchanged.
    const second = await ad.get();
    await changeAd({before: stamped, after: second}, {...context, eventId: `ad-next-${run}`});
    assert.equal(pushes.length, 2);
    assert.notEqual(pushes[0].data.notificationId, pushes[1].data.notificationId);
    assert.equal(pushes[0].topic, 'ads');
  } finally { messaging.send = originalSend; }
  console.log('PASS: frozen read IDs, new/other notifications retained, delayed/duplicate create, DM total preserved, reminder owner-only monotonic read');
  console.log('PASS: exact ad commit versions, metadata recursion suppression, unchanged updatedAt does not reuse a read identity');
}
main().then(() => process.exit(0)).catch(error => {console.error(error); process.exit(1);});
