#!/usr/bin/env node
// Requires an explicitly started LOCAL Firestore emulator. Never production.
const assert = require('assert/strict');
const {execFileSync} = require('child_process');
const admin = require('firebase-admin');
const host = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) throw new Error('Local emulator required');
const projectId = 'demo-nickname-policy';
admin.initializeApp({projectId});
const db = admin.firestore();
const policy = require('../lib/nickname_claims');
const ft = require('firebase-functions-test')();
const update = ft.wrap(policy.updateMyNicknameSecure);
const availability = ft.wrap(policy.checkNicknameAvailability);
const ctx = (uid) => ({auth: {uid, token: {}}});
const user = (uid) => db.collection('users').doc(uid);
const claim = (key) => db.collection('nicknameClaims').doc(policy.nicknameClaimId(key));
const save = (uid, nickname, fail = false) => db.runTransaction(async (tx) => {
  const current = await tx.get(user(uid));
  const reservation = await policy.prepareNicknameReservation(tx, uid, nickname, current.data() || {}, true);
  reservation.apply();
  tx.set(user(uid), {nickname: reservation.nickname, nicknameKey: reservation.nicknameKey,
    registrationStatus: 'complete'}, {merge: true});
  if (fail) throw new Error('injected failure');
});
const migrate = () => execFileSync(process.execPath, [
  require.resolve('./migrate_nickname_claims.js'), `--project=${projectId}`,
  '--apply', '--run-id=emulator-test',
], {env: process.env, encoding: 'utf8'});

async function clientPatch(uid, path, field, value) {
  const enc = (data) => Buffer.from(JSON.stringify(data)).toString('base64url');
  const token = `${enc({alg: 'none', typ: 'JWT'})}.${enc({sub: uid, user_id: uid,
    aud: projectId, iss: `https://securetoken.google.com/${projectId}`,
    iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 3600,
    firebase: {sign_in_provider: 'password'}})}.`;
  return fetch(`http://${host}/v1/projects/${projectId}/databases/(default)/documents/${path}?updateMask.fieldPaths=${field}`, {
    method: 'PATCH', headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token}`},
    body: JSON.stringify({fields: {[field]: {stringValue: value}}}),
  });
}

async function main() {
  await fetch(`http://${host}/emulator/v1/projects/${projectId}/databases/(default)/documents`, {method: 'DELETE'});
  await assert.rejects(save('pending', 'Pending'), {code: 'unavailable'});
  const legacyNames = {legacy: 'Old_98', first: 'Jaemin', second: 'jaemin',
    decomposed: '한글', arbitrary: '旧/名称😊', disabled: 'Dormant'};
  for (const [uid, nickname] of Object.entries(legacyNames)) {
    await user(uid).set({nickname, registrationStatus: 'complete', bio: 'keep', disabled: uid === 'disabled'});
  }
  const before = (await db.collection('users').get()).docs.map((d) => [d.id, d.data()]);
  migrate();
  migrate();
  assert.deepEqual((await db.collection('users').get()).docs.map((d) => [d.id, d.data()]), before);
  assert.equal((await claim('jaemin').get()).get('status'), 'conflict');
  assert.equal((await claim('한글').get()).get('ownerUid'), 'decomposed');
  assert.equal((await claim('旧/名称😊').get()).get('ownerUid'), 'arbitrary');
  assert.equal((await claim('dormant').get()).get('ownerUid'), 'disabled');
  await assert.rejects(save('new', 'JAEMIN'), {code: 'already-exists'});
  assert.equal((await availability({nickname: 'Jaemin'}, ctx('first'))).available, false);
  const oldOwner = (await claim('jaemin').get()).get('ownerUid');
  assert.equal(await policy.releaseNicknameClaimIfOwned(oldOwner, 'jaemin'), false);
  assert.equal((await update({nickname: 'Old_98'}, ctx('legacy'))).success, true);
  assert.equal((await clientPatch('legacy', 'users/legacy', 'bio', 'new bio')).status, 200);
  assert.equal((await clientPatch('legacy', 'users/legacy', 'nickname', 'Bypass')).status, 403);
  assert.equal((await clientPatch('legacy', 'users/legacy', 'nicknameKey', 'bypass')).status, 403);
  assert.equal((await clientPatch('legacy', 'nicknameClaims/bypass', 'ownerUid', 'legacy')).status, 403);
  assert.equal((await clientPatch('legacy', 'nicknamePolicyState/current', 'status', 'ready')).status, 403);
  assert.equal((await clientPatch('newclient', 'users/newclient', 'nickname', 'Bypass')).status, 403);
  assert.equal((await user('legacy').get()).get('nickname'), 'Old_98');

  const attempts = await Promise.allSettled(Array.from({length: 8}, (_, i) => save(`racer${i}`, i % 2 ? 'Racer' : 'racer')));
  assert.equal(attempts.filter((r) => r.status === 'fulfilled').length, 1);
  for (const r of attempts.filter((r) => r.status === 'rejected')) assert.equal(r.reason.code, 'already-exists');
  const winner = (await claim('racer').get()).get('ownerUid');
  assert.equal((await availability({nickname: 'RACER'}, ctx(winner))).available, true);
  await assert.rejects(save(winner, 'Nextname', true), /injected failure/);
  assert.equal((await claim('racer').get()).get('ownerUid'), winner);
  assert.equal((await claim('nextname').get()).exists, false);
  await update({nickname: 'Nextname'}, ctx(winner));
  await update({nickname: 'Nextname'}, ctx(winner)); // response-loss retry
  assert.equal((await claim('racer').get()).exists, false);
  assert.equal((await claim('nextname').get()).get('ownerUid'), winner);
  await assert.rejects(update({nickname: 'Another'}, ctx(winner)), {code: 'failed-precondition'});
  // Simulate successful deletion, reuse, then delayed cleanup of the old UID.
  await user(winner).update({deleted: true});
  await policy.releaseAllNicknameClaimsOwnedByUid(winner);
  await save('replacement', 'Nextname');
  assert.equal(await policy.releaseNicknameClaimIfOwned(winner, 'nextname'), false);
  assert.equal((await claim('nextname').get()).get('ownerUid'), 'replacement');
  await save('legacy', 'Freshname');
  assert.equal((await claim('old_98').get()).exists, false);
  await user('replacement').update({deleting: true});
  await assert.rejects(update({nickname: 'Cannot'}, ctx('replacement')), {code: 'failed-precondition'});
  const deleted = ft.wrap(policy.onDeletedAuthUserNicknameCleanup);
  await deleted({uid: 'arbitrary'});
  await deleted({uid: 'arbitrary'});
  assert.equal((await user('arbitrary').get()).get('deleted'), true);
  assert.equal((await claim('旧/名称😊').get()).exists, false);
  console.log('PASS: concurrent claims, migration rerun/legacy/collisions, rollback, rename/retry, deletion/reuse/stale cleanup');
}
main().then(() => ft.cleanup()).catch((error) => {console.error(error); process.exitCode = 1;});
