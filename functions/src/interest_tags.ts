// #관심 태그: 프로필에 다는 라벨. 가입·관리자·채팅방 없이 tags/{tagId} 하나로 관리한다.
// tagId는 정규화한 이름이라 문서 id만으로 중복이 막힌다.
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import {DocumentReference, FieldPath, FieldValue, Timestamp} from 'firebase-admin/firestore';
import {callables, triggers} from './backend';
import {COL} from './firestore_paths';
import {isSearchableUser} from './searchable_user_policy';
import {FrozenAudience, friendIdCandidatesAtCreation, resolveFrozenAudience} from './frozen_audience';

const db = () => admin.firestore();

export const MAX_PROFILE_TAGS = 8;
export const MAX_CONTENT_TAGS = 3;
/** 구버전 앱이 읽는 users.interests는 최대 5개였다. */
const LEGACY_INTEREST_LIMIT = 5;
export const DAILY_TAG_CREATE_LIMIT = 5;
const TAG_NAME_MIN = 2;
const TAG_NAME_MAX = 20;

/** 운영 금칙어. 정규화한 tagId에 포함되면 만들 수 없다. */
export const BANNED_TAG_WORDS: readonly string[] = [
  'admin', 'wefilling', '위필링', '운영자', '관리자', '공지',
  'fuck', 'shit', '씨발', '시발', '병신', '좆', '섹스', 'sex', 'porn',
];

export type OfficialTag = {
  id: string;
  ko: string;
  en: string;
  zh: string;
  /** 어떤 태그인지 한 줄 설명(ko/en/zh). */
  description: {ko: string; en: string; zh: string};
};

/** 관심사 분류: 태그마다 색을 따로 두지 않고 분류 하나에 한 색을 쓴다. */
export const TAG_CATEGORIES = ['food', 'culture', 'active', 'learn', 'play', 'etc'] as const;
export type TagCategory = typeof TAG_CATEGORIES[number];

/** 공식 태그 분류·이모지(서버만 쓴다). 없는 태그는 etc, 이모지 없음. */
export const OFFICIAL_TAG_STYLE: Readonly<Record<string, {category: TagCategory; emoji: string}>> = {
  restaurants: {category: 'food', emoji: '🍜'},
  cafe: {category: 'food', emoji: '☕'},
  music: {category: 'culture', emoji: '🎧'},
  movie: {category: 'culture', emoji: '🎬'},
  photo: {category: 'culture', emoji: '📷'},
  performance: {category: 'culture', emoji: '🎭'},
  exhibition: {category: 'culture', emoji: '🖼️'},
  travel: {category: 'active', emoji: '✈️'},
  fitness: {category: 'active', emoji: '🏋️'},
  running: {category: 'active', emoji: '🏃'},
  soccer: {category: 'active', emoji: '⚽'},
  basketball: {category: 'active', emoji: '🏀'},
  volunteer: {category: 'active', emoji: '🤝'},
  language: {category: 'learn', emoji: '🗣️'},
  study: {category: 'learn', emoji: '📚'},
  ai: {category: 'learn', emoji: '🤖'},
  reading: {category: 'learn', emoji: '📖'},
  startup: {category: 'learn', emoji: '🚀'},
  development: {category: 'learn', emoji: '💻'},
  game: {category: 'play', emoji: '🎮'},
};

/** 허용된 분류만 받는다. 그 밖은 etc. */
export function normalizeTagCategory(raw: unknown): TagCategory {
  return (TAG_CATEGORIES as readonly string[]).includes(String(raw)) ? raw as TagCategory : 'etc';
}

/** lib/models/social_profile_data.dart SocialProfileCatalog.interests와 같은 표. */
export const OFFICIAL_INTEREST_TAGS: readonly OfficialTag[] = [
  {id: 'restaurants', ko: '맛집', en: 'Food spots', zh: '美食探店',
    description: {ko: '맛있는 집을 함께 찾고 나눠요', en: 'Find and share great places to eat', zh: '一起寻找并分享美食店'}},
  {id: 'cafe', ko: '카페', en: 'Cafes', zh: '咖啡馆',
    description: {ko: '분위기 좋은 카페와 커피 이야기', en: 'Cozy cafes and coffee talk', zh: '好氛围的咖啡馆和咖啡话题'}},
  {id: 'running', ko: '러닝', en: 'Running', zh: '跑步',
    description: {ko: '같이 뛰고 기록을 나눠요', en: 'Run together and share your records', zh: '一起跑步，分享记录'}},
  {id: 'fitness', ko: '헬스', en: 'Fitness', zh: '健身',
    description: {ko: '운동 루틴과 헬스 이야기', en: 'Workout routines and gym talk', zh: '健身计划和健身话题'}},
  {id: 'soccer', ko: '축구', en: 'Soccer', zh: '足球',
    description: {ko: '축구 보고 같이 차요', en: 'Watch and play soccer together', zh: '一起看球、踢球'}},
  {id: 'basketball', ko: '농구', en: 'Basketball', zh: '篮球',
    description: {ko: '농구 경기와 같이 뛸 사람', en: 'Basketball games and pickup runs', zh: '篮球比赛和约球'}},
  {id: 'travel', ko: '여행', en: 'Travel', zh: '旅行',
    description: {ko: '여행 계획과 다녀온 곳 이야기', en: 'Trip plans and travel stories', zh: '旅行计划和游记'}},
  {id: 'photo', ko: '사진', en: 'Photography', zh: '摄影',
    description: {ko: '사진 찍기와 출사', en: 'Taking photos and photo walks', zh: '拍照与外拍'}},
  {id: 'movie', ko: '영화', en: 'Movies', zh: '电影',
    description: {ko: '영화 추천과 같이 보기', en: 'Movie picks and watching together', zh: '电影推荐和一起看电影'}},
  {id: 'music', ko: '음악', en: 'Music', zh: '音乐',
    description: {ko: '좋아하는 음악과 공연 이야기', en: 'Favorite music and live shows', zh: '喜欢的音乐和演出'}},
  {id: 'game', ko: '게임', en: 'Gaming', zh: '游戏',
    description: {ko: '게임 같이 하고 이야기해요', en: 'Play and talk about games', zh: '一起玩游戏、聊游戏'}},
  {id: 'reading', ko: '독서', en: 'Reading', zh: '阅读',
    description: {ko: '책 추천과 독서 모임', en: 'Book picks and reading groups', zh: '好书推荐和读书会'}},
  {id: 'language', ko: '외국어', en: 'Languages', zh: '外语',
    description: {ko: '외국어 공부와 언어 교환', en: 'Language study and exchange', zh: '外语学习和语言交换'}},
  {id: 'study', ko: '스터디', en: 'Study', zh: '学习',
    description: {ko: '같이 공부하고 시험 준비해요', en: 'Study together and prep for exams', zh: '一起学习、备考'}},
  {id: 'exhibition', ko: '전시', en: 'Exhibitions', zh: '展览',
    description: {ko: '전시와 미술관 나들이', en: 'Exhibitions and museum visits', zh: '展览和美术馆'}},
  {id: 'performance', ko: '공연', en: 'Performances', zh: '演出',
    description: {ko: '공연·뮤지컬·콘서트', en: 'Shows, musicals and concerts', zh: '演出、音乐剧和演唱会'}},
  {id: 'volunteer', ko: '봉사', en: 'Volunteering', zh: '志愿服务',
    description: {ko: '봉사 활동을 함께해요', en: 'Volunteer together', zh: '一起做志愿服务'}},
  {id: 'startup', ko: '창업', en: 'Startups', zh: '创业',
    description: {ko: '창업 아이디어와 프로젝트', en: 'Startup ideas and projects', zh: '创业想法和项目'}},
  {id: 'development', ko: '개발', en: 'Development', zh: '开发',
    description: {ko: '개발·코딩 이야기', en: 'Development and coding', zh: '开发与编程'}},
  {id: 'ai', ko: 'AI', en: 'AI', zh: 'AI',
    description: {ko: 'AI 도구와 기술 이야기', en: 'AI tools and tech talk', zh: 'AI 工具与技术'}},
];

export const OFFICIAL_TAG_IDS = new Set(OFFICIAL_INTEREST_TAGS.map((t) => t.id));

const PICTOGRAPHIC = /\p{Extended_Pictographic}/u;

