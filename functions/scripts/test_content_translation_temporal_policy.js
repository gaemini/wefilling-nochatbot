'use strict';

const assert = require('node:assert/strict');
const {
  detectSourceLanguageHint,
  detectTemporalProfile,
  immutableTokens,
  protectImmutableText,
  preservesImmutableTokens,
  restoreImmutableText,
  validateTemporalTranslation,
} = require('../lib/content_translation_policy');

const validTranslations = [
  ['9월 3일', 'September 3', 'ko', 'en'],
  ['2026년 9월 3일', 'September 3, 2026', 'ko', 'en'],
  ['오후 3시', '3 PM', 'ko', 'en'],
  ['오후 3시 20분', '3:20 PM', 'ko', 'en'],
  ['오전 9시 5분', '9:05 AM', 'ko', 'en'],
  ['3시간 20분', '3 hours and 20 minutes', 'ko', 'en'],
  ['5분 후', 'in 5 minutes', 'ko', 'en'],
  ['10초 뒤', 'in 10 seconds', 'ko', 'en'],
  ['3일 동안', 'for three days', 'ko', 'en'],
  ['1박2일 여행', 'a one-night, two-day trip', 'ko', 'en'],
  ['2박 3일 여행', 'a 2-night, 3-day trip', 'ko', 'en'],
  [
    '재민아 중간고사끝나고 1박2일 여행팸 한 번 모아볼까?',
    'Jaemin, shall we get the travel group together for a one-night, two-day trip after midterms?',
    'ko',
    'en',
  ],
  ['두 달 후', 'in two months', 'ko', 'en'],
  ['9월 3일은 안 돼요', "September 3 doesn't work for me", 'ko', 'en'],
  [
    '회의는 9월 3일 오후 2시입니다',
    'The meeting is on September 3 at 2 PM',
    'ko',
    'en',
  ],
  ['September 3 at 2:30 PM', '9월 3일 오후 2시 30분', 'en', 'ko'],
  ['It will take 20 minutes.', '20분 정도 걸립니다.', 'en', 'ko'],
  ["I'll be there in 5 seconds.", '5초 후에 도착할게요.', 'en', 'ko'],
  [
    '9월 3일 오후 2시 https://example.com',
    'September 3 at 2 PM https://example.com',
    'ko',
    'en',
  ],
  ['@jaemin 9월 3일 가능해요?', 'Are you available on September 3, @jaemin?', 'ko', 'en'],
  ['3시까지 15,000원 보내주세요', 'Please send 15,000 won by 3.', 'ko', 'en'],
];

for (const fixture of validTranslations) {
  assert.equal(
    validateTemporalTranslation(...fixture),
    null,
    `temporal semantics should pass: ${fixture[0]}`,
  );
}

for (const text of [
  '서울시에 문의했어요',
  '한 분이 오셨어요',
  '오늘 일이 많아요',
  '달이 밝아요',
  '시를 읽었어요',
]) {
  assert.equal(detectTemporalProfile(text).detected, false, text);
}

for (const text of [
  '9월 3일',
  '2026년 9월 3일',
  '오후 3시 20분',
  '3시간 20분',
  '5분 후',
  '2주 동안',
  '3년 후',
  '2026-09-03 15:20',
  '9.3',
  '1박2일',
]) {
  const protectedValue = protectImmutableText(text);
  assert.equal(protectedValue.text, text, `temporal text must stay visible: ${text}`);
  assert.equal(Object.keys(protectedValue.tokens).length, 0);
  if (/[가-힣]/u.test(text)) {
    assert.equal(detectSourceLanguageHint(text), 'ko');
  }
}

const immutableFixtures = [
  'https://example.com/9/3',
  'hello@example.com',
  '@user_3',
  '#9월3일모임',
  '010-1234-5678',
  'ChIJN1t_tDeuEmsRUsoyG83frY4',
  'report_v3.pdf',
  'v1.3.9',
  'room_A12',
  '🙂',
];
for (const text of immutableFixtures) {
  const protectedValue = protectImmutableText(text);
  assert.notEqual(protectedValue.text, text, `must protect ${text}`);
  assert.ok(immutableTokens(text).length >= 1, text);
  assert.equal(restoreImmutableText(protectedValue.text, protectedValue), text);
}

assert.equal(
  validateTemporalTranslation('오후 3시', '3 AM', 'ko', 'en'),
  'TEMPORAL_DAY_PERIOD_MISMATCH',
);
assert.equal(
  validateTemporalTranslation('오후 3시', 'at 3', 'ko', 'en'),
  'TEMPORAL_DAY_PERIOD_MISMATCH',
);
assert.equal(
  validateTemporalTranslation('오후 3시', 'at 3 P.M.', 'ko', 'en'),
  null,
);
assert.equal(
  validateTemporalTranslation('오후 3시', 'at 15:00', 'ko', 'en'),
  null,
);
assert.equal(
  validateTemporalTranslation('오후 3시', '4 PM', 'ko', 'en'),
  'TEMPORAL_VALUE_MISMATCH',
);
assert.equal(
  validateTemporalTranslation('9월 3일', '9월 3일', 'ko', 'en'),
  'UNTRANSLATED_TEMPORAL_UNIT',
);
assert.deepEqual(
  immutableTokens('3시까지 15,000원 보내주세요'),
  immutableTokens('Please send 15,000 won by 3.'),
);
assert.deepEqual(
  immutableTokens('@jaemin 9월 3일 가능해요?'),
  immutableTokens('Are you available on September 3, @jaemin?'),
);
assert.deepEqual(
  immutableTokens('9월 3일 오후 2시 https://example.com'),
  immutableTokens('September 3 at 2 PM https://example.com'),
);
assert.deepEqual(
  immutableTokens('1박2일 여행'),
  immutableTokens('a one-night, two-day trip'),
);
assert.deepEqual(
  immutableTokens('2박 3일 여행'),
  immutableTokens('a 2-night, 3-day trip'),
);

