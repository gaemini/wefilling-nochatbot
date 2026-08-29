import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/models/review_post.dart';
import 'package:wefilling/services/cache/my_page_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory cacheDirectory;
  late MyPageCacheService service;

  setUp(() async {
    cacheDirectory =
        await Directory.systemTemp.createTemp('mypage_cache_test_');
    Hive.init(cacheDirectory.path);
    MyPageCacheService.clearMemory();
    service = MyPageCacheService();
  });

  tearDown(() async {
    MyPageCacheService.clearMemory();
    await Hive.close();
    if (await cacheDirectory.exists()) {
      await cacheDirectory.delete(recursive: true);
    }
  });

  test('restores posts from disk after the memory cache is cleared', () async {
    final createdAt = DateTime(2026, 7, 24, 10, 30);
    final post = Post(
      id: 'post-1',
      title: 'cached post',
      content: 'cached content',
      author: 'tester',
      createdAt: createdAt,
      userId: 'user-1',
      imageUrls: const ['https://example.com/post.jpg'],
    );

    await service.saveUserPosts('user-1', [post]);
    MyPageCacheService.clearMemory();

    final cached = await MyPageCacheService().readUserPosts('user-1');

    expect(cached, isNotNull);
    expect(cached!.isFresh, isTrue);
    expect(cached.items, hasLength(1));
    expect(cached.items.single.id, 'post-1');
    expect(cached.items.single.title, 'cached post');
    expect(cached.items.single.createdAt, createdAt);
    expect(
      cached.items.single.imageUrls,
      const ['https://example.com/post.jpg'],
    );
  });

  test('keeps saved posts isolated for each signed-in user', () async {
    Post postFor(String id, String userId) => Post(
          id: id,
          title: id,
          content: '',
          author: 'tester',
          createdAt: DateTime(2026, 7, 24),
          userId: userId,
        );

    await service.saveSavedPosts('user-a', [postFor('a-post', 'user-a')]);
    await service.saveSavedPosts('user-b', [postFor('b-post', 'user-b')]);

    final userA = await service.readSavedPosts('user-a');
    final userB = await service.readSavedPosts('user-b');

    expect(userA!.items.single.id, 'a-post');
    expect(userB!.items.single.id, 'b-post');
  });

  test('restores the current user friend count without a friend list', () async {
    await service.saveFriendCount('user-1', 49);
    MyPageCacheService.clearMemory();

    final cachedCount =
        await MyPageCacheService().readFriendCount('user-1');

    expect(cachedCount, 49);
    expect(await service.readFriendCount('user-2'), isNull);
  });

  test('never persists a negative friend count', () async {
    await service.saveFriendCount('user-1', -1);
    MyPageCacheService.clearMemory();

    expect(await MyPageCacheService().readFriendCount('user-1'), 0);
  });

  test('keeps every tag when a multi-tag saved post is restored', () async {
    final post = Post(
      id: 'multi-tag-saved-post',
      title: '',
      content: 'saved content',
      author: 'tester',
      categoryKeys: const ['content', 'photo', 'cafe'],
      createdAt: DateTime(2026, 8, 25),
      userId: 'author-1',
    );

    await service.saveSavedPosts('user-1', [post]);
    MyPageCacheService.clearMemory();

    final cached = await MyPageCacheService().readSavedPosts('user-1');

    expect(cached, isNotNull);
    expect(
      cached!.items.single.categoryKeys,
      const ['content', 'photo', 'cafe'],
    );
  });

  test('round-trips meetup reviews through the persistent cache', () async {
    final review = ReviewPost(
      id: 'review-1',
      authorId: 'user-1',
      authorName: 'tester',
      authorProfileImage: '',
      meetupId: 'meetup-1',
      meetupTitle: 'meetup',
      imageUrls: const ['https://example.com/review.jpg'],
      content: 'review',
      category: 'meetup',
      rating: 5,
      taggedUserIds: const [],
      createdAt: DateTime(2026, 7, 24, 12),
      likedBy: const ['friend-1'],
      commentCount: 2,
      privacyLevel: PrivacyLevel.public,
    );

    await service.saveReviews('user-1', [review]);
    MyPageCacheService.clearMemory();

    final cached = await MyPageCacheService().readReviews('user-1');

    expect(cached, isNotNull);
    expect(cached!.items.single.id, 'review-1');
    expect(cached.items.single.imageUrls.single, contains('review.jpg'));
    expect(cached.items.single.likedBy, const ['friend-1']);
  });
}
