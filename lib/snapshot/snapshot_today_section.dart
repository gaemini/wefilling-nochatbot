import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import '../screens/create_snapshot_screen.dart';
import '../screens/snapshot_detail_screen.dart';
import '../services/snapshot_service.dart';
import '../services/user_info_cache_service.dart';
import '../ui/widgets/user_avatar.dart';
import '../ui/widgets/motion_press.dart';
import '../utils/logger.dart';
import 'snapshot_author_profile_image.dart';
import 'snack_feel_icon.dart';
import 'snapshot_seen_store.dart';
import 'snapshot_storage_image.dart';
import 'snapshot_strings.dart';
import '../l10n/ui_locale.dart';
import '../design/tokens.dart';

const BorderRadius _snackCardRadius = BorderRadius.all(Radius.circular(12));
const Color _snackNeutralBackground = Color(0xFFF3F4F6);
const Color _snackTrayBackground = Colors.white;
const double _snackCardSpacing = 8;
const double _snackVerticalPadding = 12;

/// The tray width comes from its parent, not the device's full screen width.
/// The information area grows with the measured, locale-aware My Snack label.
class SnackPreviewLayout {
  const SnackPreviewLayout({
    required this.cardWidth,
    required this.cardHeight,
    required this.myInfoHeight,
  });

  final double cardWidth;
  final double cardHeight;
  final double myInfoHeight;
  double get myImageHeight => cardHeight - myInfoHeight;
  double get sectionHeight => cardHeight + _snackVerticalPadding * 2;

  static double widthFor(double availableWidth, double horizontalPadding) {
    final preferred = (availableWidth * .265).clamp(92.0, 120.0).toDouble();
    return math.min(
        preferred, math.max(1.0, availableWidth - 2 * horizontalPadding));
  }

  static SnackPreviewLayout resolve({
    required double cardWidth,
    required double viewportHeight,
    required double myLabelHeight,
    required bool landscape,
  }) {
    final compact = landscape || viewportHeight < 620;
    final aspectHeight = cardWidth * 16 / 9;
    final targetHeight = compact ? math.min(aspectHeight, 150.0) : aspectHeight;
    final infoHeight = math.max(targetHeight * .30, myLabelHeight + 38);
    final minimumImageHeight =
        compact ? (myLabelHeight > 40 ? 90.0 : 70.0) : cardWidth * .9;
    return SnackPreviewLayout(
      cardWidth: cardWidth,
      cardHeight: math.max(targetHeight, infoHeight + minimumImageHeight),
      myInfoHeight: infoHeight,
    );
  }
}

TextStyle _snackLabelStyle(BuildContext context, Color color) => TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
      color: color,
    );

String _restrictedSnackDescription(BuildContext context) => isChineseUi(context)
    ? '部分人可见的限时动态'
    : Localizations.localeOf(context).languageCode == 'ko'
        ? '공개 범위가 제한된 스낵'
        : 'Limited audience snack';

String _restrictedSnackBadgeLabel(BuildContext context) => isChineseUi(context)
    ? '部分可见'
    : Localizations.localeOf(context).languageCode == 'ko'
        ? '제한 공개'
        : 'Limited';

class SnapshotTodaySection extends StatefulWidget {
  const SnapshotTodaySection({super.key});

  @override
  State<SnapshotTodaySection> createState() => _SnapshotTodaySectionState();
}

