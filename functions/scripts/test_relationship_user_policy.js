// evaluateRelationshipUser: 친구 요청은 활성 계정이면 허용, 검색용 파생 데이터 문제로는 막지 않는다.
const assert = require('node:assert/strict');
const {evaluateRelationshipUser} = require('../lib/searchable_user_policy');
const base = {nickname: 'jaemini', registrationStatus: 'complete', emailVerified: true};
assert.equal(evaluateRelationshipUser('u1', base).allowed, true);
assert.equal(evaluateRelationshipUser('u1', {...base, nicknameKey: 'stale-key'}).allowed, true);
assert.equal(evaluateRelationshipUser('u1', {...base, isDeleted: true}).allowed, false);
assert.equal(evaluateRelationshipUser('u1', {...base, status: 'suspended'}).allowed, false);
assert.equal(evaluateRelationshipUser('u1', {...base, registrationStatus: 'pending'}).allowed, false);
assert.equal(evaluateRelationshipUser('u1', {...base, nickname: ''}).allowed, false);
assert.equal(evaluateRelationshipUser('u1', {...base, allowUserSearch: false}).allowed, false);
assert.equal(evaluateRelationshipUser('deleted', base).allowed, false);
assert.equal(evaluateRelationshipUser('u1', undefined).allowed, false);
console.log('relationship user policy: 9 checks passed');
