import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import {COL} from './firestore_paths';
import {
  isActiveUserData,
  resolveFriendNotificationAudience,
  resolveFrozenAudience,
  VISIBILITY_SCHEMA_VERSION,
} from './frozen_audience';

const POST_CATEGORY_KEYS = new Set([
  'style', 'create', 'photo', 'content', 'cafe',
  'academic_study', 'books_writing', 'travel_local', 'global', 'other',
]);

function requireUid(context: functions.https.CallableContext): string {
  const uid = context.auth?.uid?.trim() ?? '';
  if (!uid) throw new functions.https.HttpsError('unauthenticated', 'Sign-in is required.');
  return uid;
}

function object(raw: unknown): Record<string, unknown> {
  return raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
}

function text(raw: unknown, max: number, field: string): string {
  const value = (raw ?? '').toString().trim();
  if (Array.from(value).length > max) {
    throw new functions.https.HttpsError('invalid-argument', `${field} is too long.`);
  }
  return value;
}

function contentId(raw: unknown): string {
  const value = (raw ?? '').toString().trim();
  if (!/^[A-Za-z0-9]{20}$/.test(value)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid content id.');
  }
  return value;
}

function stringList(raw: unknown, max: number, itemMax = 2048): string[] {
  if (!Array.isArray(raw)) return [];
  const result = Array.from(new Set(raw.map((item) => text(item, itemMax, 'list item')).filter(Boolean)));
  if (result.length > max) {
    throw new functions.https.HttpsError('invalid-argument', 'Too many list items.');
  }
  return result;
}

function integer(raw: unknown, min: number, max: number, field: string): number {
  const value = Number(raw);
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new functions.https.HttpsError('invalid-argument', `Invalid ${field}.`);
  }
  return value;
}

function supportedSharedLink(value: string, allowHttp = false): URL {
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch (_) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid shared link URL.');
  }
  const host = parsed.hostname.toLowerCase().replace(/\.$/, '');
  const allowed = host === 'youtu.be' || host === 'youtube.com' ||
    host.endsWith('.youtube.com') || host === 'instagram.com' ||
    host.endsWith('.instagram.com');
  const validProtocol = parsed.protocol === 'https:' ||
    (allowHttp && parsed.protocol === 'http:');
  if (!validProtocol || !allowed || parsed.username || parsed.password) {
    throw new functions.https.HttpsError('invalid-argument', 'Unsupported shared link URL.');
  }
  return parsed;
}

function validatedInstagramEmbedHtml(raw: unknown, canonicalUrl: string): string {
  const html = text(raw, 100000, 'linkPreview.embedHtml');
  if (!html) return '';
  const lower = html.toLowerCase();
  const forbiddenMarkup = /<(script|style|iframe|object|embed|form|input|meta|link|base|img)\b/i;
  const eventHandler = /\son[a-z]+\s*=/i;
  if (
    !lower.includes('class="instagram-media"') ||
    !html.includes(canonicalUrl) ||
    forbiddenMarkup.test(html) ||
    eventHandler.test(html) ||
    /\ssrc\s*=/i.test(html) ||
    lower.includes('javascript:') ||
    lower.includes('data:text/html')
  ) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid Instagram embed HTML.');
  }
  return html;
}

