import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import {COL} from './firestore_paths';
import {runtimeInfo, runtimeLogsEnabled} from './runtime_logging';
import {
  isActiveUserData,
  resolveFrozenAudience,
  VISIBILITY_SCHEMA_VERSION,
} from './frozen_audience';

const SNAPSHOT_FEED = 'snapshot_feed';
const MAX_IMAGE_BYTES = 15 * 1024 * 1024;
const MAX_VIDEO_DURATION_SECONDS = 12;
const SNAPSHOT_LIFETIME_MS = 24 * 60 * 60 * 1000;
const ORPHAN_UPLOAD_GRACE_MS = 2 * 60 * 60 * 1000;
const ALLOWED_VISIBILITIES = new Set(['public', 'friends', 'category']);
const ALLOWED_REACTIONS = new Set(['❤️']);

type SnapshotVisibility = 'public' | 'friends' | 'category';
type SnapshotMediaType = 'photo' | 'video';

type Mp4TrackInfo = {
  codec?: string;
  track_width?: number;
  track_height?: number;
  video?: {width?: number; height?: number};
};

type Mp4ReadyInfo = {
  duration?: number;
  timescale?: number;
  tracks?: Mp4TrackInfo[];
  videoTracks?: Mp4TrackInfo[];
};

type Mp4Parser = {
  onReady?: (info: Mp4ReadyInfo) => void;
  onError?: (error: unknown) => void;
  appendBuffer: (buffer: ArrayBuffer & {fileStart?: number}) => void;
  flush: () => void;
};

// mp4box is used only to inspect the already client-transcoded MP4. Chunks are
// streamed from disk; the function never creates a whole-file Buffer.
const MP4Box = require('mp4box') as {createFile(): Mp4Parser};

function snapshotReactionCopy(
  reaction: string,
  actorName: string,
  isKorean: boolean,
): {title: string; message: string} {
  if (isKorean) {
    if (reaction === '👏') {
      return {
        title: '스낵에 박수가 도착했어요',
        message: `${actorName}님이 회원님의 스낵에 박수를 보냈어요.`,
      };
    }
    if (reaction === '😊') {
      return {
        title: '스낵에 미소가 도착했어요',
        message: `${actorName}님이 회원님의 스낵을 보고 미소 지었어요.`,
      };
    }
    return {
      title: '스낵을 좋아해요',
      message: `${actorName}님이 회원님의 스낵을 좋아해요.`,
    };
  }
  if (reaction === '👏') {
    return {
      title: 'Applause for your Snack',
      message: `${actorName} applauded your Snack.`,
    };
  }
  if (reaction === '😊') {
    return {
      title: 'A smile for your Snack',
      message: `${actorName} smiled at your Snack.`,
    };
  }
  return {
    title: 'Someone liked your Snack',
    message: `${actorName} liked your Snack.`,
  };
}

function prefersKoreanNotification(data: FirebaseFirestore.DocumentData): boolean {
  const locale = text(data.preferredLanguage ?? data.locale ?? data.language).toLowerCase();
  if (locale.startsWith('en')) return false;
  if (locale.startsWith('ko')) return true;
  const nationality = text(data.nationality ?? data.country).toLowerCase();
  if (nationality.includes('korea') || nationality.includes('한국')) return true;
  return true;
}

function db(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

function snapshotBucket() {
  return admin.storage().bucket();
}

function requireUid(context: functions.https.CallableContext): string {
  const uid = context.auth?.uid?.trim() ?? '';
  if (!uid) {
    throw new functions.https.HttpsError('unauthenticated', 'Sign-in is required.');
  }
  return uid;
}

function text(value: unknown): string {
  return (value ?? '').toString().trim();
}

function validSnapshotId(value: unknown): string {
  const id = text(value);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid snapshot id.');
  }
  return id;
}

function validRequestId(value: unknown): string {
  const id = text(value);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid request id.');
  }
  return id;
}

function validNotificationId(value: unknown): string {
  const id = text(value);
  if (!/^[A-Za-z0-9_-]{1,220}$/.test(id)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid notification id.');
  }
  return id;
}

function validSnapshotComment(value: unknown): string {
  const message = text(value);
  const length = Array.from(message).length;
  if (length < 1 || length > 120 || message.includes('\n')) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid comment.');
  }
  return message;
}

function validSnapshotFeedComment(value: unknown): string {
  const message = text(value);
  const length = Array.from(message).length;
  if (length < 1 || length > 500 || message.split('\n').length > 20) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid comment.');
  }
  return message;
}

function validVisibility(value: unknown): SnapshotVisibility {
  const visibility = text(value);
  if (!ALLOWED_VISIBILITIES.has(visibility)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid visibility.');
  }
  return visibility as SnapshotVisibility;
}

function categoryIds(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const ids = Array.from(new Set(value.map(text).filter(Boolean)));
  if (ids.length > 10) {
    throw new functions.https.HttpsError('invalid-argument', 'Too many friend groups.');
  }
  return ids;
}

function positiveInteger(value: unknown, field: string): number {
  const numberValue = Number(value);
  if (!Number.isInteger(numberValue) || numberValue < 1 || numberValue > 10000) {
    throw new functions.https.HttpsError('invalid-argument', `Invalid ${field}.`);
  }
  return numberValue;
}

function finiteNumber(value: unknown, field: string, min: number, max: number): number {
  const numberValue = Number(value);
  if (!Number.isFinite(numberValue) || numberValue < min || numberValue > max) {
    throw new functions.https.HttpsError('invalid-argument', `Invalid ${field}.`);
  }
  return numberValue;
}

function parseOverlay(value: unknown) {
  const overlay = value && typeof value === 'object'
    ? value as Record<string, unknown>
    : {};
  const overlayText = text(overlay.text);
  if (Array.from(overlayText).length > 60 || overlayText.split('\n').length > 3) {
    throw new functions.https.HttpsError('invalid-argument', 'Overlay text is too long.');
  }
  return {
    text: overlayText,
    x: finiteNumber(overlay.x ?? 0.5, 'overlay.x', 0, 1),
    y: finiteNumber(overlay.y ?? 0.5, 'overlay.y', 0, 1),
    lightText: overlay.lightText !== false,
    fontScale: finiteNumber(overlay.fontScale ?? 1, 'overlay.fontScale', 0.25, 1.75),
  };
}

function parseOverlays(value: unknown) {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > 5) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid text overlays.');
  }
  const parsed = value.map((raw, index) => {
    const overlay = raw && typeof raw === 'object'
      ? raw as Record<string, unknown>
      : {};
    const overlayText = text(overlay.text);
    if (Array.from(overlayText).length > 240 || overlayText.split('\n').length > 12) {
      throw new functions.https.HttpsError('invalid-argument', 'Overlay text is too long.');
    }
    const id = text(overlay.id);
    if (!/^[A-Za-z0-9_-]{1,100}$/.test(id)) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid overlay id.');
    }
    return {
      id,
      text: overlayText,
      x: finiteNumber(overlay.x ?? 0.5, 'overlays.x', 0, 1),
      y: finiteNumber(overlay.y ?? 0.5, 'overlays.y', 0, 1),
      lightText: overlay.lightText !== false,
      fontScale: finiteNumber(overlay.fontScale ?? 1, 'overlays.fontScale', 0.25, 1.75),
      order: index,
    };
  }).filter((overlay) => overlay.text.length > 0);
  if (new Set(parsed.map((overlay) => overlay.id)).size !== parsed.length) {
    throw new functions.https.HttpsError('invalid-argument', 'Duplicate overlay id.');
  }
  return parsed;
}

function validMediaType(value: unknown): SnapshotMediaType {
  const mediaType = text(value) || 'photo';
  if (mediaType !== 'photo' && mediaType !== 'video') {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid media type.');
  }
  return mediaType;
}

async function inspectMp4File(localPath: string): Promise<{
  durationMs: number;
  width: number;
  height: number;
  codec: string;
}> {
  return new Promise((resolve, reject) => {
    const parser = MP4Box.createFile();
    const input = fs.createReadStream(localPath, {highWaterMark: 1024 * 1024});
    let offset = 0;
    let settled = false;

    const fail = (error: unknown) => {
      if (settled) return;
      settled = true;
      input.destroy();
      reject(error instanceof Error ? error : new Error(String(error)));
    };

    parser.onError = fail;
    parser.onReady = (info) => {
      if (settled) return;
      const timescale = Number(info.timescale ?? 0);
      const duration = Number(info.duration ?? 0);
      const tracks = Array.isArray(info.videoTracks) && info.videoTracks.length > 0
        ? info.videoTracks
        : (Array.isArray(info.tracks)
          ? info.tracks.filter((track) => track.video != null)
          : []);
      const track = tracks[0];
      const seconds = timescale > 0 ? duration / timescale : 0;
      const width = Number(track?.video?.width ?? track?.track_width ?? 0);
      const height = Number(track?.video?.height ?? track?.track_height ?? 0);
      const codec = text(track?.codec).toLowerCase();
      if (!track || !Number.isFinite(seconds) || seconds <= 0 ||
          seconds > MAX_VIDEO_DURATION_SECONDS || width < 1 || height < 1 ||
          !/^(avc1|avc3|hvc1|hev1)/.test(codec)) {
        fail(new Error('invalid-video-stream'));
        return;
      }
      settled = true;
      input.destroy();
      resolve({
        durationMs: Math.round(seconds * 1000),
        width: Math.round(width),
        height: Math.round(height),
        codec,
      });
    };

    input.on('data', (chunk: string | Buffer) => {
      if (settled) return;
      try {
        const source = typeof chunk === 'string' ? Buffer.from(chunk) : chunk;
        const copy = new Uint8Array(source.byteLength);
        copy.set(source);
        const buffer = copy.buffer as ArrayBuffer & {fileStart?: number};
        buffer.fileStart = offset;
        offset += source.byteLength;
        parser.appendBuffer(buffer);
      } catch (error) {
        fail(error);
      }
    });
    input.on('error', fail);
    input.on('end', () => {
      if (settled) return;
      try {
        parser.flush();
      } catch (error) {
        fail(error);
        return;
      }
      setImmediate(() => {
        if (!settled) fail(new Error('video-metadata-missing'));
      });
    });
  });
}

