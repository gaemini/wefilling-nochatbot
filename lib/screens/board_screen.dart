// lib/screens/board_screen.dart
// 나눔 피드 화면 - 나눔 / 피드 2개 탭으로 게시글 구성
// 나눔 탭: 나눔 카테고리({생활용품, 전자기기, 도서, 기타}) 전용
// 피드 탭: 그 외 일반(레거시) 게시글

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../constants/app_constants.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../services/comment_service.dart';
import '../services/content_filter_service.dart';
import '../services/cache/app_image_cache_manager.dart';
import '../services/post_service.dart';
import '../ui/widgets/app_fab.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/skeletons.dart';
import '../utils/logger.dart';
import '../utils/sharing_category.dart';
import '../widgets/ad_banner_widget.dart';
import 'create_post_screen.dart';
import 'create_sharing_post_screen.dart';
import 'create_snack_chat_screen.dart';
import 'hanyang_email_verification_screen.dart';
import 'post_detail_screen.dart';

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => BoardScreenState();
}

class BoardScreenState extends State<BoardScreen>
    with SingleTickerProviderStateMixin {
  final PostService _postService = PostService();
  final CommentService _commentService = CommentService();

  late TabController _tabController;

  // 스크롤 위치 복원을 위한 컨트롤러들
  late final ScrollController _sharingScrollController;
  late final ScrollController _feedScrollController;
  bool _controllersInitialized = false;
  static const String _psTabIndexId = 'board.tabIndex.v2';
  static const String _psSharingOffsetId = 'board.sharingScrollOffset.v2';
  static const String _psFeedOffsetId = 'board.feedScrollOffset.v2';

  // 수동 새로고침 시 계산한 댓글 수 오버라이드 (postId -> count)
  final Map<String, int> _commentCountOverrides = {};
  bool _didAutoRefreshSharingCommentCounts = false;
  bool _didAutoRefreshFeedCommentCounts = false;

  // 캐시된 데이터 (부드러운 탭 전환)
  List<Post>? _cachedSharingPosts;
  List<Post>? _cachedFeedPosts;
  String? _activeSharingGatePostId;

  // 나눔 스트림 인스턴스 고정 (매 빌드마다 새 Firestore 구독 생성 방지)
  Stream<List<Post>>? _sharingPostsStream;

  // 로컬에서 삭제 확정된 게시글 ID (스트림 갱신 전 즉시 UI 반영용)
  final Set<String> _locallyDeletedPostIds = {};

  @override
  void initState() {
    super.initState();
    _sharingPostsStream = _postService.getSharingPostsStream();
    _loadCachedData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initControllersIfNeeded();
  }

  void _initControllersIfNeeded() {
    if (_controllersInitialized) return;

    final storage = PageStorage.of(context);
    final savedTabIndex =
        (storage.readState(context, identifier: _psTabIndexId) as int?) ?? 0;
    final savedSharingOffset = (storage.readState(context,
            identifier: _psSharingOffsetId) as double?) ??
        0.0;
    final savedFeedOffset =
        (storage.readState(context, identifier: _psFeedOffsetId) as double?) ??
            0.0;

    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: savedTabIndex.clamp(0, 1),
    );
    _sharingScrollController = ScrollController(
      initialScrollOffset: savedSharingOffset < 0 ? 0 : savedSharingOffset,
    );
    _feedScrollController = ScrollController(
      initialScrollOffset: savedFeedOffset < 0 ? 0 : savedFeedOffset,
    );

    _sharingScrollController.addListener(_handleScrollChanged);
    _feedScrollController.addListener(_handleScrollChanged);
    _tabController.addListener(_handleTabChanged);

    _controllersInitialized = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _clampScrollOffsetsIfNeeded();
    });
  }

  void _persistBoardState({bool persistOffsets = true}) {
    final storage = PageStorage.of(context);
    storage.writeState(
      context,
      _tabController.index,
      identifier: _psTabIndexId,
    );

    if (!persistOffsets) return;
    if (_sharingScrollController.hasClients) {
      storage.writeState(
        context,
        _sharingScrollController.offset,
        identifier: _psSharingOffsetId,
      );
    }
    if (_feedScrollController.hasClients) {
      storage.writeState(
        context,
        _feedScrollController.offset,
        identifier: _psFeedOffsetId,
      );
    }
  }

  void _clampScrollOffsetsIfNeeded() {
    void clamp(ScrollController c) {
      if (!c.hasClients) return;
      final pos = c.position;
      final target = c.offset.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (target != c.offset) c.jumpTo(target);
    }

    clamp(_sharingScrollController);
    clamp(_feedScrollController);
  }

  /// 캐시된 데이터를 먼저 로드하여 즉시 화면에 표시
  Future<void> _loadCachedData() async {
    try {
      await ContentFilterService.preloadBlockLists();
      final cachedPosts = await _postService.getCachedPosts();
      if (!mounted) return;
      if (cachedPosts.isNotEmpty) {
        setState(() {
          _cachedFeedPosts =
              cachedPosts.where((p) => !isSharingPost(p)).toList();
        });
        Logger.log('✅ 캐시된 게시글 로드 완료: ${cachedPosts.length}개');
      }
    } catch (e) {
      Logger.error('캐시 로드 오류: $e');
    }
  }

  /// 댓글 수 재집계 - 백그라운드에서 조용히 처리
  Future<void> _refreshCommentCountsForPosts(
    List<Post> posts, {
    bool silent = false,
  }) async {
    const maxTargets = 40;
    final ids = posts.map((p) => p.id).toSet().take(maxTargets).toList();
    if (ids.isEmpty) return;

    final counts = await _commentService.fetchCommentCountsForPostIds(ids);
    if (!mounted) return;

    if (silent) {
      _commentCountOverrides.addAll(counts);
    } else {
      setState(() {
        _commentCountOverrides.addAll(counts);
      });
    }
  }

  @override
  void dispose() {
    Logger.log('🔄 BoardScreen dispose 시작');
    if (_controllersInitialized) {
      try {
        _persistBoardState();
      } catch (_) {}

      _tabController.removeListener(_handleTabChanged);
      _sharingScrollController.removeListener(_handleScrollChanged);
      _feedScrollController.removeListener(_handleScrollChanged);
      _tabController.dispose();
      _sharingScrollController.dispose();
      _feedScrollController.dispose();
    }
    Logger.log('✅ BoardScreen dispose 완료');
    super.dispose();
  }

  ScrollController get _activeScrollController {
    return _tabController.index == 0
        ? _sharingScrollController
        : _feedScrollController;
  }

  void _handleTabChanged() {
    if (!mounted) return;
    if (_tabController.indexIsChanging) return;
    _persistBoardState(persistOffsets: false);
  }

  void _handleScrollChanged() {
    if (!mounted) return;
    _persistBoardState(persistOffsets: true);
  }

  // 외부(MainScreen)에서 호출할 수 있는 public 메서드
  void scrollToTop() {
    final controller = _activeScrollController;
    if (!controller.hasClients) return;
    controller.animateTo(
      controller.position.minScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEBEBEB),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSharingStreamTab(),
                _buildFeedStreamTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: AppFab.write(
        onPressed: _openCreateEntrySheet,
        heroTag: 'board_write_fab',
      ),
    );
  }

  Widget _buildSharingStreamTab() {
    return StreamBuilder<List<Post>>(
      stream: _sharingPostsStream,
      builder: (context, snapshot) => _buildSharingTab(snapshot),
    );
  }

  Widget _buildFeedStreamTab() {
    return StreamBuilder<List<Post>>(
      stream: _postService.getPostsStream(),
      builder: (context, snapshot) => _buildFeedTab(snapshot),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          final isSharingSelected = _tabController.index == 0;
          final isKo = Localizations.localeOf(context).languageCode == 'ko';

          const selectedBase = TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          );
          const unselectedBase = TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          );

          return TabBar(
            controller: _tabController,
            indicatorColor: AppColors.pointColor,
            indicatorWeight: 2.5,
            overlayColor:
                WidgetStateProperty.all(Colors.black.withValues(alpha: 0.04)),
            tabs: [
              Tab(
                child: Text(
                  isKo ? '나눔' : 'Sharing',
                  style: (isSharingSelected ? selectedBase : unselectedBase)
                      .copyWith(
                    color: isSharingSelected
                        ? AppColors.pointColor
                        : (Colors.grey[600] ?? const Color(0xFF6B7280)),
                  ),
                ),
              ),
              Tab(
                child: Text(
                  isKo ? '피드' : 'Feed',
                  style: (!isSharingSelected ? selectedBase : unselectedBase)
                      .copyWith(
                    color: !isSharingSelected
                        ? AppColors.pointColor
                        : (Colors.grey[600] ?? const Color(0xFF6B7280)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSharingTab(AsyncSnapshot<List<Post>> snapshot) {
    final isLoading = snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData &&
        _cachedSharingPosts == null;

    final isError = snapshot.hasError &&
        (_cachedSharingPosts == null || _cachedSharingPosts!.isEmpty);

    final snapshotPosts = snapshot.data;

    // 스트림에서 데이터를 받은 경우 항상 스트림 데이터 우선 사용 (빈 리스트 포함)
    // 초기 로딩 중(아직 한 번도 데이터 못 받은 경우)에만 캐시 폴백
    final bool hasReceivedStreamData = snapshot.hasData;
    final rawPosts = hasReceivedStreamData
        ? snapshotPosts!
        : (_cachedSharingPosts ?? const <Post>[]);

    // 스트림이 아직 삭제 이벤트를 받기 전에도 즉시 UI에서 제거
    final posts = _locallyDeletedPostIds.isEmpty
        ? rawPosts
        : rawPosts
            .where((p) => !_locallyDeletedPostIds.contains(p.id))
            .toList();

    // 스트림 데이터로 캐시 갱신 (삭제 반영을 위해 빈 리스트도 저장)
    if (snapshot.hasData) {
      _cachedSharingPosts = snapshotPosts;
      // 스트림이 최신 상태를 반영했으면 로컬 삭제 ID 정리
      if (_locallyDeletedPostIds.isNotEmpty) {
        final streamIds = snapshotPosts!.map((p) => p.id).toSet();
        _locallyDeletedPostIds.removeWhere((id) => !streamIds.contains(id));
      }
    }

    if (!_didAutoRefreshSharingCommentCounts && posts.isNotEmpty) {
      _didAutoRefreshSharingCommentCounts = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshCommentCountsForPosts(posts, silent: true);
      });
    }

    return _buildPostsList(
      posts: posts,
      isLoading: isLoading,
      isError: isError,
      scrollController: _sharingScrollController,
      listKey: 'board_sharing_list',
      bannerKey: 'board_banner_sharing',
      emptyBuilder: () => _buildSharingEmpty(),
    );
  }

  Widget _buildFeedTab(AsyncSnapshot<List<Post>> snapshot) {
    final isLoading = snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData &&
        _cachedFeedPosts == null;

    final isError = snapshot.hasError &&
        (_cachedFeedPosts == null || _cachedFeedPosts!.isEmpty);

    final snapshotPosts = snapshot.data;
    final bool hasFeedStreamData = snapshot.hasData;
    final sourcePosts = hasFeedStreamData
        ? snapshotPosts!
        : (_cachedFeedPosts ?? const <Post>[]);
    final posts = sourcePosts.where((p) => !isSharingPost(p)).toList();

    if (snapshot.hasData) {
      _cachedFeedPosts = posts;
    }

    if (!_didAutoRefreshFeedCommentCounts && posts.isNotEmpty) {
      _didAutoRefreshFeedCommentCounts = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshCommentCountsForPosts(posts, silent: true);
      });
    }

    return _buildFeedList(
      posts: posts,
      isLoading: isLoading,
      isError: isError,
    );
  }

  Widget _buildFeedList({
    required List<Post> posts,
    required bool isLoading,
    required bool isError,
  }) {
    final int bodyCount;
    if (isLoading) {
      bodyCount = 5;
    } else if (isError || posts.isEmpty) {
      bodyCount = 1;
    } else {
      bodyCount = posts.length;
    }

    return RefreshIndicator(
      color: AppColors.pointColor,
      backgroundColor: Colors.white,
      onRefresh: () async {
        if (!isLoading && !isError) {
          await _refreshCommentCountsForPosts(posts);
        } else {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) setState(() {});
        }
      },
      child: ListView.builder(
        key: const PageStorageKey('board_feed_list'),
        controller: _feedScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        cacheExtent: 1000,
        padding: const EdgeInsets.only(top: 4, bottom: 90),
        itemCount: 1 + bodyCount,
        itemBuilder: (context, index) {
          if (index == 0) {
            return const AdBannerWidget(
              key: ValueKey('board_banner_feed'),
              widgetId: 'board_banner_feed',
            );
          }

          if (isLoading) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _buildPostSkeleton(),
            );
          }

          if (isError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: _buildErrorWidget('데이터를 불러올 수 없습니다'),
            );
          }

          if (posts.isEmpty) {
            return _buildFeedEmpty();
          }

          final post = posts[index - 1];
          return _buildFeedPostCard(post);
        },
      ),
    );
  }

  Widget _buildPostsList({
    required List<Post> posts,
    required bool isLoading,
    required bool isError,
    required ScrollController scrollController,
    required String listKey,
    required String bannerKey,
    required Widget Function() emptyBuilder,
  }) {
    final int bodyCount;
    if (isLoading) {
      bodyCount = 5;
    } else if (isError || posts.isEmpty) {
      bodyCount = 1;
    } else {
      bodyCount = posts.length;
    }

    return RefreshIndicator(
      color: AppColors.pointColor,
      backgroundColor: Colors.white,
      onRefresh: () async {
        if (!isLoading && !isError) {
          await _refreshCommentCountsForPosts(posts);
        } else {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) setState(() {});
        }
      },
      child: ListView.builder(
        key: PageStorageKey(listKey),
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        cacheExtent: 1000,
        padding: const EdgeInsets.only(top: 4, bottom: 90),
        itemCount: 1 + bodyCount,
        itemBuilder: (context, index) {
          if (index == 0) {
            return AdBannerWidget(
              key: ValueKey(bannerKey),
              widgetId: bannerKey,
            );
          }

          if (isLoading) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _buildPostSkeleton(),
            );
          }

          if (isError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: _buildErrorWidget('데이터를 불러올 수 없습니다'),
            );
          }

          if (posts.isEmpty) {
            return emptyBuilder();
          }

          final postIndex = index - 1;
          final post = posts[postIndex];
          return _buildSharingPostCard(post);
        },
      ),
    );
  }

  Widget _buildSharingEmpty() {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.volunteer_activism_outlined,
              size: 64, color: Color(0xFF9CA3AF)),
          const SizedBox(height: 16),
          Text(
            isKo ? '아직 나눔이 없어요' : 'No sharing posts yet',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isKo ? '처음 나눔 글을 등록해보세요.' : 'Be the first to post a sharing item.',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSharingPostCard(Post post) {
    final thumbnailUrl = post.imageUrls.isNotEmpty ? post.imageUrls.first : '';
    final sharingLocation = post.sharingLocation.trim();
    final commentCount = _commentCountOverrides[post.id] ?? post.commentCount;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isLiked =
        currentUserId != null && post.likedBy.contains(currentUserId);
    final canOpenUniv = !post.schoolOnly ||
        post.userId == currentUserId ||
        context.watch<app_auth.AuthProvider>().isHanyangUser;
    final requiresGate = post.schoolOnly && !canOpenUniv;
    final showGate = requiresGate && _activeSharingGatePostId == post.id;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          if (requiresGate) {
            setState(() {
              _activeSharingGatePostId =
                  _activeSharingGatePostId == post.id ? null : post.id;
            });
            return;
          }
          _navigateToPostDetail(post);
        },
        child: SizedBox(
          height: 180,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildSharingThumbnail(
                        thumbnailUrl,
                        width: 144,
                        height: 170,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text(
                            post.title.trim().isNotEmpty
                                ? post.title.trim()
                                : _feedPostTitle(post),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                              height: 1.12,
                              letterSpacing: -0.4,
                            ),
                          ),
                          if (sharingLocation.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              sharingLocation,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF374151),
                                height: 1.15,
                              ),
                            ),
                          ],
                          const SizedBox(height: 5),
                          Text(
                            post.getFormattedTime(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF9CA3AF),
                              height: 1.15,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (post.schoolOnly) _buildUnivBadge(),
                              const Spacer(),
                              Flexible(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: _buildSharingMetrics(
                                    isLiked: isLiked,
                                    likes: post.likes,
                                    comments: commentCount,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(height: 1, color: const Color(0xFFE5E7EB)),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !showGate,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: showGate
                        ? _buildSharingGateOverlay(
                            key: ValueKey('sharing_gate_${post.id}'),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSharingThumbnail(
    String thumbnailUrl, {
    required double width,
    required double height,
  }) {
    return thumbnailUrl.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: thumbnailUrl,
            cacheManager: AppImageCacheManager.instance,
            memCacheWidth: 520,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) =>
                _buildSharingImageFallback(width: width, height: height),
          )
        : _buildSharingImageFallback(width: width, height: height);
  }

  Widget _buildSharingImageFallback({
    double width = 172,
    double height = 170,
  }) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFE5E7EB),
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Color(0xFF9CA3AF),
      ),
    );
  }

  Widget _buildUnivBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF244BFF),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text(
        'Univ.',
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _buildSharingMetrics({
    required bool isLiked,
    required int likes,
    required int comments,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 18,
            color: const Color(0xFF111827),
          ),
          const SizedBox(width: 3),
          Text(
            '$likes',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.chat_bubble_outline_rounded,
            size: 18,
            color: Color(0xFF111827),
          ),
          const SizedBox(width: 3),
          Text(
            '$comments',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSharingGateOverlay({Key? key}) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _activeSharingGatePostId = null),
      child: Container(
        color: Colors.black.withValues(alpha: 0.68),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isKo ? '한양메일 인증을 해주세요.' : 'Please verify your Hanyang email.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _openHanyangVerification,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF244BFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  isKo ? '인증하러 가기' : 'Verify now',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeedEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 120),
      child: AppEmptyState.noPosts(
        onCreatePost: _openCreateEntrySheet,
      ),
    );
  }

  Widget _buildFeedPostCard(Post post) {
    final thumbnailUrl = post.imageUrls.isNotEmpty ? post.imageUrls.first : '';
    final commentCount = _commentCountOverrides[post.id] ?? post.commentCount;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isLiked =
        currentUserId != null && post.likedBy.contains(currentUserId);
    final hasFriendVisibility =
        post.visibility != 'public' || post.visibleToCategoryIds.isNotEmpty;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _navigateToPostDetail(post),
        child: Container(
          height: 152,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: 130,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _feedPostTitle(post),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                          height: 1.2,
                          letterSpacing: -0.3,
                        ),
                      ),
                      _buildFeedMetaRow(
                        isLiked: isLiked,
                        likes: post.likes,
                        comments: commentCount,
                        timeText: post.getFormattedTime(context),
                        hasFriendVisibility: hasFriendVisibility,
                      ),
                    ],
                  ),
                ),
              ),
              if (thumbnailUrl.isNotEmpty) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: thumbnailUrl,
                    cacheManager: AppImageCacheManager.instance,
                    memCacheWidth: 360,
                    width: 112,
                    height: 112,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 112,
                      height: 112,
                      color: const Color(0xFFE5E7EB),
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeedMetaRow({
    required bool isLiked,
    required int likes,
    required int comments,
    required String timeText,
    required bool hasFriendVisibility,
  }) {
    const iconSize = 18.0;
    const countStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Color(0xFF111827),
      height: 1.0,
    );
    const metaStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Color(0xFF6B7280),
      height: 1.0,
    );
    const friendStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: Color(0xFFE85D2A),
      height: 1.0,
    );

    return SizedBox(
      height: 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildFlexibleMetric(
            icon: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              size: iconSize,
              color:
                  isLiked ? const Color(0xFFEF4444) : const Color(0xFF111827),
            ),
            text: '$likes',
            textStyle: countStyle,
            iconBoxSize: iconSize,
          ),
          const SizedBox(width: 5),
          _buildFlexibleMetric(
            icon: const Icon(
              Icons.chat_bubble_outline,
              size: iconSize,
              color: Color(0xFF111827),
            ),
            text: '$comments',
            textStyle: countStyle,
            iconBoxSize: iconSize,
          ),
          const SizedBox(width: 6),
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              timeText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: metaStyle,
            ),
          ),
          if (hasFriendVisibility) ...[
            const SizedBox(width: 8),
            Flexible(
              fit: FlexFit.loose,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.change_history,
                    size: 12,
                    color: Color(0xFFE85D2A),
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      '친구 공개',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: friendStyle,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFlexibleMetric({
    required Widget icon,
    required String text,
    required TextStyle textStyle,
    required double iconBoxSize,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 44),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: iconBoxSize,
              height: iconBoxSize,
              child: Center(child: icon),
            ),
            const SizedBox(width: 2),
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ],
        ),
      ),
    );
  }

  /// 게시글 상세 화면으로 이동
  void _navigateToPostDetail(Post post) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => PostDetailScreen(post: post)),
    );

    // 게시글이 삭제된 경우 즉시 로컬에서 제거 (실시간 스트림 갱신 전에도 목록 반영)
    if (result == true && mounted) {
      setState(() {
        if (isSharingPost(post)) {
          _locallyDeletedPostIds.add(post.id);
          _cachedSharingPosts =
              _cachedSharingPosts?.where((p) => p.id != post.id).toList();
        } else {
          _cachedFeedPosts =
              _cachedFeedPosts?.where((p) => p.id != post.id).toList();
        }
      });
    }
  }

  void _openCreatePost() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreatePostScreen(
          onPostCreated: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  void _openCreateSharingPost() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateSharingPostScreen(
          onPostCreated: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  void _openCreateSnackChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateSnackChatScreen(),
      ),
    );
  }

  Future<void> _openHanyangVerification() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const HanyangEmailVerificationScreen(
          returnOnSuccess: true,
        ),
      ),
    );
    if (mounted) {
      setState(() => _activeSharingGatePostId = null);
    }
  }

  String _feedPostTitle(Post post) {
    final title = post.title.trim();
    if (title.isNotEmpty) return title;
    final firstLine = post.content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    return firstLine.isNotEmpty ? firstLine : 'Untitled';
  }

  void _openCreateEntrySheet() {
    final isSharingTab = _tabController.index == 0;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final primaryTitle = isSharingTab
        ? (isKo ? '나눔 작성하기' : 'Create Sharing Post')
        : (isKo ? '피드 작성하기' : 'Create Feed Post');
    final primarySubtitle = isSharingTab
        ? (isKo
            ? '사진과 카테고리를 넣어 무료 나눔을 올려요.'
            : 'Add photos and a category to share for free.')
        : (isKo
            ? '사진과 내용을 넣어 새 피드를 올려요.'
            : 'Add photos and text to create a new feed post.');
    final snackChatTitle = isKo ? '스낵챗 만들기' : 'Create Snack Chat';
    final snackChatSubtitle = isKo
        ? '오늘 함께 이야기할 스낵챗을 만들어요.'
        : 'Create a Snack Chat to talk with others today.';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCreateEntryTile(
                  icon: Icons.volunteer_activism_outlined,
                  title: primaryTitle,
                  subtitle: primarySubtitle,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (isSharingTab) {
                      _openCreateSharingPost();
                    } else {
                      _openCreatePost();
                    }
                  },
                ),
                const Divider(height: 1),
                _buildCreateEntryTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: snackChatTitle,
                  subtitle: snackChatSubtitle,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openCreateSnackChat();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCreateEntryTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.pointColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.pointColor),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF111827),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 12,
          color: Color(0xFF6B7280),
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF9CA3AF),
      ),
      onTap: onTap,
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            '오류가 발생했습니다',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {});
            },
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }

  Widget _buildPostSkeleton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppSkeleton(
                width: 32,
                height: 32,
                borderRadius: BorderRadius.circular(16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeleton(
                      width: 100,
                      height: 14,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 4),
                    AppSkeleton(
                      width: 60,
                      height: 12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppSkeleton(
            width: double.infinity,
            height: 18,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          AppSkeleton(
            width: double.infinity,
            height: 14,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 6),
          AppSkeleton(
            width: 200,
            height: 14,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              AppSkeleton(
                width: 50,
                height: 12,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(width: 12),
              AppSkeleton(
                width: 50,
                height: 12,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
