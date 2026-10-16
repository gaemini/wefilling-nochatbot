import * as functions from 'firebase-functions';
import {allKnownBuckets, bucketFor, callables, downloadUrlFor, isKnownStorageBucket, triggers, uploadBucket} from './backend';
import {
  POST_VIDEO_LIMITS,
  deleteStorageObjectQuietly,
  validateUploadedThumbnail,
  validateUploadedVideo,
} from './video_policy';
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import {COL} from './firestore_paths';
import {hasActiveHanyangClaim} from './hanyang_verification';
import {runtimeInfo, runtimeLogsEnabled} from './runtime_logging';
import {
  buildMeetupSearchIndexDocument,
  buildPostSearchIndexDocument,
  meetupSearchIndexRef,
  postSearchIndexRef,
} from './content_search';
import {
  isActiveUserData,
  resolveFriendNotificationAudience,
  resolveFrozenAudience,
  VISIBILITY_SCHEMA_VERSION,
} from './frozen_audience';
import {resolveContentTagIds, resolveTagAudience} from './interest_tags';

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

function firebaseStorageObjectPath(value: string): string {
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase().replace(/\.$/, '');
    if (url.protocol !== 'https:' || url.username || url.password) return '';
    if (host === 'firebasestorage.googleapis.com') {
      const marker = '/o/';
      const index = url.pathname.indexOf(marker);
      return index >= 0 ? decodeURIComponent(url.pathname.slice(index + marker.length)) : '';
    }
    if (host === 'storage.googleapis.com') {
      const segments = url.pathname.split('/').filter(Boolean);
      return segments.length >= 2 ? decodeURIComponent(segments.slice(1).join('/')) : '';
    }
  } catch (_) {}
  return '';
}

function isPersistentInstagramThumbnail(
  thumbnailUrl: string,
  storagePath: string,
  ownerUid: string,
  postId: string,
): boolean {
  const expectedPrefix = `post_link_previews/${ownerUid}/${postId}/`;
  return /^instagram\.(jpg|png|webp)$/.test(storagePath.slice(expectedPrefix.length)) &&
    storagePath.startsWith(expectedPrefix) &&
    firebaseStorageObjectPath(thumbnailUrl) === storagePath;
}

function sharedLinkPreview(
  raw: unknown,
  now: admin.firestore.Timestamp,
  ownerUid: string,
  postId: string,
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

  let thumbnailUrl = text(value.thumbnailUrl, 2048, 'linkPreview.thumbnailUrl');
  let thumbnailStoragePath = text(
    value.thumbnailStoragePath,
    500,
    'linkPreview.thumbnailStoragePath',
  );
  let thumbnailSource = text(value.thumbnailSource, 40, 'linkPreview.thumbnailSource');
  let thumbnailStorageBucket = text(
    value.thumbnailStorageBucket,
    230,
    'linkPreview.thumbnailStorageBucket',
  );
  if (thumbnailStorageBucket && !isKnownStorageBucket(thumbnailStorageBucket)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid thumbnail bucket.');
  }
  let thumbnailWidth = integer(
    value.thumbnailWidth ?? 0,
    0,
    10000,
    'linkPreview.thumbnailWidth',
  );
  let thumbnailHeight = integer(
    value.thumbnailHeight ?? 0,
    0,
    10000,
    'linkPreview.thumbnailHeight',
  );
  let previewVersion = integer(
    value.previewVersion ?? 0,
    0,
    100,
    'linkPreview.previewVersion',
  );
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
      : isPersistentInstagramThumbnail(
        thumbnailUrl,
        thumbnailStoragePath,
        ownerUid,
        postId,
      );
    if (!allowedThumbnail && inferredProvider === 'youtube') {
      throw new functions.https.HttpsError('invalid-argument', 'Unsupported thumbnail host.');
    }
    if (!allowedThumbnail && inferredProvider === 'instagram') {
      // Meta CDN과 /media URL은 캐시용 후보일 뿐 게시 문서의 영구
      // thumbnailUrl로 저장하지 않는다.
      thumbnailUrl = '';
      thumbnailStoragePath = '';
      thumbnailStorageBucket = '';
      thumbnailSource = '';
      thumbnailWidth = 0;
      thumbnailHeight = 0;
      previewVersion = Math.max(previewVersion, 4);
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
  const previewMode = inferredProvider === 'instagram'
    ? (thumbnailUrl ? 'image' : 'link')
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
    ...(thumbnailUrl ? {
      thumbnailStoragePath,
      thumbnailStorageBucket,
      thumbnailSource: ['share_payload', 'local_preview', 'remote_resolver']
        .includes(thumbnailSource)
        ? thumbnailSource
        : 'local_preview',
      ...(thumbnailWidth > 0 ? {thumbnailWidth} : {}),
      ...(thumbnailHeight > 0 ? {thumbnailHeight} : {}),
      previewVersion: Math.max(previewVersion, 4),
    } : {thumbnailStoragePath: '', thumbnailStorageBucket: '', thumbnailSource: '', previewVersion}),
    aspectRatio,
    previewMode,
    fetchedAt: now,
    previewStatus: previewStatus === 'ready' &&
        (inferredProvider === 'youtube' || thumbnailUrl)
      ? 'ready'
      : 'unavailable',
  };
}

