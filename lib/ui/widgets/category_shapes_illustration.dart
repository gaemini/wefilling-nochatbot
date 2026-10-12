import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../utils/ui_utils.dart';
import 'shape_icon.dart';

/// 카테고리(친구 그룹) 빈 상태용 일러스트
/// - 아이콘 선택에 쓰는 4개 도형(원/삼각형/사각형/별)을 조합해
///   "기본 아이콘 1개" 느낌을 없애고, 완성도 있는 중앙 비주얼을 만든다.
class CategoryShapesIllustration extends StatelessWidget {
  final double size;

  const CategoryShapesIllustration({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    final s = size;
    final tile = s * 0.34;
    final gap = s * 0.13;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(
            opacity: UIUtils.safeOpacity(value),
            child: child,
          ),
        );
      },
      child: SizedBox(
        width: s,
        height: s,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ShapeTile(
                  size: tile,
                  iconName: 'shape_circle',
                  color: const Color(0xFF98A2B3),
                ),
                SizedBox(width: gap),
                _ShapeTile(
                  size: tile,
                  iconName: 'shape_triangle',
                  color: const Color(0xFF667085),
                ),
              ],
            ),
            SizedBox(height: gap),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ShapeTile(
                  size: tile,
                  iconName: 'shape_square',
                  color: AppColors.pointColor,
                ),
                SizedBox(width: gap),
                _ShapeTile(
                  size: tile,
                  iconName: 'shape_star',
                  color: const Color(0xFF475467),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShapeTile extends StatelessWidget {
  final double size;
  final String iconName;
  final Color color;

  const _ShapeTile({
    required this.size,
    required this.iconName,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ShapeIcon(
        iconName: iconName,
        color: color,
        size: size,
      ),
    );
  }
}
