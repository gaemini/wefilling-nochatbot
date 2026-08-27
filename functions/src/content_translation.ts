import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import * as functions from 'firebase-functions';
import * as https from 'https';
import {COL} from './firestore_paths';
import {hasActiveHanyangClaim} from './hanyang_verification';

const GEMINI_API_VERSION = 'v1beta';
const GEMINI_MODEL = 'gemini-3.5-flash-lite';
const GEMINI_FALLBACK_MODEL = 'gemini-3.5-flash';
const TRANSLATION_VERSION = 6;
const PROMPT_VERSION = 6;
const TRANSLATION_POLICY_VERSION = '2026-08-context-quality-v6';
const GLOSSARY_VERSION = 1;
const QUALITY_POLICY_VERSION = 1;
const CURRENT_MODELS = new Set([GEMINI_MODEL, GEMINI_FALLBACK_MODEL]);
const SOURCE_INTENTS = new Set([
  'question',
  'statement',
  'answer',
  'suggestion',
  'request',
  'command',
  'exclamation',
  'unknown',
]);
const TYPO_HINTS: Record<string, string> = {
  '뮤슨': '무슨의 명백한 오타일 가능성이 높음',
  '해염': '해요의 구어체·오타 표현',
  '머해': '뭐 해의 구어체 표현',
  '할려구': '하려고의 구어체·오타 표현',
  'ㅇㅋ': '오케이의 축약형 표현',
  'ㄱㄱ': '가자 또는 진행하자는 뜻의 축약형 표현',
};
const WEFILLING_GLOSSARY: Record<string, string> = {
  '위필링': 'Wefilling',
  '스낵챗': 'Snack Chat',
  '스낵샷': 'Snackshot',
  '밋업': 'Meetup',
  '한양대 ERICA': 'Hanyang University ERICA',
};
const PRESERVE_IF_UNCERTAIN = ['섭픽'];
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
const MAX_BATCH_SIZE = 5;
const SNACK_CONTEXT_HISTORY_LIMIT = 3;
const PENDING_TTL_MS = 60_000;
// The client retries a rejected translation after two seconds and a provider
// outage after fifteen seconds. Keeping every failure for fifteen seconds made
// the fast retry read the same failed document and exhaust without regenerating.
const QUALITY_FAILED_RETRY_TTL_MS = 1_250;
const PROVIDER_FAILED_RETRY_TTL_MS = 12_000;
const MAX_SOURCE_CHARS = 12_000;
const MAX_CONTEXT_FIELD_CHARS = 1_500;
const MAX_CONTEXT_CHARS = 6_000;
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
  context: Record<string, string>;
  contextHash: string;
  typoHints: string[];
  matchedGlossary: Array<{source: string; preferred: string}>;
  preserveIfUncertain: string[];
  contextSeed: Record<string, unknown>;
  sourceHash: string;
};

type ResolutionCache = {
  snackRooms: Map<string, Promise<admin.firestore.DocumentSnapshot>>;
};

