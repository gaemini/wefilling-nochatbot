import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/services/active_content_registry.dart';

// Run with `--dart-define=ACTIVE_CONTENT_AUTO_READ=true` to exercise the
// registry itself; the scope matching below is flag-independent.
void main() {
  const owner = 'uid-owner';
  Map<String, dynamic> notification({
    String type = 'new_like',
    String? postId = 'post-1',
    String? commentId,
    String userId = owner,
  }) =>
      <String, dynamic>{
        'userId': userId,
        'type': type,
        if (postId != null) 'postId': postId,
        if (commentId != null) 'commentId': commentId,
      };

  group('ActiveContentScope', () {
    const postScope = ActiveContentScope(
      types: {'post_created', 'post_private', 'new_like'},
      targets: {'postId': 'post-1'},
    );
    const commentScope = ActiveContentScope(
      types: {'new_comment', 'comment_reply', 'comment_like'},
      targets: {'postId': 'post-1', 'commentId': 'c-9'},
    );

    test('matches only the owner, the scoped types and every target', () {
      expect(postScope.matches(notification(), owner: owner), isTrue);
      expect(postScope.matches(notification(postId: 'post-2'), owner: owner),
          isFalse);
      expect(postScope.matches(notification(userId: 'someone'), owner: owner),
          isFalse);
      expect(
          postScope.matches(notification(type: 'new_comment'), owner: owner),
          isFalse);
    });

    test('a comment scope never covers the post-level notification', () {
      expect(commentScope.matches(notification(), owner: owner), isFalse);
      expect(
          commentScope.matches(
              notification(type: 'comment_like', commentId: 'c-9'),
              owner: owner),
          isTrue);
      expect(
          commentScope.matches(
              notification(type: 'comment_like', commentId: 'c-1'),
              owner: owner),
          isFalse);
    });

    test('empty scopes match nothing', () {
      const empty = ActiveContentScope(types: {}, targets: {});
      expect(empty.isEmpty, isTrue);
      expect(empty.matches(notification(), owner: owner), isFalse);
    });
  });

  test('FCM payloads are normalized onto the notification shape', () {
    final normalized = ActiveContentRegistry.payloadAsNotification({
      'type': 'new_like',
      'recipientUserId': owner,
      'postId': 'post-1',
      'notificationId': 'n-1',
    });
    expect(normalized['userId'], owner);
    expect(normalized['postId'], 'post-1');
    const scope = ActiveContentScope(
        types: {'new_like'}, targets: {'postId': 'post-1'});
    expect(scope.matches(normalized, owner: owner), isTrue);
    expect(scope.matches(normalized, owner: 'other'), isFalse);
  });

  group('registry', () {
    setUp(ActiveContentRegistry.resetForTesting);

    test('disabled builds register nothing; enabled builds match scopes', () {
      final token = Object();
      ActiveContentRegistry.register(token,
          types: const {'new_like'}, targets: const {'postId': 'post-1'});
      if (!ActiveContentRegistry.enabled) {
        expect(ActiveContentRegistry.hasScopes, isFalse);
        expect(ActiveContentRegistry.matches(notification(), owner: owner),
            isFalse);
        return;
      }
      expect(ActiveContentRegistry.hasScopes, isTrue);
      expect(
          ActiveContentRegistry.matches(notification(), owner: owner), isTrue);
      expect(
          ActiveContentRegistry.matches(notification(postId: 'post-2'),
              owner: owner),
          isFalse);
      ActiveContentRegistry.unregister(token);
      expect(ActiveContentRegistry.hasScopes, isFalse);
      expect(
          ActiveContentRegistry.matches(notification(), owner: owner), isFalse);
    });

    test('blank targets collapse to no scope and never match everything', () {
      final token = Object();
      ActiveContentRegistry.register(token,
          types: const {'new_like'}, targets: const {'postId': '  '});
      expect(ActiveContentRegistry.hasScopes, isFalse);
      expect(
          ActiveContentRegistry.matches(notification(), owner: owner), isFalse);
    });
  });
}
