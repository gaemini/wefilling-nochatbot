import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/snack_chat_chrome.dart';
import 'package:wefilling/ui/widgets/snack_chat_translation_split_button.dart';

void main() {
  Future<({List<String> taps})> pump(
    WidgetTester tester, {
    required bool on,
    bool enabled = true,
    String language = '한국어',
    double width = 375,
    double scale = 1,
  }) async {
    final taps = <String>[];
    await tester.binding.setSurfaceSize(Size(width, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 200),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            appBar: AppBar(
              actions: [
                SnackChatTranslationSplitButton(
                  translationOn: on,
                  enabled: enabled,
                  languageLabel: language,
                  toggleSemanticLabel: on ? '원문 보기' : '번역 보기',
                  languageSemanticLabel: '번역 언어 설정',
                  onToggle: () => taps.add('toggle'),
                  onOpenLanguage: () => taps.add('language'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return (taps: taps);
  }

  Color fill(WidgetTester tester) => (tester
          .widget<AnimatedContainer>(
              find.byKey(const ValueKey('snack_translation_toggle_fill')))
          .decoration! as BoxDecoration)
      .color!;
  Color iconColor(WidgetTester tester) => tester
      .widget<Icon>(find.byKey(const ValueKey('snack_translation_toggle_icon')))
      .color!;

  testWidgets('켜짐: #2C6BC0 채움 + 흰 아이콘, 두 key와 언어 라벨', (tester) async {
    final result = await pump(tester, on: true);
    expect(find.byKey(const ValueKey('snack_translation_toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('snack_translation_language_settings')),
        findsOneWidget);
    expect(find.text('한국어'), findsOneWidget);
    expect(fill(tester), SnackChatPalette.pointStrong);
    expect(iconColor(tester), Colors.white);

    await tester.tap(find.byKey(const ValueKey('snack_translation_toggle')));
    await tester.tap(
        find.byKey(const ValueKey('snack_translation_language_settings')));
    expect(result.taps, ['toggle', 'language']);
  });

  testWidgets('꺼짐: 투명 + 검정 아이콘', (tester) async {
    await pump(tester, on: false);
    expect(fill(tester), Colors.transparent);
    expect(iconColor(tester), SnackChatPalette.ink);
  });

  testWidgets('비활성이면 토글이 반응하지 않고 반투명이다', (tester) async {
    final result = await pump(tester, on: false, enabled: false);
    await tester.tap(find.byKey(const ValueKey('snack_translation_toggle')));
    expect(result.taps, isEmpty);
    final opacity = tester.widget<AnimatedOpacity>(find.ancestor(
      of: find.byKey(const ValueKey('snack_translation_toggle_fill')),
      matching: find.byType(AnimatedOpacity),
    ));
    expect(opacity.opacity, lessThan(1));
  });

  testWidgets('터치 영역은 44 이상이다', (tester) async {
    await pump(tester, on: true);
    for (final key in ['snack_translation_toggle', 'snack_translation_language_settings']) {
      final size = tester.getSize(find.byKey(ValueKey(key)));
      expect(size.height, greaterThanOrEqualTo(44), reason: key);
      expect(size.width, greaterThanOrEqualTo(44), reason: key);
    }
  });

  testWidgets('접근성: 토글 상태와 라벨', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, on: true);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('snack_translation_toggle'))),
      matchesSemantics(
        label: '원문 보기',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      for (final language in const ['한국어', 'English', '日本語', 'Tiếng Việt', 'Bahasa Indonesia']) {
        testWidgets('오버플로우 없음 $width/$scale/$language', (tester) async {
          await pump(tester, on: true, width: width, scale: scale, language: language);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
