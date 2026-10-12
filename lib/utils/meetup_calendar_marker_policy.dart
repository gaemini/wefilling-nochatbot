import '../models/meetup.dart';
import '../security/frozen_audience_policy.dart';

enum MeetupCalendarMarkerStyle { none, solidBlue, friendGradient }

DateTime _calendarDayKey(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// 달력 날짜와 선택 날짜 카드가 함께 사용할 날짜별 모임 집합을 만든다.
///
/// 오늘과 미래는 현재 활성 상태로 볼 수 있는 모임을, 과거는 공개 시간이
/// 만료됐더라도 현재 사용자에게 읽기 권한이 있는 전체 아카이브를 사용한다.
Map<DateTime, List<Meetup>> buildMeetupCalendarDisplayByDay({
  required Map<DateTime, List<Meetup>> visibleByDay,
  required Map<DateTime, List<Meetup>> pastArchiveByDay,
  DateTime? today,
}) {
  final todayKey = _calendarDayKey(today ?? DateTime.now());
  final result = <DateTime, List<Meetup>>{};

  void addAll(DateTime rawDay, Iterable<Meetup> meetups) {
    final day = _calendarDayKey(rawDay);
    final byId = <String, Meetup>{
      for (final meetup in result[day] ?? const <Meetup>[]) meetup.id: meetup,
    };
    for (final meetup in meetups) {
      if (meetup.id.trim().isEmpty) continue;
      byId[meetup.id] = meetup;
    }
    if (byId.isEmpty) return;
    final sorted = byId.values.toList(growable: false)
      ..sort((left, right) {
        final byDate = left.date.compareTo(right.date);
        if (byDate != 0) return byDate;
        return left.time.compareTo(right.time);
      });
    result[day] = List<Meetup>.unmodifiable(sorted);
  }

  for (final entry in visibleByDay.entries) {
    if (_calendarDayKey(entry.key).isBefore(todayKey)) continue;
    addAll(entry.key, entry.value);
  }
  for (final entry in pastArchiveByDay.entries) {
    if (!_calendarDayKey(entry.key).isBefore(todayKey)) continue;
    addAll(entry.key, entry.value);
  }

  return Map<DateTime, List<Meetup>>.unmodifiable(result);
}

/// 과거 날짜의 체크는 사용자가 주최했거나 승인 참여한 기록에만 표시한다.
bool shouldShowPastParticipationCheck({
  required DateTime day,
  required Map<DateTime, List<Meetup>> myRelevantByDay,
  DateTime? today,
}) {
  final dayKey = _calendarDayKey(day);
  final todayKey = _calendarDayKey(today ?? DateTime.now());
  return dayKey.isBefore(todayKey) &&
      (myRelevantByDay[dayKey]?.isNotEmpty ?? false);
}

/// 파란색/친구 모임 링은 과거 날짜에는 표시하지 않는다.
bool shouldShowActiveMeetupRing({
  required DateTime day,
  required Map<DateTime, List<Meetup>> displayByDay,
  DateTime? today,
}) {
  final dayKey = _calendarDayKey(day);
  final todayKey = _calendarDayKey(today ?? DateTime.now());
  return !dayKey.isBefore(todayKey) &&
      (displayByDay[dayKey]?.isNotEmpty ?? false);
}

/// friendships 문서에서 현재 사용자의 실제 친구 UID만 추출한다.
///
/// 정상 관계 문서는 서로 다른 UID 두 개로만 구성된다. 레거시/비정상 문서에
/// 여러 UID가 섞여 있어 모든 모임 작성자가 친구로 오인되는 것을 막는다.
Set<String> friendIdsFromFriendshipUidLists({
  required String viewerId,
  required Iterable<Iterable<Object?>> friendshipUidLists,
}) {
  final viewer = viewerId.trim();
  if (viewer.isEmpty) return const <String>{};

  final friendIds = <String>{};
  for (final rawUids in friendshipUidLists) {
    final pair = rawUids
        .map((value) => value?.toString().trim() ?? '')
        .where((uid) => uid.isNotEmpty)
        .toSet();
    if (pair.length != 2 || !pair.contains(viewer)) continue;
    friendIds.add(pair.firstWhere((uid) => uid != viewer));
  }
  return friendIds;
}

/// 현재 사용자가 볼 수 있는 활성 모임이 달력의 일반 파란 링 대상인지 판정한다.
///
/// 전체 공개 모임은 작성자와 친구가 아니어도 항상 포함된다. 제한 공개 모임은
/// 생성 시 고정된 공개 대상에 현재 사용자가 포함된 경우에만 표시한다.
bool shouldShowVisibleMeetupBorder({
  required Meetup meetup,
  required String viewerId,
  DateTime? now,
}) {
  final viewer = viewerId.trim();
  if (viewer.isEmpty) return false;

  final base = now ?? DateTime.now();
  if (!meetup.isPublishedAt(base) || meetup.isExpired(now: base)) return false;

  return FrozenAudiencePolicy.canRead(
    viewerId: viewer,
    ownerId: meetup.userId ?? '',
    visibilityMode: meetup.visibility,
    audienceUserIdsFrozen: meetup.allowedUserIds,
  );
}

/// 한 날짜에 적용할 링을 결정한다. 친구 모임 그라데이션이 일반 파란 링보다
/// 우선하며, 친구가 아닌 사용자의 전체 공개 모임도 파란 링으로 표시한다.
MeetupCalendarMarkerStyle meetupCalendarMarkerStyleFor({
  required Iterable<Meetup> meetups,
  required String viewerId,
  required Iterable<String> friendIds,
  DateTime? now,
}) {
  var hasVisibleMeetup = false;
  for (final meetup in meetups) {
    if (!shouldShowVisibleMeetupBorder(
      meetup: meetup,
      viewerId: viewerId,
      now: now,
    )) {
      continue;
    }
    hasVisibleMeetup = true;
    if (shouldShowFriendMeetupGradientBorder(
      meetup: meetup,
      viewerId: viewerId,
      friendIds: friendIds,
      now: now,
    )) {
      return MeetupCalendarMarkerStyle.friendGradient;
    }
  }
  return hasVisibleMeetup
      ? MeetupCalendarMarkerStyle.solidBlue
      : MeetupCalendarMarkerStyle.none;
}

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
