'use strict';
// LOCAL ONLY: real callable handlers + real Firestore Rules for post-linked
// Snack Chats ("continue in Snack Chat"). No AI/API spend.
//   npm --prefix functions run build && firebase emulators:exec --only firestore \
//     --project demo-chat-delivery "node functions/scripts/test_post_snack_chat_emulator.js"
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const host = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^127\.0\.0\.1:\d+$/.test(host)) throw Error('Local emulator required');
const projectId = 'demo-chat-delivery';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId});
require('../lib/index');
const ft = require('firebase-functions-test')();
const snack = require('../lib/snack_chat');
const db = admin.firestore();
const root = `projects/${projectId}/databases/(default)/documents`;
const base = `http://${host}/v1/${root}`;

const AUTHOR = 'postRoomAuthor00001';
const C1 = 'postRoomCommenter001';
const C2 = 'postRoomCommenter002';
const VIEWER = 'postRoomViewer000001';
const BLOCKED = 'postRoomBlocked00001';
const POST = 'post-room-regression';
const ANON_POST = 'post-room-anonymous';

const create = ft.wrap(snack.createPostSnackChatSecure);
const join = ft.wrap(snack.joinPostSnackChatSecure);
const ctx = (uid) => ({auth: {uid, token: {}}, rawRequest: {header: () => ''}});

const enc = (v) => Buffer.from(JSON.stringify(v)).toString('base64url');
function token(uid) {
  const now = Math.floor(Date.now() / 1000);
  return `${enc({alg: 'none', typ: 'JWT'})}.${enc({sub: uid, user_id: uid, aud: projectId,
    iss: `https://securetoken.google.com/${projectId}`, iat: now, exp: now + 3600,
    firebase: {sign_in_provider: 'password'}})}.`;
}
const value = (v) => typeof v === 'string' ? {stringValue: v}
  : typeof v === 'boolean' ? {booleanValue: v}
  : typeof v === 'number' ? {integerValue: String(v)}
  : v === null ? {nullValue: null}
  : Array.isArray(v) ? {arrayValue: {values: v.map(value)}}
  : {mapValue: {fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, value(x)]))}};
async function clientUpdate(uid, path, fields) {
  const response = await fetch(`${base}:commit`, {
    method: 'POST',
    headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token(uid)}`},
    body: JSON.stringify({writes: [{
      update: {name: `${root}/${path}`, fields: value(fields).mapValue.fields},
      updateMask: {fieldPaths: Object.keys(fields)},
      currentDocument: {exists: true},
    }]}),
  });
  return response.ok;
}

async function rejects(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, error.message);
    return true;
  });
}

let passed = 0;
async function check(name, fn) {
  await fn();
  passed++;
  console.log(`  ok ${name}`);
}

async function seed() {
  const batch = db.batch();
  for (const uid of [AUTHOR, C1, C2, VIEWER, BLOCKED]) {
    batch.set(db.collection('users').doc(uid), {
      uid, nickname: uid, registrationStatus: 'complete', emailVerified: true,
    });
  }
  batch.set(db.collection('posts').doc(POST), {
    userId: AUTHOR, author: AUTHOR, content: '  \n안산 문화의 도시 산책 같이 이야기해요 정말 좋은 곳이 많아요 그렇죠\n둘째 줄',
    category: '일반', visibility: 'public', isAnonymous: false, likes: 0, likedBy: [],
    viewCount: 0, commentCount: 3, createdAt: admin.firestore.Timestamp.now(),
  });
  batch.set(db.collection('posts').doc(ANON_POST), {
    userId: AUTHOR, content: 'anon', visibility: 'public', isAnonymous: true,
    createdAt: admin.firestore.Timestamp.now(),
  });
  for (const [id, uid, postId, isDeleted] of [
    ['pr-c1', C1, POST, false],
    ['pr-c2', C2, POST, false],
    ['pr-blocked', BLOCKED, POST, false],
    ['pr-viewer-deleted', VIEWER, POST, true],
    ['pr-anon', C1, ANON_POST, false],
  ]) {
    batch.set(db.collection('comments').doc(id), {postId, userId: uid, content: 'hi', isDeleted});
  }
  batch.set(db.collection('blocks').doc(`${C1}_${BLOCKED}`), {blockerId: C1, blockedId: BLOCKED});
  await batch.commit();
}

