import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import {COL} from './firestore_paths';
import {
  isActiveUserData,
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

async function profile(uid: string): Promise<FirebaseFirestore.DocumentData> {
  const document = await admin.firestore().collection(COL.users).doc(uid).get();
  const data = document.data() ?? {};
  if (!document.exists || document.get('emailVerified') !== true || !isActiveUserData(data)) {
    throw new functions.https.HttpsError('failed-precondition', 'Verified profile is required.');
  }
  return data;
}

/** 서버가 source group/current friends를 한 번 읽고 immutable audience를 저장한다. */
export const createPostSecure = functions.runWith({timeoutSeconds: 120, memory: '512MB'})
  .https.onCall(async (raw, context) => {
    const uid = requireUid(context);
    const data = object(raw);
    const postId = contentId(data.postId);
    const categoryKey = text(data.categoryKey, 40, 'categoryKey');
    if (!POST_CATEGORY_KEYS.has(categoryKey)) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid category.');
    }
    const frozen = await resolveFrozenAudience(
      uid,
      data.visibility,
      data.visibleToCategoryIds,
    );
    // 현재 포스트 UI는 public/group만 제공한다.
    if (frozen.visibilityMode === 'friends') {
      throw new functions.https.HttpsError('invalid-argument', 'Unsupported post visibility.');
    }
    const user = await profile(uid);
    const now = admin.firestore.Timestamp.now();
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
      imageUrls: stringList(data.imageUrls, 10),
      createdAt: now,
      updatedAt: now,
      visibility: frozen.visibilityMode,
      visibleToCategoryIds: frozen.sourceGroupIds,
      allowedUserIds: frozen.audienceUserIdsFrozen,
      visibilityMode: frozen.visibilityMode,
      audienceUserIdsFrozen: frozen.audienceUserIdsFrozen,
      sourceGroupIds: frozen.sourceGroupIds,
      visibilityLockedAt: now,
      visibilitySchemaVersion: VISIBILITY_SCHEMA_VERSION,
      isAnonymous: data.isAnonymous === true,
      likes: 0,
      likedBy: [],
      commentCount: 0,
      viewCount: 0,
      type,
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
    const user = await profile(uid);
    const dateMillis = integer(data.dateMillis, 0, 8640000000000000, 'date');
    const startsAtMillis = integer(data.startsAtMillis, 0, 8640000000000000, 'startsAt');
    const endsAtMillis = integer(data.endsAtMillis, startsAtMillis, 8640000000000000, 'endsAt');
    const now = admin.firestore.Timestamp.now();
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
      maxParticipants: integer(data.maxParticipants, 1, 100, 'maxParticipants'),
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
      visibilityLockedAt: now,
      visibilitySchemaVersion: VISIBILITY_SCHEMA_VERSION,
      isConfirmed: false,
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
