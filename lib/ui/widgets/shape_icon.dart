import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 카테고리 도형 아이콘 공통 렌더러
/// - shape_triangle: 정삼각형(채움) 커스텀 페인터로 렌더링
/// - 나머지: Material Icon 사용
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
    if (iconName == 'shape_triangle' ||
        iconName == 'shape_triangle_filled' ||
        iconName == 'shape_triangle_outline') {
      return CustomPaint(
        size: Size.square(size),
        painter: _EquilateralTrianglePainter(color: color),
      );
    }

    return Icon(_toIconData(iconName), color: color, size: size);
  }

  IconData _toIconData(String iconName) {
    switch (iconName) {
      case 'shape_circle':
      case 'shape_circle_filled':
        return Icons.circle;
      case 'shape_circle_outline':
        return Icons.radio_button_unchecked;
      case 'shape_square':
      case 'shape_square_filled':
        return Icons.stop;
      case 'shape_square_outline':
        return Icons.crop_square;
      case 'shape_star':
      case 'shape_star_filled':
        return Icons.star;
      case 'shape_star_outline':
        return Icons.star_border;
      case 'shape_heart':
        return Icons.favorite;
      case 'shape_cross':
        return Icons.add;
      default:
        return Icons.group;
    }
  }
}

class _EquilateralTrianglePainter extends CustomPainter {
  final Color color;

  _EquilateralTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()..color = color..style = PaintingStyle.fill..isAntiAlias = true;

    // 정삼각형 높이 = 변 * sqrt(3) / 2
    final side = size.width;
    final triH = side * math.sqrt(3) / 2;
    final yOffset = (size.height - triH) / 2;

    final path = Path()
      ..moveTo(side / 2, yOffset) // top
      ..lineTo(0, yOffset + triH) // bottom-left
      ..lineTo(side, yOffset + triH) // bottom-right
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _EquilateralTrianglePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

