// lib/snapshot/snack_feel_icon.dart
// 필링 아이콘: 두 원이 겹친 모양("서로"). 하트는 포스트 좋아요 전용이다.
//
// viewBox 24 기준 원 중심 (9,12)·(15,12), 반지름 6.2.
// - 외곽선: 두 원 모두 stroke 1.8, 채움 없음.
// - 채움: 왼쪽 원 100%, 오른쪽 원 55% 불투명, 겹친 렌즈는 흰색 90%.

import 'dart:math' as math;

import 'package:flutter/material.dart';

class SnackFeelIcon extends StatelessWidget {
  const SnackFeelIcon({
    super.key,
    this.size = 24,
    this.filled = false,
    this.color = Colors.white,
    this.lensColor = Colors.white,
  });

  final double size;
  final bool filled;
  final Color color;

  /// 채움 상태에서 겹친 부분 색(기본 흰색 90%로 그려진다).
  final Color lensColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: SnackFeelIconPainter(
          filled: filled,
          color: color,
          lensColor: lensColor,
        ),
      ),
    );
  }
}

class SnackFeelIconPainter extends CustomPainter {
  const SnackFeelIconPainter({
    required this.filled,
    required this.color,
    required this.lensColor,
  });

  final bool filled;
  final Color color;
  final Color lensColor;

  static const double _viewBox = 24;
  static const Offset _leftCenter = Offset(9, 12);
  static const Offset _rightCenter = Offset(15, 12);
  static const double _radius = 6.2;
  static const double _stroke = 1.8;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _viewBox;
    canvas.save();
    canvas.scale(scale);
    if (!filled) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = color;
      canvas.drawCircle(_leftCenter, _radius, paint);
      canvas.drawCircle(_rightCenter, _radius, paint);
    } else {
      canvas.drawCircle(_leftCenter, _radius, Paint()..color = color);
      canvas.drawCircle(
        _rightCenter,
        _radius,
        Paint()..color = color.withValues(alpha: .55),
      );
      final left = Path()
        ..addOval(Rect.fromCircle(center: _leftCenter, radius: _radius));
      final right = Path()
        ..addOval(Rect.fromCircle(center: _rightCenter, radius: _radius));
      final lens = Path.combine(PathOperation.intersect, left, right);
      canvas.drawPath(
        lens,
        Paint()..color = lensColor.withValues(alpha: .9),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SnackFeelIconPainter old) =>
      old.filled != filled || old.color != color || old.lensColor != lensColor;

  /// 테스트용: 두 원이 겹치는 가로 폭(viewBox 단위).
  static double get overlapWidth =>
      math.max(0, 2 * _radius - (_rightCenter.dx - _leftCenter.dx));
}
