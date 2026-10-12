'use strict';
// LOCAL ONLY: real Firestore + Storage rules for post comment photos.
// firebase.json lists two storage buckets without targets, which the storage
// emulator refuses. Run with a throwaway single-bucket config in the repo root:
//   echo '{"firestore":{"rules":"firestore.rules"},"storage":{"rules":"storage.rules"}}' \
//     > .tmp-rules-test-firebase.json
//   npx -y firebase-tools@13.35.1 emulators:exec --config .tmp-rules-test-firebase.json \
//     --only firestore,storage --project demo-chat-delivery \
//     "node functions/scripts/test_comment_image_rules_emulator.js"
//   rm .tmp-rules-test-firebase.json
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const host = process.env.FIRESTORE_EMULATOR_HOST || '';
const storageHost = process.env.FIREBASE_STORAGE_EMULATOR_HOST || '127.0.0.1:9199';
if (!/^127\.0\.0\.1:\d+$/.test(host)) throw Error('Local emulator required');
const projectId = 'demo-chat-delivery';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId});
admin.initializeApp({projectId});
const db = admin.firestore();
const root = `projects/${projectId}/databases/(default)/documents`;
const base = `http://${host}/v1/${root}`;
const bucket = 'flutterproject3-af322-kr';

const A = 'uidAliceImg01';
const B = 'uidBobImg0002';
const POST = 'postImgRules01';
const CID = 'AbCdEfGhIjKlMnOpQrSt'; // 20 chars like a Firestore auto id
const CID2 = 'ZyXwVuTsRqPoNmLkJiHg';

const enc = (v) => Buffer.from(JSON.stringify(v)).toString('base64url');
function token(uid) {
  const now = Math.floor(Date.now() / 1000);
  return `${enc({alg: 'none', typ: 'JWT'})}.${enc({sub: uid, user_id: uid, aud: projectId,
    iss: `https://securetoken.google.com/${projectId}`, iat: now, exp: now + 3600,
    email_verified: true, firebase: {sign_in_provider: 'password'}})}.`;
}
const value = (v) => v === null ? {nullValue: null}
  : typeof v === 'string' ? {stringValue: v}
  : typeof v === 'boolean' ? {booleanValue: v}
  : typeof v === 'number' ? {integerValue: String(v)}
  : Array.isArray(v) ? {arrayValue: {values: v.map(value)}}
  : {mapValue: {fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, value(x)]))}};

async function createComment(uid, id, fields) {
  const response = await fetch(`${base}:commit`, {
    method: 'POST',
    headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token(uid)}`},
    body: JSON.stringify({writes: [{
      update: {name: `${root}/comments/${id}`, fields: value(fields).mapValue.fields},
      currentDocument: {exists: false},
      updateTransforms: [{fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME'}],
    }]}),
  });
  return response.ok;
}

function commentFields(extra = {}) {
  return {
    postId: POST, userId: A, authorNickname: 'A', authorPhotoUrl: '', content: '',
    parentCommentId: null, depth: 0, replyToCommentId: null, replyToUserId: null,
    replyToUserNickname: null, likeCount: 0, likedBy: [], isDeleted: false, ...extra,
  };
}
const img = (cid, i) => `post_comment_images/${POST}/${cid}/${i}.jpg`;

async function upload(uid, path, {contentType = 'image/jpeg', size = 1024, meta}) {
  const boundary = 'b' + Date.now();
  const metadata = {name: path, contentType, metadata: meta};
  const body = Buffer.concat([
    Buffer.from(`--${boundary}\r\nContent-Type: application/json; charset=utf-8\r\n\r\n`),
    Buffer.from(JSON.stringify(metadata)),
    Buffer.from(`\r\n--${boundary}\r\nContent-Type: ${contentType}\r\n\r\n`),
    Buffer.alloc(size, 1),
    Buffer.from(`\r\n--${boundary}--`),
  ]);
  const response = await fetch(
    `http://${storageHost}/v0/b/${bucket}/o?name=${encodeURIComponent(path)}`, {
      method: 'POST',
      headers: {
        'Authorization': `Firebase ${token(uid)}`,
        'X-Goog-Upload-Protocol': 'multipart',
        'Content-Type': `multipart/related; boundary=${boundary}`,
      },
      body,
    });
  return response.ok;
}
async function remove(uid, path) {
  const response = await fetch(
    `http://${storageHost}/v0/b/${bucket}/o/${encodeURIComponent(path)}`, {
      method: 'DELETE', headers: {Authorization: `Firebase ${token(uid)}`},
    });
  return response.ok;
}

