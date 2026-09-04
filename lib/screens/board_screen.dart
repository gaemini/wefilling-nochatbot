// lib/screens/board_screen.dart
// 게시판 화면 - 게시글 목록 표시 및 관리
// 검색, 필터링, 작성 기능 포함

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import '../models/post.dart';
import '../models/content_translation.dart';
import '../models/post_category.dart';
import '../models/meetup.dart';
import '../constants/app_constants.dart';
import '../services/post_service.dart';
import '../services/post_media_prefetch_service.dart';
import '../services/comment_service.dart';
import '../services/meetup_service.dart';
import '../services/content_filter_service.dart';
import '../services/content_translation_service.dart';
import '../ui/widgets/app_fab.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/skeletons.dart';
import '../ui/widgets/optimized_post_card.dart';
import '../ui/widgets/board_meetup_card.dart';
import '../ui/widgets/post_category_explorer.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../snapshot/snapshot_today_section.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';
import 'post_category_feed_screen.dart';
import 'meetup_detail_screen.dart';
import '../widgets/ad_banner_widget.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';
import '../utils/post_translation_policy.dart';

enum _BoardPostTranslationPriority { visible, adjacent }

class _BoardPostTranslationCandidate {
  const _BoardPostTranslationCandidate({
    required this.post,
    required this.request,
    required this.priority,
    required this.distance,
  });

  final Post post;
  final ContentTranslationRequest request;
  final _BoardPostTranslationPriority priority;
  final double distance;
}

class BoardScreen extends StatefulWidget {
  final VoidCallback onOpenMeetups;
  final ValueChanged<bool>? onChromeVisibilityChanged;

  const BoardScreen({
    super.key,
    required this.onOpenMeetups,
    this.onChromeVisibilityChanged,
  });

  @override
  State<BoardScreen> createState() => BoardScreenState();
}

class BoardScreenState extends State<BoardScreen> {
  final PostService _postService = PostService();
  final PostMediaPrefetchService _postMediaPrefetch =
      PostMediaPrefetchService.instance;
  final CommentService _commentService = CommentService();
  final MeetupService _meetupService = MeetupService();
  final ContentTranslationService _translationService =
      ContentTranslationService.instance;
  Timer? _midnightTimer;
  late final Stream<List<Post>> _postsStream;
  late final Stream<List<Meetup>> _todayMeetupsStream;

  List<Meetup>? _cachedTodayMeetups;

  // 수동 새로고침 시 계산한 댓글 수 오버라이드 (postId -> count)
  final Map<String, int> _commentCountOverrides = {};
  final Map<String, int> _commentCountOverrideSources = {};

  // 1000px 선행 빌드는 이미지가 많은 카드 여러 개를 한 프레임에 생성해
  // 디코딩과 자동 번역을 동시에 시작했다. 약 반 화면만 준비해 빠른 스크롤의
  // 여유는 유지하면서 화면 밖 작업이 현재 프레임을 방해하지 않게 한다.
  static const ScrollCacheExtent _postFeedCacheExtent =
      ScrollCacheExtent.pixels(480);

  // 일반 게시물은 그림자 대신 콘텐츠 여백과 divider로 구분한다.
  static const EdgeInsets _boardPostCardMargin = EdgeInsets.zero;

