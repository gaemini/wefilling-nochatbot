/// Both legacy top-level and current nested targets are supported, but all
/// requested target dimensions must match. Names/text are never identities.
bool matchesNotificationReadScope(
  Map<String, dynamic> notification, {
  required String owner,
  required Set<String> types,
  required Map<String, String> targets,
}) {
  if (notification['userId'] != owner ||
      (types.isNotEmpty && !types.contains(notification['type']))) return false;
  if (targets.isEmpty) return false;
  final nested =
      notification['data'] is Map ? notification['data'] as Map : const {};
  return targets.entries.every((entry) {
    final top = notification[entry.key]?.toString() ?? '';
    final canonical = top.isNotEmpty ? top : nested[entry.key]?.toString();
    return entry.value.isNotEmpty && canonical == entry.value;
  });
}

bool reminderTargetsWereSeen(Iterable<String> targets, Set<String> seen) =>
    targets.isNotEmpty && targets.every(seen.contains);

bool notificationPayloadWasConfirmedRead(
    Map<String, dynamic> payload, Map<String, dynamic> receipt, String owner) {
  if (owner.isEmpty || receipt['ownerUserId'] != owner) return false;
  final publicAd = receipt['kind'] == 'ad' &&
      payload['type'] == 'ad_updates' &&
      payload['audience'] == 'public';
  if (payload['recipientUserId'] != owner && !publicAd) return false;
  int number(Map<String, dynamic> value, String key) =>
      int.tryParse('${value[key] ?? ''}') ?? 0;
  final id = payload['notificationId'];
  if (receipt['kind'] == 'app' || publicAd) {
    return id is String && id.isNotEmpty && id == receipt['notificationId'];
  }
  if (receipt['kind'] == 'snack_chat' &&
      payload['type'] == 'snack_chat_message' &&
      payload['snackChatId'] == receipt['roomId']) {
    final sequence = number(payload, 'messageSequence');
    return sequence > 0 && sequence <= number(receipt, 'throughSequence');
  }
  if (receipt['kind'] == 'dm' &&
      payload['type'] == 'dm_received' &&
      payload['conversationId'] == receipt['roomId']) {
    final seconds = number(payload, 'sentAtSeconds');
    final throughSeconds = number(receipt, 'throughSeconds');
    final nanos = int.tryParse('${payload['sentAtNanos'] ?? ''}');
    final throughNanos = int.tryParse('${receipt['throughNanos'] ?? ''}');
    if (seconds > 0 &&
        throughSeconds > 0 &&
        nanos != null &&
        throughNanos != null &&
        nanos >= 0 &&
        nanos < 1000000000 &&
        throughNanos >= 0 &&
        throughNanos < 1000000000) {
      return seconds < throughSeconds ||
          (seconds == throughSeconds && nanos <= throughNanos);
    }
    final millis = number(payload, 'sentAtMillis');
    return millis > 0 && millis <= number(receipt, 'throughSentAtMillis');
  }
  return false;
}
