import 'package:flutter/foundation.dart';

import '../utils/notification_read_policy.dart';

/// One destination currently on screen, described by the same `types` and
/// `targets` vocabulary as `NotificationService.markRelatedNotificationsAsRead`.
@immutable
class ActiveContentScope {
  const ActiveContentScope({required this.types, required this.targets});

  final Set<String> types;
  final Map<String, String> targets;

  bool get isEmpty => types.isEmpty || targets.isEmpty;

  /// A notification document or push payload that this scope covers.
  bool matches(Map<String, dynamic> notification, {required String owner}) =>
      !isEmpty &&
      matchesNotificationReadScope(
        notification,
        owner: owner,
        types: types,
        targets: targets,
      );
}

/// Registry of destinations the user is looking at right now (post, meetup,
/// friend request, snap, visible comment ...). Generalizes the chat-only
/// `DMActiveConversation` / `SnackChatActiveConversation` registries.
///
/// Consumers:
/// * the foreground FCM handler suppresses the local banner for a push whose
///   destination is already on screen and marks that notification read;
/// * [UnreadNotificationFeed] marks unread notifications read as soon as they
///   match an active scope, closing the gap where a like or comment arrives
///   while the post is already open (the one-shot read at load and the
///   once-per-generation observer never re-arm).
///
/// Scopes are always target-bound, so nothing outside the visible content is
/// ever marked read. Disabled builds register nothing and behave as before.
class ActiveContentRegistry {
  ActiveContentRegistry._();

  // Default ON since 1.3.24: viewing content marks its notifications read.
  // `--dart-define=ACTIVE_CONTENT_AUTO_READ=false` is the kill switch.
  static const bool enabled = bool.fromEnvironment(
    'ACTIVE_CONTENT_AUTO_READ',
    defaultValue: true,
  );

  static final Map<Object, ActiveContentScope> _scopes = <Object, ActiveContentScope>{};
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool get hasScopes => _scopes.isNotEmpty;

  static List<ActiveContentScope> get scopes =>
      List<ActiveContentScope>.unmodifiable(_scopes.values);

  /// Registers (or replaces) the scope owned by [token] — typically a State.
  /// Empty scopes are ignored so observer-only widgets register nothing.
  static void register(
    Object token, {
    required Set<String> types,
    required Map<String, String> targets,
  }) {
    if (!enabled) return;
    final normalized = <String, String>{
      for (final entry in targets.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
    final scope = ActiveContentScope(
      types: Set<String>.unmodifiable(types),
      targets: Map<String, String>.unmodifiable(normalized),
    );
    if (scope.isEmpty) {
      unregister(token);
      return;
    }
    final previous = _scopes[token];
    if (previous != null &&
        setEquals(previous.types, scope.types) &&
        mapEquals(previous.targets, scope.targets)) {
      return;
    }
    _scopes[token] = scope;
    revision.value++;
  }

  static void unregister(Object token) {
    if (_scopes.remove(token) != null) revision.value++;
  }

  /// Whether any active scope covers [notification] for [owner]. Works for
  /// Firestore notification documents and for FCM data payloads, both of
  /// which carry `type` plus top-level target ids.
  static bool matches(Map<String, dynamic> notification, {required String owner}) {
    if (!enabled || owner.isEmpty || _scopes.isEmpty) return false;
    for (final scope in _scopes.values) {
      if (scope.matches(notification, owner: owner)) return true;
    }
    return false;
  }

  /// FCM data payloads name the recipient as `recipientUserId`; notification
  /// documents use `userId`. Normalizes a payload for [matches].
  static Map<String, dynamic> payloadAsNotification(Map<String, dynamic> data) {
    final recipient = (data['recipientUserId'] ?? '').toString();
    return <String, dynamic>{...data, 'userId': recipient};
  }

  @visibleForTesting
  static void resetForTesting() {
    _scopes.clear();
    revision.value++;
  }
}
