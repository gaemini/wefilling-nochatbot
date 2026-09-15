#!/usr/bin/env node
// LOCAL ONLY. Exercises actual Rules plus the stable-ID transaction protocol.
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const host = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^127\.0\.0\.1:\d+$/.test(host)) throw Error('Local emulator required');
const projectId = 'demo-chat-delivery';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId});
const index = require('../lib/index'); // production module owns initializeApp
const db = admin.firestore();
const ft = require('firebase-functions-test')();
const dm = require('../lib/dm_chat');
const alice = 'chatAlice01234567890123';
const bob = 'chatBob0123456789012345';
const room = `${alice}_${bob}`;
const ref = db.collection('conversations').doc(room);
const root = `projects/${projectId}/databases/(default)/documents`;
const base = `http://${host}/v1/${root}`;
const enc = (v) => Buffer.from(JSON.stringify(v)).toString('base64url');
function token(uid) {
  return `${enc({alg: 'none', typ: 'JWT'})}.${enc({sub: uid, user_id: uid,
    aud: projectId, iss: `https://securetoken.google.com/${projectId}`,
    iat: Math.floor(Date.now()/1000), exp: Math.floor(Date.now()/1000)+3600,
    firebase: {sign_in_provider: 'password'}})}.`;
}
async function request(url, body, uid = alice, method = 'POST') {
  const response = await fetch(url, {method, signal: AbortSignal.timeout(15000),
    headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token(uid)}`},
    ...(body ? {body: JSON.stringify(body)} : {})});
  const data = await response.json();
  if (!response.ok) throw Object.assign(Error(data.error?.message), {code: data.error?.status});
  return data;
}
const timestamp = (fieldPath) => ({fieldPath, setToServerValue: 'REQUEST_TIME'});
function writes(id, text, invalidRoomUpdate = false) {
  return [{
    update: {name: `${root}/conversations/${room}/messages/${id}`, fields: {
      senderId: {stringValue: alice}, text: {stringValue: text}, isRead: {booleanValue: false},
    }}, currentDocument: {exists: false}, updateTransforms: [timestamp('createdAt')],
  }, {
    update: {name: `${root}/conversations/${room}`, fields: {
      lastMessage: {stringValue: text}, lastMessageSenderId: {stringValue: alice},
      lastMessageId: {stringValue: id},
      ...(invalidRoomUpdate ? {unreadCount: {mapValue: {fields: {}}}} : {}),
    }}, updateMask: {fieldPaths: ['lastMessage', 'lastMessageSenderId', 'lastMessageId',
      ...(invalidRoomUpdate ? ['unreadCount'] : [])]},
    updateTransforms: [timestamp('lastMessageTime'), timestamp('updatedAt')],
  }];
}
function fileWrites(id, overrides = {}) {
  const batch = writes(id, `📎 ${id}.pdf`);
  Object.assign(batch[0].update.fields, {
    type: {stringValue: 'file'},
    fileName: {stringValue: `${id}.pdf`},
    fileExtension: {stringValue: 'pdf'},
    fileMimeType: {stringValue: 'application/pdf'},
    fileSize: {integerValue: '2048'},
    fileStoragePath: {stringValue: `dm_files/${alice}/${room}/${id}/file.pdf`},
  }, overrides);
  return batch;
}
async function send(id, text = id) {
  for (let attempt = 0; attempt < 12; attempt++) {
    // REST emulator cannot decode a bytes transaction query parameter. An
    // updateTime precondition supplies the same optimistic compare-and-swap.
    const roomDoc = await request(`${base}/conversations/${room}`, null, alice, 'GET');
    const existing = await request(`${base}/conversations/${room}/messages/${id}`,
      null, alice, 'GET').catch((e) => {if (e.code === 'NOT_FOUND') return null; throw e;});
    if (existing) {
      assert.equal(existing.fields.senderId.stringValue, alice);
      return;
    }
    try {
      const batch = writes(id, text);
      batch[1].currentDocument = {updateTime: roomDoc.updateTime};
      await request(`${base}:commit`, {writes: batch});
      return;
    } catch (e) {
      if (!['ABORTED', 'ALREADY_EXISTS', 'FAILED_PRECONDITION'].includes(e.code)) throw e;
    }
  }
  throw Error('Retry limit');
}

