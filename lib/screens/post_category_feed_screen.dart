import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../constants/app_constants.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../models/post.dart';
import '../models/post_category.dart';
import '../services/post_service.dart';
import '../ui/widgets/optimized_post_card.dart';
import '../ui/widgets/skeletons.dart';
import '../utils/responsive_helper.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';

typedef PostCategoryPageLoader = Future<PostCategoryPage> Function({
  required PostCategory category,
  DocumentSnapshot<Map<String, dynamic>>? startAfter,
  int pageSize,
  bool forceRefresh,
});

class PostCategoryFeedScreen extends StatefulWidget {
  const PostCategoryFeedScreen({
    super.key,
    required this.category,
    this.pageLoader,
  });

  static const Duration pageLoadTimeout = Duration(seconds: 12);

  final PostCategory category;
  final PostCategoryPageLoader? pageLoader;

  @override
  State<PostCategoryFeedScreen> createState() => _PostCategoryFeedScreenState();
}

class _PostCategoryFeedScreenState extends State<PostCategoryFeedScreen> {
  PostService? _postService;
  final ScrollController _scrollController = ScrollController();
  final List<Post> _posts = [];

  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _showCreateButton = true;
  Object? _error;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      final shouldShow = position.pixels <= position.minScrollExtent + 8
          ? true
          : switch (position.userScrollDirection) {
              ScrollDirection.forward => true,
              ScrollDirection.reverse => false,
              ScrollDirection.idle => _showCreateButton,
            };
      if (shouldShow != _showCreateButton && mounted) {
        setState(() => _showCreateButton = shouldShow);
      }
    }
    if (!_hasMore || _isLoading || _isLoadingMore) return;
    if (_scrollController.position.extentAfter < 480) _loadMore();
  }

  Future<PostCategoryPage> _loadPage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    bool forceRefresh = false,
  }) {
    final loader = widget.pageLoader ??
        (_postService ??= PostService()).getPostsByCategoryPage;
    return loader(
      category: widget.category,
      startAfter: startAfter,
      pageSize: 20,
      forceRefresh: forceRefresh,
    ).timeout(PostCategoryFeedScreen.pageLoadTimeout);
  }

  Future<void> _loadInitial({bool forceRefresh = false}) async {
    final generation = ++_requestGeneration;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isLoadingMore = false;
        _error = null;
      });
    }
    try {
      if (forceRefresh && widget.pageLoader == null) {
        (_postService ??= PostService()).clearCategoryCache(widget.category);
      }
      final page = await _loadPage(forceRefresh: forceRefresh);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(page.posts);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _error = error;
      });
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    final generation = _requestGeneration;
    setState(() => _isLoadingMore = true);
    try {
      final page = await _loadPage(startAfter: _cursor);
      if (!mounted || generation != _requestGeneration) return;
      final knownIds = _posts.map((post) => post.id).toSet();
      final additions =
          page.posts.where((post) => knownIds.add(post.id)).toList();
      setState(() {
        _posts.addAll(additions);
        _cursor = page.cursor;
        // 서버가 동일 페이지나 필터링 후 빈 페이지를 hasMore=true와 함께
        // 반환해도 하단 로더가 연속 호출되는 무한 페이지네이션을 막는다.
        _hasMore = page.hasMore && additions.isNotEmpty;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _error = error;
      });
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _openCreatePost() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(
          initialCategory: widget.category,
          onPostCreated: () {},
        ),
      ),
    );
    if (mounted) await _loadInitial(forceRefresh: true);
  }

  Future<void> _openPost(Post post) async {
    final preservedOffset =
        _scrollController.hasClients ? _scrollController.offset : null;
    final wasDeleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
    );
    if (!mounted) return;

    if (wasDeleted == true) {
      setState(() => _posts.removeWhere((item) => item.id == post.id));
    } else {
      // 상세 화면에서 수정된 한 건만 반영한다. 이미 불러온 페이지와 스크롤
      // 상태를 유지해 복귀 시 목록이 최신 글부터 다시 시작되지 않게 한다.
      final refreshed =
          await (_postService ??= PostService()).getPostById(post.id);
      if (!mounted) return;

      final index = _posts.indexWhere((item) => item.id == post.id);
      if (refreshed != null && index >= 0) {
        setState(() {
          if (refreshed.categoryKeys.contains(widget.category.key)) {
            _posts[index] = refreshed;
          } else {
            _posts.removeAt(index);
          }
        });
      }
    }

    _restoreScrollOffset(preservedOffset);
  }

  Future<void> _openPostCategory(PostCategory category) async {
    if (category == widget.category) {
      if (!_scrollController.hasClients) return;
      await _scrollController.animateTo(
        _scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PostCategoryFeedScreen(category: category),
      ),
    );
  }

  void _restoreScrollOffset(double? offset) {
    if (offset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target = offset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((_scrollController.offset - target).abs() > 0.5) {
        _scrollController.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = widget.category.label(l10n);
    return Scaffold(
      backgroundColor: BrandColors.surface,
      appBar: AppBar(
        backgroundColor: BrandColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: context.rh(56, min: 54, max: 60),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(18).clamp(17, 20).toDouble(),
            fontWeight: FontWeight.w700,
            color: BrandColors.textPrimary,
          ),
        ),
      ),
      floatingActionButton: _CategoryCreateButton(
        visible: _showCreateButton,
        child: FloatingActionButton(
          heroTag: 'category_post_fab_${widget.category.key}',
          onPressed: _openCreatePost,
          backgroundColor: AppColors.pointColor,
          foregroundColor: Colors.white,
          child: const Icon(Icons.add_rounded),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.pointColor,
        onRefresh: () => _loadInitial(forceRefresh: true),
        child: CustomScrollView(
          key: PageStorageKey('post_category_${widget.category.key}'),
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.s20,
                DesignTokens.s12,
                DesignTokens.s20,
                DesignTokens.s16,
              ),
              sliver: SliverToBoxAdapter(
                child: Text(
                  widget.category.description(l10n),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: BrandColors.textSecondary,
                  ),
                ),
              ),
            ),
            if (_isLoading)
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
            else if (_error != null && _posts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => _loadInitial(forceRefresh: true),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(l10n.retryAction),
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
                        l10n.postCategoryEmpty(label),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: BrandColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.s8),
                      Text(l10n.postCategoryEmptySubtitle),
                      const SizedBox(height: DesignTokens.s20),
                      FilledButton(
                        onPressed: _openCreatePost,
                        child: Text(l10n.postCategoryCreateAction),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: _posts.length,
                itemBuilder: (context, index) {
                  final post = _posts[index];
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: OptimizedPostCard(
                        key: ValueKey(post.id),
                        post: post,
                        index: index,
                        preloadImage: index < 3,
                        onTap: () => _openPost(post),
                        onCategoryTap: _openPostCategory,
                      ),
                    ),
                  );
                },
              ),
            if (_isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(DesignTokens.s20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

class _CategoryCreateButton extends StatelessWidget {
  const _CategoryCreateButton({
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: AnimatedScale(
          scale: visible ? 1 : .82,
          alignment: Alignment.bottomRight,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: child,
        ),
      ),
    );
  }
}
