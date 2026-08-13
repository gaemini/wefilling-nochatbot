import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_notification.dart';
import 'content_filter_service.dart';
import 'snack_chat_active_conversation.dart';
import '../utils/logger.dart';
import '../utils/snack_chat_list_policy.dart';

/// iOS/Android 앱 아이콘 배지 동기화 서비스 (이벤트 기반)
///
/// 정책: "배지 숫자 = 읽지 않은 알림 개수 + 안 읽은 DM 수 + 안 읽은 스냅챗 수"
class BadgeService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _userDocSubscription;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _notificationsSubscription;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _snackChatsSubscription;

  static String? _activeUserId;
  static int _sessionGeneration = 0;
  static int? _currentBadgeCount;

  static Timer? _updateDebounceTimer;
  static Timer? _snackChatExpirationTimer;
  static DocumentSnapshot<Map<String, dynamic>>? _latestUserSnapshot;
  static QuerySnapshot<Map<String, dynamic>>? _latestNotificationsSnapshot;
  static QuerySnapshot<Map<String, dynamic>>? _latestSnackChatSnapshot;
  static Future<void>? _badgeUpdateInFlight;
  static bool _badgeUpdateRequested = false;
  static String? _pendingBadgeUserId;
  static int? _pendingBadgeGeneration;
  static int _debugBadgeUpdateLogs = 0;

  static const Duration _dmRecountInterval = Duration(hours: 12);
  static const String _dmRecountPreferencePrefix = 'badge_dm_recount_v2__';

  /// 실시간 배지 리스너 시작
  static Future<void> startRealtimeBadgeSync() async {
    // Account switches must invalidate every callback and in-flight recount
    // from the previous user before the new session starts.
    await stopRealtimeBadgeSync();

    final user = _auth.currentUser;
    if (user == null) {
      await _setBadge(0);
      _currentBadgeCount = 0;
      return;
    }

    final userId = user.uid;
    final generation = _sessionGeneration;
    _activeUserId = userId;

    // Never display the previous account's cached value while the new
    // account is being recounted.
    await _setBadge(0);
    _currentBadgeCount = 0;

    if (!(Platform.isIOS || Platform.isAndroid)) return;

    final supported = await AppBadgePlus.isSupported();
    if (!supported || !_isActiveSession(userId, generation)) return;

    try {
      // 서버 카운터 동기화 (앱 시작 시 1회)
      await _syncServerCounters(userId);
      if (!_isActiveSession(userId, generation)) return;

      // 즉시 정확한 배지로 초기화
      await _updateBadge(
        expectedUserId: userId,
        expectedGeneration: generation,
      );
      if (!_isActiveSession(userId, generation)) return;

      // 1) users 문서 리스닝 (dmUnreadTotal 변경 감지)
      _userDocSubscription =
          _firestore.collection('users').doc(userId).snapshots().listen(
        (snapshot) {
          _latestUserSnapshot = snapshot;
          _onDataChanged(userId, generation);
        },
        onError: (e) => Logger.error('users 문서 리스닝 실패', e),
      );

      // 2) 알림 컬렉션 리스닝 (안 읽은 알림 변경 감지)
      _notificationsSubscription = _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .snapshots()
          .listen(
        (snapshot) {
          _latestNotificationsSnapshot = snapshot;
          _onDataChanged(userId, generation);
        },
        onError: (e) => Logger.error('알림 컬렉션 리스닝 실패', e),
      );

      // 3) snack_chats 컬렉션 리스닝 (SC 미읽음 변경 감지)
      _snackChatsSubscription = _firestore
          .collection('snack_chats')
          .where('participantIds', arrayContains: userId)
          .snapshots()
          .listen(
            (snapshot) => _onSnackChatsChanged(snapshot, userId, generation),
            onError: (e) => Logger.error('snack_chats 리스닝 실패', e),
          );
    } catch (e) {
      Logger.error('실시간 배지 동기화 시작 실패', e);
      if (_isActiveSession(userId, generation)) {
        await _setBadge(0);
        _currentBadgeCount = 0;
      }
    }
  }

  static bool _isActiveSession(String userId, int generation) {
    return _sessionGeneration == generation &&
        _activeUserId == userId &&
        _auth.currentUser?.uid == userId;
  }

  /// 서버 카운터를 실제 값으로 동기화 (앱 시작 시 1회)
  static Future<void> _syncServerCounters(String userId) async {
    // 최대 3번 재시도
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final userRef = _firestore.collection('users').doc(userId);
        final results = await Future.wait<Object>([
          _getVisibleUnreadNotificationCount(userId: userId),
          userRef.get().timeout(const Duration(seconds: 5)),
        ]);
        final actualNotificationCount = results[0] as int;
        final userSnapshot =
            results[1] as DocumentSnapshot<Map<String, dynamic>>;
        if (!userSnapshot.exists) {
          throw StateError('배지 카운터를 동기화할 사용자 문서가 없습니다.');
        }

        final rawDmTotal = userSnapshot.data()?['dmUnreadTotal'];
        final storedDmTotal =
            rawDmTotal is num && rawDmTotal >= 0 ? rawDmTotal.toInt() : null;
        final preferences = await SharedPreferences.getInstance();
        final recountKey = '$_dmRecountPreferencePrefix$userId';
        final lastRecountMillis = preferences.getInt(recountKey);
        final isRecentRecount = lastRecountMillis != null &&
            DateTime.now().difference(
                  DateTime.fromMillisecondsSinceEpoch(lastRecountMillis),
                ) <
                _dmRecountInterval;
        final shouldRecountDm = storedDmTotal == null || !isRecentRecount;
        final actualDmUnreadCount = shouldRecountDm
            ? await _recountAndRepairDmUnread(userId: userId)
            : storedDmTotal;

        // users 문서의 카운터를 실제 값으로 업데이트
        // ⚠️ merge set은 문서를 "부분 필드만 가진 상태로 생성"할 수 있으므로 update만 허용한다.
        await userRef.update({
          'notificationUnreadTotal': actualNotificationCount,
          'dmUnreadTotal': actualDmUnreadCount,
        });
        if (shouldRecountDm) {
          await preferences.setInt(
            recountKey,
            DateTime.now().millisecondsSinceEpoch,
          );
        }

        Logger.log(
            '✅ 서버 카운터 동기화 완료: 알림=$actualNotificationCount, DM=$actualDmUnreadCount');
        return; // 성공하면 즉시 리턴
      } catch (e) {
        Logger.error('서버 카운터 동기화 실패 (시도 ${attempt + 1}/3)', e);

        // 마지막 시도가 아니면 재시도
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }

        // 일시적인 네트워크/권한 실패를 "미읽음 0개"로 해석하면 실제
        // 카운터를 잃는다. 마지막 정상 값을 유지하고 다음 기회에 재시도한다.
        Logger.error('❌ 서버 카운터 동기화 최종 실패 - 기존 값 유지', e);
      }
    }
  }

  /// DM unread를 실제 메시지(isRead=false)로 재계산하고, conversations.unreadCount[userId]도 함께 복구한다.
  ///
  /// 왜 필요한가?
  /// - 과거 버그/중복 participants/경쟁 조건으로 `conversations.unreadCount` 또는 `users.dmUnreadTotal`이 드리프트하면
  ///   앱 아이콘 배지가 "0이 아닌 값"으로 고정될 수 있다.
  /// - 앱 시작 시 1회 "진짜 값"으로 되돌려 배지/카운터를 안정화한다.
  static Future<int> _recountAndRepairDmUnread({required String userId}) async {
    // conversations 스캔 (타임아웃 포함)
    final convSnap = await _firestore
        .collection('conversations')
        .where('participants', arrayContains: userId)
        .get()
        .timeout(const Duration(seconds: 15));

    bool shouldInclude(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      try {
        final data = doc.data();
        final archivedBy = List<String>.from(data['archivedBy'] ?? []);
        if (archivedBy.contains(userId)) return false;

        final userLeftAt = (data['userLeftAt'] as Map?) ?? const {};
        final lastMessageTime = data['lastMessageTime'];
        if (userLeftAt[userId] is Timestamp && lastMessageTime is Timestamp) {
          final left = (userLeftAt[userId] as Timestamp).toDate();
          if (!lastMessageTime.toDate().isAfter(left)) return false;
        }

        final participants = (data['participants'] as List?)
                ?.map((e) => e.toString())
                .where((s) => s.isNotEmpty)
                .toSet() ??
            <String>{};
        if (doc.id.startsWith('anon_') && participants.isNotEmpty) {
          final others = participants.where((id) => id != userId).toSet();
          if (others.isNotEmpty &&
              others.every((otherId) => userLeftAt[otherId] != null)) {
            return false;
          }
        }

        final unreadMap = (data['unreadCount'] as Map?) ?? const {};
        final rawClaimed = unreadMap[userId];
        final claimed = rawClaimed is num ? rawClaimed.toInt() : 0;
        // 기존 정책처럼 0인 방은 스캔하지 않는다. 실시간 트리거가 0을
        // 단일 진실로 유지하고, 과거 양수/음수 드리프트만 복구한다.
        return claimed != 0;
      } catch (_) {
        return false;
      }
    }

    Future<
        ({
          DocumentReference<Map<String, dynamic>> reference,
          String id,
          int claimed,
          int actual,
        })> recountRoom(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
      final unreadMap = (doc.data()['unreadCount'] as Map?) ?? const {};
      final rawClaimed = unreadMap[userId];
      final claimed = rawClaimed is num ? rawClaimed.toInt() : 0;
      int actual = 0;
      DocumentSnapshot<Map<String, dynamic>>? cursor;

      while (true) {
        Query<Map<String, dynamic>> query = doc.reference
            .collection('messages')
            .where('isRead', isEqualTo: false)
            .orderBy(FieldPath.documentId)
            .limit(400);
        if (cursor != null) query = query.startAfterDocument(cursor);
        final page = await query.get().timeout(const Duration(seconds: 10));
        for (final message in page.docs) {
          final senderId = (message.data()['senderId'] ?? '').toString();
          if (senderId.isNotEmpty && senderId != userId) actual++;
        }
        if (page.docs.length < 400) break;
        cursor = page.docs.last;
      }

      return (
        reference: doc.reference,
        id: doc.id,
        claimed: claimed,
        actual: actual,
      );
    }

    final eligible = convSnap.docs.where(shouldInclude).toList(growable: false);
    final results = <({
      DocumentReference<Map<String, dynamic>> reference,
      String id,
      int claimed,
      int actual,
    })>[];
    // 방이 많은 계정에서도 직렬 N+1 지연을 만들지 않되, 모바일
    // 네트워크와 Firestore에 순간 부하가 몰리지 않도록 동시성을 제한한다.
    for (var i = 0; i < eligible.length; i += 6) {
      final end = (i + 6).clamp(0, eligible.length);
      results.addAll(
        await Future.wait(eligible.sublist(i, end).map(recountRoom)),
      );
    }

    var total = 0;
    final repairs = <Future<void>>[];
    for (final result in results) {
      total += result.actual;
      if (result.actual == result.claimed) continue;
      repairs.add(result.reference.set({
        'unreadCount': {userId: result.actual},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));
      Logger.log(
          '🔧 [BadgeService] unreadCount 복구: ${result.id} claimed=${result.claimed} → actual=${result.actual}');
    }

    // repairs는 best-effort 병렬 처리 (과도 동시성 방지: 10개씩)
    for (var i = 0; i < repairs.length; i += 10) {
      final batch = repairs.sublist(i, (i + 10).clamp(0, repairs.length));
      await Future.wait(batch);
    }

    return total < 0 ? 0 : total;
  }

  /// 실시간 배지 리스너 중지
  static Future<void> stopRealtimeBadgeSync() async {
    _sessionGeneration++;
    _activeUserId = null;
    await _userDocSubscription?.cancel();
    await _notificationsSubscription?.cancel();
    await _snackChatsSubscription?.cancel();
    _userDocSubscription = null;
    _notificationsSubscription = null;
    _snackChatsSubscription = null;
    _updateDebounceTimer?.cancel();
    _updateDebounceTimer = null;
    _snackChatExpirationTimer?.cancel();
    _snackChatExpirationTimer = null;
    _latestUserSnapshot = null;
    _latestNotificationsSnapshot = null;
    _latestSnackChatSnapshot = null;
    _badgeUpdateRequested = false;
    _pendingBadgeUserId = null;
    _pendingBadgeGeneration = null;
  }

  /// 로그아웃 시 배지를 즉시 제거한다.
  /// - 이전 계정의 배지 숫자가 다음 세션까지 남지 않도록 강제 초기화
  static Future<void> clearBadgeOnSignOut() async {
    try {
      await stopRealtimeBadgeSync();
      await _setBadge(0);
      _currentBadgeCount = 0;
      Logger.log('✅ 로그아웃 배지 초기화 완료');
    } catch (e) {
      Logger.error('⚠️ 로그아웃 배지 초기화 실패(계속 진행): $e');
    }
  }

  /// 데이터 변경 감지 시 호출 (디바운싱 적용)
  static void _onDataChanged(String userId, int generation) {
    if (!_isActiveSession(userId, generation)) return;
    // 짧은 시간 내 여러 변경이 발생하면 마지막 것만 처리
    _updateDebounceTimer?.cancel();
    _updateDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      _updateBadge(
        expectedUserId: userId,
        expectedGeneration: generation,
      );
    });
  }

  static void _onSnackChatsChanged(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    String userId,
    int generation,
  ) {
    if (!_isActiveSession(userId, generation)) return;
    _latestSnackChatSnapshot = snapshot;
    _scheduleSnackChatExpirationRefresh(userId, generation);
    _onDataChanged(userId, generation);
  }

  static void _scheduleSnackChatExpirationRefresh(
    String userId,
    int generation,
  ) {
    _snackChatExpirationTimer?.cancel();
    _snackChatExpirationTimer = null;
    final snapshot = _latestSnackChatSnapshot;
    if (snapshot == null || !_isActiveSession(userId, generation)) return;

    final now = DateTime.now();
    DateTime? nextExpiration;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final createdAt = data['createdAt'];
      final expiresAt = data['expiresAt'];
      if (createdAt is! Timestamp || expiresAt is! Timestamp) continue;
      if (!isEligibleForCurrentSnackChatListPolicy(createdAt.toDate())) {
        continue;
      }
      if (data['activeDurationHours'] == 0) continue;

      final favoriteUserIds = (data['favoriteUserIds'] as List?)
              ?.map((value) => value.toString())
              .toSet() ??
          <String>{};
      final isLegacyFavorite = favoriteUserIds.isEmpty &&
          data['isFavorited'] == true &&
          (data['creatorId'] ?? '').toString() == userId;
      if (favoriteUserIds.contains(userId) || isLegacyFavorite) continue;

      final expiration = expiresAt.toDate();
      if (!expiration.isAfter(now)) continue;
      if (nextExpiration == null || expiration.isBefore(nextExpiration)) {
        nextExpiration = expiration;
      }
    }

    if (nextExpiration == null) return;
    _snackChatExpirationTimer = Timer(
      nextExpiration.difference(now) + const Duration(milliseconds: 100),
      () {
        if (!_isActiveSession(userId, generation)) return;
        _onDataChanged(userId, generation);
        _scheduleSnackChatExpirationRefresh(userId, generation);
      },
    );
  }

  /// 배지 업데이트 (내부 메서드)
  static Future<void> _updateBadge({
    String? expectedUserId,
    int? expectedGeneration,
  }) {
    _badgeUpdateRequested = true;
    _pendingBadgeUserId = expectedUserId;
    _pendingBadgeGeneration = expectedGeneration;
    final inFlight = _badgeUpdateInFlight;
    if (inFlight != null) return inFlight;

    final completer = Completer<void>();
    _badgeUpdateInFlight = completer.future;
    unawaited(_drainBadgeUpdates(completer));
    return completer.future;
  }

  static Future<void> _drainBadgeUpdates(Completer<void> completer) async {
    try {
      while (_badgeUpdateRequested) {
        _badgeUpdateRequested = false;
        final userId = _pendingBadgeUserId;
        final generation = _pendingBadgeGeneration;
        await _performBadgeUpdate(
          expectedUserId: userId,
          expectedGeneration: generation,
        );
      }
      if (!completer.isCompleted) completer.complete();
    } catch (error, stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    } finally {
      if (identical(_badgeUpdateInFlight, completer.future)) {
        _badgeUpdateInFlight = null;
      }
      // 완료 직전에 새 요청이 들어온 극단적인 경우에도 갱신을 잃지 않는다.
      if (_badgeUpdateRequested && _badgeUpdateInFlight == null) {
        unawaited(_updateBadge(
          expectedUserId: _pendingBadgeUserId,
          expectedGeneration: _pendingBadgeGeneration,
        ));
      }
    }
  }

  static Future<void> _performBadgeUpdate({
    String? expectedUserId,
    int? expectedGeneration,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      await _setBadge(0);
      _currentBadgeCount = 0;
      return;
    }

    final userId = expectedUserId ?? user.uid;
    bool isCurrentRequest() {
      if (_auth.currentUser?.uid != userId) return false;
      if (expectedGeneration == null) return true;
      return _isActiveSession(userId, expectedGeneration);
    }

    if (!isCurrentRequest()) return;

    // 최대 3번 재시도
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        // 서로 독립적인 세 카운트를 병렬로 읽어 느린 네트워크에서 배지
        // 확정 시간을 줄인다. 위 coordinator가 중복 갱신은 직렬화한다.
        final counts = await Future.wait<int>([
          _getVisibleUnreadNotificationCount(userId: userId),
          _getDmUnreadCount(userId: userId),
          _getSnackChatUnreadCount(userId: userId),
        ]);
        if (!isCurrentRequest()) return;
        final notificationCount = counts[0];
        final dmUnreadCount = counts[1];
        final scUnreadCount = counts[2];

        final totalBadge = notificationCount + dmUnreadCount + scUnreadCount;

        if (_currentBadgeCount != totalBadge) {
          await _setBadge(totalBadge);
          _currentBadgeCount = totalBadge;
          if (_debugBadgeUpdateLogs < 10) {
            _debugBadgeUpdateLogs++;
            Logger.log(
                '✅ 배지 업데이트: $totalBadge (알림: $notificationCount, DM: $dmUnreadCount, SC: $scUnreadCount)');
          }
        }

        // 성공하면 즉시 리턴
        return;
      } catch (e) {
        if (!isCurrentRequest()) return;
        Logger.error('배지 업데이트 실패 (시도 ${attempt + 1}/3)', e);

        // 마지막 시도가 아니면 재시도
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }

        // 조회 실패는 미읽음 0개를 의미하지 않는다. 이전 정상 배지를
        // 유지해야 네트워크 단절 때 아이콘 숫자가 거짓으로 사라지지 않는다.
        Logger.error('❌ 배지 업데이트 최종 실패 - 마지막 정상 값 유지', e);
      }
    }
  }

  /// DM 안 읽은 수 가져오기 (users.dmUnreadTotal 우선, conversations fallback)
  static Future<int> _getDmUnreadCount({required String userId}) async {
    if (_activeUserId == userId && _latestUserSnapshot?.exists == true) {
      final cached = _latestUserSnapshot?.data()?['dmUnreadTotal'];
      if (cached is num && cached >= 0) return cached.toInt();
    }

    // users.dmUnreadTotal 읽기 (최대 3번 재시도)
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final userDoc = await _firestore
            .collection('users')
            .doc(userId)
            .get()
            .timeout(const Duration(seconds: 5));

        final data = userDoc.data();
        final v = data?['dmUnreadTotal'];

        if (v is int && v >= 0) {
          return v;
        } else if (v is num && v >= 0) {
          return v.toInt();
        }

        // 값이 없으면 fallback으로 진행
        break;
      } catch (e) {
        Logger.error('dmUnreadTotal 조회 실패 (시도 ${attempt + 1}/3)', e);

        // 마지막 시도가 아니면 재시도
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
          continue;
        }
      }
    }

    // fallback: conversations 기반 계산 (최대 2번 재시도)
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        int convSum = 0;
        final snap = await _firestore
            .collection('conversations')
            .where('participants', arrayContains: userId)
            .get()
            .timeout(const Duration(seconds: 10));

        for (final doc in snap.docs) {
          try {
            final c = doc.data();
            final archivedBy = List<String>.from(c['archivedBy'] ?? []);
            if (archivedBy.contains(userId)) continue;

            final unreadMap = (c['unreadCount'] as Map?) ?? const {};
            final raw = unreadMap[userId];
            final v = raw is int ? raw : (raw is num ? raw.toInt() : 0);
            if (v > 0) convSum += v;
          } catch (e) {
            continue;
          }
        }
        return convSum;
      } catch (e) {
        Logger.error('conversations 조회 실패 (시도 ${attempt + 1}/2)', e);

        // 마지막 시도가 아니면 재시도
        if (attempt < 1) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
      }
    }

    // 모든 시도 실패 시 0 반환
    Logger.error('❌ DM 안 읽은 수 계산 완전 실패 - 0 반환');
    return 0;
  }

  static Future<int> _getVisibleUnreadNotificationCount({
    required String userId,
  }) async {
    final cached =
        _activeUserId == userId ? _latestNotificationsSnapshot : null;
    final snapshot = cached ??
        await _firestore
            .collection('notifications')
            .where('userId', isEqualTo: userId)
            .where('isRead', isEqualTo: false)
            .get()
            .timeout(const Duration(seconds: 10));

    final notifications = snapshot.docs
        .map((doc) => AppNotification.fromFirestore(doc))
        .where((notification) => notification.type != 'dm_received')
        .toList();

    if (notifications.isEmpty) return 0;

    final blockedUserIds = await ContentFilterService.getBlockedUserIds();
    final blockedByUserIds = await ContentFilterService.getBlockedByUserIds();

    final visibleCount = notifications.where((notification) {
      final actorId = ContentFilterService.extractNotificationActorId({
        'actorId': notification.actorId,
        'data': notification.data,
      });
      return !ContentFilterService.isUserIdExcluded(
        actorId,
        blockedUserIds: blockedUserIds,
        blockedByUserIds: blockedByUserIds,
      );
    }).length;

    return visibleCount < 0 ? 0 : visibleCount;
  }

  /// 수동 배지 동기화 (레거시 호환용, 실시간 리스너가 없을 때 대비)
  static Future<void> syncNotificationBadge() async {
    // 실시간 리스너가 활성화되어 있으면 수동 동기화 불필요
    if (_userDocSubscription != null && _notificationsSubscription != null) {
      return;
    }

    // 실시간 리스너가 없으면 한 번 업데이트
    await _updateBadge();
  }

  static Future<void> _setBadge(int count) async {
    try {
      final safeCount = count < 0 ? 0 : count;
      await AppBadgePlus.updateBadge(safeCount);
      if (Platform.isAndroid && safeCount == 0) {
        await _clearAndroidNotificationTray();
      }
    } catch (e) {
      Logger.error('배지 적용 실패', e);
    }
  }

  static Future<void> _clearAndroidNotificationTray() async {
    if (!Platform.isAndroid) return;
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.cancelAll();
    } catch (e) {
      Logger.error('Android 알림 트레이 정리 실패', e);
    }
  }

  /// SnackChat 안 읽은 수 (활성 대화방 제외)
  static Future<int> _getSnackChatUnreadCount({required String userId}) async {
    try {
      final cached = _activeUserId == userId ? _latestSnackChatSnapshot : null;
      final snap = cached ??
          await _firestore
              .collection('snack_chats')
              .where('participantIds', arrayContains: userId)
              .get()
              .timeout(const Duration(seconds: 10));

      final activeId = SnackChatActiveConversation.activeSnackChatId;
      final now = DateTime.now();
      int total = 0;
      for (final doc in snap.docs) {
        if (doc.id == activeId) continue;
        final data = doc.data();

        // Keep badge eligibility identical to the Today/All list. Legacy,
        // malformed, and expired non-favorite rooms are intentionally absent
        // from both the screen and the unread total.
        final rawCreatedAt = data['createdAt'];
        if (rawCreatedAt is! Timestamp) continue;

        final activeDurationHours = data['activeDurationHours'] == 0 ? 0 : 24;
        final rawExpiresAt = data['expiresAt'];
        final expiresAt = rawExpiresAt is Timestamp
            ? rawExpiresAt.toDate()
            : activeDurationHours == 0
                ? DateTime.utc(9999, 12, 31)
                : now.add(const Duration(days: 1));
        final favoriteUserIds = (data['favoriteUserIds'] as List?)
                ?.map((value) => value.toString())
                .toSet() ??
            <String>{};
        if (favoriteUserIds.isEmpty &&
            data['isFavorited'] == true &&
            (data['creatorId'] ?? '').toString() == userId) {
          favoriteUserIds.add(userId);
        }

        if (!isSnackChatVisibleForCurrentUser(
          createdAt: rawCreatedAt.toDate(),
          activeDurationHours: activeDurationHours,
          expiresAt: expiresAt,
          favoriteUserIds: favoriteUserIds,
          currentUserId: userId,
          now: now,
        )) {
          continue;
        }

        final unreadMap = (data['unreadCount'] as Map?) ?? const {};
        final raw = unreadMap[userId];
        final v = raw is int ? raw : (raw is num ? raw.toInt() : 0);
        if (v > 0) total += v;
      }
      return total;
    } catch (e) {
      Logger.error('SnackChat 안 읽은 수 조회 실패', e);
      return 0;
    }
  }

  /// FCM push 수신 시 payload의 badge 값을 즉시 적용
  static Future<void> applyBadgeFromPush(
    int count, {
    required String recipientUserId,
  }) async {
    if (recipientUserId.isEmpty || _auth.currentUser?.uid != recipientUserId) {
      Logger.log('⏭️ 다른 계정 또는 계정 미지정 푸시 배지 무시');
      return;
    }
    final safeCount = count < 0 ? 0 : count;
    if (_currentBadgeCount == safeCount) return;
    _currentBadgeCount = safeCount;
    await _setBadge(safeCount);
  }

  /// 앱 포그라운드 진입 시 Android 배지를 실제 값으로 강제 동기화
  static Future<void> syncAndroidBadgeOnResume() async {
    if (!Platform.isAndroid) return;
    final userId = _auth.currentUser?.uid;
    final generation = _sessionGeneration;
    await _updateBadge(
      expectedUserId: userId,
      expectedGeneration:
          userId != null && _activeUserId == userId ? generation : null,
    );
  }
}
