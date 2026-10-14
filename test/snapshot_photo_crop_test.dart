import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/snapshot/snapshot_photo_crop_screen.dart';

const _image = Size(1000, 2000);

void main() {
  test('비율 틀은 사진 안 가장 큰 가운데 영역', () {
    expect(snapshotCenteredCropRect(_image, null), Offset.zero & _image);
    expect(
      snapshotCenteredCropRect(_image, 1),
      const Rect.fromLTWH(0, 500, 1000, 1000),
    );
  });

  test('자유 비율: 모서리를 끌면 그 방향으로만 줄어든다', () {
    final rect = snapshotDragCropRect(
      rect: Offset.zero & _image,
      handle: SnapshotCropHandle.topLeft,
      delta: const Offset(100, 300),
      image: _image,
      ratio: null,
      minSide: 50,
    );
    expect(rect, const Rect.fromLTRB(100, 300, 1000, 2000));
  });

  test('옮기기는 사진 밖으로 나가지 않는다', () {
    final rect = snapshotDragCropRect(
      rect: const Rect.fromLTWH(100, 100, 400, 400),
      handle: SnapshotCropHandle.move,
      delta: const Offset(-500, 5000),
      image: _image,
      ratio: null,
      minSide: 50,
    );
    expect(rect, const Rect.fromLTWH(0, 1600, 400, 400));
  });

  test('최소 크기보다 작아지지 않는다', () {
    final rect = snapshotDragCropRect(
      rect: const Rect.fromLTWH(0, 0, 400, 400),
      handle: SnapshotCropHandle.right,
      delta: const Offset(-1000, 0),
      image: _image,
      ratio: null,
      minSide: 80,
    );
    expect(rect.width, 80);
  });

  test('1:1 비율은 끌어도 정사각형을 유지하고 사진 안에 있다', () {
    final rect = snapshotDragCropRect(
      rect: const Rect.fromLTWH(0, 500, 1000, 1000),
      handle: SnapshotCropHandle.bottomRight,
      delta: const Offset(-300, -100),
      image: _image,
      ratio: 1,
      minSide: 50,
    );
    expect(rect.width, closeTo(rect.height, .001));
    expect((Offset.zero & _image).contains(rect.topLeft), isTrue);
    expect(rect.right, lessThanOrEqualTo(1000));
  });
}
