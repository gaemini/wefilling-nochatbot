import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../utils/avatar_image.dart';
import '../../utils/logger.dart';

/// DM/채팅 등에서 공통으로 사용하는 사용자 아바타 위젯.
///
/// 정책:
/// - 익명/빈 URL이거나 허용된 프로필 사진 주소가 아니면 placeholder
/// - 캐시 키는 `photoVersion > 0`이면 (uid, version)이라 사진이 바뀌면 이전
///   파일을 재사용하지 않는다(최신 이미지 보장).
/// - 전용 아바타 캐시(AppImageCacheManager.avatars)와 크기 구간별 디코딩을 쓴다.
///   미리 데운 이미지(precacheAvatarImages)는 첫 프레임에 동기적으로 그려진다.
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
    // ✅ 보안/정책: 우리 Storage 버킷에 없는 URL은 절대 표시하지 않는다.
    if (isAnonymous || !isDisplayableAvatarUrl(photoUrl)) {
      return _placeholder();
    }

    final ratio = MediaQuery.devicePixelRatioOf(context);
    final provider = avatarImageProvider(
      uid: uid,
      photoVersion: photoVersion,
      photoUrl: photoUrl,
      logicalSize: size,
      devicePixelRatio: ratio,
    );
    // 사진이 바뀌면(버전/URL) 이전 사진이 남아 보이지 않도록 새 위젯으로 만든다.
    final identity = '${uid}_${photoVersion}_$photoUrl';

    return RepaintBoundary(
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Image(
            key: ValueKey<String>(identity),
            image: provider,
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              // 이미 디코딩된 이미지는 깜빡임 없이 첫 프레임에 바로 그린다.
              if (wasSynchronouslyLoaded) return child;
              return Stack(
                fit: StackFit.expand,
                children: [
                  _placeholder(),
                  AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    child: child,
                  ),
                ],
              );
            },
            errorBuilder: (context, error, stackTrace) {
              if (kDebugMode) {
                Logger.error(
                  '❌ UserAvatar 로드 실패: uid=$uid, v=$photoVersion, error=$error',
                );
              }
              return _placeholder();
            },
          ),
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
