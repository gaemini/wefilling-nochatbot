import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/services/snack_chat_service.dart';
import 'package:wefilling/ui/sheets/snack_chat_unread_summary_sheet.dart';

void main() {
  testWidgets('summary sheet remains scrollable on a small, large-text screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const responseItem = SnackChatUnreadSummaryItem(
      label: 'Attendance confirmation with a very long identifier',
      content: 'Please confirm whether @very_long_user_identifier can attend '
          'the Friday meeting at https://example.com/a/very/long/path/value.',
      status: SnackChatSummaryStatus.responseRequired,
      sourceSequences: <int>[1, 2],
    );
    const actionItem = SnackChatUnreadSummaryItem(
      label: '발표 자료',
      content: '오늘까지 발표 자료를 정리해 보내야 해요.',
      sourceSequences: <int>[3],
    );
    const changedItem = SnackChatUnreadSummaryItem(
      label: '모임 시간',
      content: '모임 시간이 오후 6시에서 7시로 변경됐어요.',
      status: SnackChatSummaryStatus.changed,
      sourceSequences: <int>[4],
    );
    const sections = <SnackChatUnreadSummarySection>[
      SnackChatUnreadSummarySection(
        type: SnackChatSummarySectionType.mustKnow,
        title: '',
        items: <SnackChatUnreadSummaryItem>[actionItem],
      ),
      SnackChatUnreadSummarySection(
        type: SnackChatSummarySectionType.responseRequired,
        title: 'Needs your response',
        items: <SnackChatUnreadSummaryItem>[responseItem],
      ),
      SnackChatUnreadSummarySection(
        type: SnackChatSummarySectionType.decisionsAndChanges,
        title: '',
        items: <SnackChatUnreadSummaryItem>[changedItem],
      ),
    ];
    const items = <SnackChatUnreadSummaryItem>[responseItem];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const <Locale>[Locale('ko'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSnackChatUnreadSummarySheet(
                  context,
                  items: items,
                  messageCount: 24,
                  sections: sections,
                  sourceStartedAt: DateTime.utc(2026, 9, 4, 8, 47),
                  sourceEndedAt: DateTime.utc(2026, 9, 4, 11, 15),
                  overview: 'The group is arranging Friday plans and needs '
                      'your attendance confirmation.',
                  otherConversationSummary:
                      'A few brief reactions followed the schedule discussion.',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('놓친 대화 정리'), findsOneWidget);
    expect(find.text('한눈에 보기'), findsOneWidget);
    expect(find.text('해야 할 일'), findsOneWidget);
    expect(find.text('답장이 필요한 내용'), findsOneWidget);
    expect(find.text('변경된 내용'), findsOneWidget);
    expect(find.text('Needs your response'), findsNothing);
    expect(find.text('답변 필요'), findsNothing);
    expect(find.text('변경'), findsNothing);
    expect(find.text('그 외 이야기'), findsOneWidget);
    final itemTitle = tester.widget<Text>(
      find.text('Attendance confirmation with a very long identifier'),
    );
    expect(itemTitle.style?.color, const Color(0xFF087BB5));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('today recap uses distinct localized title and metadata',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const <Locale>[Locale('ko'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSnackChatUnreadSummarySheet(
                context,
                items: const <SnackChatUnreadSummaryItem>[
                  SnackChatUnreadSummaryItem(
                    label: 'Meeting',
                    content: 'The meeting is confirmed for 5 PM.',
                    sourceSequences: <int>[350, 351],
                  ),
                ],
                messageCount: 24,
                sourceStartedAt: DateTime.utc(2026, 9, 5, 0, 10),
                sourceEndedAt: DateTime.utc(2026, 9, 5, 11, 42),
                overview: 'Today focused on the meeting plan.',
                rangeType: SnackChatSummaryRangeType.today,
              ),
              child: const Text('Open today'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open today'));
    await tester.pumpAndSettle();

    expect(find.text("Today's recap"), findsOneWidget);
    expect(find.textContaining('24 messages today'), findsOneWidget);
    expect(find.text('What you missed'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
