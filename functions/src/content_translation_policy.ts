export type ProtectedText = {
  text: string;
  tokens: Record<string, string>;
};

export type TemporalExpressionType =
  'date' | 'clock_time' | 'duration' | 'relative_time' | 'day_period';

type TemporalValueRole =
  'year' | 'month' | 'day' | 'hour' | 'minute' | 'duration';

type TemporalValue = {
  value: number;
  role: TemporalValueRole;
};

export type TemporalProfile = {
  detected: boolean;
  types: TemporalExpressionType[];
  values: TemporalValue[];
  dayPeriod: 'am' | 'pm' | '';
};

export type TemporalValidationFailureCode =
  'UNTRANSLATED_TEMPORAL_UNIT' |
  'TEMPORAL_VALUE_MISMATCH' |
  'TEMPORAL_DAY_PERIOD_MISMATCH';

// Only values whose spelling must remain byte-for-byte stable belong here.
// Natural-language dates, times and durations intentionally do not.
export const IMMUTABLE_TEXT_PATTERN = new RegExp([
  '(?:https?://|www\\.)[^\\s]+',
  '[\\p{L}\\p{N}._%+\\-]+@[\\p{L}\\p{N}.\\-]+\\.[\\p{L}]{2,}',
  '@[\\p{L}\\p{N}_.\\-]+',
  '#[\\p{L}\\p{N}_.\\-]+',
  '\\bChIJ[A-Za-z0-9_\\-]+\\b',
  '(?:place[_ ]?id\\s*[:=]\\s*)[A-Za-z0-9_\\-]+',
  '-?\\d{1,3}\\.\\d+\\s*[,/]\\s*-?\\d{1,3}\\.\\d+',
  '(?<![\\p{L}\\p{N}])(?:\\+\\d{1,3}[ .-]?)?\\d{2,4}[- ]\\d{3,4}[- ]\\d{4}(?![\\p{L}\\p{N}])',
  '[$€£¥₩]\\s?\\d+(?:[.,]\\d+)*',
  '\\d+(?:[.,]\\d+)*\\s?%',
  '\\d+(?:,\\d{3})*(?:\\.\\d+)?(?=\\s*(?:원|달러|유로|엔|위안|won|dollars?|euros?|yen|yuan))',
  '\\bv\\d+(?:\\.\\d+){1,3}(?:[-+][A-Za-z0-9.\\-]+)?\\b',
  '\\b[\\p{L}\\p{N}][\\p{L}\\p{N}_.\\-]*\\.(?:pdf|docx?|xlsx?|pptx?|zip|png|jpe?g|gif|webp|heic|mp4|mov|txt|csv)\\b',
  // Natural translated durations such as "2-day" and "1-night" are not
  // identifiers. Without this exclusion, a valid Korean "1박2일" translation
  // creates new immutable tokens and is rejected on every retry.
  '(?!(?:\\d+)-(?:second|minute|hour|day|night|week|month|year)s?\\b)\\b(?=[A-Za-z0-9_\\-]{4,}\\b)(?=[A-Za-z0-9_\\-]*[A-Za-z])(?=[A-Za-z0-9_\\-]*\\d)[A-Za-z0-9]+(?:[_\\-][A-Za-z0-9]+)*\\b',
  '\\p{Extended_Pictographic}(?:\\uFE0F|\\p{Emoji_Modifier}|\\u200D\\p{Extended_Pictographic})*',
].join('|'), 'giu');

const KOREAN_NUMBER_WORDS: Record<string, number> = {
  '한': 1,
  '두': 2,
  '세': 3,
  '네': 4,
  '다섯': 5,
  '여섯': 6,
  '일곱': 7,
  '여덟': 8,
  '아홉': 9,
  '열': 10,
};

const ENGLISH_NUMBER_WORDS: Record<number, string[]> = {
  1: ['one', 'first'],
  2: ['two', 'second'],
  3: ['three', 'third'],
  4: ['four', 'fourth'],
  5: ['five', 'fifth'],
  6: ['six', 'sixth'],
  7: ['seven', 'seventh'],
  8: ['eight', 'eighth'],
  9: ['nine', 'ninth'],
  10: ['ten', 'tenth'],
  11: ['eleven', 'eleventh'],
  12: ['twelve', 'twelfth'],
  13: ['thirteen', 'thirteenth'],
  14: ['fourteen', 'fourteenth'],
  15: ['fifteen', 'fifteenth'],
  16: ['sixteen', 'sixteenth'],
  17: ['seventeen', 'seventeenth'],
  18: ['eighteen', 'eighteenth'],
  19: ['nineteen', 'nineteenth'],
  20: ['twenty', 'twentieth'],
};

const ENGLISH_MONTHS = [
  '', 'january', 'february', 'march', 'april', 'may', 'june', 'july',
  'august', 'september', 'october', 'november', 'december',
];

