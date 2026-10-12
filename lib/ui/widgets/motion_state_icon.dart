import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// A short, paint-only transition between two states of an action icon.
/// The surrounding button owns input and state; this widget never delays it.
class MotionStateIcon extends StatelessWidget {
  const MotionStateIcon({
    super.key,
    required this.selected,
    required this.inactiveIcon,
    required this.activeIcon,
    required this.color,
    required this.size,
  });

  final bool selected;
  final IconData inactiveIcon;
  final IconData activeIcon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MotionTokens.reduceMotion(context);
    return AnimatedSwitcher(
      key: ValueKey(reduceMotion),
      duration: reduceMotion ? Duration.zero : MotionTokens.state,
      reverseDuration: reduceMotion ? Duration.zero : MotionTokens.fast,
      switchInCurve: MotionTokens.curve,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: reduceMotion
            ? child
            : ScaleTransition(
                scale: Tween<double>(begin: 1.16, end: 1).animate(animation),
                child: child,
              ),
      ),
      child: Icon(
        selected ? activeIcon : inactiveIcon,
        key: ValueKey(selected),
        color: color,
        size: size,
      ),
    );
  }
}
