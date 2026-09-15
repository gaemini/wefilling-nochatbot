import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snack_chat_message.dart';
import 'package:wefilling/services/snack_chat_service.dart';
import 'package:wefilling/services/snack_chat_summary_run.dart';
import 'package:wefilling/utils/snack_chat_mentions.dart';

void main() {
  test('literal @ opens the picker even when the keyboard marks it composing',
      () {
    final controller = SnackChatMentionController();
    addTearDown(controller.dispose);
    const input = TextEditingValue(
        text: '@',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1));
    controller.value = input;
    expect(controller.activeQuery, const TextRange(start: 0, end: 1));
    expect(controller.value, input);
    expect(controller.insertMention('participant', '민수'), isTrue);
    expect(controller.mentions.single.userId, 'participant');
  });
  test('mention identity survives surrounding edits but not edits/paste/undo',
      () {
    final c = SnackChatMentionController();
    addTearDown(c.dispose);
    c.value = const TextEditingValue(
        text: '😀 @민', selection: TextSelection.collapsed(offset: 5));
    expect(c.insertMention('uid-1', '민수'), isTrue);
    expect(c.mentions.single.start, 3);
    c.value = TextEditingValue(
        text: '  ${c.text}',
        selection: const TextSelection.collapsed(offset: 9));
    expect(c.trimmedMentions.single.start, 3);
    expect(c.mentions.single.userId, 'uid-1');
    final original = c.value;
    c.value = c.value.copyWith(text: c.text.replaceFirst('민수', '민지'));
    expect(c.mentions, isEmpty);
    c.value = original; // undo restores text, never invents selected identity
    expect(c.mentions, isEmpty);
    c.clear();
    c.text = '@민수 '; // paste is plain text
    expect(c.mentions, isEmpty);
  });

  test('IME Korean/Chinese composing values are never rewritten', () {
    final c = SnackChatMentionController();
    addTearDown(c.dispose);
    for (final text in ['@ㄱ', '@가', '@微', '@微邻']) {
      final next = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
          composing: TextRange(start: 1, end: text.length));
      c.value = next;
      expect(c.value, next);
      expect(c.activeQuery, isNull);
      expect(c.insertMention('uid', 'name'), isFalse);
    }
  });

  test('optional mention serialization does not change legacy messages', () {
    final message = SnackChatMessage(
        id: 'fixed',
        senderId: 'sender',
        text: '@微邻 hi',
        createdAt: DateTime(2026),
        sendStatus: MessageSendStatus.uncertain,
        mentions: const [
          SnackChatMention(userId: 'uid', displayName: '微邻', start: 0, end: 3)
        ]);
    expect(message.isPending, isTrue);
    expect(message.needsRetry, isTrue);
    expect(message.hasFailed, isFalse);
    final raw = message.toFirestore();
    expect(raw.containsKey('sendStatus'), isFalse);
    final copy = SnackChatMessage.fromMap('fixed', raw);
    expect(copy.mentions.single.userId, 'uid');
    expect(copy.id, 'fixed');
    raw.remove('mentions');
    expect(SnackChatMessage.fromMap('fixed', raw).mentions, isEmpty);
    final legacySummary = SnackChatUnreadSummaryResult.fromMap({
      'summarySchemaVersion': 3,
      'sections': [
        {
          'type': 'sharedInformation',
          'items': [
            {
              'title': 'Legacy',
              'description': 'Original evidence',
              'sourceMessageIds': ['old'],
              'representativeMessageId': 'old',
              'sourceSequences': <int>[],
            }
          ]
        }
      ],
    });
    expect(legacySummary.items.single.representativeMessageId, 'old');
  });

  test('overlap dedupe retains distinct facts from one source message', () {
    SnackChatUnreadSummarySection section(String text) =>
        SnackChatUnreadSummarySection(
            type: SnackChatSummarySectionType.sharedInformation,
            title: '',
            items: [
              SnackChatUnreadSummaryItem(
                  content: text,
                  label: text,
                  sourceSequences: const [],
                  sourceMessageIds: const ['source'],
                  representativeMessageId: 'source')
            ]);
    final merged = mergeSnackSummarySections(
        [section('Place'), section('Time'), section('Place')]);
    expect(merged.single.items.length, 2);
    expect(merged.single.items.map((i) => i.content),
        containsAll(['Place', 'Time']));
  });
}