  EdgeInsets get _boardPostCardContentPadding {
    final horizontal = context.rs(8).clamp(7.0, 9.0).toDouble();
    final top = context.rs(7).clamp(6.0, 8.0).toDouble();
    final bottom = context.rs(3).clamp(2.0, 4.0).toDouble();
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
  bool _showCreateButton = true;
  double? _lastScrollOffset;
  double _directionalScrollDistance = 0;
  ScrollDirection _lastScrollDirection = ScrollDirection.idle;
  static const double _chromeDirectionThreshold = 14;
  static const String _psTodayOffsetId = 'board.todayScrollOffset.v1';
  static const String _psAllOffsetId = 'board.allScrollOffset.v1';

  // 캐시된 데이터를 저장하여 부드러운 전환 구현
  List<Post>? _cachedTodayPosts;
  bool _isInitialLoad = true;
  Future<void>? _refreshInFlight;

  // 오늘 섹션 아래에 이어 붙이는 전체 포스트 커서 페이지입니다. 한 번에
  // 10개만 읽고, 오늘 게시글은 실시간 섹션과 중복되지 않도록 화면에서 제외합니다.
  static const int _historyPageSize = 10;
  static const double _historyLoadMoreThreshold = 520;
  final List<Post> _pagedPosts = <Post>[];
  final List<Post> _cachedHistoricalBacklog = <Post>[];
  AllPostsCursor? _historyCursor;
  Object? _historyInitialError;
  Object? _historyLoadMoreError;
  bool _isHistoryInitialLoading = true;
  bool _isHistoryLoadingMore = false;
  bool _historyHasMore = true;
  int _historyLoadGeneration = 0;
  final Map<String, GlobalKey> _postAnchorKeys = {};
  final Map<String, Post> _translationPostsById = <String, Post>{};
  final Set<String> _translationCacheChecksInFlight = <String>{};
  final Set<String> _translationLocalCacheChecked = <String>{};
  final Map<String, _BoardPostTranslationCandidate>
      _translationMicroBatchCandidates =
      <String, _BoardPostTranslationCandidate>{};
  final Set<String> _translationRecoveryAttempted = <String>{};
  final Set<String> _translationScopeStartsInFlight = <String>{};
  Timer? _translationMicroBatchTimer;
  bool _translationScanScheduled = false;
  late int _translationLanguageRevision;
  static const Duration _translationMicroBatchWindow =
      Duration(milliseconds: 70);
  static const int _translationMaxBatchCandidates = 10;
  static const int _translationAdjacentLimit = 2;
  String? _pendingVisiblePostAnchorId;
  double? _pendingVisiblePostAnchorDy;
  bool _postAnchorRestoreScheduled = false;

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

  bool _samePostIdOrder(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  List<Post> get _historicalPosts {
    final posts = _pagedPosts.where((post) => !_isPostInToday(post)).toList();
    posts.sort((left, right) {
      final dateOrder = right.createdAt.compareTo(left.createdAt);
      return dateOrder != 0 ? dateOrder : right.id.compareTo(left.id);
    });
    return posts;
  }

  List<Post> _mergeVisibleTodayPosts(List<Post> realtimePosts) {
    final byId = <String, Post>{
      for (final post in realtimePosts.where(_isPostInToday)) post.id: post,
    };
    for (final post in _pagedPosts.where(_isPostInToday)) {
      byId[post.id] = post;
    }
    final posts = byId.values.toList()
      ..sort((left, right) {
        final dateOrder = right.createdAt.compareTo(left.createdAt);
        return dateOrder != 0 ? dateOrder : right.id.compareTo(left.id);
      });
    return posts;
  }

  Widget _withPostAnchor(Post post, Widget child) {
    _translationPostsById[post.id] = post;
    return KeyedSubtree(
      key: _postAnchorKeys.putIfAbsent(
        post.id,
        () => GlobalKey(debugLabel: 'board_post_anchor_${post.id}'),
      ),
      child: child,
    );
  }

  String _postTranslationSignature(
    ContentTranslationRequest request, {
    int? revision,
  }) {
    final entries = request.sourceFields.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final fieldsHash = Object.hashAll(
      entries.map((entry) => Object.hash(entry.key, entry.value)),
    );
    return '${request.serverId}|$fieldsHash|'
        '${revision ?? _translationLanguageRevision}';
  }

  bool _canPreparePostTranslation(Post post) {
    if (postTranslationSourceFields(post).isEmpty) return false;
    return !_translationService.showsOriginal('post:${post.id}');
  }

  List<_BoardPostTranslationCandidate> _translationCandidatesNearViewport() {
    if (!mounted || !TickerMode.valuesOf(context).enabled) {
      return const <_BoardPostTranslationCandidate>[];
    }
    final boardRenderObject = context.findRenderObject();
    if (boardRenderObject is! RenderBox || !boardRenderObject.attached) {
      return const <_BoardPostTranslationCandidate>[];
    }

    final viewportTop = boardRenderObject.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + boardRenderObject.size.height;
    final adjacentBand = boardRenderObject.size.height * 0.28;
    final visible = <_BoardPostTranslationCandidate>[];
    final adjacent = <_BoardPostTranslationCandidate>[];

    for (final entry in _postAnchorKeys.entries) {
      final post = _translationPostsById[entry.key];
      if (post == null || !_canPreparePostTranslation(post)) continue;
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;

      final top = renderObject.localToGlobal(Offset.zero).dy;
      final bottom = top + renderObject.size.height;
      final isVisible = bottom > viewportTop && top < viewportBottom;
      final distance = isVisible
          ? 0.0
          : bottom <= viewportTop
              ? viewportTop - bottom
              : top - viewportBottom;
      if (!isVisible && distance > adjacentBand) continue;

      final request = ContentTranslationRequest(
        contentType: 'post',
        contentId: post.id,
        sourceFields: postTranslationSourceFields(post),
      );
      if (_translationService.latestResultFor(request) != null ||
          _translationService.isScopeLoading('post:${post.id}')) {
        continue;
      }
      final candidate = _BoardPostTranslationCandidate(
        post: post,
        request: request,
        priority: isVisible
            ? _BoardPostTranslationPriority.visible
            : _BoardPostTranslationPriority.adjacent,
        distance: distance,
      );
      (isVisible ? visible : adjacent).add(candidate);
    }

    visible.sort((left, right) => left.distance.compareTo(right.distance));
    adjacent.sort((left, right) => left.distance.compareTo(right.distance));
    return <_BoardPostTranslationCandidate>[
      ...visible,
      ...adjacent.take(_translationAdjacentLimit),
    ].take(_translationMaxBatchCandidates).toList(growable: false);
  }

  void _scheduleVisiblePostTranslationScan() {
    if (_translationScanScheduled || !mounted) return;
    _translationScanScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _translationScanScheduled = false;
      if (!mounted) return;
      unawaited(_primeVisiblePostTranslations());
    });
  }

  Future<void> _primeVisiblePostTranslations() async {
    final candidates = _translationCandidatesNearViewport();
    if (candidates.isEmpty) return;
    final revision = _translationLanguageRevision;
    final uiLanguageCode = Localizations.localeOf(context).languageCode;
    final uncached = <_BoardPostTranslationCandidate>[];

    for (final candidate in candidates) {
      final signature = _postTranslationSignature(candidate.request);
      if (_translationLocalCacheChecked.contains(signature)) {
        uncached.add(candidate);
        continue;
      }
      if (_translationCacheChecksInFlight.add(signature)) {
        uncached.add(candidate);
      }
    }
    final probes = uncached
        .where(
          (candidate) => _translationCacheChecksInFlight
              .contains(_postTranslationSignature(candidate.request)),
        )
        .toList(growable: false);

    Map<String, ContentTranslationResult> cached =
        const <String, ContentTranslationResult>{};
    if (probes.isNotEmpty) {
      try {
        cached = await _translationService.cachedResultsFor(
          probes.map((candidate) => candidate.request),
          uiLanguageCode: uiLanguageCode,
        );
      } catch (error) {
        if (Logger.isVerboseEnabled)
          Logger.warning(
            '포스트 로컬 번역 캐시 확인 실패: ${error.runtimeType}',
          );
      } finally {
        for (final candidate in probes) {
          final signature = _postTranslationSignature(
            candidate.request,
            revision: revision,
          );
          _translationCacheChecksInFlight.remove(signature);
          if (revision == _translationLanguageRevision) {
            _translationLocalCacheChecked.add(signature);
          }
        }
      }
    }
    if (!mounted || revision != _translationLanguageRevision) return;

    for (final candidate in uncached) {
      if (cached.containsKey(candidate.request.serverId) ||
          _translationService.latestResultFor(candidate.request) != null) {
        continue;
      }
      _translationMicroBatchCandidates[candidate.post.id] = candidate;
    }
    _schedulePostTranslationMicroBatch();
  }

