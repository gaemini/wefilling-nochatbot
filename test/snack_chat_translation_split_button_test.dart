import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
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

  Color track(WidgetTester tester) => (tester
          .widget<AnimatedContainer>(
              find.byKey(const ValueKey('translate_switch_track')))
          .decoration! as BoxDecoration)
      .color!;
  double knobLeft(WidgetTester tester) => tester
      .widget<AnimatedPositioned>(
          find.byKey(const ValueKey('translate_switch_knob')))
      .left!;

  testWidgets('켜짐: 파란 홈 + 손잡이 오른쪽, 두 key와 언어 라벨', (tester) async {
    final result = await pump(tester, on: true);
    expect(find.byKey(const ValueKey('snack_translation_toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('snack_translation_language_settings')),
        findsOneWidget);
    expect(find.text('한국어'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(track(tester), const Color(0xFF2C6BC0));
    expect(knobLeft(tester), 24);

    await tester.tap(find.byKey(const ValueKey('snack_translation_toggle')));
    await tester.tap(
        find.byKey(const ValueKey('snack_translation_language_settings')));
    expect(result.taps, ['toggle', 'language']);
  });

  testWidgets('꺼짐: 회색 홈 + 손잡이 왼쪽, 글자 없는 스위치', (tester) async {
    await pump(tester, on: false);
    await tester.pumpAndSettle();
    expect(track(tester), const Color(0xFFE4E4E4));
    expect(knobLeft(tester), 2);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('snack_translation_toggle')),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
  });

  testWidgets('비활성이면 스위치가 반응하지 않고 비활성 색이다', (tester) async {
    final result = await pump(tester, on: false, enabled: false);
    await tester.tap(find.byKey(const ValueKey('snack_translation_toggle')));
    expect(result.taps, isEmpty);
    await tester.pumpAndSettle();
    expect(track(tester), const Color(0xFFF0F0F0));
  });

  testWidgets('언어 라벨이 비면 언어', (tester) async {
    await pump(tester, on: false, language: '');
    expect(find.text('Language'), findsOneWidget);
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

  // 스낵챗 상단 기준: 뒤로 44 · 제목(남는 폭, 말줄임) · 스위치 56 · 언어 · ⋮ 40.
  for (final locale in const [Locale('ko'), Locale('en'), Locale('zh')]) {
    for (final width in const [320.0, 375.0, 430.0]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('상단 바 ${locale.languageCode} $width/$scale', (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 200));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(MaterialApp(
            locale: locale,
            supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 200),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                appBar: AppBar(
                  leading: const SizedBox(width: 44),
                  titleSpacing: 0,
                  title: const Text(
                    '한양대 교환학생 모임 국제 언어교환 스터디 단톡방',
                    key: ValueKey('title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  actions: [
                    SnackChatTranslationSplitButton(
                      translationOn: true,
                      enabled: true,
                      languageLabel: 'Bahasa Indonesia',
                      toggleSemanticLabel: '원문 보기',
                      languageSemanticLabel: '번역 언어 설정',
                      onToggle: () {},
                      onOpenLanguage: () {},
                    ),
                    const SizedBox(width: 40, child: Icon(Icons.more_vert)),
                  ],
                ),
              ),
            ),
          ));
          expect(tester.takeException(), isNull);
          final title = tester.getRect(find.byKey(const ValueKey('title')));
          final toggle = tester.getRect(
              find.byKey(const ValueKey('snack_translation_toggle')));
          expect(title.width, greaterThan(0));
          expect(title.right, lessThanOrEqualTo(toggle.left + 0.5));
        });
      }
    }
  }
}
