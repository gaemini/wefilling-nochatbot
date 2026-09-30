import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/comment.dart';
import 'package:wefilling/utils/comment_gif_input.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gif = Uint8List.fromList(<int>[
    ...'GIF89a'.codeUnits,
    1,
    0,
    1,
    0,
    0,
    0,
    0,
  ]);

  test('키보드 GIF bytes를 보존하고 다른 MIME 또는 비어 있는 입력은 거부', () {
    expect(
        validatedKeyboardGif(KeyboardInsertedContent(
          mimeType: 'image/gif',
          uri: 'content://keyboard/gif',
          data: gif,
        )),
        same(gif));
    expect(
        validatedKeyboardGif(KeyboardInsertedContent(
          mimeType: 'image/png',
          uri: 'content://keyboard/png',
          data: gif,
        )),
        isNull);
    expect(
        validatedKeyboardGif(const KeyboardInsertedContent(
          mimeType: 'image/gif',
          uri: 'content://keyboard/missing',
        )),
        isNull);
  });

  test('키보드가 URI만 보낼 때 네이티브에서 GIF bytes를 읽는다', () async {
    const channel = MethodChannel('com.wefilling.app/keyboard_gif');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readGif');
      expect((call.arguments as Map)['uri'], 'content://keyboard/gif');
      return gif;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final result = await readKeyboardGif(const KeyboardInsertedContent(
      mimeType: 'image/gif',
      uri: 'content://keyboard/gif',
    ));
    expect(result, orderedEquals(gif));
  });

  test('iOS 붙여넣기의 GIF 데이터도 같은 검증을 통과한다', () async {
    const channel = MethodChannel('com.wefilling.app/keyboard_gif');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readPasteboardGif');
      return gif;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    expect(await readPastedGif(), orderedEquals(gif));
  });

  test('포스트 GIF 댓글은 캐시에 유지되고 구버전 텍스트 댓글은 그대로 읽힘', () {
    final raw = <String, dynamic>{
      'postId': 'post',
      'userId': 'user',
      'authorNickname': 'name',
      'authorPhotoUrl': '',
      'content': '',
      'createdAt': 1000,
      'gifStoragePath': 'post_comment_gifs/post/comment.gif',
    };
    final comment = Comment.fromMap(raw, 'comment');
    expect(comment.gifStoragePath, raw['gifStoragePath']);
    expect(Comment.fromMap(comment.toMap(), 'comment').gifStoragePath,
        comment.gifStoragePath);
    raw.remove('gifStoragePath');
    raw['content'] = '기존 댓글';
    expect(Comment.fromMap(raw, 'old').gifStoragePath, isEmpty);
    expect(Comment.fromMap(raw, 'old').content, '기존 댓글');
  });
}
