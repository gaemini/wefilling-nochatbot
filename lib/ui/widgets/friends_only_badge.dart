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
  final double fontSize;
  final double gap;
  final FontWeight fontWeight;
  final Color? foregroundColor;

  const FriendsOnlyBadge({
    super.key,
    required this.label,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.iconSize = 15,
    this.radius = 16,
    this.fontSize = 12,
    this.gap = 6,
    this.fontWeight = FontWeight.w700,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    // 배경 제거: 글씨와 아이콘만 표시
    final fg = foregroundColor ?? AppColors.friendsOnlyAccent;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShapeIcon(
          iconName: 'shape_triangle',
          color: fg,
          size: iconSize,
        ),
        SizedBox(width: gap),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: fg,
            height: 1,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}
