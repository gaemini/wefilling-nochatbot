import 'package:flutter/material.dart';

import 'motion_press.dart';
import 'motion_selection_pulse.dart';

/// 선택형 버튼(탭·필터·관심사·공개범위·라디오)의 공통 반응.
///
/// 기존 Material/InkWell 서브트리를 [child]로 그대로 감싼다. 콜백·선택 규칙·
/// 단일/다중 선택은 호출부가 소유하며 이 위젯은 paint-only 반응만 더한다.
///
/// * 눌림: [MotionPress] (press 90ms / release 160ms, 콜백 지연 없음).
///   선택이 바뀌면 `resetToken`으로 눌림을 먼저 끝낸다.
/// * 선택 전환: [pulse]가 true인 칩류만 짧은 pulse(1.04 → 1).
///   탭·세그먼트·목록 행은 pulse 없이 색/윤곽/체크 전환만 사용한다.
/// * 색·윤곽·체크 전환은 호출부에서 `AnimatedContainer`,
///   `AnimatedDefaultTextStyle`, `MotionStateIcon`에
///   `MotionTokens.of(context, MotionTokens.state)`를 주어 처리한다.
///
/// 스케일 규약: 칩 .97, 세그먼트·탭 .985, 목록 행은 1.0(행은 스케일하지 않음).
/// 감소 동작에서는 눌림·pulse가 모두 꺼진다.
class MotionSelectable extends StatelessWidget {
  const MotionSelectable({
    super.key,
    required this.selected,
    required this.child,
    this.enabled = true,
    this.pressedScale = .97,
    this.pulse = false,
  }) : assert(pressedScale > 0 && pressedScale <= 1);

  /// 칩 .97 · 세그먼트/탭 .985 · 목록 행 1.0.
  static const double chipScale = .97;
  static const double segmentScale = .985;
  static const double rowScale = 1.0;

  final bool selected;
  final Widget child;
  final bool enabled;
  final double pressedScale;

  /// 칩처럼 독립된 작은 표면에만 true. 행·탭에는 false.
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final body = pulse
        ? MotionSelectionPulse(
            selected: selected,
            activePeak: 1.04,
            activeDip: 1,
            inactiveDip: .98,
            child: child,
          )
        : child;
    if (pressedScale == 1) return body;
    return MotionPress(
      enabled: enabled,
      pressedScale: pressedScale,
      resetToken: selected,
      child: body,
    );
  }
}
