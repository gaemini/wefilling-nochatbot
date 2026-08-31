import 'dart:math' as math;

import 'package:flutter/material.dart';

class SnackChatPeopleSheetContent extends StatelessWidget {
  const SnackChatPeopleSheetContent({
    super.key,
    required this.rootSystemBottomInset,
    required this.children,
  });

  /// Modal route가 Android의 하단 system inset을 제거하는 경우를 대비해
  /// 호출 화면에서 보존한 값이다.
  final double rootSystemBottomInset;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.width < 360 || media.size.height < 640;
    final horizontalPadding = media.size.width < 360 ? 16.0 : 20.0;
    final systemBottomInset = math.max(
      rootSystemBottomInset,
      math.max(media.viewPadding.bottom, media.padding.bottom),
    );
    final bottomPadding = systemBottomInset + (compact ? 10.0 : 14.0);
    final availableHeight = math.max(
      0.0,
      media.size.height - media.viewPadding.top - 12.0,
    );
    final maxHeight = math.min(media.size.height * 0.72, availableHeight);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: ListView(
          key: const ValueKey('snack_chat_people_safe_content'),
          shrinkWrap: true,
          primary: false,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            bottomPadding,
          ),
          children: children,
        ),
      ),
    );
  }
}
