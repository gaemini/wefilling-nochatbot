// Rules regression for snapshot feel collections and reactions privacy.
// Firestore emulator only:
//   firebase emulators:exec --only firestore --project demo-snapshot-feel-rules \
//     "node functions/scripts/test_snapshot_feel_rules_emulator.js"
// 환경변수 EXPECT_PRIVATE_REACTIONS=1이면 9장(반응 목록 비공개) 규칙을 함께 검증한다.
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const host = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) throw Error('Local emulator required');
const projectId = 'demo-snapshot-feel-rules';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId});
admin.initializeApp({projectId});
const db = admin.firestore();
const root = `projects/${projectId}/databases/(default)/documents`;
const base = `http://${host}/v1/${root}`;
const enc = (v) => Buffer.from(JSON.stringify(v)).toString('base64url');
function token(uid) {
  const now = Math.floor(Date.now() / 1000);
  return `${enc({alg: 'none', typ: 'JWT'})}.${enc({sub: uid, user_id: uid, aud: projectId,
    iss: `https://securetoken.google.com/${projectId}`, iat: now, exp: now + 3600,
    firebase: {sign_in_provider: 'password'}})}.`;
}
async function get(uid, path) {
  const response = await fetch(`${base}/${path}`, {headers: {Authorization: `Bearer ${token(uid)}`}});
  if (process.env.DEBUG_RULES) console.log(path, response.status, await response.clone().text());
  return response.status;
}
async function list(uid, path) {
  const response = await fetch(`${base}/${path}?pageSize=5`, {headers: {Authorization: `Bearer ${token(uid)}`}});
  return response.status;
}
let passed = 0;
function ok(condition, label) {
  assert.ok(condition, label);
  passed += 1;
}

async function main() {
  for (const uid of ['owner', 'viewer', 'stranger']) {
    await db.collection('users').doc(uid).set({nickname: uid, registrationStatus: 'complete'});
  }
  const future = admin.firestore.Timestamp.fromMillis(Date.now() + 3600000);
  await db.collection('snapshots').doc('s1').set({
    ownerId: 'owner', status: 'active', visibility: 'public',
    visibilityMode: 'public', visibilitySchemaVersion: 2,
    audienceUserIdsFrozen: ['owner', 'viewer'], sourceGroupIds: [],
    visibilityLockedAt: admin.firestore.Timestamp.now(),
    createdAt: admin.firestore.Timestamp.now(), expiresAt: future,
  });
  await db.collection('snapshots').doc('s1').collection('reactions').doc('viewer').set({
    userId: 'viewer', reaction: '❤️',
  });
  await db.collection('snapshot_feel_edges').doc('viewer_owner').set({fromUid: 'viewer'});
  await db.collection('snapshot_feel_daily').doc('viewer_20260101').set({count: 1});
  await db.collection('snapshot_mutual_feels').doc('owner_viewer').set({
    uids: ['owner', 'viewer'], createdAt: admin.firestore.Timestamp.now(),
  });

  ok(await get('viewer', 'snapshot_feel_edges/viewer_owner') === 403, 'edges not readable');
  ok(await get('owner', 'snapshot_feel_edges/viewer_owner') === 403, 'edges not readable (owner)');
  ok(await get('viewer', 'snapshot_feel_daily/viewer_20260101') === 403, 'daily not readable');
  ok(await get('owner', 'snapshot_mutual_feels/owner_viewer') === 200, 'member can get mutual');
  ok(await get('viewer', 'snapshot_mutual_feels/owner_viewer') === 200, 'member can get mutual');
  ok(await get('stranger', 'snapshot_mutual_feels/owner_viewer') === 403, 'stranger denied');
  ok(await list('owner', 'snapshot_mutual_feels') === 403, 'mutual list denied');

  // 본인 반응 여부는 항상 확인할 수 있다.
  ok(await get('viewer', 'snapshots/s1/reactions/viewer') === 200, 'self reaction readable');
  if (process.env.EXPECT_PRIVATE_REACTIONS === '1') {
    ok(await get('owner', 'snapshots/s1/reactions/viewer') === 403, 'owner cannot read who reacted');
    ok(await list('owner', 'snapshots/s1/reactions') === 403, 'owner cannot list reactions');
  }
  console.log(`snapshot feel rules checks passed (${passed})`);
}
main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
}).finally(() => admin.app().delete());
