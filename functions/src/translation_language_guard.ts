// functions/src/translation_language_guard.ts
//
// 번역 결과가 "요청한 대상 언어"로 쓰였는지 확인하는 순수 함수 모음.
//
// 배경: Gemini가 대상 언어 대신 영어나 원문 언어로 답하거나, 비슷한 라틴 문자
// 언어(스페인어↔포르투갈어 등)를 같은 언어로 오판하는 경우가 있었다. 기존 검증은
// 길이·토큰·시간 표현만 봐서 이런 결과가 그대로 통과하고 캐시에 고정됐다.
//
// 설계 원칙
// - 오탐(올바른 번역을 거부)이 미탐보다 비싸다. 글자 종류가 대상 언어와 명백히
//   다른 경우와, 다른 라틴 언어가 압도적인 경우만 거부한다.
// - 짧은 문장·고유명사 위주의 문장은 판단하지 않는다.

import {IMMUTABLE_TEXT_PATTERN} from './content_translation_policy';

const SCRIPT = {
  hangul: /[ᄀ-ᇿ㄰-㆏가-힯]/gu,
  kana: /[぀-ヿㇰ-ㇿ]/gu,
  han: /[㐀-䶿一-鿿]/gu,
  cyrillic: /[Ѐ-ӿ]/gu,
  arabic: /[؀-ۿݐ-ݿ]/gu,
  thai: /[฀-๿]/gu,
  devanagari: /[ऀ-ॿ]/gu,
  latin: /[A-Za-zÀ-ɏḀ-ỿ]/gu,
  letter: /\p{L}/gu,
} as const;

// 베트남어 성조·고유 모음 (라틴 문자 안에서 베트남어를 구별하는 가장 확실한 단서)
const VIETNAMESE_MARKS =
  /[ăâđêôơưàảãạáằẳẵặắầẩẫậấèẻẽẹéềểễệếìỉĩịíòỏõọóồổỗộốờởỡợớùủũụúừửữựứỳỷỹỵý]/giu;

export interface ScriptCounts {
  letters: number;
  hangul: number;
  kana: number;
  han: number;
  cyrillic: number;
  arabic: number;
  thai: number;
  devanagari: number;
  latin: number;
}

function count(text: string, pattern: RegExp): number {
  return (text.match(pattern) ?? []).length;
}

/** URL·멘션·해시태그·이모지 등 번역하지 않는 토큰을 뺀 본문. */
export function withoutProtectedText(text: string): string {
  return text
    .replace(IMMUTABLE_TEXT_PATTERN, ' ')
    .replace(/__WF[A-Za-z0-9_]*?KEEP_\d+__/g, ' ');
}

export function scriptCounts(text: string): ScriptCounts {
  return {
    letters: count(text, SCRIPT.letter),
    hangul: count(text, SCRIPT.hangul),
    kana: count(text, SCRIPT.kana),
    han: count(text, SCRIPT.han),
    cyrillic: count(text, SCRIPT.cyrillic),
    arabic: count(text, SCRIPT.arabic),
    thai: count(text, SCRIPT.thai),
    devanagari: count(text, SCRIPT.devanagari),
    latin: count(text, SCRIPT.latin),
  };
}

