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
  });
}
