'use strict';

/*
 * #태그 규칙·함수·이전 스크립트 확인(에뮬레이터 전용).
 * firebase emulators:exec --config firebase.tag-emulators.json --project demo-wefilling \
 *   "node functions/scripts/test_interest_tags_emulator.js"
 */
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const path = require('node:path');

const PROJECT = process.env.GCLOUD_PROJECT || 'demo-wefilling';
const FIRESTORE = `http://${process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080'}`;
const FUNCTIONS = `http://${process.env.FUNCTIONS_EMULATOR_HOST || '127.0.0.1:5001'}`;
const REGION = 'asia-northeast3';
const DOCS = `${FIRESTORE}/v1/projects/${PROJECT}/databases/(default)/documents`;

function token(uid) {
  const enc = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return `${enc({alg: 'none', typ: 'JWT'})}.${enc({
    iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT,
    sub: uid, user_id: uid, iat: now, exp: now + 3600, auth_time: now,
    firebase: {sign_in_provider: 'password'},
  })}.`;
}

function toValue(v) {
  if (v === null) return {nullValue: null};
  if (Array.isArray(v)) return {arrayValue: {values: v.map(toValue)}};
  if (typeof v === 'boolean') return {booleanValue: v};
  if (typeof v === 'number') return Number.isInteger(v) ? {integerValue: String(v)} : {doubleValue: v};
  if (typeof v === 'object') return {mapValue: {fields: fields(v)}};
  return {stringValue: String(v)};
}
function fields(o) {
  return Object.fromEntries(Object.entries(o).map(([k, v]) => [k, toValue(v)]));
}

async function request(method, url, auth, body) {
  const response = await fetch(url, {
    method,
    headers: {'Content-Type': 'application/json', Authorization: `Bearer ${auth}`},
    body: body ? JSON.stringify(body) : undefined,
  });
  return {status: response.status, json: await response.json().catch(() => ({}))};
}

const seed = (docPath, data) =>
  request('PATCH', `${DOCS}/${docPath}`, 'owner', {fields: fields(data)});
const getAs = (uid, docPath) => request('GET', `${DOCS}/${docPath}`, token(uid));
const patchAs = (uid, docPath, data) => request('PATCH',
  `${DOCS}/${docPath}?${Object.keys(data).map((k) => `updateMask.fieldPaths=${k}`).join('&')}`,
  token(uid), {fields: fields(data)});
const readAdmin = async (docPath) => (await request('GET', `${DOCS}/${docPath}`, 'owner')).json;
const intField = (doc, name) => Number(doc.fields?.[name]?.integerValue ?? NaN);
const arrayField = (doc, name) =>
  (doc.fields?.[name]?.arrayValue?.values ?? []).map((v) => v.stringValue);

async function call(name, uid, data) {
  const r = await request('POST', `${FUNCTIONS}/${PROJECT}/${REGION}/${name}`, token(uid), {data});
  if (r.json.error) return {error: r.json.error.message};
  return r.json.result;
}

const activeUser = (extra = {}) => ({
  registrationStatus: 'complete', nickname: 'tester', searchable: true, emailVerified: true, ...extra,
});

// 에뮬레이터의 함수 런타임에서는 기존 createPostSecure가 admin.firestore.Timestamp를
// 못 읽어 실패한다(배포 환경은 정상). 그래서 서버 판정 함수를 직접 불러 같은 필드로 저장한다.
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp({projectId: PROJECT});
const {resolveTagAudience} = require('../lib/interest_tags');

async function createTagPost(postId, data) {
  process.env.TAG_AUDIENCE_ENABLED = 'true';
  const tagAudience = await resolveTagAudience('alice', data, data.tagIds);
  const now = admin.firestore.Timestamp.now();
  await admin.firestore().collection('posts').doc(postId).create({
    userId: 'alice', ownerId: 'alice', content: 'tag post', categoryKey: 'other', categoryKeys: ['other'],
    tagIds: data.tagIds, createdAt: now, updatedAt: now,
    visibility: tagAudience.frozen.visibilityMode, visibilityMode: tagAudience.frozen.visibilityMode,
    allowedUserIds: tagAudience.frozen.audienceUserIdsFrozen,
    audienceUserIdsFrozen: tagAudience.frozen.audienceUserIdsFrozen,
    sourceGroupIds: [], visibleToCategoryIds: [], visibilityLockedAt: now, visibilitySchemaVersion: 2,
    audienceTagIds: tagAudience.audienceTagIds, audienceFriendsOnly: tagAudience.friendsOnly,
    isAnonymous: false,
  });
}

