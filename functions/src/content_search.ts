import * as crypto from 'crypto';
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import {COL} from './firestore_paths';

/**
 * Search data deliberately lives outside the canonical content documents.
 * Clients cannot read or write these collections; callable functions always
 * re-read the canonical document before returning a result.
 */
export const CONTENT_SEARCH_SCHEMA_VERSION = 1;
export const MAX_CONTENT_SEARCH_TOKENS = 32_000;
const MAX_NORMALIZED_FIELD_CODEPOINTS = 12_000;
const MAX_QUERY_CODEPOINTS = 100;
// Search results are relevance-sorted only after the canonical documents have
// been re-read and permission-checked. Keep enough candidates to cover the
// current corpus (and normal growth) so a common one-character query cannot
// arbitrarily hide a valid result merely because Firestore returned another
// index document first.
const MAX_CANDIDATES = 1_000;

type ContentKind = 'post' | 'meetup';
type SourceData = FirebaseFirestore.DocumentData;

const POST_SEARCH_FIELDS = [
  'title',
  'content',
  'authorNickname',
  'isAnonymous',
] as const;

const MEETUP_SEARCH_FIELDS = [
  'title',
  'description',
  'location',
  'hostNickname',
  'host',
] as const;

function stringValue(value: unknown): string {
  return String(value ?? '');
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return Array.from(new Set(
    value.map((item) => stringValue(item).trim()).filter(Boolean),
  ));
}

function finiteInteger(value: unknown, fallback = 0): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : fallback;
}

/** Stable normalization shared by indexing, candidate verification and tests. */
export function normalizeContentSearchText(value: unknown): string {
  return stringValue(value)
    .normalize('NFKC')
    // Cc/Cf includes control, bidi-control and zero-width formatting chars.
    .replace(/[\p{Cc}\p{Cf}]/gu, '')
    .replace(/\s+/gu, ' ')
    .trim()
    .toLowerCase();
}

function limitedCodepoints(value: string): {value: string; truncated: boolean} {
  const codepoints = Array.from(value);
  if (codepoints.length <= MAX_NORMALIZED_FIELD_CODEPOINTS) {
    return {value, truncated: false};
  }
  return {
    value: codepoints.slice(0, MAX_NORMALIZED_FIELD_CODEPOINTS).join(''),
    truncated: true,
  };
}

/** Returns unique Unicode-codepoint 1/2/3-grams. */
export function buildContentSearchNgrams(value: unknown): string[] {
  const normalized = normalizeContentSearchText(value);
  const codepoints = Array.from(normalized);
  const tokens = new Set<string>();
  for (let width = 1; width <= 3; width++) {
    for (let offset = 0; offset + width <= codepoints.length; offset++) {
      tokens.add(codepoints.slice(offset, offset + width).join(''));
    }
  }
  return Array.from(tokens);
}

function normalizedPostFields(data: SourceData): string[] {
  const author = data.isAnonymous === true ? '' : data.authorNickname;
  // Short, high-value fields are indexed before long bodies if malformed
  // legacy data ever exceeds the defensive token ceiling.
  return [data.title, author, data.content].map(normalizeContentSearchText);
}

function normalizedMeetupFields(data: SourceData): string[] {
  return [
    data.title,
    data.hostNickname ?? data.host,
    data.location,
    data.description,
  ].map(normalizeContentSearchText);
}

function sourceHash(kind: ContentKind, fields: string[]): string {
  return crypto.createHash('sha256')
    .update(JSON.stringify([CONTENT_SEARCH_SCHEMA_VERSION, kind, fields]))
    .digest('hex');
}

export type ContentSearchIndexCore = {
  kind: ContentKind;
  schemaVersion: number;
  sourceHash: string;
  tokens: string[];
  tokenCount: number;
  truncated: boolean;
};

