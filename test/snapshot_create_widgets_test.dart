import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/snapshot/snapshot_create_widgets.dart';
import 'package:wefilling/snapshot/snapshot_strings.dart';

Widget _host(
  Widget Function(SnapshotStrings strings) build, {
  Locale locale = const Locale('ko'),
  double scale = 1,
  double width = 375,
  double keyboard = 0,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: Size(width, 760),
          textScaler: TextScaler.linear(scale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: width,
              child: Builder(
                builder: (context) => build(SnapshotStrings.of(context)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('글자 크기 세 값: 가장 가까운 값으로 표시한다', () {
    expect(nearestSnapshotTextScale(.25), snapshotTextScaleSmall);
    expect(nearestSnapshotTextScale(.95), snapshotTextScaleMedium);
    expect(nearestSnapshotTextScale(1.2), snapshotTextScaleLarge);
    expect(nearestSnapshotTextScale(1.75), snapshotTextScaleLarge);
  });

  testWidgets('도구 줄: 자르기는 영상일 때만, 펼침 상태에 따라 밝기가 바뀐다',
      (tester) async {
    var toggles = 0;
    var nexts = 0;
    Widget row({required bool video, required bool open}) => _host(
          (s) => SnapshotEditorToolRow(
            strings: s,
            isVideo: video,
            trimOpen: open,
            onAddText: () {},
            onToggleTrim: () => toggles++,
            onNext: () => nexts++,
          ),
        );
    await tester.pumpWidget(row(video: false, open: false));
    expect(find.byKey(const ValueKey('snapshot_tool_trim')), findsNothing);
    expect(find.text('글자'), findsOneWidget);

    await tester.pumpWidget(row(video: true, open: false));
    expect(find.byKey(const ValueKey('snapshot_tool_trim')), findsOneWidget);
    Color trimColor() => tester.widget<Text>(find.text('자르기')).style!.color!;
    expect(trimColor().a, closeTo(.4, .01));
    await tester.tap(find.byKey(const ValueKey('snapshot_tool_trim')));
    expect(toggles, 1);

    await tester.pumpWidget(row(video: true, open: true));
    expect(trimColor().a, closeTo(1, .01));
    await tester.tap(find.byKey(const ValueKey('snapshot_editor_next')));
    expect(nexts, 1);
  });

  testWidgets('글자 패널: 밝게/어둡게·작게/보통/크게·앞으로·완료', (tester) async {
    bool? light;
    double? scale;
    var forward = 0;
    var done = 0;
    Widget panel({required bool many}) => _host(
          (s) => SnapshotTextEditPanel(
            strings: s,
            lightText: true,
            fontScale: 1.12,
            showBringForward: many,
            onLightChanged: (v) => light = v,
            onScaleChanged: (v) => scale = v,
            onBringForward: () => forward++,
            onDone: () => done++,
          ),
        );
    await tester.pumpWidget(panel(many: false));
    expect(find.byKey(const ValueKey('snapshot_text_forward')), findsNothing);
    // 1.12는 보통(1.0)에 가장 가깝다: 선택된 글자는 600 굵기.
    expect(
      tester.widget<Text>(find.text('보통')).style!.fontWeight,
      FontWeight.w600,
    );
    expect(
      tester.widget<Text>(find.text('크게')).style!.fontWeight,
      FontWeight.w500,
    );

    await tester.tap(find.text('어둡게'));
    expect(light, isFalse);
    await tester.tap(find.text('크게'));
    expect(scale, snapshotTextScaleLarge);
    await tester.tap(find.text('작게'));
    expect(scale, snapshotTextScaleSmall);
    await tester.tap(find.byKey(const ValueKey('snapshot_text_done')));
    expect(done, 1);

    await tester.pumpWidget(panel(many: true));
    await tester.tap(find.byKey(const ValueKey('snapshot_text_forward')));
    expect(forward, 1);
  });

  testWidgets('다음 알약: 선택이 없으면 비활성(35%)', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(
      (s) => SnapshotPillButton(label: s.next, onPressed: null),
    ));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, .35);
    await tester.tap(find.text('다음'));
    expect(taps, 0);

    await tester.pumpWidget(_host(
      (s) => SnapshotPillButton(label: s.next, onPressed: () => taps++),
    ));
    await tester.tap(find.text('다음'));
    expect(taps, 1);
  });

  testWidgets('UI 글자는 15를 넘지 않는다', (tester) async {
    await tester.pumpWidget(_host(
      (s) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SnapshotCreateTopBar(
            icon: Icons.chevron_left_rounded,
            label: s.repick,
            onBack: () {},
          ),
          SnapshotEditorToolRow(
            strings: s,
            isVideo: true,
            trimOpen: false,
            onAddText: () {},
            onToggleTrim: () {},
            onNext: () {},
          ),
          SnapshotTextEditPanel(
            strings: s,
            lightText: true,
            fontScale: 1,
            showBringForward: true,
            onLightChanged: (_) {},
            onScaleChanged: (_) {},
            onBringForward: () {},
            onDone: () {},
          ),
        ],
      ),
    ));
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.style?.fontSize ?? 14, lessThanOrEqualTo(15));
    }
  });

  for (final locale in const ['ko', 'en', 'zh']) {
    for (final width in const [320.0, 375.0, 430.0]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('오버플로우 없음 $locale ${width.toInt()} x$scale',
            (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 760));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(_host(
            (s) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SnapshotCreateTopBar(
                  icon: Icons.chevron_left_rounded,
                  label: s.repick,
                  onBack: () {},
                      ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 20, 20),
                  child: SnapshotEditorToolRow(
                    strings: s,
                    isVideo: true,
                    trimOpen: true,
                    onAddText: () {},
                    onToggleTrim: () {},
                    onNext: () {},
                  ),
                ),
                SnapshotTextEditPanel(
                  strings: s,
                  lightText: false,
                  fontScale: .8,
                  showBringForward: true,
                  onLightChanged: (_) {},
                  onScaleChanged: (_) {},
                  onBringForward: () {},
                  onDone: () {},
                ),
              ],
            ),
            locale: Locale(locale),
            scale: scale,
            width: width,
            keyboard: 280,
          ));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