class _SnapshotTodaySectionState extends State<SnapshotTodaySection>
    with WidgetsBindingObserver {
  static const int _previewWarmupLimit = 5;
  static const int _previewWarmupConcurrency = 2;
  final SnapshotService _service = SnapshotService.instance;
  final UserInfoCacheService _userInfoService = UserInfoCacheService();
  final ScrollController _trayController = ScrollController(
    keepScrollOffset: false,
  );
  late Stream<List<SnapshotItem>> _stream;
  String? _positionedUid;
  String? _previewUserId;
  List<SnapshotItem> _latestPreviewItems = const <SnapshotItem>[];
  final List<SnapshotItem> _previewQueue = <SnapshotItem>[];
  final Set<String> _queuedPreviewKeys = <String>{};
  final Set<String> _preparedPreviewKeys = <String>{};
  final Map<String, DateTime> _previewRetryAfter = <String, DateTime>{};
  final List<SnapshotAuthorProfile> _profileQueue = <SnapshotAuthorProfile>[];
  final Set<String> _queuedProfileKeys = <String>{};
  final Set<String> _preparedProfileKeys = <String>{};
  final Map<String, DateTime> _profileRetryAfter = <String, DateTime>{};
  final List<SnapshotItem> _videoCacheQueue = <SnapshotItem>[];
  final Set<String> _queuedVideoCacheKeys = <String>{};
  final Set<String> _preparedVideoCacheKeys = <String>{};
  final Map<String, DateTime> _videoCacheRetryAfter = <String, DateTime>{};
  int _activePreviewWarmups = 0;
  int _activeProfileWarmups = 0;
  int _activeVideoCacheWarmups = 0;
  int _previewGeneration = 0;
  int _previewDecodeWidth = 256;
  bool _appActive = true;
  bool _sectionVisible = true;
  bool _detailOpen = false;
  // 모션 2부 G: 타일 위치(열기·닫기 전환), 새로 생긴 타일만 등장 애니메이션.
  final Map<String, GlobalKey> _tileKeys = <String, GlobalKey>{};
  final Map<String, String> _tileAuthors = <String, String>{};
  Set<String>? _knownTileIds;
  Set<String> _enteringTileIds = const <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stream = _service.watchVisibleSnapshots();
    unawaited(SnapshotSeenStore.instance.ensureLoaded());
    // 서로 필링한 사람의 스낵을 맨 앞에 두기 위해 목록을 한 번 받아 둔다.
    _service.mutualFeels.addListener(_handleMutualFeelsChanged);
    _mutualIds = _service.mutualFeels.value.map((m) => m.otherUserId).toSet();
    unawaited(_service.refreshMutualFeels());
  }

  Set<String> _mutualIds = const <String>{};

  void _handleMutualFeelsChanged() {
    if (!mounted) return;
    final next = _service.mutualFeels.value.map((m) => m.otherUserId).toSet();
    if (next.length == _mutualIds.length && next.containsAll(_mutualIds)) {
      return;
    }
    setState(() => _mutualIds = next);
  }

  @override
  void dispose() {
    _service.mutualFeels.removeListener(_handleMutualFeelsChanged);
    WidgetsBinding.instance.removeObserver(this);
    _previewGeneration++;
    _previewQueue.clear();
    _queuedPreviewKeys.clear();
    _profileQueue.clear();
    _queuedProfileKeys.clear();
    _videoCacheQueue.clear();
    _queuedVideoCacheKeys.clear();
    unawaited(_service.cancelVideoPreloads());
    _trayController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive) {
      _previewQueue.clear();
      _queuedPreviewKeys.clear();
      _profileQueue.clear();
      _queuedProfileKeys.clear();
      _videoCacheQueue.clear();
      _queuedVideoCacheKeys.clear();
      unawaited(_service.cancelVideoPreloads());
      return;
    }
    _schedulePreviewWarmup(
      _latestPreviewItems,
      _previewUserId ?? '',
      sectionVisible: _sectionVisible,
    );
    unawaited(_service.refreshServerClock());
    unawaited(_service.syncMyFeed());
  }

  String _previewKey(String uid, SnapshotItem item) {
    final source = item.imageStoragePath.trim().isNotEmpty
        ? item.imageStoragePath.trim()
        : item.imageUrl.trim();
    return '$uid::${item.id}::$source';
  }

  String _videoCacheKey(String uid, SnapshotItem item) =>
      '$uid::${item.id}::${item.videoStoragePath.trim()}';

  void _schedulePreviewWarmup(
    List<SnapshotItem> items,
    String uid, {
    required bool sectionVisible,
  }) {
    _latestPreviewItems = items;
    if (_previewUserId != uid) {
      _previewUserId = uid;
      _previewGeneration++;
      _activePreviewWarmups = 0;
      _previewQueue.clear();
      _queuedPreviewKeys.clear();
      _preparedPreviewKeys.clear();
      _previewRetryAfter.clear();
      _activeProfileWarmups = 0;
      _profileQueue.clear();
      _queuedProfileKeys.clear();
      _preparedProfileKeys.clear();
      _profileRetryAfter.clear();
      _activeVideoCacheWarmups = 0;
      _videoCacheQueue.clear();
      _queuedVideoCacheKeys.clear();
      _preparedVideoCacheKeys.clear();
      _videoCacheRetryAfter.clear();
    }
    if (!_appActive || !sectionVisible || uid.isEmpty || _detailOpen) {
      _previewQueue.clear();
      _queuedPreviewKeys.clear();
      _profileQueue.clear();
      _queuedProfileKeys.clear();
      _videoCacheQueue.clear();
      _queuedVideoCacheKeys.clear();
      return;
    }
    unawaited(
      _service
          .preloadMyReactionStates(items.take(_previewWarmupLimit))
          .then<void>(
            (_) {},
            onError: (Object _, StackTrace __) {},
          ),
    );
    final previewItems =
        items.take(_previewWarmupLimit).toList(growable: false);
    for (final item in previewItems) {
      // The feed has already applied audience, block, and expiry filters.
      // Warming restricted media only fills this account's private cache; the
      // home tile continues to render the profile/ring instead of the media.
      final key = _previewKey(uid, item);
      final retryAfter = _previewRetryAfter[key];
      if (_preparedPreviewKeys.contains(key) ||
          (retryAfter != null && DateTime.now().isBefore(retryAfter)) ||
          !_queuedPreviewKeys.add(key)) {
        continue;
      }
      _previewQueue.add(item);
    }
    final newVideoItems = <SnapshotItem>[];
    for (final item in previewItems) {
      if (!item.isVideo || item.videoStoragePath.trim().isEmpty) continue;
      final key = _videoCacheKey(uid, item);
      final retryAfter = _videoCacheRetryAfter[key];
      if (_preparedVideoCacheKeys.contains(key) ||
          (retryAfter != null && DateTime.now().isBefore(retryAfter)) ||
          !_queuedVideoCacheKeys.add(key)) {
        continue;
      }
      newVideoItems.add(item);
    }
    // A newly arrived Snack is prepared before older queued work. An active
    // download is left intact so already transferred bytes are not discarded.
    _videoCacheQueue.insertAll(0, newVideoItems);
    final uniqueProfiles = <String, SnapshotAuthorProfile>{};
    for (final item in previewItems) {
      final profile = SnapshotAuthorProfile.resolve(item);
      // Items are newest-first. One author may own several of the five
      // entries, so prepare only that author's newest resolved profile.
      uniqueProfiles.putIfAbsent(profile.userId, () => profile);
    }
    for (final profile in uniqueProfiles.values) {
      final key = '$uid::${profile.cacheKey}';
      final retryAfter = _profileRetryAfter[key];
      if (_preparedProfileKeys.contains(key) ||
          (retryAfter != null && DateTime.now().isBefore(retryAfter)) ||
          !_queuedProfileKeys.add(key)) {
        continue;
      }
      _profileQueue.add(profile);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pumpPreviewWarmups();
      _pumpProfileWarmups();
      _pumpVideoCacheWarmups();
    });
  }

  void _pumpPreviewWarmups() {
    if (!mounted || !_appActive) return;
    while (_activePreviewWarmups < _previewWarmupConcurrency &&
        _previewQueue.isNotEmpty) {
      final item = _previewQueue.removeAt(0);
      final uid = _previewUserId ?? '';
      final key = _previewKey(uid, item);
      final generation = _previewGeneration;
      _activePreviewWarmups++;
      unawaited(_preparePreview(item).then<void>((success) {
        if (!mounted || generation != _previewGeneration) return;
        _activePreviewWarmups--;
        _queuedPreviewKeys.remove(key);
        if (success) {
          _preparedPreviewKeys.add(key);
          _previewRetryAfter.remove(key);
        } else {
          _previewRetryAfter[key] =
              DateTime.now().add(const Duration(seconds: 15));
        }
        _pumpPreviewWarmups();
      }, onError: (Object _, StackTrace __) {
        if (!mounted || generation != _previewGeneration) return;
        _activePreviewWarmups--;
        _queuedPreviewKeys.remove(key);
        _previewRetryAfter[key] =
            DateTime.now().add(const Duration(seconds: 15));
        _pumpPreviewWarmups();
      }));
    }
  }

  Future<bool> _preparePreview(SnapshotItem item) async {
    final stopwatch = Stopwatch()..start();
    final bytes = await _service.loadImageBytes(item);
    if (!mounted) return false;
    final decodeWidth = _previewDecodeWidth;
    var decodeFailed = false;
    await precacheImage(
      snapshotMemoryImageProvider(bytes, cacheWidth: decodeWidth),
      context,
      onError: (Object _, StackTrace? __) => decodeFailed = true,
    );
    if (Logger.isVerboseEnabled) {
      Logger.log(
        '스낵 목록 썸네일 준비 '
        '(snapshotId=${item.id}, success=${!decodeFailed}, '
        'decodeWidth=$decodeWidth, elapsedMs=${stopwatch.elapsedMilliseconds})',
      );
    }
    return !decodeFailed;
  }

  void _pumpVideoCacheWarmups() {
    if (!mounted || !_appActive || _detailOpen) return;
    if (_activeVideoCacheWarmups > 0 || _videoCacheQueue.isEmpty) return;
    final item = _videoCacheQueue.removeAt(0);
    final uid = _previewUserId ?? '';
    final key = _videoCacheKey(uid, item);
    final generation = _previewGeneration;
    final stopwatch = Stopwatch()..start();
    _activeVideoCacheWarmups = 1;
    unawaited(
      _service.preloadVideoFile(item, cancelOtherPreloads: false).then<void>(
          (_) {
        if (!mounted || generation != _previewGeneration) return;
        _activeVideoCacheWarmups = 0;
        _queuedVideoCacheKeys.remove(key);
        _preparedVideoCacheKeys.add(key);
        _videoCacheRetryAfter.remove(key);
        if (Logger.isVerboseEnabled) {
          Logger.log(
            '스낵 홈 영상 캐시 준비 '
            '(snapshotId=${item.id}, success=true, '
            'elapsedMs=${stopwatch.elapsedMilliseconds})',
          );
        }
        _pumpVideoCacheWarmups();
      }, onError: (Object error, StackTrace __) {
        if (!mounted || generation != _previewGeneration) return;
        _activeVideoCacheWarmups = 0;
        _queuedVideoCacheKeys.remove(key);
        _videoCacheRetryAfter[key] =
            DateTime.now().add(const Duration(seconds: 30));
        if (Logger.isVerboseEnabled) {
          Logger.warning(
            '스낵 홈 영상 캐시 준비 실패 '
            '(snapshotId=${item.id}, errorType=${error.runtimeType}, '
            'elapsedMs=${stopwatch.elapsedMilliseconds})',
          );
        }
        _pumpVideoCacheWarmups();
      }),
    );
  }

  void _pumpProfileWarmups() {
    if (!mounted || !_appActive) return;
    while (_activeProfileWarmups < _previewWarmupConcurrency &&
        _profileQueue.isNotEmpty) {
      final profile = _profileQueue.removeAt(0);
      final uid = _previewUserId ?? '';
      final key = '$uid::${profile.cacheKey}';
      final generation = _previewGeneration;
      _activeProfileWarmups++;
      unawaited(prefetchSnapshotAuthorProfile(profile).then<void>((success) {
        if (!mounted || generation != _previewGeneration) return;
        _activeProfileWarmups--;
        _queuedProfileKeys.remove(key);
        if (success) {
          _preparedProfileKeys.add(key);
          _profileRetryAfter.remove(key);
        } else {
          _profileRetryAfter[key] =
              DateTime.now().add(const Duration(seconds: 15));
        }
        _pumpProfileWarmups();
      }, onError: (Object _, StackTrace __) {
        if (!mounted || generation != _previewGeneration) return;
        _activeProfileWarmups--;
        _queuedProfileKeys.remove(key);
        _profileRetryAfter[key] =
            DateTime.now().add(const Duration(seconds: 15));
        _pumpProfileWarmups();
      }));
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateSnapshotScreen()),
    );
    if (created == true) _showMySnack();
  }

  void _showMySnack() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_trayController.hasClients) return;
      final start = _trayController.position.minScrollExtent;
      if ((_trayController.offset - start).abs() < .5) return;
      _trayController.animateTo(
        start,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _ensureInitialMySnackPosition(String uid) {
    if (_positionedUid == uid) return;
    _positionedUid = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_trayController.hasClients) return;
      _trayController.jumpTo(_trayController.position.minScrollExtent);
    });
  }

  void _retry() {
    setState(() => _stream = _service.watchVisibleSnapshots());
    unawaited(_service.syncMyFeed());
  }

  Future<void> _open(List<SnapshotItem> snapshots, int index) async {
    final selectedId =
        index >= 0 && index < snapshots.length ? snapshots[index].id : '';
    _detailOpen = true;
    _videoCacheQueue.clear();
    _queuedVideoCacheKeys.clear();
    unawaited(
      _service.cancelVideoPreloads(
        exceptSnapshotIds:
            selectedId.isEmpty ? const <String>{} : <String>{selectedId},
      ),
    );
    try {
      await Navigator.of(context).push<void>(
        SnapshotDetailMotionRoute(
          snapshots: snapshots,
          initialIndex: index,
          originRect: selectedId.isEmpty ? null : _tileRect(selectedId),
          resolveCloseRect: _closeRectFor,
        ),
      );
    } finally {
      if (mounted) {
        _detailOpen = false;
        _schedulePreviewWarmup(
          _latestPreviewItems,
          _previewUserId ?? '',
          sectionVisible: _sectionVisible,
        );
      }
    }
  }

  /// 화면에 보이는 타일의 전역 위치. 트레이가 화면 밖이거나 타일이 없으면 null.
  Rect? _tileRect(String snapshotId) {
    final box = _tileKeys[snapshotId]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    final visible = rect.intersect(screen);
    if (visible.width < rect.width * .5 || visible.height < rect.height * .5) {
      return null;
    }
    return rect;
  }

  /// 닫힐 자리: 지금 스낵의 타일, 없으면 같은 작성자의 타일.
  Rect? _closeRectFor(SnapshotItem current) {
    if (!mounted) return null;
    final direct = _tileRect(current.id);
    if (direct != null) return direct;
    for (final entry in _tileAuthors.entries) {
      if (entry.value == current.authorId) {
        final rect = _tileRect(entry.key);
        if (rect != null) return rect;
      }
    }
    return null;
  }

  /// 처음 그릴 때·다시 불러올 때는 등장 애니메이션 없이, 새로 생긴 id만 고른다.
  void _trackEnteringTiles(List<SnapshotItem> items) {
    final ids = items.map((item) => item.id).toSet();
    final known = _knownTileIds;
    _knownTileIds = ids;
    if (known == null) return;
    final entering = ids.difference(known);
    if (entering.isNotEmpty) _enteringTileIds = entering;
  }

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final pageTextDirection = Directionality.of(context);
    final sectionVisible = TickerMode.valuesOf(context).enabled;
    _sectionVisible = sectionVisible;
    _ensureInitialMySnackPosition(uid);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = MediaQuery.sizeOf(context);
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : viewport.width;
        const horizontal = _snackCardSpacing;
        var cardWidth = SnackPreviewLayout.widthFor(availableWidth, horizontal);
        final labelStyle = _snackLabelStyle(context, const Color(0xFF111827));
        final textScaler = MediaQuery.textScalerOf(context);
        final fullLabelPainter = TextPainter(
          text: TextSpan(text: strings.mySnapshot, style: labelStyle),
          textDirection: pageTextDirection,
          textScaler: textScaler,
          maxLines: 1,
        )..layout();
        if (fullLabelPainter.width > cardWidth - 16) {
          cardWidth = math.min(
            math.min(180.0, math.max(1.0, availableWidth - 2 * horizontal)),
            math.max(cardWidth, fullLabelPainter.width / 2 + 22),
          );
        }
        fullLabelPainter.dispose();
        var labelPainter = TextPainter(
          text: TextSpan(
            text: strings.mySnapshot,
            style: labelStyle,
          ),
          textDirection: pageTextDirection,
          textScaler: textScaler,
          maxLines: 2,
        )..layout(maxWidth: math.max(1.0, cardWidth - 16));
        final maximumReadableWidth =
            math.min(180.0, math.max(1.0, availableWidth - 2 * horizontal));
        if (labelPainter.didExceedMaxLines &&
            cardWidth < maximumReadableWidth) {
          labelPainter.dispose();
          cardWidth = maximumReadableWidth;
          labelPainter = TextPainter(
            text: TextSpan(text: strings.mySnapshot, style: labelStyle),
            textDirection: pageTextDirection,
            textScaler: textScaler,
            maxLines: 2,
          )..layout(maxWidth: math.max(1.0, cardWidth - 16));
        }
        final layout = SnackPreviewLayout.resolve(
          cardWidth: cardWidth,
          viewportHeight: viewport.height,
          myLabelHeight: labelPainter.height,
          landscape: viewport.width > viewport.height,
        );
        labelPainter.dispose();
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        _previewDecodeWidth =
            (layout.cardWidth * devicePixelRatio).ceil().clamp(72, 512);
        final profileSize = layout.cardWidth < 96 ? 32.0 : 36.0;
        final profileDecodeWidth =
            (profileSize * devicePixelRatio).ceil().clamp(48, 256);

        return ColoredBox(
          color: _snackTrayBackground,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StreamBuilder<List<SnapshotItem>>(
            stream: _stream,
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <SnapshotItem>[];
              _schedulePreviewWarmup(
                items,
                uid,
                sectionVisible: sectionVisible,
              );
              // The service is newest-first. The first pass keeps the newest snack
              // from each author at the front of the tray. Older snacks follow in
              // chronological order, so the initial viewport stays useful while a
              // horizontal swipe continues through older active snacks.
              final latestByAuthor = <String, SnapshotItem>{};
              for (final item in items) {
                latestByAuthor.putIfAbsent(item.authorId, () => item);
              }
              final trayItems = latestByAuthor.values.toList(growable: false);
              final own = latestByAuthor[uid];
              final latestVisibleItems = trayItems
                  .where((item) => item.authorId != uid)
                  .toList(growable: false);
              final latestVisibleIds =
                  latestVisibleItems.map((item) => item.id).toSet();
              final olderVisibleItems = items
                  .where(
                    (item) =>
                        item.authorId != uid &&
                        !latestVisibleIds.contains(item.id),
                  )
                  .toList(growable: false);
              // 서로 필링한 사람의 스낵은 내 스낵 다음 맨 앞(순서는 안정 정렬).
              final visibleItems = <SnapshotItem>[
                ...latestVisibleItems.where(
                  (item) => _mutualIds.contains(item.authorId),
                ),
                ...olderVisibleItems.where(
                  (item) => _mutualIds.contains(item.authorId),
                ),
                ...latestVisibleItems.where(
                  (item) => !_mutualIds.contains(item.authorId),
                ),
                ...olderVisibleItems.where(
                  (item) => !_mutualIds.contains(item.authorId),
                ),
              ];

              // The viewer always starts with My Snack when it exists, then walks
              // through every remaining snack newest-first. This list is also used
              // for tile taps so the tray and left/right navigation never disagree.
              final viewerItems = <SnapshotItem>[
                if (own != null) own,
                ...items.where((item) => item.id != own?.id),
              ];
              final ownIndex = own == null ? -1 : 0;
              final loading =
                  snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData;
              final failed = snapshot.hasError && items.isEmpty;
              if (!loading && !failed) _trackEnteringTiles(visibleItems);

              return SizedBox(
                height: layout.sectionHeight,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: ListView.separated(
                    controller: _trayController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      horizontal,
                      _snackVerticalPadding,
                      horizontal,
                      _snackVerticalPadding,
                    ),
                    itemCount: 1 +
                        (loading ? 3 : visibleItems.length) +
                        (failed ? 1 : 0),
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: _snackCardSpacing),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Directionality(
                          textDirection: pageTextDirection,
                          child: StreamBuilder<DMUserInfo?>(
                            stream: uid.isEmpty
                                ? null
                                : _userInfoService.watchUserInfo(uid),
                            initialData: uid.isEmpty
                                ? null
                                : _userInfoService.getCachedUserInfo(uid),
                            builder: (context, profileSnapshot) => _MySnackTile(
                              key: own == null
                                  ? const ValueKey<String>('my-snack-empty')
                                  : _tileKeys.putIfAbsent(
                                      own.id,
                                      () => GlobalKey(
                                        debugLabel: 'my-snack-${own.id}',
                                      ),
                                    ),
                              snapshot: own,
                              layout: layout,
                              previewDecodeWidth: _previewDecodeWidth,
                              label: strings.mySnapshot,
                              uid: uid,
                              profilePhotoUrl: profileSnapshot.data?.photoURL ??
                                  FirebaseAuth.instance.currentUser?.photoURL ??
                                  '',
                              profilePhotoVersion:
                                  profileSnapshot.data?.photoVersion ?? 0,
                              onTap: own == null
                                  ? _create
                                  : () => _open(viewerItems, ownIndex),
                              onAdd: _create,
                            ),
                          ),
                        );
                      }
                      if (loading) {
                        return Directionality(
                          textDirection: pageTextDirection,
                          child: _SnackSkeleton(layout: layout),
                        );
                      }
                      if (failed) {
                        return Directionality(
                          textDirection: pageTextDirection,
                          child: _SnackActionTile(
                            layout: layout,
                            icon: Icons.refresh_rounded,
                            label: strings.retry,
                            onTap: _retry,
                          ),
                        );
                      }
                      final item = visibleItems[index - 1];
                      final sourceIndex = viewerItems
                          .indexWhere((candidate) => candidate.id == item.id);
                      _tileAuthors[item.id] = item.authorId;
                      return Directionality(
                        key: ValueKey<String>('snack-tile-${item.id}'),
                        textDirection: pageTextDirection,
                        child: _SnackTileEntrance(
                          animate: _enteringTileIds.contains(item.id),
                          child: _SnapshotTile(
                            key: _tileKeys.putIfAbsent(
                              item.id,
                              () => GlobalKey(
                                debugLabel: 'snack-tile-${item.id}',
                              ),
                            ),
                            layout: layout,
                            previewDecodeWidth: _previewDecodeWidth,
                            profileDecodeWidth: profileDecodeWidth,
                            snapshot: item,
                            label: item.authorName,
                            mutualFeel: _mutualIds.contains(item.authorId),
                            onTap: () => _open(viewerItems, sourceIndex),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 남은 시간 링: 채워진 비율 = 남은 시간 / 24시간. 본 스낵은 전체 회색.
/// [seenProgress] 0(안 봄) → 1(봄)으로 보간한다: 트랙 #D6E4F5 → #D4D4D4,
/// 포인트 호 투명도 1 → 0(모션 2부 G-2).
class _SnackRemainingRing extends CustomPainter {
  const _SnackRemainingRing({
    required this.fraction,
    required this.seenProgress,
  });

  final double fraction;
  final double seenProgress;

  static const double stroke = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final seen = seenProgress.clamp(0.0, 1.0);
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Color.lerp(
        const Color(0xFFD6E4F5),
        const Color(0xFFD4D4D4),
        seen,
      )!;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, track);
    if (seen >= 1) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = const Color(0xFF2C6BC0).withValues(alpha: 1 - seen);
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2 * fraction.clamp(0.02, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_SnackRemainingRing old) =>
      old.fraction != fraction || old.seenProgress != seenProgress;
}

/// 본 상태를 0 ↔ 1로 보간한다(medium). 보기 화면에 가려진 동안(TickerMode
/// 꺼짐)에는 바꾸지 않고, 돌아와 보일 때 바뀌는 모습이 보이게 한다.
class _SeenTween extends StatefulWidget {
  const _SeenTween({required this.snapshotId, required this.builder});

  final String snapshotId;
  final Widget Function(BuildContext context, double seenProgress) builder;

  @override
  State<_SeenTween> createState() => _SeenTweenState();
}

class _SeenTweenState extends State<_SeenTween> {
  bool? _shownSeen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SnapshotSeenStore.instance,
      builder: (context, _) {
        final seen = SnapshotSeenStore.instance.isSeen(widget.snapshotId);
        final visible = TickerMode.valuesOf(context).enabled;
        if (_shownSeen == null || visible) _shownSeen = seen;
        final target = _shownSeen! ? 1.0 : 0.0;
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: target),
          duration: MotionTokens.of(context, MotionTokens.medium),
          curve: MotionTokens.curve,
          builder: (context, value, _) => widget.builder(context, value),
        );
      },
    );
  }
}

