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
import '../utils/logger.dart';
import 'snapshot_author_profile_image.dart';
import 'snapshot_storage_image.dart';
import 'snapshot_strings.dart';
import '../l10n/ui_locale.dart';

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
      fontSize: 14,
      height: 1.28,
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stream = _service.watchVisibleSnapshots();
  }

  @override
  void dispose() {
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
        MaterialPageRoute(
          builder: (_) => SnapshotDetailScreen(
            snapshots: snapshots,
            initialIndex: index,
          ),
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
          child: StreamBuilder<List<SnapshotItem>>(
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
              final visibleItems = <SnapshotItem>[
                ...latestVisibleItems,
                ...olderVisibleItems,
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
                              key: ValueKey<String>(
                                'my-snack-${own?.id ?? 'empty'}',
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
                      return Directionality(
                        key: ValueKey<String>('snack-tile-${item.id}'),
                        textDirection: pageTextDirection,
                        child: _SnapshotTile(
                          layout: layout,
                          previewDecodeWidth: _previewDecodeWidth,
                          profileDecodeWidth: profileDecodeWidth,
                          snapshot: item,
                          label: item.authorName,
                          onTap: () => _open(viewerItems, sourceIndex),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _SnapshotTile extends StatelessWidget {
  const _SnapshotTile({
    required this.layout,
    required this.previewDecodeWidth,
    required this.profileDecodeWidth,
    required this.snapshot,
    required this.label,
    required this.onTap,
  });

  final SnackPreviewLayout layout;
  final int previewDecodeWidth;
  final int profileDecodeWidth;
  final SnapshotItem snapshot;
  final String label;
  final VoidCallback onTap;

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
              child: Container(
                width: profileSize + 2,
                height: profileSize + 2,
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
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                style: nameStyle,
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
