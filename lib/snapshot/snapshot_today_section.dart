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
          final ownIndex = items.indexWhere((item) => item.authorId == uid);
          final own = ownIndex >= 0 ? items[ownIndex] : null;
          final visibleItems = items
              .where((item) => own == null || item.id != own.id)
              .toList(growable: false);
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
                              : () => _open(items, ownIndex),
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
                    final sourceIndex = items
                        .indexWhere((candidate) => candidate.id == item.id);
                    return _SnapshotTile(
                      snapshot: item,
                      label: item.authorName,
                      onTap: () => _open(items, sourceIndex),
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
    return _SnackTileShell(
      label: label,
      onTap: onTap,
      preview: AudienceRing(
        restricted: snapshot.visibility != SnapshotVisibility.public,
        size: _snackPreviewSize,
        borderRadius: _snackPreviewRadius,
        ringWidth: 2,
        innerGap: 1.5,
        semanticLabel: Localizations.localeOf(context).languageCode == 'ko'
            ? '공개 범위가 제한된 스낵'
            : 'Limited audience snack',
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
      preview: Stack(
        clipBehavior: Clip.none,
        children: [
          if (story == null)
            _EmptySnackPreview(
              uid: uid,
              photoUrl: profilePhotoUrl,
              photoVersion: profilePhotoVersion,
            )
          else
            AudienceRing(
              restricted: story.visibility != SnapshotVisibility.public,
              size: _snackPreviewSize,
              borderRadius: _snackPreviewRadius,
              ringWidth: 2,
              innerGap: 1.5,
              semanticLabel:
                  Localizations.localeOf(context).languageCode == 'ko'
                      ? '공개 범위가 제한된 스낵'
                      : 'Limited audience snack',
              child: SnapshotStorageImage(
                snapshot: story,
                borderRadius: _snackPreviewRadius,
              ),
            ),
          Positioned(
            right: -2,
            bottom: -1,
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
                    fontFamily: 'Pretendard',
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
