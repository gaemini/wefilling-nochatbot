// 앱의 시작점
// Firebase 초기화
//프로바이더 설정
// 앱 테마 및 라우팅 설정

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import 'screens/main_screen.dart';
import 'providers/auth_provider.dart' as app_auth;
import 'providers/settings_provider.dart';
import 'screens/login_screen.dart';
import 'screens/nickname_setup_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Firebase Storage 이미지 접근을 위한 Firebase Auth 초기화
  // 앱 시작 시 Firebase SDK가 완전히 활성화되도록 함
  try {
    print('🔥 Firebase 초기화 시작: ${DateTime.now()}');
    print('🔥 Firebase 프로젝트 ID: ${Firebase.app().options.projectId}');
    print('🔥 Firebase Storage 버킷: ${Firebase.app().options.storageBucket}');
    
    // Firebase Auth 상태 변화 로깅
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      print('🔐 Auth State Changed: ${user != null ? "Authenticated" : "Not Authenticated"}');
      print('🔐 User ID: ${user?.uid ?? "null"}');
      print('🔐 Timestamp: ${DateTime.now()}');
    });
    
    print('🔐 인증 초기화 대기 중...');
    
    // 인증 상태를 최대 5초간 기다림
    User? currentUser;
    int attempts = 0;
    while (attempts < 10) { // 0.5초씩 10번 = 5초
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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => app_auth.AuthProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()..init()),
      ],
      child: const MeetupApp(),
    ),
  );
}

class MeetupApp extends StatelessWidget {
  const MeetupApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    
    return MaterialApp(
      title: 'David C.',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Pretendard',
      ),
      home: Consumer<app_auth.AuthProvider>(
        builder: (context, authProvider, _) {
          if (authProvider.isLoading) {
            return const Scaffold(
              backgroundColor: Color(0xFFDEEFFF),
              body: Center(
                child: CircularProgressIndicator(),
              ),
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