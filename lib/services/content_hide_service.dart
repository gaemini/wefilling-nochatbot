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

  static List<Post> filterPostsSync(List<Post> posts) {
    if (_hiddenPostIds.isEmpty && _hiddenUserIds.isEmpty) return posts;
    return posts
        .where((p) => !_hiddenPostIds.contains(p.id) && !_hiddenUserIds.contains(p.userId))
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
    return _hiddenCommentIds.contains(commentId) || _hiddenUserIds.contains(userId);
  }

  static void clearAll() {
    _hiddenPostIds.clear();
    _hiddenCommentIds.clear();
    _hiddenMeetupIds.clear();
    _hiddenUserIds.clear();
  }
}
