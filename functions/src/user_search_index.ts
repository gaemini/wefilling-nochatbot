const MAX_INDEXED_NAME_LENGTH = 40;

const LEADING_JAMO_TO_COMPATIBILITY = new Map<string, string>([
  ['ᄀ', 'ㄱ'], ['ᄁ', 'ㄲ'], ['ᄂ', 'ㄴ'], ['ᄃ', 'ㄷ'], ['ᄄ', 'ㄸ'],
  ['ᄅ', 'ㄹ'], ['ᄆ', 'ㅁ'], ['ᄇ', 'ㅂ'], ['ᄈ', 'ㅃ'], ['ᄉ', 'ㅅ'],
  ['ᄊ', 'ㅆ'], ['ᄋ', 'ㅇ'], ['ᄌ', 'ㅈ'], ['ᄍ', 'ㅉ'], ['ᄎ', 'ㅊ'],
  ['ᄏ', 'ㅋ'], ['ᄐ', 'ㅌ'], ['ᄑ', 'ㅍ'], ['ᄒ', 'ㅎ'],
]);

function removeControlAndZeroWidth(value: string): string {
  return Array.from(value).filter((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    return !(
      codePoint <= 0x1f ||
      (codePoint >= 0x7f && codePoint <= 0x9f) ||
      (codePoint >= 0x200b && codePoint <= 0x200d) ||
      codePoint === 0x2060 ||
      codePoint === 0xfeff
    );
  }).join('');
}

/** Normalizes display text without depending on an authentication provider. */
export function normalizeUserSearchText(raw: unknown): string {
  // Nickname identity uses NFKC, so search must do the same for full-width
  // letters and other compatibility forms. NFKC converts typed Korean
  // initials (ㄱ) to leading jamo (ᄀ); map those modern initials back so the
  // existing choseong index remains searchable.
  const compatible = Array.from(String(raw ?? '').normalize('NFKC'))
    .map((character) => LEADING_JAMO_TO_COMPATIBILITY.get(character) ?? character)
    .join('');
  return removeControlAndZeroWidth(compatible)
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

/** Returns the Korean initial-consonant representation used by the old app. */
export function extractKoreanInitials(raw: unknown): string {
  const initials = [
    'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ',
    'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
  ];
  return Array.from(normalizeUserSearchText(raw)).map((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    if (codePoint < 0xac00 || codePoint > 0xd7a3) return character;
    return initials[Math.floor((codePoint - 0xac00) / (21 * 28))] ?? character;
  }).join('');
}

function addSubstrings(tokens: Set<string>, source: string): void {
  const characters = Array.from(source).slice(0, MAX_INDEXED_NAME_LENGTH);
  for (let start = 0; start < characters.length; start++) {
    for (let end = start + 1; end <= characters.length; end++) {
      tokens.add(characters.slice(start, end).join(''));
    }
  }
}

/**
 * Builds exact lookup terms for the current substring and Korean-initial UX.
 * A valid nickname is at most 20 characters; the larger cap only supports
 * old profiles safely without allowing an unbounded Firestore array.
 */
export function buildUserSearchTokens(raw: unknown): string[] {
  const normalized = normalizeUserSearchText(raw);
  if (!normalized) return [];
  const tokens = new Set<string>();
  addSubstrings(tokens, normalized);
  const initials = extractKoreanInitials(normalized);
  if (initials !== normalized) addSubstrings(tokens, initials);
  return Array.from(tokens).sort();
}

export function matchesUserSearch(rawName: unknown, rawQuery: unknown): boolean {
  const name = normalizeUserSearchText(rawName);
  const query = normalizeUserSearchText(rawQuery);
  if (!name || !query) return false;
  return name.includes(query) || extractKoreanInitials(name).includes(query);
}

export function userSearchRelevance(rawName: unknown, rawQuery: unknown): number {
  const name = normalizeUserSearchText(rawName);
  const query = normalizeUserSearchText(rawQuery);
  if (!name || !query) return 0;
  let score = 0;
  if (name === query) score += 100;
  if (name.startsWith(query)) score += 50;
  if (name.includes(query)) score += 25;
  if (extractKoreanInitials(name).includes(query)) score += 10;
  return score;
}