async function inspectSnapshotVideo(
  snapshotId: string,
  file: ReturnType<ReturnType<typeof snapshotBucket>['file']>,
) {
  const localPath = path.join(
    os.tmpdir(),
    `snapshot_${snapshotId}_${Date.now()}_${Math.random().toString(36).slice(2)}.mp4`,
  );
  try {
    await file.download({destination: localPath});
    return await inspectMp4File(localPath);
  } finally {
    await fs.promises.unlink(localPath).catch(() => undefined);
  }
}

function profileUniversity(data: FirebaseFirestore.DocumentData): string {
  return text(data.university ?? data.school ?? data.schoolId);
}

async function isBlocked(uidA: string, uidB: string): Promise<boolean> {
  if (uidA === uidB) return false;
  const store = db();
  const [a, b] = await Promise.all([
    store.collection(COL.blocks).doc(`${uidA}_${uidB}`).get(),
    store.collection(COL.blocks).doc(`${uidB}_${uidA}`).get(),
  ]);
  return a.exists || b.exists;
}

function isTimestamp(value: unknown): value is admin.firestore.Timestamp {
  return value instanceof admin.firestore.Timestamp;
}

function timestampMillis(value: unknown): number {
  if (isTimestamp(value)) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : 0;
}

function hasSnapshotDocumentAccess(
  viewerUid: string,
  data: FirebaseFirestore.DocumentData,
  now = admin.firestore.Timestamp.now(),
): boolean {
  const authorId = text(data.ownerId ?? data.authorId);
  if (!authorId || data.status !== 'active' || !isTimestamp(data.expiresAt) ||
      data.expiresAt.toMillis() <= now.toMillis()) {
    return false;
  }
  if (viewerUid === authorId) return true;

  const schemaVersion = Number(data.visibilitySchemaVersion ?? 0);
  if (schemaVersion >= VISIBILITY_SCHEMA_VERSION) {
    if (data.visibilityMode === 'public') return true;
    return Array.isArray(data.audienceUserIdsFrozen) &&
      data.audienceUserIdsFrozen.map(text).includes(viewerUid);
  }

  // 레거시 문서는 마이그레이션 기간에만 기존 저장 배열을 사용한다.
  // 현재 친구/그룹 문서를 다시 읽어 과거 대상자를 바꾸지는 않는다.
  if (data.visibility === 'public') return true;
  if (data.visibility === 'friends' || data.visibility === 'category') {
    return Array.isArray(data.allowedUserIds) &&
      data.allowedUserIds.map(text).includes(viewerUid);
  }
  return false;
}

async function canAccessSnapshot(
  viewerUid: string,
  data: FirebaseFirestore.DocumentData,
  now = admin.firestore.Timestamp.now(),
): Promise<boolean> {
  if (!hasSnapshotDocumentAccess(viewerUid, data, now)) return false;
  const authorId = text(data.ownerId ?? data.authorId);
  return viewerUid === authorId || !(await isBlocked(viewerUid, authorId));
}

function snapshotFeedData(
  snapshotId: string,
  data: FirebaseFirestore.DocumentData,
): FirebaseFirestore.DocumentData {
  return {
    snapshotId,
    authorId: text(data.ownerId ?? data.authorId),
    authorName: text(data.authorName) || 'User',
    authorPhotoUrl: text(data.authorPhotoUrl),
    authorNationality: text(data.authorNationality),
    university: text(data.university),
    storagePath: text(data.storagePath),
    imageStoragePath: text(data.imageStoragePath ?? data.storagePath),
    videoStoragePath: text(data.videoStoragePath),
    thumbnailStoragePath: text(data.thumbnailStoragePath),
    mediaType: text(data.mediaType) || 'photo',
    durationMs: Number(data.durationMs ?? 0),
    imageUrl: text(data.imageUrl),
    visibility: data.visibility,
    ownerId: text(data.ownerId ?? data.authorId),
    visibilityMode: data.visibilityMode ?? data.visibility,
    audienceUserIdsFrozen: Array.isArray(data.audienceUserIdsFrozen)
      ? data.audienceUserIdsFrozen.map(text).filter(Boolean)
      : (Array.isArray(data.allowedUserIds) ? data.allowedUserIds.map(text).filter(Boolean) : []),
    sourceGroupIds: Array.isArray(data.sourceGroupIds)
      ? data.sourceGroupIds.map(text).filter(Boolean)
      : (Array.isArray(data.visibleToCategoryIds) ? data.visibleToCategoryIds.map(text).filter(Boolean) : []),
    visibilityLockedAt: data.visibilityLockedAt ?? data.createdAt,
    visibilitySchemaVersion: Number(data.visibilitySchemaVersion ?? 0),
    visibleToCategoryIds: Array.isArray(data.visibleToCategoryIds)
      ? data.visibleToCategoryIds.map(text).filter(Boolean)
      : [],
    allowedUserIds: Array.isArray(data.allowedUserIds)
      ? data.allowedUserIds.map(text).filter(Boolean)
      : [],
    overlay: data.overlay ?? {text: '', x: 0.5, y: 0.5, lightText: true},
    overlays: Array.isArray(data.overlays) ? data.overlays.slice(0, 5) : [],
    aspectRatio: Number(data.aspectRatio) || 0.8,
    reactionCounts: data.reactionCounts ?? {},
    commentCount: Math.max(0, Number(data.commentCount ?? 0) || 0),
    createdAt: data.createdAt,
    expiresAt: data.expiresAt,
    status: data.status,
  };
}

async function unblockedViewerIds(authorId: string, viewerIds: Iterable<string>) {
  const ids = Array.from(new Set(viewerIds)).filter((uid) => uid && uid !== authorId);
  if (ids.length === 0) return [authorId];
  const store = db();
  const refs: FirebaseFirestore.DocumentReference[] = [];
  for (const uid of ids) {
    refs.push(store.collection(COL.blocks).doc(`${authorId}_${uid}`));
    refs.push(store.collection(COL.blocks).doc(`${uid}_${authorId}`));
  }
  const docs = await store.getAll(...refs);
  const result = [authorId];
  for (let i = 0; i < ids.length; i += 1) {
    if (!docs[i * 2].exists && !docs[i * 2 + 1].exists) result.push(ids[i]);
  }
  return result;
}

async function resolveViewerIds(data: FirebaseFirestore.DocumentData): Promise<string[]> {
  const authorId = text(data.ownerId ?? data.authorId);
  if (!authorId) return [];
  const candidates = new Set<string>([authorId]);
  const store = db();

  if ((data.visibilityMode ?? data.visibility) === 'public') {
    const users = await store.collection(COL.users).select(
      'isDeleted', 'deleted', 'disabled', 'isSuspended', 'status',
    ).get();
    for (const user of users.docs) {
      if (isActiveUserData(user.data())) candidates.add(user.id);
    }
  } else if (Array.isArray(data.audienceUserIdsFrozen)) {
    for (const uid of data.audienceUserIdsFrozen) candidates.add(text(uid));
  } else if (Array.isArray(data.allowedUserIds)) {
    // 레거시 호환: 이미 문서에 저장된 UID만 사용한다.
    for (const uid of data.allowedUserIds) candidates.add(text(uid));
  }
  return unblockedViewerIds(authorId, candidates);
}

async function fanOutSnapshot(
  snapshotId: string,
  data: FirebaseFirestore.DocumentData,
): Promise<void> {
  const viewers = await resolveViewerIds(data);
  const writer = db().bulkWriter();
  const feedData = snapshotFeedData(snapshotId, data);
  for (const viewerId of viewers) {
    writer.set(
      db().collection(COL.users).doc(viewerId).collection(SNAPSHOT_FEED).doc(snapshotId),
      feedData,
    );
  }
  await writer.close();
}

async function deleteQuery(query: FirebaseFirestore.Query): Promise<void> {
  while (true) {
    const result = await query.limit(400).get();
    if (result.empty) return;
    const writer = db().bulkWriter();
    for (const doc of result.docs) writer.delete(doc.ref);
    await writer.close();
    if (result.size < 400) return;
  }
}

// 고정 limit으로 결과를 잘라내지 않고 작은 페이지를 끝까지 순회한다.
// 한 번의 Firestore 응답 크기는 제한하면서도 사용자가 볼 수 있는 스낵/조회자
// 총개수에는 상한을 두지 않는다.
async function readAllQueryDocuments(
  query: FirebaseFirestore.Query,
  pageSize = 400,
): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  const documents: FirebaseFirestore.QueryDocumentSnapshot[] = [];
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  while (true) {
    let pageQuery = query.limit(pageSize);
    if (cursor) pageQuery = pageQuery.startAfter(cursor);
    const page = await pageQuery.get();
    if (page.empty) break;
    documents.push(...page.docs);
    cursor = page.docs[page.docs.length - 1];
    if (page.size < pageSize) break;
  }
  return documents;
}

async function removeSnapshotFromFeeds(
  snapshotId: string,
  data: FirebaseFirestore.DocumentData,
): Promise<void> {
  const store = db();
  const viewerIds = new Set<string>();
  const authorId = text(data.ownerId ?? data.authorId);
  if (authorId) viewerIds.add(authorId);

  const visibilityMode = text(data.visibilityMode ?? data.visibility);
  if (visibilityMode === 'public') {
    // 공개 스낵은 생성 시점의 사용자별 피드에 복제된다. 컬렉션 그룹
    // 조회는 snapshotId의 COLLECTION_GROUP 인덱스가 없으면 삭제 전체를
    // 중단시키므로, 사용자 문서를 기준으로 피드 문서 ID를 직접 지운다.
    const users = await store.collection(COL.users).select().get();
    for (const user of users.docs) viewerIds.add(user.id);
  } else {
    const frozenAudience = Array.isArray(data.audienceUserIdsFrozen)
      ? data.audienceUserIdsFrozen
      : (Array.isArray(data.allowedUserIds) ? data.allowedUserIds : []);
    for (const uid of frozenAudience) {
      const viewerId = text(uid);
      if (viewerId) viewerIds.add(viewerId);
    }
  }

  if (viewerIds.size === 0) return;
  const writer = store.bulkWriter();
  for (const viewerId of viewerIds) {
    writer.delete(
      store.collection(COL.users).doc(viewerId).collection(SNAPSHOT_FEED).doc(snapshotId),
    );
  }
  await writer.close();
}

