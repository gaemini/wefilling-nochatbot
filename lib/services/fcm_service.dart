// lib/services/fcm_service.dart
// Firebase Cloud Messaging(FCM) 관련 기능 관리
// 푸시 알림 토큰 관리 및 메시지 처리

import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'navigation_service.dart';

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
  final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();

  // 로컬 알림 초기화
  Future<void> _initializeLocalNotifications() async {
    // Android 알림 채널 설정
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // 채널 ID
      'High Importance Notifications', // 채널 이름
      description: 'This channel is used for important notifications.', // 채널 설명
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    // Android 알림 채널 생성
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 초기화 설정
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        print('📱 알림 클릭: ${response.payload}');
        // 포그라운드 로컬 알림 탭 시 딥링크 라우팅
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          try {
            final Map<String, dynamic> data = jsonDecode(payload) as Map<String, dynamic>;
            await NavigationService.handlePushNavigation(data);
          } catch (e) {
            print('⚠️ 로컬 알림 payload 파싱 실패: $e');
          }
        }
      },
    );

    print('✅ 로컬 알림 초기화 완료');
  }

  // FCM 초기화
  Future<void> initialize(String userId) async {
    try {
      print('📱 FCM 초기화 시작: $userId');

      // 로컬 알림 초기화
      await _initializeLocalNotifications();

      // iOS 및 Android 알림 권한 요청
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

        // 로컬 알림 표시
        _showLocalNotification(message);
      });

      // 백그라운드에서 앱이 열렸을 때 메시지 처리
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
        print('📱 백그라운드에서 앱 열림: ${message.messageId}');
        print('📱 데이터: ${message.data}');
        await NavigationService.handlePushNavigation(message.data);
      });

      // 앱이 종료된 상태에서 알림을 통해 열렸을 때
      RemoteMessage? initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        print('📱 앱 종료 상태에서 알림으로 열림: ${initialMessage.messageId}');
        print('📱 데이터: ${initialMessage.data}');
        await NavigationService.handlePushNavigation(initialMessage.data);
      }

      print('✅ FCM 초기화 완료');
    } catch (e) {
      print('❌ FCM 초기화 실패: $e');
      rethrow;
    }
  }

  // 로컬 알림 표시
  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      final notification = message.notification;
      if (notification == null) {
        print('⚠️ 알림 데이터가 없습니다');
        return;
      }

      const AndroidNotificationDetails androidDetails = 
          AndroidNotificationDetails(
        'high_importance_channel',
        'High Importance Notifications',
        channelDescription: 'This channel is used for important notifications.',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        message.hashCode,
        notification.title,
        notification.body,
        details,
        payload: jsonEncode(message.data),
      );

      print('✅ 로컬 알림 표시 완료');
    } catch (e) {
      print('❌ 로컬 알림 표시 실패: $e');
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
      // 5초 타임아웃 설정 (네트워크 불안정 시 무한 대기 방지)
      await Future.wait([
        // FCM 토큰 삭제
        _messaging.deleteToken().then((_) {
          print('✅ FCM 토큰 삭제 완료');
        }),
        // Firestore에서도 토큰 제거
        _firestore.collection('users').doc(userId).update({
          'fcmToken': FieldValue.delete(),
          'fcmTokenUpdatedAt': FieldValue.delete(),
        }).then((_) {
          print('✅ Firestore에서 FCM 토큰 제거 완료');
        }),
      ]).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('⚠️ FCM 토큰 삭제 타임아웃 (5초) - 로그아웃 계속 진행');
          return [];
        },
      );
    } catch (e) {
      print('❌ FCM 토큰 삭제 실패 (계속 진행): $e');
      // 예외를 다시 던지지 않음 - 로그아웃은 계속 진행되어야 함
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


