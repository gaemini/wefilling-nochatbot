import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'motion_press.dart';

/// 처리형 버튼의 표시 단계. [busy]는 호출부의 실제 처리 플래그에서만 파생된다.
enum ProcessingPhase { idle, busy, success, failure }

/// 호출부가 **실제 결과를 받은 뒤** 호출하는 표시 전용 알림.
///
/// `success()`는 짧은 체크 표시 후 스스로 idle로 돌아간다(fire-and-forget).
/// 절대 await 대상이 아니며 화면 이동·요청을 지연시키지 않는다.
/// `failure()`는 라벨로 되돌릴 뿐 흔들림·색 번쩍임 같은 연출을 추가하지 않는다.
class ProcessingFeedback extends ValueNotifier<ProcessingPhase> {
  ProcessingFeedback({this.holdDuration = MotionTokens.delight})
      : super(ProcessingPhase.idle);

  /// 결과 표시를 유지하는 시간(전환 자체는 [MotionTokens.state]).
  final Duration holdDuration;
  Timer? _timer;

  void success() => _show(ProcessingPhase.success);

  void failure() => _show(ProcessingPhase.failure);

  void reset() {
    _timer?.cancel();
    _timer = null;
    value = ProcessingPhase.idle;
  }

  void _show(ProcessingPhase phase) {
    _timer?.cancel();
    value = phase;
    _timer = Timer(holdDuration, () {
      _timer = null;
      if (value == phase) value = ProcessingPhase.idle;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

typedef ProcessingButtonBuilder = Widget Function(
  BuildContext context,
  VoidCallback? onPressed,
  Widget child,
);

/// 처리형(저장·업로드·생성·참여·로그인)과 주의 행동형(나가기·삭제) 버튼의 공통 반응.
///
/// 기존 버튼 위젯(FilledButton/ElevatedButton/TextButton/InkWell)은 [builder]가
/// 그대로 만들고, 이 위젯은 눌림과 "처리 중 → 실제 결과" 표시만 더한다.
///
/// * 눌림: [MotionPress] (.975, 주의 행동형은 .99). `busy`면 눌림 없음.
/// * 처리 중: [busy]가 true인 동안 [spinner](기본 18px) 표시. busy는 호출부의
///   `_isLoading`류 플래그이므로 요청 전에 스피너가 먼저 보일 수 없다.
/// * 성공: [feedback]이 있고 호출부가 `success()`를 호출했을 때만 체크 아이콘.
///   [feedback]이 null이면 눌림 + busy만(결과를 안전하게 알 수 없는 버튼의 기본).
/// * 라벨 슬롯은 [label]의 고유 크기로 고정되어 스피너/체크로 바뀌어도
///   버튼 크기와 주변 배치가 움직이지 않는다.
/// * 감소 동작: 전환 0ms, 스피너/체크/문구 교체만.
class MotionProcessingButton extends StatelessWidget {
  const MotionProcessingButton({
    super.key,
    required this.busy,
    required this.onPressed,
    required this.label,
    required this.builder,
    this.feedback,
    this.spinner,
    this.successIcon = Icons.check_rounded,
    this.foreground,
    this.pressedScale = .975,
  }) : assert(pressedScale > 0 && pressedScale <= 1);

  /// 주의 행동형(나가기·삭제·취소)의 절제된 눌림.
  static const double cautiousScale = .99;

  final bool busy;
  final VoidCallback? onPressed;
  final Widget label;
  final ProcessingButtonBuilder builder;
  final ProcessingFeedback? feedback;
  final Widget? spinner;
  final IconData successIcon;

  /// 체크 아이콘/기본 스피너 색. 기본은 DefaultTextStyle 색.
  final Color? foreground;
  final double pressedScale;

  static const Key labelKey = ValueKey('motion_processing_label');
  static const Key spinnerKey = ValueKey('motion_processing_spinner');
  static const Key successKey = ValueKey('motion_processing_success');

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && onPressed != null;
    final feedback = this.feedback;
    final Widget content = feedback == null
        ? _ProcessingSlot(
            phase: busy ? ProcessingPhase.busy : ProcessingPhase.idle,
            label: label,
            spinner: spinner,
            successIcon: successIcon,
            foreground: foreground,
          )
        : ValueListenableBuilder<ProcessingPhase>(
            valueListenable: feedback,
            builder: (context, phase, _) => _ProcessingSlot(
              phase: busy ? ProcessingPhase.busy : phase,
              label: label,
              spinner: spinner,
              successIcon: successIcon,
              foreground: foreground,
            ),
          );
    return MotionPress(
      enabled: enabled,
      pressedScale: pressedScale,
      child: builder(context, enabled ? onPressed : null, content),
    );
  }
}

class _ProcessingSlot extends StatelessWidget {
  const _ProcessingSlot({
    required this.phase,
    required this.label,
    required this.spinner,
    required this.successIcon,
    required this.foreground,
  });

  final ProcessingPhase phase;
  final Widget label;
  final Widget? spinner;
  final IconData successIcon;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final color = foreground ?? DefaultTextStyle.of(context).style.color;
    final Widget overlay;
    switch (phase) {
      case ProcessingPhase.busy:
        overlay = KeyedSubtree(
          key: MotionProcessingButton.spinnerKey,
          child: spinner ??
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                ),
              ),
        );
        break;
      case ProcessingPhase.success:
        overlay = Icon(
          successIcon,
          key: MotionProcessingButton.successKey,
          color: color,
          size: 22,
        );
        break;
      case ProcessingPhase.failure:
      case ProcessingPhase.idle:
        overlay = const SizedBox.shrink(key: ValueKey('motion_processing_none'));
        break;
    }
    final showLabel =
        phase == ProcessingPhase.idle || phase == ProcessingPhase.failure;
    final duration = MotionTokens.of(context, MotionTokens.state);
    return Stack(
      alignment: Alignment.center,
      children: [
        // The single label instance always reserves the slot size, so a
        // spinner or check never resizes the button or moves its neighbours.
        AnimatedOpacity(
          opacity: showLabel ? 1 : 0,
          duration: duration,
          curve: MotionTokens.curve,
          child: ExcludeSemantics(
            excluding: !showLabel,
            child: KeyedSubtree(
              key: MotionProcessingButton.labelKey,
              child: label,
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: duration,
          reverseDuration: MotionTokens.of(context, MotionTokens.fast),
          switchInCurve: MotionTokens.curve,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.center,
            children: [...previousChildren, if (currentChild != null) currentChild],
          ),
          child: overlay,
        ),
      ],
    );
  }
}
