/// Firestore 컬렉션/문서ID 규약을 중앙에서 관리하기 위한 상수/헬퍼 모음입니다.
///
/// 목표:
/// - 컬렉션명 오타 방지
/// - 문서 ID 규약(정렬/정규화) 일관성 유지
/// - 리팩토링 시 문자열 수정 범위를 최소화
class FirestoreCollections {
  // Auth / Verification
  static const String users = 'users';
  static const String emailClaims = 'email_claims'; // server-only
  static const String emailVerifications = 'email_verifications'; // server-only

  // Content
  static const String posts = 'posts';
  static const String comments = 'comments';
  static const String meetups = 'meetups';

  // DM / Notifications
  static const String conversations = 'conversations';
  static const String messages = 'messages';
  static const String notifications = 'notifications';

  // Friends / Relationship
  static const String friendRequests = 'friend_requests';
  static const String friendships = 'friendships';
  static const String blocks = 'blocks';
  static const String relationships = 'relationships';
  static const String friendCategories = 'friend_categories';

  // Reviews
  static const String meetupReviews = 'meetup_reviews';
  static const String reviewRequests = 'review_requests';
  static const String reviews = 'reviews';
  static const String meetupParticipants = 'meetup_participants';
  static const String meetings = 'meetings'; // used for consensus feature
  static const String pendingReviews = 'pendingReviews';

  // Settings / Admin
  static const String userSettings = 'user_settings';
  static const String adminSettings = 'admin_settings';
  static const String adBanners = 'ad_banners';
  static const String recommendedPlaces = 'recommended_places';
  static const String reports = 'reports';

  // User subcollections
  static const String userSavedPosts = 'savedPosts';
  static const String userPosts = 'posts';
  static const String userConversations = 'conversations';

  // Post subcollections
  static const String postPollVotes = 'pollVotes';
}

class FirestoreDocIds {
  /// 이메일을 docId로 쓸 때의 표준: trim + lowercase
  static String normalizeEmail(String email) => email.trim().toLowerCase();

  /// `{uid1}__{uid2}` (사전순 정렬)
  static String friendshipPairId(String uidA, String uidB) =>
      _sorted2(uidA, uidB).join('__');

  /// `{uid1}_{uid2}` (사전순 정렬)
  static String conversationId(String uidA, String uidB) =>
      _sorted2(uidA, uidB).join('_');

  /// `anon_{uid1}_{uid2}_{postId}` (uid는 사전순 정렬 권장)
  static String anonymousConversationId(String uidA, String uidB, String postId) {
    final sorted = _sorted2(uidA, uidB);
    return 'anon_${sorted[0]}_${sorted[1]}_$postId';
  }

  /// `{fromUid}_{toUid}`
  static String friendRequestId(String fromUid, String toUid) => '${fromUid}_$toUid';

  /// `{blockerUid}_{blockedUid}`
  static String blockId(String blockerUid, String blockedUid) =>
      '${blockerUid}_$blockedUid';

  static List<String> _sorted2(String a, String b) => (a.compareTo(b) <= 0) ? [a, b] : [b, a];
}

