import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/screens/snack_chat_discovery_screen.dart';
import 'package:wefilling/services/snack_chat_service.dart';
import 'package:wefilling/ui/sheets/snack_chat_today_summary_picker_sheet.dart';
import 'package:wefilling/ui/sheets/snack_chat_unread_summary_sheet.dart';

void main() {
  for (final language in ['ko', 'en', 'zh']) {
    testWidgets('$language: source row wraps metadata at 320px with large text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SnackChatDiscoveryMessageRow(
                  room: 'room',
                  isSource: true,
                  row: const {
                    'id': 'source',
                    'senderName': 'A very long multilingual sender 이름 测试用户',
                    'createdAt': 1789372800000,
                    'type': 'text',
                    'text':
                        'A long original message that should wrap naturally without changing its meaning. 원문도 자연스럽게 줄바꿈됩니다. 中文原文也不会被截断。',
                  },
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
          find.text(language == 'ko'
              ? '원문'
              : language == 'zh'
                  ? '原文'
                  : 'Source'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in ['ko', 'en', 'zh']) {
    testWidgets(
        '$language: narrow large-text picker combines unread with related filter',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SnackChatTodaySummaryRequest? result;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
                viewPadding: const EdgeInsets.only(bottom: 24)),
            child: child!),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showSnackChatTodaySummaryPickerSheet(
                          context,
                          hasUnreadMessages: true);
                    },
                    child: const Text('open')))),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final checkbox = find.byType(CheckboxListTile);
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      final unread = find.byType(ChoiceChip).last;
      await tester.ensureVisible(unread);
      await tester.tap(unread);
      await tester.pumpAndSettle();
      // The footer uses a filled primary button, independent of locale text.
      final submit = find.byType(FilledButton);
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(result?.scope, SnackChatTodaySummaryScope.unread);
      expect(result?.relatedToMe, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('source navigation leaves recap and evidence intact on return',
      (tester) async {
    const item = SnackChatUnreadSummaryItem(
        label: 'A story',
        content: 'A useful casual story',
        sourceSequences: [],
        sourceMessageIds: ['source'],
        representativeMessageId: 'source');
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showSnackChatUnreadSummarySheet(context,
                              items: const [item],
                              messageCount: 1,
                              includeOtherConversation: true,
                              keepOpenOnSource: true,
                              sections: const [
                                SnackChatUnreadSummarySection(
                                    type: SnackChatSummarySectionType
                                        .otherConversation,
                                    title: 'Story',
                                    items: [item])
                              ], onOpenSource: (id) async {
                            expect(id, 'source');
                            await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => Scaffold(
                                    appBar:
                                        AppBar(title: const Text('Original')),
                                    body: const Text('Source text'))));
                          }),
                      child: const Text('open')),
                ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View message'));
    await tester.tap(find.text('View message'));
    await tester.pumpAndSettle();
    expect(find.text('Source text'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('A useful casual story'), findsOneWidget);
    expect(find.text('View message'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