type GeminiTranslation = {
  id: string;
  sourceLanguage: string;
  sourceIntent: string;
  coverageComplete: boolean;
  uncertainTerms: string[];
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
  return sha256([
    TRANSLATION_VERSION,
    PROMPT_VERSION,
    TRANSLATION_POLICY_VERSION,
    GLOSSARY_VERSION,
    QUALITY_POLICY_VERSION,
    GEMINI_MODEL,
    requestKey(item),
    targetLanguage,
  ].join(':'));
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
    cached.translationPolicyVersion === TRANSLATION_POLICY_VERSION &&
    cached.glossaryVersion === GLOSSARY_VERSION &&
    cached.qualityPolicyVersion === QUALITY_POLICY_VERSION &&
    SOURCE_INTENTS.has(stringValue(cached.sourceIntent)) &&
    typeof cached.contextHash === 'string' && cached.contextHash.length > 0 &&
    cached.coverageComplete === true &&
    Array.isArray(cached.uncertainTerms) &&
    CURRENT_MODELS.has(stringValue(cached.modelUsed)) &&
    expectedFields.every((field) =>
      typeof (translatedFields as Record<string, unknown>)[field] === 'string' &&
      isPlausibleTranslation(
        item.fields[field],
        (translatedFields as Record<string, string>)[field],
        targetLanguage,
        false,
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
    cached.translationPolicyVersion === TRANSLATION_POLICY_VERSION &&
    cached.glossaryVersion === GLOSSARY_VERSION &&
    cached.qualityPolicyVersion === QUALITY_POLICY_VERSION &&
    cached.modelUsed === GEMINI_MODEL &&
    Date.now() - pendingAt < PENDING_TTL_MS;
}

function isCurrentFailedCache(
  cached: Record<string, unknown> | undefined,
  item: ResolvedContent,
  targetLanguage: string,
): cached is Record<string, unknown> {
  if (!cached || cached.status !== 'failed') return false;
  const failedAt = timestampMillis(cached.failedAt) ?? 0;
  const retryTtlMs = stringValue(cached.errorCode) ===
    'provider_unavailable' ?
    PROVIDER_FAILED_RETRY_TTL_MS : QUALITY_FAILED_RETRY_TTL_MS;
  return hasMatchingIdentity(cached, item, targetLanguage) &&
    cached.translationVersion === TRANSLATION_VERSION &&
    cached.promptVersion === PROMPT_VERSION &&
    cached.translationPolicyVersion === TRANSLATION_POLICY_VERSION &&
    cached.glossaryVersion === GLOSSARY_VERSION &&
    cached.qualityPolicyVersion === QUALITY_POLICY_VERSION &&
    Date.now() - failedAt < retryTtlMs;
}

function cachedFailureResponse(
  item: ResolvedContent,
  targetLanguage: string,
  cached: Record<string, unknown>,
): Record<string, unknown> {
  return {
    id: requestKey(item),
    status: 'failed',
    sourceHash: item.sourceHash,
    targetLanguage,
    modelUsed: stringValue(cached.modelUsed) || GEMINI_MODEL,
    translationVersion: TRANSLATION_VERSION,
    promptVersion: PROMPT_VERSION,
    translationPolicyVersion: TRANSLATION_POLICY_VERSION,
    glossaryVersion: GLOSSARY_VERSION,
    qualityPolicyVersion: QUALITY_POLICY_VERSION,
    contextHash: stringValue(cached.contextHash),
    translatedAt: timestampMillis(cached.failedAt) ?? Date.now(),
    cacheSource: 'firestore',
    errorCode: stringValue(cached.errorCode) || 'quality_validation_failed',
  };
}

const PROTECTED_TEXT_PATTERN = /https?:\/\/[^\s]+|www\.[^\s]+|[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[\p{L}]{2,}|@[\p{L}\p{N}_.-]+|#[\p{L}\p{N}_.-]+|\bChIJ[A-Za-z0-9_-]+\b|(?:place[_ ]?id\s*[:=]\s*)[A-Za-z0-9_-]+|-?\d{1,3}\.\d+\s*[,/]\s*-?\d{1,3}\.\d+|\b\d{1,4}[./:-]\d{1,2}(?:[./:-]\d{1,4})?(?:\s*(?:AM|PM|오전|오후))?\b|[$€£¥₩]\s?\d+(?:[.,]\d+)*|\+?\d[\d\s().-]{5,}\d|\d+(?:[.,]\d+)*(?:\s?(?:%|원|달러|시|분|초))?|\p{Extended_Pictographic}(?:\uFE0F|\p{Emoji_Modifier}|\u200D\p{Extended_Pictographic})*/giu;

function looksLikeSameLanguage(text: string, target: string): boolean {
  const meaningful = text
    .replace(PROTECTED_TEXT_PATTERN, '')
    .trim();
  if (!meaningful) return true;
  const letters = meaningful.match(/\p{L}/gu) ?? [];
  const ratio = (pattern: RegExp) =>
    (meaningful.match(pattern) ?? []).length / Math.max(letters.length, 1);
  if (target === 'ko') {
    const hangul = meaningful.match(/[가-힣]/g) ?? [];
    return hangul.length >= 2 && ratio(/[가-힣]/g) >= 0.85;
  }
  if (target === 'ja') {
    return /[ぁ-んァ-ン]/.test(meaningful) &&
      !/[가-힣]/.test(meaningful) &&
      ratio(/[ぁ-ン\u3400-\u9FFF]/g) >= 0.85;
  }
  if (target === 'zh') {
    return (meaningful.match(/[\u3400-\u9FFF]/g) ?? []).length >= 2 &&
      !/[ぁ-ン가-힣]/.test(meaningful) &&
      ratio(/[\u3400-\u9FFF]/g) >= 0.9;
  }
  if (target === 'ru' || target === 'uk') {
    return ratio(/[\u0400-\u04FF]/g) >= 0.9 && letters.length >= 3;
  }
  if (target === 'ar') {
    return ratio(/[\u0600-\u06FF]/g) >= 0.9 && letters.length >= 3;
  }
  if (target === 'th') {
    return ratio(/[\u0E00-\u0E7F]/g) >= 0.9 && letters.length >= 3;
  }
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
    const latinRatio = ratio(/[A-Za-zÀ-ỹ]/g);
    if (words.length === 1) return hits === 1 && latinRatio === 1;
    return words.length >= 3 && hits >= 2 && latinRatio >= 0.9 &&
      hits / words.length >= 0.3;
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
  if (/__WF_KEEP_\d+__/.test(restored)) return null;
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
  resolutionCache?: ResolutionCache,
): Promise<ResolvedContent> {
  const db = admin.firestore();
  const contentType = request.contentType;
  const contentId = request.contentId;
  let fields: Record<string, string> = {};
  let contextSeed: Record<string, unknown> = {};

  if (contentType === 'post') {
    const snap = await db.collection(COL.posts).doc(contentId).get();
    if (!snap.exists) throw new functions.https.HttpsError('not-found', 'Post not found.');
    const data = snap.data() as Record<string, unknown>;
    if (!(await canReadAudienceDocument(uid, data))) {
      throw new functions.https.HttpsError('permission-denied', 'Post is not accessible.');
    }
    const rawContent = stringValue(data.content);
    const rawTitle = stringValue(data.title);
    // Post.displayText trims the value on the client. Hash and translate the
    // same normalized source so legacy documents with surrounding whitespace
    // are not rejected as stale after a successful server translation.
    const content = rawContent.trim().length > 0 ?
      rawContent.trim() : rawTitle.trim();
    fields = {content};
    contextSeed = {
      title: rawContent.trim().length > 0 ? rawTitle : '',
      category: data.category,
      type: data.type,
    };
  } else if (contentType === 'meetup') {
    const snap = await db.collection(COL.meetups).doc(contentId).get();
    if (!snap.exists) throw new functions.https.HttpsError('not-found', 'Meetup not found.');
    const data = snap.data() as Record<string, unknown>;
    if (!(await canReadAudienceDocument(uid, data))) {
      throw new functions.https.HttpsError('permission-denied', 'Meetup is not accessible.');
    }
    fields = {
      description: stringValue(data.description),
      location: stringValue(data.location),
    };
    contextSeed = {
      category: data.category,
      type: data.type,
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
    const parentData = parent.data() as Record<string, unknown>;
    fields = {content: stringValue(data.content)};
    contextSeed = {
      parentTitle: parentData.title,
      parentBody: post.exists ? parentData.content : parentData.description,
      parentType: post.exists ? 'post' : 'meetup',
      parentCommentId: data.parentCommentId,
      replyToCommentId: data.replyToCommentId,
      createdAt: data.createdAt,
    };
    request.parentId = parentId;
  } else {
    const roomId = safeId(request.parentId, 'parentId');
    const roomRef = db.collection(COL.snackChats).doc(roomId);
    let roomRequest = resolutionCache?.snackRooms.get(roomId);
    if (!roomRequest) {
      roomRequest = roomRef.get();
      resolutionCache?.snackRooms.set(roomId, roomRequest);
    }
    const room = await roomRequest;
    if (!room.exists || !stringList(room.data()?.participantIds).includes(uid)) {
      throw new functions.https.HttpsError('permission-denied', 'Snack Chat is not accessible.');
    }
    const message = await room.ref.collection('messages').doc(contentId).get();
    if (!message.exists) throw new functions.https.HttpsError('not-found', 'Message not found.');
    const data = message.data() as Record<string, unknown>;
    const messageType = stringValue(data.type);
    if (data.isDeleted === true || messageType === 'system') {
      throw new functions.https.HttpsError('failed-precondition', 'Message cannot be translated.');
    }
    const rawPoll = messageType === 'poll' && data.poll &&
      typeof data.poll === 'object' && !Array.isArray(data.poll) ?
      data.poll as Record<string, unknown> : undefined;
    fields = {
      text: stringValue(rawPoll?.question || data.text),
    };
    const pollOptions = Array.isArray(rawPoll?.options) ?
      rawPoll.options : [];
    pollOptions.forEach((rawOption, index) => {
      const option = rawOption && typeof rawOption === 'object' &&
        !Array.isArray(rawOption) ?
        rawOption as Record<string, unknown> : {};
      const text = stringValue(option.text);
      if (text.trim()) fields[`pollOption${index}`] = text;
    });
    contextSeed = {
      roomPath: room.ref.path,
      messageType,
      replyToMessageId: data.replyToMessageId,
      senderId: data.senderId,
      sequence: data.sequence,
      createdAt: data.createdAt,
    };
  }

  const sourceHashFields: Record<string, string> = {};
  for (const [key, value] of Object.entries(fields)) {
    const normalized = value.slice(0, MAX_SOURCE_CHARS);
    sourceHashFields[key] = normalized;
    if (normalized.trim().length > 0) {
      fields[key] = normalized;
    } else {
      delete fields[key];
    }
  }
  if (!Object.values(fields).some((value) => value.trim().length > 0)) {
    throw new functions.https.HttpsError('failed-precondition', 'Content is empty.');
  }
  return {
    ...request,
    fields,
    context: {},
    contextHash: '',
    typoHints: [],
    matchedGlossary: [],
    preserveIfUncertain: [],
    contextSeed,
    sourceHash: sha256(canonicalFields(sourceHashFields)),
  };
}

function storedDocumentId(value: unknown): string {
  const id = stringValue(value).trim();
  return id && id.length <= 160 && !id.includes('/') ? id : '';
}

function addContextField(
  context: Record<string, string>,
  key: string,
  value: unknown,
): void {
  const used = Object.values(context).reduce(
    (total, field) => total + field.length,
    0,
  );
  const available = Math.max(0, MAX_CONTEXT_CHARS - used);
  if (available === 0) return;
  const normalized = stringValue(value)
    .replace(/\r\n?/g, '\n')
    .slice(0, Math.min(MAX_CONTEXT_FIELD_CHARS, available));
  if (normalized.trim()) context[key] = normalized;
}

function readableContextText(data: Record<string, unknown>): string {
  if (data.isDeleted === true || stringValue(data.type) === 'system') return '';
  const poll = data.poll && typeof data.poll === 'object' &&
    !Array.isArray(data.poll) ? data.poll as Record<string, unknown> : null;
  if (stringValue(data.type) === 'poll' && poll) {
    return stringValue(poll.question);
  }
  return stringValue(data.content || data.text);
}

function snackContextKey(
  base: string,
  contextSenderId: unknown,
  targetSenderId: unknown,
): string {
  const contextSender = stringValue(contextSenderId).trim();
  const targetSender = stringValue(targetSenderId).trim();
  if (!contextSender || !targetSender) return base;
  return `${base}_${contextSender === targetSender ?
    'sameSpeaker' : 'otherSpeaker'}`;
}

async function buildTranslationContext(
  item: ResolvedContent,
): Promise<ResolvedContent> {
  const db = admin.firestore();
  const context: Record<string, string> = {};
  const seed = item.contextSeed;

  if (item.contentType === 'post') {
    addContextField(context, 'postTitle', seed.title);
    addContextField(context, 'category', seed.category);
    addContextField(context, 'postType', seed.type);
  } else if (item.contentType === 'meetup') {
    addContextField(context, 'category', seed.category);
    addContextField(context, 'meetupType', seed.type);
  } else if (item.contentType === 'comment') {
    addContextField(context, 'parentContentType', seed.parentType);
    addContextField(context, 'parentTitle', seed.parentTitle);
    addContextField(context, 'parentExcerpt', seed.parentBody);

    const threadParentId = storedDocumentId(seed.parentCommentId);
    const replyToCommentId = storedDocumentId(seed.replyToCommentId);
    const directIds = [...new Set([
      threadParentId,
      replyToCommentId,
    ].filter(Boolean))];
    if (directIds.length > 0) {
      try {
        const direct = await Promise.all(directIds.map((id) =>
          db.collection(COL.comments).doc(id).get(),
        ));
        for (const snap of direct) {
          if (!snap.exists) continue;
          const data = snap.data() as Record<string, unknown>;
          if (stringValue(data.postId) !== item.parentId) continue;
          const text = readableContextText(data);
          if (!text) continue;
          addContextField(
            context,
            snap.id === replyToCommentId ?
              'replyToComment' : 'threadParentComment',
            text,
          );
        }
      } catch (_) {
        // Context is optional. Translation safely continues without it.
      }
    }

    const createdAt = seed.createdAt;
    const rootId = threadParentId || replyToCommentId;
    if (rootId && createdAt instanceof admin.firestore.Timestamp) {
      try {
        const recent = await db.collection(COL.comments)
          .where('postId', '==', item.parentId)
          .orderBy('createdAt', 'desc')
          .startAfter(createdAt)
          .limit(6)
          .get();
        const directIdSet = new Set(directIds);
        const related = recent.docs.filter((snap) => {
          const data = snap.data() as Record<string, unknown>;
          return !directIdSet.has(snap.id) &&
            stringValue(data.parentCommentId) === rootId;
        }).slice(0, 2).reverse();
        related.forEach((snap, index) => {
          addContextField(
            context,
            `previousReply${index + 1}`,
            readableContextText(snap.data() as Record<string, unknown>),
          );
        });
      } catch (_) {
        // Missing indexes must not change the existing comment read path.
      }
    }
  } else if (item.contentType === 'snack_chat_message') {
    const roomPath = stringValue(seed.roomPath);
    const replyToMessageId = storedDocumentId(seed.replyToMessageId);
    const targetSenderId = seed.senderId;
    addContextField(context, 'messageType', seed.messageType);
    if (roomPath) {
      const messages = db.doc(roomPath).collection('messages');
      if (replyToMessageId) {
        try {
          const reply = await messages.doc(replyToMessageId).get();
          if (reply.exists) {
            addContextField(
              context,
              snackContextKey(
                'replyToMessage',
                (reply.data() as Record<string, unknown>).senderId,
                targetSenderId,
              ),
              readableContextText(reply.data() as Record<string, unknown>),
            );
          }
        } catch (_) {
          // Reply context is optional.
        }
      }

      try {
        let previousDocs: admin.firestore.QueryDocumentSnapshot[] = [];
        if (typeof seed.sequence === 'number') {
          previousDocs = (await messages
            .where('sequence', '<', seed.sequence)
            .orderBy('sequence', 'desc')
            .limit(SNACK_CONTEXT_HISTORY_LIMIT)
            .get()).docs;
        } else if (seed.createdAt instanceof admin.firestore.Timestamp) {
          previousDocs = (await messages
            .orderBy('createdAt', 'desc')
            .orderBy(admin.firestore.FieldPath.documentId(), 'desc')
            .startAfter(seed.createdAt, item.contentId)
            .limit(SNACK_CONTEXT_HISTORY_LIMIT)
            .get()).docs;
        }
        previousDocs
          .filter((snap) => snap.id !== replyToMessageId)
          .reverse()
          .forEach((snap, index) => {
            addContextField(
              context,
              snackContextKey(
                `previousMessage${index + 1}`,
                (snap.data() as Record<string, unknown>).senderId,
                targetSenderId,
              ),
              readableContextText(snap.data() as Record<string, unknown>),
            );
          });
      } catch (_) {
        // If ordering needs a new index, omit history instead of changing data.
      }
    }
  }

  const targetText = Object.values(item.fields).join('\n');
  const allText = [targetText, ...Object.values(context)].join('\n');
  item.context = context;
  item.contextHash = sha256(canonicalFields(context));
  item.typoHints = Object.entries(TYPO_HINTS)
    .filter(([source]) => allText.includes(source))
    .map(([source, hint]) => `${source}: ${hint}`);
  item.matchedGlossary = Object.entries(WEFILLING_GLOSSARY)
    .filter(([source]) => allText.includes(source))
    .map(([source, preferred]) => ({source, preferred}));
  item.preserveIfUncertain = PRESERVE_IF_UNCERTAIN
    .filter((term) => targetText.includes(term));
  return item;
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

function isProviderUnavailableError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : '';
  const code = stringValue(
    error && typeof error === 'object' ?
      (error as Record<string, unknown>).code : '',
  );
  return /GEMINI_API_KEY|Gemini HTTP|timed out|socket hang up|network/i
    .test(message) ||
    /^(?:ECONNRESET|ECONNREFUSED|ENOTFOUND|EAI_AGAIN|ETIMEDOUT)$/i
      .test(code);
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
      CONTEXT: item.context,
      TARGET: fields,
      typoHints: item.typoHints,
      matchedGlossary: item.matchedGlossary,
      preserveIfUncertain: item.preserveIfUncertain,
    };
  });
  // 투표 문항은 pollOption0, pollOption1처럼 동적으로 늘어난다. 고정 schema가
  // 이를 막으면 Gemini가 옵션을 반환할 수 없어 Lite 재시도와 Flash fallback을
  // 연달아 호출하게 된다. 현재 batch에 실제로 존재하는 필드만 허용한다.
  const translationFieldProperties = Object.fromEntries(
    [...new Set(items.flatMap((item) => Object.keys(item.fields)))]
      .map((field) => [field, {type: 'string'}]),
  );
  const response = await postJson(
    `https://generativelanguage.googleapis.com/${GEMINI_API_VERSION}/models/${model}:generateContent`,
    apiKey,
    {
      contents: [{role: 'user', parts: [{text: [
        `Translate every field into ${targetLanguageName} (${targetLanguage}) as a professional native translator.`,
        'Complete preservation of the source meaning takes priority over naturalness; achieve both without dropping content.',
        'Return sourceLanguage as an ISO 639-1 language code.',
        'CONTEXT is read-only evidence for meaning, speaker/listener roles, and references. Never translate it and never return any CONTEXT field.',
        'TARGET contains the only fields that may be translated and returned.',
        'typoHints are conservative interpretation hints only. Do not rewrite the source or treat names, brands, memes, or nicknames as typos.',
        'matchedGlossary contains only terms present in this item. Use each preferred form exactly without inventing glossary entries.',
        'If a TARGET term is in preserveIfUncertain or its meaning is genuinely uncertain, keep the original term verbatim and include it in uncertainTerms.',
        'Set coverageComplete to true only after confirming that every TARGET meaning unit is represented.',
        'Set sourceIntent to exactly one of question, statement, answer, suggestion, request, command, exclamation, or unknown.',
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
        'Return only JSON shaped exactly as {"items":[{"id":"input id","sourceLanguage":"ISO 639-1 code","sourceIntent":"question","coverageComplete":true,"uncertainTerms":[],"translations":{"TARGET field name":"translated text"}}]}.',
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
                required: [
                  'id',
                  'sourceLanguage',
                  'sourceIntent',
                  'coverageComplete',
                  'uncertainTerms',
                  'translations',
                ],
                properties: {
                  id: {
                    type: 'string',
                    enum: compactItems.map((item) => item.id),
                  },
                  sourceLanguage: {type: 'string'},
                  sourceIntent: {
                    type: 'string',
                    enum: [...SOURCE_INTENTS],
                  },
                  coverageComplete: {type: 'boolean'},
                  uncertainTerms: {
                    type: 'array',
                    items: {type: 'string'},
                  },
                  translations: {
                    type: 'object',
                    additionalProperties: false,
                    properties: translationFieldProperties,
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
      let invalidTranslationField = false;
      for (const [field, value] of Object.entries(item.translations)) {
        const protection = protections[field];
        if (!protection) {
          invalidTranslationField = true;
          break;
        }
        const restored = restoreProtectedText(stringValue(value), protection);
        if (restored != null) translations[field] = restored;
      }
      if (!invalidTranslationField) {
        results.set(item.id, {...item, translations, modelUsed: model});
      }
    }
  }
  return results;
}

function immutableTokens(value: string): string[] {
  return value.match(PROTECTED_TEXT_PATTERN) ?? [];
}

function inferredSourceIntent(value: string): string {
  const text = value.trim();
  if (!text) return 'unknown';
  if (/[?？؟]/.test(text) ||
      /(?:무슨|뭐|왜|어떻게|어디|누구|언제|몇|어느).*(?:나요|까요|인가요|습니까|니|냐|건가요)\s*[.!~]*$/u.test(text) ||
      /(?:나요|인가요|습니까|건가요)\s*[.!~]*$/u.test(text)) {
    return 'question';
  }
  if (/(?:해주세요|해\s*주세요|부탁(?:해|드려|합니다))/u.test(text)) {
    return 'request';
  }
  if (/(?:하지\s*마|해라|하세요)\s*[.!~]*$/u.test(text)) return 'command';
  if (/(?:하자|어때요|어때|하는\s*게\s*어때)\s*[.!~]*$/u.test(text)) {
    return 'suggestion';
  }
  if (/^\s*(?:네|예|응|아니요|아뇨)(?:[\s,.!~]|$)/u.test(text)) {
    return 'answer';
  }
  if (/!|！/.test(text)) return 'exclamation';
  return 'unknown';
}

function intentIsCompatible(inferred: string, returned: string): boolean {
  if (inferred === 'unknown') return true;
  if (inferred === 'question') return returned === 'question';
  if (inferred === 'request') {
    return returned === 'request' || returned === 'command';
  }
  if (inferred === 'command') {
    return returned === 'command' || returned === 'request';
  }
  if (inferred === 'suggestion') {
    return returned === 'suggestion' || returned === 'question';
  }
  if (inferred === 'answer') {
    return returned === 'answer' || returned === 'statement';
  }
  if (inferred === 'exclamation') {
    return returned === 'exclamation' || returned === 'statement';
  }
  return inferred === returned;
}

function looksLikeTranslatedQuestion(value: string, target: string): boolean {
  const text = value.trim();
  if (/[?？؟¿]/.test(text)) return true;
  if (target === 'en') {
    return /^(?:who|what|when|where|why|how|which|whose|do|does|did|is|are|am|was|were|can|could|will|would|should|have|has)\b/i.test(text);
  }
  if (target === 'ko') return /(?:나요|까요|인가요|습니까|니|냐)\s*[.!~]*$/u.test(text);
  if (target === 'ja') return /(?:か|の)\s*[。！!~]*$/u.test(text);
  if (target === 'zh') return /(?:吗|呢|么)\s*[。！!~]*$/u.test(text);
  if (target === 'ar') return /^\s*هل\b/u.test(text);
  return false;
}

function hasNegation(value: string): boolean {
  return /(?:^|[\s,.!?])(?:안(?:\s+|해|돼|되|가|오|먹|보)|못(?:\s+|해|하|가|오|먹|보)|아니(?=$|[\s,.!?])|아니(?:야|에요|예요|다|고|면)|없|않|하지\s*마|말고)|(?:not|no|never|none|nothing|without|n't)\b|\b(?:ne|pas|non|nicht|kein|ningún|nunca|não|sem|нет|не|без)\b|[不没無ない]/iu.test(value);
}

function isShortReaction(value: string): boolean {
  return /^(?:ㅋ+|ㅎ+|응+|네+|예+|ㅇㅇ|ok(?:ay)?|yes|no)[\s.!?~]*$/iu.test(value.trim());
}

function isPlausibleTranslation(
  source: string,
  translated: string,
  targetLanguage: string,
  requireLexicalNegation = true,
): boolean {
  const normalizedSource = source.replace(/\r\n?/g, '\n');
  const normalizedTranslation = translated.replace(/\r\n?/g, '\n');
  const sourceLength = normalizedSource.trim().length;
  const translatedLength = normalizedTranslation.trim().length;
  if (translatedLength < 1) return false;
  if ((normalizedSource.match(/\n/g) ?? []).length !==
      (normalizedTranslation.match(/\n/g) ?? []).length) {
    return false;
  }
  const sourceTokens = immutableTokens(normalizedSource);
  const translatedTokens = immutableTokens(normalizedTranslation);
  if (sourceTokens.length !== translatedTokens.length ||
      sourceTokens.some((token, index) => token !== translatedTokens[index])) {
    return false;
  }
  if (sourceLength >= 12 && !isShortReaction(normalizedSource)) {
    const sourceWords = normalizedSource.match(/\p{L}+/gu) ?? [];
    let minimumRatio = sourceWords.length >= 4 ? 0.35 : 0.25;
    if (targetLanguage === 'en' && /[가-힣]/.test(normalizedSource)) {
      minimumRatio = Math.max(minimumRatio, 0.58);
    }
    const minimumLength = Math.max(2, Math.floor(sourceLength * minimumRatio));
    const maximumLength = sourceLength * 6 + 200;
    if (translatedLength < minimumLength || translatedLength > maximumLength) {
      return false;
    }
  }
  if (requireLexicalNegation &&
      hasNegation(normalizedSource) &&
      !hasNegation(normalizedTranslation)) {
    return false;
  }
  return true;
}

function hasUngroundedEnglishProperNoun(
  item: ResolvedContent,
  result: GeminiTranslation,
  targetLanguage: string,
): boolean {
  if (targetLanguage !== 'en') return false;
  const grounding = [
    ...Object.values(item.fields),
    ...Object.values(item.context),
    ...item.matchedGlossary.flatMap((entry) => [
      entry.source,
      entry.preferred,
    ]),
  ].join(' ').toLocaleLowerCase();
  const allowed = new Set([
    'i', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday',
    'saturday', 'sunday', 'january', 'february', 'march', 'april',
    'may', 'june', 'july', 'august', 'september', 'october',
    'november', 'december', 'korean', 'english', 'japanese', 'chinese',
  ]);
  for (const translated of Object.values(result.translations)) {
    const properNounPattern = /\b[A-Z][a-z]{2,}\b/g;
    let match: RegExpExecArray | null;
    while ((match = properNounPattern.exec(translated)) !== null) {
      const word = match[0];
      const offset = match.index;
      const prefix = translated.slice(0, offset).trimEnd();
      const sentenceInitial = prefix.length === 0 || /[.!?\n]\s*$/.test(prefix);
      if (!sentenceInitial && !allowed.has(word.toLocaleLowerCase()) &&
          !grounding.includes(word.toLocaleLowerCase())) {
        // Be conservative: transliterated real place/person names can also be
        // new Latin tokens. Reject only when the item already contains an
        // explicit typo/uncertainty signal.
        if (item.typoHints.length > 0 || result.uncertainTerms.length > 0) {
          return true;
        }
      }
    }
  }
  return false;
}

function isValidItemTranslation(
  item: ResolvedContent,
  result: GeminiTranslation | undefined,
  targetLanguage: string,
): result is GeminiTranslation {
  if (!result || !result.translations ||
      typeof result.translations !== 'object') {
    return false;
  }
  if (result.id !== requestKey(item) ||
      !/^[a-z]{2}$/i.test(stringValue(result.sourceLanguage)) ||
      !SOURCE_INTENTS.has(stringValue(result.sourceIntent)) ||
      result.coverageComplete !== true ||
      !Array.isArray(result.uncertainTerms) ||
      result.uncertainTerms.some((term) =>
        typeof term !== 'string' || !term.trim()
      ) ||
      new Set(result.uncertainTerms).size !== result.uncertainTerms.length) {
    return false;
  }
  const expectedFields = Object.keys(item.fields).sort();
  const actualFields = Object.keys(result.translations).sort();
  if (expectedFields.length !== actualFields.length ||
      expectedFields.some((field, index) => field !== actualFields[index])) {
    return false;
  }
  if (!expectedFields.every((field) =>
    isPlausibleTranslation(
      item.fields[field],
      result.translations[field],
      targetLanguage,
    ),
  )) return false;

  const sourceText = Object.values(item.fields).join('\n');
  const translatedText = Object.values(result.translations).join('\n');
  const inferredIntent = inferredSourceIntent(sourceText);
  if (!intentIsCompatible(inferredIntent, result.sourceIntent)) return false;
  if ((inferredIntent === 'question' || result.sourceIntent === 'question') &&
      !looksLikeTranslatedQuestion(translatedText, targetLanguage)) {
    return false;
  }
  for (const field of expectedFields) {
    if (inferredSourceIntent(item.fields[field]) === 'question' &&
        !looksLikeTranslatedQuestion(
          result.translations[field],
          targetLanguage,
        )) {
      return false;
    }
  }
  const uncertainTerms = result.uncertainTerms.map((term) => term.trim());
  if (uncertainTerms.some((term) =>
    !sourceText.includes(term) || !translatedText.includes(term)
  )) return false;
  if (item.preserveIfUncertain.some((term) =>
    !uncertainTerms.includes(term) || !translatedText.includes(term)
  )) return false;

  if (targetLanguage === 'en') {
    const hasFirstPerson = /(?:저는|제가|나는|내가|우리는|우리가)/u.test(sourceText);
    const hasSecondPerson = /(?:당신은|당신이|너는|네가|니가|여러분)/u.test(sourceText);
    if (hasFirstPerson && !/\b(?:I|me|my|mine|we|us|our|ours)\b/i.test(translatedText)) {
      return false;
    }
    if (hasSecondPerson && !/\b(?:you|your|yours)\b/i.test(translatedText)) {
      return false;
    }
  }
  return !hasUngroundedEnglishProperNoun(item, result, targetLanguage);
}

// Gemini occasionally returns a complete, usable translation whose auxiliary
// intent/uncertainty metadata fails one of the stricter quality heuristics. We
// still prefer a fully validated result, but after both the strict Lite retry
// and the Flash fallback have been exhausted it is better to use a structurally
// safe candidate than to leave the card/message untranslated and repeatedly
// spend another request on the same source.
function isSafeFallbackItemTranslation(
  item: ResolvedContent,
  result: GeminiTranslation | undefined,
  targetLanguage: string,
): result is GeminiTranslation {
  if (!result || result.id !== requestKey(item) ||
      !/^[a-z]{2}$/i.test(stringValue(result.sourceLanguage)) ||
      result.coverageComplete !== true ||
      !result.translations || typeof result.translations !== 'object') {
    return false;
  }
  const expectedFields = Object.keys(item.fields).sort();
  const actualFields = Object.keys(result.translations).sort();
  if (expectedFields.length !== actualFields.length ||
      expectedFields.some((field, index) => field !== actualFields[index])) {
    return false;
  }
  return expectedFields.every((field) =>
    isPlausibleTranslation(
      item.fields[field],
      result.translations[field],
      targetLanguage,
      false,
    ),
  );
}

function safeFallbackFailureCode(
  item: ResolvedContent,
  result: GeminiTranslation | undefined,
  targetLanguage: string,
): string {
  if (!result) return 'missing_result';
  if (result.id !== requestKey(item)) return 'id_mismatch';
  if (!/^[a-z]{2}$/i.test(stringValue(result.sourceLanguage))) {
    return 'invalid_source_language';
  }
  if (result.coverageComplete !== true) return 'coverage_incomplete';
  if (!result.translations || typeof result.translations !== 'object') {
    return 'missing_translations';
  }
  const expectedFields = Object.keys(item.fields).sort();
  const actualFields = Object.keys(result.translations).sort();
  if (expectedFields.length !== actualFields.length ||
      expectedFields.some((field, index) => field !== actualFields[index])) {
    return 'field_mismatch';
  }
  if (!expectedFields.every((field) =>
    isPlausibleTranslation(
      item.fields[field],
      result.translations[field],
      targetLanguage,
      false,
    ),
  )) return 'semantic_or_structure_guard';
  return 'strict_metadata_guard';
}

async function callGemini(
  items: ResolvedContent[],
  targetLanguage: string,
): Promise<{
  translations: Map<string, GeminiTranslation>;
  providerUnavailable: boolean;
}> {
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
    if (isProviderUnavailableError(error)) throw error;
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
  const safeFallbacks = new Map<string, GeminiTranslation>();
  const latestCandidates = new Map<string, GeminiTranslation>(batch);
  let providerUnavailable = false;
  for (const item of items) {
    const key = requestKey(item);
    const result = batch.get(key);
    if (isValidItemTranslation(item, result, targetLanguage)) {
      results.set(key, result);
    } else if (isSafeFallbackItemTranslation(item, result, targetLanguage)) {
      safeFallbacks.set(key, result);
    }
  }

  // Retry every rejected sibling in one strict request. The previous
  // per-item loop serialized up to ten provider calls for a five-item batch,
  // which made one difficult chat message block the rest of the viewport.
  const strictItems = items.filter((item) => !results.has(requestKey(item)));
  if (strictItems.length > 0) {
    try {
      const retried = await callGeminiModel(
        strictItems,
        targetLanguage,
        GEMINI_MODEL,
        true,
      );
      for (const item of strictItems) {
        const key = requestKey(item);
        const result = retried.get(key);
        if (result) latestCandidates.set(key, result);
        if (isValidItemTranslation(item, result, targetLanguage)) {
          results.set(key, result);
        } else if (isSafeFallbackItemTranslation(
          item,
          result,
          targetLanguage,
        )) {
          safeFallbacks.set(key, result);
        }
      }
    } catch (error) {
      console.warn('content_translation_item_retry_failed', {
        itemCount: strictItems.length,
        targetLanguage,
        modelUsed: GEMINI_MODEL,
        translationVersion: TRANSLATION_VERSION,
        promptVersion: PROMPT_VERSION,
        cacheSource: 'gemini',
        ...geminiErrorLogFields(error),
      });
      providerUnavailable = isProviderUnavailableError(error);
    }
  }

  // A structurally complete strict result has already preserved fields,
  // protected tokens, line breaks, length and negation. Auxiliary intent or
  // uncertainty metadata should not force another multi-second model call or
  // leave the message untranslated.
  for (const [key, result] of safeFallbacks) {
    if (!results.has(key)) results.set(key, result);
  }

  const fallbackItems = providerUnavailable ? [] :
    items.filter((item) => !results.has(requestKey(item)));
  if (fallbackItems.length > 0) {
    try {
      const fallback = await callGeminiModel(
        fallbackItems,
        targetLanguage,
        GEMINI_FALLBACK_MODEL,
        true,
      );
      for (const item of fallbackItems) {
        const key = requestKey(item);
        const result = fallback.get(key);
        if (result) latestCandidates.set(key, result);
        if (isValidItemTranslation(item, result, targetLanguage) ||
            isSafeFallbackItemTranslation(item, result, targetLanguage)) {
          results.set(key, result);
        }
      }
    } catch (error) {
      console.warn('content_translation_item_fallback_failed', {
        itemCount: fallbackItems.length,
        targetLanguage,
        modelUsed: GEMINI_FALLBACK_MODEL,
        translationVersion: TRANSLATION_VERSION,
        promptVersion: PROMPT_VERSION,
        cacheSource: 'gemini',
        ...geminiErrorLogFields(error),
      });
      providerUnavailable = isProviderUnavailableError(error);
    }
  }

  for (const item of items) {
    const key = requestKey(item);
    if (results.has(key)) continue;
    console.warn('content_translation_quality_rejected', {
      contentType: item.contentType,
      targetLanguage,
      modelUsed: GEMINI_FALLBACK_MODEL,
      translationVersion: TRANSLATION_VERSION,
      promptVersion: PROMPT_VERSION,
      reason: safeFallbackFailureCode(
        item,
        latestCandidates.get(key),
        targetLanguage,
      ),
    });
  }
  return {translations: results, providerUnavailable};
}

export const translateContentBatch = functions
  .runWith({secrets: ['GEMINI_API_KEY'], timeoutSeconds: 60, memory: '512MB'})
  .https.onCall(async (raw, context) => {
    const uid = context.auth?.uid;
    if (!uid) throw new functions.https.HttpsError('unauthenticated', 'Sign-in is required.');
    const data = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
    const targetLanguage = normalizeLanguageCode(data.targetLanguage);
    if (!Array.isArray(data.items) || data.items.length < 1 || data.items.length > MAX_BATCH_SIZE) {
      throw new functions.https.HttpsError('invalid-argument', 'Provide 1 to 5 items.');
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
    const resolutionCache: ResolutionCache = {
      // 한 callable batch의 스낵챗 메시지는 보통 모두 같은 방에 속한다.
      // 참여 권한 원본인 방 문서를 메시지마다 다시 과금/조회하지 않는다.
      snackRooms: new Map(),
    };
    const resolvedAttempts = await Promise.all(requests.map(async (item) => {
      try {
        return await resolveContent(uid, item, resolutionCache);
      } catch (error) {
        const key = requestKey(item);
        const errorCode = error instanceof functions.https.HttpsError ?
          error.code : 'internal';
        responses.set(key, {
          id: key,
          status: 'failed',
          errorCode,
        });
        console.warn('content_translation_source_resolution_failed', {
          contentType: item.contentType,
          errorCode,
        });
        return null;
      }
    }));
    const resolved = resolvedAttempts.filter(
      (item): item is ResolvedContent => item != null,
    );
    const acquired: ResolvedContent[] = [];
    let cacheHits = 0;
    let pendingBlocked = 0;

    // Every cache document is independent. Resolve the five cache locks in
    // parallel so a warm viewport pays one Firestore round trip instead of up
    // to five serial round trips before Gemini can even start.
    await Promise.all(resolved.map(async (item) => {
      const key = requestKey(item);
      if (looksLikeSameLanguage(Object.values(item.fields).join('\n'), targetLanguage)) {
        const sourceIntent = inferredSourceIntent(
          Object.values(item.fields).join('\n'),
        );
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
          translationPolicyVersion: TRANSLATION_POLICY_VERSION,
          glossaryVersion: GLOSSARY_VERSION,
          qualityPolicyVersion: QUALITY_POLICY_VERSION,
          sourceIntent,
          contextHash: sha256(canonicalFields({})),
          coverageComplete: true,
          uncertainTerms: [],
          translatedAt: Date.now(),
          cacheSource: 'same_language',
        });
        return;
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
            translationPolicyVersion: TRANSLATION_POLICY_VERSION,
            glossaryVersion: GLOSSARY_VERSION,
            qualityPolicyVersion: QUALITY_POLICY_VERSION,
            sourceIntent: stringValue(cached.sourceIntent),
            contextHash: stringValue(cached.contextHash),
            coverageComplete: true,
            uncertainTerms: Array.isArray(cached.uncertainTerms) ?
              cached.uncertainTerms : [],
            translatedAt: timestampMillis(cached.translatedAt) ?? Date.now(),
            cacheSource: 'firestore',
          });
          return false;
        }
        if (isCurrentFailedCache(cached, item, targetLanguage)) {
          cacheHits++;
          responses.set(
            key,
            cachedFailureResponse(item, targetLanguage, cached),
          );
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
          translationPolicyVersion: TRANSLATION_POLICY_VERSION,
          glossaryVersion: GLOSSARY_VERSION,
          qualityPolicyVersion: QUALITY_POLICY_VERSION,
          status: 'pending',
          pendingAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        return true;
      });
      if (acquiredLock) acquired.push(item);
    }));

    if (acquired.length > 0) {
      try {
        await Promise.all(acquired.map(buildTranslationContext));
        const gemini = await callGemini(acquired, targetLanguage);
        const translated = gemini.translations;
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
            glossaryVersion: GLOSSARY_VERSION,
            qualityPolicyVersion: QUALITY_POLICY_VERSION,
            sourceIntent: result?.sourceIntent ?? 'unknown',
            contextHash: item.contextHash,
            coverageComplete: result?.coverageComplete === true,
            uncertainTerms: result?.uncertainTerms ?? [],
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
            translationPolicyVersion: TRANSLATION_POLICY_VERSION,
            glossaryVersion: GLOSSARY_VERSION,
            qualityPolicyVersion: QUALITY_POLICY_VERSION,
            contextHash: item.contextHash,
            errorCode: gemini.providerUnavailable ?
              'provider_unavailable' : 'quality_validation_failed',
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
            translationPolicyVersion: TRANSLATION_POLICY_VERSION,
            glossaryVersion: GLOSSARY_VERSION,
            qualityPolicyVersion: QUALITY_POLICY_VERSION,
            sourceIntent: result?.sourceIntent ?? 'unknown',
            contextHash: item.contextHash,
            coverageComplete: result?.coverageComplete === true,
            uncertainTerms: result?.uncertainTerms ?? [],
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
            translationPolicyVersion: TRANSLATION_POLICY_VERSION,
            glossaryVersion: GLOSSARY_VERSION,
            qualityPolicyVersion: QUALITY_POLICY_VERSION,
            contextHash: item.contextHash,
            errorCode: gemini.providerUnavailable ?
              'provider_unavailable' : 'quality_validation_failed',
            translatedAt: Date.now(),
            cacheSource: 'gemini',
          });
        }));
      } catch (error) {
        const providerUnavailable = isProviderUnavailableError(error);
        const failureCode = providerUnavailable ?
          'provider_unavailable' : 'translation_failed';
        console.warn('content_translation_gemini_failed', {
          targetLanguage,
          modelUsed: GEMINI_MODEL,
          translationVersion: TRANSLATION_VERSION,
          promptVersion: PROMPT_VERSION,
          cacheSource: 'gemini',
          providerUnavailable,
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
              translationPolicyVersion: TRANSLATION_POLICY_VERSION,
              glossaryVersion: GLOSSARY_VERSION,
              qualityPolicyVersion: QUALITY_POLICY_VERSION,
              contextHash: item.contextHash || sha256(canonicalFields({})),
              errorCode: failureCode,
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
            translationPolicyVersion: TRANSLATION_POLICY_VERSION,
            glossaryVersion: GLOSSARY_VERSION,
            qualityPolicyVersion: QUALITY_POLICY_VERSION,
            contextHash: item.contextHash || sha256(canonicalFields({})),
            translatedAt: Date.now(),
            cacheSource: 'gemini',
            errorCode: failureCode,
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
      if (isCurrentCompletedCache(cached, item, targetLanguage)) {
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
          translationPolicyVersion: TRANSLATION_POLICY_VERSION,
          glossaryVersion: GLOSSARY_VERSION,
          qualityPolicyVersion: QUALITY_POLICY_VERSION,
          sourceIntent: stringValue(cached.sourceIntent),
          contextHash: stringValue(cached.contextHash),
          coverageComplete: true,
          uncertainTerms: Array.isArray(cached.uncertainTerms) ?
            cached.uncertainTerms : [],
          translatedAt: timestampMillis(cached.translatedAt) ?? Date.now(),
          cacheSource: 'firestore',
        });
      } else if (isCurrentFailedCache(cached, item, targetLanguage)) {
        responses.set(
          key,
          cachedFailureResponse(item, targetLanguage, cached),
        );
      } else {
        responses.set(key, {
        id: key,
        status: 'pending',
        sourceHash: item.sourceHash,
        targetLanguage,
        modelUsed: GEMINI_MODEL,
        translationVersion: TRANSLATION_VERSION,
        promptVersion: PROMPT_VERSION,
        translationPolicyVersion: TRANSLATION_POLICY_VERSION,
        glossaryVersion: GLOSSARY_VERSION,
        qualityPolicyVersion: QUALITY_POLICY_VERSION,
        translatedAt: Date.now(),
        cacheSource: 'firestore',
        });
      }
    }

    const durationMs = Date.now() - startedAt;
    console.info('content_translation_batch', {
      requested: requests.length,
      resolved: resolved.length,
      generated: acquired.length,
      cacheHits,
      cacheMisses: acquired.length,
      pendingBlocked,
      snackRoomReads: resolutionCache.snackRooms.size,
      completed: [...responses.values()].filter((item) => item.status === 'completed').length,
      failed: [...responses.values()].filter((item) => item.status === 'failed').length,
      durationMs,
      averageItemLatencyMs: Math.round(durationMs / Math.max(1, requests.length)),
      targetLanguage,
    });
    return {items: requests.map((item) => responses.get(requestKey(item)))};
  });
