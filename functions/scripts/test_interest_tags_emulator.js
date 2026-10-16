'use strict';

/*
 * #태그 규칙·함수·이전 스크립트 확인(에뮬레이터 전용).
 * firebase emulators:exec --project demo-wefilling --only firestore,functions \
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
  registrationStatus: 'complete', nickname: 'tester', searchable: true, ...extra,
});

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
  console.log('callables ok');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
