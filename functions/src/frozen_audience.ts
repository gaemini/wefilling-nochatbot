import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import {COL} from './firestore_paths';

export const VISIBILITY_SCHEMA_VERSION = 2;
export const MAX_FROZEN_AUDIENCE_SIZE = 500;

export type FrozenVisibility = 'public' | 'friends' | 'category';

export function isActiveUserData(data: FirebaseFirestore.DocumentData): boolean {
  return data.isDeleted !== true && data.deleted !== true && data.disabled !== true &&
    data.isSuspended !== true && data.status !== 'deleted' && data.status !== 'suspended';
}

function text(value: unknown): string {
  return (value ?? '').toString().trim();
}

function uniqueIds(value: unknown, max = 10): string[] {
  if (!Array.isArray(value)) return [];
  const ids = Array.from(new Set(value.map(text).filter(Boolean)));
  if (ids.length > max) {
    throw new functions.https.HttpsError('invalid-argument', 'Too many selected groups.');
  }
  return ids;
}

export function parseVisibility(value: unknown): FrozenVisibility {
  const visibility = text(value);
  if (!['public', 'friends', 'category'].includes(visibility)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid visibility.');
  }
  return visibility as FrozenVisibility;
}

async function existingUserIds(ids: Iterable<string>): Promise<string[]> {
  const all = Array.from(new Set(Array.from(ids).map(text).filter(Boolean)));
  if (all.length > MAX_FROZEN_AUDIENCE_SIZE) {
    throw new functions.https.HttpsError(
      'resource-exhausted',
      'The selected audience is too large.',
    );
  }
  if (all.length === 0) return [];

  const store = admin.firestore();
  const valid: string[] = [];
  for (let offset = 0; offset < all.length; offset += 100) {
    const chunk = all.slice(offset, offset + 100);
    const documents = await store.getAll(
      ...chunk.map((uid) => store.collection(COL.users).doc(uid)),
    );
    for (const document of documents) {
      if (!document.exists) continue;
      const data = document.data() ?? {};
      // 계정 정지/탈퇴 표시는 공개 범위와 별개의 접근 거부 정책이지만,
      // 생성 시점에 이미 유효하지 않은 계정은 새 audience에 넣지 않는다.
      if (!isActiveUserData(data)) {
        continue;
      }
      valid.push(document.id);
    }
  }
  return valid;
}

async function friendIdCandidatesAtCreation(ownerId: string): Promise<Set<string>> {
  const store = admin.firestore();
  const audience = new Set<string>([ownerId]);
  const [friendships, outgoing, incoming] = await Promise.all([
    store.collection(COL.friendships).where('uids', 'array-contains', ownerId).get(),
    store.collection(COL.relationships)
      .where('userId', '==', ownerId)
      .where('status', '==', 'accepted')
      .get(),
    store.collection(COL.relationships)
      .where('friendId', '==', ownerId)
      .where('status', '==', 'accepted')
      .get(),
  ]);
  for (const document of friendships.docs) {
    const uids = document.get('uids');
    if (Array.isArray(uids)) for (const uid of uids) audience.add(text(uid));
  }
  for (const document of outgoing.docs) audience.add(text(document.get('friendId')));
  for (const document of incoming.docs) audience.add(text(document.get('userId')));
  return audience;
}

async function friendIdsAtCreation(ownerId: string): Promise<string[]> {
  return existingUserIds(await friendIdCandidatesAtCreation(ownerId));
}

/**
 * 공개 콘텐츠의 푸시는 전체 사용자가 아니라 생성 시점의 친구에게만 보낸다.
 * 콘텐츠 공개 대상(public)과 알림 대상(friend snapshot)을 분리해 저장할 때 사용한다.
 */
export async function resolveFriendNotificationAudience(
  ownerId: string,
): Promise<string[]> {
  // 알림 fan-out이 콘텐츠 생성 자체를 막지 않게 상한까지만 결정적으로
  // 선택한다. 실제 친구 공개 범위(friends)는 위 strict 경로를 유지한다.
  const candidates = Array.from(await friendIdCandidatesAtCreation(ownerId))
    .filter((userId) => userId !== ownerId)
    .sort()
    .slice(0, MAX_FROZEN_AUDIENCE_SIZE);
  return (await existingUserIds(candidates))
    .filter((userId) => userId !== ownerId)
    .sort();
}

async function groupIdsAtCreation(ownerId: string, sourceGroupIds: string[]): Promise<string[]> {
  if (sourceGroupIds.length === 0) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Choose at least one friend group.',
    );
  }
  const store = admin.firestore();
  const documents = await store.getAll(
    ...sourceGroupIds.map((id) => store.collection(COL.friendCategories).doc(id)),
  );
  const audience = new Set<string>([ownerId]);
  for (const document of documents) {
    if (!document.exists || text(document.get('userId')) !== ownerId) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'A selected friend group is unavailable.',
      );
    }
    const friendIds = document.get('friendIds');
    if (Array.isArray(friendIds)) {
      for (const friendId of friendIds) audience.add(text(friendId));
    }
  }
  return existingUserIds(audience);
}

export type FrozenAudience = {
  visibilityMode: FrozenVisibility;
  audienceUserIdsFrozen: string[];
  sourceGroupIds: string[];
};

/**
 * 콘텐츠 생성 순간의 관계/그룹 상태를 UID 배열로 물질화한다.
 * 반환값은 생성 문서에 복사된 뒤 다시 관계 컬렉션과 동기화하지 않는다.
 */
export async function resolveFrozenAudience(
  ownerId: string,
  rawVisibility: unknown,
  rawSourceGroupIds: unknown,
): Promise<FrozenAudience> {
  const visibilityMode = parseVisibility(rawVisibility);
  const sourceGroupIds = visibilityMode === 'category'
    ? uniqueIds(rawSourceGroupIds)
    : [];
  let audienceUserIdsFrozen: string[];
  if (visibilityMode === 'friends') {
    audienceUserIdsFrozen = await friendIdsAtCreation(ownerId);
  } else if (visibilityMode === 'category') {
    audienceUserIdsFrozen = await groupIdsAtCreation(ownerId, sourceGroupIds);
  } else {
    audienceUserIdsFrozen = await existingUserIds([ownerId]);
  }
  if (!audienceUserIdsFrozen.includes(ownerId)) audienceUserIdsFrozen.push(ownerId);
  audienceUserIdsFrozen = Array.from(new Set(audienceUserIdsFrozen)).sort();
  return {visibilityMode, audienceUserIdsFrozen, sourceGroupIds};
}
