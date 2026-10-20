import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 태그 페이지를 마지막으로 본 시각(기기 저장). 게시판 '내 #태그 새 글' 개수의 기준.
class TagSeenStore {
  TagSeenStore._();

  static String _key(String tagId) =>
      'tag_seen_${FirebaseAuth.instance.currentUser?.uid ?? 'guest'}_$tagId';

  static Future<void> markSeen(String tagId, {DateTime? at}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _key(tagId), (at ?? DateTime.now()).millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<Map<String, int>> seenTimes(Iterable<String> tagIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        for (final id in tagIds)
          if (prefs.getInt(_key(id)) case final millis?) id: millis,
      };
    } catch (_) {
      return const {};
    }
  }
}