function buildIndexCore(
  kind: ContentKind,
  normalizedFields: string[],
): ContentSearchIndexCore {
  const tokens = new Set<string>();
  let truncated = false;

  outer:
  for (const originalField of normalizedFields) {
    const limited = limitedCodepoints(originalField);
    truncated = truncated || limited.truncated;
    const codepoints = Array.from(limited.value);
    for (let width = 1; width <= 3; width++) {
      for (let offset = 0; offset + width <= codepoints.length; offset++) {
        tokens.add(codepoints.slice(offset, offset + width).join(''));
        if (tokens.size >= MAX_CONTENT_SEARCH_TOKENS) {
          truncated = true;
          break outer;
        }
      }
    }
  }

  const result = Array.from(tokens);
  return {
    kind,
    schemaVersion: CONTENT_SEARCH_SCHEMA_VERSION,
    sourceHash: sourceHash(kind, normalizedFields),
    tokens: result,
    tokenCount: result.length,
    truncated,
  };
}

export function buildPostSearchIndexCore(
  data: SourceData,
): ContentSearchIndexCore {
  return buildIndexCore('post', normalizedPostFields(data));
}

export function buildMeetupSearchIndexCore(
  data: SourceData,
): ContentSearchIndexCore {
  return buildIndexCore('meetup', normalizedMeetupFields(data));
}

export function buildPostSearchIndexDocument(
  data: SourceData,
  indexedAt: FirebaseFirestore.Timestamp,
): FirebaseFirestore.DocumentData {
  return {...buildPostSearchIndexCore(data), indexedAt};
}

export function buildMeetupSearchIndexDocument(
  data: SourceData,
  indexedAt: FirebaseFirestore.Timestamp,
): FirebaseFirestore.DocumentData {
  return {...buildMeetupSearchIndexCore(data), indexedAt};
}

export function postSearchIndexRef(
  postId: string,
): FirebaseFirestore.DocumentReference {
  return admin.firestore().collection(COL.postSearchIndex).doc(postId);
}

export function meetupSearchIndexRef(
  meetupId: string,
): FirebaseFirestore.DocumentReference {
  return admin.firestore().collection(COL.meetupSearchIndex).doc(meetupId);
}

function sameSearchValue(left: unknown, right: unknown): boolean {
  if (left === right) return true;
  if (left == null && right == null) return true;
  return false;
}

/** Used by triggers and pure-node regression tests. */
export function contentSearchSourceChanged(
  kind: ContentKind,
  before: SourceData | undefined,
  after: SourceData | undefined,
): boolean {
  if (!before || !after) return true;
  const fields = kind === 'post' ? POST_SEARCH_FIELDS : MEETUP_SEARCH_FIELDS;
  return fields.some((field) => !sameSearchValue(before[field], after[field]));
}

function indexMatches(
  current: FirebaseFirestore.DocumentSnapshot,
  next: ContentSearchIndexCore,
): boolean {
  return current.exists &&
    current.get('schemaVersion') === next.schemaVersion &&
    current.get('sourceHash') === next.sourceHash &&
    current.get('tokenCount') === next.tokenCount &&
    current.get('truncated') === next.truncated;
}

async function synchronizeIndex(
  kind: ContentKind,
  contentId: string,
): Promise<void> {
  const db = admin.firestore();
  const contentRef = db.collection(
    kind === 'post' ? COL.posts : COL.meetups,
  ).doc(contentId);
  const indexRef = kind === 'post'
    ? postSearchIndexRef(contentId)
    : meetupSearchIndexRef(contentId);
  const [content, currentIndex] = await Promise.all([
    contentRef.get(),
    indexRef.get(),
  ]);

  // Re-read canonical state so out-of-order retries cannot restore a stale
  // index after a newer update or recreate.
  if (!content.exists) {
    if (currentIndex.exists) await indexRef.delete();
    return;
  }

  const data = content.data() ?? {};
  const core = kind === 'post'
    ? buildPostSearchIndexCore(data)
    : buildMeetupSearchIndexCore(data);
  if (indexMatches(currentIndex, core)) return;
  await indexRef.set({
    ...core,
    indexedAt: admin.firestore.Timestamp.now(),
  });
}

