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
import 'package:shared_preferences/shared_preferences.dart';
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
          options: DefaultFirebaseOptions.currentPlatform
        );
        if (kDebugMode) {
          debugPrint('🔥 Firebase 초기화 완료');
        }
        
        // ✅ CRITICAL FIX: Firebase 완전 초기화 대기 (iOS 필수)
        // Firebase.initializeApp()이 완료되어도 내부적으로 모든 서비스가 준비되지 않을 수 있음
        await Future.delayed(const Duration(seconds: 2));
        if (kDebugMode) {
          debugPrint('✅ Firebase 안정화 대기 완료');
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
          // 크래시 방지: 로그만 남기고 계속 진행
        }
      }

      // 1-A. iOS 버전 마이그레이션
      // 중요: v1.0.35부터는 iOS 시작 구간에서 FirebaseMessaging.deleteToken()을 호출하지 않습니다.
      // Crashlytics 스택상 FIRMessagingCurrentLocale / Swift Concurrency 크래시가
      // 초기 토큰 정리와 겹칠 가능성이 높아, 앱 안정성을 우선합니다.
      if (!kIsWeb && Platform.isIOS) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final lastVersion = prefs.getString('last_app_version') ?? '';
          const currentVersion = '1.0.35'; // pubspec.yaml과 동기화 필요

          if (kDebugMode) {
            debugPrint('📌 iOS 안전 마이그레이션: "$lastVersion" → "$currentVersion"');
          }

          if (lastVersion.isNotEmpty && lastVersion != currentVersion) {
            await prefs.setBool('ios_fcm_recovery_required', true);
            if (kDebugMode) {
              debugPrint('🛟 iOS FCM 복구 플래그 설정 완료');
            }
          }

          await prefs.setString('last_app_version', currentVersion);
          if (kDebugMode) {
            debugPrint('✅ 버전 기록 완료: $currentVersion');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ iOS 버전 마이그레이션 실패(무시): $e');
          }
        }
      }

      // 2. locale 강제 초기화 (Firebase Messaging보다 먼저 - 중요!)
      try {
        final languageService = LanguageService();
        await languageService.initializeLanguage();
        final lang = await languageService.getLanguage();
        if (kDebugMode) {
          debugPrint('🌐 locale 초기화 완료: $lang');
        }
        
        // locale 설정 후 추가 안정화 대기 (iOS 중요)
        await Future.delayed(const Duration(milliseconds: 1000));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ locale 초기화 실패 - 기본값 사용: $e');
        }
        // 실패해도 기본 locale으로 계속 진행
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 3. Firebase Messaging 백그라운드 핸들러 등록
      try {
        await Future.delayed(const Duration(milliseconds: 500));

        // iOS는 시작 직후 Messaging에 과도하게 접근하지 않도록 지연 초기화만 사용한다.
        // 백그라운드 핸들러는 Android에만 등록해도 핵심 푸시 기능에는 영향이 없다.
        if (!kIsWeb && Platform.isAndroid) {
          FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
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
          if (kDebugMode) {
            debugPrint('🛡️ App Check: iOS 전체 비활성화 (임시)');
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
            FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
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

      // 7. Firebase Auth 및 Firestore 설정
      // 7. Firebase Auth 및 Firestore 설정
      try {
        if (kDebugMode) {
          debugPrint('🔥 Firebase 추가 초기화 시작: ${DateTime.now()}');
          debugPrint(
              '🔥 Firebase 프로젝트 ID: ${Firebase.app().options.projectId}');
          debugPrint(
              '🔥 Firebase Storage 버킷: ${Firebase.app().options.storageBucket}');
        }

        // Firestore 설정 개선 (연결 안정성 향상) - Auth 전에 설정
        try {
          if (kDebugMode) {
            debugPrint('🗃️ Firestore 설정 시작');
          }
          final firestore = FirebaseFirestore.instance;

          // 🔥 하이브리드 동기화: Firestore 설정 조정
          // Android 캐시 문제 해결을 위해 무제한 → 100MB 제한
          firestore.settings = const Settings(
            persistenceEnabled: true,
            cacheSizeBytes:
                100 * 1024 * 1024, // 100MB (기존: CACHE_SIZE_UNLIMITED)
          );

          if (kDebugMode) {
            debugPrint('✅ Firestore 설정 완료 (캐시: 100MB)');
          }
        } catch (firestoreError) {
          if (kDebugMode) {
            debugPrint('⚠️ Firestore 설정 중 오류: $firestoreError');
          }
        }

        // Firebase Auth 안정화 대기 (중요!)
        await Future.delayed(const Duration(milliseconds: 1000));

        // Firebase Auth 상태 변화 로깅
        FirebaseAuth.instance.authStateChanges().listen((User? user) {
          if (kDebugMode) {
            debugPrint(
              '🔐 Auth State Changed: ${user != null ? "Authenticated" : "Not Authenticated"}',
            );
            debugPrint('🔐 User ID: ${user?.uid ?? "null"}');
            debugPrint('🔐 Timestamp: ${DateTime.now()}');
          }
        });

        if (kDebugMode) {
          debugPrint('🔐 인증 초기화 대기 중...');
        }

        // 인증 상태를 최대 5초간 기다림
        User? currentUser;
        int attempts = 0;
        while (attempts < 10) {
          // 0.5초씩 10번 = 5초
          currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null) {
            if (kDebugMode) {
              debugPrint('🔐 사용자 로그인 확인: ${currentUser.email}');
            }
            break;
          }
          await Future.delayed(Duration(milliseconds: 500));
          attempts++;
          if (kDebugMode) {
            debugPrint('🔐 인증 대기 중... (${attempts}/10)');
          }
        }

        if (kDebugMode) {
          debugPrint('🔐 인증 초기화 완료: ${DateTime.now()}');
        }

        // Firebase Storage 접근 테스트
        try {
          if (kDebugMode) {
            debugPrint('🗄️ Storage 접근 테스트 시작');
          }
          final storageRef = FirebaseStorage.instance.ref();
          await storageRef.listAll();
          if (kDebugMode) {
            debugPrint('✅ Firebase Storage 접근 테스트: 성공');
          }
        } catch (storageError) {
          if (kDebugMode) {
            debugPrint('⚠️ Firebase Storage 접근 테스트 실패: $storageError');
            if (storageError.toString().contains('403')) {
              debugPrint('⚠️  Firebase 프로젝트 권한 문제일 가능성이 높습니다.');
              debugPrint('   프로젝트 소유자에게 Firebase Console에서 사용자 추가를 요청하세요.');
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Firebase 추가 초기화 중 오류: $e');
        }
      }

      // 8. FeatureFlagService 초기화
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

      // 9. 최종 안정화 대기 (AuthProvider 초기화 전 중요!)
      if (kDebugMode) {
        debugPrint('⏳ 최종 안정화 대기 시작: ${DateTime.now()}');
      }
      await Future.delayed(const Duration(milliseconds: 1500));
      if (kDebugMode) {
        debugPrint('✅ 최종 안정화 완료 - runApp 시작: ${DateTime.now()}');
      }

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
            // 닉네임 설정 확인
            if (!authProvider.hasNickname) {
              return const NicknameSetupScreen();
            }

            // 닉네임 있으면 메인 화면
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