// 차단 관계가 바뀌면 다음 앱 재실행까지 기다리지 않고 두 사용자 사이의
// 피드 사본을 다시 계산한다. 친구/그룹 변경은 의도적으로 입력으로 사용하지
// 않는다. 원본 문서와 Storage Rules가 최종 방어선이며, 이 동기화는 차단된
// 콘텐츠의 썸네일 메타데이터도 개인 피드에서 즉시 제거한다.
async function replaceViewerAuthorFeed(
  viewerUid: string,
  authorUid: string,
): Promise<void> {
  if (!viewerUid || !authorUid || viewerUid === authorUid) return;
  const store = db();
  const feed = store.collection(COL.users).doc(viewerUid).collection(SNAPSHOT_FEED);
  await deleteQuery(feed.where('authorId', '==', authorUid));

  const now = admin.firestore.Timestamp.now();
  const active = await readAllQueryDocuments(store.collection(COL.snapshots)
    .where('authorId', '==', authorUid)
    .where('status', '==', 'active')
    .where('expiresAt', '>', now));
  if (active.length === 0) return;

  const writer = store.bulkWriter();
  for (const document of active) {
    const data = document.data();
    if (await canAccessSnapshot(viewerUid, data, now)) {
      writer.set(feed.doc(document.id), snapshotFeedData(document.id, data));
    }
  }
  await writer.close();
}

async function syncSnapshotFeedPair(uidA: string, uidB: string): Promise<void> {
  if (!uidA || !uidB || uidA === uidB) return;
  await Promise.all([
    replaceViewerAuthorFeed(uidA, uidB),
    replaceViewerAuthorFeed(uidB, uidA),
  ]);
}

async function deleteSnapshotNotifications(snapshotId: string): Promise<void> {
  const notifications = await db().collection(COL.notifications)
    .where('snapshotId', '==', snapshotId)
    .get();
  const deletableTypes = new Set([
    'snapshot_reaction',
    'snapshot_feed_comment',
    'snapshot_feed_comment_reply',
  ]);
  const writer = db().bulkWriter();
  for (const notification of notifications.docs) {
    // Legacy Snack letters are a separate user-visible feature and remain
    // available under their existing retention policy.
    if (deletableTypes.has(text(notification.get('type')))) {
      writer.delete(notification.ref);
    }
  }
  await writer.close();
}

async function deleteSnapshotStoragePrefix(snapshotId: string): Promise<void> {
  const [files] = await snapshotBucket().getFiles({
    prefix: `snapshots/${snapshotId}/`,
  });
  await Promise.all(files.map((file) => file.delete({ignoreNotFound: true})));
}

async function deleteSnapshotResources(
  snapshotId: string,
  data: FirebaseFirestore.DocumentData,
): Promise<void> {
  const snapshotRef = db().collection(COL.snapshots).doc(snapshotId);
  // Access checks require status=active, so this immediately closes reads and
  // writes while retaining a durable retry marker until every cleanup passes.
  await snapshotRef.set({
    status: 'deleting',
    deletionRequestedAt: data.deletionRequestedAt ??
      admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  const cleanupResults = await Promise.allSettled([
    removeSnapshotFromFeeds(snapshotId, data),
    deleteQuery(snapshotRef.collection('reactions')),
    deleteQuery(snapshotRef.collection('comments')),
    deleteQuery(snapshotRef.collection('feed_comments')),
    deleteQuery(snapshotRef.collection('views')),
    deleteSnapshotNotifications(snapshotId),
    deleteSnapshotStoragePrefix(snapshotId),
  ]);
  const failures = cleanupResults.filter((result) => result.status === 'rejected');
  for (const result of cleanupResults) {
    if (result.status === 'rejected') {
      console.warn(`snapshot ancillary cleanup failed id=${snapshotId}`, result.reason);
    }
  }
  if (failures.length > 0) {
    await snapshotRef.set({
      cleanupLastFailedAt: admin.firestore.FieldValue.serverTimestamp(),
      cleanupFailureCount: admin.firestore.FieldValue.increment(1),
    }, {merge: true});
    throw new Error(`snapshot-cleanup-incomplete:${failures.length}`);
  }
  await snapshotRef.delete();
}

export const getSnapshotServerTime = functions.https.onCall(async (_data, context) => {
  requireUid(context);
  return {nowMillis: Date.now()};
});

export const createSnapshot = functions.runWith({timeoutSeconds: 120, memory: '512MB'})
  .https.onCall(async (raw, context) => {
    const uid = requireUid(context);
    const data = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
    const snapshotId = validSnapshotId(data.snapshotId);
    const visibility = validVisibility(data.visibility);
    const selectedCategoryIds = categoryIds(data.visibleToCategoryIds);
    const mediaType = validMediaType(data.mediaType);
    const storagePath = text(data.storagePath);
    const expectedPath = mediaType === 'video'
      ? `snapshots/${snapshotId}/final.mp4`
      : `snapshots/${snapshotId}/final.jpg`;
    if (storagePath !== expectedPath) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid storage path.');
    }
    const overlay = parseOverlay(data.overlay);
    const overlays = parseOverlays(data.overlays);
    const aspectRatio = finiteNumber(data.aspectRatio, 'aspectRatio', 0.4, 2.5);
    const sourceWidth = positiveInteger(data.sourceWidth, 'sourceWidth');
    const sourceHeight = positiveInteger(data.sourceHeight, 'sourceHeight');

    const user = await db().collection(COL.users).doc(uid).get();
    if (!user.exists || user.get('emailVerified') !== true ||
        !isActiveUserData(user.data() ?? {})) {
      throw new functions.https.HttpsError('failed-precondition', 'User profile is missing.');
    }
    const profile = user.data() ?? {};
    const university = profileUniversity(profile);
    const frozen = await resolveFrozenAudience(uid, visibility, selectedCategoryIds);
    const allowedUserIds = frozen.audienceUserIdsFrozen;

    const file = snapshotBucket().file(storagePath);
    const [exists] = await file.exists();
    if (!exists) throw new functions.https.HttpsError('failed-precondition', 'Image is missing.');
    const [metadata] = await file.getMetadata();
    const custom = metadata.metadata ?? {};
    const mediaSize = Number(metadata.size ?? 0);
    const expectedContentType = mediaType === 'video' ? 'video/mp4' : 'image/jpeg';
    if (custom.ownerUid !== uid || custom.snapshotId !== snapshotId ||
        text(custom.mediaType || 'photo') !== mediaType ||
        metadata.contentType !== expectedContentType ||
        mediaSize < 1 || (mediaType === 'photo' && mediaSize > MAX_IMAGE_BYTES)) {
      throw new functions.https.HttpsError('permission-denied', 'Invalid media metadata.');
    }

    let verifiedDurationMs = 0;
    let verifiedWidth = sourceWidth;
    let verifiedHeight = sourceHeight;
    let verifiedCodec = '';
    let thumbnailStoragePath = '';
    if (mediaType === 'video') {
      thumbnailStoragePath = `snapshots/${snapshotId}/thumbnail.jpg`;
      const thumbnail = snapshotBucket().file(thumbnailStoragePath);
      const [thumbnailExists] = await thumbnail.exists();
      if (!thumbnailExists) {
        throw new functions.https.HttpsError('failed-precondition', 'Video thumbnail is missing.');
      }
      const [thumbnailMetadata] = await thumbnail.getMetadata();
      const thumbnailCustom = thumbnailMetadata.metadata ?? {};
      const thumbnailSize = Number(thumbnailMetadata.size ?? 0);
      if (thumbnailCustom.ownerUid !== uid ||
          thumbnailCustom.snapshotId !== snapshotId ||
          thumbnailCustom.mediaType !== 'video-thumbnail' ||
          thumbnailMetadata.contentType !== 'image/jpeg' ||
          thumbnailSize < 1 || thumbnailSize > MAX_IMAGE_BYTES) {
        throw new functions.https.HttpsError('permission-denied', 'Invalid video thumbnail.');
      }
      try {
        const inspected = await inspectSnapshotVideo(snapshotId, file);
        verifiedDurationMs = inspected.durationMs;
        verifiedWidth = inspected.width;
        verifiedHeight = inspected.height;
        verifiedCodec = inspected.codec;
      } catch (error) {
        console.warn(`snapshot video validation failed id=${snapshotId}`, error);
        throw new functions.https.HttpsError(
          'failed-precondition',
          'The video format or duration is not supported.',
        );
      }
    }

    const ref = db().collection(COL.snapshots).doc(snapshotId);
    const current = await ref.get();
    if (current.exists) {
      throw new functions.https.HttpsError('already-exists', 'Snapshot already exists.');
    }

    const createdAt = admin.firestore.Timestamp.now();
    const expiresAt = admin.firestore.Timestamp.fromMillis(
      createdAt.toMillis() + SNAPSHOT_LIFETIME_MS,
    );
    const snapshotData: FirebaseFirestore.DocumentData = {
      snapshotId,
      authorId: uid,
      authorName: text(profile.nickname) || 'User',
      authorPhotoUrl: text(profile.photoURL),
      authorNationality: text(profile.nationality),
      university,
      schoolId: university,
      storagePath,
      imageStoragePath: mediaType === 'photo' ? storagePath : thumbnailStoragePath,
      videoStoragePath: mediaType === 'video' ? storagePath : '',
      thumbnailStoragePath,
      mediaType,
      durationMs: verifiedDurationMs,
      videoCodec: verifiedCodec,
      visibility,
      visibleToCategoryIds: visibility === 'category' ? selectedCategoryIds : [],
      allowedUserIds,
      ownerId: uid,
      visibilityMode: frozen.visibilityMode,
      audienceUserIdsFrozen: frozen.audienceUserIdsFrozen,
      sourceGroupIds: frozen.sourceGroupIds,
      visibilityLockedAt: createdAt,
      visibilitySchemaVersion: VISIBILITY_SCHEMA_VERSION,
      overlay,
      overlays,
      overlayText: overlay.text,
      overlayPosition: {x: overlay.x, y: overlay.y},
      overlayStyle: {
        alignment: 'center',
        textColor: overlay.lightText ? 'white' : 'black',
        fontScale: overlay.fontScale,
        backgroundType: 'shadow',
      },
      aspectRatio,
      sourceWidth: verifiedWidth,
      sourceHeight: verifiedHeight,
      reactionCounts: {},
      commentCount: 0,
      createdAt,
      expiresAt,
      updatedAt: createdAt,
      status: 'active',
    };

    let canonicalCreated = false;
    try {
      await ref.create(snapshotData);
      canonicalCreated = true;
      await fanOutSnapshot(snapshotId, snapshotData);
    } catch (error) {
      console.error(`createSnapshot rollback id=${snapshotId}`, error);
      if (!canonicalCreated) {
        const concurrent = await ref.get().catch(() => null);
        if (concurrent?.exists &&
            text(concurrent.get('ownerId') ?? concurrent.get('authorId')) === uid &&
            text(concurrent.get('storagePath')) === storagePath &&
            text(concurrent.get('status')) === 'active') {
          const concurrentCreatedAt = concurrent.get('createdAt');
          const concurrentExpiresAt = concurrent.get('expiresAt');
          return {
            snapshotId,
            createdAtMillis: timestampMillis(concurrentCreatedAt),
            expiresAtMillis: timestampMillis(concurrentExpiresAt),
          };
        }
      }
      try {
        await removeSnapshotFromFeeds(snapshotId, snapshotData);
        await ref.delete();
        await deleteSnapshotStoragePrefix(snapshotId);
      } catch (rollbackError) {
        console.error(`createSnapshot rollback failed id=${snapshotId}`, rollbackError);
      }
      throw new functions.https.HttpsError('internal', 'Could not create snapshot.');
    }
    runtimeLogsEnabled && runtimeInfo(
      `content-created type=snapshot id=${snapshotId} owner=${uid} ` +
      `visibility=${frozen.visibilityMode} schema=${VISIBILITY_SCHEMA_VERSION} ` +
      `audienceCount=${frozen.audienceUserIdsFrozen.length} hasStoragePath=true ` +
      `createdAt=${createdAt.toMillis()} expiresAt=${expiresAt.toMillis()}`,
    );
    return {
      snapshotId,
      createdAtMillis: createdAt.toMillis(),
      expiresAtMillis: expiresAt.toMillis(),
    };
  });

export const syncMySnapshotFeed = functions.runWith({timeoutSeconds: 120, memory: '512MB'})
  .https.onCall(async (_raw, context) => {
    const uid = requireUid(context);
    const store = db();
    const now = admin.firestore.Timestamp.now();
    const user = await store.collection(COL.users).doc(uid).get();
    if (!user.exists || !isActiveUserData(user.data() ?? {})) return {count: 0};

    const docs = new Map<string, FirebaseFirestore.QueryDocumentSnapshot>();
    const queries: Array<{
      name: string;
      promise: Promise<FirebaseFirestore.QueryDocumentSnapshot[]>;
    }> = [];
    queries.push({name: 'owner-v2', promise: readAllQueryDocuments(store.collection(COL.snapshots)
      .where('ownerId', '==', uid)
      .where('status', '==', 'active')
      .where('expiresAt', '>', now))});
    queries.push({name: 'public-v2', promise: readAllQueryDocuments(store.collection(COL.snapshots)
      .where('visibilityMode', '==', 'public')
      .where('status', '==', 'active')
      .where('expiresAt', '>', now))});
    queries.push({name: 'frozen-audience', promise: readAllQueryDocuments(store.collection(COL.snapshots)
      .where('audienceUserIdsFrozen', 'array-contains', uid)
      .where('status', '==', 'active')
      .where('expiresAt', '>', now))});
    queries.push({name: 'owner-legacy', promise: readAllQueryDocuments(store.collection(COL.snapshots)
      .where('authorId', '==', uid)
      .where('status', '==', 'active')
      .where('expiresAt', '>', now))});
    queries.push({name: 'public-legacy', promise: readAllQueryDocuments(store.collection(COL.snapshots)
      .where('visibility', '==', 'public')
      .where('status', '==', 'active')
      .where('expiresAt', '>', now))});
    queries.push({name: 'legacy-audience', promise: readAllQueryDocuments(store.collection(COL.snapshots)
      .where('allowedUserIds', 'array-contains', uid)
      .where('status', '==', 'active')
      .where('expiresAt', '>', now))});
    const results = await Promise.allSettled(queries.map((entry) => entry.promise));
    results.forEach((result, index) => {
      const queryName = queries[index].name;
      if (result.status === 'rejected') {
        console.error(`syncMySnapshotFeed query failed type=${queryName} uid=${uid}`, result.reason);
        return;
      }
      for (const doc of result.value) docs.set(doc.id, doc);
    });

    const [blockedByMe, blockingMe] = await Promise.all([
      store.collection(COL.blocks).where('blocker', '==', uid).get(),
      store.collection(COL.blocks).where('blocked', '==', uid).get(),
    ]);
    const blocked = new Set<string>();
    for (const doc of blockedByMe.docs) blocked.add(text(doc.get('blocked')));
    for (const doc of blockingMe.docs) blocked.add(text(doc.get('blocker')));

    const allowed = Array.from(docs.values()).filter((doc) => {
      const item = doc.data();
      const authorId = text(item.ownerId ?? item.authorId);
      if (!authorId || blocked.has(authorId) || item.status !== 'active' ||
          !isTimestamp(item.expiresAt) || item.expiresAt.toMillis() <= now.toMillis()) return false;
      if (authorId === uid) return true;
      if (item.visibilityMode === 'public' || item.visibility === 'public') return true;
      if (Number(item.visibilitySchemaVersion ?? 0) >= VISIBILITY_SCHEMA_VERSION) {
        return Array.isArray(item.audienceUserIdsFrozen) &&
          item.audienceUserIdsFrozen.map(text).includes(uid);
      }
      return Array.isArray(item.allowedUserIds) && item.allowedUserIds.map(text).includes(uid);
    }).sort((a, b) => timestampMillis(b.get('createdAt')) - timestampMillis(a.get('createdAt')));

    await deleteQuery(store.collection(COL.users).doc(uid).collection(SNAPSHOT_FEED));
    const writer = store.bulkWriter();
    for (const doc of allowed) {
      writer.set(
        store.collection(COL.users).doc(uid).collection(SNAPSHOT_FEED).doc(doc.id),
        snapshotFeedData(doc.id, doc.data()),
      );
    }
    await writer.close();
    return {count: allowed.length};
  });

export const updateSnapshotVisibility = functions.runWith({timeoutSeconds: 120, memory: '512MB'})
  .https.onCall(async (_raw, context) => {
    requireUid(context);
    // 스낵의 공개범위는 업로드 시 확정되며 이후에는 변경할 수 없다.
    // 구버전 앱이 이 Callable을 호출해도 서버에서 항상 거부한다.
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Snapshot visibility cannot be changed after publishing.',
    );
  });