export const onPostSearchSourceWritten = functions.firestore
  .document(`${COL.posts}/{postId}`)
  .onWrite(async (change, context) => {
    const before = change.before.exists ? change.before.data() : undefined;
    const after = change.after.exists ? change.after.data() : undefined;
    // Likes, views, comments and poll votes still invoke an onWrite trigger at
    // the platform level, but return here without any Firestore read/write.
    if (!contentSearchSourceChanged('post', before, after)) return null;
    await synchronizeIndex('post', context.params.postId);
    return null;
  });

export const onMeetupSearchSourceWritten = functions.firestore
  .document(`${COL.meetups}/{meetupId}`)
  .onWrite(async (change, context) => {
    const before = change.before.exists ? change.before.data() : undefined;
    const after = change.after.exists ? change.after.data() : undefined;
    // Participant, view, comment and publication-state updates never rewrite
    // the text index.
    if (!contentSearchSourceChanged('meetup', before, after)) return null;
    await synchronizeIndex('meetup', context.params.meetupId);
    return null;
  });

function activeRequester(data: SourceData | undefined): boolean {
  if (!data) return false;
  const statuses = [data.status, data.accountStatus, data.registrationStatus]
    .map((value) => normalizeContentSearchText(value));
  if (data.isDeleted === true || data.deleted === true ||
      data.disabled === true || data.isSuspended === true ||
      data.deletedAt != null || statuses.includes('deleted') ||
      statuses.includes('suspended')) {
    return false;
  }
  const registration = normalizeContentSearchText(data.registrationStatus);
  if (registration && registration !== 'complete') return false;
  if (registration === 'complete') return true;
  // Legacy completed profiles predate registrationStatus.
  return data.emailVerified === true &&
    normalizeContentSearchText(data.nickname ?? data.displayName).length > 0;
}

type FrozenAudienceState = {
  valid: boolean;
  ownerId: string;
  visibility: string;
  audience: string[];
  sourceGroups: string[];
};

function frozenAudienceState(data: SourceData): FrozenAudienceState {
  const frozenOwner = stringValue(data.ownerId).trim();
  const frozenVisibility = stringValue(data.visibilityMode).trim();
  const frozenAudience = stringList(data.audienceUserIdsFrozen);
  const sourceGroups = stringList(data.sourceGroupIds);
  const valid = finiteInteger(data.visibilitySchemaVersion) >= 2 &&
    frozenOwner.length > 0 &&
    ['public', 'friends', 'category'].includes(frozenVisibility) &&
    Array.isArray(data.audienceUserIdsFrozen) &&
    Array.isArray(data.sourceGroupIds) &&
    data.visibilityLockedAt instanceof admin.firestore.Timestamp &&
    frozenAudience.includes(frozenOwner);
  return {
    valid,
    ownerId: frozenOwner,
    visibility: frozenVisibility,
    audience: frozenAudience,
    sourceGroups,
  };
}

function canonicalOwner(data: SourceData): string {
  const frozen = frozenAudienceState(data);
  return frozen.valid ? frozen.ownerId : stringValue(data.userId).trim();
}

export function contentAudienceAllows(uid: string, data: SourceData): boolean {
  const frozen = frozenAudienceState(data);
  if (frozen.valid) {
    return uid === frozen.ownerId || frozen.visibility === 'public' ||
      frozen.audience.includes(uid);
  }

  const legacyOwner = stringValue(data.userId).trim();
  const legacyVisibility = stringValue(data.visibility).trim();
  const legacyAudience = stringList(data.allowedUserIds);
  return uid === legacyOwner || legacyVisibility === 'public' ||
    (['friends', 'category'].includes(legacyVisibility) &&
      legacyAudience.includes(uid));
}

