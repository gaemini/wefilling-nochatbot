// lib/screens/board_screen.dart
// 게시판 화면 - 게시글 목록 표시 및 관리
// 검색, 필터링, 작성 기능 포함

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/post.dart';
import '../models/post_category.dart';
import '../models/meetup.dart';
import '../constants/app_constants.dart';
import '../services/post_service.dart';
import '../services/comment_service.dart';
import '../services/meetup_service.dart';
import '../services/content_filter_service.dart';
import '../ui/widgets/app_fab.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/skeletons.dart';
import '../ui/widgets/optimized_post_card.dart';
import '../ui/widgets/board_meetup_card.dart';
import '../ui/widgets/post_category_explorer.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../snapshot/snapshot_today_section.dart';
import 'create_post_screen.dart';
import 'create_snapshot_screen.dart';
import 'post_detail_screen.dart';
import 'post_category_feed_screen.dart';
import 'meetup_detail_screen.dart';
import '../widgets/ad_banner_widget.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => BoardScreenState();
}

class _CreateMenuRow extends StatelessWidget {
  const _CreateMenuRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 23, color: const Color(0xFF475467)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12.5,
                        height: 1.3,
                        color: Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                size: 21,
                color: Color(0xFF98A2B3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BoardScreenState extends State<BoardScreen> {
  final PostService _postService = PostService();
  final CommentService _commentService = CommentService();
  final MeetupService _meetupService = MeetupService();
  Timer? _midnightTimer;
  late final Stream<List<Meetup>> _todayMeetupsStream;

  List<Meetup>? _cachedTodayMeetups;

  // 수동 새로고침 시 계산한 댓글 수 오버라이드 (postId -> count)
  final Map<String, int> _commentCountOverrides = {};
  bool _didAutoRefreshTodayCommentCounts = false;

  // 일반 게시물은 그림자 대신 콘텐츠 여백과 divider로 구분한다.
  static const EdgeInsets _boardPostCardMargin = EdgeInsets.zero;

  EdgeInsets get _boardPostCardContentPadding {
    final horizontal = context.rs(18).clamp(14.0, 20.0).toDouble();
    final top = context.rs(11).clamp(9.0, 12.0).toDouble();
    final bottom = context.rs(13).clamp(11.0, 14.0).toDouble();
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  double get _sectionHorizontalPadding =>
      context.rs(16).clamp(12.0, 18.0).toDouble();

  double get _sectionTitleSize => context.rf(14.5).clamp(13.5, 15.0).toDouble();

  double get _sectionBodySize => context.rf(13).clamp(12.0, 13.5).toDouble();

  // 스크롤 위치 복원을 위한 컨트롤러. All 컨트롤러는 이전 버전의
  // PageStorage 키를 안전하게 정리하기 위해 당분간 유지한다.
  late final ScrollController _todayScrollController;
  late final ScrollController _allScrollController;
  bool _controllersInitialized = false;
  static const String _psTodayOffsetId = 'board.todayScrollOffset.v1';
  static const String _psAllOffsetId = 'board.allScrollOffset.v1';

  // 캐시된 데이터를 저장하여 부드러운 전환 구현
  List<Post>? _cachedTodayPosts;
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

  DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isPostInToday(Post post) {
    final local = post.createdAt.toLocal();
    return !local.isBefore(_startOfToday());
  }

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    _scheduleMidnightRefresh();
    // Today 밋업 섹션은 현재 사용자의 공개 범위 안에서:
    // - 오늘 생성된 모임
    // - 약속 날짜가 오늘인 모임
    // 만 노출한다. (공개 범위 필터링은 MeetupService에서 강제)
    _todayMeetupsStream = _meetupService.getTodayTabMeetups();

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
    final savedTodayOffset =
        (storage.readState(context, identifier: _psTodayOffsetId) as double?) ??
            0.0;
    final savedAllOffset =
        (storage.readState(context, identifier: _psAllOffsetId) as double?) ??
            0.0;
    _todayScrollController = ScrollController(
      initialScrollOffset: savedTodayOffset < 0 ? 0 : savedTodayOffset,
    );
    _allScrollController = ScrollController(
      initialScrollOffset: savedAllOffset < 0 ? 0 : savedAllOffset,
    );

    // 피드 스크롤 위치를 보존한다.
    _todayScrollController.addListener(_handleScrollChanged);
    _allScrollController.addListener(_handleScrollChanged);

    _controllersInitialized = true;

    // 첫 프레임 이후 스크롤 "최대값 초과" 방지용 보정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _clampScrollOffsetsIfNeeded();
    });
  }

