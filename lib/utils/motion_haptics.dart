import 'package:flutter/widgets.dart';

import 'accessibility_utils.dart';

/// 햅틱을 허용하는 중요한 순간. 기본 눌림·화면 이동·탭 선택·메시지 전송은
/// 의도적으로 포함하지 않는다.
enum MotionHapticEvent {
  /// 좋아요가 실제로 선택되었을 때(해제에는 없음).
  likeSelected,

  /// 할 일 체크가 실제로 완료 처리되었을 때.
  checkCompleted,

  /// 처리형 버튼이 실제 성공 결과를 받았을 때.
  processingSuccess,

  /// 켜기·임계값 도달(모션 2부 공통 이름).
  selection,

  /// 서버 확정 등 실제 성공.
  success,

  /// 되돌림·입력 거절.
  warning,
}

/// 버튼 인터랙션용 햅틱 정책. 기존 `HapticFeedback.*` 직접 호출 지점은 그대로
/// 두고, 새 지점은 모두 이 헬퍼를 통해 감소 동작 설정을 존중한다.
class MotionHaptics {
  MotionHaptics._();

  /// ButtonLab 카운터 등 개발용 관찰자. 운영 동작에는 영향 없음.
  static void Function(MotionHapticEvent event)? debugObserver;

  static void fire(BuildContext context, MotionHapticEvent event) {
    debugObserver?.call(event);
    final HapticFeedbackType type;
    switch (event) {
      case MotionHapticEvent.likeSelected:
      case MotionHapticEvent.checkCompleted:
      case MotionHapticEvent.selection:
        type = HapticFeedbackType.selectionClick;
        break;
      case MotionHapticEvent.processingSuccess:
      case MotionHapticEvent.success:
        type = HapticFeedbackType.lightImpact;
        break;
      case MotionHapticEvent.warning:
        type = HapticFeedbackType.mediumImpact;
        break;
    }
    AccessibilityUtils.provideFeedback(context, type);
  }
}