function sharedLinkPreview(
  raw: unknown,
  now: admin.firestore.Timestamp,
): FirebaseFirestore.DocumentData | null {
  if (raw == null) return null;
  const value = object(raw);
  const originalUrl = text(value.originalUrl, 2048, 'linkPreview.originalUrl');
  const canonicalUrl = text(value.canonicalUrl, 2048, 'linkPreview.canonicalUrl') || originalUrl;
  const parsed = supportedSharedLink(canonicalUrl);
  const host = parsed.hostname.toLowerCase();
  const inferredProvider = host === 'youtu.be' || host.endsWith('youtube.com')
    ? 'youtube'
    : 'instagram';
  const requestedProvider = text(value.provider, 20, 'linkPreview.provider');
  if (requestedProvider && requestedProvider !== inferredProvider) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid link preview provider.');
  }
  if (originalUrl) supportedSharedLink(originalUrl, true);
  const requestedContentId = text(value.contentId, 100, 'linkPreview.contentId');
  const pathSegments = parsed.pathname.split('/').filter(Boolean);
  const canonicalContentId = inferredProvider === 'youtube'
    ? (host === 'youtu.be'
      ? (pathSegments[0] ?? '')
      : (parsed.pathname === '/watch'
        ? (parsed.searchParams.get('v') ?? '')
        : (['shorts', 'live'].includes(pathSegments[0] ?? '')
          ? (pathSegments[1] ?? '')
          : '')))
    : (['p', 'reel'].includes(pathSegments[0] ?? '')
      ? (pathSegments[1] ?? '')
      : '');
  const validContentId = inferredProvider === 'youtube'
    ? /^[A-Za-z0-9_-]{11}$/.test(canonicalContentId)
    : /^[A-Za-z0-9_-]{3,100}$/.test(canonicalContentId);
  if (!validContentId || (requestedContentId && requestedContentId !== canonicalContentId)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid canonical shared link.');
  }

  const thumbnailUrl = text(value.thumbnailUrl, 2048, 'linkPreview.thumbnailUrl');
  if (thumbnailUrl) {
    let thumbnail: URL;
    try {
      thumbnail = new URL(thumbnailUrl);
    } catch (_) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid thumbnail URL.');
    }
    if (thumbnail.protocol !== 'https:' || thumbnail.username || thumbnail.password) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid thumbnail URL.');
    }
    const thumbnailHost = thumbnail.hostname.toLowerCase().replace(/\.$/, '');
    const allowedThumbnail = inferredProvider === 'youtube'
      ? thumbnailHost === 'i.ytimg.com' || thumbnailHost === 'img.youtube.com'
      : thumbnailHost === 'cdninstagram.com' ||
        thumbnailHost.endsWith('.cdninstagram.com') ||
        thumbnailHost === 'fbcdn.net' || thumbnailHost.endsWith('.fbcdn.net') ||
        thumbnailHost === 'instagram.com' || thumbnailHost.endsWith('.instagram.com');
    if (!allowedThumbnail) {
      throw new functions.https.HttpsError('invalid-argument', 'Unsupported thumbnail host.');
    }
  }

  const aspectRatioRaw = Number(value.aspectRatio);
  const aspectRatio = Number.isFinite(aspectRatioRaw)
    ? Math.min(2.4, Math.max(0.5, aspectRatioRaw))
    : (inferredProvider === 'instagram' ? 1 : 16 / 9);
  const previewStatus = text(value.previewStatus, 30, 'linkPreview.previewStatus');
  const contentType = inferredProvider === 'instagram'
    ? (pathSegments[0] === 'reel' ? 'reel' : 'post')
    : 'video';
  const instagramRoute = contentType === 'reel' ? 'reel' : 'p';
  const normalizedCanonicalUrl = inferredProvider === 'instagram'
    ? `https://www.instagram.com/${instagramRoute}/${canonicalContentId}/`
    : canonicalUrl;
  const requestedPreviewMode = text(value.previewMode, 20, 'linkPreview.previewMode');
  const embedHtml = inferredProvider === 'instagram'
    ? validatedInstagramEmbedHtml(value.embedHtml, normalizedCanonicalUrl)
    : '';
  const previewMode = inferredProvider === 'instagram'
    ? (requestedPreviewMode === 'embed' && embedHtml
      ? 'embed'
      : (requestedPreviewMode === 'image' && thumbnailUrl ? 'image' : 'link'))
    : 'image';

  return {
    provider: inferredProvider,
    originalUrl: originalUrl || canonicalUrl,
    canonicalUrl: normalizedCanonicalUrl,
    contentId: canonicalContentId,
    ...(inferredProvider === 'instagram' ? {shortcode: canonicalContentId} : {}),
    contentType,
    title: text(value.title, 300, 'linkPreview.title') ||
      (inferredProvider === 'instagram' ? 'Instagram에서 공유된 게시물' : ''),
    authorName: text(value.authorName, 160, 'linkPreview.authorName'),
    thumbnailUrl,
    aspectRatio,
    previewMode,
    ...(previewMode === 'embed' ? {embedHtml} : {}),
    fetchedAt: now,
    previewStatus: previewStatus === 'ready' &&
        (inferredProvider === 'youtube' || previewMode !== 'link')
      ? 'ready'
      : 'unavailable',
  };
}

