/// 생성 시점에 저장된 audience snapshot만으로 읽기 권한을 판정한다.
///
/// 친구/그룹 컬렉션은 이 정책의 입력이 아니다. 관계 변경은 새 콘텐츠를
/// 만들 때만 반영되고 이미 발행된 콘텐츠에는 소급 적용되지 않는다.
abstract final class FrozenAudiencePolicy {
  static bool canRead({
    required String? viewerId,
    required String ownerId,
    required String visibilityMode,
    required Iterable<String> audienceUserIdsFrozen,
  }) {
    final viewer = viewerId?.trim() ?? '';
    final owner = ownerId.trim();
    final mode = visibilityMode.trim();
    if (viewer.isEmpty) return false;
    if (owner.isNotEmpty && viewer == owner) return true;
    if (mode == 'public') return true;
    if (mode != 'friends' && mode != 'category') return false;
    return audienceUserIdsFrozen
        .map((id) => id.trim())
        .any((id) => id.isNotEmpty && id == viewer);
  }
}