function cleanTagText(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const value = raw.normalize('NFKC').trim().replace(/^#+/, '');
  // 이모지는 지우지 않고 거부한다. 지우면 '러닝🏃'과 '러닝'이 몰래 같은 태그가 된다.
  if (PICTOGRAPHIC.test(value)) return null;
  return value
    .replace(/[^\p{L}\p{N}_\s]/gu, '')
    .replace(/\s+/g, '')
    .toLowerCase();
}

/** 태그 이름 → tagId. 규칙에 맞지 않으면 null. */
export function normalizeTagName(raw: unknown): string | null {
  const value = cleanTagText(raw);
  if (value == null) return null;
  const length = Array.from(value).length;
  if (length < TAG_NAME_MIN || length > TAG_NAME_MAX) return null;
  if (!/^[\p{L}\p{N}_]+$/u.test(value)) return null;
  return value;
}

/** 검색어: 태그 이름과 같은 규칙이지만 1글자부터 받는다. */
export function normalizeTagQuery(raw: unknown): string | null {
  const value = cleanTagText(raw);
  if (!value) return null;
  return Array.from(value).slice(0, TAG_NAME_MAX).join('');
}

export const TAG_DESCRIPTION_MAX = 40;

/** 태그 설명 한 줄: NFKC, 줄바꿈·연속 공백 정리, 40자. 금칙어가 있으면 거부. */
export function normalizeTagDescription(raw: unknown): string {
  if (raw == null) return '';
  if (typeof raw !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'tag-description-invalid');
  }
  const value = Array.from(raw.normalize('NFKC').replace(/\s+/g, ' ').trim())
    .slice(0, TAG_DESCRIPTION_MAX).join('');
  const lowered = value.toLowerCase().replace(/\s+/g, '');
  if (BANNED_TAG_WORDS.some((word) => lowered.includes(word))) {
    throw new functions.https.HttpsError('failed-precondition', 'tag-blocked');
  }
  return value;
}

export function isBannedTagId(id: string): boolean {
  return BANNED_TAG_WORDS.some((word) => id.includes(word));
}

/** 공식 태그를 다른 이름(라벨)으로 찾기 위한 별칭. 예: running → ['러닝','跑步']. */
export function officialTagAliases(tag: OfficialTag): string[] {
  return Array.from(new Set(
    [tag.ko, tag.en, tag.zh]
      .map((label) => normalizeTagName(label))
      .filter((alias): alias is string => alias != null && alias !== tag.id),
  ));
}

/** 공식 태그 문서의 고정 필드(이전 스크립트와 같이 쓴다). 개수·상태는 넣지 않는다. */
export function officialTagFields(tag: OfficialTag): Record<string, unknown> {
  return {
    name: tag.id,
    displayName: tag.en,
    aliases: officialTagAliases(tag),
    labels: {ko: tag.ko, en: tag.en, zh: tag.zh},
    descriptions: tag.description,
    category: OFFICIAL_TAG_STYLE[tag.id]?.category ?? 'etc',
    emoji: OFFICIAL_TAG_STYLE[tag.id]?.emoji ?? '',
    official: true,
    createdBy: 'system',
  };
}

/** 프로필 태그 목록 정리: 정규화, 중복 제거, 최대 8. */
export function sanitizeProfileTagIds(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  const ids = raw
    .map((item) => normalizeTagName(item))
    .filter((id): id is string => id != null);
  return Array.from(new Set(ids)).slice(0, MAX_PROFILE_TAGS);
}

/** 구버전 앱 표시용 users.interests: 공식 태그만, 최대 5. */
export function legacyInterestsFor(tagIds: readonly string[]): string[] {
  return tagIds.filter((id) => OFFICIAL_TAG_IDS.has(id)).slice(0, LEGACY_INTEREST_LIMIT);
}

export function tagIdDiff(prev: readonly string[], next: readonly string[]) {
  return {
    added: next.filter((id) => !prev.includes(id)),
    removed: prev.filter((id) => !next.includes(id)),
  };
}

/**
 * 구버전 앱이 interests만 바꿨을 때 interestTagIds를 맞춘다.
 * 사용자 태그는 그대로 두고, 공식 태그만 interests 기준으로 바꾼다.
 */
export function mergeLegacyInterests(
  currentTagIds: readonly string[],
  legacyInterests: unknown,
): string[] {
  const official = Array.isArray(legacyInterests)
    ? legacyInterests.map((id) => String(id ?? '').trim().toLowerCase())
      .filter((id) => OFFICIAL_TAG_IDS.has(id))
    : [];
  const kept = currentTagIds.filter((id) => !OFFICIAL_TAG_IDS.has(id) || official.includes(id));
  const appended = official.filter((id) => !kept.includes(id));
  return Array.from(new Set([...kept, ...appended])).slice(0, MAX_PROFILE_TAGS);
}

function stringArray(raw: unknown): string[] {
  return Array.isArray(raw) ? raw.filter((item): item is string => typeof item === 'string') : [];
}

function tagRef(id: string) {
  return db().collection(COL.tags).doc(id);
}

export function holderRef(tagId: string, uid: string) {
  return tagRef(tagId).collection('holders').doc(uid);
}

/**
 * 트랜잭션 안에서 태그별 holderCount를 올리고 내리고, tags/{id}/holders/{uid}
 * (단 시각, '최근에 단 사람' 순서)를 맞춘다(쓰기만, 읽기 없음).
 */
export function writeHolderDelta(
  tx: admin.firestore.Transaction,
  uid: string,
  added: readonly string[],
  removed: readonly string[],
): void {
  const inc = FieldValue.increment;
  const now = FieldValue.serverTimestamp();
  added.forEach((id) => {
    tx.set(tagRef(id), {holderCount: inc(1), lastHeldAt: now}, {merge: true});
    tx.set(holderRef(id, uid), {uid, addedAt: now});
  });
  removed.forEach((id) => {
    tx.set(tagRef(id), {holderCount: inc(-1)}, {merge: true});
    tx.delete(holderRef(id, uid));
  });
}

/**
 * 가입 확정 트랜잭션에서 고른 관심사(공식 태그 id)를 interestTagIds로도 저장한다.
 * 모든 읽기가 끝난 뒤 호출해야 한다.
 */
export function signupProfileTagFields(
  tx: admin.firestore.Transaction,
  uid: string,
  existing: Record<string, unknown>,
  interests: readonly string[],
): {interestTagIds: string[]} {
  const next = Array.from(new Set(interests.filter((id) => OFFICIAL_TAG_IDS.has(id))))
    .slice(0, MAX_PROFILE_TAGS);
  const {added, removed} = tagIdDiff(stringArray(existing.interestTagIds), next);
  writeHolderDelta(tx, uid, added, removed);
  return {interestTagIds: next};
}

/**
 * users 갱신 트리거에서 호출. 구버전 앱은 interests만 직접 쓰므로,
 * interests가 바뀌고 interestTagIds는 그대로면 태그 쪽을 따라 맞춘다.
 */
export async function syncLegacyInterestsToTags(
  ref: DocumentReference,
  before: Record<string, unknown>,
  after: Record<string, unknown>,
): Promise<void> {
  const interestsChanged = JSON.stringify(stringArray(before.interests)) !==
    JSON.stringify(stringArray(after.interests));
  const tagsChanged = JSON.stringify(stringArray(before.interestTagIds)) !==
    JSON.stringify(stringArray(after.interestTagIds));
  if (!interestsChanged || tagsChanged) return;
  await db().runTransaction(async (tx) => {
    const latest = (await tx.get(ref)).data() ?? {};
    const prev = stringArray(latest.interestTagIds);
    const next = mergeLegacyInterests(prev, latest.interests);
    const {added, removed} = tagIdDiff(prev, next);
    if (added.length === 0 && removed.length === 0) return;
    writeHolderDelta(tx, ref.id, added, removed);
    tx.update(ref, {interestTagIds: next});
  });
}

function requireUid(context: functions.https.CallableContext): string {
  const uid = context.auth?.uid?.trim() ?? '';
  if (!uid) throw new functions.https.HttpsError('unauthenticated', 'login-required');
  return uid;
}

function pickPublic(data: admin.firestore.DocumentData) {
  return {
    name: String(data.name ?? ''),
    displayName: String(data.displayName ?? data.name ?? ''),
    labels: data.labels && typeof data.labels === 'object' ? data.labels : {},
    // 어떤 태그인지: 공식 태그는 언어별(descriptions), 사용자 태그는 만든 사람이 쓴 한 줄.
    description: String(data.description ?? ''),
    descriptions: data.descriptions && typeof data.descriptions === 'object' ? data.descriptions : {},
    category: normalizeTagCategory(data.category),
    emoji: typeof data.emoji === 'string' ? data.emoji.slice(0, 8) : '',
    official: data.official === true,
    holderCount: Math.max(0, Number(data.holderCount ?? 0) || 0),
    postCount: Math.max(0, Number(data.postCount ?? 0) || 0),
    meetupCount: Math.max(0, Number(data.meetupCount ?? 0) || 0),
  };
}

