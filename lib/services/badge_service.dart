import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_badge_plus/app_badge_plus.dart';

import '../utils/logger.dart';

/// iOS/Android 앱 아이콘 배지 동기화 서비스 (이벤트 기반)
///
/// 정책 (업데이트): "배지 숫자 = 읽지 않은 알림 개수 + 안 읽은 DM 수"
/// - 일반 알림: `dm_received` 타입 제외 (Notifications 탭 기준)
/// - DM: users/{uid}.dmUnreadTotal 실시간 리스닝
class BadgeService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // 스트림 구독 관리
  static StreamSubscription<DocumentSnapshot>? _userDocSubscription;
  static StreamSubscription<QuerySnapshot>? _notificationsSubscription;
  
  // 현재 배지 상태 캐싱 (불필요한 업데이트 방지)
  static int? _currentBadgeCount;
  
  // 디바운싱을 위한 타이머
  static Timer? _updateDebounceTimer;
  
  /// 실시간 배지 리스너 시작
  static Future<void> startRealtimeBadgeSync() async {
    final user = _auth.currentUser;
    if (user == null) {
      await _setBadge(0);
      return;
    }
    
    // 기존 구독 정리
    await stopRealtimeBadgeSync();
    
    if (!(Platform.isIOS || Platform.isAndroid)) return;
    
    final supported = await AppBadgePlus.isSupported();
    if (!supported) return;
    
    try {
      // 서버 카운터 동기화 (앱 시작 시 1회)
      await _syncServerCounters(user.uid);
      
      // 즉시 정확한 배지로 초기화
      await _updateBadge();
      
      // 1) users 문서 리스닝 (dmUnreadTotal 변경 감지)
      _userDocSubscription = _firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen(
            (snapshot) => _onDataChanged(),
            onError: (e) => Logger.error('users 문서 리스닝 실패', e),
          );
      
      // 2) 알림 컬렉션 리스닝 (안 읽은 알림 변경 감지)
      _notificationsSubscription = _firestore
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .where('isRead', isEqualTo: false)
          .snapshots()
          .listen(
            (snapshot) => _onDataChanged(),
            onError: (e) => Logger.error('알림 컬렉션 리스닝 실패', e),
          );
    } catch (e) {
      Logger.error('실시간 배지 동기화 시작 실패', e);
      // 실패 시에도 배지를 0으로 초기화
      await _setBadge(0);
    }
  }
  
  /// 서버 카운터를 실제 값으로 동기화 (앱 시작 시 1회)
  static Future<void> _syncServerCounters(String userId) async {
    // 최대 3번 재시도
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        // 실제 안 읽은 알림 수 계산 (dm_received 제외)
        final results = await Future.wait([
          _firestore
              .collection('notifications')
              .where('userId', isEqualTo: userId)
              .where('isRead', isEqualTo: false)
              .count()
              .get()
              .timeout(const Duration(seconds: 10)),
          _firestore
              .collection('notifications')
              .where('userId', isEqualTo: userId)
              .where('isRead', isEqualTo: false)
              .where('type', isEqualTo: 'dm_received')
              .count()
              .get()
              .timeout(const Duration(seconds: 10)),
        ]);

        final unreadAll = results[0].count ?? 0;
        final unreadDmNotif = results[1].count ?? 0;
        final actualNotificationCount = (unreadAll - unreadDmNotif) <= 0 ? 0 : (unreadAll - unreadDmNotif);

        // DM 안 읽은 수 계산 (✅ "카운터 신뢰"가 아니라 실제 메시지 기반으로 재계산)
        final actualDmUnreadCount = await _recountAndRepairDmUnread(userId: userId);

        // users 문서의 카운터를 실제 값으로 업데이트
        await _firestore.collection('users').doc(userId).set({
          'notificationUnreadTotal': actualNotificationCount,
          'dmUnreadTotal': actualDmUnreadCount,
        }, SetOptions(merge: true));

        Logger.log('✅ 서버 카운터 동기화 완료: 알림=$actualNotificationCount, DM=$actualDmUnreadCount');
        return; // 성공하면 즉시 리턴
      } catch (e) {
        Logger.error('서버 카운터 동기화 실패 (시도 ${attempt + 1}/3)', e);
        
        // 마지막 시도가 아니면 재시도
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }
        
        // 모든 재시도 실패 시 카운터를 0으로 설정
        try {
          await _firestore.collection('users').doc(userId).set({
            'notificationUnreadTotal': 0,
            'dmUnreadTotal': 0,
          }, SetOptions(merge: true));
          Logger.log('⚠️ 서버 카운터 동기화 실패 - 0으로 초기화');
        } catch (_) {
          Logger.error('❌ 서버 카운터 초기화도 실패', _);
        }
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

    int total = 0;
    final List<Future<void>> repairs = [];

    for (final doc in convSnap.docs) {
      try {
        final data = doc.data();

        final archivedBy = List<String>.from(data['archivedBy'] ?? []);
        if (archivedBy.contains(userId)) continue;

        // DM 목록/배지 정책과 일치: 내가 나간 뒤 새 메시지 없으면 제외
        final userLeftAt = (data['userLeftAt'] as Map?) ?? const {};
        final lastMessageTime = data['lastMessageTime'];
        if (userLeftAt[userId] != null && lastMessageTime is Timestamp) {
          final left = (userLeftAt[userId] as Timestamp).toDate();
          final last = lastMessageTime.toDate();
          if (!last.isAfter(left)) {
            continue;
          }
        }

        // 익명 방에서 모든 상대방이 나간 경우(목록에서 숨김) 제외
        final participants = (data['participants'] as List?)
                ?.map((e) => e.toString())
                .where((s) => s.isNotEmpty)
                .toSet() ??
            <String>{};
        if (doc.id.startsWith('anon_') && participants.isNotEmpty) {
          final others = participants.where((id) => id != userId).toSet();
          if (others.isNotEmpty) {
            final allOthersLeft = others.every((otherId) => userLeftAt[otherId] != null);
            if (allOthersLeft) continue;
          }
        }

        final unreadMap = (data['unreadCount'] as Map?) ?? const {};
        final rawClaimed = unreadMap[userId];
        final claimed = rawClaimed is int ? rawClaimed : (rawClaimed is num ? rawClaimed.toInt() : 0);

        // claimed가 0이면 굳이 messages를 스캔할 필요 없음
        if (claimed <= 0) {
          continue;
        }

        // 실제 unread(상대가 보낸 것 중 isRead=false) 재계산
        final unreadSnap = await doc.reference
            .collection('messages')
            .where('isRead', isEqualTo: false)
            .limit(200)
            .get()
            .timeout(const Duration(seconds: 10));

        int actual = 0;
        for (final m in unreadSnap.docs) {
          final md = m.data();
          final senderId = (md['senderId'] ?? '').toString();
          if (senderId.isNotEmpty && senderId != userId) {
            actual++;
          }
        }

        total += actual;

        // 복구: claimed와 actual이 다르면 conversations.unreadCount[userId]를 실제값으로 정정
        if (actual != claimed) {
          repairs.add(doc.reference.set({
            'unreadCount': {userId: actual},
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)));
        }
      } catch (_) {
        // best-effort: 개별 대화방 오류는 전체 동기화를 막지 않음
        continue;
      }
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
    await _userDocSubscription?.cancel();
    await _notificationsSubscription?.cancel();
    _userDocSubscription = null;
    _notificationsSubscription = null;
    _updateDebounceTimer?.cancel();
    _updateDebounceTimer = null;
  }
  
  /// 데이터 변경 감지 시 호출 (디바운싱 적용)
  static void _onDataChanged() {
    // 짧은 시간 내 여러 변경이 발생하면 마지막 것만 처리
    _updateDebounceTimer?.cancel();
    _updateDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      _updateBadge();
    });
  }
  
  /// 배지 업데이트 (내부 메서드)
  static Future<void> _updateBadge() async {
    final user = _auth.currentUser;
    if (user == null) {
      await _setBadge(0);
      return;
    }
    
    // 최대 3번 재시도
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        // 1) 일반 알림 읽지 않은 수 (dm_received 제외)
        final results = await Future.wait([
          _firestore
              .collection('notifications')
              .where('userId', isEqualTo: user.uid)
              .where('isRead', isEqualTo: false)
              .count()
              .get()
              .timeout(const Duration(seconds: 10)),
          _firestore
              .collection('notifications')
              .where('userId', isEqualTo: user.uid)
              .where('isRead', isEqualTo: false)
              .where('type', isEqualTo: 'dm_received')
              .count()
              .get()
              .timeout(const Duration(seconds: 10)),
        ]);

        final unreadAll = results[0].count ?? 0;
        final unreadDmNotif = results[1].count ?? 0;
        final notificationCount =
            (unreadAll - unreadDmNotif) <= 0 ? 0 : (unreadAll - unreadDmNotif);

        // 2) DM 안 읽은 수 (users.dmUnreadTotal 우선)
        final dmUnreadCount = await _getDmUnreadCount(userId: user.uid);

        final totalBadge = notificationCount + dmUnreadCount;

        // 3) 배지가 실제로 변경되었을 때만 업데이트
        // 중요: 0일 때도 반드시 업데이트 (잘못된 배지 제거)
        if (_currentBadgeCount != totalBadge) {
          await _setBadge(totalBadge);
          _currentBadgeCount = totalBadge;
          Logger.log('✅ 배지 업데이트: $totalBadge (알림: $notificationCount, DM: $dmUnreadCount)');
        }
        
        // 성공하면 즉시 리턴
        return;
      } catch (e) {
        Logger.error('배지 업데이트 실패 (시도 ${attempt + 1}/3)', e);
        
        // 마지막 시도가 아니면 재시도
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }
        
        // 모든 재시도 실패 시 0으로 초기화
        await _setBadge(0);
        _currentBadgeCount = 0;
        Logger.error('❌ 배지 업데이트 완전 실패 - 0으로 초기화', e);
      }
    }
  }
  
  /// DM 안 읽은 수 가져오기 (users.dmUnreadTotal 우선, conversations fallback)
  static Future<int> _getDmUnreadCount({required String userId}) async {
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
      Logger.log('🔔 배지 설정: $safeCount');
      await AppBadgePlus.updateBadge(safeCount);
    } catch (e) {
      Logger.error('배지 적용 실패', e);
    }
  }
}

