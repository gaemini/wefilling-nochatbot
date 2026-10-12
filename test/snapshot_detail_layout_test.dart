import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snapshot.dart';
import 'package:wefilling/screens/snapshot_detail_screen.dart';
import 'package:wefilling/snapshot/snapshot_storage_video.dart';

void main() {
  test('스낵 상세는 세로형 Android 화면에서도 합성 원본 전체를 보존한다', () {
    const composedImage = Size(1080, 1920);
    const androidViewport = Size(393, 852);

    final fitted = applyBoxFit(
      snapshotDetailImageFit,
      composedImage,
      androidViewport,
    );

    expect(fitted.source, composedImage);
    expect(fitted.destination.width, lessThanOrEqualTo(androidViewport.width));
    expect(
      fitted.destination.height,
      lessThanOrEqualTo(androidViewport.height),
    );
    expect(
      fitted.destination.aspectRatio,
      closeTo(composedImage.aspectRatio, 0.0001),
    );
  });

  test('가로·정사각형·세로 미디어의 원본 비율을 작은 화면에서도 유지한다', () {
    const viewport = Size(320, 520);
    for (final media in <Size>[
      const Size(1920, 1080),
      const Size(1080, 1080),
      const Size(1080, 1920),
    ]) {
      final fitted = applyBoxFit(snapshotDetailImageFit, media, viewport);
      expect(fitted.source, media);
      expect(fitted.destination.width, lessThanOrEqualTo(viewport.width));
      expect(fitted.destination.height, lessThanOrEqualTo(viewport.height));
      expect(fitted.destination.aspectRatio, closeTo(media.aspectRatio, .0001));
    }
  });

  testWidgets('영상 텍스트는 편집 화면과 같은 줄 높이·글자 확대 제한을 쓴다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('ko'),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Center(
              child: SizedBox(
                width: 320,
                height: 320,
                child: SnapshotOverlayLayer(
                  overlays: <SnapshotOverlay>[
                    SnapshotOverlay(
                      id: 'first',
                      text: '한글 English 简体 😀',
                      x: .5,
                      y: .5,
                      lightText: true,
                      fontScale: 1.5,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('한글 English 简体 😀'));
    expect(text.style?.height, 1.18);
    expect(text.style?.fontSize, closeTo(320 * .066 * 1.5, .001));
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('한글 English 简体 😀')))
          .scale(20),
      26,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('겹친 영상 텍스트는 기존 최대 5개 표시 범위를 유지한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 320,
            child: SnapshotOverlayLayer(
              overlays: List<SnapshotOverlay>.generate(
                6,
                (index) => SnapshotOverlay(
                  id: 'layer_$index',
                  text: 'layer_$index',
                  x: .5,
                  y: .5,
                  lightText: true,
                  order: index,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var index = 0; index < 5; index++) {
      expect(find.text('layer_$index'), findsOneWidget);
    }
    expect(find.text('layer_5'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
