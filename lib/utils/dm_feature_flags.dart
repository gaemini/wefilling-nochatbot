// lib/utils/dm_feature_flags.dart
// DM 관련 기능 플래그 관리
// 모든 새 기능은 기본적으로 비활성화되어 있으며, 필요시 개별적으로 활성화 가능

class DMFeatureFlags {
  /// FCM 직접 전송 활성화 (기본: false)
  /// true로 설정하면 DM 메시지 전송 시 Firestore 알림 생성과 함께 FCM도 직접 전송
  static const bool enableDirectFCM = false;
  
  /// 배지 주기적 동기화 활성화 (기본: false)
  /// true로 설정하면 30초마다 배지 카운트를 강제로 새로고침
  static const bool enablePeriodicSync = false;
  
  /// 라이프사이클 기반 읽음 처리 활성화 (기본: false)
  /// true로 설정하면 앱 포커스/재진입 시 자동으로 읽음 처리 수행
  static const bool enableLifecycleRead = false;
  
  /// 배지 업데이트 디바운스 시간 (밀리초, 0이면 비활성화)
  /// 0보다 크면 해당 시간만큼 배지 업데이트를 지연시켜 과도한 리빌드 방지
  static const int badgeDebounceMs = 0;
  
  /// 디버그 로그 활성화 (기본: false)
  /// true로 설정하면 DM 관련 상세 디버그 로그 출력
  static const bool enableDebugLogs = true;
  
  /// 폴백 카운팅 활성화 (기본: false)
  /// true로 설정하면 unreadCount가 0일 때 실제 메시지를 직접 카운트
  static const bool enableFallbackCount = true;
}
