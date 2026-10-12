import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import '../services/avatar_cache_service.dart';
import '../services/cache/app_image_cache_manager.dart';
import '../services/user_info_cache_service.dart';
import '../utils/logger.dart';
import '../utils/profile_photo_policy.dart';

class SnapshotAuthorProfile {
  const SnapshotAuthorProfile({
    required this.userId,
    required this.photoUrl,
    required this.photoVersion,
  });

  final String userId;
  final String photoUrl;
  final int photoVersion;

  String get cacheKey =>
      photoVersion > 0 ? '${userId}_$photoVersion' : photoUrl.trim();

  bool get canShow =>
      userId.trim().isNotEmpty &&
      photoUrl.trim().isNotEmpty &&
      ProfilePhotoPolicy.isAllowedProfilePhotoUrl(photoUrl.trim());

  static SnapshotAuthorProfile resolve(SnapshotItem item) {
    final cached = UserInfoCacheService().getCachedUserInfo(item.authorId);
    final cachedUrl = cached?.photoURL.trim() ?? '';
    if (cached != null &&
        !cached.isDeletedAccount &&
        cachedUrl.isNotEmpty &&
        ProfilePhotoPolicy.isAllowedProfilePhotoUrl(cachedUrl)) {
      return SnapshotAuthorProfile(
        userId: item.authorId,
        photoUrl: cachedUrl,
        photoVersion: cached.photoVersion,
      );
    }
    return SnapshotAuthorProfile(
      userId: item.authorId,
      photoUrl: item.authorPhotoUrl.trim(),
      photoVersion: item.authorPhotoVersion,
    );
  }
}

Future<bool> prefetchSnapshotAuthorProfile(
  SnapshotAuthorProfile profile,
) async {
  if (!profile.canShow) return true;
  final stopwatch = Stopwatch()..start();
  var source = 'image-cache';
  var success = false;
  if (profile.photoVersion > 0) {
    source = 'profile-cache';
    final file = await AvatarCacheService().getOrDownloadAvatar(
      uid: profile.userId,
      photoVersion: profile.photoVersion,
      photoUrl: profile.photoUrl,
    );
    success = file != null && await file.exists() && await file.length() > 0;
    if (!success) {
      source = 'image-cache-fallback';
      success = await AppImageCacheManager.prefetchUrl(
        profile.photoUrl,
        cacheKey: profile.cacheKey,
      );
    }
  } else {
    success = await AppImageCacheManager.prefetchUrl(
      profile.photoUrl,
      cacheKey: profile.cacheKey,
    );
  }
  if (Logger.isVerboseEnabled) {
    Logger.log(
      '스낵 작성자 프로필 준비 '
      '(authorId=${profile.userId}, success=$success, source=$source, '
      'elapsedMs=${stopwatch.elapsedMilliseconds})',
    );
  }
  return success;
}

class SnapshotAuthorProfileImage extends StatefulWidget {
  const SnapshotAuthorProfileImage({
    super.key,
    required this.profile,
    required this.size,
    required this.borderRadius,
    required this.decodeWidth,
    this.placeholderColor = const Color(0xFFF3F4F6),
    this.placeholderIconColor = const Color(0xFF98A2B3),
    this.placeholderIconSize = 30,
  });

  final SnapshotAuthorProfile profile;
  final double size;
  final BorderRadius borderRadius;
  final int decodeWidth;
  final Color placeholderColor;
  final Color placeholderIconColor;
  final double placeholderIconSize;

  @override
  State<SnapshotAuthorProfileImage> createState() =>
      _SnapshotAuthorProfileImageState();
}

