// lib/ui/widgets/icon_motion.dart
// 아이콘 반응(모션 2부 E). 켤 때만 반응하고 끌 때는 조용히 교차한다.
// - [BellShake]: 알림을 켤 때만 종이 위쪽 축 기준으로 14° → -10° → 5° → 0°(500ms).
// - [MotionSendButton]: 댓글·DM·스낵챗 공용 보내기 버튼(비어 있음 #D9D9D9 .9 /
//   입력 있음 포인트 1.0, state).
// - [CopyFeedback]: 복사 버튼 글자가 "✓ 복사됨"으로 바뀌었다가 1.5초 뒤 돌아온다.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';

const Color kMotionPointColor = Color(0xFF2C6BC0);
const Color kSendInactiveColor = Color(0xFFD9D9D9);

class BellShake extends StatefulWidget {
  const BellShake({super.key, required this.ringing, required this.child});

  /// false → true로 바뀔 때만 흔든다.
  final bool ringing;
  final Widget child;

  @override
  State<BellShake> createState() => _BellShakeState();

  @visibleForTesting
  static double angleAtForTest(double t) => _BellShakeState.angleAt(t);
}

class _BellShakeState extends State<BellShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  @override
  void didUpdateWidget(covariant BellShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.ringing &&
        widget.ringing &&
        !MotionTokens.reduceMotion(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 0 → 14° → -10° → 5° → 0°.
  static double angleAt(double t) {
    const keys = <double>[0, 14, -10, 5, 0];
    const stops = <double>[0, .2, .5, .75, 1];
    for (var i = 1; i < stops.length; i++) {
      if (t <= stops[i]) {
        final local = (t - stops[i - 1]) / (stops[i] - stops[i - 1]);
        final eased = Curves.easeInOut.transform(local.clamp(0.0, 1.0));
        final degrees = keys[i - 1] + (keys[i] - keys[i - 1]) * eased;
        return degrees * math.pi / 180;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => Transform.rotate(
        key: const ValueKey('bell_shake'),
        angle: _controller.isAnimating ? angleAt(_controller.value) : 0,
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}

class MotionSendButton extends StatelessWidget {
  const MotionSendButton({
    super.key,
    required this.active,
    required this.onTap,
    required this.label,
    this.size = 32,
    this.touch = 44,
    this.iconSize = 18,
  });

  /// 보낼 내용이 있는지(색·크기만 바뀐다).
  final bool active;

  /// 누를 때. null이면 막힌다.
  final VoidCallback? onTap;
  final String label;
  final double size;
  final double touch;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final duration = MotionTokens.of(context, MotionTokens.state);
    return Semantics(
      button: true,
      enabled: active && onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        radius: touch / 2,
        child: SizedBox.square(
          dimension: touch,
          child: Center(
            child: AnimatedScale(
              key: const ValueKey('motion_send_scale'),
              scale: active ? 1 : .9,
              duration: duration,
              curve: MotionTokens.curve,
              child: AnimatedContainer(
                key: const ValueKey('motion_send_fill'),
                duration: duration,
                curve: MotionTokens.curve,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: active ? kMotionPointColor : kSendInactiveColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size: iconSize,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 복사한 뒤 1.5초 동안 [copied]가 true인 상태로 [builder]를 그린다.
class CopyFeedback extends StatefulWidget {
  const CopyFeedback({super.key, required this.builder});

  final Widget Function(
    BuildContext context,
    bool copied,
    VoidCallback markCopied,
  ) builder;

  static const Duration hold = Duration(milliseconds: 1500);

  @override
  State<CopyFeedback> createState() => _CopyFeedbackState();
}

class _CopyFeedbackState extends State<CopyFeedback> {
  bool _copied = false;
  Timer? _timer;

  void _markCopied() {
    _timer?.cancel();
    setState(() => _copied = true);
    _timer = Timer(CopyFeedback.hold, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _copied, _markCopied);
}

/// 복사 버튼 글자: 평소 [label], 복사 직후 체크(0 → 1.15 → 1, medium) + [copiedLabel].
class CopyFeedbackLabel extends StatelessWidget {
  const CopyFeedbackLabel({
    super.key,
    required this.copied,
    required this.label,
    required this.copiedLabel,
    required this.style,
    this.checkColor = kMotionPointColor,
  });

  final bool copied;
  final String label;
  final String copiedLabel;
  final TextStyle style;
  final Color checkColor;

  @override
  Widget build(BuildContext context) {
    final reduce = MotionTokens.reduceMotion(context);
    return AnimatedSwitcher(
      duration: MotionTokens.of(context, MotionTokens.fast),
      child: copied
          ? Row(
              key: const ValueKey('copy_feedback_copied'),
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: reduce ? 1 : 0, end: 1),
                  duration: MotionTokens.of(context, MotionTokens.medium),
                  builder: (context, t, child) => Transform.scale(
                    // 0 → 1.15 → 1
                    scale:
                        t < .6 ? 1.15 * (t / .6) : 1.15 - .15 * ((t - .6) / .4),
                    child: child,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: (style.fontSize ?? 14) + 2,
                    color: checkColor,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    copiedLabel,
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          : Text(
              label,
              key: const ValueKey('copy_feedback_idle'),
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
    );
  }
}
