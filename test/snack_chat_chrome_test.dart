import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/snack_chat_chrome.dart';

void main() {
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
                  contextLabel: '스낵챗',
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
        find.byKey(const ValueKey('snack_chat_context_label')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(SnackChatBackdrop.backgroundColor, const Color(0xFFFBFAF7));
      expect(
        SnackChatBackdrop.backgroundColor,
        isNot(const Color(0xFFF4F5F3)),
      );
    },
  );
}
