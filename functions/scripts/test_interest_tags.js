'use strict';

const assert = require('node:assert/strict');
const {
  normalizeTagName,
  normalizeTagQuery,
  isBannedTagId,
  officialTagAliases,
  sanitizeProfileTagIds,
  legacyInterestsFor,
  mergeLegacyInterests,
  tagIdDiff,
  contentTagCountDelta,
  OFFICIAL_INTEREST_TAGS,
  OFFICIAL_TAG_IDS,
  MAX_PROFILE_TAGS,
} = require('../lib/interest_tags');
const {SOCIAL_PROFILE_INTEREST_IDS} = require('../lib/user_search_index');

// 정규화: NFKC, 앞 '#', 구두점·공백, 소문자, 길이 2–20, 이모지 거부.
assert.equal(normalizeTagName('#러닝'), '러닝');
assert.equal(normalizeTagName('##K-POP'), 'kpop');
assert.equal(normalizeTagName('Board Game'), 'boardgame');
assert.equal(normalizeTagName('ＡＢＣ'), 'abc');
assert.equal(normalizeTagName('snake_case'), 'snake_case');
assert.equal(normalizeTagName('  跑步  '), '跑步');
assert.equal(normalizeTagName('a'), null);
assert.equal(normalizeTagName('#'), null);
assert.equal(normalizeTagName('가'.repeat(21)), null);
assert.equal(normalizeTagName('가'.repeat(20)), '가'.repeat(20));
assert.equal(normalizeTagName('러닝🏃'), null);
assert.equal(normalizeTagName('🏃🏃'), null);
assert.equal(normalizeTagName(42), null);
assert.equal(normalizeTagName('../users'), 'users');
assert.equal(normalizeTagQuery('#러'), '러');
assert.equal(normalizeTagQuery(''), null);

assert.equal(isBannedTagId('wefillingfan'), true);
assert.equal(isBannedTagId('러닝'), false);

// 공식 태그 표는 기존 관심사 20개와 같다.
assert.equal(OFFICIAL_INTEREST_TAGS.length, 20);
assert.deepEqual([...OFFICIAL_TAG_IDS].sort(), [...SOCIAL_PROFILE_INTEREST_IDS].sort());
const running = OFFICIAL_INTEREST_TAGS.find((t) => t.id === 'running');
assert.deepEqual(officialTagAliases(running).sort(), ['러닝', '跑步'].sort());
const ai = OFFICIAL_INTEREST_TAGS.find((t) => t.id === 'ai');
assert.deepEqual(officialTagAliases(ai), []);

// 프로필 태그 정리: 정규화·중복 제거·최대 8.
assert.deepEqual(sanitizeProfileTagIds(['#Running', 'running', 'x', '러닝']), ['running', '러닝']);
assert.equal(sanitizeProfileTagIds(Array.from({length: 12}, (_, i) => `tag${i}`)).length, MAX_PROFILE_TAGS);
assert.deepEqual(sanitizeProfileTagIds('running'), []);

// 구버전 표시용 interests: 공식 태그만 최대 5.
assert.deepEqual(
  legacyInterestsFor(['kpop', 'running', 'cafe', 'movie', 'music', 'game', 'ai']),
  ['running', 'cafe', 'movie', 'music', 'game'],
);

// 구버전 앱이 interests만 바꾼 경우: 사용자 태그는 남기고 공식 태그만 교체.
assert.deepEqual(mergeLegacyInterests(['kpop', 'running', 'cafe'], ['cafe', 'movie']), ['kpop', 'cafe', 'movie']);
assert.deepEqual(mergeLegacyInterests([], ['travel', 'unknown']), ['travel']);
assert.deepEqual(mergeLegacyInterests(['kpop'], null), ['kpop']);

assert.deepEqual(tagIdDiff(['a', 'b'], ['b', 'c']), {added: ['c'], removed: ['a']});

// 글·모임 태그 개수: 생성 +1, 삭제 -1, 숨김 -1, 태그 교체.
const asObj = (m) => Object.fromEntries(m);
assert.deepEqual(asObj(contentTagCountDelta(undefined, {tagIds: ['a', 'b']})), {a: 1, b: 1});
assert.deepEqual(asObj(contentTagCountDelta({tagIds: ['a']}, undefined)), {a: -1});
assert.deepEqual(asObj(contentTagCountDelta({tagIds: ['a']}, {tagIds: ['a'], isHidden: true})), {a: -1});
assert.deepEqual(asObj(contentTagCountDelta({tagIds: ['a', 'b']}, {tagIds: ['b', 'c']})), {a: -1, c: 1});
assert.deepEqual(asObj(contentTagCountDelta({tagIds: ['a'], likes: 1}, {tagIds: ['a'], likes: 2})), {});

console.log('interest tag helper tests passed');
