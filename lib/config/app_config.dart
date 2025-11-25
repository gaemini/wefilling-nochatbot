// lib/config/app_config.dart
// 앱 설정 중앙화 - Firebase 및 OAuth 설정

import 'dart:io' show Platform;
import '../firebase_options.dart';

class AppConfig {
  /// Google OAuth Client ID 가져오기 (플랫폼별)
  /// 
  /// iOS/macOS: firebase_options.dart에서 iosClientId 사용
  /// Android: google-services.json에서 자동 처리 (null 반환)
  static String? getGoogleClientId() {
    if (Platform.isIOS || Platform.isMacOS) {
      return DefaultFirebaseOptions.currentPlatform.iosClientId;
    }
    return null; // Android는 google-services.json 사용
  }
  
  /// 앱 버전 정보
  static const String appVersion = '1.0.0';
  
  /// 앱 이름
  static const String appName = 'Wefilling';
  
  /// 회사/개발자 이름
  static const String companyName = 'Christopher Watson';
  
  /// 지원 이메일
  static const String supportEmail = 'wefilling@gmail.com';
}


