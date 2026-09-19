import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import '../screens/create_snapshot_screen.dart';
import '../screens/snapshot_detail_screen.dart';
import '../services/snapshot_service.dart';
import '../services/user_info_cache_service.dart';
import '../ui/widgets/audience_ring.dart';
import '../ui/widgets/user_avatar.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';
import 'snapshot_author_profile_image.dart';
import 'snapshot_storage_image.dart';
import 'snapshot_strings.dart';
import '../l10n/ui_locale.dart';

const double _snackPreviewSize = 72;
const double _snackTileWidth = 74;
const double _snackBannerHeight = 108;
const BorderRadius _snackPreviewRadius = BorderRadius.all(
  Radius.circular(18),
);

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
    final decodeWidth =
        (_snackPreviewSize * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(72, 512);
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
    final horizontal = MediaQuery.sizeOf(context).width < 360 ? 12.0 : 16.0;
    final itemGap = context.rs(4).clamp(3, 6).toDouble();
    final sectionVisible = TickerMode.valuesOf(context).enabled;
    _sectionVisible = sectionVisible;
    _ensureInitialMySnackPosition(uid);

    return ColoredBox(
      color: Colors.white,
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
                    item.authorId != uid && !latestVisibleIds.contains(item.id),
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
          final loading = snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData;
          final failed = snapshot.hasError && items.isEmpty;

          return Column(
            children: [
              SizedBox(
                height: _snackBannerHeight,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: ListView.separated(
                    controller: _trayController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontal,
                      vertical: 4,
                    ),
                    itemCount: 1 +
                        (loading ? 3 : visibleItems.length) +
                        (failed ? 1 : 0),
                    separatorBuilder: (_, __) => SizedBox(width: itemGap),
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
                          child: const _SnackSkeleton(),
                        );
                      }
                      if (failed) {
                        return Directionality(
                          textDirection: pageTextDirection,
                          child: _SnackActionTile(
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
                          snapshot: item,
                          label: item.authorName,
                          onTap: () => _open(viewerItems, sourceIndex),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEAECF0)),
            ],
          );
        },
      ),
    );
  }
}

class _SnapshotTile extends StatelessWidget {
  const _SnapshotTile({
    required this.snapshot,
    required this.label,
    required this.onTap,
  });

  final SnapshotItem snapshot;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isRestricted = snapshot.visibility != SnapshotVisibility.public;
    final previewDecodeWidth =
        (_snackPreviewSize * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(72, 512);
    return _SnackTileShell(
      label: label,
      onTap: onTap,
      preview: isRestricted
          ? AudienceRing(
              restricted: true,
              size: _snackPreviewSize,
              borderRadius: _snackPreviewRadius,
              ringWidth: 4,
              innerGap: 1,
              // 전체 타일 크기는 그대로 유지하고 제한 공개 링의 바깥선이
              // 스낵 썸네일의 가장 바깥 경계에 정확히 닿도록 한다.
              ringInset: 0,
              emphasized: true,
              semanticLabel: (isChineseUi(context)
                  ? '部分人可见的限时动态'
                  : Localizations.localeOf(context).languageCode == 'ko'
                      ? '공개 범위가 제한된 스낵'
                      : 'Limited audience snack'),
              child: _SnackAuthorProfilePreview(
                profile: SnapshotAuthorProfile.resolve(snapshot),
              ),
            )
          : SizedBox.square(
              dimension: _snackPreviewSize,
              child: SnapshotStorageImage(
                snapshot: snapshot,
                borderRadius: _snackPreviewRadius,
                decodeWidth: previewDecodeWidth,
              ),
            ),
    );
  }
}