export const recordSnapshotView = functions.https.onCall(async (raw, context) => {
  const uid = requireUid(context);
  const data = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
  const snapshotId = validSnapshotId(data.snapshotId);
  const store = db();
  const snapshotRef = store.collection(COL.snapshots).doc(snapshotId);
  const [snapshot, viewer] = await Promise.all([
    snapshotRef.get(),
    store.collection(COL.users).doc(uid).get(),
  ]);
  if (!snapshot.exists || !(await canAccessSnapshot(uid, snapshot.data() ?? {}))) {
    throw new functions.https.HttpsError('permission-denied', 'Snapshot is not accessible.');
  }

  const snapshotData = snapshot.data() ?? {};
  const ownerId = text(snapshotData.ownerId ?? snapshotData.authorId);
  if (!ownerId || ownerId === uid) {
    return {success: true, recorded: false};
  }
  if (!viewer.exists || !isActiveUserData(viewer.data() ?? {})) {
    throw new functions.https.HttpsError('failed-precondition', 'User profile is missing.');
  }

  const profile = viewer.data() ?? {};
  const viewRef = snapshotRef.collection('views').doc(uid);
  const created = await store.runTransaction(async (transaction) => {
    const transactionNow = admin.firestore.Timestamp.now();
    const [currentSnapshot, previous] = await Promise.all([
      transaction.get(snapshotRef),
      transaction.get(viewRef),
    ]);
    const currentData = currentSnapshot.data() ?? {};
    if (!currentSnapshot.exists ||
        !hasSnapshotDocumentAccess(uid, currentData, transactionNow)) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Snapshot has expired.',
      );
    }
    const common = {
      userId: uid,
      displayName: text(profile.nickname ?? profile.name) || 'User',
      photoUrl: text(profile.photoURL),
      photoVersion: Math.max(0, Number(profile.photoVersion ?? 0) || 0),
      nationality: text(profile.nationality),
      university: profileUniversity(profile),
      viewedAt: transactionNow,
      expiresAt: currentData.expiresAt,
    };
    if (previous.exists) {
      transaction.set(viewRef, common, {merge: true});
      return false;
    }
    transaction.create(viewRef, {
      ...common,
      firstViewedAt: transactionNow,
    });
    return true;
  });
  return {success: true, recorded: true, created};
});

