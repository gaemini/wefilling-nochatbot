/**
 * Firestore 컬렉션/문서ID 규약을 서버(Cloud Functions)에서 중앙 관리합니다.
 *
 * 목적:
 * - 컬렉션 이름 문자열 오타 방지
 * - 문서ID 규칙(정렬/정규화) 일관성 유지
 */

export const COL = {
  // Auth / Verification
  users: 'users',
  emailClaims: 'email_claims',
  emailVerifications: 'email_verifications',

  // Content
  posts: 'posts',
  comments: 'comments',
  meetups: 'meetups',

  // DM / Notifications
  conversations: 'conversations',
  messages: 'messages',
  notifications: 'notifications',

  // Friends / Relationship
  friendRequests: 'friend_requests',
  friendships: 'friendships',
  blocks: 'blocks',
  relationships: 'relationships',
  friendCategories: 'friend_categories',

  // Reviews
  meetupReviews: 'meetup_reviews',
  reviewRequests: 'review_requests',
  reviews: 'reviews',
  meetupParticipants: 'meetup_participants',
  meetings: 'meetings',
  pendingReviews: 'pendingReviews',

  // Settings / Admin
  userSettings: 'user_settings',
  adminSettings: 'admin_settings',
  adBanners: 'ad_banners',
  recommendedPlaces: 'recommended_places',
  reports: 'reports',
} as const;

export function normalizeEmailDocId(email: string): string {
  return String(email).trim().toLowerCase();
}

function sorted2(a: string, b: string): [string, string] {
  return a <= b ? [a, b] : [b, a];
}

export const DocId = {
  emailClaim(email: string) {
    return normalizeEmailDocId(email);
  },
  emailVerification(email: string) {
    return normalizeEmailDocId(email);
  },
  friendshipPair(uidA: string, uidB: string) {
    const [a, b] = sorted2(uidA, uidB);
    return `${a}__${b}`;
  },
  conversation(uidA: string, uidB: string) {
    const [a, b] = sorted2(uidA, uidB);
    return `${a}_${b}`;
  },
  anonymousConversation(uidA: string, uidB: string, postId: string) {
    const [a, b] = sorted2(uidA, uidB);
    return `anon_${a}_${b}_${postId}`;
  },
  friendRequest(fromUid: string, toUid: string) {
    return `${fromUid}_${toUid}`;
  },
  block(blockerUid: string, blockedUid: string) {
    return `${blockerUid}_${blockedUid}`;
  },
} as const;