function uniqueValues(values: TemporalValue[]): TemporalValue[] {
  const seen = new Set<string>();
  return values.filter((value) => {
    const key = `${value.role}:${value.value}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function numberValue(raw: string): number | null {
  if (/^\d+$/.test(raw)) return Number(raw);
  return KOREAN_NUMBER_WORDS[raw] ?? null;
}

function pushType(
  types: TemporalExpressionType[],
  type: TemporalExpressionType,
): void {
  if (!types.includes(type)) types.push(type);
}

export function detectSourceLanguageHint(value: string): string {
  if (/[가-힣]/u.test(value)) return 'ko';
  if (/[ぁ-んァ-ン]/u.test(value)) return 'ja';
  if (/[Ѐ-ӿ]/u.test(value)) return 'ru';
  if (/[؀-ۿ]/u.test(value)) return 'ar';
  if (/[฀-๿]/u.test(value)) return 'th';
  return '';
}

export function detectTemporalProfile(value: string): TemporalProfile {
  const types: TemporalExpressionType[] = [];
  const values: TemporalValue[] = [];
  const clockRanges: Array<{start: number; end: number}> = [];
  let dayPeriod: 'am' | 'pm' | '' = '';

  const koreanDate = /(\d{2,4})\s*년(?:\s*(\d{1,2})\s*월)?(?:\s*(\d{1,2})\s*일)?|(?<!\d)(\d{1,2})\s*월(?:\s*(\d{1,2})\s*일)?/gu;
  for (const match of value.matchAll(koreanDate)) {
    pushType(types, 'date');
    if (match[1]) values.push({value: Number(match[1]), role: 'year'});
    if (match[2]) values.push({value: Number(match[2]), role: 'month'});
    if (match[3]) values.push({value: Number(match[3]), role: 'day'});
    if (match[4]) values.push({value: Number(match[4]), role: 'month'});
    if (match[5]) values.push({value: Number(match[5]), role: 'day'});
  }
  const koreanStandaloneDay = /(?<![월박\d])(\d{1,2})\s*일(?=\s*(?:은|는|에|까지|부터|동안|후|뒤|전|입니다|이에요|예요|$))/gu;
  for (const match of value.matchAll(koreanStandaloneDay)) {
    const before = value.slice(0, match.index);
    if (/월\s*$/u.test(before)) continue;
    const tail = value.slice(
      match.index,
      match.index + match[0].length + 4,
    );
    const isDuration = /(?:동안|후|뒤|전)/u.test(tail);
    pushType(types, isDuration ? 'duration' : 'date');
    values.push({
      value: Number(match[1]),
      role: isDuration ? 'duration' : 'day',
    });
  }

  // Common compact trip duration: 1박2일, 2박 3일, 한 박 두 일.
  // Treat both numbers as duration values so the quality guard can verify a
  // natural result such as "one-night, two-day" instead of rejecting it as an
  // unexplained identifier change.
  const koreanOvernightDuration = /(\d+|한|두|세|네|다섯|여섯|일곱|여덟|아홉|열)\s*박\s*(\d+|한|두|세|네|다섯|여섯|일곱|여덟|아홉|열)\s*일/gu;
  for (const match of value.matchAll(koreanOvernightDuration)) {
    const nights = numberValue(match[1]);
    const days = numberValue(match[2]);
    if (nights == null || days == null) continue;
    pushType(types, 'duration');
    values.push({value: nights, role: 'duration'});
    values.push({value: days, role: 'duration'});
  }

  const koreanClock = /(?:(오전|오후)\s*)?(\d{1,2})\s*시(?!간)(?:\s*(\d{1,2})\s*분)?/gu;
  for (const match of value.matchAll(koreanClock)) {
    clockRanges.push({
      start: match.index,
      end: match.index + match[0].length,
    });
    pushType(types, 'clock_time');
    values.push({value: Number(match[2]), role: 'hour'});
    if (match[3]) values.push({value: Number(match[3]), role: 'minute'});
    if (match[1]) {
      dayPeriod = match[1] === '오전' ? 'am' : 'pm';
      pushType(types, 'day_period');
    }
  }

  const koreanDuration = /(\d+|한|두|세|네|다섯|여섯|일곱|여덟|아홉|열)\s*(시간|분|초|일|개월|달)(?=\s*(?:동안|후|뒤|전|정도|이내|만에|걸|소요|(?:\d+|한|두|세|네|다섯|여섯|일곱|여덟|아홉|열)\s*(?:시간|분|초|일|개월|달)|$))/gu;
  for (const match of value.matchAll(koreanDuration)) {
    if (clockRanges.some((range) =>
      match.index >= range.start && match.index < range.end
    )) continue;
    const parsed = numberValue(match[1]);
    if (parsed == null) continue;
    const before = value.slice(0, match.index);
    if (match[2] === '일' && /월\s*$/u.test(before)) continue;
    pushType(types, 'duration');
    if (/(?:후|뒤|전)/u.test(value.slice(match.index, match.index + match[0].length + 4))) {
      pushType(types, 'relative_time');
    }
    values.push({value: parsed, role: 'duration'});
  }

  const englishMonthPattern = new RegExp(
    `\\b(${ENGLISH_MONTHS.slice(1).join('|')})\\s+(\\d{1,2})(?:,?\\s+(\\d{4}))?`,
    'giu',
  );
  for (const match of value.matchAll(englishMonthPattern)) {
    pushType(types, 'date');
    values.push({
      value: ENGLISH_MONTHS.indexOf(match[1].toLowerCase()),
      role: 'month',
    });
    values.push({value: Number(match[2]), role: 'day'});
    if (match[3]) values.push({value: Number(match[3]), role: 'year'});
  }
  const englishClock = /\b(\d{1,2})(?::(\d{2}))?\s*(AM|PM)\b/giu;
  for (const match of value.matchAll(englishClock)) {
    pushType(types, 'clock_time');
    pushType(types, 'day_period');
    values.push({value: Number(match[1]), role: 'hour'});
    if (match[2]) values.push({value: Number(match[2]), role: 'minute'});
    dayPeriod = match[3].toLowerCase() === 'am' ? 'am' : 'pm';
  }
  const englishDuration = /\b(?:in\s+|for\s+|take\w*\s+)?(\d+)\s+(seconds?|minutes?|hours?|days?|months?)\b/giu;
  for (const match of value.matchAll(englishDuration)) {
    pushType(types, 'duration');
    if (/^in\s+/iu.test(match[0])) pushType(types, 'relative_time');
    values.push({value: Number(match[1]), role: 'duration'});
  }

  return {
    detected: types.length > 0,
    types,
    values: uniqueValues(values),
    dayPeriod,
  };
}

function containsNumber(
  translated: string,
  targetLanguage: string,
  value: number,
): boolean {
  if (new RegExp(`(?<!\\d)0*${value}(?!\\d)`, 'u').test(translated)) {
    return true;
  }
  if (targetLanguage === 'en') {
    return (ENGLISH_NUMBER_WORDS[value] ?? []).some((word) =>
      new RegExp(`\\b${word}\\b`, 'iu').test(translated)
    );
  }
  if (targetLanguage === 'ko') {
    return Object.entries(KOREAN_NUMBER_WORDS).some(([word, number]) =>
      number === value && translated.includes(word)
    );
  }
  return false;
}

function containsMonth(
  translated: string,
  targetLanguage: string,
  value: number,
): boolean {
  if (containsNumber(translated, targetLanguage, value)) return true;
  return targetLanguage === 'en' &&
    new RegExp(`\\b${ENGLISH_MONTHS[value]}\\b`, 'iu').test(translated);
}

function hasUntranslatedTemporalUnit(
  translated: string,
  sourceLanguage: string,
  targetLanguage: string,
): boolean {
  if (sourceLanguage === 'ko' && targetLanguage !== 'ko') {
    return /(?:\d|한|두|세|네|다섯|여섯|일곱|여덟|아홉|열)\s*(?:년|월|일|박|시|분|초|시간|개월|달)|오전|오후/u
      .test(translated);
  }
  if (sourceLanguage === 'en' && targetLanguage === 'ko') {
    return /\b(?:AM|PM|january|february|march|april|may|june|july|august|september|october|november|december|seconds?|minutes?|hours?|days?|months?)\b/iu
      .test(translated);
  }
  return false;
}

function hasExpectedDayPeriod(
  translated: string,
  targetLanguage: string,
  profile: TemporalProfile,
): boolean {
  if (!profile.dayPeriod || (targetLanguage !== 'en' &&
      targetLanguage !== 'ko')) {
    return true;
  }
  const expected = profile.dayPeriod === 'am' ?
    /\bA\.?M\.?\b|morning|오전/iu :
    /\bP\.?M\.?\b|afternoon|evening|오후/iu;
  if (expected.test(translated)) return true;
  const hour = profile.values.find((entry) => entry.role === 'hour')?.value;
  if (hour == null) return false;
  const converted = profile.dayPeriod === 'pm' ?
    (hour % 12) + 12 : hour === 12 ? 0 : hour;
  return new RegExp(`(?<!\\d)0*${converted}:\\d{2}(?!\\d)`, 'u')
    .test(translated);
}

export function validateTemporalTranslation(
  source: string,
  translated: string,
  sourceLanguage: string,
  targetLanguage: string,
): TemporalValidationFailureCode | null {
  const profile = detectTemporalProfile(source);
  if (!profile.detected || sourceLanguage === targetLanguage) return null;
  if (hasUntranslatedTemporalUnit(
    translated,
    sourceLanguage,
    targetLanguage,
  )) {
    return 'UNTRANSLATED_TEMPORAL_UNIT';
  }

  // English and Korean have deterministic numeric/number-word checks here.
  // Other supported languages may naturally spell values as words; rejecting
  // them without a full locale grammar would create false failures.
  if (targetLanguage === 'en' || targetLanguage === 'ko') {
    for (const entry of profile.values) {
      if (entry.role === 'hour' && profile.dayPeriod === 'pm' &&
          containsNumber(translated, targetLanguage, entry.value + 12)) {
        continue;
      }
      const found = entry.role === 'month' ?
        containsMonth(translated, targetLanguage, entry.value) :
        containsNumber(translated, targetLanguage, entry.value);
      if (!found) return 'TEMPORAL_VALUE_MISMATCH';
    }
  }

  if (profile.dayPeriod === 'am' &&
      /\bPM\b|afternoon|evening|오후/iu.test(translated)) {
    return 'TEMPORAL_DAY_PERIOD_MISMATCH';
  }
  if (profile.dayPeriod === 'pm' &&
      /\bAM\b|morning|오전/iu.test(translated)) {
    return 'TEMPORAL_DAY_PERIOD_MISMATCH';
  }
  if (!hasExpectedDayPeriod(translated, targetLanguage, profile)) {
    return 'TEMPORAL_DAY_PERIOD_MISMATCH';
  }
  return null;
}

export function immutableTokens(value: string): string[] {
  return value.match(IMMUTABLE_TEXT_PATTERN) ?? [];
}

export function preservesImmutableTokens(
  source: string,
  translated: string,
): boolean {
  const sourceTokens = immutableTokens(source);
  const translatedTokens = immutableTokens(translated);
  // This pattern's bare numeric tokens are amounts before currency words.
  // Translating "오천원 / 5천원" to "5,000 won" legitimately creates such a
  // token. Re-detecting it as a new immutable identifier rejects valid posts.
  // Keep every original numeric token; don't forbid amounts spelled out in
  // the source from becoming digits. Other protected values remain exact.
  const isAmount = (token: string): boolean => /^\d[\d,.]*$/.test(token);
  // Currency words may be localized (won, KRW, etc.). Validate the protected
  // digits themselves instead of requiring the translated currency to match
  // the source-side token detector's vocabulary.
  const translatedNumbers = translated.match(/\d+(?:,\d{3})*(?:\.\d+)?/g) ?? [];
  for (const token of new Set(sourceTokens.filter(isAmount))) {
    if (translatedNumbers.filter((value) => value === token).length <
        sourceTokens.filter((value) => value === token).length) return false;
  }
  const sourceIdentifiers = sourceTokens.filter((token) => !isAmount(token));
  const translatedIdentifiers = translatedTokens
    .filter((token) => !isAmount(token));
  // Only source-side identifiers are immutable. A natural translation can
  // legitimately create an alphanumeric word that resembles an identifier
  // to this broad detector (for example Korean addresses become
  // "900beon-gil" and floors become "1st"). Requiring both token lists to be
  // identical rejected those otherwise complete translations forever.
  //
  // The prompt placeholders already guarantee that every original protected
  // value is restored byte-for-byte. Here we additionally retain their order,
  // while allowing target-language words that merely look identifier-like.
  let translatedIndex = 0;
  for (const sourceIdentifier of sourceIdentifiers) {
    while (translatedIndex < translatedIdentifiers.length &&
        translatedIdentifiers[translatedIndex] !== sourceIdentifier) {
      translatedIndex++;
    }
    if (translatedIndex >= translatedIdentifiers.length) return false;
    translatedIndex++;
  }
  return true;
}

export function protectImmutableText(value: string): ProtectedText {
  let index = 0;
  const tokens: Record<string, string> = {};
  let text = value
    .replace(/\r\n?/g, '\n')
    .replace(IMMUTABLE_TEXT_PATTERN, (match) => {
      const token = `__WF_KEEP_${index++}__`;
      tokens[token] = match;
      return token;
    });
  text = text.replace(/\n/g, () => {
    const token = `__WF_KEEP_${index++}__`;
    tokens[token] = '\n';
    return token;
  });
  return {text, tokens};
}

export function restoreImmutableText(
  value: string,
  protectedText: ProtectedText,
): string | null {
  let restored = value;
  for (const [token, original] of Object.entries(protectedText.tokens)) {
    if (restored.split(token).length - 1 !== 1) return null;
    restored = restored.split(token).join(original);
  }
  if (/__WF_KEEP_\d+__/.test(restored)) return null;
  return restored;
}
