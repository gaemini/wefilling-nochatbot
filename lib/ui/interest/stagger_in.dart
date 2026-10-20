import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// 목록 줄이 [offset]px 아래에서 올라오며 나타난다. [index]마다 [step]씩 늦게(최대 8줄까지).
/// 필터를 바꿀 때 목록 키를 바꾸면 다시 재생된다. 동작 줄이기면 바로 보인다.
class StaggerIn extends StatefulWidget {
  const StaggerIn({
    super.key,
    required this.index,
    required this.child,
    this.offset = 10,
    this.scaleFrom = 1,
    this.step = const Duration(milliseconds: 35),
    this.duration = const Duration(milliseconds: 320),
    this.curve = MotionTokens.curve,
  });

  final int index;
  final Widget child;
  final double offset;

  /// 1보다 작으면 커지며 나타난다(블록 보기 전환 0.92).
  final double scaleFrom;
  final Duration step;
  final Duration duration;
  final Curve curve;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  // 지연은 타이머 대신 구간으로 둔다(앞부분은 멈춰 있음).
  late final Duration _delay = widget.step * widget.index.clamp(0, 8);
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration + _delay);
  late final double _start = _delay.inMicroseconds /
      (widget.duration + _delay).inMicroseconds;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MotionTokens.reduceMotion(context)) {
      _controller.value = 1;
      return;
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final local = Interval(_start, 1).transform(_controller.value);
        final t = widget.curve.transform(local);
        final fade = local.clamp(0.0, 1.0);
        return Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - t)),
            child: widget.scaleFrom == 1
                ? child
                : Transform.scale(
                    scale: widget.scaleFrom + (1 - widget.scaleFrom) * t,
                    child: child,
                  ),
          ),
        );
      },
    );
  }
}