/// 새로 생긴 타일만 0.6 → 1 크기 + 투명도로 나타나고(medium), 자리는 state
/// 동안 벌어져 뒤 타일들이 밀린다(모션 2부 G-3).
class _SnackTileEntrance extends StatefulWidget {
  const _SnackTileEntrance({required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  State<_SnackTileEntrance> createState() => _SnackTileEntranceState();
}

class _SnackTileEntranceState extends State<_SnackTileEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null || !widget.animate) return;
    if (MotionTokens.reduceMotion(context)) return;
    _controller = AnimationController(
      vsync: this,
      duration: MotionTokens.medium,
    )..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    final spaceEnd =
        MotionTokens.state.inMicroseconds / MotionTokens.medium.inMicroseconds;
    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final t = controller.value;
        final space = MotionTokens.curve.transform((t / spaceEnd).clamp(0, 1));
        final grow = MotionTokens.curve.transform(t);
        return Align(
          key: const ValueKey('snack_tile_entrance'),
          alignment: Alignment.centerLeft,
          widthFactor: space,
          child: Opacity(
            opacity: grow,
            child: Transform.scale(scale: .6 + .4 * grow, child: child),
          ),
        );
      },
    );
  }
}

/// 남은 비율(0~1). 24시간을 기준으로 한다.
@visibleForTesting
double snackRemainingFraction(Duration remaining) =>
    (remaining.inSeconds / const Duration(hours: 24).inSeconds)
        .clamp(0.0, 1.0)
        .toDouble();