async function main() {
  await request('DELETE', `${DOCS}`, 'owner');
  await seed('users/alice', activeUser({interests: ['running', 'cafe']}));
  await seed('users/bob', activeUser({interests: ['running'], interestTagIds: ['running']}));
  await seed('users/carol', activeUser({interests: []}));

  // 1) 이전 스크립트: 공식 태그 20개, interests 복사, 개수. 두 번 돌려도 같다.
  const script = path.join(__dirname, 'migrate_interest_tags.js');
  for (let run = 0; run < 2; run++) {
    execFileSync('node', [script, '--apply'], {stdio: 'pipe', env: process.env});
  }
  const alice = await readAdmin('users/alice');
  assert.deepEqual(arrayField(alice, 'interestTagIds'), ['running', 'cafe']);
  const running = await readAdmin('tags/running');
  assert.equal(intField(running, 'holderCount'), 2);
  assert.equal(running.fields.status.stringValue, 'active');
  assert.deepEqual(arrayField(running, 'aliases').sort(), ['러닝', '跑步'].sort());
  assert.equal(intField(await readAdmin('tags/cafe'), 'holderCount'), 1);
  assert.equal(intField(await readAdmin('tags/ai'), 'holderCount'), 0);
  console.log('migration ok');

  // 2) 규칙: 태그 읽기(활성만), 쓰기 거부, interestTagIds 직접 수정 거부.
  await seed('tags/hiddentag', {name: 'hiddentag', status: 'hidden', holderCount: 0});
  assert.equal((await getAs('alice', 'tags/running')).status, 200);
  assert.equal((await getAs('alice', 'tags/hiddentag')).status, 403);
  assert.equal((await patchAs('alice', 'tags/running', {holderCount: 99})).status, 403);
  assert.equal((await patchAs('alice', 'tags/newtag', {name: 'newtag', status: 'active'})).status, 403);
  assert.equal((await patchAs('alice', 'users/alice', {interestTagIds: ['kpop']})).status, 403);
  assert.equal((await patchAs('alice', 'users/alice', {bio: 'hi'})).status, 200);
  assert.equal((await getAs('alice', 'users_private/alice')).status, 403);
  console.log('rules ok');

  if (!(await fetch(FUNCTIONS).then(() => true, () => false))) {
    console.log('functions emulator not running: callable checks skipped');
    return;
  }

  // 3) 함수: 만들기(중복·별칭·하루 5개), 프로필 저장(개수 증감·8개·없는 태그), 사람 목록.
  assert.deepEqual(await call('createTag', 'alice', {name: '#K-POP'}), {id: 'kpop', created: true});
  assert.deepEqual(await call('createTag', 'bob', {name: 'kpop'}), {id: 'kpop', created: false});
  assert.deepEqual(await call('createTag', 'bob', {name: '러닝'}), {id: 'running', created: false});
  assert.equal((await call('createTag', 'bob', {name: 'wefilling love'})).error, 'tag-blocked');
  assert.equal((await call('createTag', 'bob', {name: '🏃'})).error, 'tag-invalid');
  for (let i = 0; i < 5; i++) await call('createTag', 'carol', {name: `carol${i}`});
  assert.equal((await call('createTag', 'carol', {name: 'carol5'})).error, 'tag-daily-limit');

  const kpopDoc = await readAdmin('tags/kpop');
  assert.equal(kpopDoc.fields.displayName.stringValue, 'K-POP');

  assert.deepEqual(await call('setProfileTags', 'alice', {tagIds: ['kpop', 'running', 'movie']}),
    {tagIds: ['kpop', 'running', 'movie']});
  assert.equal(intField(await readAdmin('tags/kpop'), 'holderCount'), 1);
  assert.equal(intField(await readAdmin('tags/cafe'), 'holderCount'), 0);
  assert.equal(intField(await readAdmin('tags/movie'), 'holderCount'), 1);
  assert.deepEqual(arrayField(await readAdmin('users/alice'), 'interests'), ['running', 'movie']);
  assert.match((await call('setProfileTags', 'alice', {tagIds: ['nosuchtag']})).error, /tag-unavailable/);
  assert.match((await call('setProfileTags', 'alice', {tagIds: ['hiddentag']})).error, /tag-unavailable/);
  const many = await call('setProfileTags', 'bob',
    {tagIds: ['running', 'cafe', 'movie', 'music', 'game', 'reading', 'ai', 'travel', 'photo']});
  assert.equal(many.tagIds.length, 8);

  const search = await call('searchTags', 'alice', {q: '러'});
  assert.equal(search.items[0].id, 'running');
  const searchK = await call('searchTags', 'alice', {q: 'k-po'});
  assert.ok(searchK.items.some((t) => t.id === 'kpop'));
  assert.equal((await call('searchTags', 'alice', {q: 'kpop'})).exact, true);

  await seed('blocks/alice_bob', {blockerId: 'alice', blockedId: 'bob'});
  const holders = await call('listTagHolders', 'alice', {tagId: 'running'});
  assert.deepEqual(holders.users.map((u) => u.uid), []);
  const holdersCarol = await call('listTagHolders', 'carol', {tagId: 'running'});
  assert.deepEqual(holdersCarol.users.map((u) => u.uid).sort(), ['alice', 'bob']);

  await seed('friendships/alice_carol', {uids: ['alice', 'carol']});
  const summary = await call('getTagSummary', 'carol', {tagId: 'running'});
  assert.equal(summary.tag.id, 'running');
  assert.equal(summary.mine, false);
  assert.deepEqual(summary.friends.map((u) => u.uid), ['alice']);
  assert.equal(summary.friendCount, 1);
  assert.equal((await call('getTagSummary', 'carol', {tagId: 'hiddentag'})).error, 'tag-unavailable');

  assert.deepEqual(await call('setTagPrefs', 'bob', {tagId: 'running', hidden: true}),
    {tagId: 'running', hidden: true});
  const afterHide = await call('listTagHolders', 'carol', {tagId: 'running'});
  assert.deepEqual(afterHide.users.map((u) => u.uid), ['alice']);
  const bobSummary = await call('getTagSummary', 'bob', {tagId: 'running'});
  assert.equal(bobSummary.hidden, true);
  assert.equal(bobSummary.mine, true);
  // 추천: carol의 친구 alice가 단 태그(kpop, running, movie) 중 carol이 안 단 것.
  const suggestions = await call('getTagSuggestions', 'carol', {});
  assert.deepEqual(suggestions.friends.map((t) => t.id).sort(), ['kpop', 'movie', 'running']);
  assert.equal(suggestions.friends[0].friendCount, 1);
  assert.ok(suggestions.popular.length > 0);
  assert.ok(suggestions.popular.every((t) => t.id !== undefined && t.holderCount >= 0));

  // 글 태그 개수: posts 쓰기 트리거가 tags/{id}.postCount를 맞춘다.
  const waitFor = async (check) => {
    for (let i = 0; i < 40; i++) {
      if (await check()) return true;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
    return false;
  };
  const before = intField(await readAdmin('tags/kpop'), 'postCount') || 0;
  await seed('posts/p1', {userId: 'alice', ownerId: 'alice', visibility: 'public', tagIds: ['kpop'], content: 'hi'});
  assert.ok(await waitFor(async () => intField(await readAdmin('tags/kpop'), 'postCount') === before + 1),
    'postCount +1');
  await request('DELETE', `${DOCS}/posts/p1`, 'owner');
  assert.ok(await waitFor(async () => intField(await readAdmin('tags/kpop'), 'postCount') === before),
    'postCount -1');
  // 클라이언트는 글의 tagIds를 바꿀 수 없다.
  await seed('posts/p2', {userId: 'alice', ownerId: 'alice', visibility: 'public', tagIds: ['kpop'], content: 'x'});
  assert.equal((await patchAs('alice', 'posts/p2', {tagIds: ['running']})).status, 403);
  console.log('callables ok');

  // ===== 공개 범위 '#태그 가진 사람' =====
  const listAs = async (uid, field, op, value) => {
    const r = await request('POST', `${DOCS}:runQuery`, token(uid), {
      structuredQuery: {
        from: [{collectionId: 'posts'}],
        where: {fieldFilter: {field: {fieldPath: field}, op, value: toValue(value)}},
      },
    });
    return Array.isArray(r.json) ? r.json.filter((row) => row.document).map((row) => row.document.name.split('/').pop()) : r.json;
  };
  await call('setProfileTags', 'carol', {tagIds: ['kpop']});
  const tagPostId = 'TagPost0000000000001';
  await createTagPost(tagPostId, {visibility: 'tag', tagIds: ['kpop']});
  const stored = await readAdmin(`posts/${tagPostId}`);
  assert.equal(stored.fields.visibility.stringValue, 'tag');
  assert.deepEqual(arrayField(stored, 'allowedUserIds'), ['alice']);
  assert.deepEqual(arrayField(stored, 'audienceTagIds'), ['kpop']);

  // 상세: 태그를 단 carol 허용, bob 거부, 작성자 허용.
  assert.equal((await getAs('carol', `posts/${tagPostId}`)).status, 200);
  assert.equal((await getAs('bob', `posts/${tagPostId}`)).status, 403);
  assert.equal((await getAs('alice', `posts/${tagPostId}`)).status, 200);
  // 구버전 쿼리(public / allowedUserIds)에는 나오지 않는다.
  assert.ok(!(await listAs('carol', 'visibility', 'EQUAL', 'public')).includes(tagPostId));
  assert.ok(!(await listAs('carol', 'allowedUserIds', 'ARRAY_CONTAINS', 'carol')).includes(tagPostId));

  // 서버 피드: carol에게만, bob은 개수만, 차단하면 빠짐.
  const carolFeed = await call('getTagAudienceFeed', 'carol', {kind: 'posts'});
  assert.deepEqual(carolFeed.items.map((item) => item.id), [tagPostId]);
  assert.equal(typeof carolFeed.items[0].createdAt._millis, 'number');
  const bobLocked = await call('getTagAudienceFeed', 'bob', {kind: 'posts', tagId: 'kpop'});
  assert.deepEqual(bobLocked.items, []);
  assert.equal(bobLocked.lockedCount, 1);
  assert.deepEqual((await call('getTagAudienceFeed', 'bob', {kind: 'posts'})).items, []);
  await seed('blocks/carol_alice', {blockerId: 'carol', blockedId: 'alice'});
  assert.deepEqual((await call('getTagAudienceFeed', 'carol', {kind: 'posts'})).items, []);
  await request('DELETE', `${DOCS}/blocks/carol_alice`, 'owner');

  // 친구 중에서만: 지금 친구 중 태그를 단 사람(carol)만 얼리고 visibility는 friends.
  const friendsPostId = 'TagPost0000000000002';
  await createTagPost(friendsPostId, {visibility: 'tag', tagIds: ['kpop'], audienceFriendsOnly: true});
  const friendsStored = await readAdmin(`posts/${friendsPostId}`);
  assert.equal(friendsStored.fields.visibility.stringValue, 'friends');
  assert.deepEqual(arrayField(friendsStored, 'allowedUserIds'), ['alice', 'carol']);
  assert.equal(friendsStored.fields.audienceFriendsOnly.booleanValue, true);

  // 막는 경우: 태그 없음, 익명, 한양 전용, 플래그 꺼짐.
  const rejects = async (data, code) => assert.equal(
    await resolveTagAudience('alice', data, data.tagIds ?? []).then(() => 'ok', (e) => e.message), code);
  await rejects({visibility: 'tag', tagIds: []}, 'tag-audience-needs-tags');
  await rejects({visibility: 'tag', tagIds: ['kpop'], isAnonymous: true}, 'tag-audience-unsupported');
  await rejects({visibility: 'tag', tagIds: ['kpop'], requiresHanyangVerification: true}, 'tag-audience-unsupported');
  process.env.TAG_AUDIENCE_ENABLED = 'false';
  await rejects({visibility: 'tag', tagIds: ['kpop']}, 'tag-audience-disabled');
  process.env.TAG_AUDIENCE_ENABLED = 'true';
  assert.equal(await resolveTagAudience('alice', {visibility: 'public'}, ['kpop']), null);

  // 도달 인원 추정.
  const kpopHolders = intField(await readAdmin('tags/kpop'), 'holderCount');
  assert.deepEqual(await call('estimateTagAudience', 'alice', {tagIds: ['kpop']}), {count: kpopHolders, approximate: true});
  assert.deepEqual(await call('estimateTagAudience', 'alice', {tagIds: ['kpop'], friendsOnly: true}), {count: 1, approximate: false});

  // 태그 공개 모임: 상세 읽기 규칙, 날짜 범위 피드.
  const day = Date.now() + 3 * 86400000;
  const meetupNow = admin.firestore.Timestamp.now();
  await admin.firestore().collection('meetups').doc('TagMeetup00000000001').create({
    userId: 'alice', ownerId: 'alice', title: 'kpop night', date: admin.firestore.Timestamp.fromMillis(day),
    createdAt: meetupNow, visibility: 'tag', visibilityMode: 'tag', allowedUserIds: ['alice'],
    audienceUserIdsFrozen: ['alice'], sourceGroupIds: [], visibleToCategoryIds: [], visibilityLockedAt: meetupNow,
    visibilitySchemaVersion: 2, audienceTagIds: ['kpop'], tagIds: ['kpop'], audienceFriendsOnly: false,
  });
  assert.equal((await getAs('carol', 'meetups/TagMeetup00000000001')).status, 200);
  assert.equal((await getAs('bob', 'meetups/TagMeetup00000000001')).status, 403);
  const range = await call('getTagAudienceFeed', 'carol', {kind: 'meetups', fromMillis: day - 86400000, toMillis: day + 86400000});
  assert.deepEqual(range.items.map((item) => item.id), ['TagMeetup00000000001']);
  assert.equal((await call('getTagAudienceFeed', 'carol', {kind: 'meetups', fromMillis: 0, toMillis: 200 * 86400000})).error, 'range-invalid');
  console.log('tag audience ok');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
