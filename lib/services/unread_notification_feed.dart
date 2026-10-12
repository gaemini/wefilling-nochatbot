import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/logger.dart';
import 'active_content_registry.dart';
import 'fcm_service.dart';
import 'notification_service.dart';

/// While at least one destination is registered in [ActiveContentRegistry],
/// keeps one listener on the signed-in user's unread notifications and marks
/// read every document an active scope covers (then removes its OS card and
/// refreshes the badge through the existing confirmed-read path).
///
/// This closes the gap where a like or comment notification arrives while the
/// post or comment is already on screen: the one-shot read at load and the
/// once-per-generation visibility observer never re-arm, and the pushless or
/// multi-device case had no trigger at all. Scopes are always target-bound, so
/// nothing outside the visible content is affected.
class UnreadNotificationFeed {
  UnreadNotificationFeed._() {
    ActiveContentRegistry.revision.addListener(_onScopesChanged);
  }

  static final UnreadNotificationFeed instance = UnreadNotificationFeed._();

  /// Creates the singleton so it starts observing scope changes.
  static void ensureStarted() => instance;

  static const int _queryLimit = 200;
  static const Duration _idleStopDelay = Duration(seconds: 2);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  String? _owner;
  int? _session;
  Timer? _stopTimer;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latest =
      const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  final Set<String> _inFlightIds = <String>{};

  void _onScopesChanged() {
    if (!ActiveContentRegistry.enabled) return;
    if (ActiveContentRegistry.hasScopes) {
      _stopTimer?.cancel();
      _stopTimer = null;
      _start();
      // A newly visible destination may cover notifications that arrived
      // before it was registered.
      _evaluate(_latest);
      return;
    }
    // Brief grace so a push between two screens does not churn the listener.
    _stopTimer?.cancel();
    _stopTimer = Timer(_idleStopDelay, () {
      if (!ActiveContentRegistry.hasScopes) stop();
    });
  }

  void _start() {
    final owner = FirebaseAuth.instance.currentUser?.uid;
    if (owner == null || owner.isEmpty) return;
    final session = FCMService().notificationSession;
    if (_subscription != null && _owner == owner && _session == session) {
      return;
    }
    stop();
    _owner = owner;
    _session = session;
    _subscription = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: owner)
        .where('isRead', isEqualTo: false)
        .limit(_queryLimit)
        .snapshots()
        .listen(_onSnapshot, onError: (Object error) {
      Logger.error('활성 콘텐츠 미읽음 알림 구독 오류', error);
    });
  }

  void stop() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _owner = null;
    _session = null;
    _latest = const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    _inFlightIds.clear();
  }

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    // Only server-confirmed documents: a cache-only entry may already be
    // deleted on the server and a batch update on it would fail outright.
    if (snapshot.metadata.isFromCache) return;
    _latest = snapshot.docs;
    _evaluate(snapshot.docs);
  }

  void _evaluate(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final owner = _owner;
    final session = _session;
    if (owner == null || session == null || docs.isEmpty) return;
    if (FirebaseAuth.instance.currentUser?.uid != owner ||
        !FCMService().isNotificationSession(owner, session)) {
      stop();
      return;
    }
    final matches = docs.where((doc) {
      if (_inFlightIds.contains(doc.id)) return false;
      final data = doc.data();
      if (data['isRead'] == true) return false;
      return ActiveContentRegistry.matches(data, owner: owner);
    }).toList(growable: false);
    if (matches.isEmpty) return;
    final ids = matches.map((doc) => doc.id).toSet();
    _inFlightIds.addAll(ids);
    unawaited(NotificationService()
        .markNotificationDocumentsAsRead(matches, owner: owner, session: session)
        .catchError((Object error) {
      Logger.error('활성 콘텐츠 알림 자동 읽음 실패', error);
      return 0;
    }).whenComplete(() => _inFlightIds.removeAll(ids)));
  }
}
