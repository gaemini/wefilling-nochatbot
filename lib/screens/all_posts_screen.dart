import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../design/tokens.dart';
import '../models/post.dart';
import '../models/post_category.dart';
import '../services/post_service.dart';
import '../ui/widgets/optimized_post_card.dart';
import '../ui/widgets/skeletons.dart';
import 'post_category_feed_screen.dart';
import 'post_detail_screen.dart';

typedef AllPostsPageLoader = Future<AllPostsPage> Function({
  AllPostsCursor? startAfter,
  int pageSize,
});

typedef AllPostsItemBuilder = Widget Function(
  BuildContext context,
  Post post,
  int index,
);

class AllPostsScreen extends StatefulWidget {
  const AllPostsScreen({
    super.key,
    this.pageLoader,
    this.postsStream,
    this.onRefresh,
    this.postBuilder,
  });

  /// 프로덕션에서는 [PostService.getAllPostsPage]를 사용합니다.
  /// 테스트와 프리뷰에서는 Firebase 없이 페이지를 주입할 수 있습니다.
  final AllPostsPageLoader? pageLoader;

  /// 이전 프리뷰/테스트 호환용입니다. 실제 ALL 화면에서는 사용하지 않습니다.
  final Stream<List<Post>>? postsStream;
  final Future<void> Function()? onRefresh;
  final AllPostsItemBuilder? postBuilder;

  @override
  State<AllPostsScreen> createState() => _AllPostsScreenState();
}

class _AllPostsScreenState extends State<AllPostsScreen> {
  static const int _pageSize = 5;
  static const double _loadMoreThreshold = 520;

  PostService? _postService;
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<List<Post>>? _legacyPostsSubscription;
  final List<Post> _posts = <Post>[];

  AllPostsCursor? _cursor;
  Object? _initialError;
  Object? _loadMoreError;
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _loadGeneration = 0;

  PostService get _service => _postService ??= PostService();
  AllPostsPageLoader get _pageLoader =>
      widget.pageLoader ?? _service.getAllPostsPage;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    final stream = widget.postsStream;
    if (stream != null) {
      _legacyPostsSubscription = stream.listen(
        (posts) {
          if (!mounted) return;
          setState(() {
            _posts
              ..clear()
              ..addAll(posts)
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            _isInitialLoading = false;
            _initialError = null;
            _hasMore = false;
          });
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _isInitialLoading = false;
            _initialError = error;
          });
        },
      );
    } else {
      unawaited(_loadFirstPage());
    }
  }

  @override
  void dispose() {
    _legacyPostsSubscription?.cancel();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > _loadMoreThreshold) {
      return;
    }
    unawaited(_loadMore());
  }

  Future<void> _loadFirstPage({bool showLoading = true}) async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _isInitialLoading = true;
        _isLoadingMore = false;
        if (showLoading) _initialError = null;
      });
    }

    try {
      final page = await _pageLoader(
        startAfter: null,
        pageSize: _pageSize,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(page.posts)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _initialError = null;
        _loadMoreError = null;
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _initialError = error;
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isInitialLoading || _isLoadingMore || !_hasMore) return;

    final previousCursor = _cursor;
    final generation = _loadGeneration;
    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await _pageLoader(
        startAfter: previousCursor,
        pageSize: _pageSize,
      );
      if (!mounted || generation != _loadGeneration) return;

      final byId = <String, Post>{for (final post in _posts) post.id: post};
      for (final post in page.posts) {
        byId[post.id] = post;
      }
      final merged = byId.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final cursorProgressed =
          page.cursor?.createdAt != previousCursor?.createdAt ||
              page.cursor?.postId != previousCursor?.postId;
      setState(() {
        _posts
          ..clear()
          ..addAll(merged);
        _cursor = page.cursor;
        _hasMore = page.hasMore && (page.posts.isNotEmpty || cursorProgressed);
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadMoreError = error;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _refresh() async {
    final callback = widget.onRefresh;
    if (callback != null) await callback();
    if (widget.postsStream != null) return;
    await _loadFirstPage(showLoading: false);
  }

  Future<void> _openPost(Post post) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
    );
  }

  Future<void> _openCategory(PostCategory category) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PostCategoryFeedScreen(category: category),
      ),
    );
  }

  Widget _buildPost(BuildContext context, Post post, int index) {
    final builder = widget.postBuilder;
    if (builder != null) return builder(context, post, index);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: OptimizedPostCard(
          key: ValueKey('all_post_${post.id}'),
          post: post,
          index: index,
          preloadImage: index < 3,
          onTap: () => _openPost(post),
          onCategoryTap: _openCategory,
        ),
      ),
    );
  }

  Widget _buildFooter(bool isKo) {
    if (_isLoadingMore) {
      return const Padding(
        key: ValueKey('all_posts_loading_more'),
        padding: EdgeInsets.fromLTRB(0, 20, 0, 34),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Center(
          child: TextButton.icon(
            key: const ValueKey('all_posts_load_more_retry'),
            onPressed: _loadMore,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(isKo ? '더 불러오기' : 'Load more'),
          ),
        ),
      );
    }
    if (!_hasMore && _posts.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
        child: Text(
          isKo ? '모든 포스트를 확인했어요.' : 'You have reached the end.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: BrandColors.textHint,
          ),
        ),
      );
    }
    return const SizedBox(height: 44);
  }

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Scaffold(
      backgroundColor: BrandColors.surface,
      appBar: AppBar(
        backgroundColor: BrandColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'ALL',
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: BrandColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: AppColors.pointColor,
          backgroundColor: BrandColors.surface,
          onRefresh: _refresh,
          child: CustomScrollView(
            key: const PageStorageKey('all_posts_paginated_list'),
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (_isInitialLoading && _posts.isEmpty)
                SliverList.builder(
                  itemCount: 4,
                  itemBuilder: (_, __) => const Padding(
                    padding: EdgeInsets.fromLTRB(20, 10, 20, 18),
                    child: AppSkeleton(
                      width: double.infinity,
                      height: 220,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                )
              else if (_initialError != null && _posts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: TextButton.icon(
                      onPressed: _loadFirstPage,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(isKo ? '다시 시도' : 'Try again'),
                    ),
                  ),
                )
              else if (_posts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(DesignTokens.s24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.article_outlined,
                          size: 42,
                          color: BrandColors.textTertiary,
                        ),
                        const SizedBox(height: DesignTokens.s16),
                        Text(
                          isKo
                              ? '표시할 포스트가 없어요.'
                              : 'There are no posts to show.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: BrandColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                SliverList.builder(
                  itemCount: _posts.length,
                  itemBuilder: (context, index) =>
                      _buildPost(context, _posts[index], index),
                ),
                SliverToBoxAdapter(child: _buildFooter(isKo)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