  void _persistBoardState({bool persistOffsets = true}) {
    final storage = PageStorage.of(context);
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
      // 차단 목록을 먼저 로드하여 flickering 방지
      await ContentFilterService.preloadBlockLists();

      final cachedPosts = await _postService.getCachedPosts();
      if (!mounted) return;

      if (cachedPosts.isNotEmpty) {
        setState(() {
          // Today 캐시는 기존 정책을 유지합니다. All은 카테고리 탐색 화면입니다.
          _cachedTodayPosts = cachedPosts.where(_isPostInToday).toList();
        });
        Logger.log('✅ 캐시된 게시글 로드 완료: ${cachedPosts.length}개');
      }
    } catch (e) {
      Logger.error('캐시 로드 오류: $e');
    }
  }

  /// 댓글 수 재집계 - 백그라운드에서 조용히 처리 (setState 없이)
  Future<void> _refreshCommentCountsForPosts(List<Post> posts,
      {bool silent = false}) async {
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
    _midnightTimer?.cancel();
    if (_controllersInitialized) {
      // 마지막 상태 저장
      try {
        _persistBoardState();
      } catch (_) {}

      _todayScrollController.removeListener(_handleScrollChanged);
      _allScrollController.removeListener(_handleScrollChanged);
      _todayScrollController.dispose();
      _allScrollController.dispose();
    }
    Logger.log('✅ BoardScreen dispose 완료');
    super.dispose();
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final startOfTomorrow =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final delay = startOfTomorrow.difference(now) + const Duration(seconds: 1);
    _midnightTimer = Timer(delay, () async {
      if (!mounted) return;
      // 날짜가 넘어가면 Today/All 분리가 바뀌므로 캐시를 갱신하고 화면을 리빌드
      await _loadCachedData();
      if (!mounted) return;
      setState(() {
        // 댓글 자동 리프레시 플래그는 날짜별로 다시 계산될 수 있게 초기화
        _didAutoRefreshTodayCommentCounts = false;
      });
      _scheduleMidnightRefresh();
    });
  }

  Future<void> _navigateToMeetupDetail(Meetup meetup) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final kicked = await _meetupService.isUserKickedFromMeetup(
        meetupId: meetup.id,
        userId: user.uid,
      );
      if (!mounted) return;
      if (kicked) {
        AppSnackBar.show(
          context,
          message: '죄송합니다. 모임에 참여할 수 없습니다',
          type: AppSnackBarType.error,
        );
        return;
      }
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MeetupDetailScreen(
          meetup: meetup,
          meetupId: meetup.id,
          onMeetupDeleted: () => setState(() {}),
        ),
      ),
    );

    // 상세 화면에서 참여 상태가 바뀔 수 있으니 캐시를 비워 재조회
    if (mounted) setState(() {});
  }

  ScrollController get _activeScrollController {
    return _todayScrollController;
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
      backgroundColor: Colors.white,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SizedBox(
            width: double.infinity,
            child: StreamBuilder<List<Post>>(
              stream: _postService.getPostsStream(),
              builder: (context, postSnap) {
                return _buildTodayPostsTab(postSnap);
              },
            ),
          ),
        ),
      ),
      floatingActionButton: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: AppFab.write(
          onPressed: _openCreateMenu,
          heroTag: 'board_write_fab',
        ),
      ),
    );
  }

  /// 오늘 게시글 탭 (posts 스트림은 build()에서 1회 구독)
  Widget _buildTodayPostsTab(AsyncSnapshot<List<Post>> snapshot) {
    final bool isPostsLoading =
        snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData &&
            _cachedTodayPosts == null;

    final bool isPostsError = snapshot.hasError &&
        (_cachedTodayPosts == null || _cachedTodayPosts!.isEmpty);

    final sourcePosts = snapshot.data ?? _cachedTodayPosts ?? const <Post>[];
    final todayPosts = sourcePosts.where(_isPostInToday).toList();

    if (snapshot.hasData) {
      _cachedTodayPosts = todayPosts;
      if (_isInitialLoad) _isInitialLoad = false;
    }

    if (!_didAutoRefreshTodayCommentCounts && todayPosts.isNotEmpty) {
      _didAutoRefreshTodayCommentCounts = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshCommentCountsForPosts(todayPosts, silent: true);
      });
    }

    return _buildTodayUnifiedList(
      todayPosts: todayPosts,
      isPostsLoading: isPostsLoading,
      isPostsError: isPostsError,
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
        padding: const EdgeInsets.only(top: 4, bottom: 90),
        children: [
          AdBannerWidget(
            key: ValueKey('board_banner_today'),
            widgetId: 'board_banner_today',
          ),
          ...List.generate(
              5,
              (index) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        padding: const EdgeInsets.only(top: 4, bottom: 90),
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

  // NOTE: Today 탭은 "오늘의 모임 + 오늘의 게시글" 섹션이 항상 존재하므로
  // 기존 단일 EmptyView는 더 이상 사용하지 않습니다(미사용 경고 방지).

  Widget _buildTodaySectionHeader({
    required IconData icon,
    required String title,
    bool isLoading = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final horizontal = _sectionHorizontalPadding;
    final iconSize = context.ri(18).clamp(17.0, 19.0).toDouble();
    final gap = context.rs(7).clamp(6.0, 8.0).toDouble();

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: EdgeInsets.fromLTRB(horizontal, 6, horizontal, 4),
        child: Row(
          children: [
            Icon(icon, size: iconSize, color: const Color(0xFF111827)),
            SizedBox(width: gap),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: _sectionTitleSize,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827),
                ),
              ),
            ),
            if (isLoading) SizedBox(width: gap),
            if (isLoading)
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 12),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF344054),
                  minimumSize: const Size(44, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: context.rf(12.5).clamp(12.0, 13.0).toDouble(),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(actionLabel),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right_rounded, size: 17),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTodaySectionMessage(
    String message, {
    double bottom = 10,
  }) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.35,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _sectionHorizontalPadding,
          0,
          _sectionHorizontalPadding,
          bottom,
        ),
        child: Text(
          message,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: _sectionBodySize,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF6B7280),
            height: 1.35,
          ),
        ),
      ),
    );
  }

  // 게시글 목록 뷰 (AdBanner + 게시글들)
  Widget _buildTodayPostsView(List<Post> todayPosts) {
    return StreamBuilder<List<Meetup>>(
      stream: _todayMeetupsStream,
      builder: (context, meetupSnapshot) {
        final todayMeetupsTitle = _safeL10n(
          (l) => l.todayMeetupsSectionTitle,
          '오늘의 밋업',
        );
        final todayPostsTitle = _safeL10n(
          (l) => l.todayPostsSectionTitle,
          '오늘의 게시글',
        );
        final noTodayMeetupsText = _safeL10n(
          (l) => l.todayNoMeetups,
          '오늘 올라온 밋업이 없어요.',
        );
        final noTodayPostsText = _safeL10n(
          (l) => l.todayNoPosts,
          '오늘 올라온 게시글이 없어요.',
        );

        final bool isMeetupsLoading =
            meetupSnapshot.connectionState == ConnectionState.waiting &&
                !meetupSnapshot.hasData &&
                _cachedTodayMeetups == null;

        // 공개 대상이 바뀌어 빈 목록이 도착했을 때 이전 카드를 유지하면 비대상자가
        // 카드와 참여 버튼을 계속 볼 수 있습니다. 명시적인 스트림 결과는 빈 목록도
        // 즉시 반영하고, 캐시는 아직 첫 결과가 오지 않은 동안에만 사용합니다.
        if (meetupSnapshot.hasData) {
          final incoming = meetupSnapshot.data ?? const <Meetup>[];
          _cachedTodayMeetups = incoming;
        }
        final todayMeetups =
            meetupSnapshot.data ?? _cachedTodayMeetups ?? const <Meetup>[];

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
            cacheExtent: 1000,
            padding: const EdgeInsets.only(top: 4, bottom: 90),
            itemCount: 1 + // AdBanner
                1 + // meetups header
                (isMeetupsLoading
                    ? 2
                    : (todayMeetups.isNotEmpty
                        ? todayMeetups.length
                        : 1)) + // meetups skeleton or meetups or empty
                1 + // posts header
                (todayPosts.isNotEmpty
                    ? todayPosts.length
                    : 1), // posts or empty
            itemBuilder: (context, index) {
              var i = index;

              // 0) AdBanner
              if (i == 0) {
                return AdBannerWidget(
                  key: ValueKey('board_banner_today'),
                  widgetId: 'board_banner_today',
                );
              }
              i -= 1;

              // 1) Meetups header
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.event_available_rounded,
                          size: 18, color: Color(0xFF111827)),
                      const SizedBox(width: 8),
                      Text(
                        todayMeetupsTitle,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isMeetupsLoading)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Text(
                          '${todayMeetups.length}',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                    ],
                  ),
                );
              }
              i -= 1;

              // 2) Meetups list or empty
              final meetupsCount = isMeetupsLoading
                  ? 2
                  : (todayMeetups.isNotEmpty ? todayMeetups.length : 1);
              if (i < meetupsCount) {
                if (isMeetupsLoading) {
                  // 로딩 중에도 카드 자리(스켈레톤)를 확보해서 레이아웃 점프를 줄인다.
                  return Padding(
                    padding: _boardPostCardMargin,
                    child: _buildMeetupSkeletonCard(),
                  );
                }
                if (todayMeetups.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      noTodayMeetupsText,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  );
                }

                final meetup = todayMeetups[i];
                return Padding(
                  padding: _boardPostCardMargin,
                  child: StreamBuilder<int>(
                    stream: _meetupService.participantCountStream(
                      meetup.id,
                      fallback: meetup.currentParticipants,
                    ),
                    builder: (context, countSnap) {
                      final count =
                          countSnap.data ?? meetup.currentParticipants;
                      return BoardMeetupCard(
                        key: ValueKey('board_meetup_${meetup.id}'),
                        meetup: meetup,
                        currentParticipants: count,
                        onTap: () => _navigateToMeetupDetail(meetup),
                      );
                    },
                  ),
                );
              }
              i -= meetupsCount;

              // 3) Posts header
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.article_rounded,
                          size: 18, color: Color(0xFF111827)),
                      const SizedBox(width: 8),
                      Text(
                        todayPostsTitle,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ],
                  ),
                );
              }
              i -= 1;

              // 4) Posts list or empty
              if (todayPosts.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Text(
                    noTodayPostsText,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                );
              }

              final postIndex = i;
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
      },
    );
  }

  Widget _buildMeetupSkeletonCard() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 9, 16, 10),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Column(
              children: [
                AppTextSkeleton(width: 28, height: 9),
                SizedBox(height: 4),
                AppTextSkeleton(width: 24, height: 22),
                SizedBox(height: 5),
                AppTextSkeleton(width: 48, height: 9),
              ],
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextSkeleton(width: 180, height: 16),
                SizedBox(height: 8),
                AppTextSkeleton(width: 130, height: 12),
                SizedBox(height: 9),
                Row(
                  children: [
                    AppAvatarSkeleton(size: 20),
                    SizedBox(width: 6),
                    Expanded(child: AppTextSkeleton(width: 80, height: 12)),
                    AppTextSkeleton(width: 38, height: 12),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPostExplorer() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _BoardPostExplorerScreen(
          onSelected: _openPostCategory,
        ),
      ),
    );
  }

  Future<void> _openPostCategory(PostCategory category) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PostCategoryFeedScreen(category: category),
      ),
    );
  }

  Widget _buildTodayUnifiedList({
    required List<Post> todayPosts,
    required bool isPostsLoading,
    required bool isPostsError,
  }) {
    return StreamBuilder<List<Meetup>>(
      stream: _todayMeetupsStream,
      builder: (context, meetupSnapshot) {
        final todayMeetupsTitle = _safeL10n(
          (l) => l.todayMeetupsSectionTitle,
          '오늘의 밋업',
        );
        final todayPostsTitle = _safeL10n(
          (l) => l.todayPostsSectionTitle,
          '오늘의 게시글',
        );
        final noTodayMeetupsText = _safeL10n(
          (l) => l.todayNoMeetups,
          '오늘 올라온 밋업이 없어요.',
        );
        final noTodayPostsText = _safeL10n(
          (l) => l.todayNoPosts,
          '오늘 올라온 게시글이 없어요.',
        );

        final bool isMeetupsLoading =
            meetupSnapshot.connectionState == ConnectionState.waiting &&
                !meetupSnapshot.hasData &&
                _cachedTodayMeetups == null;

        // 보안 필터가 빈 목록을 반환하면 이전 비공개 카드 캐시를 즉시 폐기합니다.
        if (meetupSnapshot.hasData) {
          final incoming = meetupSnapshot.data ?? const <Meetup>[];
          _cachedTodayMeetups = incoming;
        }
        final todayMeetups =
            meetupSnapshot.data ?? _cachedTodayMeetups ?? const <Meetup>[];

        final meetupsCount = isMeetupsLoading
            ? 2
            : (todayMeetups.isNotEmpty ? todayMeetups.length : 1);

        final List<dynamic> todayCombined = <dynamic>[...todayPosts]..sort(
            (a, b) => _getTodayCombinedCreatedAt(b)
                .compareTo(_getTodayCombinedCreatedAt(a)));

        final postsCount = isPostsLoading
            ? 3
            : (isPostsError
                ? 1
                : (todayCombined.isNotEmpty ? todayCombined.length : 1));

        final itemCount = 1 + // snapshots
            1 + // banner
            1 + // meetups header
            meetupsCount +
            1 + // posts header
            postsCount;

        return RefreshIndicator(
          color: AppColors.pointColor,
          backgroundColor: Colors.white,
          onRefresh: () async {
            if (!isPostsLoading && !isPostsError) {
              await _refreshCommentCountsForPosts(todayPosts);
            } else {
              await Future.delayed(const Duration(milliseconds: 500));
              if (mounted) setState(() {});
            }
          },
          child: ListView.builder(
            key: const PageStorageKey('board_today_list_unified'),
            controller: _todayScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            cacheExtent: 1000,
            padding: const EdgeInsets.only(top: 4, bottom: 90),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              var i = index;

              // 0) snapshots: Today 전용이며 All/일반 게시물 수에는 포함하지 않는다.
              if (i == 0) {
                return const SnapshotTodaySection();
              }
              i -= 1;

              // 1) banner
              if (i == 0) {
                return AdBannerWidget(
                  key: const ValueKey('board_banner_today'),
                  widgetId: 'board_banner_today',
                );
              }
              i -= 1;

              // 1) meetups header
              if (i == 0) {
                return _buildTodaySectionHeader(
                  icon: Icons.event_available_rounded,
                  title: todayMeetupsTitle,
                  isLoading: isMeetupsLoading,
                );
              }
              i -= 1;

              // 2) meetups list/skeleton/empty
              if (i < meetupsCount) {
                if (isMeetupsLoading) {
                  return Padding(
                    padding: _boardPostCardMargin,
                    child: _buildMeetupSkeletonCard(),
                  );
                }
                if (todayMeetups.isEmpty) {
                  return _buildTodaySectionMessage(noTodayMeetupsText);
                }

                final meetup = todayMeetups[i];
                return Padding(
                  padding: _boardPostCardMargin,
                  child: StreamBuilder<int>(
                    stream: _meetupService.participantCountStream(
                      meetup.id,
                      fallback: meetup.currentParticipants,
                    ),
                    builder: (context, countSnap) {
                      final count =
                          countSnap.data ?? meetup.currentParticipants;
                      return BoardMeetupCard(
                        key: ValueKey('board_meetup_${meetup.id}'),
                        meetup: meetup,
                        currentParticipants: count,
                        onTap: () => _navigateToMeetupDetail(meetup),
                      );
                    },
                  ),
                );
              }
              i -= meetupsCount;

              // 3) posts header
              if (i == 0) {
                return _buildTodaySectionHeader(
                  icon: Icons.article_rounded,
                  title: todayPostsTitle,
                  actionLabel:
                      Localizations.localeOf(context).languageCode == 'ko'
                          ? '카테고리'
                          : 'Browse',
                  onAction: _openPostExplorer,
                );
              }
              i -= 1;

              // 4) posts list/skeleton/error/empty
              if (isPostsLoading) {
                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: _sectionHorizontalPadding,
                    vertical: 8,
                  ),
                  child: _buildPostSkeleton(),
                );
              }

              if (isPostsError) {
                return Padding(
                  padding: EdgeInsets.all(_sectionHorizontalPadding),
                  child: _buildErrorWidget('데이터를 불러올 수 없습니다'),
                );
              }

              if (todayCombined.isEmpty) {
                return _buildTodaySectionMessage(
                  noTodayPostsText,
                  bottom: 24,
                );
              }

              final itemIndex = i;
              final item = todayCombined[itemIndex];
              if (item is Post) {
                return OptimizedPostCard(
                  key: ValueKey(item.id),
                  post: item,
                  index: itemIndex,
                  onTap: () => _navigateToPostDetail(item),
                  externalCommentCountOverride: _commentCountOverrides[item.id],
                  preloadImage: itemIndex < 3,
                  margin: _boardPostCardMargin,
                  contentPadding: _boardPostCardContentPadding,
                );
              }
              return const SizedBox.shrink();
            },
          ),
        );
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
          ...List.generate(
              5,
              (index) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  // 전체 탭 - 게시글 목록 뷰 (레거시, 현재 미사용)
  Widget _buildAllPostsView(List<Post> posts) {
    final grouped = _groupItemsByDate(posts);

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
        cacheExtent: 1000,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _calculateAllItemCount(grouped),
        itemBuilder: (context, index) {
          if (index == 0) {
            return AdBannerWidget(
              key: ValueKey('board_banner_all'),
              widgetId: 'board_banner_all',
            );
          }
          return _buildAllGroupedItem(grouped, index - 1);
        },
      ),
    );
  }

  int _calculateAllItemCount(List<Map<String, dynamic>> grouped) {
    int totalItems = 1; // AdBanner
    for (var group in grouped) {
      totalItems += 1; // 날짜 헤더
      final groupItems = group['items'] as List<dynamic>;
      totalItems += groupItems.length;
    }
    return totalItems;
  }

  Widget _buildAllGroupedItem(
      List<Map<String, dynamic>> grouped, int adjustedIndex) {
    int currentIndex = 0;

    for (var group in grouped) {
      final dateLabel = group['dateLabel'] as String;
      final groupItems = group['items'] as List<dynamic>;

      // 날짜 헤더
      if (currentIndex == adjustedIndex) {
        return _buildDateHeader(dateLabel);
      }
      currentIndex++;

      // 아이템들 (Post)
      for (int i = 0; i < groupItems.length; i++) {
        if (currentIndex == adjustedIndex) {
          final item = groupItems[i];
          if (item is Post) {
            return OptimizedPostCard(
              key: ValueKey(item.id),
              post: item,
              index: i,
              onTap: () => _navigateToPostDetail(item),
              externalCommentCountOverride: _commentCountOverrides[item.id],
              preloadImage: i < 3,
              margin: _boardPostCardMargin,
              contentPadding: _boardPostCardContentPadding,
            );
          }
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

  DateTime _getTodayCombinedCreatedAt(dynamic item) {
    if (item is Post) return item.createdAt;
    return DateTime.fromMillisecondsSinceEpoch(0);
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

  Future<void> _openCreateMenu() async {
    final isKorean = Localizations.localeOf(context).languageCode == 'ko';
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withValues(alpha: 0.46),
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CreateMenuRow(
              icon: Icons.add_a_photo_outlined,
              title: isKorean ? '스낵' : 'Snack',
              description:
                  isKorean ? '24시간 동안 공유되는 사진' : 'A photo shared for 24 hours',
              onTap: () => Navigator.pop(sheetContext, 'snapshot'),
            ),
            const Divider(height: 1, indent: 42, color: Color(0xFFEAECF0)),
            _CreateMenuRow(
              icon: Icons.article_outlined,
              title: isKorean ? '포스트' : 'Post',
              description:
                  isKorean ? '계속 남겨두고 싶은 이야기' : 'A story you want to keep',
              onTap: () => Navigator.pop(sheetContext, 'post'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == 'snapshot') {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const CreateSnapshotScreen()),
      );
      return;
    }
    _openCreatePost();
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

  /// 날짜별 게시글 그룹화 (All 탭용)
  List<Map<String, dynamic>> _groupItemsByDate(List<dynamic> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));

    final Map<String, List<dynamic>> groups = {
      'today': [],
      'yesterday': [],
      'thisWeek': [],
      'previous': [],
    };

    for (final item in items) {
      final createdAt = _getTodayCombinedCreatedAt(item).toLocal();
      final itemDate = DateTime(createdAt.year, createdAt.month, createdAt.day);

      if (itemDate.isAtSameMomentAs(today)) {
        groups['today']!.add(item);
      } else if (itemDate.isAtSameMomentAs(yesterday)) {
        groups['yesterday']!.add(item);
      } else if (itemDate
              .isAfter(thisWeekStart.subtract(const Duration(days: 1))) &&
          itemDate.isBefore(yesterday)) {
        groups['thisWeek']!.add(item);
      } else {
        groups['previous']!.add(item);
      }
    }

    return groups.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => {
              'dateLabel': entry.key,
              'items': entry.value,
            })
        .toList();
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
      } else if (postDate
              .isAfter(thisWeekStart.subtract(const Duration(days: 1))) &&
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

class _BoardPostExplorerScreen extends StatefulWidget {
  final ValueChanged<PostCategory> onSelected;

  const _BoardPostExplorerScreen({required this.onSelected});

  @override
  State<_BoardPostExplorerScreen> createState() =>
      _BoardPostExplorerScreenState();
}

class _BoardPostExplorerScreenState extends State<_BoardPostExplorerScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          isKo ? '포스트 카테고리' : 'Post categories',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: context.rf(18).clamp(17.0, 20.0).toDouble(),
            fontWeight: FontWeight.w800,
            color: const Color(0xFF101828),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: PostCategoryExplorer(
              scrollController: _scrollController,
              onSelected: widget.onSelected,
            ),
          ),
        ),
      ),
    );
  }
}
