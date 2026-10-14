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
    // 답장 바가 생기고 없어질 때 입력창 높이가 한 번에 바뀌면 대화 목록이
    // 튀므로, 키보드가 올라오는 동안 함께 부드럽게 늘고 줄게 한다.
    return AnimatedSize(
      duration: reduced ? Duration.zero : MotionTokens.state,
      curve: MotionTokens.curve,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
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
      ),
    );
  }
}
