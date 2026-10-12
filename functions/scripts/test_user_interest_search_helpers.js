'use strict';

const assert = require('node:assert/strict');
const {
  normalizeSocialInterestId,
  SOCIAL_PROFILE_INTEREST_IDS,
} = require('../lib/user_search_index');

assert.equal(normalizeSocialInterestId(' Travel '), 'travel');
assert.equal(normalizeSocialInterestId('language'), 'language');
assert.equal(normalizeSocialInterestId('unknown-interest'), null);
assert.equal(normalizeSocialInterestId('../users'), null);
assert.equal(SOCIAL_PROFILE_INTEREST_IDS.size, 20);

for (const requiredId of [
  'travel',
  'language',
  'study',
  'restaurants',
  'cafe',
  'fitness',
  'music',
  'movie',
  'photo',
  'game',
]) {
  assert.equal(
    SOCIAL_PROFILE_INTEREST_IDS.has(requiredId),
    true,
    `Missing featured profile interest: ${requiredId}`,
  );
}

console.log('user interest search helper tests passed');
