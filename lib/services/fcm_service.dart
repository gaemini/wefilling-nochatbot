// lib/services/fcm_service.dart
// Firebase Cloud Messaging(FCM) 관련 기능 관리
// 푸시 알림 토큰 관리 및 메시지 처리

import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui' as ui;
import 'package:shared_preferences/shared_preferences.dart';
import 'badge_service.dart';
import 'navigation_service.dart';
import 'dm_active_conversation.dart';
import 'snack_chat_active_conversation.dart';
import '../utils/logger.dart';
import 'dart:io';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final badgeStr = message.data['badge'];
  if (badgeStr != null) {
    final badge = int.tryParse(badgeStr.toString());
    if (badge != null && badge >= 0) {
      try {
        await AppBadgePlus.updateBadge(badge);
      } catch (_) {}
    }
  }
}

class FCMService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();

  static const String _channelHighImportanceId = 'high_importance_channel';
  static const String _channelHighImportanceName = 'High Importance Notifications';
  static const String _channelMeetupId = 'meetup_notifications';
  static const String _channelMeetupName = 'Meetup Notifications';

  // 로컬 알림 초기화
  Future<void> _initializeLocalNotifications() async {
    // Android 알림 채널 설정
    const AndroidNotificationChannel highImportanceChannel = AndroidNotificationChannel(
      _channelHighImportanceId,
      _channelHighImportanceName,
      description: 'This channel is used for important notifications.',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    const AndroidNotificationChannel meetupChannel = AndroidNotificationChannel(
      _channelMeetupId,
      _channelMeetupName,
      description: 'This channel is used for meetup-related notifications.',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    // Android 알림 채널 생성
    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(highImportanceChannel);
    await androidPlugin?.createNotificationChannel(meetupChannel);

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

  Future<bool> _ensureAndroidPostNotificationsPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      // Android 13+에서만 런타임 권한이 의미가 있고,
      // permission_handler는 OS별로 적절히 status/grant를 반환한다.
      final status = await Permission.notification.status;
      if (status.isGranted) return true;

      final requested = await Permission.notification.request();
      if (requested.isGranted) return true;

      // 거부/영구 거부 상태: OS 팝업이 더 이상 안 뜰 수 있다.
      // 배포 품질: 최소한 로그로 원인 노출 (UI 안내는 상위 레이어에서 처리 권장)
      Logger.log('❌ Android 알림 권한 미허용: $requested');
      return false;
    } catch (e) {
      Logger.error('❌ Android 알림 권한 요청 실패', e);
      // 실패하더라도 앱 동작은 계속 (best-effort)
      return false;
    }
  }

  // 로그아웃 시 호출 (현재는 no-op, 리스너 정리 불필요)
  Future<void> reset() async {}

  // locale 안전성 검증
  Future<void> _ensureLocaleInitialized() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLocale = prefs.getString('app_language');

      if (savedLocale == null || savedLocale.isEmpty) {
        // 기본 언어 강제 설정
        await prefs.setString('app_language', 'ko');
        Logger.log('✅ locale 기본값 설정: ko');
      } else {
        Logger.log('✅ locale 확인됨: $savedLocale');
      }
    } catch (e) {
      Logger.error('locale 초기화 실패 (무시)', e);
    }
  }

  Future<bool> _consumeIosRecoveryFlag() async {
    if (kIsWeb || !Platform.isIOS) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final required = prefs.getBool('ios_fcm_recovery_required') ?? false;
      if (!required) {
        return false;
      }

      await prefs.setBool('ios_fcm_recovery_required', false);
      Logger.log('🛟 iOS FCM 복구 플래그 감지');
      return true;
    } catch (e) {
      Logger.error('iOS FCM 복구 플래그 확인 실패', e);
      return false;
    }
  }

  Future<void> _performDeferredIosTokenRecoveryIfNeeded() async {
    if (kIsWeb || !Platform.isIOS) return;

    final shouldRecover = await _consumeIosRecoveryFlag();
    if (!shouldRecover) {
      return;
    }

    try {
      final String? apnsToken = await _messaging.getAPNSToken().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );

      if (apnsToken == null || apnsToken.isEmpty) {
        Logger.log('⚠️ iOS FCM 복구 연기: APNs 토큰 미준비');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('ios_fcm_recovery_required', true);
        return;
      }

      Logger.log('🛟 iOS FCM 안전 복구 시작');
      await _messaging.deleteToken().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          Logger.log('⏱️ iOS FCM 안전 복구 토큰 삭제 타임아웃');
        },
      );
      await Future.delayed(const Duration(seconds: 1));
      Logger.log('✅ iOS FCM 안전 복구 완료');
    } catch (e) {
      Logger.error('iOS FCM 안전 복구 실패', e);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('ios_fcm_recovery_required', true);
      } catch (_) {}
    }
  }

  // FCM 초기화
  Future<void> initialize(String userId) async {
    // 전체 초기화를 try-catch로 래핑 (최상위 보호)
    try {
      // locale 안전성 검증 (Firebase Messaging 초기화 전 필수)
      try {
        await _ensureLocaleInitialized();
      } catch (e) {
        Logger.error('locale 초기화 실패 - 계속 진행', e);
      }

      // 로컬 알림 초기화
      try {
        await _initializeLocalNotifications();
      } catch (e) {
        Logger.error('로컬 알림 초기화 실패 - 계속 진행', e);
      }

      // ✅ Android 13+: POST_NOTIFICATIONS 런타임 권한을 명시적으로 요청
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await _ensureAndroidPostNotificationsPermission();
        } catch (e) {
          Logger.error('Android 알림 권한 요청 실패 - 계속 진행', e);
        }
      }

      // iOS: 알림 권한 요청 (Android는 의미가 약하므로 best-effort로만 호출)
      try {
        final settings = await _messaging.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
        );

        if (!kIsWeb && Platform.isIOS) {
          if (settings.authorizationStatus == AuthorizationStatus.authorized) {
            Logger.log('✅ iOS 알림 권한 승인됨');
          } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
            Logger.log('✅ iOS 알림 권한 Provisional');
          } else {
            Logger.log('❌ iOS 알림 권한 거부됨 - FCM 초기화 중단');
            return; // 권한 없으면 FCM 초기화 중단
          }
        }
      } catch (e) {
        Logger.error('권한 요청 실패 - 계속 진행', e);
        // 권한 요청 실패해도 앱은 계속 실행 (FCM 기능만 제한)
      }

      // ✅ iOS(포그라운드): 시스템 자동 배너를 끄고(전역),
      //    Flutter에서 "원할 때만" 로컬 알림을 표시한다.
      // - 목적: DM 채팅 중에는 DM 알림을 띄우지 않기 위함(대화방 활성 시)
      if (!kIsWeb && Platform.isIOS) {
        try {
          await _messaging.setForegroundNotificationPresentationOptions(
            alert: false,
            badge: false,
            sound: true,
          ).timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              Logger.log('⏱️ 포그라운드 설정 타임아웃');
            },
          );
        } catch (e) {
          Logger.error('포그라운드 설정 실패 - 계속 진행', e);
        }

        try {
          await _performDeferredIosTokenRecoveryIfNeeded();
        } catch (e) {
          Logger.error('iOS 지연 복구 처리 실패 - 계속 진행', e);
        }
      }

      // 토큰 동기화는 UI와 분리해서 백그라운드로 처리
      try {
        _startTokenSync(userId);
      } catch (e) {
        Logger.error('토큰 동기화 시작 실패 - 계속 진행', e);
      }

      // 토큰 갱신 리스너 등록
      try {
        _messaging.onTokenRefresh.listen((newToken) {
          Logger.log('📱 FCM 토큰 갱신: $newToken');
          _saveFCMToken(userId, newToken);
        });
      } catch (e) {
        Logger.error('토큰 갱신 리스너 등록 실패 - 계속 진행', e);
      }

      // 포어그라운드 메시지 리스너 등록
      try {
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          try {
            Logger.log('📱 포어그라운드 메시지 수신: ${message.messageId}');
            Logger.log('📱 제목: ${message.notification?.title}');
            Logger.log('📱 내용: ${message.notification?.body}');
            Logger.log('📱 데이터: ${message.data}');

            // ✅ 포그라운드 알림 정책:
            // - iOS는 위에서 alert=false로 해뒀기 때문에, 여기서 로컬 알림을 "선택적으로" 띄운다.
            // - DM 채팅방을 보고 있는 경우(해당 conversationId 활성) DM 알림은 띄우지 않는다.
            final type = (message.data['type'] ?? '').toString();
            final conversationId = (message.data['conversationId'] ?? '').toString();
            final snackChatId = (message.data['snackChatId'] ?? '').toString();
            final isDm = type == 'dm_received' && conversationId.isNotEmpty;
            final isSnackChat = type == 'snack_chat_message' && snackChatId.isNotEmpty;

            if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
              final isActiveConversation =
                  (isDm && DMActiveConversation.isActive(conversationId)) ||
                  (isSnackChat && SnackChatActiveConversation.isActive(snackChatId));

              if (isActiveConversation) {
                return;
              }

              final badgeStr = (message.data['badge'] ?? '').toString();
              final badge = int.tryParse(badgeStr);
              if (badge != null && badge >= 0) {
                unawaited(BadgeService.applyBadgeFromPush(badge));
              }

              unawaited(_showLocalNotification(message));
            }
          } catch (e) {
            Logger.error('포어그라운드 메시지 처리 실패', e);
          }
        });
      } catch (e) {
        Logger.error('포어그라운드 메시지 리스너 등록 실패 - 계속 진행', e);
      }

      // 백그라운드에서 앱이 열렸을 때 메시지 처리
      try {
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
          try {
            Logger.log('📱 백그라운드에서 앱 열림: ${message.messageId}');
            Logger.log('📱 데이터: ${message.data}');
            await NavigationService.handlePushNavigation(message.data);
          } catch (e) {
            Logger.error('백그라운드 메시지 처리 실패', e);
          }
        });
      } catch (e) {
        Logger.error('백그라운드 메시지 리스너 등록 실패 - 계속 진행', e);
      }

      // 앱이 종료된 상태에서 알림을 통해 열렸을 때
      try {
        RemoteMessage? initialMessage = await _messaging.getInitialMessage().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            Logger.log('⏱️ getInitialMessage 타임아웃');
            return null;
          },
        );
        if (initialMessage != null) {
          Logger.log('📱 앱 종료 상태에서 알림으로 열림: ${initialMessage.messageId}');
          Logger.log('📱 데이터: ${initialMessage.data}');
          await NavigationService.handlePushNavigation(initialMessage.data);
        }
      } catch (e) {
        Logger.error('초기 메시지 처리 실패 - 계속 진행', e);
      }

    } catch (e) {
      Logger.error('FCM 초기화 실패 - 앱은 계속 실행됨', e);
      // 크래시 방지: 예외를 삼키고 앱 실행 계속
      // Firebase Crashlytics에 리포트 (가능한 경우)
      try {
        if (!kDebugMode) {
          // Production에서만 크래시 리포트
          rethrow;
        }
      } catch (_) {
        // 크래시 리포트 실패해도 앱은 계속 실행
      }
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

      final bool shouldLogRetry = i == 0 || i == retrySeconds.length - 1;

      try {
        // iOS에서 APNs 토큰 먼저 확인 (필수)
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          try {
            final String? apnsToken = await _messaging.getAPNSToken();
            if (apnsToken == null || apnsToken.isEmpty) {
              if (shouldLogRetry) {
                Logger.log('⚠️ APNs 토큰 대기 중... (retry ${i + 1}/${retrySeconds.length})');
              }
              continue;
            } else {
              Logger.log('📱 APNs 토큰 준비됨: ${apnsToken.substring(0, 20)}...');
            }
          } catch (e) {
            Logger.error('❌ APNs 토큰 가져오기 실패: $e');
            continue;
          }
        }

        // FCM 토큰 가져오기 - 타임아웃 추가
        try {
          final String? token = await _messaging.getToken().timeout(
            const Duration(seconds: 5),
            onTimeout: () => null,
          );
          
          if (token != null && token.isNotEmpty) {
            Logger.log('📱 FCM 토큰 준비됨: ${token.substring(0, 20)}...');
            await _saveFCMToken(userId, token);
            return;
          }
          if (shouldLogRetry) {
            Logger.log('⚠️ FCM 토큰 대기 중... (retry ${i + 1}/${retrySeconds.length})');
          }
        } catch (e) {
          Logger.error('❌ FCM 토큰 가져오기 실패: $e');
        }
      } catch (e) {
        Logger.error('FCM 토큰 동기화 실패 (재시도 ${i + 1}/${retrySeconds.length})', e);
        // 크래시 방지: 예외를 로그만 남기고 계속 진행
      }
    }

    Logger.log('❌ FCM 토큰 동기화 최종 실패 - 다음 실행에서 재시도');
  }

  // 포그라운드 로컬 알림 표시
  // iOS: 포그라운드에서 자동 배너를 끈 뒤, 필요한 경우만 로컬 알림을 표시한다.
  // Android: 포그라운드에서 FCM notification을 자동 표시하지 않으므로 여기서 처리.
  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      final notification = message.notification;
      final title = notification?.title ?? (message.data['title'] ?? '').toString();
      final body = notification?.body ?? (message.data['body'] ?? '').toString();
      if (title.trim().isEmpty && body.trim().isEmpty) return;

      final type = (message.data['type'] ?? '').toString();
      final String androidChannelId = _isMeetupType(type) ? _channelMeetupId : _channelHighImportanceId;
      final String androidChannelName = _isMeetupType(type) ? _channelMeetupName : _channelHighImportanceName;
      final String androidChannelDesc = _isMeetupType(type)
          ? 'This channel is used for meetup-related notifications.'
          : 'This channel is used for important notifications.';

      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        androidChannelId,
        androidChannelName,
        channelDescription: androidChannelDesc,
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

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        message.hashCode,
        title,
        body,
        details,
        payload: jsonEncode(message.data),
      );

      Logger.log('✅ 로컬 알림 표시 완료');
    } catch (e) {
      Logger.error('❌ 로컬 알림 표시 실패: $e');
    }
  }

  bool _isMeetupType(String type) {
    if (type.isEmpty) return false;
    if (type.startsWith('meetup_')) return true;
    // 서버/클라 타입이 바뀌는 경우를 대비한 안전장치
    switch (type) {
      case 'review_approval_request':
      case 'review_published':
      case 'review_rejected':
        return true;
      default:
        return false;
    }
  }

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
          }).then((_) {
            Logger.log('✅ unregisterFcmToken 완료');
          }, onError: (e) {
            Logger.log('⚠️ unregisterFcmToken 실패(무시): $e');
          }),
        // Firestore에서도 "해당 토큰"만 제거 (다른 기기 토큰은 보존)
        if (token != null && token.isNotEmpty)
          _firestore.runTransaction((tx) async {
            final ref = _firestore.collection('users').doc(userId);
            final snap = await tx.get(ref);
            if (!snap.exists) return;

            final data = snap.data() ?? {};
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
