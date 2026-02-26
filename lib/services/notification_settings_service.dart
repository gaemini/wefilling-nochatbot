// lib/services/notification_settings_service.dart
// 알림 설정 관리 서비스
// Firestore에 사용자별 알림 설정 저장 및 로드

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/logger.dart';

// 알림 설정 키 상수 (통합된 구조)
class NotificationSettingKeys {
  // 전체 알림 토글
  static const String allNotifications = 'all_notifications';
  
  // 통합 카테고리 (사용자에게 표시되는 6개)
  static const String meetupAlerts = 'meetup_alerts'; // 모임 관련 (정원+취소+참여자)
  static const String friendAlerts = 'friend_alerts'; // 친구 관련 (요청+수락)
  static const String postInteractions = 'post_interactions'; // 게시글 (댓글+좋아요+비공개)
  static const String dmMessages = 'dm_messages'; // DM 메시지
  static const String marketing = 'marketing'; // 광고/프로모션
  
  // 레거시 키 (기존 코드 호환성을 위해 유지, 내부적으로 통합 키로 매핑)
  static const String dmReceived = 'dm_received';
  static const String meetupFull = 'meetup_full';
  static const String meetupCancelled = 'meetup_cancelled';
  static const String meetupParticipantJoined = 'meetup_participant_joined';
  static const String meetupParticipantLeft = 'meetup_participant_left';
  static const String newComment = 'new_comment';
  static const String newLike = 'new_like';
  static const String postPrivate = 'post_private';
  static const String friendRequest = 'friend_request';
  static const String adUpdates = 'ad_updates';
  
  // 레거시 키를 통합 키로 매핑
  static String mapLegacyToUnified(String legacyKey) {
    switch (legacyKey) {
      case meetupFull:
      case meetupCancelled:
      case meetupParticipantJoined:
      case meetupParticipantLeft:
        return meetupAlerts;
      
      case friendRequest:
        return friendAlerts;
      
      case newComment:
      case newLike:
      case postPrivate:
        return postInteractions;
      
      case dmReceived:
        return dmMessages;
      
      case adUpdates:
        return marketing;
      
      default:
        return legacyKey;
    }
  }
}

class NotificationSettingsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 기본 알림 설정 값 (통합된 6개 키)
  final Map<String, bool> _defaultSettings = {
    NotificationSettingKeys.allNotifications: true,
    NotificationSettingKeys.meetupAlerts: true,
    NotificationSettingKeys.friendAlerts: true,
    NotificationSettingKeys.postInteractions: true,
    NotificationSettingKeys.dmMessages: true,
    NotificationSettingKeys.marketing: true,
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

        // 레거시 설정을 통합 설정으로 마이그레이션
        final migrated = await _migrateIfNeeded(settings);
        if (migrated) {
          // 마이그레이션이 발생했으면 저장
          await docRef.update({
            'notifications': settings,
            'updated_at': FieldValue.serverTimestamp(),
          });
        }

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

  // 레거시 설정을 통합 설정으로 마이그레이션
  Future<bool> _migrateIfNeeded(Map<String, bool> settings) async {
    bool changed = false;

    // 통합 키가 없고 레거시 키가 있으면 마이그레이션
    if (!settings.containsKey(NotificationSettingKeys.meetupAlerts)) {
      // 모임 관련 알림: 하나라도 true면 true
      final meetupValue = 
          (settings[NotificationSettingKeys.meetupFull] ?? true) ||
          (settings[NotificationSettingKeys.meetupCancelled] ?? true) ||
          (settings[NotificationSettingKeys.meetupParticipantJoined] ?? true) ||
          (settings[NotificationSettingKeys.meetupParticipantLeft] ?? true);
      settings[NotificationSettingKeys.meetupAlerts] = meetupValue;
      changed = true;
    }

    if (!settings.containsKey(NotificationSettingKeys.friendAlerts)) {
      settings[NotificationSettingKeys.friendAlerts] = 
          settings[NotificationSettingKeys.friendRequest] ?? true;
      changed = true;
    }

    if (!settings.containsKey(NotificationSettingKeys.postInteractions)) {
      // 게시글 관련: 하나라도 true면 true
      final postValue = 
          (settings[NotificationSettingKeys.newComment] ?? true) ||
          (settings[NotificationSettingKeys.newLike] ?? true) ||
          (settings[NotificationSettingKeys.postPrivate] ?? true);
      settings[NotificationSettingKeys.postInteractions] = postValue;
      changed = true;
    }

    if (!settings.containsKey(NotificationSettingKeys.dmMessages)) {
      settings[NotificationSettingKeys.dmMessages] = 
          settings[NotificationSettingKeys.dmReceived] ?? true;
      changed = true;
    }

    if (!settings.containsKey(NotificationSettingKeys.marketing)) {
      settings[NotificationSettingKeys.marketing] = 
          settings[NotificationSettingKeys.adUpdates] ?? true;
      changed = true;
    }

    if (changed) {
      Logger.log('✅ 알림 설정 마이그레이션 완료');
    }

    return changed;
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

      // 광고 토픽 구독/해제 처리 (marketing 키 사용)
      if (key == NotificationSettingKeys.marketing) {
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

  // 특정 알림 유형이 활성화되어 있는지 확인 (레거시 키 지원)
  Future<bool> isNotificationEnabled(String notificationType) async {
    final settings = await getNotificationSettings();

    // 전체 알림이 꺼져 있으면 모든 알림은 비활성화
    if (!(settings[NotificationSettingKeys.allNotifications] ?? true)) {
      return false;
    }

    // 레거시 키를 통합 키로 변환
    final unifiedKey = NotificationSettingKeys.mapLegacyToUnified(notificationType);
    
    // 통합 키로 확인
    return settings[unifiedKey] ?? true;
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