async function verifiedPersistedLinkPreview(
  preview: FirebaseFirestore.DocumentData | null,
  ownerUid: string,
  postId: string,
): Promise<FirebaseFirestore.DocumentData | null> {
  if (!preview || preview.provider !== 'instagram' || !preview.thumbnailUrl) {
    return preview;
  }
  const storagePath = text(
    preview.thumbnailStoragePath,
    500,
    'linkPreview.thumbnailStoragePath',
  );
  if (!isPersistentInstagramThumbnail(
    text(preview.thumbnailUrl, 2048, 'linkPreview.thumbnailUrl'),
    storagePath,
    ownerUid,
    postId,
  )) {
    return {
      ...preview,
      thumbnailUrl: '',
      thumbnailStoragePath: '',
      thumbnailStorageBucket: '',
      thumbnailSource: '',
      previewMode: 'link',
      previewStatus: 'unavailable',
    };
  }
  try {
    const file = bucketFor(preview.thumbnailStorageBucket).file(storagePath);
    const [exists] = await file.exists();
    if (!exists) throw new Error('storage-object-not-found');
    const [metadata] = await file.getMetadata();
    const custom = metadata.metadata ?? {};
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(metadata.contentType ?? '') ||
        custom.ownerUid !== ownerUid || custom.postId !== postId ||
        custom.provider !== 'instagram') {
      throw new Error('storage-object-metadata-mismatch');
    }
    return preview;
  } catch (_) {
    return {
      ...preview,
      thumbnailUrl: '',
      thumbnailStoragePath: '',
      thumbnailStorageBucket: '',
      thumbnailSource: '',
      previewMode: 'link',
      previewStatus: 'unavailable',
    };
  }
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

function jpegImageDimensions(bytes: Buffer): {width: number; height: number} | null {
  let offset = 2;
  while (offset + 8 < bytes.length) {
    if (bytes[offset] !== 0xff) {
      offset++;
      continue;
    }
    const marker = bytes[offset + 1];
    offset += 2;
    if (marker === 0xd8 || marker === 0xd9) continue;
    if (offset + 2 > bytes.length) return null;
    const segmentLength = bytes.readUInt16BE(offset);
    if (segmentLength < 2 || offset + segmentLength > bytes.length) return null;
    const isStartOfFrame = marker >= 0xc0 && marker <= 0xcf &&
      ![0xc4, 0xc8, 0xcc].includes(marker);
    if (isStartOfFrame && segmentLength >= 7) {
      return {
        height: bytes.readUInt16BE(offset + 3),
        width: bytes.readUInt16BE(offset + 5),
      };
    }
    offset += segmentLength;
  }
  return null;
}

/**
 * Lightweight preflight for the native iOS Share Extension composer.
 * Authentication still comes from Firebase Auth's shared Apple Keychain; the
 * response contains display-only group metadata and never returns credentials.
 */