  void _schedulePostTranslationMicroBatch() {
    if (_translationMicroBatchCandidates.isEmpty ||
        _translationMicroBatchTimer != null) {
      return;
    }
    _translationMicroBatchTimer = Timer(
      _translationMicroBatchWindow,
      _flushPostTranslationMicroBatch,
    );
  }

  void _flushPostTranslationMicroBatch() {
    _translationMicroBatchTimer = null;
    if (!mounted || !TickerMode.valuesOf(context).enabled) {
      _translationMicroBatchCandidates.clear();
      return;
    }

    final queuedIds = _translationMicroBatchCandidates.keys.toSet();
    _translationMicroBatchCandidates.clear();
    final current = _translationCandidatesNearViewport()
        .where((candidate) => queuedIds.contains(candidate.post.id))
        .toList(growable: false)
      ..sort((left, right) {
        final priority = left.priority.index.compareTo(right.priority.index);
        return priority != 0
            ? priority
            : left.distance.compareTo(right.distance);
      });

    for (final candidate in current.take(_translationMaxBatchCandidates)) {
      final scope = 'post:${candidate.post.id}';
      final signature = _postTranslationSignature(candidate.request);
      if (_translationService.latestResultFor(candidate.request) != null ||
          _translationService.isScopeLoading(scope)) {
        continue;
      }
      final failed = _translationService.hasExhaustedRetryForScope(scope);
      if (failed &&
          (!_translationService.canAutomaticallyRetryScope(scope) ||
              _translationRecoveryAttempted.contains(signature))) {
        continue;
      }
      if (!_translationScopeStartsInFlight.add(signature)) continue;
      unawaited(_startPostTranslationScope(
        scope: scope,
        signature: signature,
        recoveringFailure: failed,
      ));
    }
  }

  Future<void> _startPostTranslationScope({
    required String scope,
    required String signature,
    required bool recoveringFailure,
  }) async {
    try {
      final loaded = await _translationService.loadAttachedScope(
        scope,
        retryBlockedFailure: recoveringFailure,
      );
      if (loaded && recoveringFailure) {
        _translationRecoveryAttempted.add(signature);
      }
    } finally {
      _translationScopeStartsInFlight.remove(signature);
    }
  }

  void _handleTranslationServiceChanged() {
    if (!mounted) return;
    final revision = _translationService.languageRevision;
    if (revision != _translationLanguageRevision) {
      _translationLanguageRevision = revision;
      _translationMicroBatchTimer?.cancel();
      _translationMicroBatchTimer = null;
      _translationMicroBatchCandidates.clear();
      _translationCacheChecksInFlight.clear();
      _translationLocalCacheChecked.clear();
      _translationRecoveryAttempted.clear();
      _translationScopeStartsInFlight.clear();
    }
    _scheduleVisiblePostTranslationScan();
  }

  void _captureVisiblePostAnchor() {
    if (!_controllersInitialized || !_todayScrollController.hasClients) return;
    if (_todayScrollController.offset <= 0) return;

    String? bestId;
    double? bestDy;
    double bestDistance = double.infinity;
    final viewportHeight = MediaQuery.sizeOf(context).height;

    for (final entry in _postAnchorKeys.entries) {
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final dy = renderObject.localToGlobal(Offset.zero).dy;
      final bottom = dy + renderObject.size.height;
      if (bottom <= 0 || dy >= viewportHeight) continue;
      final distance = dy >= 0 ? dy : dy.abs() * 0.5;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestId = entry.key;
        bestDy = dy;
      }
    }