function sharedLinkPreviewWithImageFallback(
  preview: FirebaseFirestore.DocumentData | null,
  imageUrls: string[],
): FirebaseFirestore.DocumentData | null {
  if (!preview || imageUrls.length === 0) return preview;
  if (text(preview.thumbnailUrl, 2048, 'linkPreview.thumbnailUrl')) return preview;
  if (preview.provider !== 'youtube' && preview.provider !== 'instagram') return preview;

  // This URL has already been accepted as post media (or was uploaded by this
  // function). Persisting it on the preview lets feed cards stay image-based
  // even when Instagram oEmbed omits thumbnail_url.
  return {
    ...preview,
    thumbnailUrl: imageUrls[0],
    previewStatus: 'ready',
  };
}

async function profile(uid: string): Promise<FirebaseFirestore.DocumentData> {
  const document = await admin.firestore().collection(COL.users).doc(uid).get();
  const data = document.data() ?? {};
  if (!document.exists || document.get('emailVerified') !== true || !isActiveUserData(data)) {
    throw new functions.https.HttpsError('failed-precondition', 'Verified profile is required.');
  }
  return data;
}

function externalShareRequestId(raw: unknown): string {
  const value = (raw ?? '').toString().trim();
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(value)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid external share request id.');
  }
  return value;
}

function externalShareJpeg(raw: unknown): Buffer | null {
  if (raw == null || raw === '') return null;
  if (typeof raw !== 'string' || raw.length > 6_500_000 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(raw)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid shared image.');
  }
  const bytes = Buffer.from(raw, 'base64');
  if (bytes.length === 0 || bytes.length > 4_500_000 ||
      bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid shared JPEG image.');
  }
  return bytes;
}

/**
 * Lightweight preflight for the native iOS Share Extension composer.
 * Authentication still comes from Firebase Auth's shared Apple Keychain; the
 * response contains display-only group metadata and never returns credentials.
 */
export const getExternalShareComposerContext = functions
  .runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (_raw, context) => {
    const uid = requireUid(context);
    await profile(uid);
    const groups = await admin.firestore()
      .collection(COL.friendCategories)
      .where('userId', '==', uid)
      .limit(10)
      .get();
    return {
      ready: true,
      groups: groups.docs
        .map((document) => ({
          id: document.id,
          name: text(document.get('name'), 80, 'group name') || '그룹',
          createdAtMillis: document.get('createdAt') instanceof admin.firestore.Timestamp
            ? (document.get('createdAt') as admin.firestore.Timestamp).toMillis()
            : 0,
        }))
        .sort((left, right) => left.createdAtMillis - right.createdAtMillis)
        .map(({id, name}) => ({id, name})),
    };
  });