export const getSnapshotViewers = functions.https.onCall(async (raw, context) => {
  const uid = requireUid(context);
  const data = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
  const snapshotId = validSnapshotId(data.snapshotId);
  const snapshotRef = db().collection(COL.snapshots).doc(snapshotId);
  const snapshot = await snapshotRef.get();
  if (!snapshot.exists) {
    throw new functions.https.HttpsError('not-found', 'Snapshot was not found.');
  }

  const snapshotData = snapshot.data() ?? {};
  const ownerId = text(snapshotData.ownerId ?? snapshotData.authorId);
  if (!ownerId || ownerId !== uid) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only the snapshot owner can view this list.',
    );
  }
  if (!hasSnapshotDocumentAccess(
    uid,
    snapshotData,
    admin.firestore.Timestamp.now(),
  )) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Snapshot has expired.',
    );
  }

  // orderBy(viewedAt)는 해당 필드가 없는 레거시 조회 문서를 결과에서
  // 제외한다. 전체 영수증을 읽은 뒤 호환 타임스탬프로 서버에서 정렬한다.
  const [views, reactions] = await Promise.all([
    readAllQueryDocuments(snapshotRef.collection('views')),
    readAllQueryDocuments(snapshotRef.collection('reactions')),
  ]);
  const viewByUser = new Map(views.map((document) => [document.id, document]));
  const reactionByUser = new Map(reactions.map((document) => [document.id, document]));
  const userIds = new Set([...viewByUser.keys(), ...reactionByUser.keys()]);
  const documents = [...userIds].map((userId) => {
    const view = viewByUser.get(userId)?.data() ?? {};
    const reaction = reactionByUser.get(userId)?.data() ?? {};
    const activityAt = view.viewedAt ?? view.lastViewedAt ??
      view.firstViewedAt ?? view.createdAt ?? reaction.createdAt;
    return {
      userId,
      displayName: text(view.displayName ?? view.nickname ??
        reaction.displayName ?? reaction.nickname) || 'User',
      photoUrl: text(view.photoUrl ?? view.photoURL ??
        reaction.photoUrl ?? reaction.photoURL),
      photoVersion: Math.max(0, Number(view.photoVersion ??
        reaction.photoVersion ?? 0) || 0),
      nationality: text(view.nationality ?? reaction.nationality),
      university: text(view.university ?? reaction.university),
      reaction: text(reaction.reaction),
      viewedAtMillis: timestampMillis(activityAt),
    };
  }).sort((a, b) => b.viewedAtMillis - a.viewedAtMillis);
  return {
    viewers: documents,
  };
});

export const getSnapshotReactionStatus = functions.https.onCall(async (raw, context) => {
  const uid = requireUid(context);
  const data = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
  const snapshotId = validSnapshotId(data.snapshotId);
  const ref = db().collection(COL.snapshots).doc(snapshotId);
  const snapshot = await ref.get();
  if (!snapshot.exists || !(await canAccessSnapshot(uid, snapshot.data() ?? {}))) {
    throw new functions.https.HttpsError('permission-denied', 'Snapshot is not accessible.');
  }
  const ownerId = text(snapshot.get('ownerId') ?? snapshot.get('authorId'));
  if (ownerId === uid) return {reacted: true, reaction: ''};
  const reaction = await ref.collection('reactions').doc(uid).get();
  return {
    reacted: reaction.exists,
    reaction: reaction.exists ? text(reaction.get('reaction')) : '',
  };
});

export const getSnapshotCommentStatus = functions.https.onCall(async (raw, context) => {
  const uid = requireUid(context);
  const data = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
  const snapshotId = validSnapshotId(data.snapshotId);
  const ref = db().collection(COL.snapshots).doc(snapshotId);
  const snapshot = await ref.get();
  if (!snapshot.exists || !(await canAccessSnapshot(uid, snapshot.data() ?? {}))) {
    throw new functions.https.HttpsError('permission-denied', 'Snapshot is not accessible.');
  }
  const ownerId = text(snapshot.get('ownerId') ?? snapshot.get('authorId'));
  if (ownerId === uid) return {commented: true};

  const canonical = await ref.collection('comments').doc(uid).get();
  if (canonical.exists) return {commented: true};

  // UID 문서 방식을 적용하기 전에 생성된 코멘트도 1회 사용으로 인정한다.
  const legacy = await ref.collection('comments')
    .where('senderId', '==', uid)
    .limit(1)
    .get();
  return {commented: !legacy.empty};
});

export const toggleSnapshotReaction = functions.https.onCall(async (raw, context) => {
  const uid = requireUid(context);
  const data = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
  const snapshotId = validSnapshotId(data.snapshotId);
  const reaction = text(data.reaction);
  if (!ALLOWED_REACTIONS.has(reaction)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid reaction.');
  }
  const ref = db().collection(COL.snapshots).doc(snapshotId);
  const initial = await ref.get();
  if (!initial.exists || !(await canAccessSnapshot(uid, initial.data() ?? {}))) {
    throw new functions.https.HttpsError('permission-denied', 'Snapshot is not accessible.');
  }
  const initialData = initial.data() ?? {};
  const ownerId = text(initialData.ownerId ?? initialData.authorId);
  if (!ownerId || ownerId === uid) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'You cannot react to your own Snapshot.',
    );
  }

  const [actorDocument, ownerDocument, ownerSettingsDocument] = await Promise.all([
    db().collection(COL.users).doc(uid).get(),
    db().collection(COL.users).doc(ownerId).get(),
    db().collection('user_settings').doc(ownerId).get(),
  ]);
  const actorData = actorDocument.data() ?? {};
  const actorName = text(actorData.nickname ?? actorData.name) || 'User';
  const copy = snapshotReactionCopy(
    reaction,
    actorName,
    prefersKoreanNotification(ownerDocument.data() ?? {}),
  );
  const notifyOwner = snapshotNotificationSettingAllows(
    ownerSettingsDocument,
    'new_like',
  );
  const reactionRef = ref.collection('reactions').doc(uid);
  const notificationRef = db().collection(COL.notifications)
    .doc(`snapshot_reaction_${snapshotId}_${uid}`);
  const result = await db().runTransaction(async (transaction) => {
    const transactionNow = admin.firestore.Timestamp.now();
    const [snapshot, previous] = await Promise.all([
      transaction.get(ref),
      transaction.get(reactionRef),
    ]);
    const snapshotData = snapshot.data() ?? {};
    if (!snapshot.exists ||
        !hasSnapshotDocumentAccess(uid, snapshotData, transactionNow)) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Snapshot has expired.',
      );
    }
    const currentOwnerId = text(snapshotData.ownerId ?? snapshotData.authorId);
    if (!currentOwnerId || currentOwnerId !== ownerId || currentOwnerId === uid) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'You cannot react to your own Snapshot.',
      );
    }
    if (previous.exists) {
      // 재시도나 중복 탭은 성공으로 처리하되 기존 반응을
      // 취소하거나 다른 반응으로 변경하지 않는다.
      return {
        created: false,
        reaction: text(previous.get('reaction')),
      };
    }
    const countsRaw = snapshotData.reactionCounts;
    const counts: Record<string, number> = {};
    if (countsRaw && typeof countsRaw === 'object') {
      for (const [key, value] of Object.entries(countsRaw)) {
        counts[key] = Math.max(0, Number(value) || 0);
      }
    }
    counts[reaction] = (counts[reaction] ?? 0) + 1;
    transaction.create(reactionRef, {
      userId: uid,
      reaction,
      displayName: actorName,
      photoUrl: text(actorData.photoURL ?? actorData.photoUrl),
      photoVersion: Math.max(0, Number(actorData.photoVersion ?? 0) || 0),
      nationality: text(actorData.nationality),
      university: text(actorData.university),
      createdAt: transactionNow,
      expiresAt: snapshotData.expiresAt,
    });
    transaction.update(ref, {
      reactionCounts: counts,
      updatedAt: transactionNow,
    });
    // 반응과 알림을 한 트랜잭션으로 저장해 반응만 남거나
    // 재시도로 푸시가 중복 생성되는 상태를 방지한다.
    if (notifyOwner) {
      transaction.set(notificationRef, {
        userId: ownerId,
        type: 'snapshot_reaction',
        title: copy.title,
        message: copy.message,
        snapshotId,
        reaction,
        actorId: uid,
        actorName,
        isRead: false,
        createdAt: transactionNow,
        expiresAt: snapshotData.expiresAt,
        data: {
          snapshotId,
          reaction,
          actorId: uid,
          actorName,
        },
      });
    }
    return {created: true, reaction};
  });
  return {
    success: true,
    created: result.created,
    reaction: result.reaction,
  };
});

export const sendSnapshotComment = functions.https.onCall(async (raw, context) => {
  const uid = requireUid(context);
  const data = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
  const snapshotId = validSnapshotId(data.snapshotId);
  validRequestId(data.requestId);
  const message = validSnapshotComment(data.message);
  const ref = db().collection(COL.snapshots).doc(snapshotId);
  const accessCheckedAt = admin.firestore.Timestamp.now();
  const snapshot = await ref.get();
  if (!snapshot.exists ||
      !(await canAccessSnapshot(uid, snapshot.data() ?? {}, accessCheckedAt))) {
    throw new functions.https.HttpsError('permission-denied', 'Snapshot is not accessible.');
  }
  const snapshotData = snapshot.data() ?? {};
  const ownerId = text(snapshotData.ownerId ?? snapshotData.authorId);
  if (!ownerId || ownerId === uid) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'You cannot comment on your own Snapshot.',
    );
  }
  const comments = ref.collection('comments');
  const legacy = await comments.where('senderId', '==', uid).limit(1).get();
  if (!legacy.empty) return {success: true, created: false};

  const [actorDocument, ownerDocument] = await Promise.all([
    db().collection(COL.users).doc(uid).get(),
    db().collection(COL.users).doc(ownerId).get(),
  ]);
  const actorData = actorDocument.data() ?? {};
  const ownerData = ownerDocument.data() ?? {};
  const actorName = text(actorData.nickname ?? actorData.name) || 'User';
  const sourceAuthorName = text(snapshotData.authorName) ||
    text(ownerData.nickname ?? ownerData.name) || 'User';
  const sourceAuthorPhotoUrl = text(snapshotData.authorPhotoUrl) ||
    text(ownerData.photoURL);
  const sourceOverlay = snapshotData.overlay && typeof snapshotData.overlay === 'object'
    ? snapshotData.overlay as Record<string, unknown>
    : {};
  const sourceText = text(snapshotData.overlayText ?? sourceOverlay.text);
  const sourceCreatedAt = snapshotData.createdAt ?? accessCheckedAt;
  const sourceImageStoragePath = text(
    snapshotData.imageStoragePath ?? snapshotData.storagePath,
  );
  const sourceImageUrl = text(snapshotData.imageUrl);
  const sourceAspectRatio = Number(snapshotData.aspectRatio) || .8;
  const sourceExpiresAt = snapshotData.expiresAt;
  const isKorean = prefersKoreanNotification(ownerData);
  const title = isKorean ? '스낵에 코멘트가 도착했어요' : 'New Snack comment';
  const notificationMessage = isKorean
    ? `${actorName}님: ${message}`
    : `${actorName}: ${message}`;
  // 사용자 UID를 문서 ID로 사용해 빠른 연속 탭과 다른 기기에서의 요청도
  // 스낵샷당 한 번만 저장되도록 한다.
  const commentRef = comments.doc(uid);
  const notificationRef = db().collection(COL.notifications)
    .doc(`snapshot_comment_${snapshotId}_${uid}`);
  const result = await db().runTransaction(async (transaction) => {
    const [currentSnapshot, previous] = await Promise.all([
      transaction.get(ref),
      transaction.get(commentRef),
    ]);
    const currentData = currentSnapshot.data() ?? {};
    const currentOwnerId = text(currentData.ownerId ?? currentData.authorId);
    // 차단 관계는 트랜잭션 직전에 canAccessSnapshot으로 확인했다. 트랜잭션
    // 콜백 안에서는 외부 Firestore 읽기를 섞지 않고 현재 문서만 검증한다.
    if (!currentSnapshot.exists || currentOwnerId !== ownerId ||
        !hasSnapshotDocumentAccess(uid, currentData, accessCheckedAt)) {
      throw new functions.https.HttpsError('permission-denied', 'Snapshot is not accessible.');
    }
    if (previous.exists) return {created: false};
    transaction.create(commentRef, {
      senderId: uid,
      senderName: actorName,
      message,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.create(notificationRef, {
      userId: ownerId,
      type: 'snapshot_comment',
      title,
      message: notificationMessage,
      snapshotId,
      comment: message,
      actorId: uid,
      actorName,
      sourceAuthorName,
      sourceAuthorPhotoUrl,
      sourceText,
      sourceCreatedAt,
      sourceImageStoragePath,
      sourceImageUrl,
      sourceAspectRatio,
      sourceExpiresAt,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      data: {
        snapshotId,
        comment: message,
        actorId: uid,
        actorName,
        sourceAuthorName,
        sourceAuthorPhotoUrl,
        sourceText,
        sourceCreatedAt,
        sourceImageStoragePath,
        sourceImageUrl,
        sourceAspectRatio,
        sourceExpiresAt,
      },
    });
    return {created: true};
  });
  return {success: true, created: result.created};
});

