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
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:provider/provider.dart';
import 'design/theme.dart';
import 'screens/main_screen.dart';
import 'screens/edit_meetup_screen.dart';
import 'models/meetup.dart';
import 'providers/auth_provider.dart' as app_auth;
import 'providers/relationship_provider.dart';
import 'screens/login_screen.dart';
import 'screens/nickname_setup_screen.dart';
import 'firebase_options.dart';
import 'services/feature_flag_service.dart';
import 'services/fcm_service.dart';
import 'services/language_service.dart';
import 'services/cache/cache_manager.dart';
import 'l10n/app_localizations.dart';
import 'services/navigation_service.dart';
import 'screens/admin_migration_screen.dart';
import 'services/app_messenger.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

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
        await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform);
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
        if (!kIsWeb && Platform.isAndroid) {
          FirebaseMessaging.onBackgroundMessage(
              firebaseMessagingBackgroundHandler);
          if (kDebugMode) {
            debugPrint('📱 Android FCM 백그라운드 핸들러 등록 완료');
          }
        } else if (!kIsWeb && Platform.isIOS && kDebugMode) {
          debugPrint('📱 iOS는 안전 모드로 지연 초기화 - 백그라운드 핸들러 등록 생략');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Firebase Messaging 핸들러 등록 실패: $e');
        }
      }

      // 4. App Check 초기화
      try {
        // ⚠️ 임시: iOS에서 App Check 완전 비활성화 (TestFlight 크래시 방지)
        // TODO: 나중에 제대로 된 App Check 설정 필요
        if (Platform.isIOS) {
          await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(false);
          if (kDebugMode) {
            debugPrint('🛡️ App Check: iOS 토큰 자동 갱신 비활성화 (임시)');
          }
        } else {
          await FirebaseAppCheck.instance.activate(
            providerAndroid: const AndroidDebugProvider(),
            providerApple: const AppleDeviceCheckProvider(),
          );
          if (kDebugMode) debugPrint('🛡️ App Check 활성화 완료');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ App Check 초기화 실패(무시): $e');
        }
      }

      // 5. Crashlytics 설정
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
        await CacheManager.initialize();
        if (kDebugMode) {
          debugPrint('💾 캐시 시스템 초기화 완료');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ 캐시 시스템 초기화 실패 (앱은 정상 작동): $e');
        }
      }

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

        // Firebase Auth 상태 변화 로깅 (비동기로 처리)
        FirebaseAuth.instance.authStateChanges().listen((User? user) {
          if (kDebugMode) {
            debugPrint(
              '🔐 Auth State Changed: ${user != null ? "Authenticated" : "Not Authenticated"}',
            );
            debugPrint('🔐 User ID: ${user?.uid ?? "null"}');
            debugPrint('🔐 Timestamp: ${DateTime.now()}');
          }
        });

        // 현재 로그인 상태만 확인 (대기 시간 제거)
        final currentUser = FirebaseAuth.instance.currentUser;
        if (kDebugMode) {
          if (currentUser != null) {
            debugPrint('🔐 사용자 로그인 확인: ${currentUser.email}');
          } else {
            debugPrint('🔐 로그인된 사용자 없음');
          }
          debugPrint('🔐 인증 초기화 완료: ${DateTime.now()}');
        }

        // Firebase Storage 접근 테스트 (백그라운드로 이동)
        if (currentUser != null) {
          unawaited(Future(() async {
            try {
              if (kDebugMode) {
                debugPrint('🗄️ Storage 접근 테스트 시작 (백그라운드)');
              }
              final storageRef = FirebaseStorage.instance.ref();
              await storageRef.listAll();
              if (kDebugMode) {
                debugPrint('✅ Firebase Storage 접근 테스트: 성공');
              }
            } catch (storageError) {
              if (kDebugMode) {
                debugPrint('⚠️ Firebase Storage 접근 테스트 실패: $storageError');
              }
            }
          }));
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Firebase 추가 초기화 중 오류: $e');
        }
      }

      // 8. FeatureFlagService 초기화 (백그라운드로 이동)
      unawaited(Future(() async {
        try {
          await FeatureFlagService().init();
          if (kDebugMode) {
            debugPrint('🚩 FeatureFlagService 초기화 완료');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ FeatureFlagService 초기화 오류: $e');
          }
        }
      }));

      // 9. 앱 시작 (대기 시간 제거)
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
  StreamSubscription<User?>? _authSub;
  String? _lastSyncedLanguageCode;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) return;
      // 로그인 시점에 서버에도 언어 동기화 (푸시 i18n용)
      unawaited(_syncLanguageToFirestore(_locale.languageCode));
    });
  }

  Future<void> _syncLanguageToFirestore(String languageCode) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 동일 세션에서 중복 쓰기 최소화
    if (_lastSyncedLanguageCode == languageCode) return;
    _lastSyncedLanguageCode = languageCode;

    try {
      final uid = user.uid;
      final firestore = FirebaseFirestore.instance;

      // ⚠️ 주의: users/{uid} 문서의 "존재 여부"는 회원가입 완료 여부 판단에 사용된다.
      // 따라서 여기서 merge set으로 문서를 "새로 생성"하면 스키마가 부분만 생기거나
      // 가입 흐름이 왜곡될 수 있으므로, 문서가 있을 때만 update로 반영한다.
      await firestore.collection('users').doc(uid).update({
        'preferredLanguage': languageCode,
        'preferredLanguageUpdatedAt': FieldValue.serverTimestamp(),
      });

      await firestore.collection('user_settings').doc(uid).set({
        'locale': languageCode,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

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
    // 푸시 i18n을 위해 서버에도 동기화
    unawaited(_syncLanguageToFirestore(languageCode));
    if (kDebugMode) {
      debugPrint('🌐 언어 로드 완료: $languageCode');
    }
  }

  /// 언어 변경
  void changeLanguage(String languageCode) {
    if (_locale.languageCode != languageCode) {
      setState(() {
        _locale = Locale(languageCode);
      });
      _languageService.saveLanguage(languageCode);
      // 푸시 i18n을 위해 서버에도 동기화
      unawaited(_syncLanguageToFirestore(languageCode));
      if (kDebugMode) {
        debugPrint('🌐 언어 변경: $languageCode');
      }
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _authSub = null;
    super.dispose();
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
      },
      navigatorKey: NavigationService.navigatorKey,
      home: Consumer<app_auth.AuthProvider>(
        builder: (context, authProvider, _) {
          if (authProvider.isLoading) {
            return const Scaffold(
              backgroundColor: Color(0xFFDEEFFF),
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // 로그인되어 있으면
          if (authProvider.isLoggedIn) {
            // 프로필 완성 여부 확인 (닉네임 + 국적 모두 필수)
            if (!authProvider.isProfileComplete) {
              return const NicknameSetupScreen();
            }

            // 프로필 완성되었으면 메인 화면
            return const MainScreen();
          }

          // 로그인되어 있지 않으면
          return const LoginScreen();
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
