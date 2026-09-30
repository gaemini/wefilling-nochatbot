import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snapshot.dart';

void main() {
  test('GIF 헤더와 과도한 캔버스 크기를 거부한다', () {
    expect(isValidSnapshotCommentGifHeader(
        <int>[71, 73, 70, 56, 57, 97, 64, 1, 64, 1]), isTrue);
    expect(isValidSnapshotCommentGifHeader(<int>[71, 73, 70, 56, 57, 97]),
        isFalse);
    expect(isValidSnapshotCommentGifHeader(
        <int>[71, 73, 70, 56, 57, 97, 0, 0, 64, 1]), isFalse);
  });

  test('GIF 댓글 경로가 실시간 문서와 작성자 보관본에 유지된다', () {
    final comment = SnapshotComment.fromMap('snack-id', 'comment-id', {
      'userId': 'author-id',
      'content': '',
      'gifStoragePath': 'snapshots/snack-id/comment_gifs/comment-id.gif',
      'createdAtMs': 1000,
    });

    expect(comment.content, isEmpty);
    expect(comment.gifStoragePath,
        'snapshots/snack-id/comment_gifs/comment-id.gif');
    final restored = SnapshotComment.fromMap(
      'snack-id',
      'comment-id',
      comment.toArchiveMap(),
    );
    expect(restored.gifStoragePath, comment.gifStoragePath);
  });

  test('기존 텍스트 댓글은 GIF 필드 없이 그대로 파싱된다', () {
    final comment = SnapshotComment.fromMap('snack-id', 'comment-id', {
      'userId': 'author-id',
      'content': '안녕하세요',
      'createdAtMs': 1000,
    });

    expect(comment.content, '안녕하세요');
    expect(comment.gifStoragePath, isEmpty);
  });
}
