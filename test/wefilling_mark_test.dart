import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/wefilling_mark.dart';

const int _box = 120;

/// 흰 바탕 위 RGB(0..1)로 평탄화한 픽셀.
Future<Float64List> _rgbOnWhite(ui.Image image) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final out = Float64List(_box * _box * 3);
  for (var i = 0; i < _box * _box; i++) {
    final a = data.getUint8(i * 4 + 3) / 255;
    for (var c = 0; c < 3; c++) {
      // rawRgba는 premultiplied가 아니다.
      final v = data.getUint8(i * 4 + c) / 255;
      out[i * 3 + c] = v * a + (1 - a);
    }
  }
  return out;
}

Future<ui.Image> _renderMark() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  WefillingMarkPainter().paint(canvas, const Size(120, 120));
  return recorder.endRecording().toImage(_box, _box);
}

WefillingMarkPose _pose(WidgetTester tester) => (tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(WefillingMark), matching: find.byType(CustomPaint)))
        .painter! as WefillingMarkPainter)
    .currentPose;

Future<void> _advance(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Widget _host(WefillingMarkMode mode, {Object? nod, bool reduce = false}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Center(child: WefillingMark(mode: mode, nodSignal: nod)),
    );

void main() {
  setUp(() => WefillingAmbientMotion.enabled = true);

  test('정지 상태가 원본 PNG와 사실상 같다', () async {
    final bytes =
        File('assets/images/wefilling_boot_logo.png').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: _box, targetHeight: _box);
    final original = (await codec.getNextFrame()).image;
    final a = await _rgbOnWhite(original);
    final b = await _rgbOnWhite(await _renderMark());
    var sum = 0.0;
    var worst = 0;
    for (var i = 0; i < a.length; i++) {
      final d = (a[i] - b[i]).abs();
      sum += d;
      if (d > .25) worst++;
    }
    final mean = sum / a.length;
    // ignore: avoid_print
    print('wefilling mark vs PNG: mean |ΔRGB| = ${mean.toStringAsFixed(4)}, '
        'pixels(Δ>.25) = $worst / ${_box * _box * 3}');
    expect(mean, lessThan(.015));
    expect(worst / a.length, lessThan(.01));
  });

  testWidgets('entrance: 바깥 44에서 0으로, 캡슐마다 70ms 늦게', (tester) async {
    await tester.pumpWidget(_host(WefillingMarkMode.entrance));
    var pose = _pose(tester);
    expect(pose.offsets.first, closeTo(44, .01));
    expect(pose.opacities.first, 0);
    await _advance(tester, 352);
    pose = _pose(tester);
    expect(pose.offsets[0], lessThan(pose.offsets[4]));
    await _advance(tester, 700);
    pose = _pose(tester);
    for (final o in pose.offsets) {
      expect(o.abs(), lessThan(.5));
    }
    expect(pose.opacities, everyElement(1.0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('idle: 0 ↔ 바깥 3 숨쉬기(1000 + i×200 뒤 시작)', (tester) async {
    await tester.pumpWidget(_host(WefillingMarkMode.idle));
    await _advance(tester, 900);
    expect(_pose(tester).offsets, everyElement(0.0));
    await _advance(tester, 100 + 1800);
    final pose = _pose(tester);
    expect(pose.offsets[0], closeTo(3, .2));
    for (final o in pose.offsets) {
      expect(o, inInclusiveRange(0, 3.01));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('loading: 안쪽 6 + 회전, success: 안쪽 14·캡슐 .85·전체 1.25·물결',
      (tester) async {
    await tester.pumpWidget(_host(WefillingMarkMode.loading));
    await _advance(tester, 400);
    var pose = _pose(tester);
    expect(pose.offsets, everyElement(closeTo(-6, .01)));
    expect(pose.rotation, isNot(0));

    await tester.pumpWidget(_host(WefillingMarkMode.success));
    await _advance(tester, 560);
    pose = _pose(tester);
    expect(pose.offsets, everyElement(closeTo(-14, .01)));
    expect(pose.capsuleScale, closeTo(.85, .001));
    expect(pose.scale, closeTo(1.25, .001));
    expect(pose.rotation % (2 * 3.141592653589793), closeTo(0, .001));
    expect(pose.ripple, isNotNull);
    await _advance(tester, 1000);
    expect(_pose(tester).ripple, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('언어 바꿈: 0° → 16° → 0° 끄덕임(500ms)', (tester) async {
    WefillingAmbientMotion.enabled = false;
    await tester.pumpWidget(_host(WefillingMarkMode.still, nod: 'ko'));
    await tester.pumpWidget(_host(WefillingMarkMode.still, nod: 'en'));
    await _advance(tester, 160);
    final mid = _pose(tester).rotation;
    expect(mid * 180 / 3.141592653589793, greaterThan(12));
    await _advance(tester, 400);
    expect(_pose(tester).rotation, closeTo(0, .001));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('동작 줄이기: 항상 정지', (tester) async {
    await tester.pumpWidget(_host(WefillingMarkMode.loading, reduce: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_pose(tester).offsets, everyElement(0.0));
    expect(_pose(tester).rotation, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
