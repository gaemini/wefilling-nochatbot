'use strict';
// LOCAL ONLY: real Firestore Rules + real callable handlers, no AI/API spend.
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const host = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^127\.0\.0\.1:\d+$/.test(host)) throw Error('Local emulator required');
const projectId = 'demo-chat-delivery';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId});
require('../lib/index');
const ft = require('firebase-functions-test')();
const discovery = require('../lib/snack_chat_discovery');
const snack = require('../lib/snack_chat');
const db = admin.firestore();
const uid = 'discoveryAlice0123456789', peer = 'discoveryBob01234567890';
const roomId = 'discovery-regression';
const ref = db.collection('snack_chats').doc(roomId);
const ctx = {auth: {uid, token: {}}, rawRequest: {header: () => ''}};
const root = `projects/${projectId}/databases/(default)/documents`;
const base = `http://${host}/v1/${root}`;
const enc = v => Buffer.from(JSON.stringify(v)).toString('base64url');
function token(user) {
  return `${enc({alg: 'none', typ: 'JWT'})}.${enc({sub: user, user_id: user,
    aud: projectId, iss: `https://securetoken.google.com/${projectId}`,
    iat: Math.floor(Date.now()/1000), exp: Math.floor(Date.now()/1000)+3600,
    firebase: {sign_in_provider: 'password'}})}.`;
}
const value = v => typeof v === 'string' ? {stringValue: v}
  : typeof v === 'boolean' ? {booleanValue: v}
  : typeof v === 'number' ? {integerValue: String(v)}
  : Array.isArray(v) ? {arrayValue: {values: v.map(value)}}
  : {mapValue: {fields: Object.fromEntries(Object.entries(v).map(([k,v]) => [k,value(v)]))}};
async function commit(writes) {
  const response = await fetch(`${base}:commit`, {method: 'POST', signal: AbortSignal.timeout(15000),
    headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token(uid)}`}, body: JSON.stringify({writes})});
  const data = await response.json();
  if (!response.ok) throw Object.assign(Error(data.error?.message), {code: data.error?.status});
  return data;
}
async function writeMention(messageId, text, mentions, targets) {
  const currentRoom = await ref.get();
  const sequence = currentRoom.get('lastMessageSequence') + 1;
  const message = {senderId: uid, messageScope: 'snack_chat', chatId: roomId,
    type: 'text', text, sequence, recipientIds: currentRoom.get('participantIds').filter(id => id !== uid), readBy: [uid],
    isDeleted: false, linkPreviewRemoved: false, reactionCounts: {},
    ...(mentions ? {mentions, mentionTargetIds: targets} : {})};
  const preview = {lastMessage: text, lastMessageId: messageId, lastMessageSenderId: uid,
    lastMessageType: 'text', lastMessageSequence: sequence};
  return commit([
    {update: {name: `${root}/snack_chats/${roomId}/messages/${messageId}`, fields: value(message).mapValue.fields},
      currentDocument: {exists: false}, updateTransforms: [{fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME'}]},
    {update: {name: `${root}/snack_chats/${roomId}`, fields: value(preview).mapValue.fields},
      updateMask: {fieldPaths: Object.keys(preview)},
      updateTransforms: [{fieldPath: 'lastMessageTime', setToServerValue: 'REQUEST_TIME'},
        {fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME'}]},
  ]);
}
async function main() {
  for (const user of [uid, peer]) await db.collection('users').doc(user).set({
    nickname: user === uid ? '민수' : '微邻', registrationStatus: 'complete'});
  const now = Date.now();
  const start = new Date(now); start.setUTCHours(0,0,0,0);
  // Use nanosecond-tied timestamps to test document-id cursor ties.
  const at = admin.firestore.Timestamp.fromMillis(Math.min(now - 1000, start.getTime() + 1000));
  await ref.set({participantIds: [uid, peer], lastMessageSequence: 501,
    unreadCount: {[uid]: 501, [peer]: 0}, createdAt: at,
    expiresAt: admin.firestore.Timestamp.fromMillis(now + 86400000)});
  for (const user of [uid, peer]) await ref.collection('members').doc(user).set({
    status: 'active', joinedAfterSequence: 0, lastReadSequence: 0, joinedAt: at});
  for (let offset = 0; offset < 501; offset += 200) {
    const batch = db.batch();
    for (let i = offset; i < Math.min(offset + 200, 501); i++) {
      batch.set(ref.collection('messages').doc(`source-${String(i).padStart(4, '0')}`), {
        senderId: peer, sequence: i+1, createdAt: at, isDeleted: false,
        type: 'system', metadata: {systemType: i === 0 || i === 500 ? 'announcement' : 'member_joined'},
        text: i === 0 || i === 500 ? 'HELLO  微邻 가 일정 공지' : 'member joined'});
    }
    await batch.commit();
  }
  const search = ft.wrap(discovery.querySnackChatMessages);
  const filters = {snackChatId: roomId, fromMillis: start.getTime(), toMillis: now, keyword: 'hello 微邻 가'};
  let cursor, scanned = 0;
  const found = [];
  do {
    const result = await search({...filters, ...(cursor ? {cursor} : {})}, ctx);
    assert.ok(result.scannedCount <= 160);
    assert.ok(result.results.length <= 25);
    scanned += result.scannedCount; found.push(...result.results.map(m => m.id)); cursor = result.cursor;
  } while (cursor);
  assert.equal(scanned, 501);
  assert.deepEqual(found, ['source-0500', 'source-0000']);
  const context = ft.wrap(discovery.getSnackChatMessageContext);
  const around = await context({snackChatId: roomId, messageId: 'source-0250'}, ctx);
  assert.equal(around.results.length, 25);
  assert.equal(around.results[12].id, 'source-0250');
  assert.ok(around.results.every(row => !('readBy' in row) && !('deliveryRecipientIds' in row)));
  await ref.collection('messages').doc('source-0250').update({isDeleted: true});
  await assert.rejects(context({snackChatId: roomId, messageId: 'source-0250'}, ctx), {code: 'not-found'});
  assert.equal((await search({...filters, keyword: '', refreshIds: ['source-0250']}, ctx)).results.length, 0);
  await ref.collection('messages').doc('source-0250').update({isDeleted: false});
  const first = await search({...filters, keyword: ''}, ctx);
  await db.collection('blocks').doc('discovery-block').set({blocker: uid, blocked: peer});
  await assert.rejects(search({...filters, keyword: '', cursor: first.cursor}, ctx), {code: 'failed-precondition'});
  assert.equal((await search(filters, ctx)).results.length, 0);
  await db.collection('blocks').doc('discovery-block').delete();
  await assert.rejects(search(filters, {...ctx, auth: {uid: peer + '-outsider', token: {}}}));

  const recap = ft.wrap(snack.summarizeSnackChatUnread);
  const request = {snackChatId: roomId, summaryRangeType: 'today', paged: true, categories: ['decisions'],
    targetLanguage: 'ko', snapshotAtMillis: now, localDate: start.toISOString().slice(0,10),
    timezoneOffsetMinutes: 0, timezoneName: 'UTC', todayStartUtc: start.toISOString(),
    tomorrowStartUtc: new Date(start.getTime() + 86400000).toISOString()};
  cursor = null; scanned = 0; const evidence = new Set();
  do {
    const result = await recap({...request, ...(cursor ? {pageCursor: cursor} : {})}, ctx);
    assert.equal(result.success, true);
    assert.equal(result.paged, true);
    scanned += result.scannedMessageCount;
    for (const id of result.analyzedMessageIds) evidence.add(id);
    cursor = result.pageCursor;
  } while (cursor);
  assert.equal(scanned, 501);
  assert.deepEqual([...evidence].sort(), ['source-0000', 'source-0500']);
  const merged = await recap({...request, reconcileSourceIds: [...evidence]}, ctx);
  assert.equal(merged.reconciled, true);
  assert.equal(merged.sections[0].items.length, 2);
  const unread = await recap({snackChatId: roomId, summaryRangeType: 'unread', paged: true,
    firstUnreadSequence: 501, latestSequence: 501, categories: ['decisions'], targetLanguage: 'ko'}, ctx);
  assert.equal(unread.status, 'source_only');
  assert.equal(unread.sections[0].items[0].representativeMessageId, 'source-0500');
  const personal = await recap({...request, relatedToMe: true}, ctx);
  assert.equal(personal.status, 'no_related_content');
  assert.equal((await ref.collection('members').doc(uid).get()).get('lastReadSequence'), 0);
  assert.equal((await ref.get()).get(`unreadCount.${uid}`), 501);

  const validate = ft.wrap(discovery.validateSnackChatMentions);
  const text = '@微邻 안녕';
  const mentions = [{userId: peer, displayName: '微邻', start: 0, end: 3}];
  await validate({snackChatId: roomId, messageId: 'valid-mention', text, mentions}, ctx);
  await writeMention('valid-mention', text, mentions, [peer]);
  assert.deepEqual((await ref.collection('messages').doc('valid-mention').get()).get('mentions'), mentions);
  await assert.rejects(writeMention('forged', text, mentions, [peer]), {code: 'PERMISSION_DENIED'});
  await validate({snackChatId: roomId, messageId: 'mutated', text, mentions}, ctx);
  await assert.rejects(writeMention('mutated', '@微邻 altered', mentions, [peer]), {code: 'PERMISSION_DENIED'});
  await validate({snackChatId: roomId, messageId: 'expired-proof', text, mentions}, ctx);
  await ref.collection('mention_intents').doc('expired-proof').update({expiresAt: admin.firestore.Timestamp.fromMillis(1)});
  await assert.rejects(writeMention('expired-proof', text, mentions, [peer]), {code: 'PERMISSION_DENIED'});
  await assert.rejects(validate({snackChatId: roomId, messageId: 'valid-mention', text: '@민수 안녕', mentions: [{...mentions[0], userId: uid, displayName: '민수'}]},
    {...ctx, auth: {uid: peer, token: {}}}), {code: 'permission-denied'});
  await writeMention('legacy-no-metadata', 'plain @name');
  const extras = Array.from({length: 48}, (_, i) => `discoveryExtra${i}`);
  const members = db.batch();
  for (const extra of extras) members.set(db.collection('users').doc(extra), {nickname: '同学', registrationStatus: 'complete'});
  await members.commit();
  await ref.update({participantIds: [uid, peer, ...extras]});
  const fullText = Array(10).fill('@同学').join(' ');
  const tenMentions = extras.slice(0, 10).map((userId, i) => ({userId, displayName: '同学', start: i * 4, end: i * 4 + 3}));
  await validate({snackChatId: roomId, messageId: 'ten-mentions', text: fullText, mentions: tenMentions}, ctx);
  await writeMention('ten-mentions', fullText, tenMentions, extras.slice(0, 10));
  await validate({snackChatId: roomId, messageId: 'target-left', text: fullText, mentions: tenMentions}, ctx);
  await ref.update({participantIds: [uid, peer, ...extras.slice(1)]});
  await assert.rejects(writeMention('target-left', fullText, tenMentions, extras.slice(0, 10)), {code: 'PERMISSION_DENIED'});
  await ref.collection('members').doc(uid).update({status: 'left'});
  await assert.rejects(recap(request, ctx), {code: 'permission-denied'});
  await assert.rejects(context({snackChatId: roomId, messageId: 'source-0000'}, ctx), {code: 'permission-denied'});
  console.log('PASS: bounded 501-message search/recap, cursor ties, contextual lookup, deletion/block/access invalidation, one unread, raw-source reconciliation, no read writes, valid/forged/expired/owned mention intents, legacy writes');
  ft.cleanup(); await admin.app().delete();
}
main().catch(e => {console.error(e); process.exitCode = 1;});
