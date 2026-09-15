'use strict';
const assert = require('node:assert/strict');
const {chatPushCopy, decorateChatPush, pushText} = require('../lib/chat_push_presentation');
const args = {kind: 'snack', title: '스터디 中文 👨‍👩‍👧‍👦', sender: '서녕',
  message: {text: '내일 3시에 만나요'}, language: 'ko', unreadCount: 3,
  threadKey: 'snack_same-server-tag', messageId: 'm1', sentAtMillis: 1000};
const legacy = {tokens: ['token-a'], notification: {title: 'Legacy title', body: 'Legacy body'},
  data: {type: 'snack_chat_message', snackChatId: 'a', recipientUserId: 'me',
    badge: '17', messagePreview: 'Original preview', sentAtMillis: '999', language: 'ko'},
  apns: {headers: {'apns-collapse-id': args.threadKey}, payload: {aps: {badge: 17, sound: 'default'}}},
  android: {priority: 'high', collapseKey: args.threadKey,
    notification: {tag: args.threadKey, channelId: 'high_importance_channel', notificationCount: 3}}};
const original = JSON.stringify(legacy);
delete process.env.CHAT_PUSH_PRESENTATION_V2;
assert.equal(decorateChatPush(legacy, args), legacy, 'default rollout is disabled');
process.env.CHAT_PUSH_PRESENTATION_V2 = 'true';
const decorated = decorateChatPush(legacy, args);
assert.notEqual(decorated, legacy);
assert.equal(JSON.stringify(legacy), original, 'no mutation of original envelope');
assert.equal(decorated.notification.title, args.title);
assert.equal(decorated.notification.body, '서녕: 내일 3시에 만나요');
assert.equal(decorated.apns.payload.aps.alert.subtitle, '안 읽음 3개');
assert.equal(decorated.apns.payload.aps.threadId, args.threadKey);
assert.deepEqual(decorated.android, legacy.android, 'channel/tag/sound/count/collapse unchanged');
assert.deepEqual(decorated.tokens, legacy.tokens);
assert.deepEqual(decorated.apns.headers, legacy.apns.headers);
assert.equal(decorated.apns.payload.aps.badge, 17);
assert.equal(decorated.apns.payload.aps.sound, 'default');
for (const [key, value] of Object.entries(legacy.data)) assert.equal(decorated.data[key], value);

for (const [language, count, expected] of [['ko',1,undefined], ['ko',3,'안 읽음 3개'],
  ['zh_Hans_CN',2,'2条未读'], ['en-US',2,'2 unread'], ['en',null,undefined], ['ko',NaN,undefined]]) {
  assert.equal(chatPushCopy({...args, language, unreadCount: count}).subtitle, expected);
}
assert.equal(chatPushCopy({...args, kind: 'dm', sender: '익명'}).title, '익명');
assert.equal(chatPushCopy({...args, kind: 'dm'}).body, '내일 3시에 만나요');
for (const [message, expected] of [[{type:'image'}, '📷 照片'],
  [{type:'file',originalFileName:'课程.pdf'}, '📎 课程.pdf'],
  [{type:'file',fileName:'DM课程.pdf',text:'📎 DM课程.pdf'}, '📎 DM课程.pdf'],
  [{type:'poll'}, '📊 投票'], [{text:'好',replyToMessageId:'secret'}, '↪ 好']]) {
  assert.equal(chatPushCopy({...args, message, language:'zh'}).preview, expected);
}
assert.equal(pushText('👨‍👩‍👧‍👦'.repeat(100), 30), '👨‍👩‍👧‍👦');
assert.ok(Buffer.byteLength(pushText('中文'.repeat(1000))) <= 280);
assert.equal(pushText('e\u0301', 2), '', 'do not split a combining grapheme');
const oversized = {...legacy, data:{...legacy.data, previousField:'x'.repeat(3400)}};
assert.equal(decorateChatPush(oversized, args), oversized, 'byte-budget fallback preserves original');
assert.equal(decorateChatPush(legacy, {...args, message:null}), legacy, 'preparation error fallback');
const noCount = decorateChatPush({...legacy, data:{type:'dm_received'},
  apns:{payload:{aps:{}}}}, {...args, kind:'dm', unreadCount:null});
assert.equal(noCount.data.roomUnreadCount, undefined);
assert.equal(noCount.apns.payload.aps.badge, undefined);
assert.equal(noCount.apns.payload.aps.sound, undefined, 'do not invent sound for silent pushes');
process.env.CHAT_PUSH_PRESENTATION_V2 = 'false';
assert.equal(decorateChatPush(legacy, args), legacy, 'rollback returns exact old envelope');
console.log('PASS: chat push copy, optional fields, privacy, legacy envelope, payload budget, rollback');
