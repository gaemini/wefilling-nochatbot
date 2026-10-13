#!/usr/bin/env node
// LOCAL ONLY: 같이하기 제안/응답 callable 검증.
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

const host = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) {
  throw new Error('Local Firestore emulator required');
}
const projectId = 'demo-together';
admin.initializeApp({projectId});
const db = admin.firestore();
const ft = require('firebase-functions-test')();
const chat = require('../lib/snack_chat');
const propose = ft.wrap(chat.proposeTogetherSnackChat);
const respond = ft.wrap(chat.respondTogetherProposal);
const ctx = (uid) => ({auth: {uid, token: {}}});

async function user(uid, extra = {}) {
  await db.collection('users').doc(uid).set({
    nickname: uid, registrationStatus: 'complete', ...extra,
  });
}
async function friends(a, b) {
  await db.collection('friendships').doc([a, b].sort().join('__')).set({uids: [a, b]});
}

async function main() {
  await user('me');
  await user('you', {preferredActivities: ['lunch', 'cafe', 'movie', 'running']});
  await user('stranger', {preferredActivities: ['running']});
  await user('blocked', {preferredActivities: ['running']});
  await friends('me', 'you');
  await friends('me', 'blocked');
  await db.collection('blocks').doc('blocked_me').set({blocker: 'blocked', blocked: 'me'});

  // 친구가 아니면 거부
  await assert.rejects(() => propose({targetUid: 'stranger', activityId: 'running'}, ctx('me')));
  // 상대 프로필에 없는 활동은 거부
  await assert.rejects(() => propose({targetUid: 'you', activityId: 'bungee'}, ctx('me')));
  // 차단은 거부
  await assert.rejects(() => propose({targetUid: 'blocked', activityId: 'running'}, ctx('me')));
  // 자기 자신 거부
  await assert.rejects(() => propose({targetUid: 'me', activityId: 'running'}, ctx('me')));

  // 성공
  const first = await propose({targetUid: 'you', activityId: 'lunch'}, ctx('me'));
  assert.equal(first.success, true);
  assert.equal(first.created, true);
  const room = await db.collection('snack_chats').doc(first.snackChatId).get();
  assert.deepEqual([...room.get('participantIds')].sort(), ['me', 'you']);
  assert.equal(room.get('activeDurationHours'), 24);
  assert.equal(room.get('title'), '같이 점심 먹기');
  assert.equal(room.get('together.status'), 'pending');
  assert.equal(room.get('participantIntegrityVersion') >= 3, true);
  const messages = await room.ref.collection('messages').get();
  assert.equal(messages.size, 1);
  assert.equal(messages.docs[0].get('text'), '같이 점심 먹을래요?');
  assert.equal(messages.docs[0].get('senderId'), 'me');
  assert.equal(messages.docs[0].get('sequence'), 1);
  const notifs = await db.collection('notifications').where('type', '==', 'snack_chat_together').get();
  assert.equal(notifs.size, 1);
  assert.equal(notifs.docs[0].get('userId'), 'you');
  assert.equal(notifs.docs[0].get('data.snackChatId'), first.snackChatId);
  assert.match(notifs.docs[0].get('title'), /me님이 같이 점심 먹자고 해요/);

  // 중복: 같은 방
  const again = await propose({targetUid: 'you', activityId: 'lunch'}, ctx('me'));
  assert.equal(again.snackChatId, first.snackChatId);
  assert.equal(again.created, false);
  assert.equal((await db.collection('snack_chats').get()).size, 1);

  // 응답 권한: 보낸 사람은 불가
  await assert.rejects(() => respond({roomId: first.snackChatId, response: 'accept'}, ctx('me')));
  // 수락
  const accepted = await respond({roomId: first.snackChatId, response: 'accept'}, ctx('you'));
  assert.equal(accepted.status, 'accepted');
  assert.equal((await room.ref.get()).get('together.status'), 'accepted');
  const sys = (await room.ref.collection('messages').get()).docs.filter((d) => d.get('type') === 'system');
  assert.equal(sys.length, 1);
  assert.equal(sys[0].get('metadata.systemType'), 'together_accepted');
  const ack = await db.collection('notifications').where('type', '==', 'snack_chat_together_accepted').get();
  assert.equal(ack.size, 1);
  assert.equal(ack.docs[0].get('userId'), 'me');
  // 이미 처리됨: 다시 눌러도 변화 없음
  await respond({roomId: first.snackChatId, response: 'accept'}, ctx('you'));
  assert.equal((await db.collection('notifications').where('type', '==', 'snack_chat_together_accepted').get()).size, 1);

  // 다음에: 알림 없음, 시스템 메시지 1개
  const second = await propose({targetUid: 'you', activityId: 'cafe'}, ctx('me'));
  assert.equal((await respond({roomId: second.snackChatId, response: 'later'}, ctx('you'))).status, 'later');
  const later = await db.collection('snack_chats').doc(second.snackChatId).get();
  assert.equal(later.get('together.status'), 'later');
  assert.equal((await db.collection('notifications').where('type', '==', 'snack_chat_together_accepted').get()).size, 1);
  const laterSys = (await later.ref.collection('messages').get()).docs.filter((d) => d.get('type') === 'system');
  assert.equal(laterSys[0].get('metadata.systemType'), 'together_later');

  // 횟수 제한: 같은 상대 24시간 3회
  await propose({targetUid: 'you', activityId: 'movie'}, ctx('me'));
  await assert.rejects(() => propose({targetUid: 'you', activityId: 'running'}, ctx('me')));

  // 문장 규칙
  assert.equal(chat.togetherFirstMessage('cafe'), '카페 같이 갈래요?');
  assert.equal(chat.togetherFirstMessage('running'), '‘러닝’ 같이 할래요?');
  assert.match(chat.togetherFirstMessage('photo', 'en'), /Take photos/);

  console.log('together snack chat emulator checks passed');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}).finally(async () => {
  ft.cleanup();
  await admin.app().delete();
});