/** 서버가 source group/current friends를 한 번 읽고 immutable audience를 저장한다. */
export const createPostSecure = functions.runWith({timeoutSeconds: 120, memory: '512MB'})
  .https.onCall(async (raw, context) => {
    const uid = requireUid(context);
    const data = object(raw);
    const postId = contentId(data.postId);
    const requestedCategoryKeys = stringList(data.categoryKeys, 10, 40);
    const legacyCategoryKey = text(data.categoryKey, 40, 'categoryKey');
    const categoryKeys = requestedCategoryKeys.length > 0
      ? requestedCategoryKeys
      : (legacyCategoryKey ? [legacyCategoryKey] : []);
    if (categoryKeys.length === 0 || categoryKeys.some((key) => !POST_CATEGORY_KEYS.has(key))) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid post tags.');
    }
    const categoryKey = categoryKeys[0];
    const frozen = await resolveFrozenAudience(
      uid,
      data.visibility,
      data.visibleToCategoryIds,
    );
    // 현재 포스트 UI는 public/group만 제공한다.
    if (frozen.visibilityMode === 'friends') {
      throw new functions.https.HttpsError('invalid-argument', 'Unsupported post visibility.');
    }
    const isAnonymous = data.isAnonymous === true;
    if (frozen.visibilityMode === 'category' && isAnonymous) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Group posts cannot be anonymous.',
      );
    }
    const notificationAudienceUserIdsFrozen = frozen.visibilityMode === 'public'
      ? await resolveFriendNotificationAudience(uid)
      : frozen.audienceUserIdsFrozen.filter((userId) => userId !== uid);
    const user = await profile(uid);
    const now = admin.firestore.Timestamp.now();
    const rawLinkPreview = sharedLinkPreview(data.linkPreview, now);
    // 최대 15개의 사용자 첨부 이미지에 Instagram 카드용 영구 썸네일
    // 한 장이 앞에 추가될 수 있다.
    const imageUrls = stringList(data.imageUrls, 16);
    const linkPreview = sharedLinkPreviewWithImageFallback(
      rawLinkPreview,
      imageUrls,
    );
    const type = text(data.type, 20, 'type') || 'text';
    const content = text(data.content, 10000, 'content');
    const pollOptions = stringList(data.pollOptions, 2, 200);
    if (type === 'poll' && (content.length === 0 || pollOptions.length !== 2)) {
      throw new functions.https.HttpsError('invalid-argument', 'A poll needs a question and two options.');
    }

    const document: FirebaseFirestore.DocumentData = {
      userId: uid,
      ownerId: uid,
      authorNickname: text(user.nickname, 80, 'nickname') || 'User',
      authorNationality: text(user.nationality, 80, 'nationality'),
      authorPhotoURL: text(user.photoURL, 2048, 'photoURL'),
      title: text(data.title, 200, 'title'),
      content,
      categoryKey,
      categoryKeys,
      imageUrls,
      createdAt: now,
      updatedAt: now,
      visibility: frozen.visibilityMode,
      visibleToCategoryIds: frozen.sourceGroupIds,
      allowedUserIds: frozen.audienceUserIdsFrozen,
      visibilityMode: frozen.visibilityMode,
      audienceUserIdsFrozen: frozen.audienceUserIdsFrozen,
      sourceGroupIds: frozen.sourceGroupIds,
      notificationAudienceUserIdsFrozen,
      visibilityLockedAt: now,
      visibilitySchemaVersion: VISIBILITY_SCHEMA_VERSION,
      isAnonymous,
      likes: 0,
      likedBy: [],
      commentCount: 0,
      viewCount: 0,
      type,
      ...(linkPreview ? {linkPreview} : {}),
      ...(type === 'poll' ? {
        pollOptions: pollOptions.map((option, index) => ({id: `${index}`, text: option, votes: 0})),
        pollTotalVotes: 0,
      } : {}),
    };
    const ref = admin.firestore().collection(COL.posts).doc(postId);
    const existing = await ref.get();
    if (existing.exists) {
      if (existing.get('ownerId') === uid || existing.get('userId') === uid) return {postId};
      throw new functions.https.HttpsError('already-exists', 'Post already exists.');
    }
    await ref.create(document);
    console.log(
      `content-created type=post id=${postId} owner=${uid} ` +
      `visibility=${frozen.visibilityMode} schema=2 ` +
      `audienceCount=${frozen.audienceUserIdsFrozen.length}`,
    );
    return {postId};
  });

/**
 * Native iOS Share Extension publishing endpoint.
 *
 * requestId is converted to a deterministic post id, so a retry after an
 * interrupted extension callback returns the original result instead of
 * creating a duplicate post. The optional single JPEG is uploaded by Admin SDK
 * only after authentication, profile, visibility, and category validation.
 */
