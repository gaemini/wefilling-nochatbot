// lib/services/fcm_service.dart
// Firebase Cloud Messaging(FCM) 관련 기능 관리
// 푸시 알림 토큰 관리 및 메시지 처리

import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
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
import '../utils/notification_delivery_policy.dart';
import '../utils/notification_read_policy.dart';
import '../utils/snack_chat_notification_policy.dart';
import '../utils/chat_notification_presentation.dart';
import '../utils/chat_work_queue.dart';
import 'dart:io';

const String _pushSessionUserIdPreferenceKey = 'active_push_session_user_id';
const String _snackNotificationGroupPreferencePrefix =
    'snack_notification_group_key:';
const String _snackNotificationSequencePreferencePrefix =
    'snack_notification_sequence:';
const String _dmNotificationSentAtPreferencePrefix = 'dm_notification_sent_at:';

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

    final snackChatId = (message.data['snackChatId'] ?? '').toString().trim();
    final notificationGroupKey = (message.data['notificationThreadKey'] ??
            message.data['notificationGroupKey'] ??
            '')
        .toString()
        .trim();
    if (snackChatId.isNotEmpty && notificationGroupKey.isNotEmpty) {
      await preferences.setString(
        '$_snackNotificationGroupPreferencePrefix$snackChatId',
        notificationGroupKey,
      );
      final sequence = int.tryParse(
            (message.data['messageSequence'] ?? '').toString(),
          ) ??
          0;
      final sequenceKey =
          '$_snackNotificationSequencePreferencePrefix$recipientUserId::$snackChatId';
      final previousSequence = preferences.getInt(sequenceKey) ?? 0;
      if (sequence > previousSequence) {
        await preferences.setInt(sequenceKey, sequence);
      }
    }
    final conversationId =
        (message.data['conversationId'] ?? '').toString().trim();
    if ((message.data['type'] ?? '').toString() == 'dm_received' &&
        conversationId.isNotEmpty) {
      final sentAtMillis = int.tryParse(
            (message.data['sentAtMillis'] ?? '').toString(),
          ) ??
          0;
      final sentAtKey =
          '$_dmNotificationSentAtPreferencePrefix$recipientUserId::$conversationId';
      final previousSentAt = preferences.getInt(sentAtKey) ?? 0;
      if (sentAtMillis > previousSentAt) {
        await preferences.setInt(sentAtKey, sentAtMillis);
      }
    }

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
  static int _sessionEpoch = 0;
  static int _activeEpoch = 0;
  static Completer<void>? _appActiveCompleter;
  static AppLifecycleListener? _appLifecycleListener;
  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<RemoteMessage>? _onMessageSub;
  static StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;
  static final _chatPreviewHistory = ChatNotificationPreviewHistory();
  static final _notificationWrites = ChatWorkQueue();
  static final SnackChatNotificationBurstGate _snackChatNotificationGate =
      SnackChatNotificationBurstGate();
  static const MethodChannel _notificationCenterChannel =
      MethodChannel('com.wefilling.app/notification_center');

  static const String _channelHighImportanceId = 'high_importance_channel';
  static const String _channelHighImportanceName =
      'High Importance Notifications';
  static const String _channelMeetupId = 'meetup_notifications';
  static const String _channelMeetupName = 'Meetup Notifications';

  Future<void> _waitUntilAppActive(int epoch) async {
    if (Logger.isVerboseEnabled)
      Logger.log('🔍 [FCM 진단] _waitUntilAppActive 시작');
    if (Logger.isVerboseEnabled)
      Logger.log(
          '  - 현재 lifecycleState: ${WidgetsBinding.instance.lifecycleState}');

    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      if (Logger.isVerboseEnabled) Logger.log('🔍 [FCM 진단] 앱이 이미 resumed 상태');
      return;
    }

    if (Logger.isVerboseEnabled)
      Logger.log('🔍 [FCM 진단] 앱이 resumed 될 때까지 대기 중...');
    _appActiveCompleter ??= Completer<void>();
    _appLifecycleListener ??= AppLifecycleListener(
      onResume: () {
        if (Logger.isVerboseEnabled) Logger.log('🔍 [FCM 진단] onResume 콜백 호출됨');
        if (!(_appActiveCompleter?.isCompleted ?? true)) {
          _appActiveCompleter?.complete();
        }
        unawaited(_replayConfirmedNotificationReads());
      },
    );

    await _appActiveCompleter!.future;
    if (Logger.isVerboseEnabled) Logger.log('🔍 [FCM 진단] 앱 resumed 대기 완료');

    if (epoch != _activeEpoch) {
      if (Logger.isVerboseEnabled)
        Logger.log('🔍 [FCM 진단] stale epoch 감지 - 중단');
      throw StateError('stale epoch while waiting app active');
    }
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
        if (Logger.isVerboseEnabled)
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
      if (Logger.isVerboseEnabled)
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
    _snackChatNotificationGate.clear();
    _chatPreviewHistory.clear();
    _confirmedNotificationReads.clear();
    _cleanupFailures.clear();
    _initializingFuture = null;
    _initializedUserId = null;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_pushSessionUserIdPreferenceKey);
    } catch (e) {
      Logger.error('푸시 세션 사용자 초기화 실패', e);
    }
  }

  // locale 안전성 검증
  Future<void> _ensureLocaleInitialized() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLocale = prefs.getString('app_language');

      if (savedLocale == null || savedLocale.isEmpty) {
        // 기본 언어 강제 설정
        await prefs.setString('app_language', 'ko');
        if (Logger.isVerboseEnabled) Logger.log('✅ locale 기본값 설정: ko');
      } else {
        if (Logger.isVerboseEnabled) Logger.log('✅ locale 확인됨: $savedLocale');
      }
    } catch (e) {
      Logger.error('locale 초기화 실패 (무시)', e);
    }
  }

  // FCM 초기화
  Future<void> initialize(String userId) async {
    if (_initializedUserId == userId) {
      if (Logger.isVerboseEnabled)
        Logger.log('ℹ️ FCM 초기화 스킵: 동일 세션 사용자($userId)');
      return;
    }

    if (_initializingFuture != null) {
      await _initializingFuture;
      if (_initializedUserId == userId) {
        if (Logger.isVerboseEnabled)
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
    final completer = Completer<void>();
    _initializingFuture = completer.future;

    try {
      // locale 안전성 검증 (Firebase Messaging 초기화 전 필수)
      try {
        await _languageService.initializeLanguage();
        await _ensureLocaleInitialized();
      } catch (e) {
        Logger.error('locale 초기화 실패 - 계속 진행', e);
      }

      if (_isStaleEpoch(epoch)) {
        if (Logger.isVerboseEnabled)
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
            if (Logger.isVerboseEnabled) Logger.log('✅ iOS 알림 권한 승인됨');
          } else if (settings.authorizationStatus ==
              AuthorizationStatus.provisional) {
            if (Logger.isVerboseEnabled) Logger.log('✅ iOS 알림 권한 Provisional');
          } else {
            if (Logger.isVerboseEnabled)
              Logger.log('❌ iOS 알림 권한 거부됨 - FCM 기능 제한 (앱은 계속 실행)');
            _initializedUserId = userId;
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
            // Foreground display and sound are both owned by the local
            // notification path below. Leaving system sound enabled here can
            // play once from APNs and once again from the local notification.
            sound: false,
          )
              .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              if (Logger.isVerboseEnabled) Logger.log('⏱️ 포그라운드 설정 타임아웃');
            },
          );
        } catch (e) {
          Logger.error('포그라운드 설정 실패 - 계속 진행', e);
        }
      }

      if (_isStaleEpoch(epoch)) {
        if (Logger.isVerboseEnabled)
          Logger.log('⏭️ FCM 초기화 중단: stale epoch(listener_setup)');
        completer.complete();
        return;
      }

      // APNs가 늦게 준비되더라도 메시지 리스너는 즉시 연결한다. 토큰 동기화는
      // 아래 재시도 루프에서 독립적으로 APNs 준비를 기다린다.
      _initializedUserId = userId;
      _startTokenSync(userId, epoch);
      _appLifecycleListener ??= AppLifecycleListener(onResume: () {
        if (!(_appActiveCompleter?.isCompleted ?? true))
          _appActiveCompleter?.complete();
        unawaited(_replayConfirmedNotificationReads());
      });
      unawaited(_replayConfirmedNotificationReads());

      // 토큰 갱신 리스너 등록
      try {
        await _tokenRefreshSub?.cancel();
        _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
          if (_isStaleEpoch(epoch) || _initializedUserId != userId) {
            if (Logger.isVerboseEnabled)
              Logger.log('⏭️ 토큰 갱신 이벤트 무시: stale epoch/user');
            return;
          }
          if (Logger.isVerboseEnabled) {
            Logger.log('📱 FCM 토큰 갱신됨 (length=${newToken.length})');
          }
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
            if (_isStaleEpoch(epoch) || _initializedUserId != userId) {
              if (Logger.isVerboseEnabled) {
                Logger.log('⏭️ 이전 로그인 세션의 포어그라운드 푸시 무시');
              }
              return;
            }
            // ✅ 포그라운드 알림 정책:
            // - iOS는 위에서 alert=false로 해뒀기 때문에, 여기서 로컬 알림을 "선택적으로" 띄운다.
            // - DM 채팅방을 보고 있는 경우(해당 conversationId 활성) DM 알림은 띄우지 않는다.
            final type = (message.data['type'] ?? '').toString();
            final recipientUserId =
                (message.data['recipientUserId'] ?? '').toString().trim();
            if (recipientUserId.isNotEmpty && recipientUserId != userId) {
              if (Logger.isVerboseEnabled)
                Logger.log('⏭️ 이전 계정 대상 포어그라운드 푸시 무시');
              return;
            }
            final conversationId =
                (message.data['conversationId'] ?? '').toString();
            final snackChatId = (message.data['snackChatId'] ?? '').toString();
            if (Logger.isVerboseEnabled) {
              Logger.log(
                '📱 포어그라운드 푸시 수신: type=$type '
                'roomId=$snackChatId messageId=${message.data['messageId'] ?? message.messageId ?? ''}',
              );
            }
            final isDm = type == 'dm_received' && conversationId.isNotEmpty;
            final isSnackChat =
                type == 'snack_chat_message' && snackChatId.isNotEmpty;

            if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
              final isActiveConversation =
                  (isDm && DMActiveConversation.isActive(conversationId)) ||
                      (isSnackChat &&
                          SnackChatActiveConversation.isActive(snackChatId));

              if (isActiveConversation) {
                // Foreground delivery is suppressed here. The OS card is
                // removed only after the room's server read call returns its
                // authoritative boundary, so a newer push cannot be erased.
                return;
              }

              final badgeStr = (message.data['badge'] ?? '').toString();
              if (_wasAlreadyConfirmedRead(message.data, userId)) {
                unawaited(_reconcileReceivedNotification(
                    message.data, userId, epoch));
                return;
              }
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
            if (_isStaleEpoch(epoch) || _initializedUserId != userId) {
              if (Logger.isVerboseEnabled) {
                Logger.log('⏭️ 이전 로그인 세션의 푸시 딥링크 무시');
              }
              return;
            }
            if (Logger.isVerboseEnabled) {
              Logger.log(
                '📱 백그라운드 푸시로 앱 열림: '
                'type=${message.data['type'] ?? ''} '
                'roomId=${message.data['snackChatId'] ?? ''} '
                'messageId=${message.data['messageId'] ?? message.messageId ?? ''}',
              );
            }
            final recipientUserId =
                (message.data['recipientUserId'] ?? '').toString().trim();
            if (recipientUserId.isNotEmpty && recipientUserId != userId) {
              if (Logger.isVerboseEnabled) Logger.log('⏭️ 이전 계정 대상 푸시 딥링크 무시');
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
            if (Logger.isVerboseEnabled)
              Logger.log('⏱️ getInitialMessage 타임아웃');
            return null;
          },
        );
        if (initialMessage != null) {
          if (_isStaleEpoch(epoch) || _initializedUserId != userId) {
            if (Logger.isVerboseEnabled) {
              Logger.log('⏭️ 이전 로그인 세션의 초기 푸시 딥링크 무시');
            }
            completer.complete();
            return;
          }
          if (Logger.isVerboseEnabled) {
            Logger.log(
              '📱 종료 상태 푸시로 앱 열림: '
              'type=${initialMessage.data['type'] ?? ''} '
              'roomId=${initialMessage.data['snackChatId'] ?? ''} '
              'messageId=${initialMessage.data['messageId'] ?? initialMessage.messageId ?? ''}',
            );
          }
          final recipientUserId =
              (initialMessage.data['recipientUserId'] ?? '').toString().trim();
          if (recipientUserId.isEmpty || recipientUserId == userId) {
            await NavigationService.handlePushNavigation(initialMessage.data);
          } else {
            if (Logger.isVerboseEnabled) Logger.log('⏭️ 이전 계정 대상 초기 푸시 딥링크 무시');
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
        if (Logger.isVerboseEnabled)
          Logger.log('⏭️ 토큰 동기화 중단: stale epoch (현재=$_activeEpoch, 요청=$epoch)');
        return;
      }
      if (_initializedUserId != userId) {
        if (Logger.isVerboseEnabled)
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
                if (Logger.isVerboseEnabled)
                  Logger.log(
                      '⚠️ APNs 토큰 대기 중... (retry ${i + 1}/${retrySeconds.length})');
              }
              continue;
            } else {
              if (Logger.isVerboseEnabled) {
                Logger.log('📱 APNs 토큰 준비됨 (length=${apnsToken.length})');
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
            if (Logger.isVerboseEnabled) {
              Logger.log('📱 FCM 토큰 준비됨 (length=${token.length})');
            }
            await _saveFCMToken(userId, token);
            return;
          }
          if (shouldLogRetry) {
            if (Logger.isVerboseEnabled)
              Logger.log(
                  '⚠️ FCM 토큰 대기 중... (retry ${i + 1}/${retrySeconds.length})');
          }
        } catch (e) {
          Logger.error('❌ FCM 토큰 가져오기 실패: $e');
        }
      } catch (e) {
        if (i == retrySeconds.length - 1) {
          Logger.error('FCM 토큰 동기화 최종 실패', e);
        } else {
          if (Logger.isVerboseEnabled) Logger.warning('FCM 토큰 동기화 재시도 예정');
        }
        // 크래시 방지: 예외를 로그만 남기고 계속 진행
      }
    }

    if (Logger.isVerboseEnabled) Logger.log('❌ FCM 토큰 동기화 최종 실패 - 다음 실행에서 재시도');
  }

  // 포그라운드 로컬 알림 표시
  // iOS: 포그라운드에서 자동 배너를 끈 뒤, 필요한 경우만 로컬 알림을 표시한다.
  // Android: 포그라운드에서 FCM notification을 자동 표시하지 않으므로 여기서 처리.
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final owner = FirebaseAuth.instance.currentUser?.uid ?? '';
    final epoch = _activeEpoch;
    final type = (message.data['type'] ?? '').toString();
    final room = (message.data[type == 'snack_chat_message'
                ? 'snackChatId'
                : 'conversationId'] ??
            '')
        .toString()
        .trim();
    if (type != 'snack_chat_message' && type != 'dm_received') {
      return _renderLocalNotification(message, owner, epoch);
    }
    await _notificationWrites.run('$owner:$type:$room',
        () => _renderLocalNotification(message, owner, epoch));
  }

  Future<void> _renderLocalNotification(
      RemoteMessage message, String owner, int epoch) async {
    if (owner.isEmpty ||
        _isStaleEpoch(epoch) ||
        FirebaseAuth.instance.currentUser?.uid != owner) return;
    final recipient = (message.data['recipientUserId'] ?? '').toString().trim();
    if (recipient.isNotEmpty && recipient != owner) return;
    if (_wasAlreadyConfirmedRead(message.data, owner)) {
      unawaited(_reconcileReceivedNotification(message.data, owner, epoch));
      return;
    }
    try {
      final notification = message.notification;
      var title =
          notification?.title ?? (message.data['title'] ?? '').toString();
      var body = notification?.body ?? (message.data['body'] ?? '').toString();
      if (title.trim().isEmpty && body.trim().isEmpty) return;

      final type = (message.data['type'] ?? '').toString();
      final snackChatId = (message.data['snackChatId'] ?? '').toString().trim();
      final isGroupedSnackChat =
          type == 'snack_chat_message' && snackChatId.isNotEmpty;
      final presentation = ChatNotificationPresentation.parse(message.data,
          owner: owner,
          fallbackTitle: title,
          fallbackBody: body,
          fallbackEventId: message.messageId ?? '',
          fallbackSentAtMillis: message.sentTime?.millisecondsSinceEpoch ?? 0);
      final isGroupedChat = presentation != null;
      final notificationId =
          (message.data['notificationId'] ?? '').toString().trim();
      final notificationGroupKey = (message.data['notificationThreadKey'] ??
              message.data['notificationGroupKey'] ??
              '')
          .toString()
          .trim();
      final effectiveGroupKey = presentation?.roomKey ??
          (notificationGroupKey.isNotEmpty
              ? notificationGroupKey
              : 'snack_$snackChatId');
      var shouldAlert = true;
      if (isGroupedChat) {
        final eventId = (message.data['notificationEventId'] ??
                message.data['messageId'] ??
                message.messageId ??
                '')
            .toString();
        final sentAtMillis = presentation.sentAtMillis;
        final decision = _snackChatNotificationGate.evaluate(
          roomKey: effectiveGroupKey,
          eventId: eventId,
          sentAtMillis: sentAtMillis,
        );
        if (!decision.shouldDisplay) return;
        shouldAlert = isGroupedSnackChat ? decision.shouldAlert : true;
      }
      final unreadCount = int.tryParse(
        (message.data['roomUnreadCount'] ?? message.data['unreadCount'] ?? '')
            .toString(),
      );
      final String androidChannelId =
          _isMeetupType(type) ? _channelMeetupId : _channelHighImportanceId;
      final String androidChannelName =
          _isMeetupType(type) ? _channelMeetupName : _channelHighImportanceName;
      final String androidChannelDesc = _isMeetupType(type)
          ? 'This channel is used for meetup-related notifications.'
          : 'This channel is used for important notifications.';

      StyleInformation? expandedStyle;
      String? subtitle;
      if (chatPushPresentationV2 && presentation != null) {
        try {
          final history = _chatPreviewHistory.append(presentation);
          expandedStyle =
              buildChatMessagingStyle(presentation, history, owner: owner);
          title = presentation.title;
          body = presentation.isGroup && presentation.sender.isNotEmpty
              ? '${presentation.sender}: ${presentation.text}'
              : presentation.text;
          subtitle = presentation.subtitle;
        } catch (error) {
          // Only preparation failure falls back, before any platform post.
          Logger.error('Chat notification presentation fallback: $error');
        }
      }
      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        androidChannelId,
        androidChannelName,
        channelDescription: androidChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: shouldAlert,
        playSound: shouldAlert,
        silent: isGroupedChat && !shouldAlert,
        styleInformation: expandedStyle,
        subText: subtitle,
        onlyAlertOnce: isGroupedSnackChat,
        tag: isGroupedChat
            ? effectiveGroupKey
            : notificationId.isNotEmpty
                ? appNotificationAndroidTag(notificationId)
                : null,
        groupKey: isGroupedSnackChat ? snackChatAndroidGroupKey : null,
        // Keep the existing launcher/count policy. DM's compact count belongs
        // in subText, not a newly introduced Android badge count.
        number: isGroupedSnackChat ? unreadCount : null,
      );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: shouldAlert,
        threadIdentifier: isGroupedChat ? effectiveGroupKey : null,
        subtitle: subtitle,
      );

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      if (isGroupedSnackChat) {
        try {
          final preferences = await SharedPreferences.getInstance();
          await preferences.setString(
            '$_snackNotificationGroupPreferencePrefix$snackChatId',
            effectiveGroupKey,
          );
          final sequence = int.tryParse(
                (message.data['messageSequence'] ?? '').toString(),
              ) ??
              0;
          final sequenceKey =
              '$_snackNotificationSequencePreferencePrefix$owner::$snackChatId';
          final previousSequence = preferences.getInt(sequenceKey) ?? 0;
          if (sequence > previousSequence) {
            await preferences.setInt(sequenceKey, sequence);
          }
        } catch (error) {
          Logger.error('Notification grouping metadata save failed: $error');
        }
      }
      if (presentation != null && !presentation.isGroup) {
        final conversationId =
            (message.data['conversationId'] ?? '').toString().trim();
        if (conversationId.isNotEmpty && presentation.sentAtMillis > 0) {
          try {
            final preferences = await SharedPreferences.getInstance();
            final sentAtKey =
                '$_dmNotificationSentAtPreferencePrefix$owner::$conversationId';
            final previousSentAt = preferences.getInt(sentAtKey) ?? 0;
            if (presentation.sentAtMillis > previousSentAt) {
              await preferences.setInt(sentAtKey, presentation.sentAtMillis);
            }
          } catch (error) {
            Logger.error('DM notification metadata save failed: $error');
          }
        }
      }
      if (_isStaleEpoch(epoch) ||
          FirebaseAuth.instance.currentUser?.uid != owner) return;
      if (presentation != null &&
          (presentation.isGroup
              ? SnackChatActiveConversation.isActive(snackChatId)
              : DMActiveConversation.isActive(
                  (message.data['conversationId'] ?? '').toString()))) return;

      await _localNotifications.show(
        isGroupedChat
            ? (!kIsWeb && Platform.isAndroid
                // FirebaseMessaging's Android automatic renderer always posts
                // a tagged remote notification with id 0. Matching that exact
                // (tag, id) pair prevents a foreground-created card and a later
                // background-created card from coexisting for the same room.
                ? snackChatAndroidFcmNotificationId
                : isGroupedSnackChat
                    ? stableSnackChatNotificationId(
                        'snack_chat:$effectiveGroupKey')
                    : dmLocalNotificationId(effectiveGroupKey))
            : (!kIsWeb && Platform.isAndroid && notificationId.isNotEmpty)
                ? androidRemoteNotificationId
                : message.hashCode,
        title,
        body,
        details,
        payload: jsonEncode(message.data),
      );

      if (Logger.isVerboseEnabled) Logger.log('✅ 로컬 알림 표시 완료');
      unawaited(_reconcileReceivedNotification(message.data, owner, epoch));
    } catch (e) {
      Logger.error('❌ 로컬 알림 표시 실패: $e');
    }
  }

  /// Capture before starting a read, not after its network response.
  bool _wasAlreadyConfirmedRead(Map<String, dynamic> data, String owner) {
    final type = data['type'];
    final kind = type == 'snack_chat_message'
        ? 'snack_chat'
        : type == 'dm_received'
            ? 'dm'
            : type == 'ad_updates'
                ? 'ad'
                : 'app';
    final target = kind == 'snack_chat'
        ? data['snackChatId']
        : kind == 'dm'
            ? data['conversationId']
            : data['notificationId'];
    final receipt = _confirmedNotificationReads['$owner:$kind:$target'];
    return receipt != null &&
        notificationPayloadWasConfirmedRead(data, receipt, owner);
  }

  Future<void> _reconcileReceivedNotification(
      Map<String, dynamic> data, String owner, int epoch) async {
    try {
      if (!isNotificationSession(owner, epoch)) return;
      final type = data['type']?.toString();
      final id = data['notificationId']?.toString() ?? '';
      if (id.isNotEmpty && type != 'ad_updates') {
        final collection = type == 'personalTodoReminder'
            ? 'todoNotificationDeliveries'
            : 'notifications';
        final doc = await FirebaseFirestore.instance
            .collection(collection)
            .doc(id)
            .get(const GetOptions(source: Source.server));
        if (doc.data()?['userId'] == owner && doc.data()?['isRead'] == true) {
          await cancelAppNotification(id,
              expectedOwner: owner, expectedSession: epoch);
          if (isNotificationSession(owner, epoch))
            unawaited(BadgeService.refreshNow());
        }
      } else {
        final kind = type == 'ad_updates'
            ? 'ad'
            : type == 'snack_chat_message'
                ? 'snack_chat'
                : 'dm';
        final target = id.isNotEmpty
            ? id
            : data[kind == 'snack_chat' ? 'snackChatId' : 'conversationId'];
        final request = _confirmedNotificationReads['$owner:$kind:$target'];
        if (request != null) {
          await _runNotificationCleanup(owner, epoch, Map.of(request),
              remember: false);
          if (_wasAlreadyConfirmedRead(data, owner) &&
              isNotificationSession(owner, epoch)) {
            unawaited(BadgeService.refreshNow());
          }
        }
      }
    } catch (error) {
      // Delivery and sound never depend on this best-effort read check.
      Logger.error('지연 푸시 읽음 대조 실패', error);
    }
  }

  int get notificationSession => _activeEpoch;

  bool isNotificationSession(String owner, int session) =>
      !_isStaleEpoch(session) &&
      FirebaseAuth.instance.currentUser?.uid == owner;

  /// Removes only the local notification slot associated with [snackChatId].
  /// Android uses FCM's id 0 plus the server-issued stable room tag. iOS uses a
  /// deterministic local id; APNs keeps remote deliveries grouped/collapsed by
  /// the same room key.
  Future<void> cancelSnackChatNotification(
    String snackChatId, {
    String? notificationGroupKey,
    int? throughSequence,
    String? expectedOwner,
    int? expectedSession,
  }) async {
    final normalized = snackChatId.trim();
    final owner = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final epoch = _activeEpoch;
    if (normalized.isEmpty || owner.isEmpty || kIsWeb) return;
    if ((expectedOwner != null && expectedOwner != owner) ||
        (expectedSession != null && expectedSession != epoch)) return;
    await _notificationWrites.run(
        '$owner:snack_chat_message:$normalized',
        () => _cancelSnackChatNotification(normalized, owner, epoch,
            notificationGroupKey: notificationGroupKey,
            throughSequence: throughSequence));
  }

  Future<void> _cancelSnackChatNotification(
    String room,
    String owner,
    int epoch, {
    String? notificationGroupKey,
    int? throughSequence,
  }) async {
    if (!isNotificationSession(owner, epoch)) return;
    await _runNotificationCleanup(
        owner,
        epoch,
        {
          'kind': 'snack_chat',
          'roomId': room,
          'throughSequence': throughSequence ?? 0,
          'removeAllInRoom': throughSequence == null,
          'androidTag': snackChatNotificationGroupKey(
              recipientUserId: owner, snackChatId: room),
        },
        remember: throughSequence != null);
  }

  Future<void> cancelAdNotification(String bannerId, String version) async {
    final owner = FirebaseAuth.instance.currentUser?.uid ?? '';
    final epoch = _activeEpoch;
    if (owner.isEmpty || bannerId.isEmpty || version.isEmpty) return;
    await _runNotificationCleanup(owner, epoch, {
      'kind': 'ad',
      'bannerId': bannerId,
      'version': version,
      'notificationId': 'ad:$bannerId:$version',
      'androidTag': appNotificationAndroidTag('ad:$bannerId:$version'),
    });
  }

  Future<void> cancelPersonalTodoNotification(
    String todoId, {
    required String expectedOwner,
    required int expectedSession,
  }) async {
    // Local scheduled deliveries use the device's OS delivery clock, not a
    // chat/server read watermark. Never persist this recurring-slot request.
    final boundary = DateTime.now().millisecondsSinceEpoch;
    await _runNotificationCleanup(
        expectedOwner,
        expectedSession,
        {
          'kind': 'todo_local',
          'todoId': todoId,
          'roomId': todoId,
          'throughDeliveredAtMillis': boundary,
        },
        remember: false);
  }

  Future<void> cancelAppNotification(
    String notificationId, {
    String? expectedOwner,
    int? expectedSession,
  }) async {
    final owner = expectedOwner ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    final epoch = expectedSession ?? _activeEpoch;
    if (notificationId.trim().isEmpty || !isNotificationSession(owner, epoch))
      return;
    await _runNotificationCleanup(owner, epoch, {
      'kind': 'app',
      'notificationId': notificationId.trim(),
      'androidTag': appNotificationAndroidTag(notificationId),
    });
  }

  Future<void> cancelAppNotifications(
    Iterable<String> notificationIds, {
    required String expectedOwner,
    required int expectedSession,
    bool remember = true,
  }) async {
    final ids = notificationIds.where((id) => id.isNotEmpty).toSet().toList()
      ..sort();
    if (ids.isEmpty || !isNotificationSession(expectedOwner, expectedSession))
      return;
    await _notificationWrites.run('$expectedOwner:app:cleanup', () async {
      if (!isNotificationSession(expectedOwner, expectedSession)) return;
      if (remember) {
        for (final id in ids) {
          _confirmedNotificationReads['$expectedOwner:app:$id'] = {
            'kind': 'app',
            'notificationId': id,
            'androidTag': appNotificationAndroidTag(id),
            'ownerUserId': expectedOwner,
            'confirmedAt': DateTime.now().millisecondsSinceEpoch,
          };
        }
        try {
          final prefs = await SharedPreferences.getInstance();
          if (!isNotificationSession(expectedOwner, expectedSession)) return;
          await prefs.setString(
              'confirmed_push_reads::$expectedOwner',
              jsonEncode(_confirmedNotificationReads.values
                  .where((item) => item['ownerUserId'] == expectedOwner)
                  .toList()));
        } catch (error) {
          Logger.error('읽음 알림 복구 메타데이터 저장 실패', error);
        }
      }
      for (var offset = 0; offset < ids.length; offset += 450) {
        final portion =
            ids.sublist(offset, (offset + 450).clamp(0, ids.length));
        await _runNotificationCleanup(
            expectedOwner,
            expectedSession,
            {
              'kind': 'app',
              'notificationIds': portion,
              'notificationId':
                  'batch:${appNotificationAndroidTag(portion.join(','))}',
              'androidTags': portion.map(appNotificationAndroidTag).toList(),
            },
            remember: false);
      }
    });
  }

  Future<void> cancelDmNotification(
    String conversationId, {
    String? notificationGroupKey,
    int? throughSentAtMillis,
    int throughSeconds = 0,
    int throughNanos = 0,
    String? expectedOwner,
    int? expectedSession,
  }) async {
    final owner = expectedOwner ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    final epoch = expectedSession ?? _activeEpoch;
    if (conversationId.isEmpty ||
        (throughSentAtMillis ?? 0) <= 0 ||
        !isNotificationSession(owner, epoch)) return;
    await _notificationWrites.run(
        '$owner:dm_received:$conversationId',
        () => _runNotificationCleanup(owner, epoch, {
              'kind': 'dm',
              'roomId': conversationId,
              'throughSentAtMillis': throughSentAtMillis!,
              'throughSeconds': throughSeconds,
              'throughNanos': throughNanos,
              'androidTag': dmNotificationAndroidTag(
                  recipientUserId: owner, conversationId: conversationId),
            }));
  }

  // Confirmed reads are not cleanup successes. Keep the immutable requests so
  // a delayed remote delivery can be checked again on the next lifecycle event.
  final Map<String, Map<String, dynamic>> _confirmedNotificationReads = {};
  final Map<String, int> _cleanupFailures = {};
  int? _cleanupReplaySession;

  Future<void> _runNotificationCleanup(
      String owner, int epoch, Map<String, dynamic> request,
      {bool remember = true}) async {
    if (!isNotificationSession(owner, epoch) || kIsWeb) return;
    final key =
        '$owner:${request['kind']}:${request['notificationId'] ?? request['roomId']}';
    if (!remember && (_cleanupFailures[key] ?? 0) >= 3) return;
    if (remember) {
      final previous = _confirmedNotificationReads[key];
      if (previous != null) {
        final oldSeconds = (previous['throughSeconds'] as num?)?.toInt() ?? 0;
        final newSeconds = (request['throughSeconds'] as num?)?.toInt() ?? 0;
        final oldNanos = (previous['throughNanos'] as num?)?.toInt() ?? 0;
        final newNanos = (request['throughNanos'] as num?)?.toInt() ?? 0;
        if (oldSeconds > newSeconds ||
            (oldSeconds == newSeconds && oldNanos > newNanos)) {
          request['throughSeconds'] = oldSeconds;
          request['throughNanos'] = oldNanos;
        }
        for (final field in ['throughSequence', 'throughSentAtMillis']) {
          final old = (previous[field] as num?)?.toInt() ?? 0;
          if (old > ((request[field] as num?)?.toInt() ?? 0))
            request[field] = old;
        }
      }
      _confirmedNotificationReads[key] = {
        ...request,
        'ownerUserId': owner,
        'confirmedAt': DateTime.now().millisecondsSinceEpoch,
      };
      final oldest = DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;
      _confirmedNotificationReads.removeWhere((_, entry) =>
          ((entry['confirmedAt'] as num?)?.toInt() ?? 0) < oldest);
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!isNotificationSession(owner, epoch)) return;
        final room = request['roomId']?.toString() ?? '';
        final kind = request['kind'];
        final coveredPreview = kind == 'snack_chat'
            ? canCancelSnackChatNotificationThrough(
                latestNotificationSequence: prefs.getInt(
                        '$_snackNotificationSequencePreferencePrefix$owner::$room') ??
                    0,
                readThroughSequence:
                    (request['throughSequence'] as num?)?.toInt() ?? 0)
            : kind == 'dm' &&
                canCancelDmNotificationThrough(
                    latestNotificationSentAtMillis: prefs.getInt(
                            '$_dmNotificationSentAtPreferencePrefix$owner::$room') ??
                        0,
                    readThroughAtMillis:
                        (request['throughSentAtMillis'] as num?)?.toInt() ?? 0);
        if (coveredPreview) {
          final tag = request['androidTag'] as String;
          // Confirmed read projection, not an OS-cleanup completion flag.
          _snackChatNotificationGate.clearRoom(tag);
          _chatPreviewHistory.clearRoom(tag);
        }
        await prefs.setString(
            'confirmed_push_reads::$owner',
            jsonEncode(_confirmedNotificationReads.values
                .where((entry) => entry['ownerUserId'] == owner)
                .toList()));
      } catch (error) {
        Logger.error('읽음 알림 복구 메타데이터 저장 실패', error);
      }
    }
    if (!isNotificationSession(owner, epoch)) return;
    try {
      final removed = await _notificationCenterChannel.invokeMethod<int>(
          'removeDeliveredNotifications', {'ownerUserId': owner, ...request});
      if (!isNotificationSession(owner, epoch)) return;
      if (removed == null) throw StateError('Missing native cleanup result');
      _cleanupFailures.remove(key);
      if (removed < 0) Logger.log('OS 알림 메타데이터 부족: ${request['kind']}');
      if (removed == 0 && Logger.isVerboseEnabled)
        Logger.log('OS 알림 선택 제거: 대상 없음');
    } on MissingPluginException {
      _cleanupFailures[key] = 3;
      Logger.log('OS 선택 제거 미지원: 새 네이티브 빌드 필요');
    } on PlatformException catch (error) {
      if (!isNotificationSession(owner, epoch)) return;
      if (error.code == 'notification-removal-unsupported') {
        _cleanupFailures[key] = 3;
        Logger.log('OS 알림 선택 제거 미지원');
        return;
      }
      _cleanupFailures[key] = (_cleanupFailures[key] ?? 0) + 1;
      // No tag/id fallback: a grouped slot may have been replaced by a newer push.
      Logger.error('OS 알림 제거 실패 (다음 앱 이벤트에서 재확인)', error);
    } catch (error) {
      _cleanupFailures[key] = (_cleanupFailures[key] ?? 0) + 1;
      Logger.error('OS 알림 제거 실패', error);
    }
  }

  Future<void> _replayConfirmedNotificationReads() async {
    if (kIsWeb) return;
    final owner = FirebaseAuth.instance.currentUser?.uid ?? '';
    final epoch = _activeEpoch;
    if (owner.isEmpty || _cleanupReplaySession == epoch) return;
    _cleanupReplaySession = epoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!isNotificationSession(owner, epoch)) return;
      final encoded = prefs.getString('confirmed_push_reads::$owner');
      if (encoded != null) {
        final entries = jsonDecode(encoded) as List;
        final oldest = DateTime.now()
            .subtract(const Duration(days: 30))
            .millisecondsSinceEpoch;
        for (final value in entries) {
          final entry = Map<String, dynamic>.from(value as Map);
          if (entry['ownerUserId'] != owner ||
              ((entry['confirmedAt'] as num?)?.toInt() ?? 0) < oldest) continue;
          final key =
              '$owner:${entry['kind']}:${entry['notificationId'] ?? entry['roomId']}';
          _confirmedNotificationReads.putIfAbsent(key, () => entry);
        }
      }
      final entries = _confirmedNotificationReads.values.toList();
      await cancelAppNotifications(
          entries
              .where((entry) =>
                  entry['ownerUserId'] == owner && entry['kind'] == 'app')
              .map((entry) => entry['notificationId'] as String),
          expectedOwner: owner,
          expectedSession: epoch,
          remember: false);
      for (final entry in entries) {
        if (!isNotificationSession(owner, epoch)) return;
        if (entry['ownerUserId'] != owner) continue;
        if (entry['kind'] == 'app') continue;
        await _runNotificationCleanup(owner, epoch, Map.of(entry),
            remember: false);
      }
    } catch (error) {
      Logger.error('읽음 푸시 재확인 실패', error);
    } finally {
      if (_cleanupReplaySession == epoch) _cleanupReplaySession = null;
    }
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
      if (Logger.isVerboseEnabled)
        Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      if (Logger.isVerboseEnabled) Logger.log('🔍 [FCM 진단 1단계] FCM 토큰 저장 시작');
      if (Logger.isVerboseEnabled) {
        Logger.log('  - token length: ${token.length}');
      }

      // ✅ 서버에서 "토큰 중복(다른 계정에 남아있는 토큰)"을 정리하고,
      //    토큰 단위 locale(lang)까지 함께 저장하도록 Cloud Functions를 우선 사용.
      //    (한국어/영어 알림이 연속으로 2번 오는 문제의 핵심 원인 방지)
      // 푸시 언어도 OS locale이 아니라 앱에서 선택한 언어와 일치시킨다.
      final localeTag = await _languageService.getLanguage();
      if (Logger.isVerboseEnabled) Logger.log('  - locale: $localeTag');

      final String? platform = (() {
        if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
        if (defaultTargetPlatform == TargetPlatform.android) return 'android';
        return null;
      })();
      if (Logger.isVerboseEnabled) Logger.log('  - platform: $platform');

      try {
        if (Logger.isVerboseEnabled)
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
            if (Logger.isVerboseEnabled) Logger.log('⏱️ FCM 토큰 등록 타임아웃 (10초)');
            throw TimeoutException('FCM 토큰 등록 시간 초과');
          },
        );
        if (Logger.isVerboseEnabled)
          Logger.log('✅ FCM 토큰 등록 완료 (서버 정리 + locale 저장)');

        if (Logger.isVerboseEnabled)
          Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        return;
      } catch (e) {
        // 네트워크/함수 오류 시 레거시 방식으로 fallback (토큰은 최소한 저장되도록)
        Logger.error('⚠️ registerFcmToken 실패 - 레거시 저장으로 fallback: $e');
      }

      // fallback: 단일 토큰(fcmToken) + 멀티 토큰(fcmTokens)
      // ⚠️ merge set은 users 문서를 "부분 필드만 가진 상태로 생성"할 수 있으므로 update만 허용한다.
      if (Logger.isVerboseEnabled)
        Logger.log('  - 레거시 방식 (Firestore 직접 update) 시작...');
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (Logger.isVerboseEnabled) Logger.log('✅ FCM 토큰 저장 완료 (레거시 fallback)');
      if (Logger.isVerboseEnabled)
        Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } catch (e) {
      Logger.error('❌ [FCM 진단 1단계] FCM 토큰 저장 실패: $e');
      if (Logger.isVerboseEnabled)
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
          if (Logger.isVerboseEnabled) Logger.log('✅ FCM 토큰 삭제 완료');
        }),
        // 서버 레지스트리에서도 제거 (가능한 경우에만)
        if (token != null && token.isNotEmpty)
          _functions.httpsCallable('unregisterFcmToken').call(<String, dynamic>{
            'token': token,
          }).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              if (Logger.isVerboseEnabled)
                Logger.log('⏱️ FCM 토큰 해제 타임아웃 (10초)');
              throw TimeoutException('FCM 토큰 해제 시간 초과');
            },
          ).then((_) {
            if (Logger.isVerboseEnabled) Logger.log('✅ unregisterFcmToken 완료');
          }, onError: (e) {
            if (Logger.isVerboseEnabled)
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
            if (Logger.isVerboseEnabled)
              Logger.log('✅ Firestore에서 현재 기기 FCM 토큰 제거 완료');
          }),
      ]).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          if (Logger.isVerboseEnabled)
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
      if (Logger.isVerboseEnabled) Logger.log('✅ 토픽 구독 완료: $topic');
    } catch (e) {
      Logger.error('❌ 토픽 구독 실패: $e');
      rethrow;
    }
  }

  // 토픽 구독 취소
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      if (Logger.isVerboseEnabled) Logger.log('✅ 토픽 구독 취소 완료: $topic');
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