// 라틴 문자 언어별 기능어. 여러 언어가 공유하는 단어도 일부러 넣는다: 판정은
// "대상 언어 점수가 다른 언어 점수보다 분명히 높은가"로 하므로 공유 단어는
// 양쪽에 같이 더해져 상쇄된다.
const LATIN_STOPWORDS: Record<string, ReadonlySet<string>> = {
  en: new Set(['the', 'and', 'is', 'are', 'was', 'were', 'this', 'that', 'these',
    'those', 'with', 'for', 'you', 'your', 'have', 'has', 'had', 'not', 'but',
    'will', 'would', 'can', 'what', 'when', 'where', 'how', 'why', 'who', 'from',
    'they', 'them', 'there', 'here', 'of', 'to', 'in', 'it', 'my', 'me', 'we',
    'i', 'do', 'does', 'did', 'just', 'so', 'very', 'be', 'been', 'am', 'at',
    'on', 'as', 'if', 'or', 'hello', 'thanks', 'please', 'yes', 'about', 'some']),
  es: new Set(['el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas', 'es',
    'son', 'está', 'están', 'y', 'de', 'del', 'que', 'qué', 'en', 'con', 'para',
    'por', 'pero', 'como', 'cómo', 'más', 'muy', 'no', 'sí', 'yo', 'tú', 'usted',
    'nosotros', 'me', 'mi', 'tu', 'su', 'lo', 'le', 'se', 'al', 'hola',
    'gracias', 'buenos', 'buenas', 'también', 'porque', 'cuando', 'donde',
    'dónde', 'hay', 'estoy', 'tengo', 'quiero', 'puedo', 'esto', 'esta', 'ese',
    'eso', 'ya', 'bien', 'hoy', 'mañana', 'a', 'gusta', 'gustan', 'ayudar',
    'ayuda', 'ella', 'él', 'ustedes', 'siempre', 'nunca', 'puedes', 'tienes',
    'tiene', 'vamos', 'estás', 'soy', 'eres', 'año', 'años', 'ahora', 'después',
    'mejor', 'otro', 'otra', 'nuevo', 'aquí', 'allí', 'amigo', 'amigos']),
  pt: new Set(['o', 'a', 'os', 'as', 'um', 'uma', 'uns', 'umas', 'é', 'são',
    'está', 'estão', 'e', 'de', 'do', 'da', 'dos', 'das', 'que', 'em', 'no',
    'na', 'nos', 'nas', 'com', 'para', 'por', 'mas', 'como', 'mais', 'muito',
    'não', 'sim', 'eu', 'você', 'vocês', 'nós', 'me', 'meu', 'minha', 'seu',
    'sua', 'se', 'ao', 'olá', 'obrigado', 'obrigada', 'bom', 'boa', 'também',
    'porque', 'quando', 'onde', 'tem', 'estou', 'tenho', 'quero', 'posso',
    'isto', 'isso', 'esse', 'essa', 'já', 'bem', 'hoje', 'amanhã', 'gosto',
    'gosta', 'ajudar', 'ajuda', 'ela', 'ele', 'vocês', 'sempre', 'nunca', 'pode',
    'vamos', 'sou', 'foi', 'ano', 'anos', 'agora', 'depois', 'melhor', 'outro',
    'outra', 'novo', 'aqui', 'ali', 'amigo', 'amigos', 'tão']),
  it: new Set(['il', 'lo', 'la', 'i', 'gli', 'le', 'un', 'una', 'uno', 'è',
    'sono', 'e', 'di', 'del', 'della', 'che', 'in', 'con', 'per', 'ma', 'come',
    'più', 'molto', 'non', 'sì', 'io', 'tu', 'lei', 'noi', 'mi', 'ti', 'ci',
    'si', 'al', 'ciao', 'grazie', 'buon', 'buona', 'anche', 'perché', 'quando',
    'dove', 'ho', 'ha', 'hai', 'voglio', 'posso', 'questo', 'questa', 'quello',
    'già', 'bene', 'oggi', 'domani']),
  fr: new Set(['le', 'la', 'les', 'un', 'une', 'des', 'est', 'sont', 'et', 'de',
    'du', 'que', 'qui', 'dans', 'avec', 'pour', 'par', 'mais', 'comme', 'plus',
    'très', 'ne', 'pas', 'oui', 'non', 'je', 'tu', 'vous', 'nous', 'il', 'elle',
    'ils', 'elles', 'me', 'ma', 'mon', 'ton', 'son', 'se', 'au', 'aux',
    'bonjour', 'merci', 'salut', 'aussi', 'parce', 'quand', 'où', 'suis', 'veux',
    'peux', 'ceci', 'cela', 'ça', 'déjà', 'bien', 'demain']),
  de: new Set(['der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einen',
    'einem', 'ist', 'sind', 'und', 'von', 'mit', 'für', 'auf', 'aus', 'bei',
    'aber', 'wie', 'mehr', 'sehr', 'nicht', 'ja', 'nein', 'ich', 'du', 'sie',
    'wir', 'ihr', 'er', 'es', 'mich', 'mir', 'mein', 'dein', 'sein', 'zu', 'zum',
    'zur', 'im', 'am', 'hallo', 'danke', 'bitte', 'auch', 'weil', 'wenn', 'wo',
    'hier', 'habe', 'hast', 'hat', 'bin', 'will', 'kann', 'dies', 'diese',
    'schon', 'gut', 'heute', 'morgen']),
  ro: new Set(['și', 'este', 'sunt', 'un', 'o', 'de', 'la', 'în', 'cu',
    'pentru', 'pe', 'dar', 'ca', 'mai', 'foarte', 'nu', 'da', 'eu', 'tu', 'el',
    'ea', 'noi', 'voi', 'ei', 'mă', 'mi', 'meu', 'ta', 'lui', 'se', 'bună',
    'mulțumesc', 'deoarece', 'când', 'unde', 'aici', 'am', 'ai', 'are', 'vreau',
    'pot', 'acest', 'această', 'deja', 'bine', 'azi', 'mâine', 'că']),
  nl: new Set(['de', 'het', 'een', 'is', 'zijn', 'en', 'van', 'met', 'voor',
    'op', 'uit', 'bij', 'maar', 'zoals', 'meer', 'zeer', 'niet', 'ja', 'nee',
    'ik', 'jij', 'je', 'u', 'wij', 'we', 'jullie', 'hij', 'zij', 'ze', 'mij',
    'mijn', 'jouw', 'te', 'naar', 'hallo', 'bedankt', 'dank', 'alsjeblieft',
    'ook', 'omdat', 'wanneer', 'waar', 'hier', 'heb', 'hebt', 'heeft', 'ben',
    'wil', 'kan', 'dit', 'deze', 'al', 'goed', 'vandaag', 'morgen']),
  pl: new Set(['i', 'w', 'na', 'z', 'do', 'nie', 'tak', 'to', 'jest', 'są',
    'że', 'się', 'jak', 'co', 'ale', 'czy', 'dla', 'od', 'po', 'za', 'przez',
    'bardzo', 'jestem', 'mam', 'chcę', 'mogę', 'cześć', 'dzięki', 'dziękuję',
    'proszę', 'też', 'ponieważ', 'kiedy', 'gdzie', 'tutaj', 'ten', 'ta', 'już',
    'dobrze', 'dzisiaj', 'jutro', 'ja', 'ty', 'my', 'wy', 'on', 'ona', 'oni']),
  tr: new Set(['bir', 've', 'bu', 'şu', 'o', 'ile', 'için', 'de', 'da', 'çok',
    'değil', 'evet', 'hayır', 'ben', 'sen', 'biz', 'siz', 'ama', 'gibi', 'daha',
    'en', 'mi', 'mı', 'mu', 'mü', 'merhaba', 'teşekkürler', 'lütfen', 'ayrıca',
    'çünkü', 'ne', 'zaman', 'nerede', 'burada', 'var', 'yok', 'istiyorum',
    'şimdi', 'bugün', 'yarın', 'iyi']),
  id: new Set(['dan', 'yang', 'di', 'ke', 'dari', 'ini', 'itu', 'dengan',
    'untuk', 'pada', 'adalah', 'tidak', 'ya', 'saya', 'aku', 'kamu', 'anda',
    'kami', 'kita', 'dia', 'mereka', 'juga', 'sangat', 'lebih', 'tapi',
    'tetapi', 'atau', 'karena', 'jika', 'kalau', 'kapan', 'sini', 'ada',
    'punya', 'mau', 'bisa', 'sudah', 'belum', 'akan', 'halo', 'terima', 'kasih',
    'tolong', 'selamat', 'baik', 'hari', 'besok']),
  ms: new Set(['dan', 'yang', 'di', 'ke', 'dari', 'ini', 'itu', 'dengan',
    'untuk', 'pada', 'adalah', 'tidak', 'ya', 'saya', 'aku', 'awak', 'kamu',
    'anda', 'kami', 'kita', 'dia', 'mereka', 'juga', 'sangat', 'lebih',
    'tetapi', 'atau', 'kerana', 'jika', 'kalau', 'bila', 'sini', 'ada', 'mahu',
    'boleh', 'sudah', 'belum', 'akan', 'hai', 'terima', 'kasih', 'tolong',
    'selamat', 'baik', 'hari', 'esok', 'tak', 'nak']),
  vi: new Set(['và', 'là', 'của', 'không', 'có', 'tôi', 'bạn', 'cho', 'với',
    'được', 'này', 'một', 'những', 'các', 'xin', 'chào', 'cảm', 'ơn', 'rất',
    'đã', 'sẽ', 'ở', 'đây', 'nào', 'như']),
};