function officialMatchingQuery(q: string): string[] {
  return OFFICIAL_INTEREST_TAGS
    .filter((tag) => tag.id.startsWith(q) ||
      officialTagAliases(tag).some((alias) => alias.startsWith(q)))
    .map((tag) => tag.id);
}

/** 태그 검색: 이름 접두어 + 별칭 일치 + 공식 태그 라벨 접두어. 많이 단 순. */
export const searchTags = callables()
  .runWith({timeoutSeconds: 10, memory: '256MB'})
  .https.onCall(async (data) => {
    const q = normalizeTagQuery(data?.q);
    if (!q) return {items: [], exact: false, normalized: null};
    const tags = db().collection(COL.tags);
    const officialIds = officialMatchingQuery(q);
    const [byName, byAlias, official] = await Promise.all([
      tags.where('status', '==', 'active').orderBy('name')
        .startAt(q).endAt(q + '').limit(8).get(),
      tags.where('status', '==', 'active').where('aliases', 'array-contains', q)
        .limit(4).get(),
      officialIds.length ? db().getAll(...officialIds.map(tagRef)) : Promise.resolve([]),
    ]);
    const seen = new Set<string>();
    const items = [...byName.docs, ...byAlias.docs, ...official]
      .filter((doc) => doc.exists && doc.get('status') === 'active')
      .filter((doc) => !seen.has(doc.id) && seen.add(doc.id) != null)
      .map((doc) => ({id: doc.id, ...pickPublic(doc.data() ?? {})}))
      .sort((a, b) => b.holderCount - a.holderCount)
      .slice(0, 12);
    const normalized = normalizeTagName(data?.q);
    const exact = normalized != null && items.some((item) => item.id === normalized);
    return {items, exact, normalized};
  });

/**
 * 새 태그 만들기. 같은 이름(또는 공식 태그의 다른 이름)이 있으면 그 태그를 돌려준다.
 * 하루 5개, 금칙어 거부.
 */
export const createTag = callables()
  .runWith({timeoutSeconds: 10, memory: '256MB'})
  .https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const id = normalizeTagName(data?.name);
    if (!id) throw new functions.https.HttpsError('invalid-argument', 'tag-invalid');
    if (isBannedTagId(id)) throw new functions.https.HttpsError('failed-precondition', 'tag-blocked');
    const official = OFFICIAL_INTEREST_TAGS.find((tag) => tag.id === id ||
      officialTagAliases(tag).includes(id));
    if (official) return {id: official.id, created: false};
    const alias = await db().collection(COL.tags)
      .where('aliases', 'array-contains', id).limit(1).get();
    if (!alias.empty) {
      const doc = alias.docs[0];
      if (doc.get('status') !== 'active') {
        throw new functions.https.HttpsError('failed-precondition', 'tag-unavailable');
      }
      return {id: doc.id, created: false};
    }
    const description = normalizeTagDescription(data?.description);
    const category = normalizeTagCategory(data?.category);
    const display = Array.from(String(data?.name).normalize('NFKC').trim().replace(/^#+/, ''))
      .slice(0, TAG_NAME_MAX).join('');
    const day = new Date().toISOString().slice(0, 10);
    const quotaRef = db().collection(COL.usersPrivate).doc(uid).collection('tag_quota').doc(day);
    return db().runTransaction(async (tx) => {
      const [quota, tag] = await Promise.all([tx.get(quotaRef), tx.get(tagRef(id))]);
      if (tag.exists) {
        if (tag.get('status') !== 'active') {
          throw new functions.https.HttpsError('failed-precondition', 'tag-unavailable');
        }
        return {id, created: false};
      }
      const used = Number(quota.get('count') ?? 0) || 0;
      if (used >= DAILY_TAG_CREATE_LIMIT) {
        throw new functions.https.HttpsError('resource-exhausted', 'tag-daily-limit');
      }
      const now = FieldValue.serverTimestamp();
      tx.set(tagRef(id), {
        name: id, displayName: display, aliases: [], labels: {}, official: false,
        description, category, emoji: '',
        holderCount: 0, postCount: 0, meetupCount: 0, status: 'active',
        createdBy: uid, createdAt: now, updatedAt: now,
      });
      tx.set(quotaRef, {count: used + 1, updatedAt: now}, {merge: true});
      return {id, created: true};
    });
  });

/**
 * 프로필 태그 저장(최대 8). 클라이언트는 users.interestTagIds를 직접 쓰지 못한다.
 * 새로 단 태그는 active여야 하고, 이미 달려 있던 태그가 숨김·차단되면 조용히 뺀다.
 * 구버전 앱 표시용 interests(공식 태그 최대 5)도 같이 맞춘다.
 */
export const setProfileTags = callables()
  .runWith({timeoutSeconds: 15, memory: '256MB'})
  .https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const requested = sanitizeProfileTagIds(data?.tagIds);
    const userRef = db().collection(COL.users).doc(uid);
    const saved = await db().runTransaction(async (tx) => {
      const user = await tx.get(userRef);
      if (!user.exists || !isSearchableUser(uid, user.data())) {
        throw new functions.https.HttpsError('failed-precondition', 'account-unavailable');
      }
      const prev = stringArray(user.get('interestTagIds'));
      const snaps = requested.length ? await tx.getAll(...requested.map(tagRef)) : [];
      const next: string[] = [];
      snaps.forEach((snap) => {
        const active = snap.exists && snap.get('status') === 'active';
        if (active) next.push(snap.id);
        else if (!prev.includes(snap.id)) {
          throw new functions.https.HttpsError('failed-precondition', `tag-unavailable:${snap.id}`);
        }
      });
      const {added, removed} = tagIdDiff(prev, next);
      writeHolderDelta(tx, uid, added, removed);
      tx.update(userRef, {
        interestTagIds: next,
        interests: legacyInterestsFor(next),
        profileUpdatedAt: FieldValue.serverTimestamp(),
      });
      return {tagIds: next, prev, added};
    });
    // '+n명과 겹쳐요': 새로 단 태그를 단 사람 중 전에 나와 겹치는 태그가 없던 사람 수(어림).
    let gain: Record<string, number> = {};
    try {
      gain = await overlapGain(uid, saved.prev, saved.added);
    } catch (error) {
      functions.logger.warn('setProfileTags gain failed', {error: String(error)});
    }
    return {tagIds: saved.tagIds, gain};
  });

const GAIN_SCAN_LIMIT = 150;

/** 새로 단 태그마다, 그 태그를 단 사람 중 [prev] 태그와 겹치지 않던 사람 수. */
export async function overlapGain(
  uid: string,
  prev: readonly string[],
  added: readonly string[],
): Promise<Record<string, number>> {
  const before = new Set(prev);
  const entries = await Promise.all(added.map(async (tagId) => {
    const snap = await db().collection(COL.users)
      .where('interestTagIds', 'array-contains', tagId)
      .limit(GAIN_SCAN_LIMIT)
      .get();
    const count = snap.docs.filter((doc) => doc.id !== uid &&
      isSearchableUser(doc.id, doc.data()) &&
      !stringArray(doc.get('interestTagIds')).some((id) => before.has(id))).length;
    return [tagId, count] as const;
  }));
  return Object.fromEntries(entries);
}

/**
 * 태그를 단 사람, 최근에 단 순(본인·비활성·차단·숨긴 사람 제외).
 * tags/{id}/holders의 addedAt 커서 페이지. 커서는 'millis_uid'.
 */
export const listTagHolders = callables()
  .runWith({timeoutSeconds: 20, memory: '256MB'})
  .https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const tagId = normalizeTagName(data?.tagId);
    if (!tagId) throw new functions.https.HttpsError('invalid-argument', 'tag-invalid');
    const limit = Math.max(1, Math.min(30, Math.trunc(Number(data?.limit) || 30)));
    const rawCursor = String(data?.cursor ?? '').trim();
    const cursorMatch = /^(\d{1,15})_([A-Za-z0-9_-]{1,128})$/.exec(rawCursor);
    if (rawCursor && !cursorMatch) {
      throw new functions.https.HttpsError('invalid-argument', 'cursor-invalid');
    }
    let query = tagRef(tagId).collection('holders')
      .orderBy('addedAt', 'desc')
      .orderBy(FieldPath.documentId(), 'desc')
      .limit(limit);
    if (cursorMatch) {
      query = query.startAfter(Timestamp.fromMillis(Number(cursorMatch[1])), cursorMatch[2]);
    }
    const snapshot = await query.get();
    const ids = snapshot.docs.map((doc) => doc.id).filter((id) => id !== uid);
    const userDocs = ids.length ? await db().getAll(...ids.map((id) => db().collection(COL.users).doc(id))) : [];
    const candidates = userDocs.filter((doc) => doc.exists && isSearchableUser(doc.id, doc.data()) &&
      stringArray(doc.get('interestTagIds')).includes(tagId));
    const related = candidates.length === 0 ? [] : await db().getAll(
      ...candidates.flatMap((doc) => [
        db().collection(COL.blocks).doc(`${uid}_${doc.id}`),
        db().collection(COL.blocks).doc(`${doc.id}_${uid}`),
        db().collection(COL.usersPrivate).doc(doc.id),
      ]),
    );
    const users = candidates.filter((_, index) => {
      const hidden = related[index * 3 + 2]?.get(`tagPrefs.${tagId}.hidden`) === true;
      return !related[index * 3]?.exists && !related[index * 3 + 1]?.exists && !hidden;
    }).map(personSummary);
    const last = snapshot.docs[snapshot.docs.length - 1];
    const lastAdded = last?.get('addedAt') as Timestamp | undefined;
    const cursor = snapshot.size === limit && last && lastAdded
      ? `${lastAdded.toMillis()}_${last.id}`
      : null;
    return {users, cursor};
  });

