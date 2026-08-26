import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import '../screens/create_snapshot_screen.dart';
import '../screens/snapshot_detail_screen.dart';
import '../services/cache/app_image_cache_manager.dart';
import '../services/snapshot_service.dart';
import '../services/user_info_cache_service.dart';
import '../ui/widgets/audience_ring.dart';
import '../ui/widgets/user_avatar.dart';
import '../utils/profile_photo_policy.dart';
import '../utils/responsive_helper.dart';
import 'snapshot_storage_image.dart';
import 'snapshot_strings.dart';

const double _snackPreviewSize = 72;
const double _snackTileWidth = 74;
const double _snackBannerHeight = 104;
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
  final SnapshotService _service = SnapshotService.instance;
  final UserInfoCacheService _userInfoService = UserInfoCacheService();
  late Stream<List<SnapshotItem>> _stream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stream = _service.watchVisibleSnapshots();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_service.refreshServerClock());
    unawaited(_service.syncMyFeed());
  }

  Future<void> _create() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateSnapshotScreen()),
    );
  }

  void _retry() {
    setState(() => _stream = _service.watchVisibleSnapshots());
    unawaited(_service.syncMyFeed());
  }

  void _open(List<SnapshotItem> snapshots, int index) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SnapshotDetailScreen(
          snapshots: snapshots,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final horizontal = context.rs(6).clamp(4, 8).toDouble();
    final itemGap = context.rs(2).clamp(1, 3).toDouble();

    return ColoredBox(
      color: Colors.white,
      child: StreamBuilder<List<SnapshotItem>>(
        stream: _stream,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <SnapshotItem>[];
          // The service is newest-first. The first pass keeps the newest snack
          // from each author at the front of the tray. Older snacks follow in
          // chronological order, so the initial viewport stays useful while a
          // horizontal swipe continues naturally into the archive.
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
                child: ListView.separated(
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
                      return StreamBuilder<DMUserInfo?>(
                        stream: uid.isEmpty
                            ? null
                            : _userInfoService.watchUserInfo(uid),
                        initialData: uid.isEmpty
                            ? null
                            : _userInfoService.getCachedUserInfo(uid),
                        builder: (context, profileSnapshot) => _MySnackTile(
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
                      );
                    }
                    if (loading) return const _SnackSkeleton();
                    if (failed) {
                      return _SnackActionTile(
                        icon: Icons.refresh_rounded,
                        label: strings.retry,
                        onTap: _retry,
                      );
                    }
                    final item = visibleItems[index - 1];
                    final sourceIndex = viewerItems
                        .indexWhere((candidate) => candidate.id == item.id);
                    return _SnapshotTile(
                      snapshot: item,
                      label: item.authorName,
                      onTap: () => _open(viewerItems, sourceIndex),
                    );
                  },
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
              semanticLabel:
                  Localizations.localeOf(context).languageCode == 'ko'
                      ? '공개 범위가 제한된 스낵'
                      : 'Limited audience snack',
              child: _SnackAuthorProfilePreview(
                photoUrl: snapshot.authorPhotoUrl,
              ),
            )
          : SizedBox.square(
              dimension: _snackPreviewSize,
              child: SnapshotStorageImage(
                snapshot: snapshot,
                borderRadius: _snackPreviewRadius,
              ),
            ),
    );
  }
}

class _MySnackTile extends StatelessWidget {
  const _MySnackTile({
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
    return _SnackTileShell(
      label: label,
      onTap: onTap,
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
                          semanticLabel:
                              Localizations.localeOf(context).languageCode ==
                                      'ko'
                                  ? '공개 범위가 제한된 스낵'
                                  : 'Limited audience snack',
                          child: _SnackAuthorProfilePreview(
                            photoUrl: profilePhotoUrl.trim().isNotEmpty
                                ? profilePhotoUrl
                                : story.authorPhotoUrl,
                          ),
                        )
                      : SnapshotStorageImage(
                          snapshot: story,
                          borderRadius: _snackPreviewRadius,
                        ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAdd,
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
          ],
        ),
      ),
    );
  }
}

class _SnackAuthorProfilePreview extends StatelessWidget {
  const _SnackAuthorProfilePreview({required this.photoUrl});

  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = photoUrl.trim();
    final canShowPhoto = normalizedUrl.isNotEmpty &&
        ProfilePhotoPolicy.isAllowedProfilePhotoUrl(normalizedUrl);
    return ColoredBox(
      color: const Color(0xFFF3F4F6),
      child: canShowPhoto
          ? CachedNetworkImage(
              imageUrl: normalizedUrl,
              cacheManager: AppImageCacheManager.instance,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 120),
              fadeOutDuration: const Duration(milliseconds: 120),
              placeholder: (_, __) => const _SnackProfilePlaceholder(),
              errorWidget: (_, __, ___) => const _SnackProfilePlaceholder(),
            )
          : const _SnackProfilePlaceholder(),
    );
  }
}

class _SnackProfilePlaceholder extends StatelessWidget {
  const _SnackProfilePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF3F4F6),
      child: Center(
        child: Icon(
          Icons.person_outline_rounded,
          size: 30,
          color: Color(0xFF98A2B3),
        ),
      ),
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
  });

  final String label;
  final VoidCallback onTap;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: _snackTileWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              preview,
              const SizedBox(height: 3),
              SizedBox(
                width: _snackTileWidth,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  textScaler: MediaQuery.textScalerOf(context).clamp(
                    maxScaleFactor: 1.15,
                  ),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
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
