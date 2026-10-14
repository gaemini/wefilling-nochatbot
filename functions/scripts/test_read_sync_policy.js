'use strict';
// 읽음 동기화(read_sync) 순수 로직 테스트. 네트워크·Firestore 없음.
//   npm --prefix functions run build && node functions/scripts/test_read_sync_policy.js
const assert = require('node:assert/strict');
const p = require('../lib/read_sync_policy');

let passed = 0;
function check(name, fn) { fn(); passed++; }

check('스위치 기본 꺼짐', () => {
  assert.equal(p.readSyncEnabled({}), false);
  assert.equal(p.readSyncEnabled({READ_SYNC_PUSH: 'true'}), true);
  assert.equal(p.readSyncEnabled({READ_SYNC_PUSH: 'false'}), false);
});

check('묶기: 같은 방은 큰 경계, 앱 id는 중복 없이', () => {
  let s = p.emptyPending();
  s = p.mergePending(s, {k: 'app', id: 'a'}, 1);
  s = p.mergePending(s, {k: 'app', id: 'a'}, 1);
  s = p.mergePending(s, {k: 'dm', room: 'r', ms: 200, s: 0, n: 0}, 1);
  s = p.mergePending(s, {k: 'dm', room: 'r', ms: 100, s: 0, n: 0}, 1);
  s = p.mergePending(s, {k: 'snack_chat', room: 'x', seq: 9}, 1);
  s = p.mergePending(s, {k: 'snack_chat', room: 'x', seq: 3}, 1);
  assert.deepEqual(s.appIds, ['a']);
  assert.equal(s.dm.r.ms, 200);
  assert.equal(s.snack.x, 9);
});

check('앱 id가 40개를 넘으면 all_app 하나로', () => {
  let s = p.emptyPending();
  for (let i = 0; i < 41; i++) s = p.mergePending(s, {k: 'app', id: `n${i}`}, 5000);
  assert.equal(s.appIds.length, 0);
  assert.equal(s.allAppAt, 5000);
});

check('메시지: 데이터 전용, title/body 없음, iOS 백그라운드', () => {
  let s = p.mergePending(p.emptyPending(), {k: 'app', id: 'n1'}, 1);
  const m = p.readSyncMessage({tokens: ['t'], userId: 'u1', pending: s, badge: 3});
  assert.equal(m.data.type, 'read_sync');
  assert.equal(m.data.recipientUserId, 'u1');
  assert.equal(m.data.badge, '3');
  assert.equal('title' in m.data || 'body' in m.data, false);
  assert.equal(m.notification, undefined);
  assert.equal(m.apns.headers['apns-push-type'], 'background');
  assert.equal(m.apns.headers['apns-priority'], '5');
  assert.equal(m.apns.payload.aps.contentAvailable, true);
  assert.deepEqual(JSON.parse(m.data.targets), [{k: 'app', ids: ['n1']}]);
});

check('배지를 모르면 생략', () => {
  const m = p.readSyncMessage({tokens: ['t'], userId: 'u', pending: p.emptyPending(), badge: null});
  assert.equal('badge' in m.data, false);
});

check('저장된 상태를 안전하게 읽는다', () => {
  const s = p.pendingFromDoc({appIds: ['a', ''], allAppAt: 'x', dm: {r: {ms: 5}}, snack: {x: '7'}});
  assert.deepEqual(s.appIds, ['a']);
  assert.equal(s.allAppAt, 0);
  assert.equal(s.dm.r.ms, 5);
  assert.equal(s.snack.x, 7);
  assert.equal(p.pendingIsEmpty(p.pendingFromDoc(undefined)), true);
});

console.log(`read_sync policy: ${passed} checks passed`);
