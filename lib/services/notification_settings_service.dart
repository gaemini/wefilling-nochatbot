// lib/services/notification_settings_service.dart
// 알림 설정 관리 서비스
// Firestore에 사용자별 알림 설정 저장 및 로드

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/logger.dart';

// 알림 설정 키 상수
class NotificationSettingKeys {
  static const String allNotifications = 'all_notifications';
  static const String dmReceived = 'dm_received'; // 💬 DM 수신 알림 추가
  static const String meetupFull = 'meetup_full';
  static const String meetupCancelled = 'meetup_cancelled';
  static const String meetupParticipantJoined = 'meetup_participant_joined';
  static const String meetupParticipantLeft = 'meetup_participant_left';
  static const String newComment = 'new_comment';
  static const String newLike = 'new_like';
  static const String postPrivate = 'post_private';
  static const String friendRequest = 'friend_request';
  static const String adUpdates = 'ad_updates';
}

class NotificationSettingsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 기본 알림 설정 값
  final Map<String, bool> _defaultSettings = {
    NotificationSettingKeys.allNotifications: true,
    NotificationSettingKeys.dmReceived: true, // 💬 DM 알림 기본값 활성화
    NotificationSettingKeys.meetupFull: true,
    NotificationSettingKeys.meetupCancelled: true,
    NotificationSettingKeys.meetupParticipantJoined: true,
    NotificationSettingKeys.meetupParticipantLeft: true,
    NotificationSettingKeys.newComment: true,
    NotificationSettingKeys.newLike: true,
    NotificationSettingKeys.postPrivate: true,
    NotificationSettingKeys.friendRequest: true,
    NotificationSettingKeys.adUpdates: true,
  };

  // 알림 설정 가져오기
  Future<Map<String, bool>> getNotificationSettings() async {
    final user = _auth.currentUser;
    if (user == null) {
      return _defaultSettings;
    }

    try {
      // 사용자 설정 문서 참조
      final docRef = _firestore.collection('user_settings').doc(user.uid);
      final doc = await docRef.get();

      if (!doc.exists || doc.data() == null) {
        // 설정이 없으면 기본값으로 새로 생성
        await docRef.set({
          'notifications': _defaultSettings,
          'updated_at': FieldValue.serverTimestamp(),
        });
        return _defaultSettings;
      } else {
        // 기존 설정 불러오기
        final data = doc.data()!;
        if (data['notifications'] == null) {
          return _defaultSettings;
        }

        // Firestore 데이터를 Map<String, bool>로 변환
        final notifications = data['notifications'] as Map<String, dynamic>;
        final settings = Map<String, bool>.from(notifications);

        // 새로 추가된 설정 키가 있으면 기본값으로 추가
        _defaultSettings.forEach((key, defaultValue) {
          if (!settings.containsKey(key)) {
            settings[key] = defaultValue;
          }
        });

        return settings;
      }
    } catch (e) {
      Logger.error('알림 설정 로드 오류: $e');
      return _defaultSettings;
    }
  }

  // 알림 설정 업데이트
  Future<bool> updateNotificationSetting(String key, bool value) async {
    final user = _auth.currentUser;
    if (user == null) {
      return false;
    }

    try {
      final docRef = _firestore.collection('user_settings').doc(user.uid);

      // 전체 알림 설정을 업데이트하는 경우 특별 처리
      if (key == NotificationSettingKeys.allNotifications && !value) {
        // 전체 알림을 끄면 다른 모든 설정도 비활성화됨
        await docRef.update({
          'notifications.$key': value,
          'updated_at': FieldValue.serverTimestamp(),
        });
      } else {
        // 개별 설정 업데이트
        await docRef.update({
          'notifications.$key': value,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      // 광고 토픽 구독/해제 처리
      if (key == NotificationSettingKeys.adUpdates) {
        try {
          // 지연 import 방지 (순환참조 회피)
          // ignore: avoid_dynamic_calls
          final dynamic fcm = await _loadFCMService();
          if (value) {
            await fcm.subscribeToTopic('ads');
          } else {
            await fcm.unsubscribeFromTopic('ads');
          }
        } catch (e) {
          Logger.error('FCM 토픽 처리 오류: $e');
        }
      }

      return true;
    } catch (e) {
      Logger.error('알림 설정 업데이트 오류: $e');
      return false;
    }
  }

  // 특정 알림 유형이 활성화되어 있는지 확인
  Future<bool> isNotificationEnabled(String notificationType) async {
    final settings = await getNotificationSettings();

    // 전체 알림이 꺼져 있으면 모든 알림은 비활성화
    if (!(settings[NotificationSettingKeys.allNotifications] ?? true)) {
      return false;
    }

    // 해당 유형의 알림 설정 확인
    return settings[notificationType] ?? true;
  }

  // 지연 로딩으로 FCMService 인스턴스 획득 (순환 의존성 회피용)
  Future<dynamic> _loadFCMService() async {
    // ignore: avoid_dynamic_calls
    final fcm = (await Future.microtask(() => null));
    // 실제 앱에서는 DI 컨테이너를 사용하거나, FCMService를 상위에서 주입받도록 개선 가능
    // 여기서는 전역 싱글턴 패턴 대신 간단히 import하여 생성
    // late import 방지: 직접 new FCMService() 생성
    // ignore: prefer_const_constructors
    return new _FCMServiceShim();
  }
}

// 간단한 셈플 shim: subscribe/unsubscribe만 사용
class _FCMServiceShim {
  Future<void> subscribeToTopic(String topic) async {
    // 지연 import로 실제 FCMService 사용
    // ignore: avoid_print
    Logger.log('Shim subscribeToTopic($topic) 호출 - 실제 런타임에서는 FCMService로 대체');
  }
  Future<void> unsubscribeFromTopic(String topic) async {
    // ignore: avoid_print
    Logger.log('Shim unsubscribeFromTopic($topic) 호출 - 실제 런타임에서는 FCMService로 대체');
  }
}