export const createExternalSharePost = functions
  .runWith({timeoutSeconds: 120, memory: '512MB'})
  .https.onCall(async (raw, context) => {
    const uid = requireUid(context);
    const data = object(raw);
    const requestId = externalShareRequestId(data.requestId);
    const postId = crypto.createHash('sha256')
      .update(`${uid}:${requestId}`)
      .digest('hex')
      .slice(0, 20);
    const postRef = admin.firestore().collection(COL.posts).doc(postId);
    const existing = await postRef.get();
    if (existing.exists) {
      if (existing.get('ownerId') === uid || existing.get('userId') === uid) {
        return {postId, duplicate: true};
      }
      throw new functions.https.HttpsError('already-exists', 'Post already exists.');
    }

    const requestedCategoryKeys = stringList(data.categoryKeys, 10, 40);
    if (requestedCategoryKeys.length === 0 ||
        requestedCategoryKeys.some((key) => !POST_CATEGORY_KEYS.has(key))) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid post tags.');
    }
    const categoryKey = requestedCategoryKeys[0];
    const frozen = await resolveFrozenAudience(
      uid,
      data.visibility,
      data.visibleToCategoryIds,
    );
    if (frozen.visibilityMode === 'friends') {
      throw new functions.https.HttpsError('invalid-argument', 'Unsupported post visibility.');
    }
    const isAnonymous = data.isAnonymous === true;
    if (frozen.visibilityMode === 'category' && isAnonymous) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Group posts cannot be anonymous.',
      );
    }

    const user = await profile(uid);
    const now = admin.firestore.Timestamp.now();
    const rawLinkPreview = sharedLinkPreview(data.linkPreview, now);
    const content = text(data.content, 10000, 'content');
    const image = externalShareJpeg(data.imageBase64);
    if (!content && !rawLinkPreview && !image) {
      throw new functions.https.HttpsError('invalid-argument', 'Post content is empty.');
    }

    const notificationAudienceUserIdsFrozen = frozen.visibilityMode === 'public'
      ? await resolveFriendNotificationAudience(uid)
      : frozen.audienceUserIdsFrozen.filter((userId) => userId !== uid);

    let uploadedPath = '';
    let imageUrls: string[] = [];
    if (image) {
      uploadedPath = `posts/external-${postId}.jpg`;
      const token = crypto.randomUUID();
      const bucket = admin.storage().bucket();
      await bucket.file(uploadedPath).save(image, {
        resumable: false,
        contentType: 'image/jpeg',
        metadata: {
          cacheControl: 'public,max-age=31536000,immutable',
          metadata: {firebaseStorageDownloadTokens: token},
        },
      });
      imageUrls = [
        `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucket.name)}` +
        `/o/${encodeURIComponent(uploadedPath)}?alt=media&token=${encodeURIComponent(token)}`,
      ];
    }

    const linkPreview = sharedLinkPreviewWithImageFallback(
      rawLinkPreview,
      imageUrls,
    );
    const document: FirebaseFirestore.DocumentData = {
      userId: uid,
      ownerId: uid,
      authorNickname: text(user.nickname, 80, 'nickname') || 'User',
      authorNationality: text(user.nationality, 80, 'nationality'),
      authorPhotoURL: text(user.photoURL, 2048, 'photoURL'),
      title: '',
      content,
      categoryKey,
      categoryKeys: requestedCategoryKeys,
      imageUrls,
      createdAt: now,
      updatedAt: now,
      visibility: frozen.visibilityMode,
      visibleToCategoryIds: frozen.sourceGroupIds,
      allowedUserIds: frozen.audienceUserIdsFrozen,
      visibilityMode: frozen.visibilityMode,
      audienceUserIdsFrozen: frozen.audienceUserIdsFrozen,
      sourceGroupIds: frozen.sourceGroupIds,
      notificationAudienceUserIdsFrozen,
      visibilityLockedAt: now,
      visibilitySchemaVersion: VISIBILITY_SCHEMA_VERSION,
      isAnonymous,
      likes: 0,
      likedBy: [],
      commentCount: 0,
      viewCount: 0,
      type: 'text',
      externalShareRequestId: requestId,
      ...(linkPreview ? {linkPreview} : {}),
    };

    try {
      await postRef.create(document);
    } catch (error) {
      const raced = await postRef.get();
      if (raced.exists &&
          (raced.get('ownerId') === uid || raced.get('userId') === uid)) {
        return {postId, duplicate: true};
      }
      if (uploadedPath) {
        await admin.storage().bucket().file(uploadedPath).delete({ignoreNotFound: true})
          .catch(() => undefined);
      }
      throw error;
    }

    console.log(
      `content-created type=external-share-post id=${postId} owner=${uid} ` +
      `requestId=${requestId} visibility=${frozen.visibilityMode} schema=2`,
    );
    return {postId, duplicate: false};
  });