export const getExternalShareComposerContext = callables()
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
function firebaseStorageBucketFromUrl(raw: string): string {
  try {
    const url = new URL(raw);
    if (url.protocol !== 'https:' || url.hostname !== 'firebasestorage.googleapis.com') return '';
    const match = url.pathname.match(/^\/v0\/b\/([^/]+)\/o\//);
    return match ? decodeURIComponent(match[1]) : '';
  } catch (_) {
    return '';
  }
}

/** Deletes a post-owned image object referenced by a download URL. */
async function deletePostImageByUrl(rawUrl: string): Promise<void> {
  const objectPath = firebaseStorageObjectPath(rawUrl);
  const bucket = firebaseStorageBucketFromUrl(rawUrl);
  // 게시글 이미지는 posts/{uuid}.jpg 또는 posts/external-{postId}.jpg 뿐이다.
  if (!objectPath.startsWith('posts/') || objectPath.includes('..') ||
      !bucket || !isKnownStorageBucket(bucket)) {
    return;
  }
  await deleteStorageObjectQuietly(objectPath, bucket);
}

type PostVideoDocument = {
  url: string;
  storagePath: string;
  storageBucket: string;
  thumbnailUrl: string;
  thumbnailPath: string;
  durationMs: number;
  width: number;
  height: number;
  bytes: number;
};

/**
 * Verifies a client-uploaded post video (+thumbnail) and mints download
 * tokens for both objects. Invalid uploads are deleted so they never linger.
 */
async function verifiedPostVideo(
  raw: unknown,
  uid: string,
  postId: string,
): Promise<PostVideoDocument | null> {
  if (raw == null) return null;
  const data = object(raw);
  const prefix = `post_videos/${uid}/${postId}/`;
  const storagePath = text(data.storagePath, 300, 'video.storagePath');
  const thumbnailPath = text(data.thumbnailPath, 300, 'video.thumbnailPath');
  const storageBucket = text(data.storageBucket, 120, 'video.storageBucket') || null;
  if (storagePath !== `${prefix}video.mp4` || thumbnailPath !== `${prefix}thumbnail.jpg`) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid post video path.');
  }
  if (storageBucket && !isKnownStorageBucket(storageBucket)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid storage bucket.');
  }
  try {
    const video = await validateUploadedVideo({
      storagePath,
      storageBucket,
      ownerUid: uid,
      limits: POST_VIDEO_LIMITS,
      expectedPathPrefix: prefix,
    });
    await validateUploadedThumbnail({
      storagePath: thumbnailPath,
      storageBucket,
      ownerUid: uid,
      expectedPathPrefix: prefix,
    });
    const bucket = bucketFor(storageBucket ?? undefined);
    const tokens: string[] = [];
    for (const objectPath of [storagePath, thumbnailPath]) {
      const file = bucket.file(objectPath);
      const [metadata] = await file.getMetadata();
      const existing = String((metadata.metadata ?? {}).firebaseStorageDownloadTokens ?? '')
        .split(',')[0].trim();
      const token = existing || crypto.randomUUID();
      if (!existing) {
        await file.setMetadata({metadata: {firebaseStorageDownloadTokens: token}});
      }
      tokens.push(token);
    }
    return {
      url: downloadUrlFor(bucket.name, storagePath, tokens[0]),
      storagePath,
      storageBucket: bucket.name,
      thumbnailUrl: downloadUrlFor(bucket.name, thumbnailPath, tokens[1]),
      thumbnailPath,
      durationMs: Math.round(video.durationSeconds * 1000),
      width: video.width,
      height: video.height,
      bytes: video.bytes,
    };
  } catch (error) {
    // 검증에 실패한 업로드는 남기지 않는다(존재하지 않으면 무시).
    await deleteStorageObjectQuietly(storagePath, storageBucket);
    await deleteStorageObjectQuietly(thumbnailPath, storageBucket);
    throw error;
  }
}

