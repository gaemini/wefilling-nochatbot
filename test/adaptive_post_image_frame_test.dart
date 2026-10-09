// 영상+사진 캐러셀은 영상 비율을 knownAspectRatio로 넘긴다. 이미지를 읽지 않고
// 그 비율(4:5~1.91:1, 최대 높이)로 프레임 크기를 정하는지 확인한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/adaptive_post_image_frame.dart';

Future<Size> _frameSize(WidgetTester tester, double? ratio) async {
  const key = Key('frame-child');
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(400, 2000)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            child: AdaptivePostImageFrame(
              imageUrl: '',
              knownAspectRatio: ratio,
              child: const SizedBox.expand(key: key),
            ),
          ),
        ),
      ),
    ),
  );
  return tester.getSize(find.byKey(key));
}

void main() {
  testWidgets('landscape video ratio sets the frame height', (tester) async {
    final size = await _frameSize(tester, 16 / 9);
    expect(size.width, 400);
    expect(size.height, closeTo(225, 0.01));
  });

  testWidgets('portrait ratio is clamped to 4:5 and the max height', (tester) async {
    final size = await _frameSize(tester, 9 / 16);
    // 4:5 → 500px, 최대 높이 480px로 제한.
    expect(size.height, 480);
  });

  testWidgets('without a known ratio the 4:3 fallback is unchanged', (tester) async {
    final size = await _frameSize(tester, null);
    expect(size.height, closeTo(300, 0.01));
  });
}