const FRIEND_SCAN_LIMIT = 300;
const FRIEND_FACE_LIMIT = 30;

function chunks<T>(items: readonly T[], size: number): T[][] {
  const result: T[][] = [];
  for (let start = 0; start < items.length; start += size) result.push(items.slice(start, start + size));
  return result;
}

function personSummary(doc: admin.firestore.DocumentSnapshot) {
  const profile = doc.data() ?? {};
  return {
    uid: doc.id,
    nickname: String(profile.nickname || '').trim(),
    photoURL: String(profile.photoURL || '').trim(),
    nationality: String(profile.nationality || '').trim(),
    university: String(profile.university || '').trim(),
    studentType: String(profile.studentType || '').trim(),
    // 사람 줄 보조 문구('#러닝 #카페 #사진').
    tags: stringArray(profile.interestTagIds).slice(0, 4),
  };
}

/** 이 태그를 단 친구(차단·비활성·숨김 제외). 태그 페이지 '친구 먼저'와 미리보기 얼굴에 쓴다. */
export async function friendTagHolders(uid: string, tagId: string) {
  const friendIds = Array.from(await friendIdCandidatesAtCreation(uid))
    .filter((id) => id && id !== uid && !id.includes('/'))
    .slice(0, FRIEND_SCAN_LIMIT);
  const snaps = await Promise.all(chunks(friendIds, 30).map((ids) => db().collection(COL.users)
    .where('interestTagIds', 'array-contains', tagId)
    .where(FieldPath.documentId(), 'in', ids)
    .get()));
  const docs = snaps.flatMap((snap) => snap.docs)
    .filter((doc) => isSearchableUser(doc.id, doc.data()));
  if (docs.length === 0) return [];
  const related = await db().getAll(...docs.flatMap((doc) => [
    db().collection(COL.blocks).doc(`${uid}_${doc.id}`),
    db().collection(COL.blocks).doc(`${doc.id}_${uid}`),
    db().collection(COL.usersPrivate).doc(doc.id),
  ]));
  return docs.filter((_, index) => !related[index * 3]?.exists &&
    !related[index * 3 + 1]?.exists &&
    related[index * 3 + 2]?.get(`tagPrefs.${tagId}.hidden`) !== true)
    .map(personSummary);
}

/** 태그 미리보기·태그 페이지 머리: 태그 정보, 내가 달았는지, 태그를 단 친구, 내 태그 설정. */
export const getTagSummary = callables()
  .runWith({timeoutSeconds: 20, memory: '256MB'})
  .https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const tagId = normalizeTagName(data?.tagId);
    if (!tagId) throw new functions.https.HttpsError('invalid-argument', 'tag-invalid');
    const [tag, me, prefs] = await db().getAll(
      tagRef(tagId),
      db().collection(COL.users).doc(uid),
      db().collection(COL.usersPrivate).doc(uid),
    );
    if (!tag.exists || tag.get('status') !== 'active') {
      throw new functions.https.HttpsError('not-found', 'tag-unavailable');
    }
    const [friends, trending] = await Promise.all([
      friendTagHolders(uid, tagId),
      db().collection('tags_trending').doc('current').get(),
    ]);
    const weekly = ((trending.get('items') as Array<{id: string; delta: number}> | undefined) ?? [])
      .find((item) => item.id === tagId)?.delta ?? 0;
    const pref = prefs.get(`tagPrefs.${tagId}`) ?? {};
    return {
      tag: {id: tag.id, ...pickPublic(tag.data() ?? {})},
      aliases: stringArray(tag.get('aliases')),
      mine: stringArray(me.get('interestTagIds')).includes(tagId),
      canEditDescription: tag.get('official') !== true && tag.get('createdBy') === uid,
      friendCount: friends.length,
      friends: friends.slice(0, FRIEND_FACE_LIMIT),
      weeklyGain: Math.max(0, Number(weekly) || 0),
      hidden: pref.hidden === true,
      notify: pref.notify === true,
    };
  });

/** 내 태그 설정: hidden(태그 사람 목록에서 나를 숨김), notify(새 글 알림). */
export const setTagPrefs = callables()
  .runWith({timeoutSeconds: 10, memory: '256MB'})
  .https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const tagId = normalizeTagName(data?.tagId);
    if (!tagId) throw new functions.https.HttpsError('invalid-argument', 'tag-invalid');
    const update: Record<string, boolean> = {};
    if (typeof data?.hidden === 'boolean') update.hidden = data.hidden;
    if (typeof data?.notify === 'boolean') update.notify = data.notify;
    if (Object.keys(update).length === 0) {
      throw new functions.https.HttpsError('invalid-argument', 'nothing-to-update');
    }
    await db().collection(COL.usersPrivate).doc(uid)
      .set({tagPrefs: {[tagId]: update}, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return {tagId, ...update};
  });

const SUGGEST_LIMIT = 12;

/** 태그 추천: 친구들이 많이 단 태그(내가 단 것 제외)와 많이 다는 태그. */
export const getTagSuggestions = callables()
  .runWith({timeoutSeconds: 20, memory: '256MB'})
  .https.onCall(async (_data, context) => {
    const uid = requireUid(context);
    const [me, friendIds] = await Promise.all([
      db().collection(COL.users).doc(uid).get(),
      friendIdCandidatesAtCreation(uid),
    ]);
    const mine = new Set(stringArray(me.get('interestTagIds')));
    const ids = Array.from(friendIds).filter((id) => id && id !== uid && !id.includes('/'))
      .slice(0, FRIEND_SCAN_LIMIT);
    const friendDocs = ids.length ? await db().getAll(...ids.map((id) => db().collection(COL.users).doc(id))) : [];
    const counts = new Map<string, number>();
    friendDocs.filter((doc) => doc.exists && isSearchableUser(doc.id, doc.data()))
      .forEach((doc) => stringArray(doc.get('interestTagIds')).forEach((id) => {
        if (!mine.has(id)) counts.set(id, (counts.get(id) ?? 0) + 1);
      }));
    const friendTop = Array.from(counts.entries()).sort((a, b) => b[1] - a[1])
      .slice(0, SUGGEST_LIMIT).map(([id]) => id);
    const [friendTagDocs, popular] = await Promise.all([
      friendTop.length ? db().getAll(...friendTop.map(tagRef)) : Promise.resolve([]),
      popularTags(mine, SUGGEST_LIMIT),
    ]);
    const toItem = (doc: admin.firestore.DocumentSnapshot) =>
      ({id: doc.id, ...pickPublic(doc.data() ?? {})});
    return {
      friends: friendTagDocs.filter((doc) => doc.exists && doc.get('status') === 'active')
        .map((doc) => ({...toItem(doc), friendCount: counts.get(doc.id) ?? 0})),
      // '요즘 많이 다는 태그': 이번 주 증가(delta). 집계가 아직 없으면 많이 단 순.
      popular,
    };
  });

/**
 * 글·모임에 붙일 태그(최대 3). 정규화·중복 제거 후 모두 active여야 한다.
 */
export async function resolveContentTagIds(raw: unknown): Promise<string[]> {
  if (raw == null) return [];
  if (!Array.isArray(raw)) throw new functions.https.HttpsError('invalid-argument', 'tag-invalid');
  const normalized = raw.map((item) => normalizeTagName(item));
  if (normalized.some((id) => id == null)) {
    throw new functions.https.HttpsError('invalid-argument', 'tag-invalid');
  }
  const ids = Array.from(new Set(normalized as string[]));
  if (ids.length > MAX_CONTENT_TAGS) {
    throw new functions.https.HttpsError('invalid-argument', 'tag-too-many');
  }
  if (ids.length === 0) return [];
  const snaps = await db().getAll(...ids.map(tagRef));
  const unavailable = snaps.find((snap) => !snap.exists || snap.get('status') !== 'active');
  if (unavailable) {
    throw new functions.https.HttpsError('failed-precondition', `tag-unavailable:${unavailable.id}`);
  }
  return ids;
}