export const createMeetupSecure = functions.runWith({timeoutSeconds: 120, memory: '512MB'})
  .https.onCall(async (raw, context) => {
    const uid = requireUid(context);
    const data = object(raw);
    const meetupId = contentId(data.meetupId);
    const frozen = await resolveFrozenAudience(
      uid,
      data.visibility,
      data.visibleToCategoryIds,
    );
    const notificationAudienceUserIdsFrozen = frozen.visibilityMode === 'public'
      ? await resolveFriendNotificationAudience(uid)
      : frozen.audienceUserIdsFrozen.filter((userId) => userId !== uid);
    const user = await profile(uid);
    const dateMillis = integer(data.dateMillis, 0, 8640000000000000, 'date');
    const startsAtMillis = integer(data.startsAtMillis, 0, 8640000000000000, 'startsAt');
    const endsAtMillis = integer(data.endsAtMillis, startsAtMillis, 8640000000000000, 'endsAt');
    const now = admin.firestore.Timestamp.now();
    const publicDurationHours = data.publicDurationHours == null
      ? null
      : integer(data.publicDurationHours, 1, 12, 'publicDurationHours');
    const publicExpiresAt = publicDurationHours == null
      ? null
      : admin.firestore.Timestamp.fromMillis(
        now.toMillis() + publicDurationHours * 60 * 60 * 1000,
      );
    const remoteUrls = stringList(data.imageUrls, 3);
    const document: FirebaseFirestore.DocumentData = {
      userId: uid,
      ownerId: uid,
      hostNickname: text(user.nickname, 80, 'nickname') || 'User',
      hostPhotoURL: text(user.photoURL, 2048, 'photoURL'),
      hostNationality: text(user.nationality, 80, 'nationality'),
      title: text(data.title, 200, 'title'),
      description: text(data.description, 5000, 'description'),
      location: text(data.location, 1000, 'location'),
      time: text(data.time, 40, 'time'),
      maxParticipants: integer(data.maxParticipants, 3, 10, 'maxParticipants'),
      currentParticipants: 1,
      participants: [uid],
      date: admin.firestore.Timestamp.fromMillis(dateMillis),
      startsAt: admin.firestore.Timestamp.fromMillis(startsAtMillis),
      endsAt: admin.firestore.Timestamp.fromMillis(endsAtMillis),
      dateKey: text(data.dateKey, 10, 'dateKey'),
      createdAt: now,
      updatedAt: now,
      category: text(data.category, 80, 'category') || '기타',
      thumbnailContent: text(data.thumbnailContent, 500, 'thumbnailContent'),
      ...(remoteUrls.length > 0 ? {thumbnailImageUrl: remoteUrls[0], imageUrls: remoteUrls} : {}),
      visibility: frozen.visibilityMode,
      visibleToCategoryIds: frozen.sourceGroupIds,
      allowedUserIds: frozen.audienceUserIdsFrozen,
      visibilityMode: frozen.visibilityMode,
      audienceUserIdsFrozen: frozen.audienceUserIdsFrozen,
      sourceGroupIds: frozen.sourceGroupIds,
      notificationAudienceUserIdsFrozen,
      visibilityLockedAt: now,
      visibilitySchemaVersion: VISIBILITY_SCHEMA_VERSION,
      isConfirmed: false,
      publicWindowStatus: publicDurationHours == null ? 'unlimited' : 'timed',
      ...(publicDurationHours == null ? {} : {
        publicDurationHours,
        publicExpiresAt,
      }),
      groupChatEnabled: false,
      kickedUserIds: [],
      status: 'active',
    };
    const ref = admin.firestore().collection(COL.meetups).doc(meetupId);
    const existing = await ref.get();
    if (existing.exists) {
      if (existing.get('ownerId') === uid || existing.get('userId') === uid) return {meetupId};
      throw new functions.https.HttpsError('already-exists', 'Meetup already exists.');
    }
    await ref.create(document);
    console.log(
      `content-created type=meetup id=${meetupId} owner=${uid} ` +
      `visibility=${frozen.visibilityMode} schema=2 ` +
      `audienceCount=${frozen.audienceUserIdsFrozen.length}`,
    );
    return {meetupId};
  });

