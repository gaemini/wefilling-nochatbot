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
