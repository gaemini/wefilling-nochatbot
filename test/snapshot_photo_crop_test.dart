import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/snapshot/snapshot_photo_crop_screen.dart';

void main() {
  test('확대·이동 없으면 틀 크기만큼 왼쪽 위부터', () {
    // 1000×2000 사진, 300×300 틀: cover 배율 0.3 → 원본 1000×1000 영역.
    final rect = snapshotCropSourceRect(
      imageSize: const Size(1000, 2000),
      frameSize: const Size(300, 300),
      baseScale: .3,
      translation: Offset.zero,
      zoom: 1,
    );
    expect(rect, const Rect.fromLTWH(0, 0, 1000, 1000));
  });

  test('2배 확대 후 이동하면 그만큼 좁고 아래쪽 영역', () {
    final rect = snapshotCropSourceRect(
      imageSize: const Size(1000, 2000),
      frameSize: const Size(300, 300),
      baseScale: .3,
      translation: const Offset(-60, -300),
      zoom: 2,
    );
    expect(rect.left, closeTo(100, .001));
    expect(rect.top, closeTo(500, .001));
    expect(rect.width, closeTo(500, .001));
    expect(rect.height, closeTo(500, .001));
  });
}
