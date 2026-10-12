// Rules regression for the 2026-10 security hardening (client-forgeable
// notifications, counters, review consent lists, participants, relationships,
// friend requests, DM payload keys, conversation IDs). Firestore emulator only:
//   firebase emulators:exec --only firestore --project demo-chat-delivery \
//     "node scripts/test_security_rules_emulator.js"
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
const now = admin.firestore.Timestamp.now();
const notif = (overrides) => ({
  userId: B, title: 't', message: 'm', type: 'new_like', meetupId: null, postId: null,
  actorId: A, actorName: 'alice', data: {k: 'v'}, isRead: false, ...overrides,
});

(async () => {
  await fetch(`http://${host}/emulator/v1/projects/${projectId}/databases/(default)/documents`, {method: 'DELETE'});
  for (const [uid, nickname] of [[A, 'alice'], [B, 'bob'], [C, 'carol']]) {
    await db.collection('users').doc(uid).set({nickname, nicknameKey: nickname,
      registrationStatus: 'complete', emailVerified: true});
  }
  const post = (extra) => ({userId: B, visibility: 'public', title: 't', content: 'c',
    likedBy: [], likes: 0, viewCount: 3, createdAt: now, ...extra});
  await db.collection('posts').doc('p1').set(post({
    pollOptions: [{id: 'o1', text: 'A', votes: 0}, {id: 'o2', text: 'B', votes: 1}], pollTotalVotes: 1}));
  await db.collection('posts').doc('p2').set(post({likedBy: [A], likes: 1}));
  await db.collection('posts').doc('p3').set(post({}));
  await db.collection('posts').doc('p4').set(post({likedBy: [C], likes: 1}));
  await db.collection('meetups').doc('m1').set({userId: B, visibility: 'public', visibleToCategoryIds: [],
    title: 'm', maxParticipants: 5, currentParticipants: 2, viewCount: 0, isConfirmed: true, createdAt: now});
  await db.collection('meetup_participants').doc(`m1_${A}`).set({meetupId: 'm1', userId: A, status: 'approved', joinedAt: now});
  const review = () => ({meetupId: 'm1', authorId: B, content: 'x', imageUrl: '', imageUrls: [],
    approvedParticipants: [], rejectedParticipants: [], pendingParticipants: [A], createdAt: now});
  for (const id of ['r1', 'r2', 'r3']) await db.collection('meetup_reviews').doc(id).set(review());
  await db.collection('users').doc(B).collection('posts').doc('pp1').set({type: 'meetup_review',
    likedBy: [], likeCount: 0, commentCount: 0, isHidden: false, createdAt: now});
  await db.collection('friend_requests').doc(`${A}_${B}`).set({fromUid: A, toUid: B, status: 'PENDING', createdAt: now});
  await db.collection('friend_requests').doc(`${A}_${B}2`).set({fromUid: A, toUid: B, status: 'PENDING', createdAt: now});

  // ---- notifications ----
  await allowed('like notification to the post author', A,
    [create('notifications/n1', notif({postId: 'p2'}), [T.now('createdAt')])]);
  await denied('like notification to someone who is not the author', A,
    [create('notifications/n2', notif({postId: 'p2', userId: C}), [T.now('createdAt')])]);
  await denied('like notification without an actual like', A,
    [create('notifications/n3', notif({postId: 'p3'}), [T.now('createdAt')])]);
  await denied('server-only type (dm_received) forged by a client', A,
    [create('notifications/n4', notif({type: 'dm_received', postId: 'p2'}), [T.now('createdAt')])]);
  await denied('actorId naming another user', A,
    [create('notifications/n5', notif({postId: 'p2', actorId: B, userId: C}), [T.now('createdAt')])]);
  await denied('unknown payload key', A,
    [create('notifications/n6', notif({postId: 'p2', foo: 'bar'}), [T.now('createdAt')])]);
  await denied('isRead preset to true', A,
    [create('notifications/n7', notif({postId: 'p2', isRead: true}), [T.now('createdAt')])]);
  await denied('client-chosen createdAt', A,
    [create('notifications/n8', notif({postId: 'p2', createdAt: new Date('2020-01-01T00:00:00Z')}))]);
  await allowed('participant-left notification to the host', A,
    [create('notifications/n9', notif({type: 'meetup_participant_left', meetupId: 'm1'}), [T.now('createdAt')])]);
  await denied('participant-left notification to a non-host', A,
    [create('notifications/n10', notif({type: 'meetup_participant_left', meetupId: 'm1', userId: C}), [T.now('createdAt')])]);
  await allowed('review request between meetup members', A,
    [create('notifications/n11', notif({type: 'review_requested', meetupId: 'm1', actorId: null}), [T.now('createdAt')])]);
  await denied('review request to a non-member', A,
    [create('notifications/n12', notif({type: 'review_requested', meetupId: 'm1', userId: C, actorId: null}), [T.now('createdAt')])]);
  await denied('review request by a non-member', C,
    [create('notifications/n13', notif({type: 'review_requested', meetupId: 'm1', userId: B, actorId: null}), [T.now('createdAt')])]);

  // ---- posts counters ----
  await allowed('like own uid on a post', A, [update('posts/p3', {likedBy: [A], likes: 1})]);
  await denied('like adds another uid', A, [update('posts/p3', {likedBy: [A, C], likes: 2})]);
  await denied('likes count mismatch', A, [update('posts/p3', {likedBy: [A], likes: 5})]);
  await allowed('unlike own uid', A, [update('posts/p3', {likedBy: [], likes: 0})]);
  await denied('remove someone else\'s like', A, [update('posts/p4', {likedBy: [], likes: 0})]);
  await allowed('view count +1', A, [update('posts/p1', {}, [T.inc('viewCount', 1)])]);
  await denied('view count jump', A, [update('posts/p1', {viewCount: 40})]);
  const vote = (uid, options, total) => [
    update('posts/p1', {pollOptions: options, pollTotalVotes: total}),
    create(`posts/p1/pollVotes/${uid}`, {userId: uid, optionId: 'o1'}, [T.now('createdAt')]),
  ];
  await allowed('first poll vote (+1 with own vote doc)', A,
    vote(A, [{id: 'o1', text: 'A', votes: 1}, {id: 'o2', text: 'B', votes: 1}], 2));
  await denied('second poll vote by the same user', A,
    vote(A, [{id: 'o1', text: 'A', votes: 2}, {id: 'o2', text: 'B', votes: 1}], 3));
  await denied('poll vote rewriting option text', C,
    vote(C, [{id: 'o1', text: 'ZZ', votes: 2}, {id: 'o2', text: 'B', votes: 1}], 3));
  await denied('poll vote inflating the total', C,
    vote(C, [{id: 'o1', text: 'A', votes: 2}, {id: 'o2', text: 'B', votes: 1}], 9));
  await denied('poll counters without a vote doc', C,
    [update('posts/p1', {pollOptions: [{id: 'o1', text: 'A', votes: 2}, {id: 'o2', text: 'B', votes: 1}], pollTotalVotes: 3})]);
  await allowed('another user\'s valid poll vote', C,
    vote(C, [{id: 'o1', text: 'A', votes: 2}, {id: 'o2', text: 'B', votes: 1}], 3));

  // ---- meetups ----
  await allowed('meetup view count +1', A, [update('meetups/m1', {}, [T.inc('viewCount', 1), T.now('updatedAt')])]);
  await denied('meetup view count jump', A, [update('meetups/m1', {viewCount: 50}, [T.now('updatedAt')])]);
  await denied('participant rewriting currentParticipants', A, [update('meetups/m1', {currentParticipants: 1}, [T.now('updatedAt')])]);

  // ---- profile review posts ----
  await allowed('profile post like (self +1)', A,
    [update(`users/${B}/posts/pp1`, {}, [T.union('likedBy', [A]), T.inc('likeCount', 1)])]);
  await denied('profile post like count jump', C,
    [update(`users/${B}/posts/pp1`, {}, [T.union('likedBy', [C]), T.inc('likeCount', 5)])]);
  await denied('profile post like adding another uid', A,
    [update(`users/${B}/posts/pp1`, {}, [T.union('likedBy', [C]), T.inc('likeCount', 1)])]);
  await allowed('profile post comment count sync', A, [update(`users/${B}/posts/pp1`, {commentCount: 3})]);
  await denied('profile post negative comment count', A, [update(`users/${B}/posts/pp1`, {commentCount: -1})]);

  // ---- meetup reviews ----
  await allowed('host edits review content', B,
    [update('meetup_reviews/r1', {content: 'new', imageUrls: ['u'], imageUrl: 'u'}, [T.now('updatedAt')])]);
  await denied('host plants approved participants', B, [update('meetup_reviews/r1', {approvedParticipants: [C]})]);
  await denied('host rewrites pending participants', B, [update('meetup_reviews/r1', {pendingParticipants: [C]})]);
  await allowed('pending participant accepts', A,
    [update('meetup_reviews/r2', {}, [T.union('approvedParticipants', [A]), T.remove('pendingParticipants', [A])])]);
  await denied('non-pending user accepts', C,
    [update('meetup_reviews/r3', {}, [T.union('approvedParticipants', [C]), T.remove('pendingParticipants', [C])])]);
  await denied('participant approves someone else too', A,
    [update('meetup_reviews/r3', {}, [T.union('approvedParticipants', [A, C]), T.remove('pendingParticipants', [A])])]);
  await denied('host creates review with pre-approved list', B,
    [create('meetup_reviews/r4', {...review(), approvedParticipants: [C]})]);
  await allowed('host creates review with empty approved list', B, [create('meetup_reviews/r5', review())]);

  // ---- meetup participants ----
  await denied('participant approves self', A, [update(`meetup_participants/m1_${A}`, {status: 'approved'})]);
  await denied('host rewrites participant userId', B, [update(`meetup_participants/m1_${A}`, {userId: C})]);
  await allowed('host changes participant status', B, [update(`meetup_participants/m1_${A}`, {status: 'rejected'})]);

  // ---- relationships / friend requests ----
  await denied('client-created relationship', A, [create('relationships/x1', {userId: A, friendId: B})]);
  await denied('client-created friend request', A, [create(`friend_requests/${A}_${C}`, {fromUid: A, toUid: C, status: 'PENDING'})]);
  await allowed('recipient accepts a friend request', B, [update(`friend_requests/${A}_${B}`, {status: 'ACCEPTED'}, [T.now('updatedAt')])]);
  await denied('recipient rewrites fromUid while accepting', B, [update(`friend_requests/${A}_${B}2`, {status: 'ACCEPTED', fromUid: C})]);

  // ---- DM ----
  const convId = [A, B].sort().join('_');
  const conversation = (participants) => ({participants, displayTitle: 'a ↔ b', participantNamesVersion: 1,
    participantNames: {[A]: 'alice', [B]: 'bob'}, participantPhotos: {[A]: '', [B]: ''},
    isAnonymous: {[A]: false, [B]: false}, lastMessage: '', lastMessageTime: new Date(),
    unreadCount: {[A]: 0, [B]: 0}, createdAt: new Date(), updatedAt: new Date(), archivedBy: []});
  await denied('conversation whose ID names a third user', A,
    [create(`conversations/${[A, C].sort().join('_')}`, conversation([A, B]), [T.now('participantNamesUpdatedAt')])]);
  await allowed('conversation with the canonical ID', A,
    [create(`conversations/${convId}`, conversation([A, B]), [T.now('participantNamesUpdatedAt')])]);
  await allowed('DM message with model keys and server timestamp', A,
    [create(`conversations/${convId}/messages/msg1`, {senderId: A, text: 'hi', isRead: false}, [T.now('createdAt')])]);
  await denied('DM message with an extra key', A,
    [create(`conversations/${convId}/messages/msg2`, {senderId: A, text: 'hi', isRead: false, foo: 'bar'}, [T.now('createdAt')])]);
  await denied('DM message with a client-chosen createdAt', A,
    [create(`conversations/${convId}/messages/msg3`, {senderId: A, text: 'hi', isRead: false, createdAt: new Date('2020-01-01T00:00:00Z')})]);
  await denied('DM message sent as someone else', C,
    [create(`conversations/${convId}/messages/msg4`, {senderId: A, text: 'hi', isRead: false}, [T.now('createdAt')])]);
  const dmVideo = (id, extra = {}) => ({
    senderId: A, text: '🎬 clip.mp4', isRead: false, type: 'file', fileName: 'clip.mp4',
    fileExtension: 'mp4', fileMimeType: 'video/mp4', fileSize: 1024 * 1024,
    fileStoragePath: `dm_files/${A}/${convId}/${id}/file.mp4`, storageBucket: 'flutterproject3-af322-kr',
    videoDurationMs: 12000, videoWidth: 960, videoHeight: 540,
    videoThumbnail: 'data:image/jpeg;base64,/9j/4AAQSkZJRg==', ...extra,
  });
  await allowed('DM video message with meta', A,
    [create(`conversations/${convId}/messages/vid1`, dmVideo('vid1'), [T.now('createdAt')])]);
  await denied('DM video message over 60 seconds', A,
    [create(`conversations/${convId}/messages/vid2`, dmVideo('vid2', {videoDurationMs: 90000}), [T.now('createdAt')])]);
  await denied('DM video thumbnail that is not a JPEG data URL', A,
    [create(`conversations/${convId}/messages/vid3`, dmVideo('vid3', {videoThumbnail: 'https://evil.example/x.jpg'}), [T.now('createdAt')])]);
  await denied('DM document message carrying video meta', A,
    [create(`conversations/${convId}/messages/doc1`, dmVideo('doc1', {fileName: 'a.pdf', fileExtension: 'pdf', fileMimeType: 'application/pdf', fileStoragePath: `dm_files/${A}/${convId}/doc1/file.pdf`}), [T.now('createdAt')])]);
  // 구버전 DM 규칙과 같이 문서 파일은 여전히 허용된다.
  await allowed('DM document message without video meta', A,
    [create(`conversations/${convId}/messages/doc2`, {senderId: A, text: '📎 a.pdf', isRead: false, type: 'file', fileName: 'a.pdf', fileExtension: 'pdf', fileMimeType: 'application/pdf', fileSize: 2048, fileStoragePath: `dm_files/${A}/${convId}/doc2/file.pdf`}, [T.now('createdAt')])]);

  // ---- legacy comment subcollections ----
  await denied('legacy post comment as another user', A, [create('posts/p1/comments/c1', {userId: B, text: 'x'})]);
  await allowed('legacy post comment as self', A, [create('posts/p1/comments/c2', {userId: A, text: 'x'})]);

  console.log(`security rules emulator checks: ${passed} passed`);
  process.exit(0);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
