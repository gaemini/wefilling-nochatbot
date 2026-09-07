import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/comment.dart';
import 'package:wefilling/models/content_translation.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/utils/post_translation_policy.dart';

Post _post({
  String userId = 'author',
  bool anonymous = false,
  int likes = 0,
  int views = 0,
  int comments = 0,
  int optionVotes = 0,
}) {
  return Post(
    id: 'same-id',
    title: 'legacy title',
    content: 'Question?',
    author: 'Writer',
    createdAt: DateTime(2026, 8, 29),
    userId: userId,
    isAnonymous: anonymous,
    type: 'poll',
    likes: likes,
    viewCount: views,
    commentCount: comments,
    pollOptions: <PollOption>[
      PollOption(id: 'yes', text: 'Yes', votes: optionVotes),
      const PollOption(id: 'no', text: 'No'),
    ],
  );
}

Comment _comment({
  required String id,
  String postId = 'post-1',
  String userId = 'other-user',
  String content = 'Original',
  String? parentCommentId,
  bool isDeleted = false,
}) {
  return Comment(
    id: id,
    postId: postId,
    userId: userId,
    authorNickname: 'Writer',
    authorPhotoUrl: '',
    content: content,
    createdAt: DateTime(2026, 9, 5),
    parentCommentId: parentCommentId,
    depth: parentCommentId == null ? 0 : 1,
    isDeleted: isDeleted,
  );
}

void main() {
  group('post translation policy', () {
    test('own posts keep the same translation source fields', () {
      final ownPost = postTranslationSourceFields(_post(userId: 'me'));
      final anonymousOwnPost = postTranslationSourceFields(
        _post(userId: 'me', anonymous: true),
      );

      expect(ownPost, isNotEmpty);
      expect(anonymousOwnPost, ownPost);
    });

    test('identifies my comment by internal uid', () {
      final comment = Comment(
        id: 'comment',
        postId: 'post',
        userId: 'me',
        authorNickname: 'Anonymous',
        authorPhotoUrl: '',
        content: 'Original',
        createdAt: DateTime(2026, 8, 29),
      );
      expect(isOwnCommentForTranslation(comment, 'me'), isTrue);
    });

    test('source fields contain text and stable poll option ids only', () {
      final first = postTranslationSourceFields(_post());
      final engagementOnlyChange = postTranslationSourceFields(
        _post(likes: 20, views: 50, comments: 3, optionVotes: 9),
      );

      expect(first, engagementOnlyChange);
      expect(first, <String, String>{
        'content': 'Question?',
        'pollOption:yes': 'Yes',
        'pollOption:no': 'No',
      });
    });

    test('content type keeps post and comment cache identities separate', () {
      const postRequest = ContentTranslationRequest(
        contentType: 'post',
        contentId: 'same-id',
        sourceFields: <String, String>{'content': 'text'},
      );
      const commentRequest = ContentTranslationRequest(
        contentType: 'comment',
        contentId: 'same-id',
        sourceFields: <String, String>{'content': 'text'},
      );
      expect(postRequest.serverId, isNot(commentRequest.serverId));
    });

    test('comment scope remains stable when list membership or order changes',
        () {
      final before = <Comment>[
        _comment(id: 'first'),
        _comment(id: 'middle'),
        _comment(id: 'last'),
      ];
      final after = <Comment>[
        _comment(id: 'new'),
        before.last,
        before.first,
        before[1],
      ];

      expect(commentTranslationScope('post-1'), 'post-comments:post-1');
      expect(
        after.map(
          (comment) => commentTranslationItemKey(
            comment,
            postId: 'post-1',
          ),
        ),
        containsAll(<String>[
          'comment:post-1:first',
          'comment:post-1:middle',
          'comment:post-1:last',
        ]),
      );
    });

    test('middle and last comments are independently eligible', () {
      final comments = <Comment>[
        _comment(id: 'first'),
        _comment(id: 'middle'),
        _comment(id: 'last'),
      ];

      expect(
        comments.map((comment) =>
            isCommentTranslationCandidate(comment, 'current-user')),
        everyElement(isTrue),
      );
    });

    test('own, deleted, and empty comments do not enter translation queue', () {
      expect(
        isCommentTranslationCandidate(
          _comment(id: 'own', userId: 'me'),
          'me',
        ),
        isFalse,
      );
      expect(
        isCommentTranslationCandidate(
          _comment(id: 'deleted', isDeleted: true),
          'me',
        ),
        isFalse,
      );
      expect(
        isCommentTranslationCandidate(
          _comment(id: 'empty', content: '  '),
          'me',
        ),
        isFalse,
      );
    });

    test('reply UI identity includes parent while callable keeps document id',
        () {
      final top = _comment(id: 'same-id');
      final firstReply = _comment(
        id: 'same-id',
        parentCommentId: 'parent-a',
      );
      final secondReply = _comment(
        id: 'same-id',
        parentCommentId: 'parent-b',
      );

      final topKey = commentTranslationItemKey(top, postId: 'post-1');
      final firstReplyKey =
          commentTranslationItemKey(firstReply, postId: 'post-1');
      final secondReplyKey =
          commentTranslationItemKey(secondReply, postId: 'post-1');
      expect(<String>{topKey, firstReplyKey, secondReplyKey}, hasLength(3));

      final request = commentTranslationRequest(
        firstReply,
        postId: 'post-1',
      );
      expect(request.serverId, 'comment:post-1:same-id');
      expect(request.sourceFields, <String, String>{'content': 'Original'});
    });

    test('comment edit changes translation source without changing identity',
        () {
      final before = commentTranslationRequest(
        _comment(id: 'comment-1', content: 'Before'),
        postId: 'post-1',
      );
      final after = commentTranslationRequest(
        _comment(id: 'comment-1', content: 'After'),
        postId: 'post-1',
      );

      expect(before.serverId, after.serverId);
      expect(before.sourceFields, isNot(after.sourceFields));
    });
  });
}
