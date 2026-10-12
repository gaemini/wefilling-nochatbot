import 'package:flutter/material.dart';

import '../../utils/meetup_calendar_marker_policy.dart';
import 'audience_ring.dart';

/// 달력 날짜의 모임 상태를 표시하는 공통 링.
///
/// 일반 공개/허용 모임은 단색 파란색, 친구가 만든 모임이 하나라도 포함되면
/// 공개범위 링과 같은 그라데이션을 사용한다.
class MeetupCalendarDayRing extends StatelessWidget {
  const MeetupCalendarDayRing({
    super.key,
    required this.style,
    required this.size,
    required this.child,
    this.semanticLabel,
    this.strokeWidth = 2.5,
  });

  static const Color solidBlue = Color(0xFF2E90FA);

  final MeetupCalendarMarkerStyle style;
  final double size;
  final Widget child;
  final String? semanticLabel;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case MeetupCalendarMarkerStyle.none:
        return SizedBox.square(dimension: size, child: child);
      case MeetupCalendarMarkerStyle.solidBlue:
        final ring = SizedBox.square(
          dimension: size,
          child: CustomPaint(
            foregroundPainter: _SolidCircleBorderPainter(
              color: solidBlue,
              strokeWidth: strokeWidth,
            ),
            child: ClipOval(child: child),
          ),
        );
        return semanticLabel == null
            ? ring
            : Semantics(label: semanticLabel, container: true, child: ring);
      case MeetupCalendarMarkerStyle.friendGradient:
        return AudienceRing(
          restricted: true,
          emphasized: true,
          size: size,
          ringWidth: strokeWidth,
          semanticLabel: semanticLabel,
          child: child,
        );
    }
  }
}

class _SolidCircleBorderPainter extends CustomPainter {
  const _SolidCircleBorderPainter({
    required this.color,
    required this.strokeWidth,
  });

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;
    final inset = strokeWidth / 2;
    canvas.drawOval((Offset.zero & size).deflate(inset), paint);
  }

  @override
  bool shouldRepaint(covariant _SolidCircleBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
