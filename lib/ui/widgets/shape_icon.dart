import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 카테고리 도형 아이콘 공통 렌더러
/// - 모든 shape_* 도형을 동일한 캔버스 기준(CustomPaint)으로 렌더링해
///   아이콘 폰트별 여백 차이로 생기는 "크기 들쭉날쭉"을 제거한다.
class ShapeIcon extends StatelessWidget {
  final String iconName;
  final Color color;
  final double size;

  const ShapeIcon({
    super.key,
    required this.iconName,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final painter = _painterFor(iconName, color);
    if (painter != null) {
      return CustomPaint(
        size: Size.square(size),
        painter: painter,
      );
    }

    // 알 수 없는 값은 기존 기본 아이콘으로 폴백
    return Icon(Icons.group, color: color, size: size);
  }

  CustomPainter? _painterFor(String iconName, Color color) {
    switch (iconName) {
      case 'shape_circle':
      case 'shape_circle_filled':
      case 'shape_circle_outline':
        return _CirclePainter(color: color);
      case 'shape_square':
      case 'shape_square_filled':
      case 'shape_square_outline':
        return _SquarePainter(color: color);
      case 'shape_triangle':
      case 'shape_triangle_filled':
      case 'shape_triangle_outline':
        return _EquilateralTrianglePainter(color: color);
      case 'shape_star':
      case 'shape_star_filled':
      case 'shape_star_outline':
        return _StarPainter(color: color);
      case 'shape_heart':
        return _HeartPainter(color: color);
      case 'shape_cross':
        return _CrossPainter(color: color);
      default:
        return null;
    }
  }
}

abstract class _BaseShapePainter extends CustomPainter {
  final Color color;

  // 캔버스 가장자리 클리핑 방지용 패딩
  static const double _padFactor = 0.08;

  const _BaseShapePainter({required this.color});

  double get pad => _padFactor;

  @override
  bool shouldRepaint(covariant _BaseShapePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _CirclePainter extends _BaseShapePainter {
  const _CirclePainter({required super.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()..color = color..style = PaintingStyle.fill..isAntiAlias = true;
    final p = size.width * pad;
    final r = (size.width - p * 2) / 2;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), r, paint);
  }
}

class _SquarePainter extends _BaseShapePainter {
  const _SquarePainter({required super.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()..color = color..style = PaintingStyle.fill..isAntiAlias = true;
    final p = size.width * pad;
    canvas.drawRect(Rect.fromLTWH(p, p, size.width - p * 2, size.height - p * 2), paint);
  }
}

class _EquilateralTrianglePainter extends _BaseShapePainter {
  const _EquilateralTrianglePainter({required Color color}) : super(color: color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()..color = color..style = PaintingStyle.fill..isAntiAlias = true;

    // 정삼각형 높이 = 변 * sqrt(3) / 2
    final p = size.width * pad;
    final side = size.width - p * 2;
    final triH = side * math.sqrt(3) / 2;
    final yOffset = (size.height - triH) / 2;

    final path = Path()
      ..moveTo(size.width / 2, yOffset) // top
      ..lineTo(p, yOffset + triH) // bottom-left
      ..lineTo(size.width - p, yOffset + triH) // bottom-right
      ..close();

    canvas.drawPath(path, paint);
  }
}

class _StarPainter extends _BaseShapePainter {
  const _StarPainter({required super.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()..color = color..style = PaintingStyle.fill..isAntiAlias = true;
    final p = size.width * pad;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outerR = (size.width - p * 2) / 2;
    final innerR = outerR * 0.5;

    final path = Path();
    const points = 5;
    final startAngle = -math.pi / 2;
    for (int i = 0; i < points * 2; i++) {
      final isOuter = i.isEven;
      final r = isOuter ? outerR : innerR;
      final angle = startAngle + (math.pi / points) * i;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }
}

class _HeartPainter extends _BaseShapePainter {
  const _HeartPainter({required super.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()..color = color..style = PaintingStyle.fill..isAntiAlias = true;
    final p = size.width * pad;
    final w = size.width - p * 2;
    final h = size.height - p * 2;
    final x = p;
    final y = p;

    final path = Path();
    // 간단한 하트 베지어(정규화)
    path.moveTo(x + w / 2, y + h);
    path.cubicTo(x + w * 1.05, y + h * 0.62, x + w * 0.92, y + h * 0.18, x + w / 2, y + h * 0.32);
    path.cubicTo(x + w * 0.08, y + h * 0.18, x - w * 0.05, y + h * 0.62, x + w / 2, y + h);
    path.close();

    canvas.drawPath(path, paint);
  }
}

class _CrossPainter extends _BaseShapePainter {
  const _CrossPainter({required super.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()..color = color..style = PaintingStyle.fill..isAntiAlias = true;
    final p = size.width * pad;
    final w = size.width - p * 2;
    final h = size.height - p * 2;
    final thickness = w * 0.24;
    final cx = size.width / 2;
    final cy = size.height / 2;

    final rectV = Rect.fromCenter(center: Offset(cx, cy), width: thickness, height: h);
    final rectH = Rect.fromCenter(center: Offset(cx, cy), width: w, height: thickness);
    canvas.drawRect(rectV, paint);
    canvas.drawRect(rectH, paint);
  }
}