function audienceResult(data: SourceData): Record<string, unknown> {
  const frozen = frozenAudienceState(data);
  if (frozen.valid) {
    return {
      userId: frozen.ownerId,
      ownerId: frozen.ownerId,
      visibility: frozen.visibility,
      visibilityMode: frozen.visibility,
      visibleToCategoryIds: frozen.sourceGroups,
      sourceGroupIds: frozen.sourceGroups,
      allowedUserIds: frozen.audience,
      audienceUserIdsFrozen: frozen.audience,
      visibilitySchemaVersion: finiteInteger(data.visibilitySchemaVersion),
      visibilityLockedAt: timestampMillis(data.visibilityLockedAt),
    };
  }
  const ownerId = stringValue(data.userId).trim();
  const visibility = stringValue(data.visibility).trim();
  const audience = stringList(data.allowedUserIds);
  const sourceGroups = stringList(data.visibleToCategoryIds);
  return {
    userId: ownerId,
    ownerId,
    visibility,
    visibilityMode: visibility,
    visibleToCategoryIds: sourceGroups,
    sourceGroupIds: sourceGroups,
    allowedUserIds: audience,
    audienceUserIdsFrozen: audience,
    visibilitySchemaVersion: 0,
  };
}

function postSearchFields(data: SourceData): string[] {
  return normalizedPostFields(data);
}

function meetupSearchFields(data: SourceData): string[] {
  return normalizedMeetupFields(data);
}

export function contentMatchesQuery(fields: unknown[], query: unknown): boolean {
  const normalizedQuery = normalizeContentSearchText(query);
  if (!normalizedQuery) return false;
  return fields.some((field) =>
    normalizeContentSearchText(field).includes(normalizedQuery),
  );
}

export function contentSearchRelevance(fields: unknown[], query: unknown): number {
  const normalizedQuery = normalizeContentSearchText(query);
  if (!normalizedQuery) return 0;
  let best = 0;
  fields.forEach((field, index) => {
    const value = normalizeContentSearchText(field);
    if (!value) return;
    const weight = Math.max(1, 5 - index);
    if (value === normalizedQuery) best = Math.max(best, 500 * weight);
    else if (value.startsWith(normalizedQuery)) best = Math.max(best, 100 * weight);
    else if (value.includes(normalizedQuery)) best = Math.max(best, 10 * weight);
  });
  return best;
}

/** Selects at most three same-width grams for one array-contains-any query. */
export function contentSearchLookupTokens(query: unknown): string[] {
  const normalized = normalizeContentSearchText(query);
  const codepoints = Array.from(normalized);
  if (codepoints.length === 0) return [];
  const width = Math.min(3, codepoints.length);
  const grams: string[] = [];
  for (let offset = 0; offset + width <= codepoints.length; offset++) {
    grams.push(codepoints.slice(offset, offset + width).join(''));
  }
  const indexes = [0, Math.floor((grams.length - 1) / 2), grams.length - 1];
  return Array.from(new Set(indexes.map((index) => grams[index]).filter(Boolean)));
}