class _SnapshotTile extends StatelessWidget {
  const _SnapshotTile({
    super.key,
    required this.layout,
    required this.previewDecodeWidth,
    required this.profileDecodeWidth,
    required this.snapshot,
    required this.label,
    required this.onTap,
    this.mutualFeel = false,
  });

  final SnackPreviewLayout layout;
  final int previewDecodeWidth;
  final int profileDecodeWidth;
  final SnapshotItem snapshot;
  final String label;
  final VoidCallback onTap;

  /// 나와 서로 필링한 사람의 스낵이면 링 아래에 필링 배지를 단다.
  final bool mutualFeel;

  @override
  Widget build(BuildContext context) {
    final isRestricted = snapshot.visibility != SnapshotVisibility.public;
    final profile = SnapshotAuthorProfile.resolve(snapshot);
    final profileSize = layout.cardWidth < 96 ? 32.0 : 36.0;
    final nameStyle = _snackLabelStyle(
      context,
      isRestricted ? const Color(0xFF111827) : Colors.white,
    );
    return _SnackTileShell(
      layout: layout,
      semanticLabel: isRestricted
          ? '$label, ${_restrictedSnackDescription(context)}'
          : label,
      onTap: onTap,
      child: Stack(
        children: [
          Positioned.fill(
            child: isRestricted
                ? _RestrictedSnackArtwork(
                    profile: profile,
                    width: layout.cardWidth,
                    height: layout.cardHeight,
                    reserveBottomName: true,
                  )
                : SnapshotStorageImage(
                    snapshot: snapshot,
                    decodeWidth: previewDecodeWidth,
                  ),
          ),
          if (!isRestricted)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: math.min(
                layout.cardHeight,
                math.max(
                  layout.cardHeight * .40,
                  MediaQuery.textScalerOf(context).scale(14) * 2.56 + 20,
                ),
              ),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xB3000000)],
                  ),
                ),
              ),
            ),
          if (!isRestricted)
            Positioned(
              top: 8,
              left: 8,
              child: _SeenTween(
                snapshotId: snapshot.id,
                builder: (context, seenProgress) {
                  final fraction = snackRemainingFraction(
                    snapshot.remainingAt(SnapshotService.instance.serverNow),
                  );
                  final outer = profileSize + 2 + _SnackRemainingRing.stroke * 2;
                  final ring = CustomPaint(
                    key: ValueKey<String>('snack-ring-${snapshot.id}'),
                    painter: _SnackRemainingRing(
                      fraction: fraction,
                      seenProgress: seenProgress,
                    ),
                    child: Container(
                      width: outer,
                      height: outer,
                      padding: const EdgeInsets.all(_SnackRemainingRing.stroke),
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: _SnackAuthorProfilePreview(
                          profile: profile,
                          size: profileSize,
                          decodeWidth: profileDecodeWidth,
                        ),
                      ),
                    ),
                  );
                  if (!mutualFeel) return ring;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ring,
                      Positioned(
                        left: outer / 2 - 10,
                        bottom: -8,
                        child: Container(
                          key: ValueKey<String>('mutual-badge-${snapshot.id}'),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2C6BC0),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Center(
                            child: SnackFeelIcon(size: 12, filled: true),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          if (!isRestricted && snapshot.isVideo)
            const Align(
              alignment: Alignment.center,
              child: Icon(
                Icons.play_circle_outline_rounded,
                size: 28,
                color: Colors.white,
              ),
            ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 10,
            child: ExcludeSemantics(
              // 본 뒤에는 이름이 흐려지고 굵기 600 → 500(같은 보간 값).
              child: _SeenTween(
                snapshotId: snapshot.id,
                builder: (context, seenProgress) => Opacity(
                  opacity: 1 - .3 * seenProgress,
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    style: nameStyle.copyWith(
                      fontWeight: FontWeight.lerp(
                        FontWeight.w600,
                        FontWeight.w500,
                        seenProgress,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestrictedSnackArtwork extends StatelessWidget {
  const _RestrictedSnackArtwork({
    required this.profile,
    required this.width,
    required this.height,
    required this.reserveBottomName,
  });

  final SnapshotAuthorProfile profile;
  final double width;
  final double height;
  final bool reserveBottomName;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final topReserve = math.max(32.0, scaler.scale(11) * 1.25 + 16);
    final bottomReserve = reserveBottomName
        ? math.min(height * .52, scaler.scale(14) * 2.56 + 10)
        : 0.0;
    final avatarSpace = math.max(12.0, height - topReserve - bottomReserve);
    final avatarSize = math.min(68.0, math.min(width * .62, avatarSpace));
    final avatarTop = topReserve + math.max(0, (avatarSpace - avatarSize) / 2);
    final decodeWidth = (avatarSize * MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(48, 256);
    return ColoredBox(
      color: _snackNeutralBackground,
      child: Stack(
        children: [
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Row(
              children: [
                const Icon(Icons.people_outline_rounded,
                    size: 14, color: Color(0xFF475467)),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    _restrictedSnackBadgeLabel(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF475467),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: avatarTop,
            left: (width - avatarSize) / 2,
            child: _SnackAuthorProfilePreview(
              profile: profile,
              size: avatarSize,
              decodeWidth: decodeWidth,
            ),
          ),
        ],
      ),
    );
  }
}

class _MySnackTile extends StatelessWidget {
  const _MySnackTile({
    super.key,
    required this.layout,
    required this.previewDecodeWidth,
    required this.snapshot,
    required this.label,
    required this.uid,
    required this.profilePhotoUrl,
    required this.profilePhotoVersion,
    required this.onTap,
    required this.onAdd,
  });

  final SnackPreviewLayout layout;
  final int previewDecodeWidth;
  final SnapshotItem? snapshot;
  final String label;
  final String uid;
  final String profilePhotoUrl;
  final int profilePhotoVersion;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final story = snapshot;
    final ownProfile = story == null
        ? SnapshotAuthorProfile(
            userId: uid,
            photoUrl: profilePhotoUrl,
            photoVersion: profilePhotoVersion,
          )
        : profilePhotoUrl.trim().isNotEmpty
            ? SnapshotAuthorProfile(
                userId: uid,
                photoUrl: profilePhotoUrl,
                photoVersion: profilePhotoVersion,
              )
            : SnapshotAuthorProfile.resolve(story);
    return _SnackTileShell(
      layout: layout,
      semanticLabel:
          story != null && story.visibility != SnapshotVisibility.public
              ? '$label, ${_restrictedSnackDescription(context)}'
              : label,
      onTap: onTap,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: layout.myImageHeight,
            child: story == null
                ? _EmptySnackPreview(
                    uid: uid,
                    photoUrl: profilePhotoUrl,
                    photoVersion: profilePhotoVersion,
                    width: layout.cardWidth,
                    height: layout.myImageHeight,
                  )
                : story.visibility != SnapshotVisibility.public
                    ? _RestrictedSnackArtwork(
                        profile: ownProfile,
                        width: layout.cardWidth,
                        height: layout.myImageHeight,
                        reserveBottomName: false,
                      )
                    : SnapshotStorageImage(
                        snapshot: story,
                        decodeWidth: previewDecodeWidth,
                      ),
          ),
          Positioned(
            top: layout.myImageHeight,
            left: 0,
            right: 0,
            bottom: 0,
            child: const ColoredBox(color: Colors.white),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 10,
            child: ExcludeSemantics(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _snackLabelStyle(context, const Color(0xFF111827)),
              ),
            ),
          ),
          Positioned(
            top: layout.myImageHeight - 24,
            left: 8,
            child: Semantics(
              button: true,
              label: SnapshotStrings.of(context).createSnapshot,
              child: MotionPress(
                pressedScale: .91,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onAdd,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Color(0xFF344054),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SnackAuthorProfilePreview extends StatelessWidget {
  const _SnackAuthorProfilePreview({
    required this.profile,
    required this.size,
    required this.decodeWidth,
  });

  final SnapshotAuthorProfile profile;
  final double size;
  final int decodeWidth;

  @override
  Widget build(BuildContext context) {
    return SnapshotAuthorProfileImage(
      profile: profile,
      size: size,
      borderRadius: BorderRadius.circular(size / 2),
      decodeWidth: decodeWidth,
    );
  }
}

class _EmptySnackPreview extends StatelessWidget {
  const _EmptySnackPreview({
    required this.uid,
    required this.photoUrl,
    required this.photoVersion,
    required this.width,
    required this.height,
  });

  final String uid;
  final String photoUrl;
  final int photoVersion;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: _snackNeutralBackground,
        child: Center(
          child: UserAvatar(
            uid: uid,
            photoUrl: photoUrl,
            photoVersion: photoVersion,
            isAnonymous: false,
            size: math.min(68, math.min(width * .66, height * .70)),
            placeholderColor: _snackNeutralBackground,
            placeholderIcon: Icons.camera_alt_outlined,
            placeholderIconSize: 29,
          ),
        ),
      ),
    );
  }
}

class _SnackTileShell extends StatelessWidget {
  const _SnackTileShell({
    required this.layout,
    required this.semanticLabel,
    required this.onTap,
    required this.child,
  });

  final SnackPreviewLayout layout;
  final String semanticLabel;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      explicitChildNodes: true,
      onTap: onTap,
      child: SizedBox(
        width: layout.cardWidth,
        height: layout.cardHeight,
        child: MotionPress(
          pressedScale: .975,
          child: Material(
            color: _snackNeutralBackground,
            borderRadius: _snackCardRadius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              excludeFromSemantics: true,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _SnackActionTile extends StatelessWidget {
  const _SnackActionTile({
    required this.layout,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final SnackPreviewLayout layout;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SnackTileShell(
      layout: layout,
      semanticLabel: label,
      onTap: onTap,
      child: Stack(
        children: [
          Center(child: Icon(icon, size: 28, color: const Color(0xFF667085))),
          Positioned(
            left: 8,
            right: 8,
            bottom: 10,
            child: ExcludeSemantics(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _snackLabelStyle(context, const Color(0xFF111827)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SnackSkeleton extends StatelessWidget {
  const _SnackSkeleton({required this.layout});

  final SnackPreviewLayout layout;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: layout.cardWidth,
      height: layout.cardHeight,
      child: ClipRRect(
        borderRadius: _snackCardRadius,
        child: ColoredBox(
          color: const Color(0xFFF1F3F5),
          child: Stack(
            children: [
              Positioned(
                left: 8,
                right: 24,
                bottom: 13,
                child: SizedBox(
                  height: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
