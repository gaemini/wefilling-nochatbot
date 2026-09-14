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
  ['  Jaemin  ', 'Jaemin'],
  ['한글', '한글'],
  ['한글English', '한글English'],
]);
for (const [raw, expected] of valid) {
  assert.strictEqual(normalizeNickname(raw).nickname, expected);
}

for (const invalid of [
  '1', '12345', '_____', '12_34', 'user.name', 'user-name', '사용자😊',
  'anonymous', 'DELETED_ACCOUNT', 'abcdefghijklmnopqrstu',
  'Jaemin_98', 'Cha Jaemin', 'Ｔｅｓｔ', 'Jae\u200bmin', '中文', 'ひらがな',
  'Jaemin1', 'ㄱㄴ', 'Jae\u0085min', 'Jae\nmin',
]) {
  assert.throws(() => normalizeNickname(invalid), invalid);
}

assert.strictEqual(
  normalizeNickname(' Jaemin ').nicknameKey,
  normalizeNickname('jaemin').nicknameKey,
);
assert.strictEqual(
  normalizeLegacyStoredNickname('legacy.user').nickname,
  'legacy.user',
);
assert.strictEqual(NICKNAME_POLICY_VERSION, 3);

process.stdout.write('nickname policy: all scenarios passed\n');
