import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/meetup.dart';
import 'package:wefilling/utils/meetup_calendar_marker_policy.dart';

Meetup _meetup({
  String id = 'meetup-1',
  String ownerId = 'friend',
  String visibility = 'public',
  List<String> allowedUserIds = const <String>[],
  DateTime? date,
  String time = '10:00 ~ 12:00',
  DateTime? publicExpiresAt,
  String publicWindowStatus = '',
}) {
  return Meetup(
    id: id,
    title: '친구 모임',
    description: '',
    location: '',
    time: time,
    maxParticipants: 4,
    currentParticipants: 1,
    host: '친구',
    imageUrl: '',
    date: date ?? DateTime(2026, 8, 29),
    userId: ownerId,
    visibility: visibility,
    allowedUserIds: allowedUserIds,
    publicExpiresAt: publicExpiresAt,
    publicWindowStatus: publicWindowStatus,
  );
}

void main() {
  final now = DateTime(2026, 8, 28, 9);

  test('정상적인 2인 친구 관계에서만 상대 UID를 추출한다', () {
    final friendIds = friendIdsFromFriendshipUidLists(
      viewerId: 'viewer',
      friendshipUidLists: const <List<String>>[
        <String>['viewer', 'friend'],
        <String>['viewer', 'stranger-a', 'stranger-b'],
        <String>['other-a', 'other-b'],
        <String>['viewer', 'viewer'],
      ],
    );

    expect(friendIds, const <String>{'friend'});
  });

  test('친구가 아닌 사용자의 전체 공개 모임은 단색 파란 링 대상이다', () {
    expect(
      meetupCalendarMarkerStyleFor(
        meetups: <Meetup>[_meetup(ownerId: 'stranger')],
        viewerId: 'viewer',
        friendIds: const <String>{'friend'},
        now: now,
      ),
      MeetupCalendarMarkerStyle.solidBlue,
    );
  });

  test('같은 날 친구 모임도 있으면 그라데이션 링이 우선한다', () {
    expect(
      meetupCalendarMarkerStyleFor(
        meetups: <Meetup>[
          _meetup(ownerId: 'stranger'),
          _meetup(ownerId: 'friend'),
        ],
        viewerId: 'viewer',
        friendIds: const <String>{'friend'},
        now: now,
      ),
      MeetupCalendarMarkerStyle.friendGradient,
    );
  });

  test('공개 대상이 아닌 제한 모임은 달력 링을 표시하지 않는다', () {
    expect(
      meetupCalendarMarkerStyleFor(
        meetups: <Meetup>[
          _meetup(
            ownerId: 'stranger',
            visibility: 'category',
            allowedUserIds: const <String>['stranger'],
          ),
        ],
        viewerId: 'viewer',
        friendIds: const <String>{'friend'},
        now: now,
      ),
      MeetupCalendarMarkerStyle.none,
    );
  });

  test('친구가 만든 전체 공개 활성 모임이면 테두리를 표시한다', () {
    expect(
      shouldShowFriendMeetupGradientBorder(
        meetup: _meetup(),
        viewerId: 'viewer',
        friendIds: const <String>{'friend'},
        now: now,
      ),
      isTrue,
    );
  });

  test('제한 공개 모임은 생성 시 공개 대상에 포함된 사용자에게만 표시한다', () {
    final meetup = _meetup(
      visibility: 'category',
      allowedUserIds: const <String>['friend', 'viewer'],
    );

    expect(
      shouldShowFriendMeetupGradientBorder(
        meetup: meetup,
        viewerId: 'viewer',
        friendIds: const <String>{'friend'},
        now: now,
      ),
      isTrue,
    );
    expect(
      shouldShowFriendMeetupGradientBorder(
        meetup: meetup,
        viewerId: 'other',
        friendIds: const <String>{'friend'},
        now: now,
      ),
      isFalse,
    );
  });

  test('작성자가 친구가 아니거나 내 모임이면 테두리를 표시하지 않는다', () {
    expect(
      shouldShowFriendMeetupGradientBorder(
        meetup: _meetup(ownerId: 'stranger'),
        viewerId: 'viewer',
        friendIds: const <String>{'friend'},
        now: now,
      ),
      isFalse,
    );
    expect(
      shouldShowFriendMeetupGradientBorder(
        meetup: _meetup(ownerId: 'viewer'),
        viewerId: 'viewer',
        friendIds: const <String>{'viewer'},
        now: now,
      ),
      isFalse,
    );
  });

  test('공개 시간이 만료된 모임은 테두리를 표시하지 않는다', () {
    expect(
      shouldShowFriendMeetupGradientBorder(
        meetup: _meetup(
          publicExpiresAt: now.subtract(const Duration(minutes: 1)),
          publicWindowStatus: 'timed',
        ),
        viewerId: 'viewer',
        friendIds: const <String>{'friend'},
        now: now,
      ),
      isFalse,
    );
  });

  test('모임 일정이 지난 경우 테두리를 표시하지 않는다', () {
    expect(
      shouldShowFriendMeetupGradientBorder(
        meetup: _meetup(
          date: DateTime(2026, 8, 27),
          time: '10:00 ~ 12:00',
        ),
        viewerId: 'viewer',
        friendIds: const <String>{'friend'},
        now: now,
      ),
      isFalse,
    );
  });

  test('실시간 날짜 목록에서 마지막 친구 모임이 삭제되면 테두리가 사라진다', () {
    final liveMeetupsForDay = <Meetup>[_meetup()];

    bool hasBorder() => liveMeetupsForDay.any(
          (meetup) => shouldShowFriendMeetupGradientBorder(
            meetup: meetup,
            viewerId: 'viewer',
            friendIds: const <String>{'friend'},
            now: now,
          ),
        );

    expect(hasBorder(), isTrue);
    liveMeetupsForDay.removeWhere((meetup) => meetup.id == 'meetup-1');
    expect(hasBorder(), isFalse);
  });

  test('과거 날짜 카드는 참여 여부와 관계없이 읽을 수 있는 아카이브를 사용한다', () {
    final day = DateTime(2026, 8, 27);
    final publicMeetup = _meetup(id: 'public', date: day);
    final joinedMeetup = _meetup(id: 'joined', date: day);

    final displayByDay = buildMeetupCalendarDisplayByDay(
      visibleByDay: <DateTime, List<Meetup>>{
        day: <Meetup>[publicMeetup],
      },
      pastArchiveByDay: <DateTime, List<Meetup>>{
        day: <Meetup>[publicMeetup, joinedMeetup],
      },
      today: now,
    );

    expect(
      displayByDay[day]?.map((meetup) => meetup.id).toSet(),
      <String>{'public', 'joined'},
    );
  });

  test('과거 참여일은 체크만 표시하고 활성 모임 원은 표시하지 않는다', () {
    final day = DateTime(2026, 8, 27);
    final archived = _meetup(id: 'archived', date: day);
    final byDay = <DateTime, List<Meetup>>{
      day: <Meetup>[archived],
    };

    expect(
      shouldShowPastParticipationCheck(
        day: day,
        myRelevantByDay: byDay,
        today: now,
      ),
      isTrue,
    );
    expect(
      shouldShowActiveMeetupRing(
        day: day,
        displayByDay: byDay,
        today: now,
      ),
      isFalse,
    );
  });

  test('참여하지 않은 과거 날짜도 아카이브 카드는 보이지만 체크는 없다', () {
    final day = DateTime(2026, 8, 27);
    final archived = _meetup(id: 'archived', date: day);
    final displayByDay = buildMeetupCalendarDisplayByDay(
      visibleByDay: const <DateTime, List<Meetup>>{},
      pastArchiveByDay: <DateTime, List<Meetup>>{
        day: <Meetup>[archived],
      },
      today: now,
    );

    expect(displayByDay[day], <Meetup>[archived]);
    expect(
      shouldShowPastParticipationCheck(
        day: day,
        myRelevantByDay: const <DateTime, List<Meetup>>{},
        today: now,
      ),
      isFalse,
    );
  });

  test('오늘과 미래 날짜의 마커와 카드는 공개 가능한 모임을 함께 사용한다', () {
    final day = DateTime(2026, 8, 29);
    final visibleMeetup = _meetup(id: 'visible', date: day);
    final archivedOnlyMeetup = _meetup(id: 'archived-only', date: day);

    final displayByDay = buildMeetupCalendarDisplayByDay(
      visibleByDay: <DateTime, List<Meetup>>{
        day: <Meetup>[visibleMeetup],
      },
      pastArchiveByDay: <DateTime, List<Meetup>>{
        day: <Meetup>[archivedOnlyMeetup],
      },
      today: now,
    );

    expect(displayByDay[day]?.map((meetup) => meetup.id), <String>['visible']);
    expect(
      shouldShowActiveMeetupRing(
        day: day,
        displayByDay: displayByDay,
        today: now,
      ),
      isTrue,
    );
  });

  test('카테고리 필터에서 제외된 날짜는 달력 표시 데이터에도 남지 않는다', () {
    final selectedCategoryDay = DateTime(2026, 8, 29);
    final otherCategoryDay = DateTime(2026, 8, 30);

    final displayByDay = buildMeetupCalendarDisplayByDay(
      // 화면에서 선택 카테고리로 필터된 맵만 전달한다.
      visibleByDay: <DateTime, List<Meetup>>{
        selectedCategoryDay: <Meetup>[
          _meetup(id: 'selected-category', date: selectedCategoryDay),
        ],
      },
      pastArchiveByDay: const <DateTime, List<Meetup>>{},
      today: now,
    );

    expect(displayByDay[selectedCategoryDay], hasLength(1));
    expect(displayByDay.containsKey(otherCategoryDay), isFalse);
  });
}
