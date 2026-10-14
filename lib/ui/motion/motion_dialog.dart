// lib/ui/motion/motion_dialog.dart
// 다이얼로그 등장: medium 페이드 + 0.96 → 1 크기(동작 줄이기면 즉시).

import 'package:flutter/material.dart';

import '../../design/tokens.dart';

Future<T?> showMotionDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final reduce = MotionTokens.reduceMotion(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: reduce ? Duration.zero : MotionTokens.medium,
    pageBuilder: (dialogContext, _, __) => builder(dialogContext),
    transitionBuilder: (context, animation, _, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: MotionTokens.curve);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: .96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