class _SnapshotAuthorProfileImageState
    extends State<SnapshotAuthorProfileImage> {
  Future<({File? file, bool cacheHit})>? _versionedFile;
  bool? _networkCacheHit;
  bool _displayReported = false;
  late Stopwatch _displayStopwatch;

  @override
  void initState() {
    super.initState();
    _resetSource();
  }

  @override
  void didUpdateWidget(covariant SnapshotAuthorProfileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.cacheKey != widget.profile.cacheKey ||
        oldWidget.profile.photoUrl != widget.profile.photoUrl) {
      _resetSource();
    }
  }

  void _resetSource() {
    _displayReported = false;
    _displayStopwatch = Stopwatch()..start();
    _networkCacheHit = null;
    final profile = widget.profile;
    if (!profile.canShow) {
      _versionedFile = null;
      return;
    }
    if (profile.photoVersion > 0) {
      _versionedFile = _loadVersionedFile(profile);
      return;
    }
    _versionedFile = null;
    unawaited(
      AppImageCacheManager.instance
          .getFileFromCache(profile.cacheKey)
          .then<void>((entry) {
        if (mounted && widget.profile.cacheKey == profile.cacheKey) {
          _networkCacheHit = entry != null;
        }
      }),
    );
  }

  Future<({File? file, bool cacheHit})> _loadVersionedFile(
    SnapshotAuthorProfile profile,
  ) async {
    final local = await AvatarCacheService().getLocalAvatarIfExists(
      profile.userId,
      profile.photoVersion,
    );
    if (local != null) return (file: local, cacheHit: true);
    final downloaded = await AvatarCacheService().getOrDownloadAvatar(
      uid: profile.userId,
      photoVersion: profile.photoVersion,
      photoUrl: profile.photoUrl,
    );
    return (file: downloaded, cacheHit: false);
  }

  void _reportDisplayed({required bool? cacheHit, required String source}) {
    if (_displayReported) return;
    _displayReported = true;
    if (Logger.isVerboseEnabled) {
      Logger.log(
        '스낵 작성자 프로필 표시 '
        '(authorId=${widget.profile.userId}, source=$source, '
        'cacheHit=${cacheHit ?? 'unknown'}, '
        'elapsedMs=${_displayStopwatch.elapsedMilliseconds})',
      );
    }
  }

  Widget _frameReportingImage(
    ImageProvider<Object> provider, {
    required bool? cacheHit,
    required String source,
  }) {
    return Image(
      image: provider,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null || wasSynchronouslyLoaded) {
          _reportDisplayed(cacheHit: cacheHit, source: source);
        }
        return child;
      },
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    Widget child;
    if (!profile.canShow) {
      child = _placeholder();
    } else if (profile.photoVersion > 0) {
      child = FutureBuilder<({File? file, bool cacheHit})>(
        future: _versionedFile,
        builder: (context, snapshot) {
          final result = snapshot.data;
          final file = result?.file;
          if (file == null) {
            if (snapshot.connectionState != ConnectionState.done) {
              return _placeholder();
            }
            return _networkImage(profile);
          }
          return _frameReportingImage(
            ResizeImage.resizeIfNeeded(
              widget.decodeWidth,
              null,
              FileImage(file),
            ),
            cacheHit: result?.cacheHit,
            source: 'profile-cache',
          );
        },
      );
    } else {
      child = _networkImage(profile);
    }

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox.square(dimension: widget.size, child: child),
    );
  }

  Widget _networkImage(SnapshotAuthorProfile profile) {
    return CachedNetworkImage(
      imageUrl: profile.photoUrl,
      cacheKey: profile.cacheKey,
      cacheManager: AppImageCacheManager.instance,
      memCacheWidth: widget.decodeWidth,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: const Duration(milliseconds: 120),
      imageBuilder: (_, provider) => _frameReportingImage(
        provider,
        cacheHit: _networkCacheHit,
        source: 'image-cache',
      ),
      placeholder: (_, __) => _placeholder(),
      errorWidget: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return ColoredBox(
      color: widget.placeholderColor,
      child: Center(
        child: Icon(
          Icons.person_outline_rounded,
          size: widget.placeholderIconSize,
          color: widget.placeholderIconColor,
        ),
      ),
    );
  }
}
