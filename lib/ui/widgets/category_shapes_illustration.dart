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
    final tile = s * 0.33; // 120 -> ~40
    final gap = s * 0.06; // 120 -> ~7

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
        child: Stack(
          alignment: Alignment.center,
          children: [
            // AppEmptyState 기본 원형 스타일과 톤을 맞춤
            Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                color: UIUtils.safeColorWithOpacity(AppColors.pointColor, 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: UIUtils.safeColorWithOpacity(AppColors.pointColor, 0.2),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: UIUtils.safeColorWithOpacity(Colors.black, 0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),

            // 중앙 2x2 그리드로 정갈하게 배치 (다른 페이지들과 통일감)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ShapeTile(
                      size: tile,
                      iconName: 'shape_circle',
                      color: AppColors.accentRed,
                    ),
                    SizedBox(width: gap),
                    _ShapeTile(
                      size: tile,
                      iconName: 'shape_triangle',
                      color: AppColors.accentAmber,
                    ),
                  ],
                ),
                SizedBox(height: gap),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ShapeTile(
                      size: tile,
                      iconName: 'shape_square',
                      color: AppColors.accentEmerald,
                    ),
                    SizedBox(width: gap),
                    _ShapeTile(
                      size: tile,
                      iconName: 'shape_star',
                      color: AppColors.pointColor,
                    ),
                  ],
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
    final iconSize = size * 0.58;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: Center(
        child: ShapeIcon(
          iconName: iconName,
          color: color,
          size: iconSize,
        ),
      ),
    );
  }
}

