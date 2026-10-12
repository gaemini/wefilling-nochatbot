import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/services/comment_image_upload.dart';

void main() {
  test('사진 경로는 규칙과 같은 고정 형식이다', () {
    expect(commentImagePath('p1', 'c1', 2), 'post_comment_images/p1/c1/2.jpg');
  });

  test('모두 성공하면 순서대로 경로를 돌려준다', () async {
    final deleted = <String>[];
    final paths = await uploadCommentImagesAllOrNothing(
      count: 3,
      upload: (i) async => commentImagePath('p', 'c', i),
      delete: (path) async => deleted.add(path),
    );
    expect(paths, [
      'post_comment_images/p/c/0.jpg',
      'post_comment_images/p/c/1.jpg',
      'post_comment_images/p/c/2.jpg',
    ]);
    expect(deleted, isEmpty);
  });

  test('중간 실패 시 올라간 사진을 모두 지우고 null을 돌려준다', () async {
    final deleted = <String>[];
    var attempts = 0;
    final paths = await uploadCommentImagesAllOrNothing(
      count: 4,
      upload: (i) async {
        attempts++;
        if (i == 2) throw StateError('upload-failed');
        return commentImagePath('p', 'c', i);
      },
      delete: (path) async {
        deleted.add(path);
        if (path.endsWith('0.jpg')) throw StateError('delete-failed');
      },
    );
    expect(paths, isNull);
    expect(attempts, 3, reason: '실패 뒤에는 더 올리지 않는다');
    expect(deleted, [
      'post_comment_images/p/c/0.jpg',
      'post_comment_images/p/c/1.jpg',
    ]);
  });

  test('0장이나 5장 이상은 올리지 않는다', () async {
    var calls = 0;
    Future<String> upload(int i) async {
      calls++;
      return 'x';
    }

    Future<void> delete(String _) async {}
    expect(
      await uploadCommentImagesAllOrNothing(
          count: 0, upload: upload, delete: delete),
      isNull,
    );
    expect(
      await uploadCommentImagesAllOrNothing(
          count: maxCommentImages + 1, upload: upload, delete: delete),
      isNull,
    );
    expect(calls, 0);
  });
}
