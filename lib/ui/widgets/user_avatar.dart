import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/avatar_cache_service.dart';
import '../../utils/logger.dart';

/// DM/채팅 등에서 공통으로 사용하는 사용자 아바타 위젯.
///
/// 정책:
/// - 익명/빈 URL이면 placeholder(회색 원 + 아이콘)
/// - `photoVersion > 0`이면 (uid, version) 로컬 캐시 파일을 우선 사용
/// - 네트워크는 `withVersion(url, photoVersion)`로 캐시를 확실히 무효화(최신 이미지 보장)
class UserAvatar extends StatelessWidget {
  final String uid;
  final String photoUrl;
  final int photoVersion;
  final bool isAnonymous;
  final double size;
  final Color placeholderColor;
  final IconData placeholderIcon;
  final double? placeholderIconSize;

  const UserAvatar({
    super.key,
    required this.uid,
    required this.photoUrl,
    required this.photoVersion,
    required this.isAnonymous,
    required this.size,
    this.placeholderColor = const Color(0xFFE5E7EB),
    this.placeholderIcon = Icons.person,
    this.placeholderIconSize,
  });

  @override
  Widget build(BuildContext context) {
    if (isAnonymous || photoUrl.isEmpty) {
      return _placeholder();
    }

    if (photoVersion > 0) {
      return FutureBuilder<File?>(
        key: ValueKey('${uid}_$photoVersion'),
        future: AvatarCacheService().getOrDownloadAvatar(
          uid: uid,
          photoVersion: photoVersion,
          photoUrl: photoUrl,
        ),
        builder: (context, snapshot) {
          final file = snapshot.data;
          if (file != null) {
            return ClipOval(
              child: SizedBox(
                width: size,
                height: size,
                child: Image.file(file, fit: BoxFit.cover),
              ),
            );
          }

          // 로딩 중에는 이전 사진을 유지하지 않고 placeholder를 노출 (DM UX 통일)
          if (snapshot.connectionState != ConnectionState.done) {
            return _placeholder();
          }

          return _networkAvatar();
        },
      );
    }

    return _networkAvatar();
  }

  Widget _networkAvatar() {
    // URL 자체를 바꾸지 않고(cache-bust로 인한 서명/토큰 파손 방지),
    // cacheKey를 버전 기반으로 바꿔서 "최신만" 보이게 한다.
    final cacheKey = photoVersion > 0 ? '${uid}_$photoVersion' : photoUrl;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: CachedNetworkImage(
          key: ValueKey(cacheKey),
          imageUrl: photoUrl,
          cacheKey: cacheKey,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 150),
          fadeOutDuration: const Duration(milliseconds: 150),
          placeholder: (_, __) => _placeholder(),
          errorWidget: (context, url, error) {
            if (kDebugMode) {
              Logger.error(
                '❌ UserAvatar 로드 실패: uid=$uid, v=$photoVersion, url=$url, error=$error',
              );
            }
            return _placeholder();
          },
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: placeholderColor,
      ),
      child: Icon(
        placeholderIcon,
        size: placeholderIconSize ?? (size * 0.5),
        color: const Color(0xFF6B7280),
      ),
    );
  }
}