/** 공개 제한시간과 확정이 경합해도 서버 트랜잭션에서 한 상태만 선택한다. */
export const confirmMeetupSecure = functions
  .runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const uid = requireUid(context);
    await profile(uid);
    const data = object(raw);
    const meetupId = contentId(data.meetupId);
    const ref = admin.firestore().collection(COL.meetups).doc(meetupId);

    return admin.firestore().runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        throw new functions.https.HttpsError('not-found', 'Meetup not found.');
      }
      const meetup = snapshot.data() ?? {};
      if ((meetup.ownerId ?? meetup.userId ?? '').toString() !== uid) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Only the meetup host can confirm it.',
        );
      }
      if (meetup.isConfirmed === true) return {success: true, meetupId};

      const now = admin.firestore.Timestamp.now();
      const expiresAt = meetup.publicExpiresAt;
      if (meetup.publicWindowStatus === 'expired' ||
          (expiresAt instanceof admin.firestore.Timestamp &&
            expiresAt.toMillis() <= now.toMillis())) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'The meetup publication window has expired.',
        );
      }

      transaction.update(ref, {
        isConfirmed: true,
        confirmedAt: now,
        updatedAt: now,
        publicWindowStatus: 'confirmed',
        // 확정된 문서는 만료 스케줄 쿼리에서 즉시 제외한다.
        publicExpiresAt: admin.firestore.FieldValue.delete(),
      });
      return {success: true, meetupId};
    });
  });

/**
 * 제한시간이 지난 미확정 밋업을 매분 비공개 상태로 전환한다.
 * 문서를 삭제하지 않아 경합/연관 데이터 손실을 피하고 모든 앱 목록에서 숨긴다.
 */
export const expireTimedMeetups = functions.pubsub
  .schedule('* * * * *')
  .timeZone('Asia/Seoul')
  .onRun(async () => {
    const firestore = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const snapshot = await firestore.collection(COL.meetups)
      .where('publicExpiresAt', '<=', now)
      .limit(300)
      .get();

    let expired = 0;
    for (let offset = 0; offset < snapshot.docs.length; offset += 20) {
      const chunk = snapshot.docs.slice(offset, offset + 20);
      const results = await Promise.all(chunk.map((candidate) =>
        firestore.runTransaction(async (transaction) => {
          const current = await transaction.get(candidate.ref);
          if (!current.exists) {
            return false;
          }
          const expiresAt = current.get('publicExpiresAt');
          if (!(expiresAt instanceof admin.firestore.Timestamp) ||
              expiresAt.toMillis() > now.toMillis()) {
            return false;
          }
          if (current.get('isConfirmed') === true) {
            transaction.update(candidate.ref, {
              publicWindowStatus: 'confirmed',
              publicExpiresAt: admin.firestore.FieldValue.delete(),
              updatedAt: now,
            });
            return false;
          }
          transaction.update(candidate.ref, {
            publicWindowStatus: 'expired',
            publicExpiredAt: expiresAt,
            publicExpiresAt: admin.firestore.FieldValue.delete(),
            status: 'expired',
            expiredAt: now,
            updatedAt: now,
          });
          return true;
        }),
      ));
      expired += results.filter((result) => result).length;
    }
    console.log(`expireTimedMeetups: scanned=${snapshot.size} expired=${expired}`);
    return null;
  });