function snapshotNotificationSettingAllows(
  settings: FirebaseFirestore.DocumentSnapshot,
  legacyKey: 'new_comment' | 'new_like',
): boolean {
  const notifications = settings.exists &&
      settings.data()?.notifications &&
      typeof settings.data()?.notifications === 'object'
    ? settings.data()?.notifications as Record<string, unknown>
    : {};
  return notifications.all_notifications !== false &&
    notifications.post_interactions !== false &&
    notifications[legacyKey] !== false;
}

async function snapshotCommentNotificationAllowed(userId: string): Promise<boolean> {
  const settings = await db().collection('user_settings').doc(userId).get();
  return snapshotNotificationSettingAllows(settings, 'new_comment');
}

/**
 * Public Snack feed comment/reply. This intentionally uses a separate callable
 * and notification type from the existing one-to-one Snack letter feature.
 */
export const createSnapshotFeedComment = functions.https.onCall(async (raw, context) => {
  const uid = requireUid(context);
  const data = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
  const snapshotId = validSnapshotId(data.snapshotId);
  const commentId = validRequestId(data.commentId ?? data.requestId);
  const content = validSnapshotFeedComment(data.content ?? data.message);
  const parentCommentId = text(data.parentCommentId);
  const replyToCommentId = text(data.replyToCommentId);
  if (parentCommentId) validRequestId(parentCommentId);
  if (replyToCommentId) validRequestId(replyToCommentId);

  const store = db();
  const snapshotRef = store.collection(COL.snapshots).doc(snapshotId);
  const initial = await snapshotRef.get();
  const snapshotData = initial.data() ?? {};
  const now = admin.firestore.Timestamp.now();
  if (!initial.exists || !(await canAccessSnapshot(uid, snapshotData, now))) {
    throw new functions.https.HttpsError('permission-denied', 'Snapshot is not accessible.');
  }

  const ownerId = text(snapshotData.ownerId ?? snapshotData.authorId);
  const expiresAt = snapshotData.expiresAt;
  if (!ownerId || !isTimestamp(expiresAt) || expiresAt.toMillis() <= now.toMillis()) {
    throw new functions.https.HttpsError('failed-precondition', 'Snapshot has expired.');
  }

  const comments = snapshotRef.collection('feed_comments');
  let parentData: FirebaseFirestore.DocumentData | null = null;
  let replyTargetData: FirebaseFirestore.DocumentData | null = null;
  if (parentCommentId) {
    const parent = await comments.doc(parentCommentId).get();
    if (!parent.exists || parent.get('isDeleted') === true ||
        text(parent.get('parentCommentId'))) {
      throw new functions.https.HttpsError('failed-precondition', 'Parent comment is unavailable.');
    }
    parentData = parent.data() ?? {};
    const targetId = replyToCommentId || parentCommentId;
    const target = targetId === parentCommentId
      ? parent
      : await comments.doc(targetId).get();
    if (!target.exists || target.get('isDeleted') === true ||
        (text(target.get('parentCommentId')) || target.id) !== parentCommentId) {
      throw new functions.https.HttpsError('failed-precondition', 'Reply target is unavailable.');
    }
    replyTargetData = target.data() ?? {};
    const relatedAuthors = new Set([
      text(parentData.userId),
      text(replyTargetData.userId),
    ].filter(Boolean));
    for (const relatedAuthor of relatedAuthors) {
      if (await isBlocked(uid, relatedAuthor)) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Reply target is not accessible.',
        );
      }
    }
  }

  const author = await store.collection(COL.users).doc(uid).get();
  if (!author.exists || !isActiveUserData(author.data() ?? {})) {
    throw new functions.https.HttpsError('failed-precondition', 'User profile is missing.');
  }
  const authorData = author.data() ?? {};
  const authorName = text(authorData.nickname ?? authorData.name) || 'User';
  const authorPhotoUrl = text(authorData.photoURL);

  const recipientTypes = new Map<string, 'snapshot_feed_comment' | 'snapshot_feed_comment_reply'>();
  if (ownerId !== uid) recipientTypes.set(ownerId, 'snapshot_feed_comment');
  if (parentData != null && replyTargetData != null) {
    const targetUserId = text(replyTargetData.userId);
    const parentUserId = text(parentData.userId);
    if (targetUserId && targetUserId !== uid) {
      recipientTypes.set(targetUserId, 'snapshot_feed_comment_reply');
    }
    if (parentUserId && parentUserId !== uid) {
      recipientTypes.set(parentUserId, 'snapshot_feed_comment_reply');
    }
  }

  type SnapshotCommentRecipient = {
    userId: string;
    type: 'snapshot_feed_comment' | 'snapshot_feed_comment_reply';
  };
  const recipients = (await Promise.all(
    Array.from(recipientTypes.entries()).map(async ([userId, type]) => {
      const [blocked, notificationAllowed] = await Promise.all([
        isBlocked(uid, userId),
        snapshotCommentNotificationAllowed(userId),
      ]);
      return blocked || !notificationAllowed ? null : {userId, type};
    }),
  )).filter((recipient): recipient is SnapshotCommentRecipient => recipient != null);

  const commentRef = comments.doc(commentId);
  const result = await store.runTransaction(async (transaction) => {
    const transactionNow = admin.firestore.Timestamp.now();
    const [currentSnapshot, existing] = await Promise.all([
      transaction.get(snapshotRef),
      transaction.get(commentRef),
    ]);
    const currentData = currentSnapshot.data() ?? {};
    if (!currentSnapshot.exists ||
        !hasSnapshotDocumentAccess(uid, currentData, transactionNow)) {
      throw new functions.https.HttpsError('failed-precondition', 'Snapshot has expired.');
    }
    if (existing.exists) return {created: false};

    transaction.create(commentRef, {
      snapshotId,
      userId: uid,
      authorNickname: authorName,
      authorPhotoUrl,
      content,
      parentCommentId: parentCommentId || null,
      replyToCommentId: replyToCommentId || null,
      replyToUserId: replyTargetData == null ? null : text(replyTargetData.userId),
      replyToUserNickname: replyTargetData == null
        ? null
        : text(replyTargetData.authorNickname),
      isDeleted: false,
      createdAt: transactionNow,
      expiresAt,
    });
    transaction.update(snapshotRef, {
      commentCount: admin.firestore.FieldValue.increment(1),
      updatedAt: transactionNow,
    });

    for (const recipient of recipients) {
      const notificationId = `${recipient.type}_${commentId}_${recipient.userId}`;
      transaction.create(store.collection(COL.notifications).doc(notificationId), {
        userId: recipient.userId,
        type: recipient.type,
        title: recipient.type === 'snapshot_feed_comment_reply'
          ? 'New reply on a Snack'
          : 'New comment on your Snack',
        message: `${authorName}: ${content}`,
        snapshotId,
        commentId,
        actorId: uid,
        actorName: authorName,
        isRead: false,
        createdAt: transactionNow,
        expiresAt,
        data: {
          snapshotId,
          commentId,
          parentCommentId: parentCommentId || '',
          actorId: uid,
          actorName: authorName,
          content,
        },
      });
    }
    return {created: true};
  });
  return {success: true, created: result.created, commentId};
});

export const deleteSnapshotFeedComment = functions.https.onCall(async (raw, context) => {
  const uid = requireUid(context);
  const data = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
  const snapshotId = validSnapshotId(data.snapshotId);
  const commentId = validRequestId(data.commentId);
  const snapshotRef = db().collection(COL.snapshots).doc(snapshotId);
  const commentRef = snapshotRef.collection('feed_comments').doc(commentId);

  await db().runTransaction(async (transaction) => {
    const transactionNow = admin.firestore.Timestamp.now();
    const [snapshot, comment] = await Promise.all([
      transaction.get(snapshotRef),
      transaction.get(commentRef),
    ]);
    if (!snapshot.exists ||
        !hasSnapshotDocumentAccess(uid, snapshot.data() ?? {}, transactionNow)) {
      throw new functions.https.HttpsError('failed-precondition', 'Snapshot has expired.');
    }
    if (!comment.exists) return;
    if (text(comment.get('userId')) !== uid) {
      throw new functions.https.HttpsError('permission-denied', 'Only the author can delete it.');
    }
    if (comment.get('isDeleted') === true) return;
    transaction.update(commentRef, {
      isDeleted: true,
      deletedAt: transactionNow,
      content: '',
      authorNickname: '',
      authorPhotoUrl: '',
    });
    transaction.update(snapshotRef, {
      commentCount: admin.firestore.FieldValue.increment(-1),
      updatedAt: transactionNow,
    });
  });
  return {success: true};
});

