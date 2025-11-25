// lib/utils/logger.dart
// 로깅 유틸리티 - 디버그 모드에서만 로그 출력, 프로덕션에서는 Crashlytics로 전송

import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class Logger {
  /// 일반 로그 메시지 출력 (디버그 모드에서만)
  static void log(String message) {
    if (kDebugMode) {
      debugPrint('📝 $message');
    }
  }

  /// 정보성 로그 메시지 출력 (디버그 모드에서만)
  static void info(String message) {
    if (kDebugMode) {
      debugPrint('ℹ️ $message');
    }
  }

  /// 경고 로그 메시지 출력 (디버그 모드에서만)
  static void warning(String message) {
    if (kDebugMode) {
      debugPrint('⚠️ $message');
    }
  }

  /// 에러 로그 출력 및 Crashlytics 전송
  /// 
  /// [message]: 에러 설명
  /// [error]: 에러 객체 (선택사항)
  /// [stackTrace]: 스택 트레이스 (선택사항)
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('❌ $message');
      if (error != null) debugPrint('Error: $error');
      if (stackTrace != null) debugPrint('StackTrace: $stackTrace');
    }
    
    // 프로덕션에서는 Crashlytics로 전송
    if (!kDebugMode && error != null) {
      FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        reason: message,
        fatal: false,
      );
    }
  }

  /// 치명적 에러 로그 출력 및 Crashlytics 전송 (fatal=true)
  /// 
  /// [message]: 에러 설명
  /// [error]: 에러 객체
  /// [stackTrace]: 스택 트레이스 (선택사항)
  static void fatal(String message, Object error, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('💀 FATAL: $message');
      debugPrint('Error: $error');
      if (stackTrace != null) debugPrint('StackTrace: $stackTrace');
    }
    
    // Crashlytics로 치명적 에러 전송
    FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace ?? StackTrace.current,
      reason: message,
      fatal: true,
    );
  }
}


