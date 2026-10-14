import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wefilling/services/feature_flag_service.dart';
import 'package:wefilling/ui/widgets/translate_hints.dart';

void main() {
  testWidgets('선택 항목 플래그는 기본 꺼짐', (tester) async {
    expect(TranslateHintFlags.singleMessageButton, isFalse);
    expect(TranslateHintFlags.firstHint, isFalse);
    expect(FeatureFlagService.FEATURE_TRANSLATE_SINGLE_MESSAGE_BUTTON,
        'translate_single_message_button');
    expect(FeatureFlagService.FEATURE_TRANSLATE_FIRST_HINT,
        'translate_first_hint');
  });

  testWidgets('메시지 번역 단추: 누름 영역 44, 탭 콜백, 번역 중이면 막힘', (tester) async {
    var taps = 0;
    Widget host(bool busy) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: TranslateSingleMessageButton(
                busy: busy,
                onPressed: () => taps++,
              ),
            ),
          ),
        );
    await tester.pumpWidget(host(false));
    final size = tester.getSize(
        find.byKey(const ValueKey('translate_single_message_button')));
    expect(size, const Size(44, 44));
    await tester.tap(
        find.byKey(const ValueKey('translate_single_message_button')));
    expect(taps, 1);
    await tester.pumpWidget(host(true));
    await tester.tap(
        find.byKey(const ValueKey('translate_single_message_button')));
    expect(taps, 1);
  });

  testWidgets('알림 줄: 번역해서 보기 · 닫기 콜백, 320 폭 오버플로우 없음', (tester) async {
    final calls = <String>[];
    await tester.binding.setSurfaceSize(const Size(320, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 300),
          textScaler: TextScaler.linear(2),
        ),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: TranslateFirstHintBar(
              languageLabel: 'Bahasa Indonesia',
              onTranslate: () => calls.add('translate'),
              onDismiss: () => calls.add('dismiss'),
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('translate_first_hint_action')));
    await tester.tap(find.byKey(const ValueKey('translate_first_hint_close')));
    expect(calls, ['translate', 'dismiss']);
  });

  test('알림 줄 닫음은 방별로 기억한다', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await TranslateHintStore.isDismissed('u1', 'room1'), isFalse);
    await TranslateHintStore.dismiss('u1', 'room1');
    expect(await TranslateHintStore.isDismissed('u1', 'room1'), isTrue);
    expect(await TranslateHintStore.isDismissed('u1', 'room2'), isFalse);
  });
}
