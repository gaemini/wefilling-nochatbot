import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';

import '../utils/logger.dart';

/// iOS/Android 앱 아이콘 배지 동기화 서비스
///
/// 정책 (업데이트): "배지 숫자 = 읽지 않은 알림 개수 + 안 읽은 DM 수"
/// - 일반 알림: `dm_received` 타입 제외 (Notifications 탭 기준)
/// - DM: conversations 컬렉션의 unreadCount 합산
class BadgeService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<void> syncNotificationBadge() async {
    // 배지는 iOS에서 가장 중요. Android는 런처에 따라 미지원일 수 있어도 안전하게 no-op.
    if (!(Platform.isIOS || Platform.isAndroid)) return;

    final supported = await FlutterAppBadger.isAppBadgeSupported();
    if (!supported) return;

    final user = _auth.currentUser;
    if (user == null) {
      await _setBadge(0);
      return;
    }

    try {
      // 1) 일반 알림 읽지 않은 수 (dm_received 제외)
      final unreadAllAgg = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .where('isRead', isEqualTo: false)
          .count()
          .get();

      final unreadDmNotifAgg = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .where('isRead', isEqualTo: false)
          .where('type', isEqualTo: 'dm_received')
          .count()
          .get();

      final unreadAll = unreadAllAgg.count ?? 0;
      final unreadDmNotif = unreadDmNotifAgg.count ?? 0;
      final notificationCount = (unreadAll - unreadDmNotif) <= 0 ? 0 : (unreadAll - unreadDmNotif);

      // 2) DM 안 읽은 수 (conversations 컬렉션의 unreadCount 합산)
      final convsSnap = await _firestore
          .collection('conversations')
          .where('participants', arrayContains: user.uid)
          .get();

      int dmUnreadCount = 0;
      for (final doc in convsSnap.docs) {
        final data = doc.data();
        final archivedBy = List<String>.from(data['archivedBy'] ?? []);
        if (archivedBy.contains(user.uid)) continue; // 보관된 대화방 제외

        final unreadCount = Map<String, int>.from(data['unreadCount'] ?? {});
        final myUnread = unreadCount[user.uid] ?? 0;
        dmUnreadCount += myUnread;
      }

      final totalBadge = notificationCount + dmUnreadCount;
      Logger.log('BadgeService: 일반 알림($notificationCount) + DM($dmUnreadCount) = $totalBadge');

      await _setBadge(totalBadge);
    } catch (e) {
      Logger.error('BadgeService: 배지 동기화 실패: $e');
      // 실패 시 기존 배지 유지 (잘못된 0으로 지우는 것보다 안전)
    }
  }

  static Future<void> _setBadge(int count) async {
    try {
      if (count <= 0) {
        FlutterAppBadger.removeBadge();
        Logger.log('BadgeService: 배지 제거(0)');
      } else {
        FlutterAppBadger.updateBadgeCount(count);
        Logger.log('BadgeService: 배지 설정($count)');
      }
    } catch (e) {
      Logger.error('BadgeService: 배지 적용 실패: $e');
    }
  }
}

