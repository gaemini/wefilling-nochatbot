// lib/utils/dm_feature_flags.dart
// DM 관련 디버그 플래그 관리
// 오류 진단을 위한 디버그 로그 제어

class DMFeatureFlags {
  /// 디버그 로그 활성화 (오류 진단용)
  /// 개발/테스트 시: true
  /// 프로덕션 배포 시: false로 변경
  static const bool enableDebugLogs = false; // 프로덕션: false
  
  /// 상세 배지 로그 활성화 (배지 오류 진단용)
  /// 배지 관련 문제 발생 시 상세 로그 확인
  static const bool enableBadgeDebugLogs = false; // 프로덕션: false
}
