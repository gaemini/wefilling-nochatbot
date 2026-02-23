// lib/services/fcm_service.dart
// Firebase Cloud Messaging(FCM) 관련 기능 관리
// 푸시 알림 토큰 관리 및 메시지 처리

import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'dart:ui' as ui;
import 'badge_service.dart';
import 'navigation_service.dart';
import '../utils/logger.dart';

// 백그라운드 메시지 핸들러 (최상위 함수여야 함)
// iOS에서 앱이 백그라운드/종료 상태일 때 메시지를 처리
// ⚠️ 중요: 이 핸들러에서는 배지를 직접 설정하지 않음
//    iOS는 APNs payload의 badge 값을 자동으로 처리함
//    Android만 필요 시 여기서 배지 설정 가능
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  Logger.log('📱 백그라운드 메시지 수신: ${message.messageId}');
  Logger.log('📱 제목: ${message.notification?.title}');
  Logger.log('📱 내용: ${message.notification?.body}');
  Logger.log('📱 데이터: ${message.data}');
  
  // iOS: APNs payload의 badge가 자동으로 적용됨 (여기서 처리 불필요)
  // Android: 필요 시 여기서 배지 설정 가능
}

class FCMService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
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
        Logger.log('📱 알림 클릭: ${response.payload}');
        // 포그라운드 로컬 알림 탭 시 딥링크 라우팅
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          try {
            final Map<String, dynamic> data = jsonDecode(payload) as Map<String, dynamic>;
            await NavigationService.handlePushNavigation(data);
          } catch (e) {
            Logger.error('⚠️ 로컬 알림 payload 파싱 실패: $e');
          }
        }
      },
    );
  }

  // FCM 초기화
  Future<void> initialize(String userId) async {
    try {

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

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        // 알림 권한 승인됨
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        // 임시 알림 권한 승인됨
      } else {
        Logger.log('❌ 알림 권한 거부됨');
        return;
      }

      // ✅ iOS: AppDelegate의 UNUserNotificationCenterDelegate가 알림 표시 처리
      // ✅ Android: Firebase Cloud Messaging이 자동으로 알림 표시

      // 토큰 동기화는 UI와 분리해서 백그라운드로 처리
      _startTokenSync(userId);

      // 토큰 갱신 리스너 등록
      _messaging.onTokenRefresh.listen((newToken) {
        Logger.log('📱 FCM 토큰 갱신: $newToken');
        _saveFCMToken(userId, newToken);
      });

      // 포어그라운드 메시지 리스너 등록
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        Logger.log('📱 포어그라운드 메시지 수신: ${message.messageId}');
        Logger.log('📱 제목: ${message.notification?.title}');
        Logger.log('📱 내용: ${message.notification?.body}');
        Logger.log('📱 데이터: ${message.data}');

        // iOS: setForegroundNotificationPresentationOptions 설정으로
        //      FCM이 자동으로 알림을 표시하므로 로컬 알림 불필요
        // Android: Firebase Cloud Messaging이 자동으로 처리
        //          (notification 필드가 있으면 자동으로 알림 표시)
        
        // 실시간 리스너가 자동으로 배지를 업데이트하므로 수동 호출 불필요
      });

      // 백그라운드에서 앱이 열렸을 때 메시지 처리
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
        Logger.log('📱 백그라운드에서 앱 열림: ${message.messageId}');
        Logger.log('📱 데이터: ${message.data}');
        await NavigationService.handlePushNavigation(message.data);
      });

      // 앱이 종료된 상태에서 알림을 통해 열렸을 때
      RemoteMessage? initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        Logger.log('📱 앱 종료 상태에서 알림으로 열림: ${initialMessage.messageId}');
        Logger.log('📱 데이터: ${initialMessage.data}');
        await NavigationService.handlePushNavigation(initialMessage.data);
      }

    } catch (e) {
      Logger.error('FCM 초기화 실패', e);
      rethrow;
    }
  }

  void _startTokenSync(String userId) {
    // 로그인/초기화 흐름을 막지 않도록 비동기 작업으로 분리
    Future.microtask(() async {
      await _syncTokenWithRetries(userId);
    });
  }

  Future<void> _syncTokenWithRetries(String userId) async {
    const List<int> retrySeconds = [0, 2, 4, 8, 16];

    for (int i = 0; i < retrySeconds.length; i++) {
      if (retrySeconds[i] > 0) {
        await Future.delayed(Duration(seconds: retrySeconds[i]));
      }

      // iOS에서 APNs 토큰 먼저 확인 (필수)
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          final String? apnsToken = await _messaging.getAPNSToken();
          if (apnsToken == null || apnsToken.isEmpty) {
            Logger.log('⚠️ APNs 토큰 대기 중... (retry ${i + 1}/${retrySeconds.length})');
            continue;
          } else {
            Logger.log('📱 APNs 토큰 준비됨: ${apnsToken.substring(0, 20)}...');
          }
        } catch (e) {
          Logger.error('❌ APNs 토큰 가져오기 실패: $e');
          continue;
        }
      }

      // FCM 토큰 가져오기
      try {
        final String? token = await _messaging.getToken();
        if (token != null && token.isNotEmpty) {
          Logger.log('📱 FCM 토큰: $token');
          await _saveFCMToken(userId, token);
          return;
        }
        Logger.log('⚠️ FCM 토큰 대기 중... (retry ${i + 1}/${retrySeconds.length})');
      } catch (e) {
        Logger.error('❌ FCM 토큰 가져오기 실패: $e');
      }
    }

    Logger.log('❌ FCM 토큰 동기화 실패 - 다음 실행에서 재시도됩니다');
  }

  // 로컬 알림 표시 (현재 미사용)
  // iOS: setForegroundNotificationPresentationOptions로 자동 처리
  // Android: Firebase Cloud Messaging이 자동으로 notification 표시
  // 
  // 향후 커스텀 알림 UI가 필요할 경우를 위해 코드 보존
  /*
  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      final notification = message.notification;
      if (notification == null) {
        Logger.log('⚠️ 알림 데이터가 없습니다');
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

      Logger.log('✅ 로컬 알림 표시 완료');
    } catch (e) {
      Logger.error('❌ 로컬 알림 표시 실패: $e');
    }
  }
  */

  // FCM 토큰 저장
  Future<void> _saveFCMToken(String userId, String token) async {
    try {
      // ✅ 서버에서 "토큰 중복(다른 계정에 남아있는 토큰)"을 정리하고,
      //    토큰 단위 locale(lang)까지 함께 저장하도록 Cloud Functions를 우선 사용.
      //    (한국어/영어 알림이 연속으로 2번 오는 문제의 핵심 원인 방지)
      final locale = ui.PlatformDispatcher.instance.locale;
      final String localeTag = (() {
        try {
          return locale.toLanguageTag();
        } catch (_) {
          final cc = locale.countryCode;
          return cc == null || cc.isEmpty ? locale.languageCode : '${locale.languageCode}-$cc';
        }
      })();

      final String? platform = (() {
        if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
        if (defaultTargetPlatform == TargetPlatform.android) return 'android';
        return null;
      })();

      try {
        final callable = _functions.httpsCallable('registerFcmToken');
        await callable.call(<String, dynamic>{
          'token': token,
          'locale': localeTag,
          if (platform != null) 'platform': platform,
        });
        Logger.log('✅ FCM 토큰 등록 완료 (서버 정리 + locale 저장)');
        return;
      } catch (e) {
        // 네트워크/함수 오류 시 레거시 방식으로 fallback (토큰은 최소한 저장되도록)
        Logger.error('⚠️ registerFcmToken 실패 - 레거시 저장으로 fallback: $e');
      }

      // fallback: 단일 토큰(fcmToken) + 멀티 토큰(fcmTokens)
      // ⚠️ merge set은 users 문서를 "부분 필드만 가진 상태로 생성"할 수 있으므로 update만 허용한다.
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
      Logger.log('✅ FCM 토큰 저장 완료 (레거시 fallback)');
    } catch (e) {
      Logger.error('❌ FCM 토큰 저장 실패: $e');
    }
  }

  // FCM 토큰 삭제 (로그아웃 시)
  Future<void> deleteFCMToken(String userId) async {
    try {
      // 멀티 디바이스 지원:
      // - 현재 기기의 토큰만 fcmTokens에서 제거
      // - fcmToken(레거시 단일 토큰)은 "현재 토큰과 일치할 때만" 삭제/대체
      final String? token = await _messaging.getToken();

      // 5초 타임아웃 설정 (네트워크 불안정 시 무한 대기 방지)
      await Future.wait([
        // FCM 토큰 삭제
        _messaging.deleteToken().then((_) {
          Logger.log('✅ FCM 토큰 삭제 완료');
        }),
        // 서버 레지스트리에서도 제거 (가능한 경우에만)
        if (token != null && token.isNotEmpty)
          _functions.httpsCallable('unregisterFcmToken').call(<String, dynamic>{
            'token': token,
          }).catchError((e) {
            Logger.log('⚠️ unregisterFcmToken 실패(무시): $e');
          }),
        // Firestore에서도 "해당 토큰"만 제거 (다른 기기 토큰은 보존)
        if (token != null && token.isNotEmpty)
          _firestore.runTransaction((tx) async {
            final ref = _firestore.collection('users').doc(userId);
            final snap = await tx.get(ref);
            if (!snap.exists) return;

            final data = snap.data() as Map<String, dynamic>? ?? {};
            final currentSingle = data['fcmToken'] as String?;
            final currentList = (data['fcmTokens'] as List?)
                    ?.whereType<String>()
                    .where((t) => t.isNotEmpty)
                    .toList() ??
                <String>[];

            final newList = currentList.where((t) => t != token).toList();

            final updates = <String, dynamic>{
              // 배열이 비면 필드 자체 제거
              'fcmTokens': newList.isEmpty ? FieldValue.delete() : newList,
              'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
            };

            // 레거시 단일 토큰이 현재 토큰과 같으면 삭제/대체
            if (currentSingle == token) {
              updates['fcmToken'] =
                  newList.isEmpty ? FieldValue.delete() : newList.first;
            }

            tx.set(ref, updates, SetOptions(merge: true));
          }).then((_) {
            Logger.log('✅ Firestore에서 현재 기기 FCM 토큰 제거 완료');
          }),
      ]).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          Logger.log('⚠️ FCM 토큰 삭제 타임아웃 (5초) - 로그아웃 계속 진행');
          return [];
        },
      );
    } catch (e) {
      Logger.error('❌ FCM 토큰 삭제 실패 (계속 진행): $e');
      // 예외를 다시 던지지 않음 - 로그아웃은 계속 진행되어야 함
    }
  }

  // 특정 토픽 구독
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      Logger.log('✅ 토픽 구독 완료: $topic');
    } catch (e) {
      Logger.error('❌ 토픽 구독 실패: $e');
      rethrow;
    }
  }

  // 토픽 구독 취소
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      Logger.log('✅ 토픽 구독 취소 완료: $topic');
    } catch (e) {
      Logger.error('❌ 토픽 구독 취소 실패: $e');
      rethrow;
    }
  }

  // 현재 FCM 토큰 가져오기
  Future<String?> getToken() async {
    try {
      String? token = await _messaging.getToken();
      return token;
    } catch (e) {
      Logger.error('❌ FCM 토큰 가져오기 실패: $e');
      return null;
    }
  }
}


