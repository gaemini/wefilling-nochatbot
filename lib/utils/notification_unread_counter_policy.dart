const int notificationUnreadCounterVersion = 1;

// A negative version means the server intentionally kept the document-query
// fallback because the account currently has a block relationship. Existing
// unread notifications must remain dynamically hidden/shown by that policy.
const int notificationUnreadCounterDocumentFallbackVersion = -1;

int? trustedNotificationUnreadTotal(Map<String, dynamic>? userData) {
  if (userData == null) return null;
  final rawVersion = userData['notificationUnreadCounterVersion'];
  final rawTotal = userData['notificationUnreadTotal'];
  if (rawVersion is! num ||
      rawVersion.toInt() != notificationUnreadCounterVersion ||
      rawTotal is! num ||
      !rawTotal.isFinite ||
      rawTotal < 0) {
    return null;
  }
  return rawTotal.toInt();
}

bool notificationUnreadCounterNeedsReconciliation(
  Map<String, dynamic>? userData,
) {
  final rawVersion = userData?['notificationUnreadCounterVersion'];
  if (rawVersion is num &&
      rawVersion.toInt() == notificationUnreadCounterDocumentFallbackVersion) {
    return false;
  }
  return trustedNotificationUnreadTotal(userData) == null;
}

/// 계정 전환 경계에서 이전 세션의 비동기 badge 결과를 적용할지 판정한다.
///
/// [activeUserId]가 아직 없는 push 직접 진입은 허용하지만, logout으로
/// 무효화된 사용자와 이전 generation의 작업은 항상 거부한다.
bool isBadgeAccountContextCurrent({
  required String? authenticatedUserId,
  required String? activeUserId,
  required String? invalidatedUserId,
  required int currentGeneration,
  required String expectedUserId,
  required int expectedGeneration,
}) {
  return currentGeneration == expectedGeneration &&
      authenticatedUserId == expectedUserId &&
      invalidatedUserId != expectedUserId &&
      (activeUserId == null || activeUserId == expectedUserId);
}