// Natural text remains visible as one coherent sentence. This deliberately
// covers categories rather than adding one protected-span exception per word.
for (const text of [
  '년 월 주 일 시 분 초',
  '오늘 내일 어제 이번 주 다음 주 이번 달 다음 달 작년 내년',
  '3명 2개 한 명 두 명',
  '3시간 10분 30초 세 시간 몇 분',
  '6시 반 10시쯤 6시까지 10분 전',
  '2번 세 번 주 2회 하루 한 번 하루 3번',
  '9월 10일 목요일',
  '1박 2일 2박 3일 당일치기 3일간 2주 동안',
  '1~3명 10시~12시 월~금',
  '1학년 2학년 1차 2차 첫 번째 3번째',
  '202호 3층 제1학술관 정문 앞',
  '10,000원 3만원 무료 ₩15,000',
  '5km 10kg 500m',
  '50% 4.5점 3대2',
  '9/10(목) 18:00 오후 6시 30분 D-3 3일째',
  '이번 주 토요일 오후 6시에 3명이서 1박 2일로 부산에 가자',
  '내일 6시에 확인해줘',
  '37.5665, 126.9780에서 만나자',
  '12pm',
  '20mins',
  '2-weeks',
  '21st',
  'Sep3',
  '10kg',
  '180cm',
]) {
  assert.deepEqual(immutableTokens(text), [], `must remain translatable: ${text}`);
  assert.equal(protectImmutableText(text).text, text, text);
}

// Only explicit machine data and code-like identifiers are preserved.
for (const text of [
  'room_A12',
  'userId=abc_123',
  'ChIJN1t_tDeuEmsRUsoyG83frY4',
  '550e8400-e29b-41d4-a716-446655440000',
  'v1.3.9',
  '/Users/shared/report.pdf',
]) {
  assert.ok(immutableTokens(text).length > 0, `must remain immutable: ${text}`);
}

// Internal marker-looking user text used to collide with placeholders and
// fail forever. Marker selection is now collision-safe for arbitrary input.
for (const text of [
  'literal __WF_KEEP_0__ text 🙂',
  '__WF_KEEP_0__ and __WF1_KEEP_0__ with https://example.com',
  'symbols \u0000 \u2028 \u2029 <> [] {} | \\ ^ 🇰🇷 1️⃣',
  'code `const room_A12 = 1;` must stay exact',
  '```js\nconst room_A12 = 1;\n```',
]) {
  const protectedValue = protectImmutableText(text);
  assert.equal(
    restoreImmutableText(protectedValue.text, protectedValue),
    text,
    `round trip must be exact: ${JSON.stringify(text)}`,
  );
}

assert.ok(immutableTokens('🇰🇷').length > 0, 'flag emoji is protected');
assert.ok(immutableTokens('1️⃣').length > 0, 'keycap emoji is protected');
assert.ok(immutableTokens('`const x = 1;`').length > 0, 'inline code is protected');

const contextualProtection = protectImmutableText(
  '내일 6시에 https://example.com에서 test@example.com으로 확인해줘',
);
assert.equal(Object.keys(contextualProtection.tokens).length, 2);
assert.ok(contextualProtection.text.startsWith('내일 6시에 '));
assert.ok(contextualProtection.text.includes('에서 '));
assert.ok(contextualProtection.text.endsWith('으로 확인해줘'));
assert.equal(
  restoreImmutableText(contextualProtection.text, contextualProtection),
  '내일 6시에 https://example.com에서 test@example.com으로 확인해줘',
);

for (const text of [
  '010-1234-5678로 전화해줘',
  'report_v3.pdf를 확인해줘',
  'v1.3.9를 설치해줘',
]) {
  const protectedValue = protectImmutableText(text);
  assert.equal(Object.keys(protectedValue.tokens).length, 1, text);
  assert.equal(restoreImmutableText(protectedValue.text, protectedValue), text);
}

// Natural target-language address and ordinal words may look like generated
// identifiers. They must not invalidate an otherwise complete translation.
const addressSource = [
  '디저트가 맛이 없으면 사장님을 때릴 수 있는 카페가 있다?!',
  '- butt(버트 카페)',
  '- 정조로 900번길 13 1층',
  '- 수원성 근처 카페(추천!)',
].join('\n');
const addressTranslation = [
  "There's a cafe where you can hit the owner if the dessert is bad?!",
  '- butt (Butt Cafe)',
  '- 1st floor, 13 Jeongjo-ro 900beon-gil',
  '- Cafe near Suwon Fortress (recommended!)',
].join('\n');
assert.equal(
  preservesImmutableTokens(addressSource, addressTranslation),
  true,
  'translated addresses and ordinals are natural text, not immutable IDs',
);

// Existing source-side identifiers still have to survive exactly and in order.
assert.equal(
  preservesImmutableTokens(
    'room_A12에서 report_v3.pdf 확인',
    'Check report_v3.pdf in room_A12',
  ),
  false,
  'source identifiers cannot be reordered',
);
assert.equal(
  preservesImmutableTokens(
    'room_A12에서 report_v3.pdf 확인',
    'Check room_A12 and report_v3.pdf on the 1st floor',
  ),
  true,
  'source identifiers remain exact while natural target tokens are allowed',
);

console.log('content translation temporal policy tests passed');
