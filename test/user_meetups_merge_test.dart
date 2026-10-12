import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/meetup.dart';
import 'package:wefilling/screens/user_meetups_screens.dart';

void main() {
  Meetup meetup(String id, DateTime date, {String? title}) => Meetup(
        id: id,
        title: title ?? id,
        description: '',
        location: '',
        time: '12:00',
        maxParticipants: 4,
        currentParticipants: 1,
        host: 'host',
        imageUrl: '',
        date: date,
      );

  test('주최 모임과 참여 모임을 중복 없이 최신 일정순으로 합친다', () {
    final duplicateFromHosted = meetup(
      'shared',
      DateTime(2026, 9, 2),
      title: 'hosted copy',
    );
    final duplicateFromJoined = meetup(
      'shared',
      DateTime(2026, 9, 2),
      title: 'joined copy',
    );

    final result = mergeMyMeetups(
      [duplicateFromHosted, meetup('old', DateTime(2026, 8, 20))],
      [duplicateFromJoined, meetup('new', DateTime(2026, 9, 8))],
    );

    expect(result.map((meetup) => meetup.id), ['new', 'shared', 'old']);
    expect(result.where((meetup) => meetup.id == 'shared'), hasLength(1));
  });
}
