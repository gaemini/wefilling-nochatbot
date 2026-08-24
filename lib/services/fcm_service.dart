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
import 'package:flutter/widgets.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'badge_service.dart';
import 'navigation_service.dart';
import 'dm_active_conversation.dart';
import 'snack_chat_active_conversation.dart';
import 'language_service.dart';
import '../utils/logger.dart';
import 'dart:io';

const String _pushSessionUserIdPreferenceKey = 'active_push_session_user_id';

enum PushInitState {
  idle,
  localeReady,
  sessionReady,
  appActive,
  permissionResolved,
  apnsRegistered,
  tokenSynced,
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    final recipientUserId =
        (message.data['recipientUserId'] ?? '').toString().trim();
    if (recipientUserId.isEmpty) return;

    // A delayed push for the previous account must never overwrite the badge
    // after this device has switched users.
    final preferences = await SharedPreferences.getInstance();
    final activeUserId =
        preferences.getString(_pushSessionUserIdPreferenceKey) ?? '';
    if (activeUserId != recipientUserId) return;

    final badgeStr = message.data['badge'];
    if (badgeStr != null) {
      final badge = int.tryParse(badgeStr.toString());
      if (badge != null && badge >= 0) {
        await AppBadgePlus.updateBadge(badge);
      }
    }
  } catch (_) {}
}

