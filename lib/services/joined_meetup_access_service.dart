import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/logger.dart';

/// Shares the server-validated set of readable joined meetup IDs across the
/// calendar and My Page. A short cache and one in-flight request per ID set
/// prevent duplicate callable requests when both screens subscribe together.
class JoinedMeetupAccessService {
  JoinedMeetupAccessService._();

  static final JoinedMeetupAccessService instance =
      JoinedMeetupAccessService._();

  static const Duration _cacheLifetime = Duration(seconds: 20);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  String? _cachedKey;
  Set<String>? _cachedIds;
  DateTime? _cachedAt;
  String? _inFlightKey;
  Future<Set<String>>? _inFlight;

  Future<Set<String>> resolveReadableIds(
    Iterable<String> participantMeetupIds, {
    bool forceRefresh = false,
  }) async {
    final userId = _auth.currentUser?.uid;
    final requestedIds = participantMeetupIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (userId == null || requestedIds.isEmpty) return <String>{};

    final sortedIds = requestedIds.toList(growable: false)..sort();
    final key = '$userId:${sortedIds.join(',')}';
    final cachedAt = _cachedAt;
    if (!forceRefresh &&
        _cachedKey == key &&
        _cachedIds != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheLifetime) {
      return Set<String>.of(_cachedIds!);
    }
    if (!forceRefresh && _inFlightKey == key && _inFlight != null) {
      return Set<String>.of(await _inFlight!);
    }

    final request = _resolveFromServer(
      key: key,
      requestedIds: requestedIds,
    );
    _inFlightKey = key;
    _inFlight = request;
    try {
      return Set<String>.of(await request);
    } finally {
      if (identical(_inFlight, request)) {
        _inFlight = null;
        _inFlightKey = null;
      }
    }
  }

  Future<Set<String>> _resolveFromServer({
    required String key,
    required Set<String> requestedIds,
  }) async {
    try {
      final response = await _functions
          .httpsCallable('resolveMyReadableJoinedMeetupIds')
          .call<Map<String, dynamic>>(const <String, dynamic>{}).timeout(
              const Duration(seconds: 12));
      final rawIds = response.data['meetupIds'];
      final readableIds = rawIds is List
          ? rawIds
              .map((id) => id.toString().trim())
              .where(requestedIds.contains)
              .toSet()
          : <String>{};
      _cachedKey = key;
      _cachedIds = Set<String>.unmodifiable(readableIds);
      _cachedAt = DateTime.now();
      return readableIds;
    } catch (error) {
      // Availability fallback: a temporary Functions outage must not make the
      // user's existing joined-meetup list disappear. The old direct-read path
      // remains available until the next successful validation.
      if (Logger.isVerboseEnabled) {
        Logger.warning('참여 모임 접근 목록 서버 확인 실패, 기존 경로 사용: $error');
      }
      return Set<String>.of(requestedIds);
    }
  }

  void invalidate() {
    _cachedKey = null;
    _cachedIds = null;
    _cachedAt = null;
  }
}
