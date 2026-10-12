import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/comment.dart';
import 'package:wefilling/services/comment_service.dart';

void main() {
  Comment comment(
    String id, {
    String? parentCommentId,
    bool isDeleted = false,
  }) {
    return Comment(
      id: id,
      postId: 'post-1',
      userId: 'user-$id',
      authorNickname: 'User $id',
      authorPhotoUrl: '',
      content: isDeleted ? '' : 'comment $id',
      createdAt: DateTime(2026, 8, 11),
      isDeleted: isDeleted,
      parentCommentId: parentCommentId,
      depth: parentCommentId == null ? 0 : 1,
    );
  }

  group('CommentService active thread count', () {
    test('does not count soft-deleted comments', () {
      final comments = [
        comment('parent'),
        comment('reply', parentCommentId: 'parent'),
        comment('deleted-reply', parentCommentId: 'parent', isDeleted: true),
      ];

      expect(CommentService.countActiveThreadComments(comments), 2);
    });

    test('does not count replies whose parent document is missing', () {
      final comments = [
        comment('parent'),
        comment('orphan-reply', parentCommentId: 'missing-parent'),
      ];

      expect(CommentService.countActiveThreadComments(comments), 1);
      expect(
        CommentService.retainValidThreadComments(comments)
            .map((item) => item.id),
        ['parent'],
      );
    });

    test('keeps active replies under a deleted parent placeholder', () {
      final comments = [
        comment('deleted-parent', isDeleted: true),
        comment('active-reply', parentCommentId: 'deleted-parent'),
      ];

      expect(CommentService.countActiveThreadComments(comments), 1);
      expect(
        CommentService.retainValidThreadComments(comments).length,
        2,
      );
    });
  });
}