function timestampMillis(value: unknown): number {
  if (value instanceof admin.firestore.Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number' && Number.isFinite(value)) return Math.trunc(value);
  if (typeof value === 'string') {
    const parsed = Date.parse(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return 0;
}

function recursiveMillis(value: unknown): unknown {
  if (value instanceof admin.firestore.Timestamp) return value.toMillis();
  if (Array.isArray(value)) return value.map(recursiveMillis);
  if (value && typeof value === 'object') {
    const result: Record<string, unknown> = {};
    Object.entries(value as Record<string, unknown>).forEach(([key, item]) => {
      result[key] = recursiveMillis(item);
    });
    return result;
  }
  return value;
}

function postResult(id: string, data: SourceData): Record<string, unknown> {
  return {
    id,
    title: stringValue(data.title),
    content: stringValue(data.content),
    authorNickname: stringValue(data.authorNickname),
    authorNationality: stringValue(data.authorNationality),
    authorPhotoURL: stringValue(data.authorPhotoURL),
    category: stringValue(data.category),
    categoryKey: stringValue(data.categoryKey),
    categoryKeys: stringList(data.categoryKeys),
    createdAt: timestampMillis(data.createdAt),
    ...audienceResult(data),
    commentCount: finiteInteger(data.commentCount),
    viewCount: finiteInteger(data.viewCount),
    likes: finiteInteger(data.likes),
    likedBy: stringList(data.likedBy),
    imageUrls: stringList(data.imageUrls),
    ...(data.linkPreview && typeof data.linkPreview === 'object'
      ? {linkPreview: recursiveMillis(data.linkPreview)}
      : {}),
    type: stringValue(data.type) || 'text',
    pollOptions: Array.isArray(data.pollOptions)
      ? recursiveMillis(data.pollOptions)
      : [],
    pollTotalVotes: finiteInteger(data.pollTotalVotes),
    isAnonymous: data.isAnonymous === true,
    requiresHanyangVerification: data.requiresHanyangVerification === true,
  };
}

function meetupResult(id: string, data: SourceData): Record<string, unknown> {
  return {
    id,
    title: stringValue(data.title),
    description: stringValue(data.description),
    location: stringValue(data.location),
    time: stringValue(data.time),
    maxParticipants: finiteInteger(data.maxParticipants),
    currentParticipants: finiteInteger(data.currentParticipants),
    host: stringValue(data.host ?? data.hostNickname),
    hostNickname: stringValue(data.hostNickname ?? data.host),
    hostNationality: stringValue(data.hostNationality),
    hostPhotoURL: stringValue(data.hostPhotoURL),
    imageUrl: stringValue(data.imageUrl),
    thumbnailContent: stringValue(data.thumbnailContent),
    thumbnailImageUrl: stringValue(data.thumbnailImageUrl),
    imageUrls: stringList(data.imageUrls),
    date: timestampMillis(data.date),
    startsAt: timestampMillis(data.startsAt),
    endsAt: timestampMillis(data.endsAt),
    createdAt: timestampMillis(data.createdAt),
    category: stringValue(data.category) || '기타',
    ...audienceResult(data),
    requiresHanyangVerification: data.requiresHanyangVerification === true,
    isCompleted: data.isCompleted === true,
    hasReview: data.hasReview === true,
    groupChatEnabled: data.groupChatEnabled === true,
    isConfirmed: data.isConfirmed === true,
    ...(data.publicDurationHours == null
      ? {}
      : {publicDurationHours: finiteInteger(data.publicDurationHours)}),
    ...(data.publicExpiresAt == null
      ? {}
      : {publicExpiresAt: timestampMillis(data.publicExpiresAt)}),
    publicWindowStatus: stringValue(data.publicWindowStatus),
    snackChatId: stringValue(data.snackChatId),
    reviewId: stringValue(data.reviewId),
    viewCount: finiteInteger(data.viewCount),
    commentCount: finiteInteger(data.commentCount),
  };
}

export function meetupIsFutureAndPublished(
  data: SourceData,
  nowMillis: number,
): boolean {
  const status = normalizeContentSearchText(data.status);
  if (['expired', 'deleted', 'cancelled', 'canceled', 'hidden'].includes(status)) {
    return false;
  }
  if (data.isConfirmed !== true) {
    const publicationStatus = normalizeContentSearchText(data.publicWindowStatus);
    if (publicationStatus === 'expired') {
      return false;
    }
    const expiresAt = timestampMillis(data.publicExpiresAt);
    if (publicationStatus === 'timed' && expiresAt <= 0) return false;
    if (expiresAt > 0 && expiresAt <= nowMillis) return false;
  }

  const endsAt = timestampMillis(data.endsAt);
  if (endsAt > 0) return endsAt > nowMillis;
  const date = timestampMillis(data.date);
  // Mirrors the rules/model fallback for legacy records without endsAt.
  return date > 0 && date + 24 * 60 * 60 * 1000 > nowMillis;
}

function postIsSearchable(data: SourceData): boolean {
  const status = normalizeContentSearchText(data.status);
  return data.isHidden !== true && data.deleted !== true &&
    !['deleted', 'hidden', 'removed'].includes(status);
}

async function blockedOwnerIds(
  uid: string,
  ownerIds: Iterable<string>,
): Promise<Set<string>> {
  const db = admin.firestore();
  const owners = Array.from(new Set(Array.from(ownerIds)
    .map((owner) => owner.trim())
    .filter((owner) => owner && owner !== uid)));
  const blocked = new Set<string>();
  for (let offset = 0; offset < owners.length; offset += 200) {
    const chunk = owners.slice(offset, offset + 200);
    const documents = await db.getAll(...chunk.flatMap((owner) => [
      db.collection(COL.blocks).doc(`${uid}_${owner}`),
      db.collection(COL.blocks).doc(`${owner}_${uid}`),
    ]));
    chunk.forEach((owner, index) => {
      if (documents[index * 2]?.exists || documents[index * 2 + 1]?.exists) {
        blocked.add(owner);
      }
    });
  }
  return blocked;
}

async function anonymouslyHiddenPostIds(
  uid: string,
  posts: Array<{id: string; data: SourceData}>,
): Promise<Set<string>> {
  const db = admin.firestore();
  const anonymousIds = posts
    .filter((post) => post.data.isAnonymous === true)
    .map((post) => post.id);
  const hidden = new Set<string>();
  for (let offset = 0; offset < anonymousIds.length; offset += 300) {
    const chunk = anonymousIds.slice(offset, offset + 300);
    const documents = await db.getAll(...chunk.map((postId) =>
      db.collection('anonymous_post_blocks').doc(`${uid}_${postId}`),
    ));
    chunk.forEach((postId, index) => {
      if (documents[index]?.exists) hidden.add(postId);
    });
  }
  return hidden;
}

function callableRequest(
  raw: unknown,
): {query: string; limit: number; category: string} {
  const data = raw && typeof raw === 'object'
    ? raw as Record<string, unknown>
    : {};
  const query = normalizeContentSearchText(data.query);
  if (!query || Array.from(query).length > MAX_QUERY_CODEPOINTS) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `Search query must be 1-${MAX_QUERY_CODEPOINTS} characters.`,
    );
  }
  const requestedLimit = Number(data.limit);
  const limit = Math.max(
    1,
    Math.min(100, Number.isFinite(requestedLimit) ? Math.trunc(requestedLimit) : 20),
  );
  return {
    query,
    limit,
    category: stringValue(data.category).trim(),
  };
}

async function requireActiveRequester(
  context: functions.https.CallableContext,
): Promise<string> {
  const uid = stringValue(context.auth?.uid).trim();
  if (!uid) {
    throw new functions.https.HttpsError('unauthenticated', 'Sign-in is required.');
  }
  const user = await admin.firestore().collection(COL.users).doc(uid).get();
  if (!user.exists || !activeRequester(user.data())) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'An active, completed account is required.',
    );
  }
  return uid;
}

