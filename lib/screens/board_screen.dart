// lib/screens/board_screen.dart
// 게시판 화면 - 게시글 목록 표시 및 관리
// 검색, 필터링, 작성 기능 포함

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/post.dart';
import '../constants/app_constants.dart';
import '../services/post_service.dart';
import '../services/comment_service.dart';
import '../ui/widgets/app_fab.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/skeletons.dart';
import '../ui/widgets/optimized_post_card.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';
import '../widgets/ad_banner_widget.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> with SingleTickerProviderStateMixin {
  final PostService _postService = PostService();
  final CommentService _commentService = CommentService();
  late TabController _tabController;

  // 수동 새로고침 시 계산한 댓글 수 오버라이드 (postId -> count)
  final Map<String, int> _commentCountOverrides = {};
  bool _didAutoRefreshTodayCommentCounts = false;
  bool _didAutoRefreshAllCommentCounts = false;
  
  // "맨 위로" 버튼 노출 상태 (스크롤이 내려갔을 때만 표시)
  bool _showScrollToTop = false;
  static const double _scrollToTopShowOffset = 420; // 이 이상 내려가면 표시
  static const double _scrollToTopHideOffset = 140; // 이 이하로 올라오면 숨김 (히스테리시스)

  // 게시글 카드 외부 여백(첨부 이미지처럼 좌우 여백을 더 주고, 카드 간 간격도 안정적으로)
  static const EdgeInsets _boardPostCardMargin =
      EdgeInsets.symmetric(horizontal: 12, vertical: 2);
  // 카드 내부 패딩(기본 12 유지, 필요 시 여기서만 조정)
  static const EdgeInsets _boardPostCardContentPadding = EdgeInsets.all(12);
  
  // 스크롤 위치 복원을 위한 ScrollController들
  late final ScrollController _todayScrollController;
  late final ScrollController _allScrollController;
  bool _controllersInitialized = false;
  static const String _psTabIndexId = 'board.tabIndex.v1';
  static const String _psTodayOffsetId = 'board.todayScrollOffset.v1';
  static const String _psAllOffsetId = 'board.allScrollOffset.v1';
  
  // 캐시된 데이터를 저장하여 부드러운 전환 구현
  List<Post>? _cachedTodayPosts;
  List<Post>? _cachedAllPosts;
  bool _isInitialLoad = true;
  
  // AppLocalizations 안전 호출 헬퍼
  String _safeL10n(String Function(AppLocalizations) getter, String fallback) {
    try {
      final l10n = AppLocalizations.of(context);
      return l10n != null ? getter(l10n) : fallback;
    } catch (e) {
      return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    
    // 컨트롤러 초기화/상태 복원은 didChangeDependencies에서 처리
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
    final savedTodayOffset =
        (storage.readState(context, identifier: _psTodayOffsetId) as double?) ??
            0.0;
    final savedAllOffset =
        (storage.readState(context, identifier: _psAllOffsetId) as double?) ??
            0.0;

    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: savedTabIndex.clamp(0, 1),
    );
    _todayScrollController = ScrollController(
      initialScrollOffset: savedTodayOffset < 0 ? 0 : savedTodayOffset,
    );
    _allScrollController = ScrollController(
      initialScrollOffset: savedAllOffset < 0 ? 0 : savedAllOffset,
    );

    // 스크롤 상태 감지 (Today/All 탭 모두)
    _todayScrollController.addListener(_handleScrollChanged);
    _allScrollController.addListener(_handleScrollChanged);
    _tabController.addListener(_handleTabChanged);

    _controllersInitialized = true;

    // 첫 프레임 이후 스크롤 "최대값 초과" 방지용 보정
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
    if (_todayScrollController.hasClients) {
      storage.writeState(
        context,
        _todayScrollController.offset,
        identifier: _psTodayOffsetId,
      );
    }
    if (_allScrollController.hasClients) {
      storage.writeState(
        context,
        _allScrollController.offset,
        identifier: _psAllOffsetId,
      );
    }
  }

  void _clampScrollOffsetsIfNeeded() {
    // 데이터/레이아웃 변화로 saved offset이 maxScrollExtent보다 클 수 있어
    // attach 이후 안전하게 clamp한다.
    if (_todayScrollController.hasClients) {
      final pos = _todayScrollController.position;
      final target = _todayScrollController.offset.clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      );
      if (target != _todayScrollController.offset) {
        _todayScrollController.jumpTo(target);
      }
    }
    if (_allScrollController.hasClients) {
      final pos = _allScrollController.position;
      final target = _allScrollController.offset.clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      );
      if (target != _allScrollController.offset) {
        _allScrollController.jumpTo(target);
      }
    }
  }

  /// 캐시된 데이터를 먼저 로드하여 즉시 화면에 표시
  Future<void> _loadCachedData() async {
    try {
      final cachedPosts = await _postService.getCachedPosts();
      if (!mounted) return;
      
      if (cachedPosts.isNotEmpty) {
        setState(() {
          _cachedAllPosts = cachedPosts;
          
          // 오늘 날짜의 게시글만 필터링
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          _cachedTodayPosts = cachedPosts.where((post) {
            final postDate = DateTime(
              post.createdAt.year,
              post.createdAt.month,
              post.createdAt.day,
            );
            return postDate.isAtSameMomentAs(today);
          }).toList();
        });
        Logger.log('✅ 캐시된 게시글 로드 완료: ${cachedPosts.length}개');
      }
    } catch (e) {
      Logger.error('캐시 로드 오류: $e');
    }
  }

  /// 댓글 수 재집계 - 백그라운드에서 조용히 처리 (setState 없이)
  Future<void> _refreshCommentCountsForPosts(List<Post> posts, {bool silent = false}) async {
    // 너무 많은 카드에 대해 매번 집계하면 느려질 수 있어, 상위 N개만 갱신
    const maxTargets = 40;
    final ids = posts.map((p) => p.id).toSet().take(maxTargets).toList();
    if (ids.isEmpty) return;

    final counts = await _commentService.fetchCommentCountsForPostIds(ids);
    if (!mounted) return;
    
    // silent 모드일 때는 setState 없이 데이터만 업데이트
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
      // 마지막 상태 저장
      try {
        _persistBoardState();
      } catch (_) {}

      _tabController.removeListener(_handleTabChanged);
      _todayScrollController.removeListener(_handleScrollChanged);
      _allScrollController.removeListener(_handleScrollChanged);
      _tabController.dispose();
      _todayScrollController.dispose();
      _allScrollController.dispose();
    }
    Logger.log('✅ BoardScreen dispose 완료');
    super.dispose();
  }

  ScrollController get _activeScrollController {
    // index 0: Today, index 1: All
    return _tabController.index == 0 ? _todayScrollController : _allScrollController;
  }

  void _handleTabChanged() {
    // 탭 전환 시 현재 탭의 스크롤 위치에 맞춰 버튼 노출 상태 동기화
    if (!mounted) return;
    if (_tabController.indexIsChanging) return;
    _persistBoardState(persistOffsets: false);
    _syncScrollToTopVisibility();
  }

  void _handleScrollChanged() {
    if (!mounted) return;
    _persistBoardState(persistOffsets: true);
    _syncScrollToTopVisibility();
  }

  void _syncScrollToTopVisibility() {
    final controller = _activeScrollController;
    if (!controller.hasClients) return;

    final offset = controller.offset;
    final shouldShow =
        _showScrollToTop ? offset > _scrollToTopHideOffset : offset > _scrollToTopShowOffset;

    if (shouldShow != _showScrollToTop) {
      setState(() => _showScrollToTop = shouldShow);
    }
  }

  void _scrollToTop() {
    final controller = _activeScrollController;
    if (!controller.hasClients) return;
    controller.animateTo(
      controller.position.minScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildScrollToTopOverlay() {
    // 하단 탭바/안전영역 고려
    final bottom = MediaQuery.of(context).padding.bottom + 14;

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: IgnorePointer(
        ignoring: !_showScrollToTop,
        child: AnimatedSlide(
          offset: _showScrollToTop ? Offset.zero : const Offset(0, 0.35),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _showScrollToTop ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: Center(
              child: Semantics(
                button: true,
                label: '맨 위로 이동',
                child: Material(
                  color: const Color(0xFFF3F4F6),
                  elevation: 2,
                  shadowColor: const Color(0x14000000),
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    onTap: _scrollToTop,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: 22,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEBEBEB), // 연한 회색 배경 (L: 92%, 친구 카드와 6% 명도 차이)
      body: Stack(
        children: [
          Column(
            children: [
              // 탭 바
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppColors.pointColor, // 위필링 시그니처 파란색으로 통일
                  unselectedLabelColor: Colors.grey[600],
                  indicatorColor: AppColors.pointColor, // 위필링 시그니처 파란색으로 통일
                  labelStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: const [
                    Tab(text: 'Today'),
                    Tab(text: 'All'),
                  ],
                ),
              ),
              // 게시글 목록 (광고 배너가 스크롤 영역 안으로 이동)
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // 오늘 탭
                    _buildTodayPostsTab(),
                    // 전체 탭
                    _buildAllPostsTab(),
                  ],
                ),
              ),
            ],
          ),
          _buildScrollToTopOverlay(),
        ],
      ),
      floatingActionButton: AppFab.write(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => CreatePostScreen(
                    onPostCreated: () {
                      // 게시글이 작성되면 화면 새로고침 (스트림이므로 자동으로 업데이트됨)
                      setState(() {});
                    },
                  ),
            ),
          );
        },
        heroTag: 'board_write_fab',
      ),
    );
  }

  /// 오늘 게시글 탭
  Widget _buildTodayPostsTab() {
    return StreamBuilder<List<Post>>(
      stream: _postService.getPostsStream(),
      builder: (context, snapshot) {
        // 🎯 핵심 개선: 데이터가 있으면 로딩 화면을 보여주지 않음
        // 초기 로딩 시에만 스켈레톤 UI 표시
        final bool isLoading = snapshot.connectionState == ConnectionState.waiting && 
                               !snapshot.hasData && 
                               _cachedTodayPosts == null;
        
        if (isLoading) {
          return _buildTodayLoadingView();
        }

        // 에러 발생 시 - 캐시된 데이터가 있으면 그것을 사용
        if (snapshot.hasError) {
          if (_cachedTodayPosts != null && _cachedTodayPosts!.isNotEmpty) {
            Logger.log('⚠️ 스트림 에러 발생, 캐시된 데이터 사용');
            return _buildTodayPostsView(_cachedTodayPosts!);
          }
          return _buildTodayErrorView();
        }

        // 최신 데이터 또는 캐시된 데이터 사용
        List<Post> posts = snapshot.data ?? _cachedAllPosts ?? [];

        // 오늘 날짜의 게시글만 필터링
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final todayPosts = posts.where((post) {
          final postDate = DateTime(
            post.createdAt.year,
            post.createdAt.month,
            post.createdAt.day,
          );
          return postDate.isAtSameMomentAs(today);
        }).toList();

        // 캐시 업데이트 (다음 로딩을 위해)
        if (snapshot.hasData && todayPosts.isNotEmpty) {
          _cachedTodayPosts = todayPosts;
          
          // 초기 로드 완료 표시
          if (_isInitialLoad) {
            _isInitialLoad = false;
            Logger.log('✅ 초기 데이터 로드 완료');
          }
        }

        // 앱 첫 진입 시 자동으로 댓글 수 재집계 (백그라운드에서 조용히)
        if (!_didAutoRefreshTodayCommentCounts && todayPosts.isNotEmpty) {
          _didAutoRefreshTodayCommentCounts = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // silent 모드로 setState 없이 처리
            _refreshCommentCountsForPosts(todayPosts, silent: true);
          });
        }

        // 빈 상태
        if (todayPosts.isEmpty) {
          return _buildTodayEmptyView();
        }

        // 게시글 목록 표시
        return _buildTodayPostsView(todayPosts);
      },
    );
  }
  
  // 로딩 뷰 (AdBanner + 스켈레톤)
  Widget _buildTodayLoadingView() {
    return RefreshIndicator(
      color: AppColors.pointColor,
      backgroundColor: Colors.white,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
      },
      child: ListView(
        controller: _todayScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          AdBannerWidget(
            key: ValueKey('board_banner_today'),
            widgetId: 'board_banner_today',
          ),
          ...List.generate(5, (index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _buildPostSkeleton(),
          )),
        ],
      ),
    );
  }
  
  // 에러 뷰 (AdBanner + 에러)
  Widget _buildTodayErrorView() {
    return RefreshIndicator(
      color: AppColors.pointColor,
      backgroundColor: Colors.white,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
      },
      child: ListView(
        controller: _todayScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          AdBannerWidget(
            key: ValueKey('board_banner_today'),
            widgetId: 'board_banner_today',
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildErrorWidget('데이터를 불러올 수 없습니다'),
          ),
        ],
      ),
    );
  }
  
  // 빈 상태 뷰 (AdBanner + Empty State)
  Widget _buildTodayEmptyView() {
    return RefreshIndicator(
      color: AppColors.pointColor,
      backgroundColor: Colors.white,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
      },
      child: ListView(
        controller: _todayScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          AdBannerWidget(
            key: ValueKey('board_banner_today'),
            widgetId: 'board_banner_today',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 120),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _safeL10n((l10n) => l10n.yourStoryMatters, '당신의 이야기가 중요합니다'),
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  _safeL10n((l10n) => l10n.shareYourMoments, '순간을 공유해보세요'),
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
          );
        }

  // 게시글 목록 뷰 (AdBanner + 게시글들)
  Widget _buildTodayPostsView(List<Post> todayPosts) {
        return RefreshIndicator(
      color: AppColors.pointColor,
      backgroundColor: Colors.white,
          onRefresh: () async {
        await _refreshCommentCountsForPosts(todayPosts);
          },
          child: ListView.builder(
            key: const PageStorageKey('board_today_list'),
            controller: _todayScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: todayPosts.length + 1, // AdBanner + 게시글들
            itemBuilder: (context, index) {
          // 첫 번째는 AdBanner
          if (index == 0) {
            return AdBannerWidget(
              key: ValueKey('board_banner_today'),
              widgetId: 'board_banner_today',
            );
          }
          
          // 게시글 표시
          final postIndex = index - 1;
          final post = todayPosts[postIndex];
              return OptimizedPostCard(
                key: ValueKey(post.id),
                post: post,
            index: postIndex,
                onTap: () => _navigateToPostDetail(post),
            externalCommentCountOverride: _commentCountOverrides[post.id],
            preloadImage: postIndex < 3,
            margin: _boardPostCardMargin,
            contentPadding: _boardPostCardContentPadding,
              );
            },
          ),
    );
  }


  /// 전체 게시글 탭
  Widget _buildAllPostsTab() {
    return StreamBuilder<List<Post>>(
      stream: _postService.getPostsStream(),
      builder: (context, snapshot) {
        // 🎯 핵심 개선: 데이터가 있으면 로딩 화면을 보여주지 않음
        // 초기 로딩 시에만 스켈레톤 UI 표시
        final bool isLoading = snapshot.connectionState == ConnectionState.waiting && 
                               !snapshot.hasData && 
                               _cachedAllPosts == null;
        
        if (isLoading) {
          return _buildAllLoadingView();
        }

        // 에러 발생 시 - 캐시된 데이터가 있으면 그것을 사용
        if (snapshot.hasError) {
          if (_cachedAllPosts != null && _cachedAllPosts!.isNotEmpty) {
            Logger.log('⚠️ 스트림 에러 발생, 캐시된 데이터 사용');
            return _buildAllPostsView(_cachedAllPosts!);
          }
          return _buildAllErrorView();
        }

        // 최신 데이터 또는 캐시된 데이터 사용
        List<Post> posts = snapshot.data ?? _cachedAllPosts ?? [];

        // 캐시 업데이트 (다음 로딩을 위해)
        if (snapshot.hasData && posts.isNotEmpty) {
          _cachedAllPosts = posts;
        }

        // 앱 첫 진입 시 자동으로 댓글 수 재집계 (백그라운드에서 조용히)
        if (!_didAutoRefreshAllCommentCounts && posts.isNotEmpty) {
          _didAutoRefreshAllCommentCounts = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // silent 모드로 setState 없이 처리
            _refreshCommentCountsForPosts(posts, silent: true);
          });
        }

        // 빈 상태
        if (posts.isEmpty) {
          return _buildAllEmptyView();
        }

        // 게시글 목록 표시
        return _buildAllPostsView(posts);
      },
    );
  }
  
  // 전체 탭 - 로딩 뷰
  Widget _buildAllLoadingView() {
    return RefreshIndicator(
      color: AppColors.pointColor,
      backgroundColor: Colors.white,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
      },
      child: ListView(
        controller: _allScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          AdBannerWidget(
            key: ValueKey('board_banner_all'),
            widgetId: 'board_banner_all',
          ),
          ...List.generate(5, (index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _buildPostSkeleton(),
          )),
        ],
      ),
    );
  }
  
  // 전체 탭 - 에러 뷰
  Widget _buildAllErrorView() {
    return RefreshIndicator(
      color: AppColors.pointColor,
      backgroundColor: Colors.white,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
      },
      child: ListView(
        controller: _allScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          AdBannerWidget(
            key: ValueKey('board_banner_all'),
            widgetId: 'board_banner_all',
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildErrorWidget('데이터를 불러올 수 없습니다'),
          ),
        ],
      ),
    );
  }
  
  // 전체 탭 - 빈 상태 뷰
  Widget _buildAllEmptyView() {
    return RefreshIndicator(
      color: AppColors.pointColor,
      backgroundColor: Colors.white,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
      },
      child: ListView(
        controller: _allScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          AdBannerWidget(
            key: ValueKey('board_banner_all'),
            widgetId: 'board_banner_all',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 120),
            child: AppEmptyState.noPosts(
              onCreatePost: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreatePostScreen(
                      onPostCreated: () {
                        setState(() {});
                      },
                    ),
                  ),
                );
              },
                  ),
          ),
        ],
      ),
            );
          }
  
  // 전체 탭 - 게시글 목록 뷰
  Widget _buildAllPostsView(List<Post> posts) {
    final groupedPosts = _groupPostsByDate(posts);

        return RefreshIndicator(
      color: AppColors.pointColor,
      backgroundColor: Colors.white,
          onRefresh: () async {
        await _refreshCommentCountsForPosts(posts);
          },
      child: ListView.builder(
        key: const PageStorageKey('board_all_list'),
        controller: _allScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _calculateAllItemCount(groupedPosts),
        itemBuilder: (context, index) {
          if (index == 0) {
            return AdBannerWidget(
              key: ValueKey('board_banner_all'),
              widgetId: 'board_banner_all',
            );
          }
          return _buildAllGroupedItem(groupedPosts, index - 1);
        },
      ),
    );
  }
  
  int _calculateAllItemCount(List<Map<String, dynamic>> groupedPosts) {
    int totalItems = 1; // AdBanner
    for (var group in groupedPosts) {
      totalItems += 1; // 날짜 헤더
      final groupPosts = group['posts'] as List<Post>;
      totalItems += groupPosts.length; // 게시글들
    }
    return totalItems;
  }
  
  Widget _buildAllGroupedItem(List<Map<String, dynamic>> groupedPosts, int adjustedIndex) {
    int currentIndex = 0;
    
    for (var group in groupedPosts) {
      final dateLabel = group['dateLabel'] as String;
      final groupPosts = group['posts'] as List<Post>;
      
      // 날짜 헤더
      if (currentIndex == adjustedIndex) {
        return _buildDateHeader(dateLabel);
      }
      currentIndex++;
      
      // 게시글들
      for (int i = 0; i < groupPosts.length; i++) {
        if (currentIndex == adjustedIndex) {
          return OptimizedPostCard(
            key: ValueKey(groupPosts[i].id),
            post: groupPosts[i],
            index: i,
            onTap: () => _navigateToPostDetail(groupPosts[i]),
            externalCommentCountOverride: _commentCountOverrides[groupPosts[i].id],
            preloadImage: i < 3,
            margin: _boardPostCardMargin,
            contentPadding: _boardPostCardContentPadding,
    );
  }
        currentIndex++;
      }
    }
    
    return const SizedBox.shrink();
  }


  /// 게시글 상세 화면으로 이동
  void _navigateToPostDetail(Post post) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => PostDetailScreen(post: post)),
    );

    // StreamBuilder가 자동으로 갱신하므로 setState 불필요
    // setState를 호출하면 로딩 화면이 다시 보여 스크롤이 초기화될 수 있음
  }

  /// 에러 위젯 빌드
  Widget _buildErrorWidget(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
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
              setState(() {}); // 새로고침
            },
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }


  /// 날짜별로 게시글 그룹화
  List<Map<String, dynamic>> _groupPostsByDate(List<Post> posts) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
    
    final Map<String, List<Post>> groups = {
      'today': [],
      'yesterday': [],
      'thisWeek': [],
      'previous': [],
    };
    
    for (final post in posts) {
      final postDate = DateTime(
        post.createdAt.year,
        post.createdAt.month,
        post.createdAt.day,
      );
      
      if (postDate.isAtSameMomentAs(today)) {
        groups['today']!.add(post);
      } else if (postDate.isAtSameMomentAs(yesterday)) {
        groups['yesterday']!.add(post);
      } else if (postDate.isAfter(thisWeekStart.subtract(const Duration(days: 1))) && 
                 postDate.isBefore(yesterday)) {
        groups['thisWeek']!.add(post);
      } else {
        groups['previous']!.add(post);
      }
    }
    
    // 비어있지 않은 그룹만 반환
    return groups.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => {
              'dateLabel': entry.key,
              'posts': entry.value,
            })
        .toList();
  }

  /// 날짜 헤더 빌드
  Widget _buildDateHeader(String dateLabel) {
    // All 탭에서 날짜 구분(어제/이전 등) 텍스트 라벨을 표시하지 않음
    return const SizedBox.shrink();
  }

  /// 전체 목록에서의 인덱스 찾기
  int _getGlobalIndex(List<Post> allPosts, Post targetPost) {
    return allPosts.indexWhere((post) => post.id == targetPost.id);
  }

  /// 게시글 카드 스켈레톤 (로딩 시 표시)
  Widget _buildPostSkeleton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더: 작성자 정보
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
          
          // 제목
          AppSkeleton(
            width: double.infinity,
            height: 18,
            borderRadius: BorderRadius.circular(4),
          ),
          
          const SizedBox(height: 8),
          
          // 내용 (2줄)
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
          
          // 하단: 좋아요, 댓글 수
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