// 서로 거의 같은 언어는 한 가족으로 보고, 가족 안의 점수 차이는 따지지 않는다.
const FAMILY: Record<string, string> = {id: 'malayic', ms: 'malayic'};

// 특정 언어에만 쓰이는 글자. 한 글자가 기능어 두 개만큼의 근거가 된다.
const CHARACTER_CUES: Record<string, RegExp> = {
  es: /[ñ¿¡]/giu,
  pt: /[ãõ]/giu,
  fr: /[œùû]/giu,
  de: /[ßäöü]/giu,
  ro: /[ășț]/giu,
  pl: /[ąęłńśźżć]/giu,
  tr: /[ğış]/giu,
};

export interface LatinProfile {
  words: number;
  hits: Record<string, number>;
  vietnameseMarkRatio: number;
  latinRatio: number;
}

export function latinProfile(text: string): LatinProfile {
  const cleaned = withoutProtectedText(text).toLocaleLowerCase();
  const tokens = cleaned.match(/\p{L}+/gu) ?? [];
  const letters = count(cleaned, SCRIPT.letter);
  const hits: Record<string, number> = {};
  for (const [language, words] of Object.entries(LATIN_STOPWORDS)) {
    let total = 0;
    for (const token of tokens) if (words.has(token)) total++;
    const cue = CHARACTER_CUES[language];
    if (cue) total += 2 * count(cleaned, cue);
    hits[language] = total;
  }
  return {
    words: tokens.length,
    hits,
    vietnameseMarkRatio:
      count(cleaned, VIETNAMESE_MARKS) / Math.max(letters, 1),
    latinRatio: count(cleaned, SCRIPT.latin) / Math.max(letters, 1),
  };
}

