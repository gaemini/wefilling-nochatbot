import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/meetup.dart';
import 'package:wefilling/utils/meetup_calendar_marker_policy.dart';

Meetup _meetup({
  String ownerId = 'friend',
  String visibility = 'public',
  List<String> allowedUserIds = const <String>[],
  DateTime? date,
  String time = '10:00 ~ 12:00',
  DateTime? publicExpiresAt,
  String publicWindowStatus = '',
}) {
  return Meetup(
    id: 'meetup-1',
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
}
