import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/services/clipboard_image_service.dart';

Uint8List _bytes(List<int> head) =>
    Uint8List.fromList(<int>[...head, ...List<int>.filled(32, 0)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('이미지 형식 판별', () {
    test('PNG·JPEG·GIF·WebP·HEIC 머리말', () {
      expect(ClipboardImageService.sniffImageMime(_bytes([0x89, 0x50, 0x4E, 0x47])),
          'image/png');
      expect(ClipboardImageService.sniffImageMime(_bytes([0xFF, 0xD8, 0xFF])),
          'image/jpeg');
      expect(ClipboardImageService.sniffImageMime(_bytes([0x47, 0x49, 0x46])),
          'image/gif');
      expect(
        ClipboardImageService.sniffImageMime(_bytes(
            [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])),
        'image/webp',
      );
      expect(
        ClipboardImageService.sniffImageMime(
            _bytes([0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70])),
        'image/heic',
      );
    });

    test('이미지가 아니거나 너무 작으면 거부', () {
      expect(ClipboardImageService.validated(_bytes([0x41, 0x42]), 'image/png'),
          isNull);
      expect(ClipboardImageService.validated(Uint8List(4), 'image/png'), isNull);
    });

    test('선언 형식이 비었으면 머리말 형식, jpg는 jpeg로', () {
      final png = ClipboardImageService.validated(
          _bytes([0x89, 0x50, 0x4E, 0x47]), 'image/*')!;
      expect(png.mimeType, 'image/png');
      expect(png.extension, 'png');
      final jpg = ClipboardImageService.validated(
          _bytes([0xFF, 0xD8, 0xFF]), 'image/jpg')!;
      expect(jpg.mimeType, 'image/jpeg');
      expect(jpg.extension, 'jpg');
    });
  });

  group('네이티브 채널', () {
    const channel = MethodChannel('com.wefilling.app/clipboard_image');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'readImage':
            return <String, Object>{
              'bytes': _bytes([0x89, 0x50, 0x4E, 0x47]),
              'mimeType': 'image/png',
            };
          case 'writeImage':
            return true;
          case 'hasImage':
            return true;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('붙여넣기: 클립보드 이미지를 읽는다', () async {
      final image = await ClipboardImageService.instance.readImage();
      expect(image, isNotNull);
      expect(image!.mimeType, 'image/png');
    });

    test('복사: 이미지가 아니면 채널을 부르지 않는다', () async {
      expect(
        await ClipboardImageService.instance.writeImage(_bytes([1, 2, 3])),
        isFalse,
      );
      expect(calls.where((c) => c.method == 'writeImage'), isEmpty);
      expect(
        await ClipboardImageService.instance
            .writeImage(_bytes([0xFF, 0xD8, 0xFF])),
        isTrue,
      );
      expect(calls.last.arguments['mimeType'], 'image/jpeg');
      expect(ClipboardImageService.instance.cachedHasImage, isTrue);
    });
  });
}
