#!/usr/bin/env node

const assert = require('assert');
const {
  NICKNAME_POLICY_VERSION,
  normalizeLegacyStoredNickname,
  normalizeNickname,
} = require('../lib/nickname_claims');

const valid = new Map([
  ['차재민', '차재민'],
  ['Jaemin', 'Jaemin'],
  ['Jaemin_98', 'Jaemin_98'],
  ['  Cha   Jaemin  ', 'Cha_Jaemin'],
  ['Ｔｅｓｔ　Ｕｓｅｒ', 'Test_User'],
  ['Jae\u200bmin', 'Jaemin'],
]);
for (const [raw, expected] of valid) {
  assert.strictEqual(normalizeNickname(raw).nickname, expected);
}

for (const invalid of [
  '1', '12345', '_____', '12_34', 'user.name', 'user-name', '사용자😊',
  'anonymous', 'DELETED_ACCOUNT', 'abcdefghijklmnopqrstu',
]) {
  assert.throws(() => normalizeNickname(invalid), invalid);
}

assert.strictEqual(
  normalizeNickname('Cha Jaemin').nicknameKey,
  normalizeNickname('CHA_JAEMIN').nicknameKey,
);
assert.strictEqual(
  normalizeLegacyStoredNickname('legacy.user').nickname,
  'legacy.user',
);
assert.strictEqual(NICKNAME_POLICY_VERSION, 2);

process.stdout.write('nickname policy: 18 scenarios passed\n');