async function candidateIds(
  collectionName: string,
  query: string,
  limit: number,
): Promise<{ids: string[]; exhausted: boolean}> {
  const lookupTokens = contentSearchLookupTokens(query);
  const candidateLimit = Math.min(
    MAX_CANDIDATES,
    Math.max(500, limit * 10),
  );
  // Read one extra index document so `exhaustive` is accurate even when the
  // number of matches is exactly the candidate ceiling.
  const snapshot = await admin.firestore().collection(collectionName)
    .where('tokens', 'array-contains-any', lookupTokens)
    .limit(candidateLimit + 1)
    .get();
  return {
    ids: snapshot.docs
      .slice(0, candidateLimit)
      .map((document) => document.id),
    exhausted: snapshot.size > candidateLimit,
  };
}

export const searchPostsSecure = functions
  .runWith({timeoutSeconds: 30, memory: '512MB', enforceAppCheck: true})
  .https.onCall(async (raw, context) => {
    const request = callableRequest(raw);
    const uid = await requireActiveRequester(context);
    const db = admin.firestore();
    const candidates = await candidateIds(
      COL.postSearchIndex,
      request.query,
      request.limit,
    );
    if (candidates.ids.length === 0) return {posts: [], exhaustive: true};

    const snapshots = await db.getAll(...candidates.ids.map((id) =>
      db.collection(COL.posts).doc(id),
    ));
    let readable = snapshots
      .filter((snapshot) => snapshot.exists)
      .map((snapshot) => ({id: snapshot.id, data: snapshot.data() ?? {}}))
      .filter(({data}) => postIsSearchable(data) &&
        contentAudienceAllows(uid, data) &&
        contentMatchesQuery(postSearchFields(data), request.query) &&
        (!request.category ||
          stringList(data.categoryKeys).includes(request.category) ||
          stringValue(data.categoryKey).trim() === request.category));

    const [blockedOwners, anonymousHidden] = await Promise.all([
      blockedOwnerIds(uid, readable.map(({data}) => canonicalOwner(data))),
      anonymouslyHiddenPostIds(uid, readable),
    ]);
    const posts = readable
      .filter(({id, data}) =>
        !blockedOwners.has(canonicalOwner(data)) && !anonymousHidden.has(id),
      )
      .sort((left, right) => {
        const score = contentSearchRelevance(
          postSearchFields(right.data),
          request.query,
        ) - contentSearchRelevance(postSearchFields(left.data), request.query);
        return score || timestampMillis(right.data.createdAt) -
          timestampMillis(left.data.createdAt) || left.id.localeCompare(right.id);
      })
      .slice(0, request.limit)
      .map(({id, data}) => postResult(id, data));
    return {posts, exhaustive: !candidates.exhausted};
  });

