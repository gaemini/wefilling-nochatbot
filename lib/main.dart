// 앱의 시작점
// Firebase 초기화
//프로바이더 설정
// 앱 테마 및 라우팅 설정

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:provider/provider.dart';
import 'design/theme.dart';
import 'screens/main_screen.dart';
import 'screens/edit_meetup_screen.dart';
import 'models/meetup.dart';
import 'providers/auth_provider.dart' as app_auth;
import 'providers/relationship_provider.dart';
import 'screens/login_screen.dart';
import 'screens/nickname_setup_screen.dart';
import 'screens/hanyang_email_verification_screen.dart';
import 'firebase_options.dart';
import 'services/feature_flag_service.dart';
import 'services/fcm_service.dart';
import 'services/language_service.dart';
import 'services/semester_todo_service.dart';
import 'services/cache/cache_manager.dart';
import 'services/cache/app_image_cache_manager.dart';
import 'services/content_translation_service.dart';
import 'l10n/app_localizations.dart';
import 'services/navigation_service.dart';
import 'screens/admin_migration_screen.dart';
import 'services/app_messenger.dart';
import 'services/external_share_service.dart';
import 'services/ios_shared_auth_service.dart';
import 'services/firebase_app_check_service.dart';
import 'services/release_metadata_service.dart';
import 'services/app_update_service.dart';
import 'screens/release_diagnostics_screen.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Android gallery actions must only expose media explicitly selected by
      // the user. This enables Android's system Photo Picker for every
      // image_picker call while leaving the iOS implementation untouched.
      if (!kIsWeb && Platform.isAndroid) {
        final imagePickerImplementation = ImagePickerPlatform.instance;
        if (imagePickerImplementation is ImagePickerAndroid) {
          imagePickerImplementation.useAndroidPhotoPicker = true;
        }
      }

      // 시스템 UI 최적화 (갤럭시 S23 등 최신 Android 기기 대응)
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark, // 라이트모드용
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark, // 라이트모드용
          systemNavigationBarDividerColor: Colors.transparent,
        ),
      );

      // Edge-to-edge 모드 활성화
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      // 화면 회전 제한 (세로 방향만 허용)
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      // 1. Firebase 기본 초기화 (중복 초기화 방지)
      try {
        // Android는 네이티브 google-services 설정을 사용해 빌드 variant의
        // applicationId와 Firebase App ID를 항상 일치시킨다.
        await Firebase.initializeApp(
          options: !kIsWeb && Platform.isAndroid
              ? null
              : DefaultFirebaseOptions.currentPlatform,
        );
        if (kDebugMode) {
          debugPrint('🔥 Firebase 초기화 완료');
        }
      } catch (e) {
        if (e.toString().contains('duplicate-app')) {
          if (kDebugMode) {
            debugPrint('🔥 Firebase는 이미 초기화되어 있습니다.');
          }
        } else {
          if (kDebugMode) {
            debugPrint('🔥 Firebase 초기화 실패: $e');
          }
        }
      }

      // App Check must be activated once before Firestore, Storage, Functions,
      // Messaging, or auth-state driven app initialization can start.
      await FirebaseAppCheckService.instance.initialize();

      // The immutable artifact identity is read before caches, auth routing or
      // app services. A mismatch disables update prompting instead of risking
      // an update against the wrong Store listing.
      await ReleaseMetadataService.instance.initialize();

      // 2. locale 초기화 (비동기로 빠르게 처리)
      try {
        final languageService = LanguageService();
        await languageService.initializeLanguage();
        final lang = await languageService.getLanguage();
        if (kDebugMode) {
          debugPrint('🌐 locale 초기화 완료: $lang');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ locale 초기화 실패 - 기본값 사용: $e');
        }
      }

      // 3. Firebase Messaging 백그라운드 핸들러 등록 (즉시 실행)
      try {
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          FirebaseMessaging.onBackgroundMessage(
              firebaseMessagingBackgroundHandler);
          if (kDebugMode) {
            debugPrint('📱 FCM 백그라운드 핸들러 등록 완료');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Firebase Messaging 핸들러 등록 실패: $e');
        }
      }

      // 4. Crashlytics 설정
      try {
        await FirebaseCrashlytics.instance
            .setCrashlyticsCollectionEnabled(!kDebugMode);

        FlutterError.onError = (FlutterErrorDetails details) {
          try {
            FirebaseCrashlytics.instance.recordFlutterError(details);
          } catch (_) {}
        };

        PlatformDispatcher.instance.onError = (error, stack) {
          try {
            FirebaseCrashlytics.instance
                .recordError(error, stack, fatal: false);
          } catch (_) {}
          return true;
        };

        if (kDebugMode) {
          debugPrint('🐞 Crashlytics 초기화 완료 (debug mode: $kDebugMode)');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Crashlytics 초기화 실패: $e');
        }
      }

      // 6. 캐시 시스템 초기화
      try {
        await CacheManager.initialize(
          releaseMetadata: ReleaseMetadataService.instance.metadata,
        );
        // 명시적으로 cacheManager를 전달하지 않은 썸네일/상세 이미지도
        // 포스트 피드와 같은 디스크 저장소를 사용해 화면 이동 시 재다운로드와
        // 중복 파일 보관이 생기지 않게 한다.
        CachedNetworkImageProvider.defaultCacheManager =
            AppImageCacheManager.instance;
        if (kDebugMode) {
          debugPrint('💾 캐시 시스템 초기화 완료');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ 캐시 시스템 초기화 실패 (앱은 정상 작동): $e');
        }
      }

      // Update policy has a bounded startup budget. Remote Config or Store
      // outages never block login; the service falls back to a paused policy.
      final updateInitialization = AppUpdateService.instance.initialize();
      try {
        await updateInitialization.timeout(const Duration(seconds: 12));
      } on TimeoutException {
        if (kDebugMode) {
          debugPrint('⚠️ 업데이트 정책 확인 지연 - 정상 앱 진입 계속');
        }
      }

      // Release identity, cache migration and update policy are settled before
      // the first Auth read. Existing iOS sessions are then shared safely.
      await IosSharedAuthService.configure();

      // 7. Firebase Auth 및 Firestore 설정 (병렬 처리로 최적화)
      try {
        if (kDebugMode) {
          debugPrint('🔥 Firebase 추가 초기화 시작: ${DateTime.now()}');
          debugPrint(
              '🔥 Firebase 프로젝트 ID: ${Firebase.app().options.projectId}');
          debugPrint(
              '🔥 Firebase Storage 버킷: ${Firebase.app().options.storageBucket}');
        }

        // Firestore 설정 (즉시 실행)
        try {
          if (kDebugMode) {
            debugPrint('🗃️ Firestore 설정 시작');
          }
          // 상세 SDK 로깅은 데이터 흐름과 무관하며, 네트워크가 불안정할 때
          // WatchStream 재연결 스택을 대량으로 출력할 수 있다. 경고/오류와
          // Firestore 자체 재시도 동작은 그대로 두고 상세 로깅만 끈다.
          await FirebaseFirestore.setLoggingEnabled(false);
          final firestore = FirebaseFirestore.instance;
          firestore.settings = const Settings(
            persistenceEnabled: true,
            cacheSizeBytes: 100 * 1024 * 1024, // 100MB
          );
          if (kDebugMode) {
            debugPrint('✅ Firestore 설정 완료 (캐시: 100MB)');
          }
        } catch (firestoreError) {
          if (kDebugMode) {
            debugPrint('⚠️ Firestore 설정 중 오류: $firestoreError');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Firebase 추가 초기화 중 오류: $e');
        }
      }

      // 8. 앱 시작 (가입 완료 뒤에만 앱 기능 서비스를 초기화한다.)
      if (kDebugMode) {
        debugPrint('🚀 runApp 호출: ${DateTime.now()}');
      }

      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) {
              if (kDebugMode) {
                debugPrint('🔐 AuthProvider 생성 요청: ${DateTime.now()}');
              }
              return app_auth.AuthProvider();
            }),
            ChangeNotifierProvider(create: (_) => RelationshipProvider()),
          ],
          child: const MeetupApp(),
        ),
      );
      if (kDebugMode) {
        debugPrint('🎉 runApp 완료: ${DateTime.now()}');
      }
    },
    (error, stack) {
      // 크래시 리포트 (최선을 다하되 크래시는 방지)
      if (kDebugMode) {
        debugPrint('❌ runZonedGuarded 에러 캐치: $error');
        debugPrint('스택: $stack');
      }

      try {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      } catch (crashlyticsError) {
        // Crashlytics 리포트 실패해도 앱 실행은 계속
        if (kDebugMode) {
          debugPrint('⚠️ Crashlytics 리포트 실패: $crashlyticsError');
        }
      }

      // ❌ 절대 rethrow 하지 않음 - 앱이 종료됨!
      // production에서도 앱 계속 실행
    },
  );
}