let passed = 0;
async function check(name, fn) {
  await fn();
  passed++;
  console.log(`  ok ${name}`);
}

(async () => {
  for (const uid of [A, B]) {
    await db.collection('users').doc(uid).set({
      uid, nickname: uid, registrationStatus: 'complete', emailVerified: true,
    });
  }
  await db.collection('posts').doc(POST).set({
    userId: B, content: 'post', visibility: 'public', isAnonymous: false,
    createdAt: admin.firestore.Timestamp.now(),
  });

  await check('firestore: existing text comment still passes', async () => {
    assert.equal(await createComment(A, 'txtCommentId00000001', commentFields({content: 'hi'})), true);
  });
  await check('firestore: existing GIF comment still passes', async () => {
    const id = 'gifCommentId00000001';
    assert.equal(await createComment(A, id, commentFields({
      gifStoragePath: `post_comment_gifs/${POST}/${id}.gif`, storageBucket: bucket,
    })), true);
  });
  await check('firestore: 4 photos on the fixed paths pass', async () => {
    assert.equal(await createComment(A, CID, commentFields({
      imagePaths: [0, 1, 2, 3].map((i) => img(CID, i)), storageBucket: bucket,
    })), true);
  });
  await check('firestore: 5 photos are rejected', async () => {
    const id = 'fiveCommentId0000001';
    assert.equal(await createComment(A, id, commentFields({
      imagePaths: [0, 1, 2, 3, 4].map((i) => img(id, i)),
    })), false);
  });
  await check('firestore: a wrong path is rejected', async () => {
    const id = 'badPathCommentId0001';
    assert.equal(await createComment(A, id, commentFields({
      imagePaths: [img('someoneElsesComment1', 0)],
    })), false);
    assert.equal(await createComment(A, id, commentFields({
      imagePaths: [`post_comment_images/otherPost/${id}/0.jpg`],
    })), false);
  });
  await check('firestore: photos and GIF together are rejected', async () => {
    const id = 'mixedCommentId000001';
    assert.equal(await createComment(A, id, commentFields({
      imagePaths: [img(id, 0)], gifStoragePath: `post_comment_gifs/${POST}/${id}.gif`,
    })), false);
  });

  const meta = (uid, cid) => ({ownerUid: uid, postId: POST, commentId: cid});
  await check('storage: owner can upload a jpeg on the fixed path', async () => {
    assert.equal(await upload(A, img(CID2, 0), {meta: meta(A, CID2)}), true);
  });
  await check('storage: wrong owner metadata, type, index or size is rejected', async () => {
    assert.equal(await upload(A, img(CID2, 1), {meta: meta(B, CID2)}), false);
    assert.equal(await upload(A, img(CID2, 1), {meta: meta(A, CID2), contentType: 'image/gif'}), false);
    assert.equal(await upload(A, img(CID2, 4), {meta: meta(A, CID2)}), false);
    assert.equal(await upload(A, img(CID2, 1), {meta: meta(A, CID2), size: 3 * 1024 * 1024 + 1}), false);
  });
  await check('storage: owner can clean up before the comment exists; others cannot', async () => {
    assert.equal(await remove(B, img(CID2, 0)), false);
    assert.equal(await remove(A, img(CID2, 0)), true);
  });
  await check('storage: cannot delete a photo of a live comment', async () => {
    assert.equal(await upload(A, img(CID, 0), {meta: meta(A, CID)}), true);
    assert.equal(await remove(A, img(CID, 0)), false);
  });

  console.log(`comment image rules emulator: ${passed} checks passed`);
  process.exit(0);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