function strongestRival(
  hits: Record<string, number>,
  target: string,
): {language: string; hits: number} {
  const family = FAMILY[target];
  let best = {language: '', hits: 0};
  for (const [language, value] of Object.entries(hits)) {
    if (language === target) continue;
    if (family && FAMILY[language] === family) continue;
    if (value > best.hits) best = {language, hits: value};
  }
  return best;
}

/**
 * 본문이 이미 [target] 언어로 쓰였다고 확신할 수 있는지(번역 불필요 판정).
 * 확신하지 못하면 false → 번역을 시도한다.
 */
export function looksLikeTargetLanguage(text: string, target: string): boolean {
  const meaningful = withoutProtectedText(text).trim();
  if (!meaningful) return true;
  const counts = scriptCounts(meaningful);
  const letters = counts.letters;
  const ratio = (value: number) => value / Math.max(letters, 1);

  switch (target) {
    case 'ko':
      return counts.hangul >= 2 && ratio(counts.hangul) >= 0.95;
    case 'ja':
      return counts.kana > 0 && counts.hangul === 0 &&
        ratio(counts.kana + counts.han) >= 0.95;
    case 'zh':
      return counts.han >= 2 && counts.kana === 0 && counts.hangul === 0 &&
        ratio(counts.han) >= 0.97;
    case 'ru':
    case 'uk':
    case 'mn':
      return letters >= 3 && ratio(counts.cyrillic) >= 0.9;
    case 'ar':
      return letters >= 3 && ratio(counts.arabic) >= 0.9;
    case 'th':
      return letters >= 3 && ratio(counts.thai) >= 0.9;
    case 'hi':
      return letters >= 3 && ratio(counts.devanagari) >= 0.9;
  }

  const profile = latinProfile(meaningful);
  // 한 단어짜리 라틴 문자 메시지는 이름·공유 어휘일 수 있어 판정하지 않는다.
  if (profile.words < 3 || profile.latinRatio < 0.9) return false;
  if (target === 'vi' && profile.vietnameseMarkRatio >= 0.08 &&
      profile.words >= 3) {
    return profile.hits.vi >= 1 || profile.vietnameseMarkRatio >= 0.15;
  }
  const own = profile.hits[target];
  if (own === undefined) return false;
  const rival = strongestRival(profile.hits, target);
  return own >= 2 &&
    own / profile.words >= 0.3 &&
    own >= rival.hits + 1;
}

