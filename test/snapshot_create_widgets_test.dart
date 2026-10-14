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

  testWidgets('아래 줄: 공개 범위 요약과 다음, 도구 원 켜짐 표시', (tester) async {
    var audience = 0;
    var next = 0;
    await tester.pumpWidget(_host(
      (s) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SnapshotEditorBottomBar(
            audienceLabel: s.editorAudienceSummary(
              s.shareChoicePublic,
              repliesOn: true,
            ),
            nextLabel: s.next,
            onAudience: () => audience++,
            onNext: () => next++,
          ),
          SnapshotToolCircle(
            key: const ValueKey('trim'),
            semanticLabel: s.trimTool,
            selected: true,
            onTap: () {},
            child: const Icon(Icons.crop_rounded),
          ),
        ],
      ),
    ));
    expect(find.text('전체 공개 · 답장까지'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('snapshot_editor_audience')));
    await tester.tap(find.byKey(const ValueKey('snapshot_editor_next')));
    expect(audience, 1);
    expect(next, 1);
    final circle = tester.widget<Container>(find.descendant(
      of: find.byKey(const ValueKey('trim')),
      matching: find.byType(Container),
    ));
    expect((circle.decoration as BoxDecoration).color, Colors.white);
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

  testWidgets('UI 글자는 15를 넘지 않는다', (tester) async {
    await tester.pumpWidget(_host(
      (s) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SnapshotLifetimeChip(label: s.lifetime24h),
          SnapshotEditorBottomBar(
            audienceLabel: s.editorAudienceSummary(
              s.shareChoicePublic,
              repliesOn: true,
            ),
            nextLabel: s.next,
            onAudience: () {},
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
                SnapshotLifetimeChip(label: s.lifetime24h),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: SnapshotEditorBottomBar(
                    audienceLabel: s.editorAudienceSummary(
                      s.shareChoiceGroups,
                      repliesOn: false,
                    ),
                    nextLabel: s.next,
                    onAudience: () {},
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

