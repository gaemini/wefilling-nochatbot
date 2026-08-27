import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import * as functions from 'firebase-functions';
import * as https from 'https';
import {COL} from './firestore_paths';
import {hasActiveHanyangClaim} from './hanyang_verification';

const GEMINI_API_VERSION = 'v1beta';
const GEMINI_MODEL = 'gemini-3.5-flash-lite';
const GEMINI_FALLBACK_MODEL = 'gemini-3.5-flash';
const TRANSLATION_VERSION = 5;
const PROMPT_VERSION = 5;
const TRANSLATION_POLICY_VERSION = '2026-08-faithful-v5';
const CURRENT_MODELS = new Set([GEMINI_MODEL, GEMINI_FALLBACK_MODEL]);
const TARGET_LANGUAGE_NAMES: Record<string, string> = {
  ko: 'Korean',
  en: 'English',
  ja: 'Japanese',
  zh: 'Chinese',
  es: 'Spanish',
  fr: 'French',
  de: 'German',
  ru: 'Russian',
  pt: 'Portuguese',
  it: 'Italian',
  ar: 'Arabic',
  hi: 'Hindi',
  th: 'Thai',
  vi: 'Vietnamese',
  id: 'Indonesian',
  ms: 'Malay (Bahasa Melayu)',
  tr: 'Turkish',
  nl: 'Dutch',
  pl: 'Polish',
  uk: 'Ukrainian',
  mn: 'Mongolian',
};
const MAX_BATCH_SIZE = 10;
const PENDING_TTL_MS = 60_000;
const MAX_SOURCE_CHARS = 12_000;
const SUPPORTED_TYPES = new Set([
  'post',
  'comment',
  'meetup',
  'snack_chat_message',
]);

type TranslationRequest = {
  contentType: string;
  contentId: string;
  parentId?: string;
};

type ResolvedContent = TranslationRequest & {
  fields: Record<string, string>;
  sourceHash: string;
};

type GeminiTranslation = {
  id: string;
  sourceLanguage: string;
  translations: Record<string, string>;
  modelUsed: string;
};

type ProtectedText = {
  text: string;
  tokens: Record<string, string>;
};

function stringValue(value: unknown): string {
  return value == null ? '' : String(value);
}

function stringList(value: unknown): string[] {
  return Array.isArray(value) ? value.map(String) : [];
}

function normalizeLanguageCode(value: unknown): string {
  const raw = stringValue(value).trim().toLowerCase().replace('_', '-');
  const code = raw.split('-')[0] || raw;
  const allowed = new Set([
    'ko', 'en', 'ja', 'zh', 'es', 'fr', 'de', 'ru', 'pt', 'it', 'ar',
    'hi', 'th', 'vi', 'id', 'ms', 'tr', 'nl', 'pl', 'uk', 'mn',
  ]);
  if (!allowed.has(code)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Unsupported target language.',
    );
  }
  return code;
}

function safeId(value: unknown, field: string): string {
  const id = stringValue(value).trim();
  if (!id || id.length > 160 || id.includes('/')) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `Invalid ${field}.`,
    );
  }
  return id;
}

function canonicalFields(fields: Record<string, string>): string {
  return Object.keys(fields)
    .sort()
    .map((key) => `${key}\u0000${fields[key].replace(/\r\n?/g, '\n')}`)
    .join('\u0001');
}

