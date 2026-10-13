import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/snapshot/snapshot_dm_reply_panel.dart';

Future<void> _pump(
  WidgetTester tester, {
  Future<bool> Function(String)? onSend,
  ValueChanged<String>? onClose,
  String initialText = '',
  double width = 375,
  double scale = 1,
  double keyboard = 0,
  String name = 'm1nz1',
  Locale locale = const Locale('ko'),
}) async {
  await tester.binding.setSurfaceSize(Size(width, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 700),
        textScaler: TextScaler.linear(scale),
        viewInsets: EdgeInsets.only(bottom: keyboard),
        padding: const EdgeInsets.only(bottom: 34),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: keyboard,
              child: SnapshotDmReplyPanel(
                authorName: name,
                thumbnail: null,
                initialText: initialText,
                onClose: onClose ?? (_) {},
                onSend: onSend ?? (_) async => true,
              ),
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  const input = ValueKey('dm_reply_input');
  const send = ValueKey('dm_reply_send');

  testWidgets('문맥 줄과 placeholder, 글이 없으면 보내기 버튼이 없다(크기 0)',
      (tester) async {
    await _pump(tester, onSend: (_) async => true);
    expect(find.text('m1nz1의 스낵에 답장'), findsOneWidget);
    expect(find.text('DM으로 보내져요'), findsOneWidget);
    expect(find.text('메시지 보내기…'), findsOneWidget);
    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 0);
  });

  testWidgets('글을 쓰면 보내기 버튼이 나타나고 전송 콜백이 불린다', (tester) async {
    final sent = <String>[];
    await _pump(tester, onSend: (text) async {
      sent.add(text);
      return true;
    });
    await tester.enterText(find.byKey(input), '안녕하세요');
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await tester.tap(find.byKey(send));
    await tester.pump();
    expect(sent, ['안녕하세요']);
  });

  testWidgets('실패하면 글이 보존되고 다시 보낼 수 있다', (tester) async {
    var calls = 0;
    await _pump(tester, onSend: (text) async {
      calls++;
      return calls > 1;
    });
    await tester.enterText(find.byKey(input), '재시도');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(send));
    await tester.pump();
    await tester.pump();
    expect(find.text('재시도'), findsOneWidget);
    await tester.tap(find.byKey(send));
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('닫기는 입력 중인 글을 넘기고, 초기 글은 복원된다', (tester) async {
    String? draft;
    await _pump(tester, initialText: '임시 글', onClose: (d) => draft = d);
    expect(find.text('임시 글'), findsOneWidget);
    await tester.enterText(find.byKey(input), '임시 글 수정');
    await tester.tap(find.byKey(const ValueKey('dm_reply_close')));
    expect(draft, '임시 글 수정');
  });

  testWidgets('보내는 동안 입력이 잠긴다', (tester) async {
    final completer = Completer<bool>();
    await _pump(tester, onSend: (_) => completer.future);
    await tester.enterText(find.byKey(input), '보내는 중');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(send));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(input)).enabled, isFalse);
    completer.complete(true);
    await tester.pump();
  });

  testWidgets('글자 크기는 15를 넘지 않는다', (tester) async {
    await _pump(tester, onSend: (_) async => true);
    await tester.enterText(find.byKey(input), '글자');
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.style?.fontSize ?? 14, lessThanOrEqualTo(15));
    }
    expect(tester.widget<TextField>(find.byKey(input)).style!.fontSize, 15);
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      for (final keyboard in const [0.0, 300.0]) {
        testWidgets('오버플로우 없음 $width/$scale/키보드 $keyboard', (tester) async {
          for (final locale in const [Locale('ko'), Locale('en'), Locale('zh')]) {
            await _pump(
              tester,
              onSend: (_) async => true,
              width: width,
              scale: scale,
              keyboard: keyboard,
              name: 'seoyeon_international_student_club_long_name',
              locale: locale,
              initialText: '아주 긴 글 ' * 30,
            );
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  }
}