export const createPostSecure = callables().runWith({timeoutSeconds: 120, memory: '512MB'})
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
    const tagIds = await resolveContentTagIds(data.tagIds);
    const tagAudience = await resolveTagAudience(uid, data, tagIds);
    const frozen = tagAudience?.frozen ?? await resolveFrozenAudience(
      uid,
      data.visibility,
      data.visibleToCategoryIds,
    );
    // 현재 포스트 UI는 public/group(+태그)만 제공한다. 친구 공개는 '#태그 · 친구 중에서만'뿐.
    if (frozen.visibilityMode === 'friends' && !tagAudience) {
      throw new functions.https.HttpsError('invalid-argument', 'Unsupported post visibility.');
    }
    const isAnonymous = data.isAnonymous === true;
    if (frozen.visibilityMode === 'category' && isAnonymous) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Group posts cannot be anonymous.',
      );
    }
    const requiresHanyangVerification =
      data.requiresHanyangVerification === true;
    if (requiresHanyangVerification &&
        (frozen.visibilityMode !== 'public' || isAnonymous)) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Hanyang-only visibility cannot be combined with another visibility mode or anonymity.',
      );
    }
    // 익명 글은 친구에게 새 글 알림을 보내지 않는다(알림 = 작성자가 친구라는 노출).
    const notificationAudienceUserIdsFrozen = isAnonymous
      ? []
      : frozen.visibilityMode === 'public'
        ? await resolveFriendNotificationAudience(uid)
        : frozen.audienceUserIdsFrozen.filter((userId) => userId !== uid);
    const user = await profile(uid);
    if (requiresHanyangVerification && !(await hasActiveHanyangClaim(uid))) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Hanyang email verification is required for Hanyang-only posts.',
      );
    }
    const now = admin.firestore.Timestamp.now();
    const linkPreview = await verifiedPersistedLinkPreview(
      sharedLinkPreview(data.linkPreview, now, uid, postId),
      uid,
      postId,
    );
    const type = text(data.type, 20, 'type') || 'text';
    const content = text(data.content, 10000, 'content');
    const pollOptions = stringList(data.pollOptions, 2, 200);
    if (type === 'poll' && (content.length === 0 || pollOptions.length !== 2)) {
      throw new functions.https.HttpsError('invalid-argument', 'A poll needs a question and two options.');
    }
    if (data.video != null && type !== 'text') {
      throw new functions.https.HttpsError('invalid-argument', 'Only text posts can carry a video.');
    }
    // 같은 postId 재시도는 이미 연결된 영상 객체를 다시 검증하지 않는다.
    const ref = admin.firestore().collection(COL.posts).doc(postId);
    const existing = await ref.get();
    if (existing.exists) {
      if (existing.get('ownerId') === uid || existing.get('userId') === uid) return {postId};
      throw new functions.https.HttpsError('already-exists', 'Post already exists.');
    }
    const video = await verifiedPostVideo(data.video, uid, postId);
    const rawImageUrls = stringList(data.imageUrls, 15);
    // 영상 썸네일을 imageUrls[0]에도 넣어 목록·알림·프로필 그리드의 기존
    // 썸네일 경로가 그대로 동작하게 한다. 카드/상세는 video를 우선 렌더링한다.
    const imageUrls = video
      ? [video.thumbnailUrl, ...rawImageUrls.filter((url) => url !== video.thumbnailUrl)]
      : rawImageUrls;

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
      tagIds,
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
      ...(tagAudience ? {
        audienceTagIds: tagAudience.audienceTagIds,
        audienceFriendsOnly: tagAudience.friendsOnly,
      } : {}),
      requiresHanyangVerification,
      isAnonymous,
      likes: 0,
      likedBy: [],
      commentCount: 0,
      viewCount: 0,
      type,
      ...(linkPreview ? {linkPreview} : {}),
      ...(video ? {video} : {}),
      ...(type === 'poll' ? {
        pollOptions: pollOptions.map((option, index) => ({id: `${index}`, text: option, votes: 0})),
        pollTotalVotes: 0,
      } : {}),
    };
    const batch = admin.firestore().batch();
    batch.create(ref, document);
    batch.set(
      postSearchIndexRef(postId),
      buildPostSearchIndexDocument(document, now),
    );
    try {
      await batch.commit();
    } catch (error) {
      // 클라이언트 타임아웃 재시도가 첫 요청과 겹치면 create가 이미 성공해
      // 있을 수 있다. 같은 작성자의 문서면 성공으로 돌려 중복 생성·실패
      // 표시를 막는다.
      const code = Number((error as {code?: unknown})?.code);
      if (code === 6) {
        const duplicate = await ref.get();
        if (duplicate.exists &&
            (duplicate.get('ownerId') === uid || duplicate.get('userId') === uid)) {
          return {postId};
        }
      }
      throw error;
    }
    runtimeLogsEnabled && runtimeInfo(
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
export const createExternalSharePost = callables()
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

    const requiresHanyangVerification =
      data.requiresHanyangVerification === true;
    if (requiresHanyangVerification &&
        (frozen.visibilityMode !== 'public' || isAnonymous)) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Hanyang-only visibility cannot be combined with another visibility mode or anonymity.',
      );
    }

    const user = await profile(uid);
    if (requiresHanyangVerification && !(await hasActiveHanyangClaim(uid))) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Hanyang email verification is required for Hanyang-only posts.',
      );
    }
    const now = admin.firestore.Timestamp.now();
    let linkPreview = sharedLinkPreview(data.linkPreview, now, uid, postId);
    const content = text(data.content, 10000, 'content');
    const image = externalShareJpeg(data.imageBase64);
    if (!content && !linkPreview && !image) {
      throw new functions.https.HttpsError('invalid-argument', 'Post content is empty.');
    }

    // 익명 글은 친구에게 새 글 알림을 보내지 않는다(알림 = 작성자가 친구라는 노출).
    const notificationAudienceUserIdsFrozen = isAnonymous
      ? []
      : frozen.visibilityMode === 'public'
        ? await resolveFriendNotificationAudience(uid)
        : frozen.audienceUserIdsFrozen.filter((userId) => userId !== uid);

    let uploadedPath = '';
    let uploadedPreviewPath = '';
    let imageUrls: string[] = [];
    if (image) {
      const token = crypto.randomUUID();
      const bucket = uploadBucket();
      if (linkPreview?.provider === 'instagram') {
        uploadedPreviewPath = `post_link_previews/${uid}/${postId}/instagram.jpg`;
        const dimensions = jpegImageDimensions(image);
        await bucket.file(uploadedPreviewPath).save(image, {
          resumable: false,
          contentType: 'image/jpeg',
          metadata: {
            cacheControl: 'public,max-age=31536000,immutable',
            metadata: {
              firebaseStorageDownloadTokens: token,
              provider: 'instagram',
              postId,
              ownerUid: uid,
              source: 'share_payload',
              width: `${dimensions?.width ?? 0}`,
              height: `${dimensions?.height ?? 0}`,
            },
          },
        });
        const thumbnailUrl =
          `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucket.name)}` +
          `/o/${encodeURIComponent(uploadedPreviewPath)}?alt=media&token=${encodeURIComponent(token)}`;
        linkPreview = {
          ...linkPreview,
          thumbnailUrl,
          thumbnailStoragePath: uploadedPreviewPath,
          thumbnailStorageBucket: bucket.name,
          thumbnailSource: 'share_payload',
          ...(dimensions ? {
            thumbnailWidth: dimensions.width,
            thumbnailHeight: dimensions.height,
            aspectRatio: Math.min(2.4, Math.max(0.5, dimensions.width / dimensions.height)),
          } : {}),
          previewMode: 'image',
          previewStatus: 'ready',
          previewVersion: 4,
        };
      } else {
        uploadedPath = `posts/external-${postId}.jpg`;
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
    }
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
      requiresHanyangVerification,
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
      const batch = admin.firestore().batch();
      batch.create(postRef, document);
      batch.set(
        postSearchIndexRef(postId),
        buildPostSearchIndexDocument(document, now),
      );
      await batch.commit();
    } catch (error) {
      const raced = await postRef.get();
      if (raced.exists &&
          (raced.get('ownerId') === uid || raced.get('userId') === uid)) {
        return {postId, duplicate: true};
      }
      if (uploadedPath) {
        await uploadBucket().file(uploadedPath).delete({ignoreNotFound: true})
          .catch(() => undefined);
      }
      if (uploadedPreviewPath) {
        await uploadBucket().file(uploadedPreviewPath).delete({ignoreNotFound: true})
          .catch(() => undefined);
      }
      throw error;
    }

    runtimeLogsEnabled && runtimeInfo(
      `content-created type=external-share-post id=${postId} owner=${uid} ` +
      `requestId=${requestId} visibility=${frozen.visibilityMode} schema=2`,
    );
    return {postId, duplicate: false};
  });