function sha256(value: string): string {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function requestKey(item: TranslationRequest): string {
  return `${item.contentType}:${item.parentId ?? ''}:${item.contentId}`;
}

function cacheId(item: TranslationRequest, targetLanguage: string): string {
  return sha256(
    `${TRANSLATION_VERSION}:${PROMPT_VERSION}:${GEMINI_MODEL}:${requestKey(item)}:${targetLanguage}`,
  );
}

function timestampMillis(value: unknown): number | null {
  return value instanceof admin.firestore.Timestamp ? value.toMillis() : null;
}

function hasMatchingIdentity(
  cached: Record<string, unknown>,
  item: ResolvedContent,
  targetLanguage: string,
): boolean {
  return cached.contentType === item.contentType &&
    cached.contentId === item.contentId &&
    (cached.parentId ?? null) === (item.parentId ?? null) &&
    cached.sourceHash === item.sourceHash &&
    cached.targetLanguage === targetLanguage;
}

function isCurrentCompletedCache(
  cached: Record<string, unknown> | undefined,
  item: ResolvedContent,
  targetLanguage: string,
): cached is Record<string, unknown> {
  if (!cached || cached.status !== 'completed') return false;
  const translatedFields = cached.translatedFields;
  if (!translatedFields || typeof translatedFields !== 'object' ||
      Array.isArray(translatedFields)) {
    return false;
  }
  const expectedFields = Object.keys(item.fields).sort();
  const actualFields = Object.keys(translatedFields).sort();
  if (expectedFields.length !== actualFields.length ||
      expectedFields.some((field, index) => field !== actualFields[index])) {
    return false;
  }
  return hasMatchingIdentity(cached, item, targetLanguage) &&
    cached.translationVersion === TRANSLATION_VERSION &&
    cached.promptVersion === PROMPT_VERSION &&
    CURRENT_MODELS.has(stringValue(cached.modelUsed)) &&
    expectedFields.every((field) =>
      typeof (translatedFields as Record<string, unknown>)[field] === 'string' &&
      isPlausibleTranslation(
        item.fields[field],
        (translatedFields as Record<string, string>)[field],
      ),
    );
}

function isCurrentPendingCache(
  cached: Record<string, unknown> | undefined,
  item: ResolvedContent,
  targetLanguage: string,
): boolean {
  if (!cached || cached.status !== 'pending') return false;
  const pendingAt = timestampMillis(cached.pendingAt) ?? 0;
  return hasMatchingIdentity(cached, item, targetLanguage) &&
    cached.translationVersion === TRANSLATION_VERSION &&
    cached.promptVersion === PROMPT_VERSION &&
    cached.modelUsed === GEMINI_MODEL &&
    Date.now() - pendingAt < PENDING_TTL_MS;
}

const PROTECTED_TEXT_PATTERN = /https?:\/\/[^\s]+|www\.[^\s]+|[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[\p{L}]{2,}|@[\p{L}\p{N}_.-]+|#[\p{L}\p{N}_.-]+|\bChIJ[A-Za-z0-9_-]+\b|(?:place[_ ]?id\s*[:=]\s*)[A-Za-z0-9_-]+|-?\d{1,3}\.\d+\s*[,/]\s*-?\d{1,3}\.\d+|\b\d{1,4}[./:-]\d{1,2}(?:[./:-]\d{1,4})?(?:\s*(?:AM|PM|오전|오후))?\b|\+?\d[\d\s().-]{5,}\d|\p{Extended_Pictographic}(?:\uFE0F|\p{Emoji_Modifier}|\u200D\p{Extended_Pictographic})*/giu;

function looksLikeSameLanguage(text: string, target: string): boolean {
  const meaningful = text
    .replace(PROTECTED_TEXT_PATTERN, '')
    .trim();
  if (!meaningful) return true;
  if (target === 'ko') return /[가-힣]/.test(meaningful) && !/[A-Za-z]{4,}/.test(meaningful);
  if (target === 'ja') return /[ぁ-んァ-ン]/.test(meaningful);
  if (target === 'zh') return /[\u3400-\u9FFF]/.test(meaningful) && !/[ぁ-んァ-ン]/.test(meaningful);
  if (target === 'ru' || target === 'uk') return /[\u0400-\u04FF]/.test(meaningful);
  if (target === 'ar') return /[\u0600-\u06FF]/.test(meaningful);
  if (target === 'th') return /[\u0E00-\u0E7F]/.test(meaningful);
  const latinHints: Record<string, Set<string>> = {
    en: new Set(['the', 'and', 'is', 'are', 'this', 'that', 'hello', 'thanks', 'with', 'for']),
    es: new Set(['el', 'la', 'los', 'las', 'es', 'hola', 'gracias', 'con', 'para', 'que']),
    fr: new Set(['le', 'la', 'les', 'est', 'bonjour', 'merci', 'avec', 'pour', 'que', 'des']),
    de: new Set(['der', 'die', 'das', 'ist', 'hallo', 'danke', 'mit', 'für', 'und', 'ein']),
    pt: new Set(['o', 'a', 'os', 'as', 'é', 'olá', 'obrigado', 'com', 'para', 'que']),
    it: new Set(['il', 'la', 'gli', 'è', 'ciao', 'grazie', 'con', 'per', 'che', 'un']),
    tr: new Set(['bir', 've', 'bu', 'ile', 'için', 'merhaba', 'teşekkürler', 'çok']),
    id: new Set(['dan', 'ini', 'itu', 'dengan', 'untuk', 'halo', 'terima', 'kasih']),
    ms: new Set(['dan', 'ini', 'itu', 'dengan', 'untuk', 'hai', 'terima', 'kasih']),
    vi: new Set(['và', 'là', 'này', 'với', 'cho', 'xin', 'chào', 'cảm', 'ơn']),
  };
  const hints = latinHints[target];
  if (hints && /[A-Za-zÀ-ỹ]/.test(meaningful)) {
    const words = meaningful.toLocaleLowerCase()
      .match(/[\p{L}]+/gu) ?? [];
    const hits = words.filter((word) => hints.has(word)).length;
    return hits >= 2 && hits / Math.max(words.length, 1) >= 0.2;
  }
  return false;
}

function protectText(value: string): ProtectedText {
  let index = 0;
  const tokens: Record<string, string> = {};
  let text = value
    .replace(/\r\n?/g, '\n')
    .replace(PROTECTED_TEXT_PATTERN, (match) => {
      const token = `__WF_KEEP_${index++}__`;
      tokens[token] = match;
      return token;
    });
  // 사용자가 입력한 문단/줄바꿈도 URL 및 이모지와 같은 보호 토큰으로
  // 취급하여 Gemini가 합치거나 새로 나누지 못하게 한다.
  text = text.replace(/\n/g, () => {
    const token = `__WF_KEEP_${index++}__`;
    tokens[token] = '\n';
    return token;
  });
  return {text, tokens};
}

function restoreProtectedText(
  value: string,
  protectedText: ProtectedText,
): string | null {
  let restored = value;
  for (const [token, original] of Object.entries(protectedText.tokens)) {
    // A duplicated or missing placeholder means a URL, mention, emoji, or
    // line break was changed. Reject only this item so it can be retried.
    if (restored.split(token).length - 1 !== 1) return null;
    restored = restored.split(token).join(original);
  }
  return restored;
}

async function canReadAudienceDocument(
  uid: string,
  data: Record<string, unknown>,
): Promise<boolean> {
  const ownerId = stringValue(data.ownerId || data.userId);
  if (ownerId === uid) return true;
  if (data.requiresHanyangVerification === true &&
      !(await hasActiveHanyangClaim(uid))) {
    return false;
  }
  const visibility = stringValue(data.visibilityMode || data.visibility || 'public');
  if (visibility === 'public' || visibility === 'anonymous') return true;
  return stringList(data.audienceUserIdsFrozen || data.allowedUserIds).includes(uid);
}

async function resolveContent(
  uid: string,
  request: TranslationRequest,
): Promise<ResolvedContent> {
  const db = admin.firestore();
  const contentType = request.contentType;
  const contentId = request.contentId;
  let fields: Record<string, string> = {};

  if (contentType === 'post') {
    const snap = await db.collection(COL.posts).doc(contentId).get();
    if (!snap.exists) throw new functions.https.HttpsError('not-found', 'Post not found.');
    const data = snap.data() as Record<string, unknown>;
    if (!(await canReadAudienceDocument(uid, data))) {
      throw new functions.https.HttpsError('permission-denied', 'Post is not accessible.');
    }
    const rawContent = stringValue(data.content);
    const rawTitle = stringValue(data.title);
    const content = rawContent.trim().length > 0 ? rawContent : rawTitle;
    fields = {content};
  } else if (contentType === 'meetup') {
    const snap = await db.collection(COL.meetups).doc(contentId).get();
    if (!snap.exists) throw new functions.https.HttpsError('not-found', 'Meetup not found.');
    const data = snap.data() as Record<string, unknown>;
    if (!(await canReadAudienceDocument(uid, data))) {
      throw new functions.https.HttpsError('permission-denied', 'Meetup is not accessible.');
    }
    fields = {
      title: stringValue(data.title),
      description: stringValue(data.description),
      location: stringValue(data.location),
    };
  } else if (contentType === 'comment') {
    const snap = await db.collection(COL.comments).doc(contentId).get();
    if (!snap.exists) throw new functions.https.HttpsError('not-found', 'Comment not found.');
    const data = snap.data() as Record<string, unknown>;
    if (data.isDeleted === true) {
      throw new functions.https.HttpsError('failed-precondition', 'Deleted comment.');
    }
    const parentId = stringValue(data.postId || request.parentId).trim();
    if (!parentId) throw new functions.https.HttpsError('failed-precondition', 'Comment parent is missing.');
    const [post, meetup] = await Promise.all([
      db.collection(COL.posts).doc(parentId).get(),
      db.collection(COL.meetups).doc(parentId).get(),
    ]);
    const parent = post.exists ? post : meetup;
    if (!parent.exists ||
        !(await canReadAudienceDocument(uid, parent.data() as Record<string, unknown>))) {
      throw new functions.https.HttpsError('permission-denied', 'Comment is not accessible.');
    }
    fields = {content: stringValue(data.content)};
    request.parentId = parentId;
  } else {
    const roomId = safeId(request.parentId, 'parentId');
    const room = await db.collection(COL.snackChats).doc(roomId).get();
    if (!room.exists || !stringList(room.data()?.participantIds).includes(uid)) {
      throw new functions.https.HttpsError('permission-denied', 'Snack Chat is not accessible.');
    }
    const message = await room.ref.collection('messages').doc(contentId).get();
    if (!message.exists) throw new functions.https.HttpsError('not-found', 'Message not found.');
    const data = message.data() as Record<string, unknown>;
    if (data.isDeleted === true || stringValue(data.type) === 'system') {
      throw new functions.https.HttpsError('failed-precondition', 'Message cannot be translated.');
    }
    fields = {text: stringValue(data.text)};
  }

  for (const [key, value] of Object.entries(fields)) {
    const normalized = value.slice(0, MAX_SOURCE_CHARS);
    if (normalized.trim().length > 0) {
      fields[key] = normalized;
    } else {
      delete fields[key];
    }
  }
  if (!Object.values(fields).some((value) => value.trim().length > 0)) {
    throw new functions.https.HttpsError('failed-precondition', 'Content is empty.');
  }
  return {...request, fields, sourceHash: sha256(canonicalFields(fields))};
}

function postJson(url: string, apiKey: string, body: unknown): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const parsed = new URL(url);
    const req = https.request({
      hostname: parsed.hostname,
      path: parsed.pathname + parsed.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
        'x-goog-api-key': apiKey,
      },
      timeout: 45_000,
    }, (response) => {
      let raw = '';
      response.setEncoding('utf8');
      response.on('data', (chunk: string) => { raw += chunk; });
      response.on('end', () => {
        if ((response.statusCode ?? 500) >= 400) {
          let detail = '';
          try {
            const parsedError = JSON.parse(raw) as {
              error?: {message?: unknown};
            };
            detail = stringValue(parsedError.error?.message)
              .replace(/[\r\n]+/g, ' ')
              .slice(0, 240);
          } catch (_) {
            // 응답 본문 전체나 API key는 로그에 남기지 않는다.
          }
          reject(new Error(
            `Gemini HTTP ${response.statusCode ?? 500}` +
            (detail ? `: ${detail}` : ''),
          ));
          return;
        }
        try {
          resolve(JSON.parse(raw));
        } catch (_) {
          reject(new Error('Gemini returned invalid JSON.'));
        }
      });
    });
    req.on('timeout', () => req.destroy(new Error('Gemini request timed out.')));
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

function parseGeminiJson(value: unknown): {items?: GeminiTranslation[]} {
  let text = stringValue(value).trim();
  if (text.startsWith('```')) {
    text = text
      .replace(/^```(?:json)?\s*/i, '')
      .replace(/\s*```$/, '')
      .trim();
  }
  if (!text) throw new Error('Gemini returned an empty response.');
  return JSON.parse(text) as {items?: GeminiTranslation[]};
}

function geminiErrorLogFields(error: unknown): {
  errorCategory: string;
  httpStatus?: number;
} {
  const message = error instanceof Error ? error.message : '';
  const httpStatus = /Gemini HTTP (\d{3})/i.exec(message);
  if (httpStatus) {
    return {
      errorCategory: Number(httpStatus[1]) === 429 ? 'quota' : 'http',
      httpStatus: Number(httpStatus[1]),
    };
  }
  if (/timed out/i.test(message)) return {errorCategory: 'timeout'};
  if (/GEMINI_API_KEY/i.test(message)) return {errorCategory: 'configuration'};
  if (error instanceof SyntaxError ||
      /invalid JSON|empty response/i.test(message)) {
    return {errorCategory: 'invalid_response'};
  }
  return {errorCategory: 'unknown'};
}

async function callGeminiModel(
  items: ResolvedContent[],
  targetLanguage: string,
  model: string,
  strict: boolean,
): Promise<Map<string, GeminiTranslation>> {
  const apiKey = stringValue(process.env.GEMINI_API_KEY).trim();
  if (!apiKey) throw new Error('GEMINI_API_KEY is not configured.');
  const targetLanguageName =
    TARGET_LANGUAGE_NAMES[targetLanguage] ?? targetLanguage;
  const protectedItems = new Map<string, Record<string, ProtectedText>>();
  const compactItems = items.map((item) => {
    const fields: Record<string, string> = {};
    for (const [field, value] of Object.entries(item.fields)) {
      const protectedText = protectText(value);
      const key = requestKey(item);
      const itemProtection = protectedItems.get(key) ?? {};
      itemProtection[field] = protectedText;
      protectedItems.set(key, itemProtection);
      fields[field] = protectedText.text;
    }
    return {
      id: requestKey(item),
      contentType: item.contentType,
      fields,
    };
  });
  const response = await postJson(
    `https://generativelanguage.googleapis.com/${GEMINI_API_VERSION}/models/${model}:generateContent`,
    apiKey,
    {
      contents: [{role: 'user', parts: [{text: [
        `Translate every field into ${targetLanguageName} (${targetLanguage}) as a professional native translator.`,
        'Complete preservation of the source meaning takes priority over naturalness; achieve both without dropping content.',
        'Return sourceLanguage as an ISO 639-1 language code.',
        'Preserve every __WF_KEEP_N__ placeholder exactly, including its spelling and position.',
        'Produce idiomatic, publication-ready text for a native reader; do not use awkward word-for-word phrasing.',
        'Preserve meaning, nuance, tone, emotion, repetition, laughter, slang, and intentional informality.',
        'Never summarize, shorten a long sentence, remove repetition, or omit any meaning unit.',
        'Preserve who did what to whom, time, place, target, conditions, cause, result, quantities, numbers, and positive or negative meaning.',
        'Keep each question, answer, suggestion, command, and exclamation as the same speech act, and never change the speaker or listener.',
        'Every existing paragraph boundary and line break is protected by a placeholder. Never add spaces or line breaks inside a placeholder.',
        'Keep every emoji unchanged and in the same relative position. Never translate, split, lowercase, or add spaces to URLs, emails, mentions, hashtags, IDs, or other protected values.',
        'Keep punctuation and intentional emphasis unless target-language grammar requires an equivalent natural form.',
        'Do not explain, add information, censor, invent names or brands, or rewrite proper nouns unnecessarily.',
        'Use an obvious typo only to infer the intended meaning internally. Never alter the source, and if an expression is uncertain, preserve it instead of guessing a person, brand, apology, or unrelated word.',
        'Use natural social-post and comment language for post/comment, natural conversational language for snack_chat_message, and clear informational language for meetup.',
        'Do not add explanations. Return one result per input id. A failure for one item must not remove other results.',
        strict ?
          'Before returning, verify sentence by sentence that no meaning unit was omitted, every protected token remains exactly once, paragraph structure is unchanged, and the result is fluent.' :
          'Before returning, verify completeness and fluency without adding any explanation.',
        'Return only JSON shaped exactly as {"items":[{"id":"input id","sourceLanguage":"ISO 639-1 code","translations":{"field name":"translated text"}}]}.',
        JSON.stringify(compactItems),
      ].join('\n')}]}],
      generationConfig: {
        temperature: 0.1,
        responseMimeType: 'application/json',
        responseJsonSchema: {
          type: 'object',
          additionalProperties: false,
          required: ['items'],
          properties: {
            items: {
              type: 'array',
              minItems: compactItems.length,
              maxItems: compactItems.length,
              items: {
                type: 'object',
                additionalProperties: false,
                required: ['id', 'sourceLanguage', 'translations'],
                properties: {
                  id: {
                    type: 'string',
                    enum: compactItems.map((item) => item.id),
                  },
                  sourceLanguage: {type: 'string'},
                  translations: {
                    type: 'object',
                    additionalProperties: false,
                    properties: {
                      content: {type: 'string'},
                      title: {type: 'string'},
                      description: {type: 'string'},
                      location: {type: 'string'},
                      text: {type: 'string'},
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  ) as Record<string, unknown>;
  const candidates = response.candidates as Array<Record<string, unknown>> | undefined;
  const content = candidates?.[0]?.content as Record<string, unknown> | undefined;
  const parts = content?.parts as Array<Record<string, unknown>> | undefined;
  const parsed = parseGeminiJson(parts?.[0]?.text);
  const results = new Map<string, GeminiTranslation>();
  const invalidIds = new Set<string>();
  for (const item of parsed.items ?? []) {
    if (item && typeof item.id === 'string' && item.translations &&
        typeof item.translations === 'object' &&
        protectedItems.has(item.id) && !invalidIds.has(item.id)) {
      if (results.has(item.id)) {
        results.delete(item.id);
        invalidIds.add(item.id);
        continue;
      }
      const protections = protectedItems.get(item.id) ?? {};
      const translations: Record<string, string> = {};
      for (const [field, value] of Object.entries(item.translations)) {
        const protection = protections[field];
        if (!protection) continue;
        const restored = restoreProtectedText(stringValue(value), protection);
        if (restored != null) translations[field] = restored;
      }
      results.set(item.id, {...item, translations, modelUsed: model});
    }
  }
  return results;
}

function isPlausibleTranslation(source: string, translated: string): boolean {
  const normalizedSource = source.replace(/\r\n?/g, '\n');
  const normalizedTranslation = translated.replace(/\r\n?/g, '\n');
  const sourceLength = normalizedSource.trim().length;
  const translatedLength = normalizedTranslation.trim().length;
  if (translatedLength < 1) return false;
  if ((normalizedSource.match(/\n/g) ?? []).length !==
      (normalizedTranslation.match(/\n/g) ?? []).length) {
    return false;
  }
  if (sourceLength >= 20) {
    const minimumLength = Math.max(2, Math.floor(sourceLength * 0.15));
    const maximumLength = sourceLength * 6 + 200;
    if (translatedLength < minimumLength || translatedLength > maximumLength) {
      return false;
    }
  }
  return true;
}

function isValidItemTranslation(
  item: ResolvedContent,
  result: GeminiTranslation | undefined,
): result is GeminiTranslation {
  if (!result || !result.translations ||
      typeof result.translations !== 'object') {
    return false;
  }
  const expectedFields = Object.keys(item.fields).sort();
  const actualFields = Object.keys(result.translations).sort();
  if (expectedFields.length !== actualFields.length ||
      expectedFields.some((field, index) => field !== actualFields[index])) {
    return false;
  }
  return expectedFields.every((field) =>
    isPlausibleTranslation(item.fields[field], result.translations[field]),
  );
}

async function callGemini(
  items: ResolvedContent[],
  targetLanguage: string,
): Promise<Map<string, GeminiTranslation>> {
  // Keep the normal batch fast and inexpensive. Only malformed or incomplete
  // items are retried, so a single bad result never discards valid siblings.
  let batch = new Map<string, GeminiTranslation>();
  try {
    batch = await callGeminiModel(
      items,
      targetLanguage,
      GEMINI_MODEL,
      false,
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : 'unknown';
    if (/GEMINI_API_KEY|Gemini HTTP|timed out/i.test(message)) throw error;
    console.warn('content_translation_batch_structure_retry', {
      targetLanguage,
      modelUsed: GEMINI_MODEL,
      translationVersion: TRANSLATION_VERSION,
      promptVersion: PROMPT_VERSION,
      cacheSource: 'gemini',
      ...geminiErrorLogFields(error),
    });
  }
  const results = new Map<string, GeminiTranslation>();
  for (const item of items) {
    const key = requestKey(item);
    const result = batch.get(key);
    if (isValidItemTranslation(item, result)) results.set(key, result);
  }

  for (const item of items) {
    const key = requestKey(item);
    if (results.has(key)) continue;

    let qualityFallbackRequired = false;
    try {
      const retried = await callGeminiModel(
        [item],
        targetLanguage,
        GEMINI_MODEL,
        true,
      );
      const result = retried.get(key);
      if (isValidItemTranslation(item, result)) {
        results.set(key, result);
        continue;
      }
      qualityFallbackRequired = true;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'unknown';
      console.warn('content_translation_item_retry_failed', {
        contentType: item.contentType,
        contentId: item.contentId,
        targetLanguage,
        modelUsed: GEMINI_MODEL,
        translationVersion: TRANSLATION_VERSION,
        promptVersion: PROMPT_VERSION,
        cacheSource: 'gemini',
        ...geminiErrorLogFields(error),
      });
      qualityFallbackRequired =
        !/GEMINI_API_KEY|Gemini HTTP|timed out/i.test(message);
    }

    if (!qualityFallbackRequired) continue;
    try {
      const fallback = await callGeminiModel(
        [item],
        targetLanguage,
        GEMINI_FALLBACK_MODEL,
        true,
      );
      const result = fallback.get(key);
      if (isValidItemTranslation(item, result)) results.set(key, result);
    } catch (error) {
      console.warn('content_translation_item_fallback_failed', {
        contentType: item.contentType,
        contentId: item.contentId,
        targetLanguage,
        modelUsed: GEMINI_FALLBACK_MODEL,
        translationVersion: TRANSLATION_VERSION,
        promptVersion: PROMPT_VERSION,
        cacheSource: 'gemini',
        ...geminiErrorLogFields(error),
      });
    }
  }
  return results;
}

export const translateContentBatch = functions
  .runWith({secrets: ['GEMINI_API_KEY'], timeoutSeconds: 60, memory: '512MB'})
  .https.onCall(async (raw, context) => {
    const uid = context.auth?.uid;
    if (!uid) throw new functions.https.HttpsError('unauthenticated', 'Sign-in is required.');
    const data = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
    const targetLanguage = normalizeLanguageCode(data.targetLanguage);
    if (!Array.isArray(data.items) || data.items.length < 1 || data.items.length > MAX_BATCH_SIZE) {
      throw new functions.https.HttpsError('invalid-argument', 'Provide 1 to 10 items.');
    }
    const requests = data.items.map((value): TranslationRequest => {
      const item = value && typeof value === 'object' ? value as Record<string, unknown> : {};
      const contentType = stringValue(item.contentType).trim();
      if (!SUPPORTED_TYPES.has(contentType)) {
        throw new functions.https.HttpsError('invalid-argument', 'Unsupported content type.');
      }
      return {
        contentType,
        contentId: safeId(item.contentId, 'contentId'),
        parentId: stringValue(item.parentId).trim() || undefined,
      };
    });
    if (new Set(requests.map(requestKey)).size !== requests.length) {
      throw new functions.https.HttpsError('invalid-argument', 'Duplicate items are not allowed.');
    }

    const startedAt = Date.now();
    const responses = new Map<string, Record<string, unknown>>();
    const db = admin.firestore();
    const resolvedAttempts = await Promise.all(requests.map(async (item) => {
      try {
        return await resolveContent(uid, item);
      } catch (_) {
        const key = requestKey(item);
        responses.set(key, {id: key, status: 'failed'});
        return null;
      }
    }));
    const resolved = resolvedAttempts.filter(
      (item): item is ResolvedContent => item != null,
    );
    const acquired: ResolvedContent[] = [];
    let cacheHits = 0;
    let pendingBlocked = 0;

    for (const item of resolved) {
      const key = requestKey(item);
      if (looksLikeSameLanguage(Object.values(item.fields).join('\n'), targetLanguage)) {
        responses.set(key, {
          id: key,
          status: 'same_language',
          sourceHash: item.sourceHash,
          sourceLanguage: targetLanguage,
          targetLanguage,
          translatedFields: item.fields,
          modelUsed: 'same-language',
          translationVersion: TRANSLATION_VERSION,
          promptVersion: PROMPT_VERSION,
          translatedAt: Date.now(),
          cacheSource: 'same_language',
        });
        continue;
      }
      const ref = db.collection(COL.contentTranslations).doc(cacheId(item, targetLanguage));
      const acquiredLock = await db.runTransaction(async (transaction) => {
        const snap = await transaction.get(ref);
        const cached = snap.data();
        if (isCurrentCompletedCache(cached, item, targetLanguage)) {
          cacheHits++;
          responses.set(key, {
            id: key,
            status: 'completed',
            sourceHash: item.sourceHash,
            sourceLanguage: stringValue(cached.sourceLanguage),
            targetLanguage,
            translatedFields: cached.translatedFields ?? {},
            modelUsed: stringValue(cached.modelUsed),
            translationVersion: TRANSLATION_VERSION,
            promptVersion: PROMPT_VERSION,
            translatedAt: timestampMillis(cached.translatedAt) ?? Date.now(),
            cacheSource: 'firestore',
          });
          return false;
        }
        if (isCurrentPendingCache(cached, item, targetLanguage)) {
          pendingBlocked++;
          return false;
        }
        transaction.set(ref, {
          contentType: item.contentType,
          contentId: item.contentId,
          parentId: item.parentId ?? null,
          targetLanguage,
          sourceHash: item.sourceHash,
          modelUsed: GEMINI_MODEL,
          translationVersion: TRANSLATION_VERSION,
          promptVersion: PROMPT_VERSION,
          status: 'pending',
          pendingAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        return true;
      });
      if (acquiredLock) acquired.push(item);
    }

    if (acquired.length > 0) {
      try {
        const translated = await callGemini(acquired, targetLanguage);
        await Promise.all(acquired.map(async (item) => {
          const key = requestKey(item);
          const result = translated.get(key);
          const translatedFields: Record<string, string> = {};
          if (result) {
            for (const field of Object.keys(item.fields)) {
              const value = stringValue(result.translations[field])
                .replace(/\r\n?/g, '\n');
              if (value.trim()) translatedFields[field] = value;
            }
          }
          const complete = Object.keys(translatedFields).length === Object.keys(item.fields).length;
          const ref = db.collection(COL.contentTranslations).doc(cacheId(item, targetLanguage));
          await ref.set(complete ? {
            contentType: item.contentType,
            contentId: item.contentId,
            parentId: item.parentId ?? null,
            status: 'completed',
            sourceHash: item.sourceHash,
            sourceLanguage: stringValue(result?.sourceLanguage).toLowerCase(),
            targetLanguage,
            translatedFields,
            modelUsed: result?.modelUsed ?? GEMINI_MODEL,
            translationVersion: TRANSLATION_VERSION,
            promptVersion: PROMPT_VERSION,
            translationPolicyVersion: TRANSLATION_POLICY_VERSION,
            cacheSource: 'gemini',
            translatedAt: admin.firestore.FieldValue.serverTimestamp(),
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          } : {
            contentType: item.contentType,
            contentId: item.contentId,
            parentId: item.parentId ?? null,
            status: 'failed',
            sourceHash: item.sourceHash,
            targetLanguage,
            modelUsed: result?.modelUsed ?? GEMINI_MODEL,
            translationVersion: TRANSLATION_VERSION,
            promptVersion: PROMPT_VERSION,
            failedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
          responses.set(key, complete ? {
            id: key,
            status: 'completed',
            sourceHash: item.sourceHash,
            sourceLanguage: stringValue(result?.sourceLanguage).toLowerCase(),
            targetLanguage,
            translatedFields,
            modelUsed: result?.modelUsed ?? GEMINI_MODEL,
            translationVersion: TRANSLATION_VERSION,
            promptVersion: PROMPT_VERSION,
            translatedAt: Date.now(),
            cacheSource: 'gemini',
          } : {
            id: key,
            status: 'failed',
            sourceHash: item.sourceHash,
            targetLanguage,
            modelUsed: result?.modelUsed ?? GEMINI_MODEL,
            translationVersion: TRANSLATION_VERSION,
            promptVersion: PROMPT_VERSION,
            translatedAt: Date.now(),
            cacheSource: 'gemini',
          });
        }));
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : 'unknown';
        const providerQuotaExhausted =
          /Gemini HTTP 429/i.test(errorMessage) &&
          /credits|quota|resource_exhausted/i.test(errorMessage);
        console.warn('content_translation_gemini_failed', {
          targetLanguage,
          modelUsed: GEMINI_MODEL,
          translationVersion: TRANSLATION_VERSION,
          promptVersion: PROMPT_VERSION,
          cacheSource: 'gemini',
          providerQuotaExhausted,
          ...geminiErrorLogFields(error),
        });
        await Promise.all(acquired.map(async (item) => {
          const key = requestKey(item);
          await db.collection(COL.contentTranslations)
            .doc(cacheId(item, targetLanguage)).set({
              contentType: item.contentType,
              contentId: item.contentId,
              parentId: item.parentId ?? null,
              status: 'failed',
              sourceHash: item.sourceHash,
              targetLanguage,
              modelUsed: GEMINI_MODEL,
              translationVersion: TRANSLATION_VERSION,
              promptVersion: PROMPT_VERSION,
              failedAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
          responses.set(key, {
            id: key,
            status: 'failed',
            sourceHash: item.sourceHash,
            targetLanguage,
            modelUsed: GEMINI_MODEL,
            translationVersion: TRANSLATION_VERSION,
            promptVersion: PROMPT_VERSION,
            translatedAt: Date.now(),
            cacheSource: 'gemini',
            // resolveContent() already verified this user can read the source.
            // Only quota exhaustion may fall back to an on-device translator;
            // permission and validation failures never receive this flag.
            allowClientFallback: providerQuotaExhausted,
            errorCode: providerQuotaExhausted ? 'provider_quota_exhausted' : 'provider_error',
          });
        }));
      }
    }

    for (const item of resolved) {
      const key = requestKey(item);
      if (responses.has(key)) continue;
      const snap = await db.collection(COL.contentTranslations)
        .doc(cacheId(item, targetLanguage)).get();
      const cached = snap.data();
      responses.set(key, isCurrentCompletedCache(cached, item, targetLanguage) ? {
        id: key,
        status: 'completed',
        sourceHash: item.sourceHash,
        sourceLanguage: stringValue(cached.sourceLanguage),
        targetLanguage,
        translatedFields: cached.translatedFields ?? {},
        modelUsed: stringValue(cached.modelUsed),
        translationVersion: TRANSLATION_VERSION,
        promptVersion: PROMPT_VERSION,
        translatedAt: timestampMillis(cached.translatedAt) ?? Date.now(),
        cacheSource: 'firestore',
      } : {
        id: key,
        status: 'pending',
        sourceHash: item.sourceHash,
        targetLanguage,
        modelUsed: GEMINI_MODEL,
        translationVersion: TRANSLATION_VERSION,
        promptVersion: PROMPT_VERSION,
        translatedAt: Date.now(),
        cacheSource: 'firestore',
      });
    }

    const durationMs = Date.now() - startedAt;
    console.info('content_translation_batch', {
      requested: requests.length,
      resolved: resolved.length,
      generated: acquired.length,
      cacheHits,
      cacheMisses: acquired.length,
      pendingBlocked,
      completed: [...responses.values()].filter((item) => item.status === 'completed').length,
      failed: [...responses.values()].filter((item) => item.status === 'failed').length,
      durationMs,
      averageItemLatencyMs: Math.round(durationMs / Math.max(1, requests.length)),
      targetLanguage,
    });
    return {items: requests.map((item) => responses.get(requestKey(item)))};
  });
