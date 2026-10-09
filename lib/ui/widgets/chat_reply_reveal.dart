import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// A stable composer slot: showing a reply does not remount the text input.
class ChatReplyReveal extends StatelessWidget {
  const ChatReplyReveal({super.key, required this.replyId, this.child});

  final String? replyId;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final reduced = MotionTokens.reduceMotion(context);
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : MotionTokens.state,
      switchInCurve: MotionTokens.curve,
      switchOutCurve: MotionTokens.curve,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [
          for (final child in previous)
            Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: IgnorePointer(child: ExcludeSemantics(child: child))),
          if (current != null) current,
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: child == null
          ? const SizedBox(key: ValueKey('empty-reply'), width: double.infinity)
          : KeyedSubtree(key: ValueKey(replyId), child: child!),
    );
  }
}