(async () => {
  await seed();
  const notificationsBefore = (await db.collection('notifications').get()).size;
  let roomId;

  await check('viewer whose only comment is deleted is rejected', async () => {
    await rejects(create({postId: POST}, ctx(VIEWER)), 'permission-denied');
  });
  await check('anonymous post is rejected', async () => {
    await rejects(create({postId: ANON_POST}, ctx(C1)), 'failed-precondition');
  });
  await check('commenter creates the post room', async () => {
    const result = await create({postId: POST}, ctx(C1));
    assert.equal(result.created, true);
    roomId = result.snackChatId;
    const room = (await db.collection('snack_chats').doc(roomId).get()).data();
    assert.deepEqual(room.participantIds, [C1]);
    assert.equal(room.postId, POST);
    assert.equal(room.allowPostJoin, true);
    assert.equal(room.activeDurationHours, 24);
    assert.deepEqual(room.visibleToCategoryIds, []);
    assert.equal(room.title, '안산 문화의 도시 산책 같이 이야기해요 정말 좋은 곳이 많아요 그렇죠'.slice(0, 40));
    assert.ok(Array.from(room.title).length <= 40);
    const post = (await db.collection('posts').doc(POST).get()).data();
    assert.equal(post.snackChatId, roomId);
  });
  await check('second create is idempotent and joins the caller', async () => {
    const result = await create({postId: POST}, ctx(AUTHOR));
    assert.equal(result.created, false);
    assert.equal(result.snackChatId, roomId);
    const room = (await db.collection('snack_chats').doc(roomId).get()).data();
    assert.deepEqual(room.participantIds, [C1, AUTHOR]);
  });
  await check('join by eligible commenter, then idempotent', async () => {
    assert.equal((await join({snackChatId: roomId, postId: POST}, ctx(C2))).joined, true);
    assert.equal((await join({snackChatId: roomId, postId: POST}, ctx(C2))).joined, true);
    const room = (await db.collection('snack_chats').doc(roomId).get()).data();
    assert.deepEqual(room.participantIds, [C1, AUTHOR, C2]);
  });
  await check('join is rejected for ineligible user', async () => {
    await rejects(join({snackChatId: roomId, postId: POST}, ctx(VIEWER)), 'permission-denied');
  });
  await check('join is rejected when blocked with an existing participant', async () => {
    await rejects(join({snackChatId: roomId, postId: POST}, ctx(BLOCKED)), 'permission-denied');
  });
  await check('join is rejected for a mismatched post link', async () => {
    await rejects(join({snackChatId: roomId, postId: ANON_POST}, ctx(C1)), 'failed-precondition');
  });
  await check('50 participant cap', async () => {
    const roomRef = db.collection('snack_chats').doc(roomId);
    const before = (await roomRef.get()).data();
    const filler = Array.from({length: 50}, (_, i) => `filler${String(i).padStart(14, '0')}`);
    await roomRef.update({participantIds: filler});
    await db.collection('blocks').doc(`${C1}_${BLOCKED}`).delete();
    await rejects(join({snackChatId: roomId, postId: POST}, ctx(BLOCKED)), 'resource-exhausted');
    await roomRef.update({participantIds: before.participantIds});
    await db.collection('blocks').doc(`${C1}_${BLOCKED}`).set({blockerId: C1, blockedId: BLOCKED});
  });
  await check('no invite notification was created', async () => {
    const after = await db.collection('notifications').get();
    assert.equal(after.size, notificationsBefore);
    assert.ok(after.docs.every((doc) => doc.get('type') !== 'snack_chat_invite'));
  });
  await check('expired room is replaced and stops admitting', async () => {
    const oldRef = db.collection('snack_chats').doc(roomId);
    await oldRef.update({expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000)});
    const result = await create({postId: POST}, ctx(AUTHOR));
    assert.equal(result.created, true);
    assert.notEqual(result.snackChatId, roomId);
    assert.equal((await oldRef.get()).get('allowPostJoin'), false);
    roomId = result.snackChatId;
  });
  await check('rules: post author cannot change snackChatId', async () => {
    // 양성 대조: 같은 작성자의 일반 수정은 통과해야 거부 사유가 snackChatId임을 보장한다.
    assert.equal(await clientUpdate(AUTHOR, `posts/${POST}`, {content: 'edited'}), true);
    assert.equal(await clientUpdate(AUTHOR, `posts/${POST}`, {snackChatId: 'other'}), false);
    assert.equal(await clientUpdate(AUTHOR, `posts/${POST}`, {snackChatId: null}), false);
  });
  await check('rules: non-author cannot write snackChatId', async () => {
    assert.equal(await clientUpdate(C1, `posts/${POST}`, {snackChatId: 'other'}), false);
  });
  await check('rules: participant cannot write post link fields on the room', async () => {
    assert.equal(await clientUpdate(AUTHOR, `snack_chats/${roomId}`, {allowPostJoin: false}), false);
    assert.equal(await clientUpdate(AUTHOR, `snack_chats/${roomId}`, {postId: 'other'}), false);
  });

  console.log(`post snack chat emulator: ${passed} checks passed`);
  await ft.cleanup();
  process.exit(0);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
