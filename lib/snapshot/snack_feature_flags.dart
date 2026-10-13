// lib/snapshot/snack_feature_flags.dart
// 스낵 v3: 필링 하나만 남기므로 공개 댓글·편지 진입점은 기본으로 끈다.
// 서버 함수와 데이터는 이전 버전 앱을 위해 그대로 둔다.

class SnackFeatureFlags {
  const SnackFeatureFlags._();

  /// 공개 댓글(모두의 한마디) 진입점. 알림으로 들어온 경우만 읽기 전용으로 연다.
  static bool publicComments = false;

  /// 스낵 편지 작성 진입점과 받은 편지의 답장 버튼.
  static bool letters = false;

  /// 원격 설정 등에서 값을 받아 갱신한다.
  static void apply({bool? publicComments, bool? letters}) {
    if (publicComments != null) SnackFeatureFlags.publicComments = publicComments;
    if (letters != null) SnackFeatureFlags.letters = letters;
  }
}
