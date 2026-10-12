// Rules regression for first_response_requests (비친구 첫 응답 요청).
// Firestore emulator only:
//   firebase emulators:exec --only firestore --project demo-chat-delivery \
//     "node scripts/test_first_response_rules_emulator.js"
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const host = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^127\.0\.0\.1:\d+$/.test(host)) throw Error('Local emulator required');
const projectId = 'demo-chat-delivery';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId});
admin.initializeApp({projectId});
const db = admin.firestore();
const root = `projects/${projectId}/databases/(default)/documents`;
const base = `http://${host}/v1/${root}`;

const A = 'uidAlice0001';
const B = 'uidBob000002';
const C = 'uidCarol0003';
const enc = (v) => Buffer.from(JSON.stringify(v)).toString('base64url');
function token(uid) {
  const now = Math.floor(Date.now() / 1000);
  return `${enc({alg: 'none', typ: 'JWT'})}.${enc({sub: uid, user_id: uid, aud: projectId,
    iss: `https://securetoken.google.com/${projectId}`, iat: now, exp: now + 3600,
    firebase: {sign_in_provider: 'password'}})}.`;
}
const value = (v) => v === null ? {nullValue: null} :
  typeof v === 'string' ? {stringValue: v} :
  typeof v === 'boolean' ? {booleanValue: v} :
  typeof v === 'number' ? (Number.isInteger(v) ? {integerValue: String(v)} : {doubleValue: v}) :
  v instanceof Date ? {timestampValue: v.toISOString()} :
  Array.isArray(v) ? {arrayValue: {values: v.map(value)}} :
  {mapValue: {fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, value(x)]))}};
const T = {
  now: (fieldPath) => ({fieldPath, setToServerValue: 'REQUEST_TIME'}),
  inc: (fieldPath, n) => ({fieldPath, increment: {integerValue: String(n)}}),
  union: (fieldPath, vals) => ({fieldPath, appendMissingElements: {values: vals.map(value)}}),
  remove: (fieldPath, vals) => ({fieldPath, removeAllFromArray: {values: vals.map(value)}}),
};
function create(path, fields, transforms = []) {
  const w = {update: {name: `${root}/${path}`, fields: value(fields).mapValue.fields},
    currentDocument: {exists: false}};
  if (transforms.length) w.updateTransforms = transforms;
  return w;
}
function update(path, fields, transforms = []) {
  const w = {update: {name: `${root}/${path}`, fields: value(fields).mapValue.fields},
    updateMask: {fieldPaths: Object.keys(fields)}, currentDocument: {exists: true}};
  if (transforms.length) w.updateTransforms = transforms;
  return w;
}
async function commit(uid, writes) {
  const response = await fetch(`${base}:commit`, {
    method: 'POST',
    headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token(uid)}`},
    body: JSON.stringify({writes}),
  });
  const data = await response.json().catch(() => ({}));
  return {ok: response.ok, status: response.status, message: data.error?.message || ''};
}
let passed = 0;
async function allowed(label, uid, writes) {
  const r = await commit(uid, writes);
  assert.ok(r.ok, `${label}: expected ALLOWED, got ${r.status} ${r.message}`);
  passed++;
  console.log('PASS allowed:', label);
}
async function denied(label, uid, writes) {
  const r = await commit(uid, writes);
  assert.equal(r.status, 403, `${label}: expected PERMISSION_DENIED, got ${r.status} ${r.message}`);
  passed++;
  console.log('PASS denied :', label);
}

const D = 'uidDave00004';
const req = (from, to, extra = {}) => ({
  senderId: from, recipientId: to, senderName: 'n', senderPhotoUrl: '',
  senderPhotoVersion: 0, recipientName: '', message: '안녕하세요',
  translatedMessage: 'Hello', sourceLanguage: 'ko', sourceType: 'snapshot',
  sourceId: 's1', sourcePreview: 'p', sourceImageUrl: '', status: 'pending',
  conversationId: '', deliveredMessageId: '', ...extra,
});
const reqPath = (from, to) => `first_response_requests/${from}_${to}`;

(async () => {
  await fetch(`http://${host}/emulator/v1/projects/${projectId}/databases/(default)/documents`, {method: 'DELETE'});
  for (const [uid, nickname] of [[A, 'alice'], [B, 'bob'], [C, 'carol'], [D, 'dave']]) {
    await db.collection('users').doc(uid).set({nickname, nicknameKey: nickname,
      registrationStatus: 'complete', emailVerified: true});
  }
  // A와 C는 친구, D는 A를 차단.
  const pair = [A, C].sort().join('__');
  await db.collection('friendships').doc(pair).set({uids: [A, C]});
  await db.collection('blocks').doc(`${D}_${A}`).set({blocker: D, blocked: A});

  // ---- create ----
  await allowed('non-friend first response', A,
    [create(reqPath(A, B), req(A, B), [T.now('createdAt')])]);
  // 같은 쌍의 두 번째 요청: 덮어쓰기(사전 조건 없음)로 시도해도 규칙이 막는다.
  await denied('second request to the same person', A,
    [update(reqPath(A, B), req(A, B, {message: '또 보낼게요'}))]);
  await denied('request on behalf of another sender', A,
    [create(reqPath(C, B), req(C, B), [T.now('createdAt')])]);
  await denied('request to a friend (use DM instead)', A,
    [create(reqPath(A, C), req(A, C), [T.now('createdAt')])]);
  await denied('request to someone who blocked me', A,
    [create(reqPath(A, D), req(A, D), [T.now('createdAt')])]);
  await denied('request with message over 300 chars', B,
    [create(reqPath(B, D), req(B, D, {message: 'x'.repeat(301)}), [T.now('createdAt')])]);
  await denied('request created already accepted', B,
    [create(reqPath(B, D), req(B, D, {status: 'accepted'}), [T.now('createdAt')])]);
  await denied('request with unknown field', B,
    [create(reqPath(B, D), req(B, D, {admin: true}), [T.now('createdAt')])]);

  // ---- respond ----
  await denied('sender cannot accept own request', A,
    [update(reqPath(A, B), {status: 'accepted', conversationId: `${A}_${B}`})]);
  await denied('recipient cannot accept without conversation', B,
    [update(reqPath(A, B), {status: 'accepted'})]);
  await denied('recipient cannot rewrite the message', B,
    [update(reqPath(A, B), {message: 'changed'})]);
  await allowed('recipient accepts with conversation', B,
    [update(reqPath(A, B), {status: 'accepted', conversationId: [A, B].sort().join('_')}, [T.now('respondedAt')])]);
  await allowed('sender marks first message delivered', A,
    [update(reqPath(A, B), {deliveredMessageId: 'm1'}, [T.now('deliveredAt')])]);
  await denied('recipient cannot mark delivery', B,
    [update(reqPath(A, B), {deliveredMessageId: 'm2'})]);

  await allowed('another non-friend request', C,
    [create(reqPath(C, B), req(C, B), [T.now('createdAt')])]);
  await allowed('recipient declines', B,
    [update(reqPath(C, B), {status: 'declined'}, [T.now('respondedAt')])]);
  await denied('declined request cannot be reopened', B,
    [update(reqPath(C, B), {status: 'pending'})]);

  console.log(`first response rules emulator checks: ${passed} passed`);
  process.exit(0);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