function expectedScriptRatio(counts: ScriptCounts, target: string): number | null {
  const letters = Math.max(counts.letters, 1);
  switch (target) {
    case 'ko': return counts.hangul / letters;
    case 'ja': return (counts.kana + counts.han) / letters;
    case 'zh': return counts.han / letters;
    case 'ru':
    case 'uk':
    case 'mn': return counts.cyrillic / letters;
    case 'ar': return counts.arabic / letters;
    case 'th': return counts.thai / letters;
    case 'hi': return counts.devanagari / letters;
    default: return null; // 라틴 문자 언어
  }
}

/**
 * 번역문이 대상 언어로 쓰였는지 확인한다. 명백히 틀린 경우에만 false.
 *
 * - 비라틴 대상: 대상 문자(한글·가나·한자·키릴 등)가 거의 없으면 false
 * - 중국어 대상: 가나가 많이 섞인 일본어 출력이면 false
 * - 라틴 대상: 라틴 문자가 절반 미만이거나, 원문이 비라틴인데 비라틴 글자가
 *   많이 남았거나, 다른 라틴 언어(특히 영어)의 기능어가 압도적이면 false
 *
 * 원문과 번역문이 사실상 같거나(이름·브랜드만 있는 문장) 글자가 적으면
 * 판단하지 않는다(기존 "변하지 않은 번역" 검사가 담당).
 */
export function translationMatchesTargetLanguage(
  source: string,
  translated: string,
  target: string,
): boolean {
  const output = withoutProtectedText(translated).trim();
  const input = withoutProtectedText(source).trim();
  if (!output) return true;
  const normalize = (value: string) => value.replace(/\s+/gu, ' ').trim();
  if (normalize(output) === normalize(input)) return true;

  const counts = scriptCounts(output);
  if (counts.letters < 6) return true;
  const sourceCounts = scriptCounts(input);
  const sourceWords = (input.match(/\p{L}+/gu) ?? []).length;
  // 이름·브랜드 몇 개로 된 입력은 그대로 남는 것이 정상이다.
  if (sourceWords < 3 && sourceCounts.letters < 12) return true;

  const expected = expectedScriptRatio(counts, target);
  if (expected != null) {
    if (expected < 0.2) return false;
    if (target === 'zh' && counts.kana / Math.max(counts.letters, 1) > 0.3) {
      return false;
    }
    return true;
  }

  // 라틴 문자 대상 언어
  const letters = Math.max(counts.letters, 1);
  if (counts.latin / letters < 0.5) return false;
  const sourceNonLatin = sourceCounts.letters - sourceCounts.latin;
  const outputNonLatin = counts.letters - counts.latin;
  if (sourceNonLatin >= 4 && outputNonLatin / letters > 0.35) return false;

  const profile = latinProfile(output);
  if (profile.words >= 5 && target !== 'vi') {
    const own = profile.hits[target] ?? 0;
    const rival = strongestRival(profile.hits, target);
    if (rival.hits >= 3 &&
        rival.hits >= own + 2 &&
        rival.hits / profile.words >= 0.3) {
      return false;
    }
  }
  return true;
}
