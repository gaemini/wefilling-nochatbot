import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import {COL} from './firestore_paths';
import {
  isActiveUserData,
  resolveFrozenAudience,
  VISIBILITY_SCHEMA_VERSION,
} from './frozen_audience';

const SNAPSHOT_FEED = 'snapshot_feed';
const MAX_IMAGE_BYTES = 15 * 1024 * 1024;
const SNAPSHOT_LIFETIME_MS = 24 * 60 * 60 * 1000;
const ORPHAN_UPLOAD_GRACE_MS = 2 * 60 * 60 * 1000;
const ALLOWED_VISIBILITIES = new Set(['public', 'friends', 'category']);
const ALLOWED_REACTIONS = new Set(['❤️', '👏', '😊']);

type SnapshotVisibility = 'public' | 'friends' | 'category';

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

function validSnapshotComment(value: unknown): string {
  const message = text(value);
  const length = Array.from(message).length;
  if (length < 1 || length > 120 || message.includes('\n')) {
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
    fontScale: finiteNumber(overlay.fontScale ?? 1, 'overlay.fontScale', 0.65, 1.75),
  };
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
    aspectRatio: Number(data.aspectRatio) || 0.8,
    reactionCounts: data.reactionCounts ?? {},
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
  const active = await store.collection(COL.snapshots)
    .where('authorId', '==', authorUid)
    .where('status', '==', 'active')
    .where('expiresAt', '>', now)
    .limit(120)
    .get();
  if (active.empty) return;

  const writer = store.bulkWriter();
  for (const document of active.docs) {
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

async function deleteSnapshotResources(
  snapshotId: string,
  data: FirebaseFirestore.DocumentData,
): Promise<void> {
  const snapshotRef = db().collection(COL.snapshots).doc(snapshotId);
  const cleanupResults = await Promise.allSettled([
    removeSnapshotFromFeeds(snapshotId, data),
    deleteQuery(snapshotRef.collection('reactions')),
    deleteQuery(snapshotRef.collection('comments')),
  ]);
  for (const result of cleanupResults) {
    if (result.status === 'rejected') {
      // 피드/하위 컬렉션 정리는 부수 작업이다. 정리 실패 때문에 사용자가
      // 소유한 원본 스낵을 삭제하지 못하는 상태로 남겨 두지 않는다.
      console.warn(`snapshot ancillary cleanup failed id=${snapshotId}`, result.reason);
    }
  }
  const storagePath = text(data.imageStoragePath ?? data.storagePath);
  if (storagePath) {
    try {
      await snapshotBucket().file(storagePath).delete({ignoreNotFound: true});
    } catch (error) {
      console.warn(`snapshot storage delete failed id=${snapshotId}`, error);
    }
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
    const storagePath = text(data.storagePath);
    const expectedPath = `snapshots/${snapshotId}/final.jpg`;
    if (storagePath !== expectedPath) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid storage path.');
    }
    const overlay = parseOverlay(data.overlay);
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
    const imageSize = Number(metadata.size ?? 0);
    if (custom.ownerUid !== uid || custom.snapshotId !== snapshotId ||
        metadata.contentType !== 'image/jpeg' || imageSize < 1 || imageSize > MAX_IMAGE_BYTES) {
      throw new functions.https.HttpsError('permission-denied', 'Invalid image metadata.');
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
      imageStoragePath: storagePath,
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
      overlayText: overlay.text,
      overlayPosition: {x: overlay.x, y: overlay.y},
      overlayStyle: {
        alignment: 'center',
        textColor: overlay.lightText ? 'white' : 'black',
        fontScale: overlay.fontScale,
        backgroundType: 'shadow',
      },
      aspectRatio,
      sourceWidth,
      sourceHeight,
      reactionCounts: {},
      createdAt,
      expiresAt,
      updatedAt: createdAt,
      status: 'active',
    };

    try {
      await ref.create(snapshotData);
      await fanOutSnapshot(snapshotId, snapshotData);
    } catch (error) {
      console.error(`createSnapshot rollback id=${snapshotId}`, error);
      try {
        await removeSnapshotFromFeeds(snapshotId, snapshotData);
        await ref.delete();
        await file.delete({ignoreNotFound: true});
      } catch (rollbackError) {
        console.error(`createSnapshot rollback failed id=${snapshotId}`, rollbackError);
      }
      throw new functions.https.HttpsError('internal', 'Could not create snapshot.');
    }
    console.log(
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
    const queries: Array<{name: string; promise: Promise<FirebaseFirestore.QuerySnapshot>}> = [];
    queries.push({name: 'owner-v2', promise: store.collection(COL.snapshots)
      .where('ownerId', '==', uid)
      .where('status', '==', 'active')
      .where('expiresAt', '>', now)
      .limit(120)
      .get()});
    queries.push({name: 'public-v2', promise: store.collection(COL.snapshots)
      .where('visibilityMode', '==', 'public')
      .where('status', '==', 'active')
      .where('expiresAt', '>', now)
      .limit(120)
      .get()});
    queries.push({name: 'frozen-audience', promise: store.collection(COL.snapshots)
      .where('audienceUserIdsFrozen', 'array-contains', uid)
      .where('status', '==', 'active')
      .where('expiresAt', '>', now)
      .limit(120)
      .get()});
    queries.push({name: 'owner-legacy', promise: store.collection(COL.snapshots)
      .where('authorId', '==', uid)
      .where('status', '==', 'active')
      .where('expiresAt', '>', now)
      .limit(120)
      .get()});
    queries.push({name: 'public-legacy', promise: store.collection(COL.snapshots)
      .where('visibility', '==', 'public')
      .where('status', '==', 'active')
      .where('expiresAt', '>', now)
      .limit(120)
      .get()});
    queries.push({name: 'legacy-audience', promise: store.collection(COL.snapshots)
      .where('allowedUserIds', 'array-contains', uid)
      .where('status', '==', 'active')
      .where('expiresAt', '>', now)
      .limit(120)
      .get()});
    const results = await Promise.allSettled(queries.map((entry) => entry.promise));
    results.forEach((result, index) => {
      const queryName = queries[index].name;
      if (result.status === 'rejected') {
        console.error(`syncMySnapshotFeed query failed type=${queryName} uid=${uid}`, result.reason);
        return;
      }
      for (const doc of result.value.docs) docs.set(doc.id, doc);
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
    }).sort((a, b) => timestampMillis(b.get('createdAt')) - timestampMillis(a.get('createdAt')))
      .slice(0, 120);

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

  const [actorDocument, ownerDocument] = await Promise.all([
    db().collection(COL.users).doc(uid).get(),
    db().collection(COL.users).doc(ownerId).get(),
  ]);
  const actorData = actorDocument.data() ?? {};
  const actorName = text(actorData.nickname ?? actorData.name) || 'User';
  const copy = snapshotReactionCopy(
    reaction,
    actorName,
    prefersKoreanNotification(ownerDocument.data() ?? {}),
  );
  const reactionRef = ref.collection('reactions').doc(uid);
  const notificationRef = db().collection(COL.notifications)
    .doc(`snapshot_reaction_${snapshotId}_${uid}`);
  const result = await db().runTransaction(async (transaction) => {
    const [snapshot, previous] = await Promise.all([
      transaction.get(ref),
      transaction.get(reactionRef),
    ]);
    if (!snapshot.exists) throw new Error('snapshot-missing');
    const snapshotData = snapshot.data() ?? {};
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
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.update(ref, {
      reactionCounts: counts,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // 반응과 알림을 한 트랜잭션으로 저장해 반응만 남거나
    // 재시도로 푸시가 중복 생성되는 상태를 방지한다.
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
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      data: {
        snapshotId,
        reaction,
        actorId: uid,
        actorName,
      },
    });
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
  const requestId = validRequestId(data.requestId);
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
  const [actorDocument, ownerDocument] = await Promise.all([
    db().collection(COL.users).doc(uid).get(),
    db().collection(COL.users).doc(ownerId).get(),
  ]);
  const actorData = actorDocument.data() ?? {};
  const actorName = text(actorData.nickname ?? actorData.name) || 'User';
  const isKorean = prefersKoreanNotification(ownerDocument.data() ?? {});
  const title = isKorean ? '스낵에 코멘트가 도착했어요' : 'New Snack comment';
  const notificationMessage = isKorean
    ? `${actorName}님: ${message}`
    : `${actorName}: ${message}`;
  const commentRef = ref.collection('comments').doc(requestId);
  const notificationRef = db().collection(COL.notifications)
    .doc(`snapshot_comment_${snapshotId}_${requestId}`);
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
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      data: {
        snapshotId,
        comment: message,
        actorId: uid,
        actorName,
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
    while (true) {
      const expired = await db().collection(COL.snapshots)
        .where('expiresAt', '<=', admin.firestore.Timestamp.now())
        .orderBy('expiresAt')
        .limit(100)
        .get();
      if (expired.empty) break;
      for (let offset = 0; offset < expired.docs.length; offset += 10) {
        await Promise.all(expired.docs.slice(offset, offset + 10).map(async (doc) => {
          await deleteSnapshotResources(doc.id, doc.data());
          deleted += 1;
        }));
      }
      if (expired.size < 100) break;
    }
    console.log(`cleanupExpiredSnapshots deleted=${deleted}`);
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
        const match = /^snapshots\/([0-9a-f-]{36})\/final\.jpg$/i.exec(file.name);
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

    console.log(`cleanupOrphanSnapshotUploads inspected=${inspected} deleted=${deleted}`);
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