/**
 * 알림에서만 열 수 있는 스낵 코멘트 편지를 반환한다.
 *
 * 스냅샷은 24시간 후 삭제되지만 코멘트 알림은 사용자가 지울 때까지 남는다.
 * 편지 원본을 알림 문서로 삼아 스냅샷 만료 후에도 당사자 두 명만 코멘트와
 * 답장을 확인할 수 있게 한다.
 */
export const getSnapshotCommentLetter = functions.https.onCall(async (raw, context) => {
  const uid = requireUid(context);
  const data = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
  const notificationId = validNotificationId(data.notificationId);
  const store = db();
  const tapped = await store.collection(COL.notifications).doc(notificationId).get();
  if (!tapped.exists) {
    throw new functions.https.HttpsError('not-found', 'The Snack letter is no longer available.');
  }

  const tappedData = tapped.data() ?? {};
  const tappedNested = tappedData.data && typeof tappedData.data === 'object'
    ? tappedData.data as Record<string, unknown>
    : {};
  const tappedType = text(tappedData.type);
  if (tappedType !== 'snapshot_comment' && tappedType !== 'snapshot_comment_reply') {
    throw new functions.https.HttpsError('invalid-argument', 'This notification is not a Snack letter.');
  }

  let originalId = notificationId;
  let original = tapped;
  if (tappedType === 'snapshot_comment_reply') {
    originalId = validNotificationId(tappedNested.originalNotificationId);
    original = await store.collection(COL.notifications).doc(originalId).get();
  }

  const originalData = original.exists ? (original.data() ?? {}) : {};
  const originalNested = originalData.data && typeof originalData.data === 'object'
    ? originalData.data as Record<string, unknown>
    : {};
  if (original.exists && text(originalData.type) !== 'snapshot_comment') {
    throw new functions.https.HttpsError('permission-denied', 'The Snack letter is invalid.');
  }

  // 답장 알림은 원본 알림이 작성자에 의해 삭제된 뒤에도 상대방이 자신에게
  // 도착한 편지를 읽을 수 있도록 필요한 원문을 함께 보관한다.
  const ownerId = text(
    originalData.userId ?? originalNested.ownerId ?? tappedNested.ownerId,
  );
  const commenterId = text(
    originalData.actorId ?? originalNested.actorId ?? originalNested.commenterId ??
      tappedNested.commenterId ?? tappedData.userId,
  );
  if (!ownerId || !commenterId || (uid !== ownerId && uid !== commenterId)) {
    throw new functions.https.HttpsError('permission-denied', 'Only the participants can read this letter.');
  }

  const snapshotId = text(
    originalData.snapshotId ?? originalNested.snapshotId ??
      tappedData.snapshotId ?? tappedNested.snapshotId,
  );
  const [ownerDocument, commenterDocument] = await Promise.all([
    store.collection(COL.users).doc(ownerId).get(),
    store.collection(COL.users).doc(commenterId).get(),
  ]);
  const ownerProfile = ownerDocument.data() ?? {};
  const commenterProfile = commenterDocument.data() ?? {};
  const sourceSnapshotDocument = snapshotId
    ? await store.collection(COL.snapshots).doc(snapshotId).get()
    : null;
  const sourceSnapshotData = sourceSnapshotDocument?.data() ?? {};
  const sourceOverlay = sourceSnapshotData.overlay &&
      typeof sourceSnapshotData.overlay === 'object'
    ? sourceSnapshotData.overlay as Record<string, unknown>
    : {};
  const comment = text(
    originalData.comment ?? originalNested.comment ?? tappedNested.comment,
  );
  const reply = text(
    originalData.reply ?? originalNested.reply ?? tappedData.reply ?? tappedNested.reply,
  );
  if (!comment) {
    throw new functions.https.HttpsError('not-found', 'The original comment is missing.');
  }

  const ownerName = text(ownerProfile.nickname ?? ownerProfile.name) ||
    text(tappedNested.ownerName ?? originalNested.ownerName) || 'User';
  const ownerPhotoUrl = text(ownerProfile.photoURL) ||
    text(tappedNested.ownerPhotoUrl ?? originalNested.ownerPhotoUrl);
  const sourceAuthorName = text(
    originalData.sourceAuthorName ?? originalNested.sourceAuthorName ??
      tappedNested.sourceAuthorName ?? sourceSnapshotData.authorName,
  ) || ownerName;
  const sourceAuthorPhotoUrl = text(
    originalData.sourceAuthorPhotoUrl ?? originalNested.sourceAuthorPhotoUrl ??
      tappedNested.sourceAuthorPhotoUrl ?? sourceSnapshotData.authorPhotoUrl,
  ) || ownerPhotoUrl;
  const sourceText = text(
    originalData.sourceText ?? originalNested.sourceText ??
      tappedNested.sourceText ?? sourceSnapshotData.overlayText ?? sourceOverlay.text,
  );
  const sourceImageStoragePath = text(
    originalData.sourceImageStoragePath ?? originalNested.sourceImageStoragePath ??
      tappedNested.sourceImageStoragePath ?? sourceSnapshotData.imageStoragePath ??
      sourceSnapshotData.storagePath,
  );
  const sourceImageUrl = text(
    originalData.sourceImageUrl ?? originalNested.sourceImageUrl ??
      tappedNested.sourceImageUrl ?? sourceSnapshotData.imageUrl,
  );
  const sourceAspectRatio = Number(
    originalData.sourceAspectRatio ?? originalNested.sourceAspectRatio ??
      tappedNested.sourceAspectRatio ?? sourceSnapshotData.aspectRatio,
  ) || .8;
  const sourceExpiresAt = originalData.sourceExpiresAt ??
    originalNested.sourceExpiresAt ?? tappedNested.sourceExpiresAt ??
    sourceSnapshotData.expiresAt;

  return {
    notificationId,
    originalNotificationId: originalId,
    snapshotId,
    ownerId,
    ownerName,
    ownerPhotoUrl,
    commenterId,
    commenterName: text(commenterProfile.nickname ?? commenterProfile.name) ||
      text(originalData.actorName ?? originalNested.actorName ??
        tappedNested.commenterName) || 'User',
    commenterPhotoUrl: text(commenterProfile.photoURL) ||
      text(tappedNested.commenterPhotoUrl ?? originalNested.commenterPhotoUrl),
    comment,
    reply,
    commentCreatedAtMillis: timestampMillis(
      originalData.createdAt ?? originalNested.commentCreatedAt ??
        tappedNested.commentCreatedAt,
    ),
    repliedAtMillis: timestampMillis(
      originalData.repliedAt ?? originalNested.repliedAt ??
        tappedData.repliedAt ?? tappedNested.repliedAt,
    ),
    sourceAuthorName,
    sourceAuthorPhotoUrl,
    sourceText,
    sourceImageStoragePath,
    sourceImageUrl,
    sourceAspectRatio,
    sourceExpiresAtMillis: timestampMillis(sourceExpiresAt),
    sourceCreatedAtMillis: timestampMillis(
      originalData.sourceCreatedAt ?? originalNested.sourceCreatedAt ??
        tappedNested.sourceCreatedAt ?? sourceSnapshotData.createdAt ??
        originalData.createdAt,
    ),
    viewerRole: uid === ownerId ? 'owner' : 'commenter',
    canReply: uid === ownerId && reply.length === 0 && original.exists,
  };
});

