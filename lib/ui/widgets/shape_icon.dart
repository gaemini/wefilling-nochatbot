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

  // 네모는 면적감이 커서 상대적으로 커 보이므로
  // 다른 도형(특히 원)과의 체감 크기를 맞추기 위해 패딩을 조금 늘려 줄인다.
  @override
  double get pad => 0.12;

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

  // 별은 내부 여백(음영)이 커서 상대적으로 작아 보이므로
  // 원/사각형 대비 체감 크기를 맞추기 위해 패딩을 줄여 크게 렌더링한다.
  @override
  double get pad => 0.04;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()..color = color..style = PaintingStyle.fill..isAntiAlias = true;
    final p = size.width * pad;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outerR = (size.width - p * 2) / 2;
    // 별의 중앙 오목함을 조금 줄여 면적감을 확보
    final innerR = outerR * 0.56;

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

  // 하트는 곡선 형태로 인해 여백이 크게 느껴져 작아 보이므로
  // 별과 동일하게 패딩을 줄여 체감 크기를 맞춘다.
  @override
  double get pad => 0.02;

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
    // 하트 베지어(정규화)
    // - 위쪽 홈(notch)과 아래쪽 뾰족함을 살리기 위해
    //   "둥근" 컨트롤 포인트를 줄이고 곡률 변화를 크게 준다.
    // - 캔버스 밖으로 튀지 않도록 컨트롤 포인트는 [x, x+w] 범위 내로 유지.
    final cx = x + w / 2;
    final bottomY = y + h;
    final notchY = y + h * 0.28;

    path.moveTo(cx, bottomY);
    // 오른쪽 반쪽: 아래 → 오른쪽 볼록 → 위쪽 홈
    path.cubicTo(
      x + w * 0.60, y + h * 0.86,
      x + w * 0.98, y + h * 0.58,
      x + w * 0.84, y + h * 0.36,
    );
    path.cubicTo(
      x + w * 0.72, y + h * 0.14,
      x + w * 0.56, y + h * 0.10,
      cx, notchY,
    );
    // 왼쪽 반쪽: 위쪽 홈 → 왼쪽 볼록 → 아래
    path.cubicTo(
      x + w * 0.44, y + h * 0.10,
      x + w * 0.28, y + h * 0.14,
      x + w * 0.16, y + h * 0.36,
    );
    path.cubicTo(
      x + w * 0.02, y + h * 0.58,
      x + w * 0.40, y + h * 0.86,
      cx, bottomY,
    );
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

