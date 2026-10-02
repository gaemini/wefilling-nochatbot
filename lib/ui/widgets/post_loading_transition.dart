import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// Fades the initial feed skeleton into its first loaded item. Keep the same
/// wrapper after loading so subsequent post updates do not replay the effect.
class PostLoadingTransition extends StatelessWidget {
  const PostLoadingTransition({
    super.key,
    required this.loading,
    required this.child,
  });

  final bool loading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: MotionTokens.reduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      switchInCurve: MotionTokens.curve,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      child: KeyedSubtree(
        key: ValueKey<bool>(loading),
        child: child,
      ),
    );
  }
}