/** 스낵 작성자가 코멘트 한 건에 정확히 한 번만 답장한다. */
export const replySnapshotComment = functions.https.onCall(async (raw, context) => {
  const uid = requireUid(context);
  const data = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
  const notificationId = validNotificationId(data.notificationId);
  if (data.requestId != null) validRequestId(data.requestId);
  const reply = validSnapshotComment(data.message ?? data.reply);
  const store = db();
  const originalRef = store.collection(COL.notifications).doc(notificationId);
  const initial = await originalRef.get();
  if (!initial.exists || text(initial.get('type')) !== 'snapshot_comment') {
    throw new functions.https.HttpsError('not-found', 'The original Snack comment is missing.');
  }
  const initialData = initial.data() ?? {};
  const initialNested = initialData.data && typeof initialData.data === 'object'
    ? initialData.data as Record<string, unknown>
    : {};
  const ownerId = text(initialData.userId);
  const commenterId = text(
    initialData.actorId ?? initialNested.actorId ?? initialNested.commenterId,
  );
  const snapshotId = text(initialData.snapshotId ?? initialNested.snapshotId);
  const comment = text(initialData.comment ?? initialNested.comment);
  if (ownerId !== uid || !commenterId || commenterId === uid || !comment) {
    throw new functions.https.HttpsError('permission-denied', 'Only the Snack author can reply.');
  }
  if (await isBlocked(uid, commenterId)) {
    throw new functions.https.HttpsError('permission-denied', 'This letter is not available.');
  }

  const [ownerDocument, commenterDocument] = await Promise.all([
    store.collection(COL.users).doc(uid).get(),
    store.collection(COL.users).doc(commenterId).get(),
  ]);
  const ownerProfile = ownerDocument.data() ?? {};
  const commenterProfile = commenterDocument.data() ?? {};
  const sourceSnapshotDocument = snapshotId
    ? await store.collection(COL.snapshots).doc(snapshotId).get()
    : null;
  const sourceSnapshotData = sourceSnapshotDocument?.data() ?? {};
  const sourceOverlay = sourceSnapshotData.overlay &&
      typeof sourceSnapshotData.overlay === 'object'
    ? sourceSnapshotData.overlay as Record<string, unknown>
    : {};
  const ownerName = text(ownerProfile.nickname ?? ownerProfile.name) || 'User';
  const ownerPhotoUrl = text(ownerProfile.photoURL);
  const commenterName = text(commenterProfile.nickname ?? commenterProfile.name) ||
    text(initialData.actorName ?? initialNested.actorName) || 'User';
  const commenterPhotoUrl = text(commenterProfile.photoURL);
  const sourceAuthorName = text(
    initialData.sourceAuthorName ?? initialNested.sourceAuthorName ??
      sourceSnapshotData.authorName,
  ) || ownerName;
  const sourceAuthorPhotoUrl = text(
    initialData.sourceAuthorPhotoUrl ?? initialNested.sourceAuthorPhotoUrl ??
      sourceSnapshotData.authorPhotoUrl,
  ) || ownerPhotoUrl;
  const sourceText = text(
    initialData.sourceText ?? initialNested.sourceText ??
      sourceSnapshotData.overlayText ?? sourceOverlay.text,
  );
  const sourceImageStoragePath = text(
    initialData.sourceImageStoragePath ?? initialNested.sourceImageStoragePath ??
      sourceSnapshotData.imageStoragePath ?? sourceSnapshotData.storagePath,
  );
  const sourceImageUrl = text(
    initialData.sourceImageUrl ?? initialNested.sourceImageUrl ??
      sourceSnapshotData.imageUrl,
  );
  const sourceAspectRatio = Number(
    initialData.sourceAspectRatio ?? initialNested.sourceAspectRatio ??
      sourceSnapshotData.aspectRatio,
  ) || .8;
  const sourceExpiresAt = initialData.sourceExpiresAt ??
    initialNested.sourceExpiresAt ?? sourceSnapshotData.expiresAt;
  const sourceCreatedAt = initialData.sourceCreatedAt ??
    initialNested.sourceCreatedAt ?? sourceSnapshotData.createdAt ??
    initialData.createdAt;
  const isKorean = prefersKoreanNotification(commenterProfile);
  const title = isKorean ? '스낵 답장이 도착했어요' : 'A Snack reply arrived';
  const message = isKorean ? `${ownerName}님: ${reply}` : `${ownerName}: ${reply}`;
  const replyNotificationRef = store.collection(COL.notifications)
    .doc(`snapshot_comment_reply_${notificationId}`);

  const result = await store.runTransaction(async (transaction) => {
    const [current, previousReply] = await Promise.all([
      transaction.get(originalRef),
      transaction.get(replyNotificationRef),
    ]);
    if (!current.exists || text(current.get('type')) !== 'snapshot_comment' ||
        text(current.get('userId')) !== uid) {
      throw new functions.https.HttpsError('permission-denied', 'The Snack letter changed.');
    }
    const currentData = current.data() ?? {};
    const currentNested = currentData.data && typeof currentData.data === 'object'
      ? currentData.data as Record<string, unknown>
      : {};
    const currentCommenterId = text(
      currentData.actorId ?? currentNested.actorId ?? currentNested.commenterId,
    );
    if (currentCommenterId !== commenterId) {
      throw new functions.https.HttpsError('permission-denied', 'The Snack letter changed.');
    }
    // 네트워크 재시도와 빠른 연속 탭은 성공으로 응답하되 새 답장/알림을
    // 만들지 않는다. 원본과 답장 알림은 같은 트랜잭션이므로 부분 저장도 없다.
    if (text(currentData.reply ?? currentNested.reply) || previousReply.exists) {
      return {created: false};
    }

    const repliedAt = admin.firestore.Timestamp.now();
    const mergedOriginalData = {
      ...currentNested,
      ownerId: uid,
      ownerName,
      ownerPhotoUrl,
      commenterId,
      commenterName,
      commenterPhotoUrl,
      sourceAuthorName,
      sourceAuthorPhotoUrl,
      sourceText,
      sourceCreatedAt,
      sourceImageStoragePath,
      sourceImageUrl,
      sourceAspectRatio,
      sourceExpiresAt,
      comment,
      reply,
      repliedAt,
      replyActorId: uid,
      replyActorName: ownerName,
    };
    transaction.update(originalRef, {
      reply,
      repliedAt,
      replyActorId: uid,
      replyActorName: ownerName,
      data: mergedOriginalData,
    });
    transaction.create(replyNotificationRef, {
      userId: commenterId,
      type: 'snapshot_comment_reply',
      title,
      message,
      snapshotId,
      comment,
      reply,
      actorId: uid,
      actorName: ownerName,
      isRead: false,
      createdAt: repliedAt,
      data: {
        snapshotId,
        originalNotificationId: notificationId,
        ownerId: uid,
        ownerName,
        ownerPhotoUrl,
        commenterId,
        commenterName,
        commenterPhotoUrl,
        sourceAuthorName,
        sourceAuthorPhotoUrl,
        sourceText,
        sourceCreatedAt,
        sourceImageStoragePath,
        sourceImageUrl,
        sourceAspectRatio,
        sourceExpiresAt,
        comment,
        commentCreatedAt: currentData.createdAt,
        reply,
        repliedAt,
        actorId: uid,
        actorName: ownerName,
      },
    });
    return {created: true};
  });
  return {success: true, created: result.created};
});

export const deleteSnapshot = functions.runWith({timeoutSeconds: 120, memory: '512MB'})
  .https.onCall(async (raw, context) => {
    const uid = requireUid(context);
    const data = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
    const snapshotId = validSnapshotId(data.snapshotId);
    const snapshot = await db().collection(COL.snapshots).doc(snapshotId).get();
    if (!snapshot.exists) return {success: true};
    const snapshotData = snapshot.data() ?? {};
    if (text(snapshotData.authorId ?? snapshotData.ownerId) !== uid) {
      throw new functions.https.HttpsError('permission-denied', 'Only the author can delete it.');
    }
    await deleteSnapshotResources(snapshotId, snapshotData);
    return {success: true};
  });

export const cleanupExpiredSnapshots = functions.runWith({timeoutSeconds: 540, memory: '1GB'})
  .pubsub.schedule('every 10 minutes')
  .timeZone('UTC')
  .onRun(async () => {
    let deleted = 0;
    let failed = 0;
    while (true) {
      const expired = await db().collection(COL.snapshots)
        .where('expiresAt', '<=', admin.firestore.Timestamp.now())
        .orderBy('expiresAt')
        .limit(100)
        .get();
      if (expired.empty) break;
      const failedBeforePage = failed;
      for (let offset = 0; offset < expired.docs.length; offset += 10) {
        const results = await Promise.allSettled(
          expired.docs.slice(offset, offset + 10).map(async (doc) => {
            await deleteSnapshotResources(doc.id, doc.data());
            deleted += 1;
          }),
        );
        for (const result of results) {
          if (result.status === 'rejected') failed += 1;
        }
      }
      if (expired.size < 100 || failed > failedBeforePage) break;
    }
    // 작성자가 만료 전에 삭제했지만 일부 하위 리소스 정리에 실패한 경우도
    // TTL까지 기다리지 않고 durable `deleting` 표식을 기준으로 다시 정리한다.
    const pending = await db().collection(COL.snapshots)
      .where('status', '==', 'deleting')
      .limit(100)
      .get();
    for (let offset = 0; offset < pending.docs.length; offset += 10) {
      const results = await Promise.allSettled(
        pending.docs.slice(offset, offset + 10).map(async (doc) => {
          await deleteSnapshotResources(doc.id, doc.data());
          deleted += 1;
        }),
      );
      for (const result of results) {
        if (result.status === 'rejected') failed += 1;
      }
    }
    runtimeLogsEnabled && runtimeInfo(
      `cleanupExpiredSnapshots deleted=${deleted} failed=${failed} ` +
      `pendingRetried=${pending.size}`,
    );
    return null;
  });

// 클라이언트가 이미지를 올린 직후 종료되면 Callable이 실행되지 않아 문서 없는
// 파일이 남을 수 있다. 2시간의 안전 유예 후 문서가 없는 완성 이미지만 제거한다.
// 한 실행에서 최대 500개만 검사해 Storage 전체 스캔 비용이 무한히 커지지 않게 한다.
export const cleanupOrphanSnapshotUploads = functions.runWith({
  timeoutSeconds: 540,
  memory: '1GB',
}).pubsub.schedule('every 6 hours')
  .timeZone('UTC')
  .onRun(async () => {
    const [files] = await snapshotBucket().getFiles({
      prefix: 'snapshots/',
      maxResults: 500,
      autoPaginate: false,
    });
    const cutoff = Date.now() - ORPHAN_UPLOAD_GRACE_MS;
    let deleted = 0;
    let inspected = 0;

    for (let offset = 0; offset < files.length; offset += 20) {
      await Promise.all(files.slice(offset, offset + 20).map(async (file) => {
        const match = /^snapshots\/([0-9a-f-]{36})\/(?:final\.(?:jpg|mp4)|thumbnail\.jpg)$/i
          .exec(file.name);
        if (!match) return;
        inspected += 1;
        try {
          const [metadata] = await file.getMetadata();
          const createdAt = Date.parse(String(metadata.timeCreated ?? ''));
          if (!Number.isFinite(createdAt) || createdAt > cutoff) return;
          const snapshot = await db().collection(COL.snapshots).doc(match[1]).get();
          if (snapshot.exists) return;
          await file.delete({ignoreNotFound: true});
          deleted += 1;
        } catch (error) {
          console.warn(`orphan snapshot inspection failed path=${file.name}`, error);
        }
      }));
    }

    runtimeLogsEnabled && runtimeInfo(`cleanupOrphanSnapshotUploads inspected=${inspected} deleted=${deleted}`);
    return null;
  });

export const onSnapshotBlockChanged = functions.runWith({
  timeoutSeconds: 120,
  memory: '512MB',
}).firestore.document(`${COL.blocks}/{blockId}`).onWrite(async (change) => {
  const data = change.after.exists ? change.after.data() : change.before.data();
  if (!data) return null;
  const blocker = text(data.blocker);
  const blocked = text(data.blocked);
  if (!blocker || !blocked || blocker === blocked) return null;
  await syncSnapshotFeedPair(blocker, blocked);
  return null;
});