async function snackChecks() {
  const snackId = 'delivery-test';
  const roomRef = db.collection('snack_chats').doc(snackId);
  await roomRef.set({participantIds: [alice, bob], lastMessageSequence: 0,
    lastMessage: '', unreadCount: {[alice]: 0, [bob]: 0},
    createdAt: admin.firestore.Timestamp.now(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now()+86400000)});
  for (const uid of [alice, bob]) await roomRef.collection('members').doc(uid).set({
    joinedAfterSequence: 0, lastReadSequence: 0});
  const value = (v) => typeof v === 'string' ? {stringValue: v}
    : typeof v === 'boolean' ? {booleanValue: v}
    : typeof v === 'number' ? {integerValue: String(v)}
    : Array.isArray(v) ? {arrayValue: {values: v.map(value)}}
    : {mapValue: {fields: Object.fromEntries(Object.entries(v).map(([k,v]) => [k,value(v)]))}};
  async function snackSend(id, uid) {
    for (let attempt = 0; attempt < 12; attempt++) {
      const current = await request(`${base}/snack_chats/${snackId}`, null, uid, 'GET');
      const sequence = Number(current.fields.lastMessageSequence.integerValue)+1;
      const message = {senderId: uid, messageScope: 'snack_chat', chatId: snackId,
        type: 'text', text: id, sequence, recipientIds: [uid === alice ? bob : alice],
        readBy: [uid], isDeleted: false, linkPreviewRemoved: false, reactionCounts: {}};
      const preview = {lastMessage: id, lastMessageId: id, lastMessageSenderId: uid,
        lastMessageType: 'text', lastMessageSequence: sequence};
      try {
        await request(`${base}:commit`, {writes: [
          {update: {name: `${root}/snack_chats/${snackId}/messages/${id}`,
            fields: value(message).mapValue.fields}, currentDocument: {exists: false},
            updateTransforms: [timestamp('createdAt')]},
          {update: {name: `${root}/snack_chats/${snackId}`,
            fields: value(preview).mapValue.fields},
            updateMask: {fieldPaths: Object.keys(preview)},
            currentDocument: {updateTime: current.updateTime},
            updateTransforms: [timestamp('lastMessageTime'), timestamp('updatedAt')]},
        ]}, uid);
        return;
      } catch (e) {
        if (e.code === 'PERMISSION_DENIED') {
          const latest = await roomRef.get();
          if (latest.get('lastMessageSequence') !== sequence - 1) continue;
        }
        if (!['ABORTED', 'ALREADY_EXISTS', 'FAILED_PRECONDITION'].includes(e.code)) throw e;
      }
    }
    throw Error('Snack contention retry limit');
  }
  for (let i = 0; i < 4; i++) await snackSend(`snack-${i}`, i % 2 ? alice : bob);
  await Promise.all(Array.from({length: 4}, (_, i) => snackSend(`concurrent-${i}`, i % 2 ? alice : bob)));
  const messages = (await roomRef.collection('messages').orderBy('sequence').get()).docs;
  assert.deepEqual(messages.map(m => m.get('sequence')), [1,2,3,4,5,6,7,8]);
  const created = ft.wrap(require('../lib/snack_chat').onSnackChatMessageCreatedSecure);
  await Promise.all(messages.map(m => created(m, {eventId: m.id,
    params: {snackChatId: snackId, messageId: m.id}})));
  const count = (await roomRef.get()).get('unreadCount');
  assert.equal(count[alice] + count[bob], 8);
  await created(messages[0], {eventId: messages[0].id,
    params: {snackChatId: snackId, messageId: messages[0].id}});
  assert.deepEqual((await roomRef.get()).get('unreadCount'), count);
  // A trusted read cursor wins against delayed create deliveries.
  await roomRef.collection('members').doc(bob).update({lastReadSequence: 100});
  await roomRef.update({[`unreadCount.${bob}`]: 0});
  await snackSend('late-read', alice);
  const late = await roomRef.collection('messages').doc('late-read').get();
  await created(late, {eventId: late.id, params: {snackChatId: snackId, messageId: late.id}});
  assert.equal((await roomRef.get()).get(`unreadCount.${bob}`), 0);
  console.log('PASS: Snack concurrent Rules commits preserve sequence/audience; duplicate and late unread delivery is idempotent');
}