function countedTagIds(data: admin.firestore.DocumentData | undefined): string[] {
  if (!data || data.isHidden === true || data.status === 'deleted' || data.isDeleted === true) return [];
  return stringArray(data.tagIds).slice(0, MAX_CONTENT_TAGS);
}

/** 글·모임 문서 변경 → 태그별 개수 변화. */
export function contentTagCountDelta(
  before: admin.firestore.DocumentData | undefined,
  after: admin.firestore.DocumentData | undefined,
): Map<string, number> {
  const delta = new Map<string, number>();
  const prev = countedTagIds(before);
  const next = countedTagIds(after);
  prev.filter((id) => !next.includes(id)).forEach((id) => delta.set(id, -1));
  next.filter((id) => !prev.includes(id)).forEach((id) => delta.set(id, 1));
  return delta;
}

/** 기존 posts/meetups onWrite 트리거에서 호출한다(바뀐 게 없으면 읽기·쓰기 없음). */
export async function syncContentTagCounts(
  field: 'postCount' | 'meetupCount',
  before: admin.firestore.DocumentData | undefined,
  after: admin.firestore.DocumentData | undefined,
): Promise<void> {
  const delta = contentTagCountDelta(before, after);
  if (delta.size === 0) return;
  const batch = db().batch();
  delta.forEach((change, id) => batch.set(tagRef(id), {[field]: FieldValue.increment(change)}, {merge: true}));
  await batch.commit();
}

// ===== 공개 범위 '#태그 가진 사람' =====

/** functions/.env TAG_AUDIENCE_ENABLED=true일 때만 새 공개 범위를 받는다(기본 꺼짐). */
export function tagAudienceEnabled(env: Record<string, string | undefined> = process.env): boolean {
  return (env.TAG_AUDIENCE_ENABLED ?? '').trim().toLowerCase() === 'true';
}

export async function viewerTagIds(uid: string): Promise<string[]> {
  if (!uid) return [];
  const snap = await db().collection(COL.users).doc(uid).get();
  return stringArray(snap.get('interestTagIds'));
}

/** 태그 공개 글을 이 사용자 태그로 볼 수 있는지(규칙 tagAudienceCanRead와 같은 판정). */
export function tagAudienceAllows(viewerTags: readonly string[], data: admin.firestore.DocumentData | undefined): boolean {
  if (!data || String(data.visibility ?? '') !== 'tag') return false;
  const audience = stringArray(data.audienceTagIds);
  return audience.length > 0 && audience.some((id) => viewerTags.includes(id));
}

/** uids 중 tagIds를 하나라도 단 활성 사용자. */
export async function tagHoldersAmong(uids: readonly string[], tagIds: readonly string[]): Promise<string[]> {
  const ids = Array.from(new Set(uids)).filter((id) => id && !id.includes('/'));
  const holders: string[] = [];
  for (const chunk of chunks(ids, 100)) {
    const docs = await db().getAll(...chunk.map((id) => db().collection(COL.users).doc(id)));
    docs.forEach((doc) => {
      if (doc.exists && isSearchableUser(doc.id, doc.data()) &&
          stringArray(doc.get('interestTagIds')).some((id) => tagIds.includes(id))) {
        holders.push(doc.id);
      }
    });
  }
  return holders;
}

const FEED_PAGE = 20;

/**
 * 태그 공개 글·모임 목록. 규칙은 필터가 아니므로 목록은 이 함수로만 만든다.
 * - kind: posts | meetups, tagId(태그 페이지) 없으면 내 태그 전체(최대 10)
 * - 모임은 fromMillis~toMillis 날짜 범위(밋업 탭 달력)로도 부를 수 있다.
 * - 내가 달지 않은 태그를 물으면 목록 없이 lockedCount(볼 수 있게 될 개수)만 준다.
 */
export const getTagAudienceFeed = callables()
  .runWith({timeoutSeconds: 20, memory: '256MB'})
  .https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const kind = data?.kind === 'meetups' ? COL.meetups : COL.posts;
    const myTags = await viewerTagIds(uid);
    const only = data?.tagId == null ? null : normalizeTagName(data.tagId);
    if (data?.tagId != null && !only) {
      throw new functions.https.HttpsError('invalid-argument', 'tag-invalid');
    }
    if (only && !myTags.includes(only)) {
      const counted = await db().collection(kind)
        .where('visibility', '==', 'tag')
        .where('audienceTagIds', 'array-contains', only)
        .count().get();
      return {items: [], cursor: null, lockedCount: counted.data().count};
    }
    const tags = only ? [only] : myTags.slice(0, 10);
    if (tags.length === 0) return {items: [], cursor: null, lockedCount: 0};

    let query: admin.firestore.Query = db().collection(kind)
      .where('visibility', '==', 'tag')
      .where('audienceTagIds', 'array-contains-any', tags);
    const byDate = kind === COL.meetups && data?.fromMillis != null;
    if (byDate) {
      const from = Number(data.fromMillis);
      const to = Number(data.toMillis);
      if (!Number.isFinite(from) || !Number.isFinite(to) || to < from || to - from > 100 * 86400000) {
        throw new functions.https.HttpsError('invalid-argument', 'range-invalid');
      }
      query = query
        .where('date', '>=', Timestamp.fromMillis(from))
        .where('date', '<', Timestamp.fromMillis(to))
        .orderBy('date').limit(100);
    } else {
      query = query.orderBy('createdAt', 'desc').limit(FEED_PAGE);
      const cursor = Number(data?.cursor);
      if (data?.cursor != null && Number.isFinite(cursor)) {
        query = query.startAfter(Timestamp.fromMillis(cursor));
      }
    }
    const snap = await query.get();
    const owners = Array.from(new Set(snap.docs.map((doc) => String(doc.get('userId') ?? ''))))
      .filter((owner) => owner && owner !== uid && !owner.includes('/'));
    const blocks = owners.length === 0 ? [] : await db().getAll(...owners.flatMap((owner) => [
      db().collection(COL.blocks).doc(`${uid}_${owner}`),
      db().collection(COL.blocks).doc(`${owner}_${uid}`),
    ]));
    const blocked = new Set(owners.filter((_, i) => blocks[i * 2]?.exists || blocks[i * 2 + 1]?.exists));
    const items = snap.docs
      .filter((doc) => doc.get('isHidden') !== true && !blocked.has(String(doc.get('userId') ?? '')))
      .map((doc) => ({id: doc.id, ...(serializeForClient(doc.data()) as Record<string, unknown>)}));
    const last = snap.docs[snap.docs.length - 1];
    const cursor = !byDate && snap.size === FEED_PAGE
      ? (last.get('createdAt') as Timestamp | undefined)?.toMillis() ?? null
      : null;
    return {items, cursor, lockedCount: 0};
  });

/** 콜러블 응답용: Timestamp → {_millis}. 앱은 _millis를 DateTime으로 바꾼다. */
export function serializeForClient(value: unknown): unknown {
  if (value instanceof Timestamp) return {_millis: value.toMillis()};
  if (Array.isArray(value)) return value.map(serializeForClient);
  if (value && typeof value === 'object' && !(value instanceof DocumentReference)) {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>)
      .map(([key, item]) => [key, serializeForClient(item)]));
  }
  if (value instanceof DocumentReference) return value.path;
  return value;
}

export type TagAudience = {
  frozen: FrozenAudience;
  audienceTagIds: string[];
  friendsOnly: boolean;
};

/**
 * 생성 요청의 visibility가 'tag'일 때 공개 대상을 정한다. 아니면 null.
 * - friendsOnly: 지금 친구 중 태그를 단 사람만 얼린다(저장 visibility='friends',
 *   구버전 앱·기존 규칙이 그대로 읽는다).
 * - 아니면 visibility='tag', allowedUserIds=[작성자]: 구버전 쿼리에 걸리지 않고,
 *   목록은 getTagAudienceFeed, 상세는 규칙 tagAudienceCanRead로만 본다.
 */