class _MySnackTile extends StatelessWidget {
  const _MySnackTile({
    super.key,
    required this.snapshot,
    required this.label,
    required this.uid,
    required this.profilePhotoUrl,
    required this.profilePhotoVersion,
    required this.onTap,
    required this.onAdd,
  });

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
    final previewDecodeWidth =
        (_snackPreviewSize * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(72, 512);
    return _SnackTileShell(
      label: label,
      onTap: onTap,
      expandToFitLabel: true,
      preview: SizedBox.square(
        dimension: _snackPreviewSize,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: story == null
                  ? _EmptySnackPreview(
                      uid: uid,
                      photoUrl: profilePhotoUrl,
                      photoVersion: profilePhotoVersion,
                    )
                  : story.visibility != SnapshotVisibility.public
                      ? AudienceRing(
                          restricted: true,
                          size: _snackPreviewSize,
                          borderRadius: _snackPreviewRadius,
                          ringWidth: 4,
                          innerGap: 1,
                          ringInset: 0,
                          emphasized: true,
                          semanticLabel: (isChineseUi(context)
                              ? '部分人可见的限时动态'
                              : Localizations.localeOf(context).languageCode ==
                                      'ko'
                                  ? '공개 범위가 제한된 스낵'
                                  : 'Limited audience snack'),
                          child: _SnackAuthorProfilePreview(
                            profile: profilePhotoUrl.trim().isNotEmpty
                                ? SnapshotAuthorProfile(
                                    userId: uid,
                                    photoUrl: profilePhotoUrl,
                                    photoVersion: profilePhotoVersion,
                                  )
                                : SnapshotAuthorProfile.resolve(story),
                          ),
                        )
                      : SnapshotStorageImage(
                          snapshot: story,
                          borderRadius: _snackPreviewRadius,
                          decodeWidth: previewDecodeWidth,
                        ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAdd,
                child: SizedBox.square(
                  dimension: 36,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D9CDB),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        size: 17,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SnackAuthorProfilePreview extends StatelessWidget {
  const _SnackAuthorProfilePreview({required this.profile});

  final SnapshotAuthorProfile profile;

  @override
  Widget build(BuildContext context) {
    final decodeWidth =
        (_snackPreviewSize * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(72, 512);
    return SnapshotAuthorProfileImage(
      profile: profile,
      size: _snackPreviewSize,
      borderRadius: _snackPreviewRadius,
      decodeWidth: decodeWidth,
    );
  }
}

class _EmptySnackPreview extends StatelessWidget {
  const _EmptySnackPreview({
    required this.uid,
    required this.photoUrl,
    required this.photoVersion,
  });

  final String uid;
  final String photoUrl;
  final int photoVersion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _snackPreviewSize,
      height: _snackPreviewSize,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFF3F4F6),
        borderRadius: _snackPreviewRadius,
      ),
      child: UserAvatar(
        uid: uid,
        photoUrl: photoUrl,
        photoVersion: photoVersion,
        isAnonymous: false,
        size: 58,
        placeholderColor: const Color(0xFFF3F4F6),
        placeholderIcon: Icons.camera_alt_outlined,
        placeholderIconSize: 29,
      ),
    );
  }
}

class _SnackTileShell extends StatelessWidget {
  const _SnackTileShell({
    required this.label,
    required this.onTap,
    required this.preview,
    this.expandToFitLabel = false,
  });

  final String label;
  final VoidCallback onTap;
  final Widget preview;
  final bool expandToFitLabel;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context).clamp(
      maxScaleFactor: 1.15,
    );
    final labelStyle = TextStyle(
      // Preserve every existing snack label exactly; only My Snack opts into
      // the locale-aware family needed to measure/render its Chinese label.
      fontFamily: expandToFitLabel ? uiFontFamily(context, 'Inter') : 'Inter',
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: 13,
      height: 1.25,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF111827),
    );
    var tileWidth = _snackTileWidth;
    if (expandToFitLabel) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout();
      tileWidth = (painter.width + 4).clamp(_snackTileWidth, 140.0).toDouble();
      painter.dispose();
    }
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: SizedBox(
            width: tileWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: _snackTileWidth,
                  child: Center(child: preview),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  width: tileWidth,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: expandToFitLabel
                        ? TextOverflow.clip
                        : TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    textScaler: textScaler,
                    style: labelStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SnackActionTile extends StatelessWidget {
  const _SnackActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SnackTileShell(
      label: label,
      onTap: onTap,
      preview: Container(
        width: _snackPreviewSize,
        height: _snackPreviewSize,
        decoration: const BoxDecoration(
          color: Color(0xFFF1F3F5),
          borderRadius: _snackPreviewRadius,
        ),
        child: Icon(icon, size: 26, color: const Color(0xFF667085)),
      ),
    );
  }
}

class _SnackSkeleton extends StatelessWidget {
  const _SnackSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _snackTileWidth,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: _snackPreviewSize,
            height: _snackPreviewSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFF1F3F5),
                borderRadius: _snackPreviewRadius,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Center(
            child: Container(
              width: 48,
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F5),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