class FCMService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final LanguageService _languageService = LanguageService();

  static Future<void>? _initializingFuture;
  static String? _initializedUserId;
  static PushInitState _state = PushInitState.idle;
  static int _sessionEpoch = 0;
  static int _activeEpoch = 0;
  static Completer<void>? _appActiveCompleter;
  static AppLifecycleListener? _appLifecycleListener;
  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<RemoteMessage>? _onMessageSub;
  static StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;

  static const String _channelHighImportanceId = 'high_importance_channel';
  static const String _channelHighImportanceName =
      'High Importance Notifications';
  static const String _channelMeetupId = 'meetup_notifications';
  static const String _channelMeetupName = 'Meetup Notifications';

  void _setState(PushInitState state, {String? reason}) {
    _state = state;
    final suffix = reason == null ? '' : ' ($reason)';
    Logger.log('🧭 PushInitState: ${state.name}$suffix');
  }

  Future<void> _waitUntilAppActive(int epoch) async {
    Logger.log('🔍 [FCM 진단] _waitUntilAppActive 시작');
    Logger.log(
        '  - 현재 lifecycleState: ${WidgetsBinding.instance.lifecycleState}');

    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _setState(PushInitState.appActive, reason: 'already_resumed');
      Logger.log('🔍 [FCM 진단] 앱이 이미 resumed 상태');
      return;
    }

    Logger.log('🔍 [FCM 진단] 앱이 resumed 될 때까지 대기 중...');
    _appActiveCompleter ??= Completer<void>();
    _appLifecycleListener ??= AppLifecycleListener(
      onResume: () {
        Logger.log('🔍 [FCM 진단] onResume 콜백 호출됨');
        if (!(_appActiveCompleter?.isCompleted ?? true)) {
          _appActiveCompleter?.complete();
        }
      },
    );

    await _appActiveCompleter!.future;
    Logger.log('🔍 [FCM 진단] 앱 resumed 대기 완료');

    if (epoch != _activeEpoch) {
      Logger.log('🔍 [FCM 진단] stale epoch 감지 - 중단');
      throw StateError('stale epoch while waiting app active');
    }
    _setState(PushInitState.appActive, reason: 'resumed');
  }

  bool _isStaleEpoch(int epoch) => epoch != _activeEpoch;

  // 로컬 알림 초기화
  Future<void> _initializeLocalNotifications() async {
    // Android 알림 채널 설정
    const AndroidNotificationChannel highImportanceChannel =
        AndroidNotificationChannel(
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
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
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
            final Map<String, dynamic> data =
                jsonDecode(payload) as Map<String, dynamic>;
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

  // 로그아웃/계정 전환 시 호출
  Future<void> reset() async {
    _sessionEpoch += 1;
    _activeEpoch = _sessionEpoch;
    _appActiveCompleter = null;
    _appLifecycleListener?.dispose();
    _appLifecycleListener = null;

    try {
      await _tokenRefreshSub?.cancel();
      await _onMessageSub?.cancel();
      await _onMessageOpenedAppSub?.cancel();
    } catch (_) {}

    _tokenRefreshSub = null;
    _onMessageSub = null;
    _onMessageOpenedAppSub = null;
    _initializingFuture = null;
    _initializedUserId = null;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_pushSessionUserIdPreferenceKey);
    } catch (e) {
      Logger.error('푸시 세션 사용자 초기화 실패', e);
    }
    _setState(PushInitState.idle, reason: 'reset');
  }

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

  // FCM 초기화
  Future<void> initialize(String userId) async {
    if (_initializedUserId == userId) {
      Logger.log('ℹ️ FCM 초기화 스킵: 동일 세션 사용자($userId)');
      return;
    }

    if (_initializingFuture != null) {
      await _initializingFuture;
      if (_initializedUserId == userId) {
        Logger.log('ℹ️ FCM 초기화 스킵: 초기화 완료됨($userId)');
        return;
      }
    }

    if (_initializedUserId != null && _initializedUserId != userId) {
      await reset();
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_pushSessionUserIdPreferenceKey, userId);
    } catch (e) {
      Logger.error('푸시 세션 사용자 저장 실패', e);
    }

    _sessionEpoch += 1;
    _activeEpoch = _sessionEpoch;
    final int epoch = _activeEpoch;
    _setState(PushInitState.idle, reason: 'initialize_start');

    final completer = Completer<void>();
    _initializingFuture = completer.future;

    try {
      _setState(PushInitState.sessionReady, reason: 'user:$userId');

      // locale 안전성 검증 (Firebase Messaging 초기화 전 필수)
      try {
        await _languageService.initializeLanguage();
        await _ensureLocaleInitialized();
        _setState(PushInitState.localeReady);
      } catch (e) {
        Logger.error('locale 초기화 실패 - 계속 진행', e);
      }

      if (_isStaleEpoch(epoch)) {
        Logger.log('⏭️ FCM 초기화 중단: stale epoch(locale)');
        completer.complete();
        return;
      }

      await _waitUntilAppActive(epoch);

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
            _setState(PushInitState.permissionResolved);
          } else if (settings.authorizationStatus ==
              AuthorizationStatus.provisional) {
            Logger.log('✅ iOS 알림 권한 Provisional');
            _setState(PushInitState.permissionResolved);
          } else {
            Logger.log('❌ iOS 알림 권한 거부됨 - FCM 기능 제한 (앱은 계속 실행)');
            _initializedUserId = userId;
            _setState(PushInitState.permissionResolved);
            completer.complete();
            return; // 권한 없어도 앱은 계속 실행
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
          await _messaging
              .setForegroundNotificationPresentationOptions(
            alert: false,
            badge: false,
            sound: true,
          )
              .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              Logger.log('⏱️ 포그라운드 설정 타임아웃');
            },
          );
        } catch (e) {
          Logger.error('포그라운드 설정 실패 - 계속 진행', e);
        }
      }

      if (_isStaleEpoch(epoch)) {
        Logger.log('⏭️ FCM 초기화 중단: stale epoch(listener_setup)');
        completer.complete();
        return;
      }

      // APNs가 늦게 준비되더라도 메시지 리스너는 즉시 연결한다. 토큰 동기화는
      // 아래 재시도 루프에서 독립적으로 APNs 준비를 기다린다.
      _initializedUserId = userId;
      _startTokenSync(userId, epoch);

      // 토큰 갱신 리스너 등록
      try {
        await _tokenRefreshSub?.cancel();
        _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
          if (_isStaleEpoch(epoch) || _initializedUserId != userId) {
            Logger.log('⏭️ 토큰 갱신 이벤트 무시: stale epoch/user');
            return;
          }
          Logger.log('📱 FCM 토큰 갱신: $newToken');
          _saveFCMToken(userId, newToken);
        });
      } catch (e) {
        Logger.error('토큰 갱신 리스너 등록 실패 - 계속 진행', e);
      }

      // 포어그라운드 메시지 리스너 등록
      try {
        await _onMessageSub?.cancel();
        _onMessageSub =
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
            final recipientUserId =
                (message.data['recipientUserId'] ?? '').toString().trim();
            if (recipientUserId.isNotEmpty && recipientUserId != userId) {
              Logger.log('⏭️ 이전 계정 대상 포어그라운드 푸시 무시');
              return;
            }
            final conversationId =
                (message.data['conversationId'] ?? '').toString();
            final snackChatId = (message.data['snackChatId'] ?? '').toString();
            final isDm = type == 'dm_received' && conversationId.isNotEmpty;
            final isSnackChat =
                type == 'snack_chat_message' && snackChatId.isNotEmpty;

            if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
              final isActiveConversation =
                  (isDm && DMActiveConversation.isActive(conversationId)) ||
                      (isSnackChat &&
                          SnackChatActiveConversation.isActive(snackChatId));

              if (isActiveConversation) {
                return;
              }

              final badgeStr = (message.data['badge'] ?? '').toString();
              final badge = int.tryParse(badgeStr);
              if (badge != null && badge >= 0 && recipientUserId.isNotEmpty) {
                unawaited(BadgeService.applyBadgeFromPush(
                  badge,
                  recipientUserId: recipientUserId,
                ));
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
        await _onMessageOpenedAppSub?.cancel();
        _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp
            .listen((RemoteMessage message) async {
          try {
            Logger.log('📱 백그라운드에서 앱 열림: ${message.messageId}');
            Logger.log('📱 데이터: ${message.data}');
            final recipientUserId =
                (message.data['recipientUserId'] ?? '').toString().trim();
            if (recipientUserId.isNotEmpty && recipientUserId != userId) {
              Logger.log('⏭️ 이전 계정 대상 푸시 딥링크 무시');
              return;
            }
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
        RemoteMessage? initialMessage =
            await _messaging.getInitialMessage().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            Logger.log('⏱️ getInitialMessage 타임아웃');
            return null;
          },
        );
        if (initialMessage != null) {
          Logger.log('📱 앱 종료 상태에서 알림으로 열림: ${initialMessage.messageId}');
          Logger.log('📱 데이터: ${initialMessage.data}');
          final recipientUserId =
              (initialMessage.data['recipientUserId'] ?? '').toString().trim();
          if (recipientUserId.isEmpty || recipientUserId == userId) {
            await NavigationService.handlePushNavigation(initialMessage.data);
          } else {
            Logger.log('⏭️ 이전 계정 대상 초기 푸시 딥링크 무시');
          }
        }
      } catch (e) {
        Logger.error('초기 메시지 처리 실패 - 계속 진행', e);
      }

      completer.complete();
    } catch (e) {
      completer.complete();
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
    } finally {
      _initializingFuture = null;
    }
  }

  void _startTokenSync(String userId, int epoch) {
    // 로그인/초기화 흐름을 막지 않도록 비동기 작업으로 분리
    Future.microtask(() async {
      await _syncTokenWithRetries(userId, epoch);
    });
  }

  Future<void> _syncTokenWithRetries(String userId, int epoch) async {
    const List<int> retrySeconds = [0, 2, 4, 8, 16];

    for (int i = 0; i < retrySeconds.length; i++) {
      if (_isStaleEpoch(epoch)) {
        Logger.log('⏭️ 토큰 동기화 중단: stale epoch (현재=$_activeEpoch, 요청=$epoch)');
        return;
      }
      if (_initializedUserId != userId) {
        Logger.log(
            '⏭️ 토큰 동기화 중단: stale user (현재=$_initializedUserId, 요청=$userId)');
        return;
      }

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
                Logger.log(
                    '⚠️ APNs 토큰 대기 중... (retry ${i + 1}/${retrySeconds.length})');
              }
              continue;
            } else {
              Logger.log('📱 APNs 토큰 준비됨: ${apnsToken.substring(0, 20)}...');
              if (!_isStaleEpoch(epoch) && _initializedUserId == userId) {
                _setState(PushInitState.apnsRegistered);
              }
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
            if (!_isStaleEpoch(epoch) && _initializedUserId == userId) {
              Logger.log(
                  '✅ [FCM] 토큰 동기화 성공 - userId=$userId, token=${token.substring(0, 20)}... (시도 ${i + 1}/${retrySeconds.length})');
              _setState(PushInitState.tokenSynced, reason: 'token_uploaded');
            } else {
              Logger.log('⏭️ [FCM] 토큰 저장 완료 후 stale 감지 - 상태 업데이트 생략');
            }
            return;
          }
          if (shouldLogRetry) {
            Logger.log(
                '⚠️ FCM 토큰 대기 중... (retry ${i + 1}/${retrySeconds.length})');
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
      final title =
          notification?.title ?? (message.data['title'] ?? '').toString();
      final body =
          notification?.body ?? (message.data['body'] ?? '').toString();
      if (title.trim().isEmpty && body.trim().isEmpty) return;

      final type = (message.data['type'] ?? '').toString();
      final snackChatId = (message.data['snackChatId'] ?? '').toString().trim();
      final isGroupedSnackChat =
          type == 'snack_chat_message' && snackChatId.isNotEmpty;
      final notificationGroupKey =
          (message.data['notificationGroupKey'] ?? '').toString().trim();
      final effectiveGroupKey = notificationGroupKey.isNotEmpty
          ? notificationGroupKey
          : 'snack_$snackChatId';
      final unreadCount = int.tryParse(
        (message.data['unreadCount'] ?? '').toString(),
      );
      final String androidChannelId =
          _isMeetupType(type) ? _channelMeetupId : _channelHighImportanceId;
      final String androidChannelName =
          _isMeetupType(type) ? _channelMeetupName : _channelHighImportanceName;
      final String androidChannelDesc = _isMeetupType(type)
          ? 'This channel is used for meetup-related notifications.'
          : 'This channel is used for important notifications.';

      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        androidChannelId,
        androidChannelName,
        channelDescription: androidChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        tag: isGroupedSnackChat ? effectiveGroupKey : null,
        groupKey: isGroupedSnackChat ? effectiveGroupKey : null,
        number: isGroupedSnackChat ? unreadCount : null,
      );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: isGroupedSnackChat ? effectiveGroupKey : null,
      );

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        isGroupedSnackChat
            ? _stableNotificationId('snack_chat:$snackChatId')
            : message.hashCode,
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

  int _stableNotificationId(String value) {
    var hash = 0x811C9DC5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }

  bool _isMeetupType(String type) {
    if (type.isEmpty) return false;
    final normalized = type.toLowerCase();
    if (normalized.startsWith('meetup_') || normalized == 'new_meetup') {
      return true;
    }
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
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Logger.log('🔍 [FCM 진단 1단계] FCM 토큰 저장 시작');
      Logger.log('  - userId: $userId');
      Logger.log('  - token (첫 20자): ${token.substring(0, 20)}...');

      // ✅ 서버에서 "토큰 중복(다른 계정에 남아있는 토큰)"을 정리하고,
      //    토큰 단위 locale(lang)까지 함께 저장하도록 Cloud Functions를 우선 사용.
      //    (한국어/영어 알림이 연속으로 2번 오는 문제의 핵심 원인 방지)
      // 푸시 언어도 OS locale이 아니라 앱에서 선택한 언어와 일치시킨다.
      final localeTag = await _languageService.getLanguage();
      Logger.log('  - locale: $localeTag');

      final String? platform = (() {
        if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
        if (defaultTargetPlatform == TargetPlatform.android) return 'android';
        return null;
      })();
      Logger.log('  - platform: $platform');

      try {
        Logger.log('  - registerFcmToken 함수 호출 시작...');
        // 🔥 iOS 크래시 방지: 네이티브 gRPC 통신에 명시적 타임아웃 추가
        final callable = _functions.httpsCallable('registerFcmToken');
        await callable.call(<String, dynamic>{
          'token': token,
          'locale': localeTag,
          if (platform != null) 'platform': platform,
        }).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            Logger.log('⏱️ FCM 토큰 등록 타임아웃 (10초)');
            throw TimeoutException('FCM 토큰 등록 시간 초과');
          },
        );
        Logger.log('✅ FCM 토큰 등록 완료 (서버 정리 + locale 저장)');

        // 🔍 진단: 실제로 Firestore에 저장되었는지 확인
        try {
          final userDoc =
              await _firestore.collection('users').doc(userId).get();
          if (userDoc.exists) {
            final data = userDoc.data();
            Logger.log('🔍 [FCM 진단 1단계] Firestore 확인:');
            Logger.log('  - fcmToken 존재: ${data?['fcmToken'] != null}');
            Logger.log(
                '  - fcmTokens 길이: ${(data?['fcmTokens'] as List?)?.length ?? 0}');
            Logger.log('  - fcmTokenUpdatedAt: ${data?['fcmTokenUpdatedAt']}');
          } else {
            Logger.log('⚠️ [FCM 진단 1단계] users/{$userId} 문서가 없음!');
          }
        } catch (e) {
          Logger.error('⚠️ [FCM 진단 1단계] Firestore 확인 실패: $e');
        }

        Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        return;
      } catch (e) {
        // 네트워크/함수 오류 시 레거시 방식으로 fallback (토큰은 최소한 저장되도록)
        Logger.error('⚠️ registerFcmToken 실패 - 레거시 저장으로 fallback: $e');
      }

      // fallback: 단일 토큰(fcmToken) + 멀티 토큰(fcmTokens)
      // ⚠️ merge set은 users 문서를 "부분 필드만 가진 상태로 생성"할 수 있으므로 update만 허용한다.
      Logger.log('  - 레거시 방식 (Firestore 직접 update) 시작...');
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
      Logger.log('✅ FCM 토큰 저장 완료 (레거시 fallback)');
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } catch (e) {
      Logger.error('❌ [FCM 진단 1단계] FCM 토큰 저장 실패: $e');
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    }
  }

  /// 언어 변경 직후 현재 토큰의 locale을 서버에 다시 등록한다.
  Future<void> refreshTokenLocale(String userId) async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.trim().isEmpty) return;
      await _saveFCMToken(userId, token);
    } catch (e) {
      Logger.error('⚠️ FCM 토큰 locale 갱신 실패(다음 동기화에서 재시도): $e');
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
          }).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              Logger.log('⏱️ FCM 토큰 해제 타임아웃 (10초)');
              throw TimeoutException('FCM 토큰 해제 시간 초과');
            },
          ).then((_) {
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
