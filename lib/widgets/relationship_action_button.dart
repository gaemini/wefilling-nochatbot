import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../utils/responsive_helper.dart';

enum RelationshipActionButtonTone { primary, neutral }

/// 친구 관계 액션에 공통으로 사용하는 작은 버튼입니다.
///
/// 검색 결과와 친구 요청 목록에서 동일한 크기, 여백, 색상을 유지하며
/// 긴 번역 문구는 생략하지 않고 두 줄까지 표시합니다.
class RelationshipActionButton extends StatelessWidget {
  const RelationshipActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = RelationshipActionButtonTone.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final RelationshipActionButtonTone tone;

  @override
  Widget build(BuildContext context) {
    final isPrimary = tone == RelationshipActionButtonTone.primary;

    return Semantics(
      button: true,
      label: label,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor:
              isPrimary ? AppColors.pointColor : const Color(0xFFF2F4F7),
          foregroundColor: isPrimary ? Colors.white : const Color(0xFF344054),
          disabledBackgroundColor: const Color(0xFFF2F4F7),
          disabledForegroundColor: const Color(0xFF98A2B3),
          elevation: 0,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          maxLines: 2,
          softWrap: true,
          textAlign: TextAlign.center,
          overflow: TextOverflow.visible,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(12.5).clamp(11.5, 13).toDouble(),
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
      ),
    );
  }
}
