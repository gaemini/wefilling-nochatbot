import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/screens/snapshot_detail_screen.dart';

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
}
