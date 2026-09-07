import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/snack_chat_chrome.dart';

void main() {
  test('toolbar tracker respects reverse list visual direction and threshold',
      () {
    final tracker = SnackChatToolbarScrollTracker();

    expect(
      tracker.addUserDelta(
        axisDirection: AxisDirection.up,
        scrollDelta: -8,
        outOfRange: false,
        scrollableExtent: 400,
      ),
      isNull,
    );
    expect(
      tracker.addUserDelta(
        axisDirection: AxisDirection.up,
        scrollDelta: -8,
        outOfRange: false,
        scrollableExtent: 400,
      ),
      isFalse,
    );
    expect(tracker.visible, isFalse);

    expect(
      tracker.addUserDelta(
        axisDirection: AxisDirection.up,
        scrollDelta: 16,
        outOfRange: false,
        scrollableExtent: 400,
      ),
      isTrue,
    );
    expect(tracker.visible, isTrue);
  });

  test('toolbar tracker ignores bounce and stays visible without scrolling',
      () {
    final tracker = SnackChatToolbarScrollTracker();
    tracker.addUserDelta(
      axisDirection: AxisDirection.down,
      scrollDelta: 16,
      outOfRange: false,
      scrollableExtent: 400,
    );
    expect(tracker.visible, isFalse);

    expect(
      tracker.addUserDelta(
        axisDirection: AxisDirection.down,
        scrollDelta: -30,
        outOfRange: true,
        scrollableExtent: 400,
      ),
      isNull,
    );
    expect(tracker.visible, isFalse);
    expect(
      tracker.addUserDelta(
        axisDirection: AxisDirection.down,
        scrollDelta: 0,
        outOfRange: false,
        scrollableExtent: 0,
      ),
      isTrue,
    );
    expect(tracker.visible, isTrue);
  });

  test('Snack Chat date labels are localized with the full calendar date', () {
    final date = DateTime(2026, 9, 3);

    expect(
      SnackChatDateSeparator.formatDate(date, languageCode: 'ko'),
      '2026년 9월 3일 목요일',
    );
    expect(
      SnackChatDateSeparator.formatDate(date, languageCode: 'en'),
      'Thursday, September 3, 2026',
    );
  });

  testWidgets(
    'Snack Chat date marker is high-contrast and overflow-free on a narrow screen',
    (tester) async {
      const surfaceSize = Size(280, 480);
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: surfaceSize,
              textScaler: TextScaler.linear(2),
              viewPadding: EdgeInsets.only(bottom: 24),
            ),
            child: Scaffold(
              body: SnackChatDateSeparator(
                date: DateTime(2026, 9, 3),
                languageCode: 'ko',
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('2026년 9월 3일 목요일'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
      final badge = tester.widget<Container>(
        find.byKey(const ValueKey('snack_chat_date_badge')),
      );
      final decoration = badge.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFF667085));
      expect(
        tester.widget<Text>(find.text('2026년 9월 3일 목요일')).style?.color,
        Colors.white,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.calendar_today_outlined)).color,
        Colors.white,
      );
    },
  );

  testWidgets(
    'Snack Chat chrome stays distinct and overflow-free on a narrow Android screen',
    (tester) async {
      const surfaceSize = Size(320, 568);
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: surfaceSize,
              textScaler: TextScaler.linear(2),
              viewPadding: EdgeInsets.only(bottom: 24),
            ),
            child: Scaffold(
              appBar: AppBar(
                toolbarHeight: 58,
                centerTitle: true,
                leading: const Icon(Icons.arrow_back_rounded),
                actions: const [
                  SizedBox(
                    width: 48,
                    child: Icon(Icons.info_outline_rounded),
                  ),
                ],
                title: const SnackChatHeaderTitle(
                  roomTitle: '아주 긴 스낵챗 대화방 제목입니다',
                  participantLabel: '128명 참여',
                ),
              ),
              body: const SnackChatBackdrop(child: SizedBox.expand()),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('snack_chat_participant_badge')),
        findsOneWidget,
      );
      expect(find.text('128명 참여'), findsOneWidget);
      expect(find.byIcon(Icons.forum_outlined), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(SnackChatBackdrop.backgroundColor, const Color(0xFFFBFAF7));
      expect(
        SnackChatBackdrop.backgroundColor,
        isNot(const Color(0xFFF4F5F3)),
      );
    },
  );
}
