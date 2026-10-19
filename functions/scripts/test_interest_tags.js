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
  pickTrendingTags,
  tagNotificationCopy,
  contentAudienceIncludes,
  tagAudienceEnabled,
  tagAudienceAllows,
  OFFICIAL_INTEREST_TAGS,
  OFFICIAL_TAG_IDS,
  MAX_PROFILE_TAGS,
  normalizeTagDescription,
  normalizeTagCategory,
  countFriendTags,
  rankOverlapPeople,
  overlapTagCounts,
  nextHiddenSuggestions,
  OFFICIAL_TAG_STYLE,
  officialTagFields,
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

// 뜨는 태그: 7일 증가 순, 7일 전 기록이 없으면 비움.
const nowMs = Date.UTC(2026, 9, 16);
const current = new Map([
  ['a', {count: 10, createdAtMillis: 0}],
  ['b', {count: 5, createdAtMillis: nowMs - 86400000}],
  ['c', {count: 3, createdAtMillis: 0}],
]);
assert.deepEqual(pickTrendingTags(current, {a: 9, b: 0, c: 3}), [{id: 'b', delta: 5}, {id: 'a', delta: 1}]);
assert.deepEqual(pickTrendingTags(current, null), []);
void nowMs;

// 알림 문구(ko/en/zh).
assert.equal(tagNotificationCopy('ko', 'post', '러닝', 3).message, '#러닝에 새 글 3개');
assert.equal(tagNotificationCopy('en', 'meetup', 'Running', 1).message, '1 new meetup in #Running');
assert.equal(tagNotificationCopy('zh-Hans', 'post', '跑步', 2).message, '#跑步 有 2 篇新帖子');

// 알림 대상의 공개 범위 확인.
assert.equal(contentAudienceIncludes('u', {visibility: 'public'}), true);
assert.equal(contentAudienceIncludes('u', {visibility: 'friends', visibilitySchemaVersion: 2, audienceUserIdsFrozen: ['o']}), false);
assert.equal(contentAudienceIncludes('u', {visibility: 'category', visibilitySchemaVersion: 2, audienceUserIdsFrozen: ['o', 'u']}), true);

// 플래그·태그 공개 판정.
assert.equal(tagAudienceEnabled({}), false);
assert.equal(tagAudienceEnabled({TAG_AUDIENCE_ENABLED: 'true'}), true);
assert.equal(tagAudienceAllows(['a'], {visibility: 'tag', audienceTagIds: ['a', 'b']}), true);
assert.equal(tagAudienceAllows(['c'], {visibility: 'tag', audienceTagIds: ['a']}), false);
assert.equal(tagAudienceAllows(['a'], {visibility: 'public', audienceTagIds: ['a']}), false);

// 태그 설명: 공백 정리, 40자, 금칙어 거부, 공식 태그는 모두 3개 언어 설명.
assert.equal(normalizeTagDescription('  주말마다\n한강에서   같이 뛰어요 '), '주말마다 한강에서 같이 뛰어요');
assert.equal(normalizeTagDescription(undefined), '');
assert.equal(Array.from(normalizeTagDescription('가'.repeat(60))).length, 40);
assert.throws(() => normalizeTagDescription('위필링 운영자입니다'), /tag-blocked/);
assert.throws(() => normalizeTagDescription(3), /tag-description-invalid/);
for (const tag of OFFICIAL_INTEREST_TAGS) {
  assert.ok(tag.description.ko && tag.description.en && tag.description.zh, tag.id);
}

// 분류·이모지: 허용 값만, 공식 태그는 모두 분류가 있다.
assert.equal(normalizeTagCategory('food'), 'food');
assert.equal(normalizeTagCategory('FOOD'), 'etc');
assert.equal(normalizeTagCategory(undefined), 'etc');
for (const tag of OFFICIAL_INTEREST_TAGS) {
  assert.ok(OFFICIAL_TAG_STYLE[tag.id], tag.id);
  const fields = officialTagFields(tag);
  assert.notEqual(fields.category, 'etc', tag.id);
  assert.ok(fields.emoji, tag.id);
}
assert.equal(officialTagFields(OFFICIAL_INTEREST_TAGS.find((t) => t.id === 'game')).category, 'play');

// 관심 탭: 친구들이 단 태그 수, 겹침 순위(겹침 많은 순 → 친구 먼저), scope.
assert.deepEqual(countFriendTags([['a', 'b'], ['a'], ['c', 'a', 'a']]),
  [{id: 'a', friendHolders: 3}, {id: 'b', friendHolders: 1}, {id: 'c', friendHolders: 1}]);
const people = [
  {uid: 'p1', tags: ['a'], isFriend: false},
  {uid: 'p2', tags: ['a'], isFriend: true},
  {uid: 'p3', tags: ['a', 'b'], isFriend: false},
  {uid: 'p4', tags: ['z'], isFriend: true},
];
assert.deepEqual(rankOverlapPeople(people, ['a', 'b'], 'all').map((p) => p.uid), ['p3', 'p2', 'p1']);
assert.deepEqual(rankOverlapPeople(people, ['a', 'b'], 'friends').map((p) => p.uid), ['p2']);
assert.deepEqual(rankOverlapPeople(people, ['a', 'b'], 'others').map((p) => p.uid), ['p3', 'p1']);
assert.deepEqual(rankOverlapPeople(people, ['a', 'b'], 'all')[0].overlapTagIds, ['a', 'b']);

// v6: 같은 겹침이면 친구 → 최근 활동 → uid, 칩 숫자, 숨김 목록 최신 300.
assert.deepEqual(rankOverlapPeople([
  {uid: 'z', tags: ['a'], isFriend: false, lastActiveMillis: 5},
  {uid: 'y', tags: ['a'], isFriend: false, lastActiveMillis: 9},
  {uid: 'x', tags: ['a'], isFriend: false},
], ['a'], 'all').map((p) => p.uid), ['y', 'z', 'x']);
assert.deepEqual(overlapTagCounts([{overlapTagIds: ['a', 'b']}, {overlapTagIds: ['a']}]), {a: 2, b: 1});
assert.deepEqual(nextHiddenSuggestions(['a', 'b'], 'a', true), ['b', 'a']);
assert.deepEqual(nextHiddenSuggestions(['a', 'b'], 'a', false), ['b']);
const many = Array.from({length: 300}, (_, i) => `u${i}`);
const capped = nextHiddenSuggestions(many, 'new', true);
assert.equal(capped.length, 300);
assert.equal(capped[0], 'u1');
assert.equal(capped[299], 'new');

console.log('interest tag helper tests passed');