export async function resolveTagAudience(
  ownerId: string,
  data: Record<string, unknown>,
  tagIds: readonly string[],
): Promise<TagAudience | null> {
  if (data.visibility !== 'tag') return null;
  if (!tagAudienceEnabled()) {
    throw new functions.https.HttpsError('failed-precondition', 'tag-audience-disabled');
  }
  if (tagIds.length === 0) {
    throw new functions.https.HttpsError('invalid-argument', 'tag-audience-needs-tags');
  }
  if (data.isAnonymous === true || data.requiresHanyangVerification === true) {
    throw new functions.https.HttpsError('invalid-argument', 'tag-audience-unsupported');
  }
  // 공개 범위 태그는 글 태그 중 고른 것(없으면 전부).
  let audienceTagIds = [...tagIds];
  if (Array.isArray(data.audienceTagIds) && data.audienceTagIds.length > 0) {
    const chosen = Array.from(new Set(data.audienceTagIds.map((item) => normalizeTagName(item))));
    if (chosen.some((id) => id == null || !tagIds.includes(id))) {
      throw new functions.https.HttpsError('invalid-argument', 'tag-audience-invalid');
    }
    audienceTagIds = chosen as string[];
  }
  const friendsOnly = data.audienceFriendsOnly === true;
  if (friendsOnly) {
    const friends = await resolveFrozenAudience(ownerId, 'friends', []);
    const holders = await tagHoldersAmong(
      friends.audienceUserIdsFrozen.filter((id) => id !== ownerId), audienceTagIds);
    return {
      frozen: {
        visibilityMode: 'friends',
        audienceUserIdsFrozen: Array.from(new Set([ownerId, ...holders])).sort(),
        sourceGroupIds: [],
      },
      audienceTagIds,
      friendsOnly: true,
    };
  }
  return {
    frozen: {visibilityMode: 'tag', audienceUserIdsFrozen: [ownerId], sourceGroupIds: []},
    audienceTagIds,
    friendsOnly: false,
  };
}

/** 공개 범위 시트의 '약 n명': 태그별 holderCount 합(근사), 친구 중에서만이면 실제 친구 수. */
export const estimateTagAudience = callables()
  .runWith({timeoutSeconds: 20, memory: '256MB'})
  .https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const raw: unknown[] = Array.isArray(data?.tagIds) ? data.tagIds : [];
    const tagIds = Array.from(new Set(raw.map((item) => normalizeTagName(item))
      .filter((id): id is string => id != null))).slice(0, MAX_CONTENT_TAGS);
    if (tagIds.length === 0) return {count: 0, approximate: false};
    if (data?.friendsOnly === true) {
      const friends = Array.from(await friendIdCandidatesAtCreation(uid)).filter((id) => id !== uid);
      return {count: (await tagHoldersAmong(friends, tagIds)).length, approximate: false};
    }
    const docs = await db().getAll(...tagIds.map(tagRef));
    const sum = docs.reduce((total, doc) => total + Math.max(0, Number(doc.get('holderCount') ?? 0) || 0), 0);
    return {count: sum, approximate: true};
  });

// ===== 태그 알림 =====

export const TAG_NOTIFY_DAILY_LIMIT = 3;
const TAG_NOTIFY_CANDIDATE_LIMIT = 500;

/** 이 태그들에 알림을 켠 사람(users_private.tagPrefs.<tag>.notify == true) → 켠 태그. */
export async function tagNotifyCandidates(tagIds: readonly string[]): Promise<Map<string, string[]>> {
  const byUser = new Map<string, string[]>();
  const snaps = await Promise.all(tagIds.map((tagId) => db().collection(COL.usersPrivate)
    .where(new FieldPath('tagPrefs', tagId, 'notify'), '==', true)
    .limit(TAG_NOTIFY_CANDIDATE_LIMIT).get()));
  snaps.forEach((snap, index) => snap.docs.forEach((doc) => {
    byUser.set(doc.id, [...(byUser.get(doc.id) ?? []), tagIds[index]]);
  }));
  return byUser;
}

/** 글·모임의 공개 범위로 이 사람이 볼 수 있는지(태그 보유는 따로 확인). */
export function contentAudienceIncludes(uid: string, data: admin.firestore.DocumentData): boolean {
  const visibility = String(data.visibility ?? 'public');
  if (visibility === 'public' || visibility === 'tag') return true;
  const audience = stringArray(Number(data.visibilitySchemaVersion ?? 0) >= 2 ?
    data.audienceUserIdsFrozen : data.allowedUserIds);
  return audience.includes(uid);
}

export function tagNotificationCopy(
  language: string,
  kind: 'post' | 'meetup',
  tagLabel: string,
  count: number,
): {title: string; message: string} {
  const lang = language.startsWith('ko') ? 'ko' : language.startsWith('zh') ? 'zh' : 'en';
  const title = `#${tagLabel}`;
  if (lang === 'ko') {
    return {title, message: kind === 'post' ? `#${tagLabel}에 새 글 ${count}개` : `#${tagLabel}에 새 모임 ${count}개`};
  }
  if (lang === 'zh') {
    return {title, message: kind === 'post' ? `#${tagLabel} 有 ${count} 篇新帖子` : `#${tagLabel} 有 ${count} 个新聚会`};
  }
  return {
    title,
    message: kind === 'post'
      ? `${count} new ${count === 1 ? 'post' : 'posts'} in #${tagLabel}`
      : `${count} new ${count === 1 ? 'meetup' : 'meetups'} in #${tagLabel}`,
  };
}

/** 하루 태그별 알림 횟수를 1 올린다. 한도를 넘으면 null, 아니면 오늘 몇 번째인지. */
export async function takeTagNotifySlot(uid: string, tagId: string, day: string): Promise<number | null> {
  const ref = db().collection(COL.usersPrivate).doc(uid).collection('tag_notify').doc(`${tagId}_${day}`);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const used = Number(snap.get('count') ?? 0) || 0;
    if (used >= TAG_NOTIFY_DAILY_LIMIT) return null;
    tx.set(ref, {count: used + 1, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return used + 1;
  });
}

// ===== 뜨는 태그 · 새 글 개수 =====

const TREND_WINDOW_DAYS = 7;
const TREND_LIMIT = 20;

export function dayKey(millis: number): string {
  return new Date(millis).toISOString().slice(0, 10);
}

/**
 * 7일 holderCount 증가로 뜨는 태그를 고른다. 7일 전 기록이 아직 없으면(집계 첫 주)
 * 비워 둔다. 이전 직후 공식 태그 전체가 '이번 주 +n'으로 보이지 않게 한다.
 */
export function pickTrendingTags(
  now: Map<string, {count: number; createdAtMillis: number}>,
  before: Record<string, number> | null,
): Array<{id: string; delta: number}> {
  if (!before) return [];
  return Array.from(now.entries())
    .map(([id, tag]) => ({id, delta: tag.count - (before[id] ?? 0)}))
    .filter((item) => item.delta > 0)
    .sort((a, b) => b.delta - a.delta || a.id.localeCompare(b.id))
    .slice(0, TREND_LIMIT);
}

/** 하루 한 번: 태그별 holderCount를 tags_daily/{day}에 남기고 tags_trending/current를 갱신한다. */
export const computeTagTrends = triggers()
  .runWith({timeoutSeconds: 120, memory: '256MB'})
  .pubsub.schedule('every 24 hours')
  .onRun(async () => {
    const nowMillis = Date.now();
    const snap = await db().collection(COL.tags).where('status', '==', 'active')
      .select('holderCount', 'createdAt').get();
    const now = new Map<string, {count: number; createdAtMillis: number}>();
    snap.docs.forEach((doc) => now.set(doc.id, {
      count: Math.max(0, Number(doc.get('holderCount') ?? 0) || 0),
      createdAtMillis: (doc.get('createdAt') as Timestamp | undefined)?.toMillis() ?? 0,
    }));
    const daily = db().collection('tags_daily');
    const before = await daily.doc(dayKey(nowMillis - TREND_WINDOW_DAYS * 86400000)).get();
    const items = pickTrendingTags(now, before.exists ? (before.get('counts') ?? {}) : null);
    const batch = db().batch();
    batch.set(daily.doc(dayKey(nowMillis)), {
      counts: Object.fromEntries(Array.from(now.entries()).map(([id, tag]) => [id, tag.count])),
      updatedAt: FieldValue.serverTimestamp(),
    });
    batch.set(db().collection('tags_trending').doc('current'), {
      items, updatedAt: FieldValue.serverTimestamp(),
    });
    batch.delete(daily.doc(dayKey(nowMillis - 15 * 86400000)));
    await batch.commit();
    return null;
  });

/**
 * 게시판 '내 #태그 새 글': 내 태그별로 since 이후 새 글 수(공개 글 + 내가 볼 수 있는 태그 공개 글).
 * since가 없으면 7일 전부터. 개수 쿼리라 글 1000개당 읽기 1회.
 */
