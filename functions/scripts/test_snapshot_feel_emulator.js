#!/usr/bin/env node
// LOCAL ONLY: 필링(스낵 반응) 관계 기록, 서로 필링 판정, 알림 묶기, 상한/차단.
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

const host = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) {
  throw new Error('Local Firestore emulator required');
}

const projectId = 'demo-snapshot-feel';
admin.initializeApp({projectId});
const db = admin.firestore();
const ft = require('firebase-functions-test')();
const snapshotModule = require('../lib/snapshot');
const react = ft.wrap(snapshotModule.toggleSnapshotReaction);
const viewers = ft.wrap(snapshotModule.getSnapshotViewers);
const mutuals = ft.wrap(snapshotModule.getMyMutualFeels);
const ctx = (uid) => ({auth: {uid, token: {}}});
const DAY = 24 * 60 * 60 * 1000;

let counter = 0;
function snapshotIdOf(n) {
  return `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
}

async function makeUser(uid, extra = {}) {
  await db.collection('users').doc(uid).set({nickname: uid, ...extra});
}

async function makeSnapshot(ownerId) {
  counter += 1;
  const id = snapshotIdOf(counter);
  await db.collection('snapshots').doc(id).set({
    ownerId,
    status: 'active',
    visibility: 'public',
    mediaType: 'photo',
    storagePath: `snapshots/${ownerId}/${id}.jpg`,
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 3600000),
    reactionCounts: {},
  });
  return id;
}

async function clearAll() {
  for (const name of [
    'snapshots', 'notifications', 'snapshot_feel_edges', 'snapshot_feel_daily',
    'snapshot_mutual_feels', 'blocks', 'users',
  ]) {
    const docs = await db.collection(name).listDocuments();
    await Promise.all(docs.map(async (ref) => {
      if (name === 'snapshots') {
        for (const sub of await ref.listCollections()) {
          const subDocs = await sub.listDocuments();
          await Promise.all(subDocs.map((d) => d.delete()));
        }
      }
      await ref.delete();
    }));
  }
}

async function main() {
  // 1) 첫 반응: 알림 1개, actorId 없음, feelCount 올라감, 푸시용 생성은 한 번
  await makeUser('owner');
  await makeUser('a');
  await makeUser('b');
  const s1 = await makeSnapshot('owner');
  assert.equal((await react({snapshotId: s1, reaction: '❤️'}, ctx('a'))).created, true);
  let notifications = await db.collection('notifications').get();
  assert.equal(notifications.size, 1);
  let n = notifications.docs[0];
  assert.equal(n.id, `snapshot_feel_${s1}`);
  assert.equal(n.get('type'), 'snapshot_reaction');
  assert.equal(n.get('userId'), 'owner');
  assert.equal(n.get('feelCount'), 1);
  assert.equal(n.get('actorId'), undefined);
  assert.equal(n.get('actorName'), undefined);
  assert.equal(n.get('data.anonymous'), true);
  assert.equal(n.get('data.actorId'), undefined);

  // 2) 두 번째 사람: 같은 문서, feelCount 2
  assert.equal((await react({snapshotId: s1, reaction: '❤️'}, ctx('b'))).created, true);
  notifications = await db.collection('notifications').get();
  assert.equal(notifications.size, 1);
  assert.equal(notifications.docs[0].get('feelCount'), 2);
  // 중복 탭은 아무것도 바꾸지 않는다
  assert.equal((await react({snapshotId: s1, reaction: '❤️'}, ctx('b'))).created, false);
  assert.equal((await db.collection('notifications').doc(`snapshot_feel_${s1}`).get())
    .get('feelCount'), 2);

  // 관계 기록은 서버 컬렉션에만 남는다
  const edge = await db.collection('snapshot_feel_edges').doc('a_owner').get();
  assert.equal(edge.exists, true);
  assert.equal(edge.get('lastSnapshotId'), s1);

  // 3) A→owner 이후 owner→A (7일 안): 서로 필링 1개 + 알림 2개
  const sA = await makeSnapshot('a');
  assert.equal((await react({snapshotId: sA, reaction: '❤️'}, ctx('owner'))).created, true);
  const pair = await db.collection('snapshot_mutual_feels').doc('a_owner').get();
  assert.equal(pair.exists, true);
  assert.deepEqual([...pair.get('uids')].sort(), ['a', 'owner']);
  // 각 사람의 값은 그 사람 소유의 스낵 id다.
  assert.equal(pair.get('snapshotIds.owner'), s1);
  assert.equal(pair.get('snapshotIds.a'), sA);
  const mutualNotifications = (await db.collection('notifications').get()).docs
    .filter((d) => d.get('type') === 'snapshot_mutual_feel');
  assert.equal(mutualNotifications.length, 2);
  const forOwner = mutualNotifications.find((d) => d.get('userId') === 'owner');
  assert.equal(forOwner.get('actorId'), 'a');
  const forA = mutualNotifications.find((d) => d.get('userId') === 'a');
  assert.equal(forA.get('actorId'), 'owner');

  // 4) 30일 안 재발생은 중복을 만들지 않는다
  const s2 = await makeSnapshot('owner');
  await react({snapshotId: s2, reaction: '❤️'}, ctx('a'));
  const sA2 = await makeSnapshot('a');
  await react({snapshotId: sA2, reaction: '❤️'}, ctx('owner'));
  assert.equal((await db.collection('notifications').get()).docs
    .filter((d) => d.get('type') === 'snapshot_mutual_feel').length, 2);

  // 5) callable: 목록과 snapshotId 필터
  const list = await mutuals({}, ctx('owner'));
  assert.equal(list.mutuals.length, 1);
  assert.equal(list.mutuals[0].otherUserId, 'a');
  assert.equal(list.mutuals[0].mine.snapshotId, s1);
  assert.equal(list.mutuals[0].theirs.snapshotId, sA);
  assert.equal((await mutuals({snapshotId: s1}, ctx('owner'))).mutuals.length, 1);
  assert.equal((await mutuals({snapshotId: 'nope'}, ctx('owner'))).mutuals.length, 0);
  assert.equal((await mutuals({}, ctx('b'))).mutuals.length, 0);

  // 6) 8일 전 역방향 기록: 판정 없음
  await makeUser('c');
  await makeUser('d');
  await db.collection('snapshot_feel_edges').doc('d_c').set({
    fromUid: 'd', toUid: 'c', lastSnapshotId: 'old',
    lastAt: admin.firestore.Timestamp.fromMillis(Date.now() - 8 * DAY),
  });
  const sC = await makeSnapshot('c');
  const sD = await makeSnapshot('d');
  await react({snapshotId: sD, reaction: '❤️'}, ctx('c'));
  assert.equal((await db.collection('snapshot_mutual_feels').doc('c_d').get()).exists, false);
  // 방금 기록(c→d) 이후 d→c: 이제는 서로 필링이 열린다(7일 안)
  await react({snapshotId: sC, reaction: '❤️'}, ctx('d'));
  assert.equal((await db.collection('snapshot_mutual_feels').doc('c_d').get()).exists, true);

  // 7) 차단 쌍은 접근 자체가 막히고 서로 필링도 없다
  await makeUser('e');
  await makeUser('f');
  await db.collection('blocks').doc('e_f').set({blocker: 'e', blocked: 'f'});
  const sE = await makeSnapshot('e');
  await assert.rejects(() => react({snapshotId: sE, reaction: '❤️'}, ctx('f')));
  assert.equal((await db.collection('snapshot_mutual_feels').doc('e_f').get()).exists, false);

  // 8) 하루 상한: 반응은 저장하되 관계 기록은 건너뛴다
  await makeUser('g');
  const day = new Date(Date.now() + 9 * 3600 * 1000).toISOString()
    .slice(0, 10).replace(/-/g, '');
  await db.collection('snapshot_feel_daily').doc(`g_${day}`).set({count: 30});
  await makeUser('h');
  const sH = await makeSnapshot('h');
  assert.equal((await react({snapshotId: sH, reaction: '❤️'}, ctx('g'))).created, true);
  assert.equal((await db.collection('snapshots').doc(sH).collection('reactions').doc('g').get()).exists, true);
  assert.equal((await db.collection('snapshot_feel_edges').doc('g_h').get()).exists, false);

  // 9) getSnapshotViewers: includeReaction=false는 reaction을 비우고 기본은 기존 응답
  await db.collection('snapshots').doc(s1).collection('views').doc('a').set({
    viewedAt: admin.firestore.Timestamp.now(), displayName: 'a',
  });
  const withReaction = await viewers({snapshotId: s1, includeReaction: true}, ctx('owner'));
  assert.equal(withReaction.viewers.find((v) => v.userId === 'a').reaction, '❤️');
  const hidden = await viewers({snapshotId: s1, includeReaction: false}, ctx('owner'));
  assert.equal(hidden.viewers.find((v) => v.userId === 'a').reaction, '');
  // 기본값(필드 없음)은 반응을 돌려주지 않는다
  const byDefault = await viewers({snapshotId: s1}, ctx('owner'));
  assert.equal(byDefault.viewers.find((v) => v.userId === 'a').reaction, '');

  console.log('snapshot feel emulator checks passed');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}).finally(async () => {
  ft.cleanup();
  await admin.app().delete();
});
