'use strict';

/*
 * posts.latestComment(카드의 최근 댓글 한 줄) 트리거·규칙 확인(에뮬레이터 전용).
 * firebase emulators:exec --config firebase.tag-emulators.json --project demo-wefilling \
 *   "node functions/scripts/test_latest_comment_emulator.js"
 */
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const {
  latestCommentFields,
  pickLatestComment,
  isVisibleTopLevelComment,
  isNewerThanLatest,
  backfillLatestComments,
} = require('../lib/latest_comment');

const PROJECT = process.env.GCLOUD_PROJECT || 'demo-wefilling';
const FIRESTORE = `http://${process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080'}`;
const DOCS = `${FIRESTORE}/v1/projects/${PROJECT}/databases/(default)/documents`;

if (!admin.apps.length) admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();
const {Timestamp} = admin.firestore;

function token(uid) {
  const enc = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return `${enc({alg: 'none', typ: 'JWT'})}.${enc({
    iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT,
    sub: uid, user_id: uid, iat: now, exp: now + 3600, auth_time: now,
    firebase: {sign_in_provider: 'password'},
  })}.`;
}

async function waitFor(check, label) {
  for (let i = 0; i < 60; i++) {
    if (await check()) return;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  assert.fail(`timeout: ${label}`);
}

const latestOf = async (postId) => (await db.collection('posts').doc(postId).get()).get('latestComment');

function unitTests() {
  const t = (ms) => Timestamp.fromMillis(ms);
  assert.equal(isVisibleTopLevelComment({content: 'a'}), true);
  assert.equal(isVisibleTopLevelComment({content: 'a', parentCommentId: 'c1'}), false);
  assert.equal(isVisibleTopLevelComment({content: 'a', isDeleted: true}), false);
  const long = latestCommentFields('c1', {userId: 'u', authorNickname: ' sound ', content: `${'가'.repeat(130)}\n끝`, createdAt: t(1)});
  assert.equal(Array.from(long.text).length, 120);
  assert.equal(long.authorName, 'sound');
  const anon = latestCommentFields('c2', {userId: 'u', authorNickname: 'x', authorPhotoUrl: 'p', isAnonymous: true, content: 'hi'});
  assert.equal('authorName' in anon, false);
  assert.equal('authorPhotoUrl' in anon, false);
  assert.equal(latestCommentFields('c3', {content: '', imagePaths: ['a']}).hasMedia, true);
  assert.equal(isNewerThanLatest({createdAt: t(10)}, {createdAt: t(5)}), false);
  assert.equal(isNewerThanLatest({createdAt: t(10)}, {createdAt: t(20)}), true);
  const picked = pickLatestComment([
    {id: 'a', data: {createdAt: t(1)}},
    {id: 'b', data: {createdAt: t(3), parentCommentId: 'a'}},
    {id: 'c', data: {createdAt: t(2), isDeleted: true}},
    {id: 'd', data: {createdAt: t(4)}},
  ], 'd');
  assert.equal(picked.id, 'a');
  console.log('latestComment unit ok');
}

async function main() {
  unitTests();
  const now = Date.now();
  await db.collection('users').doc('alice').set({nickname: 'alice', emailVerified: true});
  await db.collection('posts').doc('lp1').set({
    userId: 'alice', content: 'hello', visibility: 'public', commentCount: 0,
    createdAt: Timestamp.fromMillis(now), isAnonymous: false,
  });
  const comment = (id, data) => db.collection('comments').doc(id).set({
    postId: 'lp1', userId: 'bob', authorNickname: 'bob', authorPhotoUrl: '', content: id,
    createdAt: Timestamp.fromMillis(now + data.at), ...data.extra,
  });

  // 1) 최상위 댓글 → latestComment, 2) 더 최근 댓글로 바뀜
  await comment('c1', {at: 1000});
  await waitFor(async () => (await latestOf('lp1'))?.commentId === 'c1', 'c1 latest');
  await comment('c2', {at: 2000});
  await waitFor(async () => (await latestOf('lp1'))?.commentId === 'c2', 'c2 latest');
  const latest = await latestOf('lp1');
  assert.equal(latest.text, 'c2');
  assert.equal(latest.authorName, 'bob');
  assert.equal(latest.isAnonymous, false);

  // 3) 대댓글은 갱신하지 않음
  await comment('r1', {at: 3000, extra: {parentCommentId: 'c2', depth: 1}});
  await waitFor(async () => (await db.collection('posts').doc('lp1').get()).get('commentCount') === 3, 'reply counted');
  assert.equal((await latestOf('lp1')).commentId, 'c2');

  // 4) 최신 댓글을 숨김(soft delete) → 이전 댓글로 재계산
  await db.collection('comments').doc('c2').update({isDeleted: true});
  await waitFor(async () => (await latestOf('lp1'))?.commentId === 'c1', 'soft delete recompute');

  // 5) 최신 댓글을 삭제 → 남은 최상위 댓글이 없으면 필드 삭제
  await db.collection('comments').doc('c1').delete();
  await waitFor(async () => (await latestOf('lp1')) === undefined, 'delete clears');

  // 6) 클라이언트는 latestComment를 쓸 수 없다(작성자도).
  const response = await fetch(
    `${DOCS}/posts/lp1?updateMask.fieldPaths=latestComment`,
    {
      method: 'PATCH',
      headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token('alice')}`},
      body: JSON.stringify({fields: {latestComment: {mapValue: {fields: {text: {stringValue: 'fake'}}}}}}),
    },
  );
  assert.equal(response.status, 403);

  // 7) 이전 스크립트: 필드가 없는 글을 채운다(dry run은 쓰지 않음).
  await comment('c9', {at: 9000});
  await waitFor(async () => (await latestOf('lp1'))?.commentId === 'c9', 'c9 latest');
  await db.collection('posts').doc('lp1').update({latestComment: admin.firestore.FieldValue.delete()});
  const dry = await backfillLatestComments(now - 60 * 1000, false);
  assert.equal(dry.updated, 1);
  assert.equal(await latestOf('lp1'), undefined);
  const applied = await backfillLatestComments(now - 60 * 1000, true);
  assert.equal(applied.updated, 1);
  assert.equal((await latestOf('lp1')).commentId, 'c9');
  assert.equal((await backfillLatestComments(now - 60 * 1000, true)).updated, 0);
  console.log('latestComment emulator ok');
}

main().then(() => process.exit(0), (error) => {
  console.error(error);
  process.exit(1);
});
