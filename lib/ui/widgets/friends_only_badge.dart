import 'package:flutter/material.dart';
import 'shape_icon.dart';
import '../../constants/app_constants.dart';

/// 친구 공개(Friends Only) 배지
/// - 크기는 호출부에서 패딩/아이콘 크기로 동일 유지
/// - 아이콘은 앱에서 쓰는 정삼각형(ShapeIcon) 사용
class FriendsOnlyBadge extends StatelessWidget {
  final String label;
  final EdgeInsetsGeometry padding;
  final double iconSize;
  final double radius;

  const FriendsOnlyBadge({
    super.key,
    required this.label,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.iconSize = 15,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    // 기존 디자인(연한 주황 배경 + 주황 텍스트/아이콘)로 유지
    const bg = Color(0xFFFFF3E0);
    const fg = AppColors.friendsOnlyAccent;
    // 우측이 너무 어두워 보이지 않도록, 아주 미세하게만 톤을 내려주는 컬러
    const bgRight = Color(0xFFFFEBDD);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        children: [
          // 베이스 배경 (테두리 없음)
          Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [bg, bgRight],
              ),
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShapeIcon(
                  iconName: 'shape_triangle',
                  color: fg,
                  size: iconSize,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    height: 1,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),

          // 광택(좌→우 하이라이트): 색은 유지하면서 표면만 반짝이게
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.white.withAlpha(150),
                      Colors.white.withAlpha(40),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.28, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

