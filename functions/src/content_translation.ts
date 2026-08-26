import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import * as functions from 'firebase-functions';
import * as https from 'https';
import {COL} from './firestore_paths';
import {hasActiveHanyangClaim} from './hanyang_verification';

const GEMINI_API_VERSION = 'v1beta';
const GEMINI_MODEL = 'gemini-3.5-flash-lite';
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
    .map((key) => `${key}\u0000${fields[key].replace(/\r\n/g, '\n').trim()}`)
    .join('\u0001');
}

function sha256(value: string): string {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function requestKey(item: TranslationRequest): string {
  return `${item.contentType}:${item.parentId ?? ''}:${item.contentId}`;
}

function cacheId(item: TranslationRequest, targetLanguage: string): string {
  return sha256(`${requestKey(item)}:${targetLanguage}`);
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
    return words.some((word) => hints.has(word));
  }
  return false;
}

function protectText(value: string): ProtectedText {
  let index = 0;
  const tokens: Record<string, string> = {};
  const text = value.replace(PROTECTED_TEXT_PATTERN, (match) => {
    const token = `__WF_KEEP_${index++}__`;
    tokens[token] = match;
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
    if (!restored.includes(token)) return null;
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
    const content = stringValue(data.content).trim() || stringValue(data.title).trim();
    fields = {content};
  } else if (contentType === 'meetup') {
    const snap = await db.collection(COL.meetups).doc(contentId).get();
    if (!snap.exists) throw new functions.https.HttpsError('not-found', 'Meetup not found.');
    const data = snap.data() as Record<string, unknown>;
    if (!(await canReadAudienceDocument(uid, data))) {
      throw new functions.https.HttpsError('permission-denied', 'Meetup is not accessible.');
    }
    fields = {
      description: stringValue(data.description).trim(),
      location: stringValue(data.location).trim(),
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
    fields = {content: stringValue(data.content).trim()};
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
    fields = {text: stringValue(data.text).trim()};
  }

  for (const [key, value] of Object.entries(fields)) {
    fields[key] = value.slice(0, MAX_SOURCE_CHARS);
  }
  if (!Object.values(fields).some((value) => value.length > 0)) {
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

async function callGemini(
  items: ResolvedContent[],
  targetLanguage: string,
): Promise<Map<string, GeminiTranslation>> {
  const apiKey = stringValue(process.env.GEMINI_API_KEY).trim();
  if (!apiKey) throw new Error('GEMINI_API_KEY is not configured.');
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
    `https://generativelanguage.googleapis.com/${GEMINI_API_VERSION}/models/${GEMINI_MODEL}:generateContent`,
    apiKey,
    {
      contents: [{role: 'user', parts: [{text: [
        `Translate every field into language code ${targetLanguage}.`,
        'Return sourceLanguage as an ISO 639-1 language code.',
        'Preserve every __WF_KEEP_N__ placeholder exactly, including its spelling and position.',
        'Preserve meaning, tone, emotion, line breaks, repetition, laughter, slang, and intentional informality.',
        'Do not summarize, explain, add information, censor, or rewrite proper nouns unnecessarily.',
        'Use natural social-post and comment language for post/comment, natural conversational language for snack_chat_message, and clear informational language for meetup.',
        'Do not add explanations. Return one result per input id. A failure for one item must not remove other results.',
        'Return only JSON shaped exactly as {"items":[{"id":"input id","sourceLanguage":"ISO 639-1 code","translations":{"field name":"translated text"}}]}.',
        JSON.stringify(compactItems),
      ].join('\n')}]}],
      generationConfig: {
        temperature: 0.1,
        responseMimeType: 'application/json',
      },
    },
  ) as Record<string, unknown>;
  const candidates = response.candidates as Array<Record<string, unknown>> | undefined;
  const content = candidates?.[0]?.content as Record<string, unknown> | undefined;
  const parts = content?.parts as Array<Record<string, unknown>> | undefined;
  const parsed = parseGeminiJson(parts?.[0]?.text);
  const results = new Map<string, GeminiTranslation>();
  for (const item of parsed.items ?? []) {
    if (item && typeof item.id === 'string' && item.translations &&
        typeof item.translations === 'object') {
      const protections = protectedItems.get(item.id) ?? {};
      const translations: Record<string, string> = {};
      for (const [field, value] of Object.entries(item.translations)) {
        const protection = protections[field];
        if (!protection) continue;
        const restored = restoreProtectedText(stringValue(value), protection);
        if (restored != null) translations[field] = restored;
      }
      results.set(item.id, {...item, translations});
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
          translatedFields: item.fields,
        });
        continue;
      }
      const ref = db.collection(COL.contentTranslations).doc(cacheId(item, targetLanguage));
      const acquiredLock = await db.runTransaction(async (transaction) => {
        const snap = await transaction.get(ref);
        const cached = snap.data();
        if (cached?.status === 'completed' && cached.sourceHash === item.sourceHash) {
          cacheHits++;
          responses.set(key, {
            id: key,
            status: 'completed',
            sourceHash: item.sourceHash,
            sourceLanguage: stringValue(cached.sourceLanguage),
            translatedFields: cached.translatedFields ?? {},
          });
          return false;
        }
        const pendingAt = cached?.pendingAt instanceof admin.firestore.Timestamp ?
          cached.pendingAt.toMillis() : 0;
        if (cached?.status === 'pending' && cached.sourceHash === item.sourceHash &&
            Date.now() - pendingAt < PENDING_TTL_MS) {
          pendingBlocked++;
          return false;
        }
        transaction.set(ref, {
          contentType: item.contentType,
          contentId: item.contentId,
          parentId: item.parentId ?? null,
          targetLanguage,
          sourceHash: item.sourceHash,
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
              const value = stringValue(result.translations[field]).trim();
              if (value) translatedFields[field] = value;
            }
          }
          const complete = Object.keys(translatedFields).length === Object.keys(item.fields).length;
          const ref = db.collection(COL.contentTranslations).doc(cacheId(item, targetLanguage));
          await ref.set(complete ? {
            status: 'completed',
            sourceHash: item.sourceHash,
            sourceLanguage: stringValue(result?.sourceLanguage).toLowerCase(),
            translatedFields,
            translatedAt: admin.firestore.FieldValue.serverTimestamp(),
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          } : {
            status: 'failed',
            sourceHash: item.sourceHash,
            failedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
          responses.set(key, complete ? {
            id: key,
            status: 'completed',
            sourceHash: item.sourceHash,
            sourceLanguage: stringValue(result?.sourceLanguage).toLowerCase(),
            translatedFields,
          } : {id: key, status: 'failed', sourceHash: item.sourceHash});
        }));
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : 'unknown';
        const providerQuotaExhausted =
          /Gemini HTTP 429/i.test(errorMessage) &&
          /credits|quota|resource_exhausted/i.test(errorMessage);
        console.warn('content_translation_gemini_failed', {
          message: errorMessage,
          providerQuotaExhausted,
        });
        await Promise.all(acquired.map(async (item) => {
          const key = requestKey(item);
          await db.collection(COL.contentTranslations)
            .doc(cacheId(item, targetLanguage)).set({
              status: 'failed',
              sourceHash: item.sourceHash,
              failedAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
          responses.set(key, {
            id: key,
            status: 'failed',
            sourceHash: item.sourceHash,
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
      responses.set(key, cached?.status === 'completed' && cached.sourceHash === item.sourceHash ? {
        id: key,
        status: 'completed',
        sourceHash: item.sourceHash,
        sourceLanguage: stringValue(cached.sourceLanguage),
        translatedFields: cached.translatedFields ?? {},
      } : {id: key, status: 'pending', sourceHash: item.sourceHash});
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