async function main() {
  // Only clears the explicitly named disposable demo emulator project.
  await fetch(`http://${host}/emulator/v1/projects/${projectId}/databases/(default)/documents`, {method: 'DELETE'});
  for (const uid of [alice, bob]) await db.collection('users').doc(uid).set({
    nickname: uid, registrationStatus: 'complete', dmUnreadTotal: 0,
  });
  await ref.set({participants: [alice, bob], participantNames: {keep: 'metadata'},
    lastMessage: '', lastMessageTime: admin.firestore.Timestamp.now(),
    unreadCount: {[alice]: 0, [bob]: 0}, archivedBy: []});
  await Promise.all(Array.from({length: 4}, () => send('same-id', 'immutable')));
  assert.equal((await ref.collection('messages').get()).size, 1);
  await ref.collection('messages').doc('same-id').update({isRead: true});
  await send('same-id', 'MUST NOT OVERWRITE');
  assert.equal((await ref.collection('messages').doc('same-id').get()).get('text'), 'immutable');
  assert.equal((await ref.collection('messages').doc('same-id').get()).get('isRead'), true);
  for (let i = 0; i < 8; i++) await send(`ordered-${i}`);
  await send('same-id'); // delayed response-loss retry cannot regress preview
  assert.equal((await ref.get()).get('lastMessageId'), 'ordered-7');
  assert.equal((await ref.get()).get('participantNames.keep'), 'metadata');
  await assert.rejects(request(`${base}:commit`, {writes: writes('rollback', 'no partial save', true)}), {code: 'PERMISSION_DENIED'});
  assert.equal((await ref.collection('messages').doc('rollback').get()).exists, false);
  await assert.rejects(request(`${base}:commit`, {writes: writes('stranger', 'forged')}, 'outsider'), {code: 'PERMISSION_DENIED'});
  await request(`${base}:commit`, {writes: fileWrites('valid-file')});
  assert.equal((await ref.collection('messages').doc('valid-file').get()).get('text'), '📎 valid-file.pdf');
  await assert.rejects(request(`${base}:commit`, {writes: fileWrites('wrong-file-path', {
    fileStoragePath: {stringValue: `dm_files/${alice}/another-room/wrong-file-path/file.pdf`},
  })}), {code: 'PERMISSION_DENIED'});
  await assert.rejects(request(`${base}:commit`, {writes: fileWrites('wrong-file-mime', {
    fileMimeType: {stringValue: 'application/x-msdownload'},
  })}), {code: 'PERMISSION_DENIED'});
  await db.collection('blocks').doc(`${bob}_${alice}`).set({blocker: bob, blocked: alice});
  await assert.rejects(send('blocked'), {code: 'PERMISSION_DENIED'});
  await db.collection('blocks').doc(`${bob}_${alice}`).delete();
  await db.collection('users').doc(bob).update({disabled: true});
  await assert.rejects(send('disabled-peer'), {code: 'PERMISSION_DENIED'});
  await db.collection('users').doc(bob).update({disabled: false,
    registrationStatus: '', emailVerified: true});
  const legacy = writes('legacy-client', 'legacy display name / device timestamp');
  delete legacy[1].update.fields.lastMessageId;
  legacy[1].updateMask.fieldPaths = legacy[1].updateMask.fieldPaths.filter(f => f !== 'lastMessageId');
  legacy[0].update.fields.createdAt = {timestampValue: new Date().toISOString()};
  delete legacy[0].updateTransforms;
  await request(`${base}:commit`, {writes: legacy});
  assert.equal((await ref.collection('messages').doc('legacy-client').get()).exists, true);
  await db.collection('users').doc(bob).update({registrationStatus: 'complete'});
  const exact = admin.firestore.Timestamp.fromMillis(1700000000000);
  for (let i = 0; i < 7; i++) await ref.collection('messages').doc(`same-time-${i}`).set({
    senderId: alice, text: 'legacy same-time', createdAt: exact, isRead: false});
  const query = ref.collection('messages').where('createdAt', '==', exact)
    .orderBy('createdAt', 'desc').orderBy(admin.firestore.FieldPath.documentId(), 'desc');
  const page1 = await query.limit(3).get();
  const last = page1.docs.at(-1);
  const page2 = await query.startAfter(last.get('createdAt'), last.id).limit(4).get();
  assert.equal(new Set([...page1.docs, ...page2.docs].map(d => d.id)).size, 7);

  const markRead = ft.wrap(dm.markDMConversationReadSecure);
  const cleanup = ft.wrap(dm.onDMReceiptCleanupRequested);
  const onCreate = ft.wrap(index.onDMMessageCreated);
  const onRead = ft.wrap(index.onDMMessageRead);
  const before = await ref.get();
  const result = await markRead({conversationId: room, deferReceipts: true}, {auth: {uid: bob, token: {}}});
  assert.equal(result.receiptsUpdated, 0); // callable did not scan per-message receipts
  const after = await ref.get();
  const messageBefore = await ref.collection('messages').doc('ordered-7').get();
  await cleanup({before, after});
  const messageAfter = await messageBefore.ref.get();
  assert.equal(messageAfter.get('isRead'), true);
  const context = {eventId: 'repeated-create', params: {conversationId: room, messageId: 'ordered-7'}};
  await onCreate(messageBefore, context); // delayed create after read watermark
  await onCreate(messageBefore, context);
  await onRead({before: messageBefore, after: messageAfter}, {...context, eventId: 'repeated-read'});
  await onRead({before: messageBefore, after: messageAfter}, {...context, eventId: 'repeated-read'});
  assert.equal((await ref.get()).get(`unreadCount.${bob}`), 0);
  assert.equal((await db.collection('users').doc(bob).get()).get('dmUnreadTotal'), 0);
  await request(`${base}:commit`, {writes: fileWrites('file-unread')});
  const unreadFile = await ref.collection('messages').doc('file-unread').get();
  const fileContext = {eventId: 'file-unread-create',
    params: {conversationId: room, messageId: 'file-unread'}};
  await onCreate(unreadFile, fileContext);
  await onCreate(unreadFile, fileContext);
  assert.equal((await ref.get()).get(`unreadCount.${bob}`), 1);
  assert.equal((await db.collection('users').doc(bob).get()).get('dmUnreadTotal'), 1);
  await unreadFile.ref.update({isRead: true, readAt: admin.firestore.FieldValue.serverTimestamp()});
  const readFile = await unreadFile.ref.get();
  await onRead({before: unreadFile, after: readFile}, {...fileContext, eventId: 'file-unread-read'});
  await onRead({before: unreadFile, after: readFile}, {...fileContext, eventId: 'file-unread-read'});
  assert.equal((await ref.get()).get(`unreadCount.${bob}`), 0);
  assert.equal((await db.collection('users').doc(bob).get()).get('dmUnreadTotal'), 0);
  // A stale cleanup event must not rewind the newest watermark/cursor.
  await markRead({conversationId: room, deferReceipts: true}, {auth: {uid: bob, token: {}}});
  const latest = (await ref.get()).get(`lastReadAtBy.${bob}`);
  await cleanup({before, after});
  assert.equal((await ref.get()).get(`lastReadAtBy.${bob}`).toMillis(), latest.toMillis());
  console.log('PASS: concurrent stable IDs, rapid ordered sends, lost-response retry, atomic rollback, Rules/blocks, same-time pagination, deferred receipts, duplicate/delayed events');
  await snackChecks();
  ft.cleanup();
  await admin.app().delete();
}
main().catch(e => {console.error(e); process.exitCode = 1;});
