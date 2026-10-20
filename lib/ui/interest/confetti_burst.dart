import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// 색종이 12조각(950ms, 시드 고정). [trigger]가 바뀔 때마다 한 번 터진다.
/// 동작 줄이기면 그리지 않는다.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    super.key,
    required this.trigger,
    this.colors = const [
      Color(0xFF2E6CC2),
      Color(0xFFEB785A),
      Color(0xFF2DA578),
      Color(0xFFD7A523),
      Color(0xFF966EDC),
    ],
    this.size = 120,
  });

  /// 0이면 아무것도 하지 않는다.
  final int trigger;
  final List<Color> colors;
  final double size;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 950));

  @override
  void didUpdateWidget(ConfettiBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger &&
        widget.trigger != 0 &&
        !MotionTokens.reduceMotion(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _controller.isAnimating
              ? CustomPaint(
                  painter: _ConfettiPainter(_controller.value, widget.colors))
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.colors);

  final double t;
  final List<Color> colors;

  static final _pieces = () {
    final random = math.Random(7);
    return List.generate(12, (i) {
      final angle = -math.pi / 2 + (random.nextDouble() - .5) * math.pi * 1.4;
      return (
        angle: angle,
        speed: .55 + random.nextDouble() * .45,
        spin: (random.nextDouble() - .5) * 10,
        w: 5 + random.nextDouble() * 4,
      );
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final ease = Curves.easeOutCubic.transform(t);
    final reach = size.width * .5;
    final paint = Paint();
    for (var i = 0; i < _pieces.length; i++) {
      final p = _pieces[i];
      final dx = math.cos(p.angle) * reach * p.speed * ease;
      final dy = math.sin(p.angle) * reach * p.speed * ease + 40 * t * t;
      paint.color = colors[i % colors.length].withValues(alpha: 1 - t * t);
      canvas.save();
      canvas.translate(center.dx + dx, center.dy + dy);
      canvas.rotate(p.spin * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.w, height: p.w * .6),
            const Radius.circular(1.5)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