export const createMeetupSecure = callables().runWith({timeoutSeconds: 120, memory: '512MB'})
  .https.onCall(async (raw, context) => {
    const uid = requireUid(context);
    const data = object(raw);
    const meetupId = contentId(data.meetupId);
    const tagIds = await resolveContentTagIds(data.tagIds);
    const tagAudience = await resolveTagAudience(uid, data, tagIds);
    const frozen = tagAudience?.frozen ?? await resolveFrozenAudience(
      uid,
      data.visibility,
      data.visibleToCategoryIds,
    );
    const requiresHanyangVerification =
      data.requiresHanyangVerification === true;
    if (requiresHanyangVerification && frozen.visibilityMode !== 'public') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Hanyang-only visibility cannot be combined with another visibility mode.',
      );
    }
    const notificationAudienceUserIdsFrozen = frozen.visibilityMode === 'public'
      ? await resolveFriendNotificationAudience(uid)
      : frozen.audienceUserIdsFrozen.filter((userId) => userId !== uid);
    const user = await profile(uid);
    if (requiresHanyangVerification && !(await hasActiveHanyangClaim(uid))) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Hanyang email verification is required for Hanyang-only meetups.',
      );
    }
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
      tagIds,
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
      ...(tagAudience ? {
        audienceTagIds: tagAudience.audienceTagIds,
        audienceFriendsOnly: tagAudience.friendsOnly,
      } : {}),
      requiresHanyangVerification,
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
    const batch = admin.firestore().batch();
    batch.create(ref, document);
    batch.set(
      meetupSearchIndexRef(meetupId),
      buildMeetupSearchIndexDocument(document, now),
    );
    await batch.commit();
    runtimeLogsEnabled && runtimeInfo(
      `content-created type=meetup id=${meetupId} owner=${uid} ` +
      `visibility=${frozen.visibilityMode} schema=2 ` +
      `audienceCount=${frozen.audienceUserIdsFrozen.length}`,
    );
    return {meetupId};
  });