    _pendingVisiblePostAnchorId = bestId;
    _pendingVisiblePostAnchorDy = bestDy;
  }

  void _scheduleVisiblePostAnchorRestore() {
    if (_postAnchorRestoreScheduled || _pendingVisiblePostAnchorId == null) {
      return;
    }
    _postAnchorRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postAnchorRestoreScheduled = false;
      if (!mounted || !_todayScrollController.hasClients) return;
      final postId = _pendingVisiblePostAnchorId;
      final previousDy = _pendingVisiblePostAnchorDy;
      _pendingVisiblePostAnchorId = null;
      _pendingVisiblePostAnchorDy = null;
      if (postId == null || previousDy == null) return;

      final renderObject =
          _postAnchorKeys[postId]?.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) return;
      final currentDy = renderObject.localToGlobal(Offset.zero).dy;
      final delta = currentDy - previousDy;
      if (delta.abs() < 0.5) return;
      final position = _todayScrollController.position;
      final target = (_todayScrollController.offset + delta)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      _todayScrollController.jumpTo(target);
    });
  }

  @override
  void initState() {
    super.initState();
    _translationLanguageRevision = _translationService.languageRevision;
    _translationService.addListener(_handleTranslationServiceChanged);
    // 탭 전환이나 하단 내비게이션 애니메이션으로 build가 다시 호출돼도
    // 동일 스트림 구독을 유지한다. 목록과 스크롤 위치가 그대로 보존되고,
    // 다른 탭에 있는 동안 들어온 최신 포스트도 기존 구독으로 반영된다.
    _postsStream = _postService.getPostsStream();
    unawaited(_bootstrapFeed());
    _scheduleMidnightRefresh();
    // Today 밋업 섹션은 현재 사용자의 공개 범위 안에서:
    // - 오늘 생성된 모임
    // - 약속 날짜가 오늘인 모임
    // 만 노출한다. (공개 범위 필터링은 MeetupService에서 강제)
    _todayMeetupsStream = _meetupService.getTodayTabMeetups();

    // 컨트롤러 초기화/상태 복원은 didChangeDependencies에서 처리
  }

  Future<void> _bootstrapFeed() async {
    final restoredHistory = await _loadCachedData();
    if (!mounted) return;
    if (!restoredHistory) {
      await _loadFirstHistoricalPage();
    } else {
      _scheduleHistoricalPrefetchIfNeeded();
    }
  }

  Future<void> _loadFirstHistoricalPage({bool showLoading = true}) async {
    final generation = ++_historyLoadGeneration;
    if (mounted) {
      setState(() {
        _isHistoryInitialLoading = true;
        _isHistoryLoadingMore = false;
        if (showLoading) _historyInitialError = null;
      });
    }

    try {
      final page = await _postService.getAllPostsPage(
        startAfter: null,
        pageSize: _historyPageSize,
      );
      if (!mounted || generation != _historyLoadGeneration) return;
      setState(() {
        _pagedPosts
          ..clear()
          ..addAll(page.posts);
        _cachedHistoricalBacklog.clear();
        _historyCursor = page.cursor;
        _historyHasMore = page.hasMore;
        _historyInitialError = null;
        _historyLoadMoreError = null;
        _isHistoryInitialLoading = false;
        _isHistoryLoadingMore = false;
      });
      unawaited(_postMediaPrefetch.prefetchPosts(page.posts, maxPosts: 4));
      _scheduleHistoricalPrefetchIfNeeded();
    } catch (error) {
      if (!mounted || generation != _historyLoadGeneration) return;
      setState(() {
        _historyInitialError = error;
        _isHistoryInitialLoading = false;
        _isHistoryLoadingMore = false;
      });
    }
  }

  Future<void> _loadMoreHistoricalPosts() async {
    if (_isHistoryInitialLoading || _isHistoryLoadingMore || !_historyHasMore) {
      return;
    }

    final previousCursor = _historyCursor;
    final generation = _historyLoadGeneration;
    setState(() {
      _isHistoryLoadingMore = true;
      _historyLoadMoreError = null;
    });

    // 이미 휴대폰에 저장된 다음 페이지가 있으면 네트워크보다 먼저 10개만
    // 꺼냅니다. 스크롤 왕복으로 같은 문서를 다시 읽지 않게 하는 경로입니다.
    if (_cachedHistoricalBacklog.isNotEmpty) {
      final chunk = _cachedHistoricalBacklog
          .take(_historyPageSize)
          .toList(growable: false);
      _cachedHistoricalBacklog.removeRange(0, chunk.length);
      final byId = <String, Post>{
        for (final post in _pagedPosts) post.id: post,
        for (final post in chunk) post.id: post,
      };
      final merged = byId.values.toList()
        ..sort((left, right) {
          final dateOrder = right.createdAt.compareTo(left.createdAt);
          return dateOrder != 0 ? dateOrder : right.id.compareTo(left.id);
        });
      final oldest = chunk.isEmpty ? null : chunk.last;
      setState(() {
        _pagedPosts
          ..clear()
          ..addAll(merged);
        if (oldest != null) {
          _historyCursor = AllPostsCursor(
            createdAt: oldest.createdAt,
            postId: oldest.id,
          );
        }
        _historyHasMore = true;
        _isHistoryLoadingMore = false;
      });
      unawaited(_postMediaPrefetch.prefetchPosts(chunk, maxPosts: 4));
      _scheduleHistoricalPrefetchIfNeeded();
      return;
    }

    try {
      final page = await _postService.getAllPostsPage(
        startAfter: previousCursor,
        pageSize: _historyPageSize,
      );
      if (!mounted || generation != _historyLoadGeneration) return;

      final byId = <String, Post>{
        for (final post in _pagedPosts) post.id: post
      };
      for (final post in page.posts) {
        byId[post.id] = post;
      }
      final merged = byId.values.toList()
        ..sort((left, right) {
          final dateOrder = right.createdAt.compareTo(left.createdAt);
          return dateOrder != 0 ? dateOrder : right.id.compareTo(left.id);
        });
      final cursorProgressed =
          page.cursor?.createdAt != previousCursor?.createdAt ||
              page.cursor?.postId != previousCursor?.postId;

      setState(() {
        _pagedPosts
          ..clear()
          ..addAll(merged);
        _historyCursor = page.cursor;
        _historyHasMore =
            page.hasMore && (page.posts.isNotEmpty || cursorProgressed);
        _isHistoryLoadingMore = false;
      });
      unawaited(_postMediaPrefetch.prefetchPosts(page.posts, maxPosts: 4));
      _scheduleHistoricalPrefetchIfNeeded();
    } catch (error) {
      if (!mounted || generation != _historyLoadGeneration) return;
      setState(() {
        _historyLoadMoreError = error;
        _isHistoryLoadingMore = false;
      });
    }
  }

  void _scheduleHistoricalPrefetchIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_controllersInitialized ||
          !_todayScrollController.hasClients) {
        return;
      }
      if (_todayScrollController.position.extentAfter <=
          _historyLoadMoreThreshold) {
        unawaited(_loadMoreHistoricalPosts());
      }
    });
  }

  Future<void> _refreshBoardFeed(List<Post> visiblePosts) async {
    await Future.wait<void>([
      _refreshFeed(visiblePosts),
      _loadFirstHistoricalPage(showLoading: false),
    ]);
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
  Future<bool> _loadCachedData() async {
    try {
      // 차단 목록을 먼저 로드하여 flickering 방지
      await ContentFilterService.preloadBlockLists();

      final cachedResults = await Future.wait<List<Post>>(<Future<List<Post>>>[
        _postService.getCachedPosts(),
        _postService.getCachedAllPosts(),
      ]);
      if (!mounted) return false;

      final cachedPosts = cachedResults[0];
      final cachedAllPosts = cachedResults[1];
      final cachedHistory =
          cachedAllPosts.where((post) => !_isPostInToday(post)).toList()
            ..sort((left, right) {
              final dateOrder = right.createdAt.compareTo(left.createdAt);
              return dateOrder != 0 ? dateOrder : right.id.compareTo(left.id);
            });

      if (cachedPosts.isNotEmpty || cachedHistory.isNotEmpty) {
        final firstHistoryPage =
            cachedHistory.take(_historyPageSize).toList(growable: false);
        final remainingHistory =
            cachedHistory.skip(firstHistoryPage.length).toList(growable: false);
        final oldest = firstHistoryPage.isEmpty ? null : firstHistoryPage.last;
        setState(() {
          // Today 캐시는 기존 정책을 유지합니다. All은 카테고리 탐색 화면입니다.
          _cachedTodayPosts = cachedPosts.where(_isPostInToday).toList();
          if (firstHistoryPage.isNotEmpty) {
            _pagedPosts
              ..clear()
              ..addAll(firstHistoryPage);
            _cachedHistoricalBacklog
              ..clear()
              ..addAll(remainingHistory);
            _historyCursor = AllPostsCursor(
              createdAt: oldest!.createdAt,
              postId: oldest.id,
            );
            _historyHasMore = true;
            _historyInitialError = null;
            _historyLoadMoreError = null;
            _isHistoryInitialLoading = false;
            _isHistoryLoadingMore = false;
          }
        });
        unawaited(
          _postMediaPrefetch.prefetchPosts(
            <Post>[...cachedPosts.take(3), ...firstHistoryPage.take(3)],
            maxPosts: 6,
          ),
        );
        if (Logger.isVerboseEnabled)
          Logger.log(
            '✅ 캐시된 게시글 로드 완료: today=${cachedPosts.length}, history=${cachedHistory.length}',
          );
      }
      return cachedHistory.isNotEmpty;
    } catch (e) {
      Logger.error('캐시 로드 오류: $e');
      return false;
    }
  }

  /// 상세 화면과 같은 기준으로 카드 댓글 수를 일괄 재집계합니다.
  Future<void> _refreshCommentCountsForPosts(List<Post> posts) async {
    // 너무 많은 카드에 대해 매번 집계하면 느려질 수 있어, 상위 N개만 갱신
    const maxTargets = 40;
    final ids = posts.map((p) => p.id).toSet().take(maxTargets).toList();
    if (ids.isEmpty) return;

    final counts = await _commentService.fetchCommentCountsForPostIds(ids);
    if (!mounted) return;

    final postsById = <String, Post>{for (final post in posts) post.id: post};
    setState(() {
      _commentCountOverrides.addAll(counts);
      for (final entry in counts.entries) {
        final source = postsById[entry.key];
        if (source != null) {
          _commentCountOverrideSources[entry.key] = source.commentCount;
        }
      }
    });
  }

  /// 포스트 본문과 지표를 함께 새로 읽고, 모든 네트워크 대기에 상한을 둔다.
  /// 연속으로 당겨도 동일 Future를 공유하므로 중복 요청과 무한 인디케이터를 막는다.
  Future<void> _refreshFeed([List<Post> visiblePosts = const <Post>[]]) {
    final activeRefresh = _refreshInFlight;
    if (activeRefresh != null) return activeRefresh;

    late final Future<void> trackedRefresh;
    trackedRefresh = _performFeedRefresh(visiblePosts).whenComplete(() {
      if (identical(_refreshInFlight, trackedRefresh)) {
        _refreshInFlight = null;
      }
    });
    _refreshInFlight = trackedRefresh;
    return trackedRefresh;
  }

  Future<void> _performFeedRefresh(List<Post> visiblePosts) async {
    var refreshedPosts = visiblePosts;
    Object? refreshError;

    // 일시적인 연결 실패는 한 번 자동 재시도한다. 각 시도는 서비스 내부
    // timeout으로 반드시 끝나므로 RefreshIndicator도 무한 대기하지 않는다.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        refreshedPosts = await _postService.refreshPosts(
          timeout: const Duration(seconds: 7),
        );
        refreshError = null;
        break;
      } catch (error) {
        refreshError = error;
        if (Logger.isVerboseEnabled)
          Logger.warning('포스트 수동 새로고침 실패(${attempt + 1}/2): $error');
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    }

    final refreshedTodayPosts = refreshedPosts.where(_isPostInToday).toList();
    final commentTargets =
        refreshedTodayPosts.isNotEmpty ? refreshedTodayPosts : visiblePosts;
    try {
      await _refreshCommentCountsForPosts(commentTargets).timeout(
        const Duration(seconds: 8),
      );
    } catch (error) {
      // 댓글 재집계 실패가 포스트 목록 새로고침이나 인디케이터 종료를 막지 않는다.
      if (Logger.isVerboseEnabled) Logger.warning('새로고침 중 댓글 수 재집계 실패: $error');
    }

    if (!mounted) return;
    setState(() {
      if (refreshError == null) {
        _cachedTodayPosts = refreshedTodayPosts;
        _isInitialLoad = false;
      }
    });
    if (refreshError == null) {
      unawaited(
        _postMediaPrefetch.prefetchPosts(refreshedTodayPosts, maxPosts: 4),
      );
    }

    if (refreshError != null) {
      final isKo = Localizations.localeOf(context).languageCode == 'ko';
      AppSnackBar.show(
        context,
        message: isKo
            ? '새로고침에 실패했습니다. 잠시 후 다시 시도해 주세요.'
            : 'Refresh failed. Please try again shortly.',
        type: AppSnackBarType.error,
      );
    }
  }

  @override
  void dispose() {
    if (Logger.isVerboseEnabled) Logger.log('🔄 BoardScreen dispose 시작');
    _midnightTimer?.cancel();
    _translationService.removeListener(_handleTranslationServiceChanged);
    _translationMicroBatchTimer?.cancel();
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
    if (Logger.isVerboseEnabled) Logger.log('✅ BoardScreen dispose 완료');
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
    _scheduleVisiblePostTranslationScan();
    final controller = _activeScrollController;
    if (!controller.hasClients) return;
    final position = controller.position;
    final offset = position.pixels;
    final direction = position.userScrollDirection;

    if (position.extentAfter <= _historyLoadMoreThreshold) {
      unawaited(_loadMoreHistoricalPosts());
    }

    if (offset <= position.minScrollExtent + 8) {
      _lastScrollOffset = offset;
      _directionalScrollDistance = 0;
      _lastScrollDirection = ScrollDirection.idle;
      _setScrollChromeVisibility(true);
      return;
    }

    if (direction == ScrollDirection.idle) {
      _lastScrollOffset = offset;
      // 스크롤이 멈추면 현재 chrome 상태를 그대로 유지한다.
      // 위로 스크롤하거나 맨 위에 도달했을 때만 다시 노출한다.
      return;
    }

    if (direction != _lastScrollDirection) {
      _directionalScrollDistance = 0;
      _lastScrollDirection = direction;
    }
    final previousOffset = _lastScrollOffset;
    _lastScrollOffset = offset;
    if (previousOffset != null) {
      _directionalScrollDistance += (offset - previousOffset).abs();
    }
    if (_directionalScrollDistance < _chromeDirectionThreshold) return;

    _directionalScrollDistance = 0;
    _setScrollChromeVisibility(direction == ScrollDirection.forward);
  }

  bool _handleBoardScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical || notification.depth != 0) {
      return false;
    }
    // ScrollEnd/idle에서 자동 복원하지 않는다. 방향 판별은
    // ScrollController listener에서만 처리해 멈춤 상태가 유지되게 한다.
    return false;
  }

  void _setScrollChromeVisibility(bool shouldShow) {
    if (shouldShow != _showCreateButton) {
      setState(() => _showCreateButton = shouldShow);
      widget.onChromeVisibilityChanged?.call(shouldShow);
    }
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

  Future<void> showLatestPost() async {
    _setScrollChromeVisibility(true);
    await _refreshBoardFeed(const <Post>[]);
    if (!mounted) return;
    scrollToTop();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleVisiblePostTranslationScan();
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SizedBox(
            width: double.infinity,
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleBoardScrollNotification,
              child: StreamBuilder<List<Post>>(
                stream: _postsStream,
                builder: (context, postSnap) {
                  return _buildTodayPostsTab(postSnap);
                },
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: _ScrollAwareCreateButton(
          visible: _showCreateButton,
          child: AppFab.write(
            onPressed: _openCreatePost,
            heroTag: 'board_write_fab',
          ),
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

    // 일괄 재집계 값은 과거 카운터 드리프트를 보정하기 위한 임시 값이다.
    // 이후 서버 commentCount가 바뀌면 새 댓글/삭제 이벤트가 반영된 것이므로
    // 임시 값을 해제하고 실시간 포스트 스트림을 다시 단일 기준으로 사용한다.
    for (final post in todayPosts) {
      final sourceCount = _commentCountOverrideSources[post.id];
      if (sourceCount != null && sourceCount != post.commentCount) {
        _commentCountOverrideSources.remove(post.id);
        _commentCountOverrides.remove(post.id);
      }
    }

    if (snapshot.hasData) {
      final previousIds = (_cachedTodayPosts ?? const <Post>[])
          .map((post) => post.id)
          .toList(growable: false);
      final nextIds = todayPosts.map((post) => post.id).toList(growable: false);
      if (!_samePostIdOrder(previousIds, nextIds)) {
        _captureVisiblePostAnchor();
      }
      _cachedTodayPosts = todayPosts;
      unawaited(_postMediaPrefetch.prefetchPosts(todayPosts, maxPosts: 4));
      if (_isInitialLoad) _isInitialLoad = false;
      _scheduleVisiblePostAnchorRestore();
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
      onRefresh: () => _refreshFeed(_cachedTodayPosts ?? const <Post>[]),
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
      onRefresh: () => _refreshFeed(_cachedTodayPosts ?? const <Post>[]),
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
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
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
              SizedBox(width: gap),
              TextButton(
                key: const ValueKey('today_meetups_all_button'),
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF475467),
                  minimumSize: const Size(44, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.padded,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  actionLabel,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: context.rf(12.5).clamp(12.0, 13.0).toDouble(),
                    fontWeight: FontWeight.w800,
                  ),
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
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
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
          onRefresh: () => _refreshFeed(todayPosts),
          child: ListView.builder(
            key: const PageStorageKey('board_today_list'),
            controller: _todayScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            scrollCacheExtent: _postFeedCacheExtent,
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
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
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
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
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
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
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
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
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
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                );
              }

              final postIndex = i;
              final post = todayPosts[postIndex];
              return _withPostAnchor(
                post,
                OptimizedPostCard(
                  key: ValueKey(post.id),
                  post: post,
                  index: postIndex,
                  onTap: () => _navigateToPostDetail(post),
                  onCategoryTap: _openPostCategory,
                  externalCommentCountOverride: _commentCountOverrides[post.id],
                  preloadImage: postIndex < 3,
                  deferTranslationUntilVisible: true,
                  onTranslationLoaderAttached:
                      _scheduleVisiblePostTranslationScan,
                  margin: _boardPostCardMargin,
                  contentPadding: _boardPostCardContentPadding,
                ),
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

  Future<void> _openPostCategory(PostCategory category) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PostCategoryFeedScreen(category: category),
      ),
    );
  }

  Widget _buildPostCategoryRail() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 360;
        final isExpanded = constraints.maxWidth >= 600;
        final cardWidth = isCompact ? 158.0 : (isExpanded ? 210.0 : 176.0);
        final cardHeight = isCompact ? 140.0 : (isExpanded ? 148.0 : 144.0);
        final contentPadding = isCompact ? 12.0 : (isExpanded ? 16.0 : 14.0);
        final iconSize = isCompact ? 21.0 : (isExpanded ? 24.0 : 22.0);
        final titleSize = isCompact ? 14.0 : (isExpanded ? 16.0 : 15.0);
        final descriptionSize = isCompact ? 11.0 : (isExpanded ? 12.0 : 11.5);

        return _AutoScrollingPostCategoryRail(
          key: const ValueKey('board_post_category_rail'),
          height: cardHeight + 14,
          cardWidth: cardWidth,
          cardHeight: cardHeight,
          horizontalPadding: _sectionHorizontalPadding,
          contentPadding: contentPadding,
          iconSize: iconSize,
          titleSize: titleSize,
          descriptionSize: descriptionSize,
          onSelected: _openPostCategory,
        );
      },
    );
  }

  Widget _buildHistoricalPostsDivider() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _sectionHorizontalPadding,
        48,
        _sectionHorizontalPadding,
        8,
      ),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFFEAECF0))),
          const SizedBox(width: 10),
          Text(
            '${l10n.previous} ${l10n.posts}',
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: context.rf(11.5).clamp(11, 12.5).toDouble(),
              fontWeight: FontWeight.w600,
              color: const Color(0xFF98A2B3),
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: Color(0xFFEAECF0))),
        ],
      ),
    );
  }

  Widget _buildHistoricalPostsFooter() {
    if (_isHistoryInitialLoading || _isHistoryLoadingMore) {
      return const Padding(
        key: ValueKey('board_history_loading'),
        padding: EdgeInsets.fromLTRB(0, 16, 0, 28),
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final error =
        _pagedPosts.isEmpty ? _historyInitialError : _historyLoadMoreError;
    if (error != null) {
      final isKo = Localizations.localeOf(context).languageCode == 'ko';
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
        child: Center(
          child: TextButton(
            key: const ValueKey('board_history_retry'),
            onPressed: () {
              if (_pagedPosts.isEmpty) {
                unawaited(_loadFirstHistoricalPage());
              } else {
                unawaited(_loadMoreHistoricalPosts());
              }
            },
            child: Text(isKo ? '이전 포스트 다시 불러오기' : 'Retry earlier posts'),
          ),
        ),
      );
    }

    // 추가 페이지는 스크롤 임계점에서 자동으로 요청됩니다. 버튼이나 완료
    // 문구를 두지 않아 오늘 피드에서 이전 피드로 자연스럽게 이어집니다.
    return SizedBox(height: _historyHasMore ? 44 : 24);
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

        // 로딩/빈 상태/캐러셀 모두 기존 한 칸 높이를 사용한다.
        final meetupsCount = 1;

        final visibleTodayPosts = _mergeVisibleTodayPosts(todayPosts);
        final List<dynamic> todayCombined = <dynamic>[...visibleTodayPosts]
          ..sort((a, b) => _getTodayCombinedCreatedAt(b)
              .compareTo(_getTodayCombinedCreatedAt(a)));
        final historicalPosts = _historicalPosts;

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
            1 + // horizontally scrollable post categories
            postsCount +
            (historicalPosts.isEmpty ? 0 : historicalPosts.length + 1) +
            1; // 이전 포스트 로딩/재시도 여백

        return RefreshIndicator(
          color: AppColors.pointColor,
          backgroundColor: Colors.white,
          onRefresh: () => _refreshBoardFeed(todayPosts),
          child: ListView.builder(
            key: const PageStorageKey('board_today_list_unified'),
            controller: _todayScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            scrollCacheExtent: _postFeedCacheExtent,
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
                  actionLabel:
                      Localizations.localeOf(context).languageCode == 'ko'
                          ? '모두 보기'
                          : 'ALL',
                  onAction: widget.onOpenMeetups,
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

                return _buildTodayMeetupCarousel(todayMeetups);
              }
              i -= meetupsCount;

              // 3) posts header
              if (i == 0) {
                return _buildTodaySectionHeader(
                  icon: Icons.article_rounded,
                  title: todayPostsTitle,
                );
              }
              i -= 1;

              // 4) categories: page snapping 없이 연속적으로 움직이는 가로 목록
              if (i == 0) {
                return _buildPostCategoryRail();
              }
              i -= 1;

              // 5) posts list/skeleton/error/empty
              if (i < postsCount) {
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
                    bottom: 10,
                  );
                }

                final itemIndex = i;
                final item = todayCombined[itemIndex];
                if (item is Post) {
                  return _withPostAnchor(
                    item,
                    OptimizedPostCard(
                      key: ValueKey(item.id),
                      post: item,
                      index: itemIndex,
                      onTap: () => _navigateToPostDetail(item),
                      onCategoryTap: _openPostCategory,
                      externalCommentCountOverride:
                          _commentCountOverrides[item.id],
                      preloadImage: itemIndex < 3,
                      deferTranslationUntilVisible: true,
                      onTranslationLoaderAttached:
                          _scheduleVisiblePostTranslationScan,
                      showBottomDivider: historicalPosts.isEmpty ||
                          itemIndex != todayCombined.length - 1,
                      margin: _boardPostCardMargin,
                      contentPadding: _boardPostCardContentPadding,
                    ),
                  );
                }
                return const SizedBox.shrink();
              }

              i -= postsCount;

              // 6) 오늘 이후의 이전 포스트. 첫 카드 앞에 작은 구분선을 넣고,
              // 페이지는 사용자가 아래로 내릴 때마다 최신순 10개씩 추가한다.
              if (historicalPosts.isNotEmpty) {
                if (i == 0) return _buildHistoricalPostsDivider();
                i -= 1;
                if (i < historicalPosts.length) {
                  final post = historicalPosts[i];
                  return _withPostAnchor(
                    post,
                    OptimizedPostCard(
                      key: ValueKey('board_history_${post.id}'),
                      post: post,
                      index: todayCombined.length + i,
                      onTap: () => _navigateToPostDetail(post),
                      onCategoryTap: _openPostCategory,
                      externalCommentCountOverride:
                          _commentCountOverrides[post.id],
                      preloadImage: i < 2,
                      deferTranslationUntilVisible: true,
                      onTranslationLoaderAttached:
                          _scheduleVisiblePostTranslationScan,
                      margin: _boardPostCardMargin,
                      contentPadding: _boardPostCardContentPadding,
                    ),
                  );
                }
                i -= historicalPosts.length;
              }

              if (i == 0) return _buildHistoricalPostsFooter();
              return const SizedBox.shrink();
            },
          ),
        );
      },
    );
  }

  Widget _buildTodayMeetupCarousel(List<Meetup> meetups) {
    return SizedBox(
      height: context.rh(108, min: 104, max: 116),
      child: PageView.builder(
        key: const PageStorageKey('board_today_meetups_carousel'),
        physics: meetups.length > 1
            ? const PageScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        itemCount: meetups.length,
        itemBuilder: (context, index) {
          final meetup = meetups[index];
          return Semantics(
            label: '${index + 1} / ${meetups.length}',
            child: Padding(
              padding: _boardPostCardMargin,
              child: StreamBuilder<int>(
                stream: _meetupService.participantCountStream(
                  meetup.id,
                  fallback: meetup.currentParticipants,
                ),
                builder: (context, countSnap) {
                  final count = countSnap.data ?? meetup.currentParticipants;
                  return BoardMeetupCard(
                    key: ValueKey('board_meetup_${meetup.id}'),
                    meetup: meetup,
                    currentParticipants: count,
                    onTap: () => _navigateToMeetupDetail(meetup),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  // 전체 탭 - 로딩 뷰
  Widget _buildAllLoadingView() {
    return RefreshIndicator(
      color: AppColors.pointColor,
      backgroundColor: Colors.white,
      onRefresh: () => _refreshFeed(),
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
      onRefresh: () => _refreshFeed(),
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
      onRefresh: () => _refreshFeed(),
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
      onRefresh: () => _refreshFeed(posts),
      child: ListView.builder(
        key: const PageStorageKey('board_all_list'),
        controller: _allScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        scrollCacheExtent: _postFeedCacheExtent,
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
            return _withPostAnchor(
              item,
              OptimizedPostCard(
                key: ValueKey(item.id),
                post: item,
                index: i,
                onTap: () => _navigateToPostDetail(item),
                onCategoryTap: _openPostCategory,
                externalCommentCountOverride: _commentCountOverrides[item.id],
                preloadImage: i < 3,
                deferTranslationUntilVisible: true,
                onTranslationLoaderAttached:
                    _scheduleVisiblePostTranslationScan,
                margin: _boardPostCardMargin,
                contentPadding: _boardPostCardContentPadding,
              ),
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
    final controller = _activeScrollController;
    final preservedOffset = controller.hasClients ? controller.offset : null;

    final wasDeleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => PostDetailScreen(post: post)),
    );

    if (!mounted) return;
    _restoreActiveScrollOffset(preservedOffset);

    // 삭제된 글만 현재 목록에서 제거한다. 나머지 수치는 카드와 상세가 같은
    // PostService 상태를 구독하므로 복귀 시 별도 댓글/피드 재조회 없이 유지된다.
    if (wasDeleted == true) {
      setState(() => _pagedPosts.removeWhere((item) => item.id == post.id));
    }
  }

  void _restoreActiveScrollOffset(double? offset) {
    if (offset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _activeScrollController;
      if (!controller.hasClients) return;

      final position = controller.position;
      final target = offset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((controller.offset - target).abs() > 0.5) {
        controller.jumpTo(target);
      }
    });
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

class _ScrollAwareCreateButton extends StatelessWidget {
  const _ScrollAwareCreateButton({
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

class _AutoScrollingPostCategoryRail extends StatefulWidget {
  const _AutoScrollingPostCategoryRail({
    super.key,
    required this.height,
    required this.cardWidth,
    required this.cardHeight,
    required this.horizontalPadding,
    required this.contentPadding,
    required this.iconSize,
    required this.titleSize,
    required this.descriptionSize,
    required this.onSelected,
  });

  final double height;
  final double cardWidth;
  final double cardHeight;
  final double horizontalPadding;
  final double contentPadding;
  final double iconSize;
  final double titleSize;
  final double descriptionSize;
  final ValueChanged<PostCategory> onSelected;

  @override
  State<_AutoScrollingPostCategoryRail> createState() =>
      _AutoScrollingPostCategoryRailState();
}

class _AutoScrollingPostCategoryRailState
    extends State<_AutoScrollingPostCategoryRail>
    with SingleTickerProviderStateMixin {
  static const double _gap = 8;
  static const double _pixelsPerSecond = 26;
  static const int _repeatedCycles = 1000;
  static const int _initialCycle = _repeatedCycles ~/ 2;

  late final ScrollController _scrollController;
  late final Ticker _ticker;
  Duration? _lastElapsed;
  bool _isUserScrolling = false;
  bool _disableAnimations = false;

  double get _itemExtent => widget.cardWidth + _gap;
  double get _cycleExtent => _itemExtent * PostCategory.ordered.length;
  double get _loopStartOffset => _cycleExtent * _initialCycle;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(initialScrollOffset: _loopStartOffset);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations = MediaQuery.of(context).disableAnimations;
  }

  @override
  void didUpdateWidget(covariant _AutoScrollingPostCategoryRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardWidth != widget.cardWidth &&
        _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(_loopStartOffset);
      });
    }
  }

  void _onTick(Duration elapsed) {
    final previous = _lastElapsed;
    _lastElapsed = elapsed;
    if (previous == null ||
        _isUserScrolling ||
        !_scrollController.hasClients ||
        _disableAnimations) {
      return;
    }

    final elapsedMicros =
        (elapsed - previous).inMicroseconds.clamp(0, 50000).toDouble();
    var target = _scrollController.offset +
        (_pixelsPerSecond * elapsedMicros / Duration.microsecondsPerSecond);

    final loopEnd = _loopStartOffset + _cycleExtent;
    if (target < _loopStartOffset || target >= loopEnd) {
      final unwrapped = (target - _loopStartOffset) % _cycleExtent;
      final relative = (unwrapped + _cycleExtent) % _cycleExtent;
      target = _loopStartOffset + relative;
    }

    final position = _scrollController.position;
    _scrollController.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _isUserScrolling = true;
    } else if (notification is ScrollEndNotification) {
      _isUserScrolling = false;
    }
    return false;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoryCount = PostCategory.ordered.length;
    return SizedBox(
      height: widget.height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          widget.horizontalPadding,
          5,
          widget.horizontalPadding,
          9,
        ),
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            itemExtent: _itemExtent,
            itemCount: categoryCount * _repeatedCycles,
            itemBuilder: (context, index) {
              final category = PostCategory.ordered[index % categoryCount];
              return Padding(
                padding: const EdgeInsets.only(right: _gap),
                child: SizedBox(
                  height: widget.cardHeight,
                  child: PostCategoryTile(
                    category: category,
                    contentPadding: widget.contentPadding,
                    iconSize: widget.iconSize,
                    titleSize: widget.titleSize,
                    descriptionSize: widget.descriptionSize,
                    onTap: () => widget.onSelected(category),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
