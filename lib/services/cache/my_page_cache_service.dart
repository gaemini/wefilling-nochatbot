import 'package:hive/hive.dart';

import '../../models/post.dart';
import '../../models/review_post.dart';
import '../../utils/logger.dart';

/// 마이페이지 탭 데이터를 사용자별로 보관하는 영구 캐시입니다.
///
/// 오래된 데이터도 즉시 표시할 수 있도록 읽어 오되, [isFresh]를 통해
/// 네트워크 갱신 여부를 호출자가 결정합니다.
class MyPageCacheEntry<T> {
  const MyPageCacheEntry({
    required this.items,
    required this.cachedAt,
    required this.isFresh,
  });

  final List<T> items;
  final DateTime cachedAt;
  final bool isFresh;
}

class MyPageCacheService {
  static const String boxName = 'my_page_tabs_v1';
  static const int _schemaVersion = 2;
  static const Duration cacheTtl = Duration(minutes: 30);

  /// 같은 앱 실행 중에는 Hive 접근조차 반복하지 않도록 하는 1차 메모리 캐시.
  /// 영구 저장소(Hive)는 앱 재실행 후 복원용 2차 캐시로 사용한다.
  static final Map<String, _RawCacheEntry> _memoryCache = {};

  Future<Box<dynamic>>? _openingBox;

  static void clearMemory() => _memoryCache.clear();

  Future<MyPageCacheEntry<Post>?> readUserPosts(String userId) {
    return _readPosts(_key(userId, 'posts'));
  }

  Future<MyPageCacheEntry<Post>?> readSavedPosts(String userId) {
    return _readPosts(_key(userId, 'saved_posts'));
  }

  Future<MyPageCacheEntry<ReviewPost>?> readReviews(String userId) async {
    final raw = await _readRaw(_key(userId, 'reviews'));
    if (raw == null) return null;

    try {
      final reviews = raw.items
          .whereType<Map>()
          .map((item) => ReviewPost.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
      return MyPageCacheEntry<ReviewPost>(
        items: reviews,
        cachedAt: raw.cachedAt,
        isFresh: raw.isFresh,
      );
    } catch (error) {
      Logger.error('마이페이지 후기 캐시 파싱 실패', error);
      return null;
    }
  }

  Future<void> saveUserPosts(String userId, List<Post> posts) {
    return _write(
      _key(userId, 'posts'),
      posts.map((post) => post.toMap()).toList(growable: false),
    );
  }

  Future<void> saveSavedPosts(String userId, List<Post> posts) {
    return _write(
      _key(userId, 'saved_posts'),
      posts.map((post) => post.toMap()).toList(growable: false),
    );
  }

  Future<void> saveReviews(String userId, List<ReviewPost> reviews) {
    return _write(
      _key(userId, 'reviews'),
      reviews.map((review) => review.toJson()).toList(growable: false),
    );
  }

  Future<MyPageCacheEntry<Post>?> _readPosts(String key) async {
    final raw = await _readRaw(key);
    if (raw == null) return null;

    try {
      final posts = raw.items.whereType<Map>().map((item) {
        final data = Map<String, dynamic>.from(item);
        return Post.fromMap(data, data['id']?.toString() ?? '');
      }).toList(growable: false);
      return MyPageCacheEntry<Post>(
        items: posts,
        cachedAt: raw.cachedAt,
        isFresh: raw.isFresh,
      );
    } catch (error) {
      Logger.error('마이페이지 포스트 캐시 파싱 실패', error);
      return null;
    }
  }

  Future<_RawCacheEntry?> _readRaw(String key) async {
    try {
      final memoryEntry = _memoryCache[key];
      if (memoryEntry != null) {
        return memoryEntry.withFreshness(
          DateTime.now().difference(memoryEntry.cachedAt) <= cacheTtl,
        );
      }

      final box = await _box();
      if (box == null) return null;

      final value = box.get(key);
      if (value is! Map) return null;

      final map = Map<dynamic, dynamic>.from(value);
      final cachedAtValue = map['cachedAt'];
      final itemsValue = map['items'];
      if (cachedAtValue is! int || itemsValue is! List) return null;

      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtValue);
      final entry = _RawCacheEntry(
        items: List<dynamic>.from(itemsValue),
        cachedAt: cachedAt,
        isFresh: DateTime.now().difference(cachedAt) <= cacheTtl,
      );
      _memoryCache[key] = entry;
      return entry;
    } catch (error) {
      Logger.error('마이페이지 캐시 읽기 실패', error);
      return null;
    }
  }

  Future<void> _write(String key, List<Map<String, dynamic>> items) async {
    final cachedAt = DateTime.now();
    final cachedItems = items
        .map<dynamic>((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    _memoryCache[key] = _RawCacheEntry(
      items: cachedItems,
      cachedAt: cachedAt,
      isFresh: true,
    );

    try {
      final box = await _box();
      if (box == null) return;

      await box.put(key, <String, dynamic>{
        'cachedAt': cachedAt.millisecondsSinceEpoch,
        'items': cachedItems,
      });
    } catch (error) {
      Logger.error('마이페이지 캐시 저장 실패', error);
    }
  }

  Future<Box<dynamic>?> _box() async {
    try {
      if (Hive.isBoxOpen(boxName)) {
        return Hive.box<dynamic>(boxName);
      }

      final openingBox = _openingBox ??= Hive.openBox<dynamic>(boxName);
      final box = await openingBox;
      if (box.isOpen) return box;

      _openingBox = Hive.openBox<dynamic>(boxName);
      return await _openingBox;
    } catch (error) {
      _openingBox = null;
      Logger.error('마이페이지 캐시 박스 열기 실패', error);
      return null;
    }
  }

  String _key(String userId, String tab) => 'v$_schemaVersion::$userId::$tab';
}

class _RawCacheEntry {
  const _RawCacheEntry({
    required this.items,
    required this.cachedAt,
    required this.isFresh,
  });

  final List<dynamic> items;
  final DateTime cachedAt;
  final bool isFresh;

  _RawCacheEntry withFreshness(bool value) {
    if (value == isFresh) return this;
    return _RawCacheEntry(
      items: items,
      cachedAt: cachedAt,
      isFresh: value,
    );
  }
}
