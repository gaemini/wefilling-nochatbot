// lib/utils/logger.dart
// 로깅 유틸리티 - 디버그 모드에서만 로그 출력, 프로덕션에서는 Crashlytics로 전송

import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class Logger {
  /// 정상 동작 경로의 상세 로그는 명시적으로 요청한 디버그 빌드에서만
  /// 출력한다. Firestore snapshot, 채팅 읽음 처리, FCM payload처럼 자주
  /// 실행되는 경로가 logcat I/O 때문에 느려지지 않게 기본값은 false다.
  ///
  /// 필요할 때만 다음 옵션으로 실행한다.
  /// `--dart-define=WEFILLING_VERBOSE_LOGS=true`
  static const bool verboseLoggingEnabled = bool.fromEnvironment(
    'WEFILLING_VERBOSE_LOGS',
    defaultValue: false,
  );

  /// 호출 지점에서도 이 상수로 감싸 릴리스 AOT 빌드가 로그 메시지의 문자열
  /// 보간과 payload 생성을 통째로 제거할 수 있게 한다.
  static const bool isVerboseEnabled = kDebugMode && verboseLoggingEnabled;

  /// 일반 로그 메시지 출력 (명시적으로 활성화한 디버그 모드에서만)
  static void log(String message) {
    if (isVerboseEnabled) {
      debugPrint('📝 $message');
    }
  }

  /// 정보성 로그 메시지 출력 (명시적으로 활성화한 디버그 모드에서만)
  static void info(String message) {
    if (isVerboseEnabled) {
      debugPrint('ℹ️ $message');
    }
  }

  /// 경고 로그 메시지 출력 (상세 로그를 켠 디버그 모드에서만)
  static void warning(String message) {
    if (isVerboseEnabled) {
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