/** 공개 제한시간과 확정이 경합해도 서버 트랜잭션에서 한 상태만 선택한다. */
export const confirmMeetupSecure = callables()
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
export const expireTimedMeetups = triggers().pubsub
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
    runtimeLogsEnabled && runtimeInfo(`expireTimedMeetups: scanned=${snapshot.size} expired=${expired}`);
    return null;
  });

/**
 * Post media lives in Storage objects the client can no longer delete (posts/
 * objects are create-only; post_videos/ is owner-deletable only before the
 * document exists). Server-side cleanup keeps storage cost bounded.
 */
async function deletePostMedia(data: FirebaseFirestore.DocumentData | undefined, postId: string) {
  if (!data) return;
  const video = data.video && typeof data.video === 'object' ? data.video as Record<string, unknown> : null;
  const thumbnailUrl = video ? String(video.thumbnailUrl ?? '') : '';
  const imageUrls: string[] = Array.isArray(data.imageUrls)
    ? data.imageUrls.filter((url: unknown): url is string => typeof url === 'string')
    : [];
  await Promise.all(imageUrls
    .filter((url) => url !== thumbnailUrl)
    .map((url) => deletePostImageByUrl(url)));
  const ownerUid = String(data.ownerId ?? data.userId ?? '');
  if (ownerUid && ownerUid !== 'deleted') {
    await Promise.all(allKnownBuckets().map((bucket) =>
      bucket.deleteFiles({prefix: `post_videos/${ownerUid}/${postId}/`}).catch(() => undefined)));
    await Promise.all(allKnownBuckets().map((bucket) =>
      bucket.deleteFiles({prefix: `post_link_previews/${ownerUid}/${postId}/`}).catch(() => undefined)));
  } else if (video) {
    await deleteStorageObjectQuietly(String(video.storagePath ?? ''), String(video.storageBucket ?? '') || null);
    await deleteStorageObjectQuietly(String(video.thumbnailPath ?? ''), String(video.storageBucket ?? '') || null);
  }
}

export const onPostDeletedStorageCleanup = triggers().firestore
  .document('posts/{postId}')
  .onDelete(async (snapshot, context) => {
    try {
      await deletePostMedia(snapshot.data(), String(context.params.postId));
    } catch (error) {
      console.warn('post media cleanup failed', {postId: context.params.postId, message: (error as Error)?.message});
    }
  });

/** Images removed while editing a post are deleted once the edit is saved. */
export const onPostUpdatedStorageCleanup = triggers().firestore
  .document('posts/{postId}')
  .onUpdate(async (change) => {
    try {
      const before = change.before.data() ?? {};
      const after = change.after.data() ?? {};
      const afterUrls = new Set<string>(Array.isArray(after.imageUrls) ? after.imageUrls : []);
      const video = after.video && typeof after.video === 'object' ? after.video as Record<string, unknown> : null;
      const thumbnailUrl = video ? String(video.thumbnailUrl ?? '') : '';
      const removed: string[] = (Array.isArray(before.imageUrls) ? before.imageUrls : [])
        .filter((url: unknown): url is string => typeof url === 'string' && !afterUrls.has(url) && url !== thumbnailUrl);
      await Promise.all(removed.map((url) => deletePostImageByUrl(url)));
    } catch (error) {
      console.warn('post image cleanup failed', {message: (error as Error)?.message});
    }
  });
