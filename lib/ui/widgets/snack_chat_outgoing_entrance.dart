import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// Paint-only entrance motion for a message created by the local sender.
///
/// The widget deliberately owns no delivery state. A Firestore commit can
/// complete before, during, or after this motion without restarting it.
class SnackChatOutgoingEntrance extends StatefulWidget {
  const SnackChatOutgoingEntrance({
    super.key,
    required this.animateOnMount,
    required this.onAnimationClaimed,
    required this.child,
  });

  /// Prevents a message that was inserted while its row was offscreen from
  /// animating much later when the user returns to the newest messages.
  static const Duration claimWindow = Duration(milliseconds: 400);

  final bool animateOnMount;
  final VoidCallback onAnimationClaimed;
  final Widget child;

  @override
  State<SnackChatOutgoingEntrance> createState() =>
      _SnackChatOutgoingEntranceState();
}

class _SnackChatOutgoingEntranceState extends State<SnackChatOutgoingEntrance> {
  late final bool _animate = widget.animateOnMount;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    if (_animate) {
      // Claim once when the row is first mounted. Later delivery snapshots
      // rebuild the same keyed state and therefore cannot replay the motion.
      widget.onAnimationClaimed();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_animate || _completed) return widget.child;

    final mediaQuery = MediaQuery.of(context);
    final reduceMotion =
        mediaQuery.disableAnimations || mediaQuery.accessibleNavigation;
    if (reduceMotion) return widget.child;

    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: DesignTokens.normal,
        curve: Curves.easeOutCubic,
        onEnd: () {
          if (mounted) setState(() => _completed = true);
        },
        child: widget.child,
        builder: (context, progress, child) {
          final easedOpacity = .86 + (.14 * progress);
          final easedScale = .985 + (.015 * progress);
          final remainingDistance = 18 * (1 - progress);
          return Opacity(
            opacity: easedOpacity,
            child: Transform.translate(
              offset: Offset(0, remainingDistance),
              child: Transform.scale(
                alignment: Alignment.bottomCenter,
                scale: easedScale,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}