export const getMyTagNewCounts = callables()
  .runWith({timeoutSeconds: 20, memory: '256MB'})
  .https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const myTags = (await viewerTagIds(uid)).slice(0, MAX_PROFILE_TAGS);
    const since = data?.since && typeof data.since === 'object' ? data.since as Record<string, unknown> : {};
    const fallback = Date.now() - TREND_WINDOW_DAYS * 86400000;
    const posts = db().collection(COL.posts);
    const entries = await Promise.all(myTags.map(async (tagId) => {
      const raw = Number(since[tagId]);
      const after = Timestamp.fromMillis(Number.isFinite(raw) && raw > 0 ? raw : fallback);
      const [publicCount, tagCount] = await Promise.all([
        posts.where('visibility', '==', 'public').where('tagIds', 'array-contains', tagId)
          .where('createdAt', '>', after).count().get(),
        posts.where('visibility', '==', 'tag').where('audienceTagIds', 'array-contains', tagId)
          .where('createdAt', '>', after).count().get(),
      ]);
      return [tagId, publicCount.data().count + tagCount.data().count] as const;
    }));
    return {counts: Object.fromEntries(entries)};
  });


/** 요즘 많이 다는 태그: tags_trending/current(이번 주 증가), 없으면 많이 단 순. */
async function popularTags(exclude: ReadonlySet<string>, limit: number) {
  const trending = await db().collection('tags_trending').doc('current').get();
  const items = (trending.get('items') as Array<{id: string; delta: number}> | undefined) ?? [];
  const wanted = items.filter((item) => !exclude.has(item.id)).slice(0, limit);
  if (wanted.length > 0) {
    const docs = await db().getAll(...wanted.map((item) => tagRef(item.id)));
    return docs.filter((doc) => doc.exists && doc.get('status') === 'active').map((doc) => ({
      id: doc.id,
      ...pickPublic(doc.data() ?? {}),
      delta: wanted.find((item) => item.id === doc.id)?.delta ?? 0,
    }));
  }
  const snap = await db().collection(COL.tags).where('status', '==', 'active')
    .orderBy('holderCount', 'desc').limit(limit + exclude.size).get();
  return snap.docs.filter((doc) => !exclude.has(doc.id)).slice(0, limit)
    .map((doc) => ({id: doc.id, ...pickPublic(doc.data() ?? {}), delta: 0}));
}

const EXPLORE_LIMIT = 20;
const COOCCUR_SAMPLE = 300;

/**
 * 태그 둘러보기 목록과 줄마다의 이유(보조 문구).
 * - recommended: 내 태그와 함께 많이 달린 태그(reason.withTag). 내 태그가 없으면 많이 단 순.
 * - friends: 친구들이 단 태그(reason.friendNames, friendCount)
 * - trending: 이번 주 증가(reason.delta)
 * - newest: 새로 생긴 태그(reason.createdAtMillis)
 */
export const exploreTags = callables()
  .runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const filter = String(data?.filter ?? 'recommended');
    const me = await db().collection(COL.users).doc(uid).get();
    const mine = new Set(stringArray(me.get('interestTagIds')));
    const toItem = (doc: admin.firestore.DocumentSnapshot, reason: Record<string, unknown>) =>
      ({id: doc.id, ...pickPublic(doc.data() ?? {}), reason});
    const activeDocs = async (ids: string[]) => ids.length === 0 ? [] :
      (await db().getAll(...ids.map(tagRef))).filter((doc) => doc.exists && doc.get('status') === 'active');

    if (filter === 'friends') {
      const friendIds = Array.from(await friendIdCandidatesAtCreation(uid))
        .filter((id) => id && id !== uid && !id.includes('/')).slice(0, FRIEND_SCAN_LIMIT);
      const docs = friendIds.length ? await db().getAll(...friendIds.map((id) => db().collection(COL.users).doc(id))) : [];
      const byTag = new Map<string, string[]>();
      docs.filter((doc) => doc.exists && isSearchableUser(doc.id, doc.data())).forEach((doc) => {
        const name = String(doc.get('nickname') || '').trim();
        stringArray(doc.get('interestTagIds')).forEach((tagId) =>
          byTag.set(tagId, [...(byTag.get(tagId) ?? []), name]));
      });
      const top = Array.from(byTag.entries()).sort((a, b) => b[1].length - a[1].length)
        .slice(0, EXPLORE_LIMIT);
      const tags = await activeDocs(top.map(([id]) => id));
      return {items: tags.map((doc) => {
        const names = byTag.get(doc.id) ?? [];
        return toItem(doc, {type: 'friends', friendCount: names.length, friendNames: names.filter(Boolean).slice(0, 2)});
      })};
    }
    if (filter === 'trending') {
      const trending = await db().collection('tags_trending').doc('current').get();
      const items = ((trending.get('items') as Array<{id: string; delta: number}> | undefined) ?? [])
        .slice(0, EXPLORE_LIMIT);
      const tags = await activeDocs(items.map((item) => item.id));
      return {items: tags.map((doc) => toItem(doc, {
        type: 'trending', delta: items.find((item) => item.id === doc.id)?.delta ?? 0,
      }))};
    }
    if (filter === 'newest') {
      const snap = await db().collection(COL.tags).where('status', '==', 'active')
        .orderBy('createdAt', 'desc').limit(EXPLORE_LIMIT).get();
      return {items: snap.docs.map((doc) => toItem(doc, {
        type: 'new', createdAtMillis: (doc.get('createdAt') as Timestamp | undefined)?.toMillis() ?? 0,
      }))};
    }
    // recommended
    if (mine.size === 0) {
      const popular = await popularTags(mine, EXPLORE_LIMIT);
      return {items: popular.map((item) => ({...item, reason: {type: 'popular'}}))};
    }
    const sample = await db().collection(COL.users)
      .where('interestTagIds', 'array-contains-any', Array.from(mine).slice(0, 10))
      .limit(COOCCUR_SAMPLE).get();
    const counts = new Map<string, number>();
    const withTag = new Map<string, Map<string, number>>();
    sample.docs.filter((doc) => doc.id !== uid && isSearchableUser(doc.id, doc.data())).forEach((doc) => {
      const tags = stringArray(doc.get('interestTagIds'));
      const shared = tags.filter((id) => mine.has(id));
      tags.filter((id) => !mine.has(id)).forEach((id) => {
        counts.set(id, (counts.get(id) ?? 0) + 1);
        const pairs = withTag.get(id) ?? new Map<string, number>();
        shared.forEach((own) => pairs.set(own, (pairs.get(own) ?? 0) + 1));
        withTag.set(id, pairs);
      });
    });
    const top = Array.from(counts.entries()).sort((a, b) => b[1] - a[1]).slice(0, EXPLORE_LIMIT);
    const tags = await activeDocs(top.map(([id]) => id));
    return {items: tags.map((doc) => {
      const pairs = Array.from(withTag.get(doc.id)?.entries() ?? []).sort((a, b) => b[1] - a[1]);
      return toItem(doc, {type: 'with', withTag: pairs[0]?.[0] ?? null});
    })};
  });


/** 태그 설명 고치기: 그 태그를 만든 사람만(공식 태그는 운영자가 정한 설명을 쓴다). */
export const updateTagDescription = callables()
  .runWith({timeoutSeconds: 10, memory: '256MB'})
  .https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const tagId = normalizeTagName(data?.tagId);
    if (!tagId) throw new functions.https.HttpsError('invalid-argument', 'tag-invalid');
    const description = normalizeTagDescription(data?.description);
    return db().runTransaction(async (tx) => {
      const tag = await tx.get(tagRef(tagId));
      if (!tag.exists || tag.get('status') !== 'active') {
        throw new functions.https.HttpsError('not-found', 'tag-unavailable');
      }
      if (tag.get('official') === true || tag.get('createdBy') !== uid) {
        throw new functions.https.HttpsError('permission-denied', 'tag-not-owner');
      }
      tx.update(tagRef(tagId), {description, updatedAt: FieldValue.serverTimestamp()});
      return {tagId, description};
    });
  });

// ---- 마이페이지 관심 탭 ----

const OVERVIEW_TAG_LIMIT = 8;
const OVERLAP_SCAN_LIMIT = 200;
const OVERLAP_PAGE = 20;
const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

/** 친구들이 단 태그별 친구 수(많은 순). */
export function countFriendTags(friendTags: ReadonlyArray<readonly string[]>): Array<{id: string; friendHolders: number}> {
  const counts = new Map<string, number>();
  friendTags.forEach((tags) => new Set(tags).forEach((id) => counts.set(id, (counts.get(id) ?? 0) + 1)));
  return Array.from(counts.entries())
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([id, friendHolders]) => ({id, friendHolders}));
}

export type OverlapCandidate = {uid: string; tags: readonly string[]; isFriend: boolean};
export type OverlapScope = 'all' | 'friends' | 'others';

