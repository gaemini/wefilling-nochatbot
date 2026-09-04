import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/screens/all_posts_screen.dart';
import 'package:wefilling/services/post_service.dart';

void main() {
  testWidgets('ALL 화면은 전체 목록이 비어 있어도 정상적인 빈 상태를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AllPostsScreen(
          postsStream: Stream.value(const []),
          onRefresh: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ALL'), findsOneWidget);
    expect(find.text('표시할 포스트가 없어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ALL 화면은 최신순 포스트를 스크롤할 때 10개씩 요청한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime(2026, 8, 23, 12);
    final posts = List<Post>.generate(
      25,
      (index) => Post(
        id: 'post-$index',
        title: '',
        content: '포스트 $index',
        author: '작성자',
        createdAt: now.subtract(Duration(minutes: index)),
        userId: 'user-$index',
      ),
    );
    final requestedPageSizes = <int>[];

    Future<AllPostsPage> loadPage({
      AllPostsCursor? startAfter,
      int pageSize = 10,
    }) async {
      requestedPageSizes.add(pageSize);
      final start = startAfter == null
          ? 0
          : posts.indexWhere((post) => post.id == startAfter.postId) + 1;
      final end = (start + pageSize).clamp(0, posts.length);
      final pagePosts = posts.sublist(start, end);
      return AllPostsPage(
        posts: pagePosts,
        cursor: pagePosts.isEmpty
            ? startAfter
            : AllPostsCursor(
                createdAt: pagePosts.last.createdAt,
                postId: pagePosts.last.id,
              ),
        hasMore: end < posts.length,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AllPostsScreen(
          pageLoader: loadPage,
          postBuilder: (_, post, __) => SizedBox(
            key: ValueKey('test_${post.id}'),
            height: 120,
            child: Text(post.content),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedPageSizes, <int>[10]);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(requestedPageSizes, everyElement(10));
    expect(requestedPageSizes.length, greaterThan(1));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1600));
    await tester.pumpAndSettle();
    expect(requestedPageSizes, everyElement(10));

    final completedRequestCount = requestedPageSizes.length;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(requestedPageSizes, everyElement(10));
    expect(
        requestedPageSizes.length, greaterThanOrEqualTo(completedRequestCount));
    expect(requestedPageSizes.length, 3);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(requestedPageSizes.length, 3);
    expect(find.text('모든 포스트를 확인했어요.'), findsOneWidget);
  });
}
