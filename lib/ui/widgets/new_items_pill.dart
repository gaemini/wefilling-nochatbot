// lib/ui/widgets/new_items_pill.dart
// "새 댓글 3" · "↑ 새 포스트 2"처럼 목록 밖에서 새 항목을 알리는 알약 버튼.
// 나타날 때 위아래로 8px 움직이며 선명해지고(state), 사라질 때는 fast.
// 누르면 해당 위치로 간다.

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'motion_press.dart';

class NewItemsPill extends StatelessWidget {
  const NewItemsPill({
    super.key,
    required this.visible,
    required this.label,
    required this.onTap,
    this.icon,
    this.fromTop = false,
    this.color = const Color(0xFF111111),
    this.shadowColor = const Color(0x33000000),
  });

  final bool visible;
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  /// 위에서 내려오는 알약(새 포스트)인지. 아니면 아래에서 올라온다.
  final bool fromTop;

  /// 새 댓글은 검정, 새 포스트는 포인트 파랑.
  final Color color;
  final Color shadowColor;

  @override
  Widget build(BuildContext context) {
    final duration = MotionTokens.of(
      context,
      visible ? MotionTokens.state : MotionTokens.fast,
    );
    final textScaler = MediaQuery.textScalerOf(context).clamp(
      maxScaleFactor: 1.3,
    );
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : Offset(0, fromTop ? -.25 : .25),
        duration: duration,
        curve: MotionTokens.curve,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          curve: MotionTokens.curve,
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: MotionPress(
              enabled: visible,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: color,
                  shape: const StadiumBorder(),
                  shadows: [
                    BoxShadow(
                      color: shadowColor,
                      offset: const Offset(0, 4),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: onTap,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 32),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icon != null) ...[
                              Icon(icon, size: 15, color: Colors.white),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              label,
                              textScaler: textScaler,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                height: 1.2,
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
          ),
        ),
      ),
    );
  }
}
