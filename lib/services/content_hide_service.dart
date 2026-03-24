import '../models/post.dart';
import '../models/meetup.dart';

/// Client-side immediate hide cache for reported content/users.
///
/// Apple Guideline 1.2 대응:
/// - 신고 직후 서버 처리와 무관하게 사용자 피드에서 즉시 숨김
/// - 앱 세션 내 즉시 반영을 위한 in-memory 캐시
class ContentHideService {
  static final Set<String> _hiddenPostIds = <String>{};
  static final Set<String> _hiddenCommentIds = <String>{};
  static final Set<String> _hiddenMeetupIds = <String>{};
  static final Set<String> _hiddenUserIds = <String>{};
  static final Set<String> _hiddenAnonymousPostIds = <String>{};
  static final Set<String> _hiddenAnonymousCommentIds = <String>{};

  static void hideReportedTarget({
    required String targetType,
    required String targetId,
    String? reportedUserId,
  }) {
    final type = targetType.trim().toLowerCase();
    final id = targetId.trim();
    final uid = (reportedUserId ?? '').trim();

    if (id.isNotEmpty) {
      if (type == 'post') {
        _hiddenPostIds.add(id);
      } else if (type == 'comment') {
        _hiddenCommentIds.add(id);
      } else if (type == 'meetup') {
        _hiddenMeetupIds.add(id);
      } else if (type == 'user') {
        _hiddenUserIds.add(id);
      }
    }

    if (uid.isNotEmpty) {
      _hiddenUserIds.add(uid);
    }
  }

  static bool isHiddenPost(String postId) => _hiddenPostIds.contains(postId.trim());
  static bool isHiddenComment(String commentId) => _hiddenCommentIds.contains(commentId.trim());
  static bool isHiddenMeetup(String meetupId) => _hiddenMeetupIds.contains(meetupId.trim());
  static bool isHiddenUser(String userId) => _hiddenUserIds.contains(userId.trim());
  static bool isHiddenAnonymousPost(String postId) =>
      _hiddenAnonymousPostIds.contains(postId.trim());
  static bool isHiddenAnonymousComment(String commentId) =>
      _hiddenAnonymousCommentIds.contains(commentId.trim());

  static void hideAnonymousPost(String postId) {
    final id = postId.trim();
    if (id.isEmpty) return;
    _hiddenAnonymousPostIds.add(id);
  }

  static void unhideAnonymousPost(String postId) {
    final id = postId.trim();
    if (id.isEmpty) return;
    _hiddenAnonymousPostIds.remove(id);
  }

  static void addHiddenAnonymousPostIds(Iterable<String> postIds) {
    for (final postId in postIds) {
      final id = postId.trim();
      if (id.isNotEmpty) {
        _hiddenAnonymousPostIds.add(id);
      }
    }
  }

  static void hideAnonymousComment(String commentId) {
    final id = commentId.trim();
    if (id.isEmpty) return;
    _hiddenAnonymousCommentIds.add(id);
  }

  static void unhideAnonymousComment(String commentId) {
    final id = commentId.trim();
    if (id.isEmpty) return;
    _hiddenAnonymousCommentIds.remove(id);
  }

  static void addHiddenAnonymousCommentIds(Iterable<String> commentIds) {
    for (final commentId in commentIds) {
      final id = commentId.trim();
      if (id.isNotEmpty) {
        _hiddenAnonymousCommentIds.add(id);
      }
    }
  }

  static List<Post> filterPostsSync(List<Post> posts) {
    if (_hiddenPostIds.isEmpty &&
        _hiddenUserIds.isEmpty &&
        _hiddenAnonymousPostIds.isEmpty) {
      return posts;
    }
    return posts
        .where((p) =>
            !_hiddenPostIds.contains(p.id) &&
            !_hiddenAnonymousPostIds.contains(p.id) &&
            !_hiddenUserIds.contains(p.userId))
        .toList();
  }

  static List<Meetup> filterMeetupsSync(List<Meetup> meetups) {
    if (_hiddenMeetupIds.isEmpty && _hiddenUserIds.isEmpty) return meetups;
    return meetups
        .where((m) => !_hiddenMeetupIds.contains(m.id) && !_hiddenUserIds.contains(m.userId))
        .toList();
  }

  static bool shouldHideComment({
    required String commentId,
    required String userId,
  }) {
    // 익명 댓글 숨김은 플레이스홀더로 대체되어야 하므로 여기서 제외
    return _hiddenCommentIds.contains(commentId) || _hiddenUserIds.contains(userId);
  }

  static void clearAll() {
    _hiddenPostIds.clear();
    _hiddenCommentIds.clear();
    _hiddenMeetupIds.clear();
    _hiddenUserIds.clear();
    _hiddenAnonymousPostIds.clear();
    _hiddenAnonymousCommentIds.clear();
  }
}