/** 겹침 수 많은 순, 같으면 친구 먼저. scope로 친구/친구 아닌 사람만 고른다. */
export function rankOverlapPeople(
  candidates: readonly OverlapCandidate[],
  myTags: readonly string[],
  scope: OverlapScope,
): Array<OverlapCandidate & {overlapTagIds: string[]}> {
  const mine = new Set(myTags);
  return candidates
    .filter((person) => scope === 'all' || (scope === 'friends') === person.isFriend)
    .map((person) => ({...person, overlapTagIds: myTags.filter((id) => person.tags.includes(id))}))
    .filter((person) => person.overlapTagIds.length > 0 && person.tags.some((id) => mine.has(id)))
    .sort((a, b) => b.overlapTagIds.length - a.overlapTagIds.length ||
      Number(b.isFriend) - Number(a.isFriend) || a.uid.localeCompare(b.uid));
}

async function friendIdList(uid: string): Promise<string[]> {
  return Array.from(await friendIdCandidatesAtCreation(uid))
    .filter((id) => id && id !== uid && !id.includes('/'))
    .slice(0, FRIEND_SCAN_LIMIT);
}

/**
 * 마이페이지 관심 탭을 한 번에 채운다(앱이 10분 캐시).
 * myTags(내 글에 붙인 횟수) / friendOverlap(내 태그를 하나 이상 단 친구 수, 친구들이 단 태그)
 * / community(이번 주 새 태그 수, 많이 단 태그와 이번 주 증가) / suggestions(아직 안 단 추천)
 * / friendFaces(친구 버튼 얼굴 3개) / tags(위에 나온 태그의 공개 정보).
 */
export const getMyInterestOverview = callables()
  .runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (_data, context) => {
    const uid = requireUid(context);
    const me = await db().collection(COL.users).doc(uid).get();
    const myTags = stringArray(me.get('interestTagIds'));
    const mine = new Set(myTags);
    const friendIds = await friendIdList(uid);
    const weekAgo = Timestamp.fromMillis(Date.now() - WEEK_MS);
    const [friendDocs, myPosts, trending, newTags, popular] = await Promise.all([
      friendIds.length ? db().getAll(...friendIds.map((id) => db().collection(COL.users).doc(id))) : Promise.resolve([]),
      db().collection(COL.posts).where('userId', '==', uid).select('tagIds').limit(500).get(),
      db().collection('tags_trending').doc('current').get(),
      // 기존 인덱스(status, createdAt desc)를 쓰도록 같은 정렬을 붙인다.
      db().collection(COL.tags).where('status', '==', 'active').where('createdAt', '>=', weekAgo)
        .orderBy('createdAt', 'desc').count().get(),
      db().collection(COL.tags).where('status', '==', 'active').orderBy('holderCount', 'desc')
        .limit(OVERVIEW_TAG_LIMIT).get(),
    ]);
    const friends = friendDocs.filter((doc) => doc.exists && isSearchableUser(doc.id, doc.data()));
    const friendTagLists = friends.map((doc) => stringArray(doc.get('interestTagIds')));
    const friendTags = countFriendTags(friendTagLists);
    const postCounts = new Map<string, number>();
    myPosts.docs.forEach((doc) => stringArray(doc.get('tagIds'))
      .forEach((id) => postCounts.set(id, (postCounts.get(id) ?? 0) + 1)));
    const weekly = new Map(((trending.get('items') as Array<{id: string; delta: number}> | undefined) ?? [])
      .map((item) => [item.id, Math.max(0, Number(item.delta) || 0)]));
    const suggestions = friendTags.filter((item) => !mine.has(item.id)).slice(0, 2);
    const ids = new Set<string>([
      ...myTags,
      ...friendTags.slice(0, OVERVIEW_TAG_LIMIT).map((item) => item.id),
      ...suggestions.map((item) => item.id),
    ]);
    popular.docs.forEach((doc) => ids.delete(doc.id));
    const extra = ids.size ? await db().getAll(...Array.from(ids).map(tagRef)) : [];
    const tagDocs = [...popular.docs, ...extra].filter((doc) => doc.exists && doc.get('status') === 'active');
    const active = new Set(tagDocs.map((doc) => doc.id));
    // 블록 큰 칸의 얼굴: 태그별 친구 사진 최대 3장.
    const tagFaces: Record<string, string[]> = {};
    friends.forEach((doc) => {
      const photo = String(doc.get('photoURL') || '').trim();
      if (!photo.startsWith('https://')) return;
      stringArray(doc.get('interestTagIds')).forEach((id) => {
        if (!active.has(id)) return;
        const list = tagFaces[id] ?? (tagFaces[id] = []);
        if (list.length < 3) list.push(photo);
      });
    });
    return {
      myTags: myTags.filter((id) => active.has(id))
        .map((id) => ({id, myPostCount: postCounts.get(id) ?? 0})),
      friendOverlap: {
        friendCount: friendTagLists.filter((tags) => tags.some((id) => mine.has(id))).length,
        tags: friendTags.filter((item) => active.has(item.id)).slice(0, OVERVIEW_TAG_LIMIT),
      },
      community: {
        newTagsThisWeek: newTags.data().count,
        tags: popular.docs.filter((doc) => doc.get('status') === 'active').map((doc) => ({
          id: doc.id,
          holderCount: Math.max(0, Number(doc.get('holderCount') ?? 0) || 0),
          weeklyGain: weekly.get(doc.id) ?? 0,
        })),
      },
      suggestions: suggestions.filter((item) => active.has(item.id)),
      friendFaces: friends.map((doc) => String(doc.get('photoURL') || '').trim())
        .filter((url) => url.startsWith('https://')).slice(0, 3),
      tagFaces,
      tags: Object.fromEntries(tagDocs.map((doc) => [doc.id, {id: doc.id, ...pickPublic(doc.data() ?? {})}])),
    };
  });

/**
 * 나와 겹치는 사람: 내 태그(최대 10)를 하나 이상 단 사람, 겹침 많은 순(같으면 친구 먼저), 20명씩.
 * 나·비활성·차단 관계·겹치는 태그를 모두 숨긴 사람은 뺀다. cursor는 다음 시작 순번.
 */
export const getOverlapPeople = callables()
  .runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const scope: OverlapScope = data?.scope === 'friends' || data?.scope === 'others' ? data.scope : 'all';
    const start = Math.max(0, Math.trunc(Number(data?.cursor) || 0));
    const me = await db().collection(COL.users).doc(uid).get();
    const myTags = stringArray(me.get('interestTagIds')).slice(0, 10);
    if (myTags.length === 0) return {people: [], cursor: null, total: 0};
    const [friendIds, snap] = await Promise.all([
      friendIdList(uid),
      db().collection(COL.users).where('interestTagIds', 'array-contains-any', myTags)
        .limit(OVERLAP_SCAN_LIMIT).get(),
    ]);
    const friendSet = new Set(friendIds);
    const docs = new Map(snap.docs
      .filter((doc) => doc.id !== uid && isSearchableUser(doc.id, doc.data()))
      .map((doc) => [doc.id, doc]));
    const ranked = rankOverlapPeople(Array.from(docs.values()).map((doc) => ({
      uid: doc.id, tags: stringArray(doc.get('interestTagIds')), isFriend: friendSet.has(doc.id),
    })), myTags, scope);
    // 차단·숨김은 보여 줄 만큼만 확인한다.
    const people: Array<Record<string, unknown>> = [];
    let index = start;
    while (people.length < OVERLAP_PAGE && index < ranked.length) {
      const batch = ranked.slice(index, index + 30);
      const related = await db().getAll(...batch.flatMap((person) => [
        db().collection(COL.blocks).doc(`${uid}_${person.uid}`),
        db().collection(COL.blocks).doc(`${person.uid}_${uid}`),
        db().collection(COL.usersPrivate).doc(person.uid),
      ]));
      for (let i = 0; i < batch.length && people.length < OVERLAP_PAGE; i++) {
        index++;
        const person = batch[i];
        if (related[i * 3]?.exists || related[i * 3 + 1]?.exists) continue;
        const visible = person.overlapTagIds.filter((tagId) =>
          related[i * 3 + 2]?.get(`tagPrefs.${tagId}.hidden`) !== true);
        if (visible.length === 0) continue;
        const profile = docs.get(person.uid)?.data() ?? {};
        people.push({
          uid: person.uid,
          name: String(profile.nickname || '').trim(),
          photoURL: String(profile.photoURL || '').trim(),
          school: String(profile.university || '').trim(),
          country: String(profile.nationality || '').trim(),
          isFriend: person.isFriend,
          overlapTagIds: visible,
        });
      }
    }
    return {people, cursor: index < ranked.length ? String(index) : null, total: ranked.length};
  });
