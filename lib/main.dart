// 앱의 시작점
// Firebase 초기화
//프로바이더 설정
// 앱 테마 및 라우팅 설정

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'services/ad_banner_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  
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
  
  // Firebase 중복 초기화 방지
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    print('🔥 Firebase 초기화 완료');
  } catch (e) {
    if (e.toString().contains('duplicate-app')) {
      print('🔥 Firebase는 이미 초기화되어 있습니다.');
    } else {
      print('🔥 Firebase 초기화 중 오류: $e');
      rethrow;
    }
  }

  // FCM 백그라운드 메시지 핸들러 등록
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Firebase Storage 이미지 접근을 위한 Firebase Auth 초기화
  // 앱 시작 시 Firebase SDK가 완전히 활성화되도록 함
  try {
    print('🔥 Firebase 초기화 시작: ${DateTime.now()}');
    print('🔥 Firebase 프로젝트 ID: ${Firebase.app().options.projectId}');
    print('🔥 Firebase Storage 버킷: ${Firebase.app().options.storageBucket}');

    // Firebase Auth 상태 변화 로깅
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      print(
        '🔐 Auth State Changed: ${user != null ? "Authenticated" : "Not Authenticated"}',
      );
      print('🔐 User ID: ${user?.uid ?? "null"}');
      print('🔐 Timestamp: ${DateTime.now()}');
    });

    print('🔐 인증 초기화 대기 중...');

    // 인증 상태를 최대 5초간 기다림
    User? currentUser;
    int attempts = 0;
    while (attempts < 10) {
      // 0.5초씩 10번 = 5초
      currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        print('🔐 사용자 로그인 확인: ${currentUser.email}');
        break;
      }
      await Future.delayed(Duration(milliseconds: 500));
      attempts++;
      print('🔐 인증 대기 중... (${attempts}/10)');
    }

    print('🔐 인증 초기화 완료: ${DateTime.now()}');

    // Firestore 설정 개선 (연결 안정성 향상)
    try {
      print('🗃️ Firestore 설정 시작');
      final firestore = FirebaseFirestore.instance;
      
      // 오프라인 지속성은 Settings를 통해 설정됩니다 (아래 firestore.settings 참고)
      
      // Firestore 설정 조정
      firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      
      print('✅ Firestore 설정 완료');
      
      // 광고 배너 초기화
      try {
        print('📢 광고 배너 초기화 시작');
        final adBannerService = AdBannerService();
        await adBannerService.initializeSampleBanners();
        print('✅ 광고 배너 초기화 완료');
      } catch (adError) {
        print('❌ 광고 배너 초기화 오류: $adError');
      }
    } catch (firestoreError) {
      print('❌ Firestore 설정 중 오류: $firestoreError');
    }

    // Firebase Storage 접근 테스트
    try {
      print('🗄️ Storage 접근 테스트 시작');
      final storageRef = FirebaseStorage.instance.ref();
      await storageRef.listAll();
      print('✅ Firebase Storage 접근 테스트: 성공');
    } catch (storageError) {
      print('❌ Firebase Storage 접근 테스트 실패: $storageError');
      if (storageError.toString().contains('403')) {
        print('⚠️  Firebase 프로젝트 권한 문제일 가능성이 높습니다.');
        print('   프로젝트 소유자에게 Firebase Console에서 사용자 추가를 요청하세요.');
      }
    }
  } catch (e) {
    print('❌ Firebase 초기화 중 오류: $e');
  }

  // FeatureFlagService 초기화
  try {
    await FeatureFlagService().init();
    print('🚩 FeatureFlagService 초기화 완료');
  } catch (e) {
    print('⚠️ FeatureFlagService 초기화 오류: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => app_auth.AuthProvider()),
        ChangeNotifierProvider(create: (_) => RelationshipProvider()),
      ],
      child: const MeetupApp(),
    ),
  );
}

class MeetupApp extends StatelessWidget {
  const MeetupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'David C.',
      theme: AppTheme.light(),
      themeMode: ThemeMode.light, // 강제 라이트모드
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'), // 한국어
        Locale('en', 'US'), // 영어
      ],
      routes: {
        '/edit-meetup': (context) {
          final meetup = ModalRoute.of(context)!.settings.arguments as Meetup;
          return EditMeetupScreen(meetup: meetup);
        },
      },
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
            if (authProvider.hasNickname) {
              return const MainScreen();
            } else {
              return const NicknameSetupScreen();
            }
          }

          // 로그인되어 있지 않으면
          return const LoginScreen();
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
