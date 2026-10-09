import '../config/app_backend.dart';

/// 프로필 사진 URL 정책(보안/일관성)
///
/// 요구사항:
/// - 프로필 이미지는 이 프로젝트의 Firebase Storage 버킷(레거시 US 버킷 또는
///   현재 업로드 버킷)에 저장된 것만 사용
/// - 버킷에 없는(=외부 URL/다른 버킷) 이미지는 절대 표시하지 않고 기본 이미지(placeholder)로 처리
class ProfilePhotoPolicy {
  /// 레거시(US) 버킷. 새 업로드 버킷은 `AppBackend.config.uploadStorageBucket`.
  static const String bucket = 'flutterproject3-af322.firebasestorage.app';
  static const String bucketGsPrefix = 'gs://$bucket/';

  /// 프로필 사진은 `profile_images/` 하위에만 허용
  static const String allowedFolder = 'profile_images/';

  static Iterable<String> get allowedBuckets => AppBackend.config.knownBuckets;

  static bool isAllowedProfilePhotoUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return false;

    // gs://bucket/profile_images/...
    for (final allowed in allowedBuckets) {
      final prefix = 'gs://$allowed/';
      if (u.startsWith(prefix)) {
        return u.substring(prefix.length).startsWith(allowedFolder);
      }
    }

    // https download URL (Firebase Storage)
    // 예: https://firebasestorage.googleapis.com/v0/b/<bucket>/o/profile_images%2F...
    if (u.contains('firebasestorage.googleapis.com')) {
      final urlBucket = AppStorage.bucketFromUrl(u);
      if (urlBucket == null || !allowedBuckets.contains(urlBucket)) return false;
      return u.contains('/o/${Uri.encodeComponent(allowedFolder)}') ||
          u.contains('/o/profile_images%2F');
    }

    // 그 외(외부 CDN/구글 프로필 사진 등)는 전부 차단
    return false;
  }
}
