import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/translate_switch.dart';

void main() {
  late List<MethodCall> haptics;
  setUp(() {
    haptics = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
      return null;
    });
  });

  Future<List<bool>> pump(
    WidgetTester tester, {
    bool value = false,
    bool enabled = true,
    bool busy = false,
    bool failed = false,
    bool reduceMotion = false,
  }) async {
    final changes = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: Center(
            child: TranslateSwitch(
              key: const ValueKey('sw'),
              value: value,
              busy: busy,
              failed: failed,
              semanticLabel: '번역 보기',
              onChanged: enabled ? changes.add : null,
            ),
          ),
        ),
      ),
    ));
    return changes;
  }

  double knobLeft(WidgetTester tester) => tester
      .widget<AnimatedPositioned>(
          find.byKey(const ValueKey('translate_switch_knob')))
      .left!;
  Color iconColor(WidgetTester tester) => tester
      .widget<Icon>(find.byKey(const ValueKey('translate_switch_icon')))
      .color!;
  Color track(WidgetTester tester) => (tester
          .widget<AnimatedContainer>(
              find.byKey(const ValueKey('translate_switch_track')))
          .decoration! as BoxDecoration)
      .color!;

  testWidgets('꺼짐/켜짐 손잡이 위치와 아이콘 색, 누름 영역 56×44 이상', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();
    expect(knobLeft(tester), 2);
    expect(iconColor(tester), const Color(0xFF8A8A8A));
    final size = tester.getSize(find.byKey(const ValueKey('sw')));
    expect(size.width, greaterThanOrEqualTo(56));
    expect(size.height, greaterThanOrEqualTo(44));
    await pump(tester, value: true);
    await tester.pumpAndSettle();
    expect(knobLeft(tester), 24);
    expect(iconColor(tester), const Color(0xFF2C6BC0));
  });

  testWidgets('누르는 동안 손잡이가 30으로 늘어난다', (tester) async {
    await pump(tester);
    final gesture =
        await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('sw'))));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedPositioned>(
              find.byKey(const ValueKey('translate_switch_knob')))
          .width,
      30,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('비활성이면 탭을 무시하고 비활성 색', (tester) async {
    final changes = await pump(tester, enabled: false);
    await tester.tap(find.byKey(const ValueKey('sw')));
    expect(changes, isEmpty);
    await tester.pumpAndSettle();
    expect(track(tester), const Color(0xFFF0F0F0));
    expect(iconColor(tester), const Color(0xFFCFCFCF));
  });

  testWidgets('번역 중이면 아이콘이 돌고, 동작 줄이기면 돌지 않고 흐리다', (tester) async {
    await pump(tester, busy: true);
    double angle() => tester
        .widget<Transform>(find.ancestor(
          of: find.byKey(const ValueKey('translate_switch_icon')),
          matching: find.byType(Transform),
        ).first)
        .transform
        .getRotation()
        .entry(1, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(angle(), isNot(0));
    await pump(tester, busy: true, reduceMotion: true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(angle(), 0);
    expect(
      tester
          .widget<Opacity>(find.ancestor(
            of: find.byKey(const ValueKey('translate_switch_icon')),
            matching: find.byType(Opacity),
          ).first)
          .opacity,
      .5,
    );
  });

  testWidgets('실패 상태: 손잡이 꺼짐 위치, 탭하면 onChanged(true)', (tester) async {
    final changes = await pump(tester, value: true, failed: true);
    await tester.pumpAndSettle();
    expect(knobLeft(tester), 2);
    expect(track(tester), const Color(0xFFF2D4D4));
    await tester.tap(find.byKey(const ValueKey('sw')));
    expect(changes, [true]);
  });

  testWidgets('의미 라벨에 toggled 값, 글자 위젯 없음', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, value: true);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('sw'))),
      matchesSemantics(
        label: '번역 보기',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sw')),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    handle.dispose();
  });

  testWidgets('켤 때만 햅틱', (tester) async {
    await pump(tester, value: true);
    await tester.tap(find.byKey(const ValueKey('sw')));
    expect(haptics, isEmpty);
    await pump(tester, value: false);
    await tester.tap(find.byKey(const ValueKey('sw')));
    expect(haptics, hasLength(1));
  });

  testWidgets('언어 버튼: 빈 라벨이면 언어, 긴 이름은 말줄임', (tester) async {
    Future<void> lang(String label) => tester.pumpWidget(MaterialApp(
          locale: const Locale('ko'),
          supportedLocales: const [Locale('ko')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: Center(
              child: TranslateLanguageButton(
                languageLabel: label,
                semanticLabel: '번역 언어 설정',
                onPressed: () {},
              ),
            ),
          ),
        ));
    await lang('');
    expect(find.text('언어'), findsOneWidget);
    await lang('Bahasa Indonesia Panjang Sekali');
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(TranslateLanguageButton)).width,
      lessThanOrEqualTo(96),
    );
  });
}
