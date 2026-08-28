import '../models/meetup.dart';
import '../security/frozen_audience_policy.dart';

/// 달력에서 친구 모임 그라데이션 테두리를 표시할지 판정한다.
///
/// 카드 목록과 동일하게 생성 시 고정된 공개 대상만 사용하며, 공개 시간이
/// 끝났거나 모임 일정 자체가 지난 경우에는 표시하지 않는다.
bool shouldShowFriendMeetupGradientBorder({
  required Meetup meetup,
  required String viewerId,
  required Iterable<String> friendIds,
  DateTime? now,
}) {
  final viewer = viewerId.trim();
  final owner = meetup.userId?.trim() ?? '';
  if (viewer.isEmpty || owner.isEmpty || owner == viewer) return false;
  if (!friendIds.contains(owner)) return false;

  final base = now ?? DateTime.now();
  if (!meetup.isPublishedAt(base) || meetup.isExpired(now: base)) return false;

  return FrozenAudiencePolicy.canRead(
    viewerId: viewer,
    ownerId: owner,
    visibilityMode: meetup.visibility,
    audienceUserIdsFrozen: meetup.allowedUserIds,
  );
}
