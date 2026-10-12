import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snapshot.dart';
import 'package:wefilling/screens/snapshot_comments_sheet.dart';

SnapshotComment _comment({
  String id = 'c1',
  String userId = 'other',
  String content = 'Nice photo!',
  bool isDeleted = false,
}) =>
    SnapshotComment(
      id: id,
      snapshotId: 'snack-1',
      userId: userId,
      authorNickname: 'n',
      authorPhotoUrl: '',
      content: content,
      createdAt: DateTime(2026, 10, 10),
      isDeleted: isDeleted,
    );

void main() {
  test('다른 사람이 쓴 텍스트 댓글만 번역한다', () {
    expect(isSnapshotCommentTranslationCandidate(_comment(), 'me'), isTrue);
    expect(
      isSnapshotCommentTranslationCandidate(_comment(userId: 'me'), 'me'),
      isFalse,
    );
    expect(
      isSnapshotCommentTranslationCandidate(_comment(isDeleted: true), 'me'),
      isFalse,
    );
    expect(
      isSnapshotCommentTranslationCandidate(_comment(content: '  '), 'me'),
      isFalse,
    );
  });

  test('서버 번역 요청은 snapshot_comment 타입과 부모 스낵 id를 쓴다', () {
    final request = snapshotCommentTranslationRequest(_comment(id: 'c9'));
    expect(request.contentType, 'snapshot_comment');
    expect(request.contentId, 'c9');
    expect(request.parentId, 'snack-1');
    expect(request.sourceFields, {'content': 'Nice photo!'});
    expect(request.serverId, 'snapshot_comment:snack-1:c9');
  });

  test('스낵 댓글 번역 범위는 스낵마다 하나다', () {
    expect(snapshotCommentTranslationScope('snack-1'),
        'snapshot-comments:snack-1');
  });
}
