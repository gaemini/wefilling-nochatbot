import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/motion/optimistic_toggle.dart';
import 'package:wefilling/ui/widgets/icon_motion.dart';

void main() {
  group('저장 먼저 반응', () {
    test('성공하면 기대값 유지, 되돌림 없음', () async {
      final shown = <bool>[];
      var mismatches = 0;
      final result = await runOptimisticToggle(
        current: false,
        apply: shown.add,
        commit: () async => true,
        onMismatch: () => mismatches++,
      );
      expect(result, isTrue);
      expect(shown.first, isTrue, reason: '서버 응답 전에 먼저 바뀐다');
      expect(mismatches, 0);
    });

    test('실패(예외·다른 결과)면 원래대로 되돌리고 알린다', () async {
      final shown = <bool>[];
      var mismatches = 0;
      final thrown = await runOptimisticToggle(
        current: false,
        apply: shown.add,
        commit: () async => throw Exception('offline'),
        onMismatch: () => mismatches++,
      );
      expect(thrown, isFalse);
      expect(shown, <bool>[true, false]);
      final denied = await runOptimisticToggle(
        current: false,
        apply: shown.add,
        commit: () async => false,
        onMismatch: () => mismatches++,
      );
      expect(denied, isFalse);
      expect(mismatches, 2);
    });
  });

  testWidgets('알림 종: 켤 때만 흔들리고 끌 때는 그대로', (tester) async {
    Widget bell(bool on) => MaterialApp(
          home: Center(
            child: BellShake(
              ringing: on,
              child: const Icon(Icons.notifications_active_outlined),
            ),
          ),
        );
    double angle() => tester
        .widget<Transform>(find.byKey(const ValueKey('bell_shake')))
        .transform
        .getRotation()
        .entry(1, 0);
    await tester.pumpWidget(bell(false));
    await tester.pumpWidget(bell(true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(angle(), isNot(0));
    await tester.pumpAndSettle();
    expect(angle(), 0);
    await tester.pumpWidget(bell(false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(angle(), 0);
  });

  test('종 각도 순서 14° → -10° → 5° → 0°', () {
    double deg(double t) => BellShake.angleAtForTest(t) * 180 / 3.141592653589793;
    expect(deg(.2), closeTo(14, .01));
    expect(deg(.5), closeTo(-10, .01));
    expect(deg(.75), closeTo(5, .01));
    expect(deg(1), closeTo(0, .01));
  });

  testWidgets('보내기 버튼: 비어 있으면 회색 .9, 입력 있으면 포인트 1.0', (tester) async {
    Widget send(bool active) => MaterialApp(
          home: Scaffold(
            body: Center(
              child:
                  MotionSendButton(active: active, onTap: () {}, label: '전송'),
            ),
          ),
        );
    await tester.pumpWidget(send(false));
    await tester.pumpAndSettle();
    BoxDecoration fill() => tester
        .widget<AnimatedContainer>(find.byKey(const ValueKey('motion_send_fill')))
        .decoration! as BoxDecoration;
    expect(fill().color, kSendInactiveColor);
    expect(
      tester.widget<AnimatedScale>(find.byKey(const ValueKey('motion_send_scale'))).scale,
      .9,
    );
    await tester.pumpWidget(send(true));
    await tester.pumpAndSettle();
    expect(fill().color, kMotionPointColor);
    expect(
      tester.widget<AnimatedScale>(find.byKey(const ValueKey('motion_send_scale'))).scale,
      1,
    );
  });

  testWidgets('복사: ✓ 복사됨으로 바뀌고 1.5초 뒤 돌아온다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: CopyFeedback(
          builder: (context, copied, markCopied) => TextButton(
            onPressed: markCopied,
            child: CopyFeedbackLabel(
              copied: copied,
              label: '링크 복사',
              copiedLabel: '복사됨',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('링크 복사'));
    await tester.pumpAndSettle();
    expect(find.text('복사됨'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('링크 복사'), findsOneWidget);
    expect(find.text('복사됨'), findsNothing);
  });
}
