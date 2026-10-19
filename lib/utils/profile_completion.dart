/// 마이페이지 처음 사용자 완성도: 프로필 사진 30 + 자기소개 30 + 관심 태그 40(3개 기준).
class ProfileCompletion {
  const ProfileCompletion({
    required this.hasPhoto,
    required this.hasBio,
    required this.tagCount,
  });

  final bool hasPhoto;
  final bool hasBio;
  final int tagCount;

  static const int targetTags = 3;

  bool get tagsDone => tagCount >= targetTags;

  /// 0–100.
  int get percent {
    final tags = tagCount.clamp(0, targetTags) / targetTags;
    return ((hasPhoto ? 30 : 0) + (hasBio ? 30 : 0) + 40 * tags).round();
  }

  bool get complete => percent >= 100;
}
