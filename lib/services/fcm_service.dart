// lib/services/fcm_service.dart
// Firebase Cloud Messaging(FCM) 관련 기능 관리
// 푸시 알림 토큰 관리 및 메시지 처리

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// 백그라운드 메시지 핸들러 (최상위 함수여야 함)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('📱 백그라운드 메시지 수신: ${message.messageId}');
  print('📱 제목: ${message.notification?.title}');
  print('📱 내용: ${message.notification?.body}');
  print('📱 데이터: ${message.data}');
}

class FCMService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // FCM 초기화
  Future<void> initialize(String userId) async {
    try {
      print('📱 FCM 초기화 시작: $userId');

      // iOS 알림 권한 요청
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      print('📱 알림 권한 상태: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ 알림 권한 승인됨');
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        print('⚠️ 임시 알림 권한 승인됨');
      } else {
        print('❌ 알림 권한 거부됨');
        return;
      }

      // FCM 토큰 가져오기
      String? token = await _messaging.getToken();
      if (token != null) {
        print('📱 FCM 토큰: $token');
        await _saveFCMToken(userId, token);
      } else {
        print('❌ FCM 토큰을 가져올 수 없습니다');
      }

      // 토큰 갱신 리스너 등록
      _messaging.onTokenRefresh.listen((newToken) {
        print('📱 FCM 토큰 갱신: $newToken');
        _saveFCMToken(userId, newToken);
      });

      // 포어그라운드 메시지 리스너 등록
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📱 포어그라운드 메시지 수신: ${message.messageId}');
        print('📱 제목: ${message.notification?.title}');
        print('📱 내용: ${message.notification?.body}');
        print('📱 데이터: ${message.data}');

        // 여기서 로컬 알림을 표시하거나 UI 업데이트 가능
        // 필요한 경우 flutter_local_notifications 패키지 사용
      });

      // 백그라운드에서 앱이 열렸을 때 메시지 처리
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('📱 백그라운드에서 앱 열림: ${message.messageId}');
        print('📱 데이터: ${message.data}');
        
        // 알림을 통해 앱이 열렸을 때의 처리
        // 예: 특정 화면으로 이동
      });

      // 앱이 종료된 상태에서 알림을 통해 열렸을 때
      RemoteMessage? initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        print('📱 앱 종료 상태에서 알림으로 열림: ${initialMessage.messageId}');
        print('📱 데이터: ${initialMessage.data}');
        
        // 알림을 통해 앱이 열렸을 때의 처리
      }

      print('✅ FCM 초기화 완료');
    } catch (e) {
      print('❌ FCM 초기화 실패: $e');
      rethrow;
    }
  }

  // FCM 토큰 저장
  Future<void> _saveFCMToken(String userId, String token) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ FCM 토큰 저장 완료');
    } catch (e) {
      print('❌ FCM 토큰 저장 실패: $e');
      
      // 문서가 없는 경우 set으로 생성
      try {
        await _firestore.collection('users').doc(userId).set({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        print('✅ FCM 토큰 병합 저장 완료');
      } catch (e2) {
        print('❌ FCM 토큰 병합 저장 실패: $e2');
      }
    }
  }

  // FCM 토큰 삭제 (로그아웃 시)
  Future<void> deleteFCMToken(String userId) async {
    try {
      // FCM 토큰 삭제
      await _messaging.deleteToken();
      print('✅ FCM 토큰 삭제 완료');

      // Firestore에서도 토큰 제거
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.delete(),
      });
      print('✅ Firestore에서 FCM 토큰 제거 완료');
    } catch (e) {
      print('❌ FCM 토큰 삭제 실패: $e');
      rethrow;
    }
  }

  // 특정 토픽 구독
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      print('✅ 토픽 구독 완료: $topic');
    } catch (e) {
      print('❌ 토픽 구독 실패: $e');
      rethrow;
    }
  }

  // 토픽 구독 취소
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      print('✅ 토픽 구독 취소 완료: $topic');
    } catch (e) {
      print('❌ 토픽 구독 취소 실패: $e');
      rethrow;
    }
  }

  // 현재 FCM 토큰 가져오기
  Future<String?> getToken() async {
    try {
      String? token = await _messaging.getToken();
      return token;
    } catch (e) {
      print('❌ FCM 토큰 가져오기 실패: $e');
      return null;
    }
  }
}


