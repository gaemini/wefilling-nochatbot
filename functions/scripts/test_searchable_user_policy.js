#!/usr/bin/env node

const assert = require('assert');
const {evaluateSearchableUser} = require('../lib/searchable_user_policy');

const valid = {
  uid: 'uid-valid',
  nickname: 'Jaemin_1',
  nicknameKey: 'jaemin_1',
  nicknameSearchTokens: ['j'],
  emailVerified: true,
  registrationStatus: 'complete',
};
const decision = (uid, patch) => evaluateSearchableUser(
  uid,
  patch === null ? undefined : {...valid, ...patch},
);
const rejects = (uid, patch, reason) => {
  const result = decision(uid, patch);
  assert.strictEqual(result.searchable, false);
  assert.strictEqual(result.reason, reason);
};

assert.strictEqual(decision('uid-valid', {}).searchable, true); // 1
assert.strictEqual(decision('uid-valid', {registrationStatus: ''}).searchable, true); // 2
assert.strictEqual(decision('uid-valid', {nicknameKey: ''}).searchable, true); // 3
assert.strictEqual(decision('uid-valid', {nicknameKey: ''}).needsNicknameKeyRepair, true); // 4
rejects('uid-valid', null, 'missing_document'); // 5
rejects('', {}, 'invalid_uid'); // 6
rejects('deleted', {}, 'invalid_uid'); // 7
rejects('uid/invalid', {}, 'invalid_uid'); // 8
rejects('uid-valid', {isDeleted: true}, 'deleted_or_disabled'); // 9
rejects('uid-valid', {deleted: true}, 'deleted_or_disabled'); // 10
rejects('uid-valid', {deleting: true}, 'deleted_or_disabled'); // 11
rejects('uid-valid', {disabled: true}, 'deleted_or_disabled'); // 12
rejects('uid-valid', {isSuspended: true}, 'deleted_or_disabled'); // 13
rejects('uid-valid', {deletedAt: new Date()}, 'deleted_or_disabled'); // 14
rejects('uid-valid', {status: 'suspended'}, 'deleted_or_disabled'); // 15
rejects('uid-valid', {registrationStatus: 'profile_pending'}, 'incomplete_registration'); // 16
rejects('uid-valid', {registrationStatus: 'auth_created'}, 'incomplete_registration'); // 17
rejects('uid-valid', {registrationStatus: '', emailVerified: false}, 'incomplete_registration'); // 18
rejects('uid-valid', {registrationStatus: '', signupState: 'profilePending'}, 'incomplete_registration'); // 19
rejects('uid-valid', {searchable: false}, 'private'); // 20
rejects('uid-valid', {isProfilePrivate: true}, 'private'); // 21
rejects('uid-valid', {nickname: ''}, 'missing_nickname'); // 22
rejects('uid-valid', {nickname: '익명', nicknameKey: '익명'}, 'sentinel_nickname'); // 23
rejects('uid-valid', {nickname: 'invalid name', nicknameKey: ''}, 'invalid_nickname'); // 24
rejects('uid-valid', {nicknameKey: 'someone_else'}, 'nickname_key_mismatch'); // 25
assert.strictEqual(decision('uid-valid', { // 26
  nickname: 'legacy.user',
  nicknameKey: 'legacy.user',
}).searchable, true);

process.stdout.write('searchable user policy: 26 scenarios passed\n');
