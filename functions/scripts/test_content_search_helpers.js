#!/usr/bin/env node

const assert = require('assert');
const admin = require('firebase-admin');
const {
  buildPostSearchIndexCore,
  contentAudienceAllows,
  contentMatchesQuery,
  contentSearchLookupTokens,
  contentSearchSourceChanged,
  meetupIsFutureAndPublished,
  normalizeContentSearchText,
} = require('../lib/content_search');
const {
  buildUserSearchTokens,
  extractKoreanInitials,
  matchesUserSearch,
  normalizeUserSearchText,
} = require('../lib/user_search_index');

// User lookup is derived solely from the stored nickname, never from the
// Google/Apple/password provider that created the account.
assert.strictEqual(normalizeUserSearchText('  ＡＢ\u200B C  '), 'ab c');
assert.strictEqual(normalizeUserSearchText('ㄱㅁㅅ'), 'ㄱㅁㅅ');
assert.strictEqual(extractKoreanInitials('김민수'), 'ㄱㅁㅅ');
const userTokens = buildUserSearchTokens('김민수');
for (const token of ['김', '민수', 'ㄱ', 'ㄱㅁ', 'ㅁㅅ']) {
  assert.ok(userTokens.includes(token), `missing user token: ${token}`);
}
assert.strictEqual(matchesUserSearch('김민수', '민수'), true);
assert.strictEqual(matchesUserSearch('김민수', 'ㄱㅁ'), true);
assert.strictEqual(matchesUserSearch('Apple', 'ＡＰＰ'), true);
assert.strictEqual(matchesUserSearch('김민수', 'Google'), false);

assert.strictEqual(
  normalizeContentSearchText('  Ａ\u200BＢ\n\t  Cafe  '),
  'ab cafe',
);
assert.strictEqual(normalizeContentSearchText('가\u0000 나'), '가 나');

const post = buildPostSearchIndexCore({
  title: '한양 카페',
  content: '같이 공부해요',
  authorNickname: 'Apple User',
  isAnonymous: false,
});
for (const token of ['한', '한양', '한양 ', '공부', 'apple user'.slice(0, 3)]) {
  assert.ok(post.tokens.includes(token), `missing token: ${token}`);
}
assert.ok(post.tokenCount > 0);
assert.strictEqual(post.truncated, false);
contentSearchLookupTokens('공부해요').forEach((token) =>
  assert.ok(post.tokens.includes(token), `lookup token missing from index: ${token}`));

const anonymous = buildPostSearchIndexCore({
  title: '제목',
  content: '본문',
  authorNickname: '찾으면안됨',
  isAnonymous: true,
});
assert.strictEqual(anonymous.tokens.includes('찾으'), false);
assert.strictEqual(contentMatchesQuery(['제목', '본문'], '본문'), true);
assert.strictEqual(contentMatchesQuery(['제목', '본문'], '작성자'), false);

const lookup = contentSearchLookupTokens('abcdefgh');
assert.ok(lookup.length >= 1 && lookup.length <= 3);
lookup.forEach((token) => assert.strictEqual(Array.from(token).length, 3));

const basePost = {title: 't', content: 'c', authorNickname: 'n', isAnonymous: false};
assert.strictEqual(
  contentSearchSourceChanged('post', basePost, {...basePost, likes: 1}),
  false,
);
assert.strictEqual(
  contentSearchSourceChanged('post', basePost, {...basePost, content: 'changed'}),
  true,
);
const baseMeetup = {
  title: 't', description: 'd', location: 'l', hostNickname: 'h', host: '',
};
assert.strictEqual(
  contentSearchSourceChanged(
    'meetup',
    baseMeetup,
    {...baseMeetup, currentParticipants: 3, viewCount: 9},
  ),
  false,
);
assert.strictEqual(
  contentSearchSourceChanged('meetup', baseMeetup, {...baseMeetup, location: 'x'}),
  true,
);

const owner = 'owner';
const frozenCategory = {
  ownerId: owner,
  userId: owner,
  visibilityMode: 'category',
  visibility: 'public', // A legacy field must never widen valid frozen data.
  audienceUserIdsFrozen: [owner, 'allowed'],
  allowedUserIds: [owner, 'legacy-allowed'],
  sourceGroupIds: ['group'],
  visibilitySchemaVersion: 2,
  visibilityLockedAt: admin.firestore.Timestamp.now(),
};
assert.strictEqual(contentAudienceAllows('allowed', frozenCategory), true);
assert.strictEqual(contentAudienceAllows('legacy-allowed', frozenCategory), false);
assert.strictEqual(contentAudienceAllows('stranger', frozenCategory), false);

const now = Date.now();
assert.strictEqual(meetupIsFutureAndPublished({
  endsAt: admin.firestore.Timestamp.fromMillis(now + 60_000),
  publicWindowStatus: 'timed',
  publicExpiresAt: admin.firestore.Timestamp.fromMillis(now - 1),
  isConfirmed: false,
}, now), false);
assert.strictEqual(meetupIsFutureAndPublished({
  endsAt: admin.firestore.Timestamp.fromMillis(now + 60_000),
  publicWindowStatus: 'confirmed',
  publicExpiresAt: admin.firestore.Timestamp.fromMillis(now - 1),
  isConfirmed: true,
}, now), true);
assert.strictEqual(meetupIsFutureAndPublished({
  endsAt: admin.firestore.Timestamp.fromMillis(now - 1),
  isConfirmed: true,
}, now), false);

const pathologicalLegacyText = Array.from(
  {length: 13_000},
  (_, index) => String.fromCodePoint(0x10000 + index),
).join('');
const bounded = buildPostSearchIndexCore({
  title: '',
  authorNickname: '',
  isAnonymous: false,
  content: pathologicalLegacyText,
});
assert.ok(bounded.tokenCount <= 32_000);
assert.strictEqual(bounded.truncated, true);

process.stdout.write('content search helper assertions passed\n');