export const searchMeetupsSecure = functions
  .runWith({timeoutSeconds: 30, memory: '512MB', enforceAppCheck: true})
  .https.onCall(async (raw, context) => {
    const request = callableRequest(raw);
    const uid = await requireActiveRequester(context);
    const db = admin.firestore();
    const candidates = await candidateIds(
      COL.meetupSearchIndex,
      request.query,
      request.limit,
    );
    if (candidates.ids.length === 0) return {meetups: [], exhaustive: true};

    const nowMillis = Date.now();
    const snapshots = await db.getAll(...candidates.ids.map((id) =>
      db.collection(COL.meetups).doc(id),
    ));
    let readable = snapshots
      .filter((snapshot) => snapshot.exists)
      .map((snapshot) => ({id: snapshot.id, data: snapshot.data() ?? {}}))
      .filter(({data}) => meetupIsFutureAndPublished(data, nowMillis) &&
        contentAudienceAllows(uid, data) &&
        contentMatchesQuery(meetupSearchFields(data), request.query) &&
        (!request.category ||
          normalizeContentSearchText(data.category) ===
            normalizeContentSearchText(request.category)));

    const blockedOwners = await blockedOwnerIds(
      uid,
      readable.map(({data}) => canonicalOwner(data)),
    );
    const meetups = readable
      .filter(({data}) => !blockedOwners.has(canonicalOwner(data)))
      .sort((left, right) => {
        const score = contentSearchRelevance(
          meetupSearchFields(right.data),
          request.query,
        ) - contentSearchRelevance(meetupSearchFields(left.data), request.query);
        const leftStart = timestampMillis(left.data.startsAt) ||
          timestampMillis(left.data.date);
        const rightStart = timestampMillis(right.data.startsAt) ||
          timestampMillis(right.data.date);
        return score || leftStart - rightStart || left.id.localeCompare(right.id);
      })
      .slice(0, request.limit)
      .map(({id, data}) => meetupResult(id, data));
    return {meetups, exhaustive: !candidates.exhausted};
  });
