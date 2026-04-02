// lib/utils/notification_permission_helper.dart
// 알림 권한 헬퍼 유틸리티
// APK 푸시 알림 문제 해결을 위한 권한 관리

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/logger.dart';

class NotificationPermissionHelper {
  // 알림 권한 상태 확인 및 상세 로그
  static Future<void> checkAndLogPermissionStatus() async {
    if (kIsWeb) return;

    try {
      // Firebase Messaging 권한 상태
      final fcmSettings = await FirebaseMessaging.instance.getNotificationSettings();
      Logger.log('🔍 FCM 권한 상태: ${fcmSettings.authorizationStatus}');
      
      switch (fcmSettings.authorizationStatus) {
        case AuthorizationStatus.authorized:
          Logger.log('   ✅ authorized: 알림 권한 허용됨');
          break;
        case AuthorizationStatus.denied:
          Logger.log('   ❌ denied: 알림 권한 거부됨 (설정에서 수동 변경 필요)');
          break;
        case AuthorizationStatus.notDetermined:
          Logger.log('   ⚠️  notDetermined: 아직 권한을 물어보지 않음');
          break;
        case AuthorizationStatus.provisional:
          Logger.log('   ✅ provisional: 임시 허용 (iOS)');
          break;
      }

      // Android: permission_handler로 추가 확인
      if (Platform.isAndroid) {
        final permissionStatus = await Permission.notification.status;
        Logger.log('🔍 Android 권한 상태: $permissionStatus');
        
        if (permissionStatus.isGranted) {
          Logger.log('   ✅ 알림 권한 허용됨');
        } else if (permissionStatus.isDenied) {
          Logger.log('   ⚠️  알림 권한 거부됨 (다시 요청 가능)');
        } else if (permissionStatus.isPermanentlyDenied) {
          Logger.log('   ❌ 알림 권한 영구 거부됨 (설정에서만 변경 가능)');
        } else {
          Logger.log('   ⚠️  알림 권한 상태: $permissionStatus');
        }
      }
    } catch (e) {
      Logger.error('❌ 권한 상태 확인 실패: $e');
    }
  }

  // 알림 권한 요청 (앱 시작 시 호출)
  static Future<bool> requestPermission() async {
    if (kIsWeb) return true;

    try {
      Logger.log('🔔 알림 권한 요청 시작...');
      
      // 1. 현재 상태 확인
      await checkAndLogPermissionStatus();
      
      // 2. FCM 권한 요청
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      
      Logger.log('✅ FCM 권한 요청 완료: ${settings.authorizationStatus}');
      
      // 3. Android 추가 권한 요청
      if (Platform.isAndroid) {
        final permissionStatus = await Permission.notification.status;
        
        if (permissionStatus.isDenied) {
          Logger.log('📱 Android POST_NOTIFICATIONS 권한 요청 중...');
          final result = await Permission.notification.request();
          Logger.log('✅ Android 권한 요청 결과: $result');
          
          if (result.isPermanentlyDenied) {
            Logger.log('❌ 권한이 영구 거부되었습니다');
            Logger.log('💡 해결: 설정 > 앱 > Wefilling > 알림 켜기');
            return false;
          }
          
          return result.isGranted;
        }
        
        return permissionStatus.isGranted;
      }
      
      // iOS
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
             settings.authorizationStatus == AuthorizationStatus.provisional;
      
    } catch (e) {
      Logger.error('❌ 알림 권한 요청 실패: $e');
      return false;
    }
  }

  // 설정 화면으로 이동
  static Future<void> openSettings() async {
    if (kIsWeb) return;
    
    try {
      Logger.log('⚙️ 앱 설정 화면 열기...');
      await openAppSettings();
      Logger.log('✅ 설정 화면 열림');
    } catch (e) {
      Logger.error('❌ 설정 화면 열기 실패: $e');
    }
  }

  // 권한이 거부된 경우 사용자에게 안내
  static Future<bool> checkPermissionOrPromptSettings() async {
    if (kIsWeb) return true;

    try {
      final fcmSettings = await FirebaseMessaging.instance.getNotificationSettings();
      
      // 권한이 허용된 경우
      if (fcmSettings.authorizationStatus == AuthorizationStatus.authorized ||
          fcmSettings.authorizationStatus == AuthorizationStatus.provisional) {
        return true;
      }
      
      // 권한이 거부된 경우
      if (fcmSettings.authorizationStatus == AuthorizationStatus.denied) {
        Logger.log('⚠️  알림 권한이 거부되어 있습니다');
        Logger.log('💡 설정에서 알림 권한을 켜주세요');
        
        // Android: 영구 거부 확인
        if (Platform.isAndroid) {
          final status = await Permission.notification.status;
          if (status.isPermanentlyDenied) {
            Logger.log('❌ 권한이 영구 거부되었습니다 - 설정에서 수동으로 변경해야 합니다');
            return false;
          }
        }
        
        return false;
      }
      
      return false;
    } catch (e) {
      Logger.error('❌ 권한 확인 실패: $e');
      return false;
    }
  }
}
