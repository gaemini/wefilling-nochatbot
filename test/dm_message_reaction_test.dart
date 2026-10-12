import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/dm_message.dart';
import 'package:wefilling/ui/widgets/chat_reaction_widgets.dart';

void main() {
  Map<String, dynamic> localMessage({Map<String, int>? reactionCounts}) =>
      <String, dynamic>{
        'id': 'message-1',
        'senderId': 'user-1',
        'text': 'hello',
        'createdAtMs': DateTime(2026, 9, 16).millisecondsSinceEpoch,
        'isRead': false,
        'deliveryState': 'sent',
        if (reactionCounts != null) 'reactionCounts': reactionCounts,
      };

  test('legacy cached DM without reactionCounts remains readable', () {
    final message = DMMessage.fromLocalMap(localMessage());
    expect(message.reactionCounts, isEmpty);
  });

  test('DM reactionCounts survive local cache round trip', () {
    final message = DMMessage.fromLocalMap(
      localMessage(reactionCounts: const <String, int>{'❤️': 2, '👍': 1}),
    );

    final restored = DMMessage.fromLocalMap(message.toLocalMap());
    expect(restored.reactionCounts, const <String, int>{'❤️': 2, '👍': 1});
  });

  testWidgets('reaction picker fits a narrow screen and exposes selection',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatReactionPickerRow(
            selectedReaction: '❤️',
            addLabel: 'Add reaction',
            removeLabel: 'Remove reaction',
            onSelected: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ChatReactionIcon), findsNWidgets(6));
    expect(
      tester.getSemantics(find.byTooltip('Remove reaction ❤️')).hasFlag(
            SemanticsFlag.isSelected,
          ),
      isTrue,
    );
  });
}