class MeetupApp extends StatefulWidget {
  const MeetupApp({super.key});

  @override
  State<MeetupApp> createState() => _MeetupAppState();

  // 어디서든 접근 가능하도록 static 메서드 제공
  static _MeetupAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MeetupAppState>();
}

class _MeetupAppState extends State<MeetupApp> {
  Locale _locale = const Locale('ko'); // 기본 언어: 한국어
  final LanguageService _languageService = LanguageService();
  String? _lastSyncedLanguageCode;
  Future<void>? _languageSyncInFlight;
  String? _completedServicesUid;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    unawaited(
      AppUpdateService.instance.initialize().whenComplete(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(AppUpdateService.instance.presentIfNeeded());
        });
      }),
    );
  }

  Future<void> _syncLanguageToFirestore(String languageCode) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 동일 세션에서 중복 쓰기 최소화
    if (_lastSyncedLanguageCode == languageCode) return;

    final activeSync = _languageSyncInFlight;
    if (activeSync != null) {
      await activeSync;
      if (_lastSyncedLanguageCode == languageCode) return;
    }

    final request = _syncLanguageToExistingUser(
      uid: user.uid,
      languageCode: languageCode,
    );
    _languageSyncInFlight = request;
    await request.whenComplete(() {
      if (identical(_languageSyncInFlight, request)) {
        _languageSyncInFlight = null;
      }
    });
  }

  Future<void> _syncLanguageToExistingUser({
    required String uid,
    required String languageCode,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection('users').doc(uid);

      // Social Auth creates an Auth session before the final sign-up function
      // creates users/{uid}. Do not turn that expected pending state into a
      // permission-denied write, and never create a partial users document
      // from language synchronization.
      final userSnapshot = await userRef.get(const GetOptions(
        source: Source.server,
      ));
      if (!userSnapshot.exists) {
        if (kDebugMode) {
          debugPrint('ℹ️ 언어 Firestore 동기화 보류: 회원가입 완료 전');
        }
        return;
      }
      final userData = userSnapshot.data() ?? const <String, dynamic>{};
      final status = (userData['registrationStatus'] ?? '').toString();
      final legacyComplete = status.isEmpty &&
          userData['emailVerified'] == true &&
          (userData['nickname'] ?? '').toString().trim().isNotEmpty;
      if (status != 'complete' && !legacyComplete) return;

      await userRef.update({
        'preferredLanguage': languageCode,
        'preferredLanguageUpdatedAt': FieldValue.serverTimestamp(),
      });

      await firestore.collection('user_settings').doc(uid).set({
        'locale': languageCode,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (FirebaseAuth.instance.currentUser?.uid == uid) {
        _lastSyncedLanguageCode = languageCode;
      }
      if (kDebugMode) {
        debugPrint('✅ 언어 Firestore 동기화 완료: $languageCode (uid=$uid)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 언어 Firestore 동기화 실패(무시): $e');
      }
    }
  }

  /// 저장된 언어 불러오기
  Future<void> _loadLanguage() async {
    final languageCode = await _languageService.getLanguage();
    if (mounted) {
      setState(() {
        _locale = Locale(languageCode);
      });
    }
    if (kDebugMode) {
      debugPrint('🌐 언어 로드 완료: $languageCode');
    }
  }

  void _initializeCompletedServices(app_auth.AuthProvider authProvider) {
    final uid = authProvider.user?.uid;
    if (uid == null || _completedServicesUid == uid) return;
    _completedServicesUid = uid;
    unawaited(Future<void>(() async {
      try {
        await FeatureFlagService().init();
        await ExternalShareService.instance.initialize();
        await ContentTranslationService.instance
            .synchronizeAutomaticLanguageWithUi(_locale.languageCode);
        await _syncLanguageToFirestore(_locale.languageCode);
      } catch (error) {
        if (kDebugMode) debugPrint('완료 사용자 서비스 초기화 실패: $error');
      }
    }));
  }

  /// 언어 변경
  void changeLanguage(String languageCode) {
    if (_locale.languageCode != languageCode) {
      setState(() {
        _locale = Locale(languageCode);
      });
      unawaited(_saveLanguageAndRefreshNotifications(languageCode));
      if (_completedServicesUid != null) {
        unawaited(
          ContentTranslationService.instance
              .synchronizeAutomaticLanguageWithUi(languageCode),
        );
        unawaited(_syncLanguageToFirestore(languageCode));
      }
      if (kDebugMode) {
        debugPrint('🌐 언어 변경: $languageCode');
      }
    }
  }

  Future<void> _saveLanguageAndRefreshNotifications(
    String languageCode,
  ) async {
    await _languageService.saveLanguage(languageCode);
    if (_completedServicesUid == null) return;
    try {
      await SemesterTodoService.instance
          .refreshPersonalTodoNotificationLanguage();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 로컬 할 일 알림 언어 갱신 실패(다음 화면 진입 시 재시도): $e');
      }
    }
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      await FCMService().refreshTokenLocale(userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wefilling',
      theme: AppTheme.light(),
      themeMode: ThemeMode.light, // 강제 라이트모드
      locale: _locale, // 현재 선택된 언어
      scaffoldMessengerKey: AppMessenger.scaffoldMessengerKey,
      localizationsDelegates: const [
        AppLocalizations.delegate, // 앱 전용 번역
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko'), // 한국어
        Locale('en'), // 영어
      ],
      // 전역 탭-투-디스미스: 빈 공간 탭 시 키보드 닫힘 + SnackBar 닫힘
      builder: (context, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            // 키보드 닫기
            final currentFocus = FocusScope.of(context);
            if (!currentFocus.hasPrimaryFocus &&
                currentFocus.focusedChild != null) {
              FocusManager.instance.primaryFocus?.unfocus();
            }
            // SnackBar 닫기 (전역 ScaffoldMessenger 키 사용)
            AppMessenger.scaffoldMessengerKey.currentState
                ?.hideCurrentSnackBar();
          },
          child: child,
        );
      },
      routes: {
        '/edit-meetup': (context) {
          final meetup = ModalRoute.of(context)!.settings.arguments as Meetup;
          return EditMeetupScreen(meetup: meetup);
        },
        '/admin-migration': (context) => const AdminMigrationScreen(),
        if (kDebugMode)
          '/release-diagnostics': (context) => const ReleaseDiagnosticsScreen(),
      },
      navigatorKey: NavigationService.navigatorKey,
      home: Consumer<app_auth.AuthProvider>(
        builder: (context, authProvider, _) {
          final canRouteExternalShare = !authProvider.isLoading &&
              authProvider.isLoggedIn &&
              authProvider.isRegistrationComplete;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ExternalShareService.instance
                .setRoutingReady(canRouteExternalShare);
          });

          if (authProvider.isLoading) {
            return const Scaffold(
              backgroundColor: Color(0xFFDEEFFF),
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // 로그인되어 있으면
          if (authProvider.isLoggedIn) {
            // Firebase Auth 존재 여부가 아니라 서버의 최종 가입 완료 상태를
            // 기준으로만 앱 진입을 허용한다.
            if (!authProvider.isRegistrationComplete) {
              if (authProvider.registrationState ==
                  app_auth.AccountRegistrationState.authCreated) {
                final signupLanguage =
                    (authProvider.userData?['signupLanguage'] ?? 'ko')
                        .toString();
                return signupLanguage.startsWith('en')
                    ? const HanyangEmailVerificationScreen.general(
                        signupLanguage: 'en',
                      )
                    : const HanyangEmailVerificationScreen();
              }
              return const NicknameSetupScreen();
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              _initializeCompletedServices(authProvider);
            });

            return MainScreen(
              key: ValueKey('main_session_${authProvider.user!.uid}'),
            );
          }

          // 로그인되어 있지 않으면
          return const LoginScreen();
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
