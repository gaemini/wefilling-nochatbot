// lib/ui/widgets/create_action_button.dart
// 만들기 버튼(포스트·밋업·새 메시지·스낵챗 열기)의 공통 모양.
// 높이 46, 좌우 18, `+` 20 / 400 + 라벨 15 / 600, 그림자 `0 4 14 #2C6BC0 30%`.
// 위치는 모두 오른쪽 16, 아래 16(스낵챗 탭과 같다).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/ui_locale.dart';
import 'motion_press.dart';

/// 만들기 버튼과 하단 사이 간격(오른쪽도 같은 값).
const double kCreateActionMargin = 16;

class CreateActionButton extends StatelessWidget {
  const CreateActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
    this.tooltip,
    this.showPlus = true,
    this.enabled = true,
  });

  static const double height = 46;

  final String label;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final String? tooltip;

  /// false면 `+` 없이 라벨만(예: 공유하기).
  final bool showPlus;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onPressed != null;
    Widget button = MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        button: true,
        enabled: active,
        label: semanticLabel ?? label,
        excludeSemantics: true,
        child: MotionPress(
          enabled: active,
          pressedScale: .975,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height / 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4D2C6BC0),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: const Color(0xFF2C6BC0),
              borderRadius: BorderRadius.circular(height / 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(height / 2),
                onTap: active
                    ? () {
                        HapticFeedback.lightImpact();
                        onPressed!();
                      }
                    : null,
                child: Container(
                  height: height,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showPlus) ...[
                        Text(
                          '+',
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontSize: 20,
                            height: 1.1,
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 15,
                          height: 20 / 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
