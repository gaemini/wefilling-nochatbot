import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import 'wf_colors.dart';

/// 태그 달기 버튼: 아직 안 단 태그는 ＋, 내 태그는 [checkedColor] 바탕 ✓.
/// 블록·둘러보기 목록·시트가 같이 쓴다.
///
/// 누르면 0.85로 줄고(120ms) 선택 햅틱. ＋→✓로 바뀔 때 ＋는 90° 돌며 사라지고
/// ✓는 -60°에서 돌아오며 커진다(350ms 넘침). 동시에 2px 고리가 2.3배로 퍼진다(550ms).
/// 동작 줄이기면 최종 모양만 즉시 보여 준다(햅틱은 유지).
class AddCheckButton extends StatefulWidget {
  const AddCheckButton({
    super.key,
    required this.added,
    required this.onPressed,
    required this.checkedColor,
    this.size = 38,
    this.idleColor = WfColors.surface,
    this.idleIconColor = WfColors.ink,
    this.semanticLabel,
  });

  final bool added;
  final VoidCallback? onPressed;

  /// ✓ 바탕(분류 dark).
  final Color checkedColor;
  final double size;

  /// ＋ 바탕: 목록은 회색 면, 블록 위는 흰 원.
  final Color idleColor;
  final Color idleIconColor;
  final String? semanticLabel;

  @override
  State<AddCheckButton> createState() => _AddCheckButtonState();
}

class _AddCheckButtonState extends State<AddCheckButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  bool _pressed = false;

  @override
  void didUpdateWidget(AddCheckButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.added &&
        widget.added &&
        !MotionTokens.reduceMotion(context)) {
      _ring.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MotionTokens.reduceMotion(context);
    final size = widget.size;
    final icon = widget.added
        ? Icon(Icons.check_rounded,
            key: const ValueKey('check'), size: size * .5, color: Colors.white)
        : Icon(Icons.add_rounded,
            key: const ValueKey('plus'),
            size: size * .55,
            color: widget.idleIconColor);
    // 터치 영역은 44 이상.
    final hit = math.max(44.0, size);
    return Semantics(
      button: true,
      toggled: widget.added,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onPressed == null ? null : (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onPressed == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onPressed!();
              },
        child: SizedBox(
          width: hit,
          height: hit,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _ring,
                  builder: (context, _) {
                    if (!_ring.isAnimating) return const SizedBox.shrink();
                    final t = Curves.easeOut.transform(_ring.value);
                    return IgnorePointer(
                      child: Container(
                        width: size * (1 + 1.3 * t),
                        height: size * (1 + 1.3 * t),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: widget.checkedColor
                                .withValues(alpha: (1 - t).clamp(0, 1)),
                            width: 2,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                AnimatedScale(
                  scale: _pressed ? .85 : 1,
                  duration: reduce ? Duration.zero : MotionTokens.pressShort,
                  curve: MotionTokens.pressSnappy,
                  child: AnimatedContainer(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          widget.added ? widget.checkedColor : widget.idleColor,
                    ),
                    child: reduce
                        ? icon
                        : AnimatedSwitcher(
                            duration: reduce
                                ? Duration.zero
                                : const Duration(milliseconds: 350),
                            switchInCurve: MotionTokens.springOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) {
                              final isCheck =
                                  child.key == const ValueKey('check');
                              final turn = Tween<double>(
                                // ✓는 -60°에서 0으로, ＋는 0에서 90°로(사라질 때 거꾸로 재생).
                                begin: isCheck ? -1 / 6 : 1 / 4,
                                end: 0,
                              ).animate(animation);
                              return RotationTransition(
                                turns: turn,
                                child: ScaleTransition(
                                    scale: animation, child: child),
                              );
                            },
                            child: icon,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
