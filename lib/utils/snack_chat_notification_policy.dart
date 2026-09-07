import 'dart:convert';

import 'package:crypto/crypto.dart';

const int snackChatAndroidFcmNotificationId = 0;
const String snackChatAndroidGroupKey = 'wefilling_snack_chat_messages';
const Duration snackChatNotificationBurstWindow = Duration(seconds: 4);

/// Mirrors the server-issued Android notification tag exactly. Keeping this
/// derivation on the client lets an in-app room open remove its own remote
/// notification even when the background isolate did not persist the tag.
String snackChatNotificationGroupKey({
  required String recipientUserId,
  required String snackChatId,
}) {
  final digest = sha256.convert(
    utf8.encode('${recipientUserId.trim()}:${snackChatId.trim()}'),
  );
  return 'snack_${digest.toString().substring(0, 40)}';
}

int stableSnackChatNotificationId(String value) {
  var hash = 0x811C9DC5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7FFFFFFF;
  }
  return hash;
}

class SnackChatNotificationDecision {
  const SnackChatNotificationDecision({
    required this.shouldDisplay,
    required this.shouldAlert,
  });

  final bool shouldDisplay;
  final bool shouldAlert;
}

/// Keeps foreground Snack Chat notification updates ordered and quiet during a
/// short same-room burst. The state is deliberately process-local: background
/// and terminated notification delivery remains owned by FCM/Android.
class SnackChatNotificationBurstGate {
  SnackChatNotificationBurstGate({
    this.burstWindow = snackChatNotificationBurstWindow,
  });

  final Duration burstWindow;
  final Map<String, int> _latestSentAtByRoom = <String, int>{};
  final Map<String, DateTime> _lastAlertAtByRoom = <String, DateTime>{};
  final Map<String, DateTime> _seenEventAt = <String, DateTime>{};

  SnackChatNotificationDecision evaluate({
    required String roomKey,
    required String eventId,
    required int sentAtMillis,
    DateTime? now,
  }) {
    final evaluatedAt = now ?? DateTime.now();
    _prune(evaluatedAt);

    final normalizedEventId = eventId.trim();
    final eventKey =
        normalizedEventId.isEmpty ? '' : '$roomKey:$normalizedEventId';
    if (eventKey.isNotEmpty && _seenEventAt.containsKey(eventKey)) {
      return const SnackChatNotificationDecision(
        shouldDisplay: false,
        shouldAlert: false,
      );
    }

    final latestSentAt = _latestSentAtByRoom[roomKey];
    if (sentAtMillis > 0 &&
        latestSentAt != null &&
        sentAtMillis < latestSentAt) {
      if (eventKey.isNotEmpty) {
        _seenEventAt[eventKey] = evaluatedAt;
      }
      return const SnackChatNotificationDecision(
        shouldDisplay: false,
        shouldAlert: false,
      );
    }

    if (eventKey.isNotEmpty) {
      _seenEventAt[eventKey] = evaluatedAt;
    }
    if (sentAtMillis > 0) {
      _latestSentAtByRoom[roomKey] = sentAtMillis;
    }

    final lastAlertAt = _lastAlertAtByRoom[roomKey];
    final shouldAlert = lastAlertAt == null ||
        evaluatedAt.difference(lastAlertAt) >= burstWindow;
    if (shouldAlert) _lastAlertAtByRoom[roomKey] = evaluatedAt;

    return SnackChatNotificationDecision(
      shouldDisplay: true,
      shouldAlert: shouldAlert,
    );
  }

  void clearRoom(String roomKey) {
    _latestSentAtByRoom.remove(roomKey);
    _lastAlertAtByRoom.remove(roomKey);
  }

  void clear() {
    _latestSentAtByRoom.clear();
    _lastAlertAtByRoom.clear();
    _seenEventAt.clear();
  }

  void _prune(DateTime now) {
    if (_seenEventAt.length < 256) return;
    final cutoff = now.subtract(const Duration(minutes: 10));
    _seenEventAt.removeWhere((_, seenAt) => seenAt.isBefore(cutoff));
  }
}
