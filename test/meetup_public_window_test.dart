import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/meetup.dart';
import 'package:wefilling/ui/widgets/meetup_public_countdown.dart';

Meetup meetup({
  required DateTime? expiresAt,
  bool confirmed = false,
  String status = 'timed',
}) {
  return Meetup(
    id: 'timed-meetup',
    title: 'Timed meetup',
    description: '',
    location: 'Seoul',
    time: '20:00',
    maxParticipants: 6,
    currentParticipants: 1,
    host: 'host',
    imageUrl: '',
    date: DateTime(2026, 8, 14),
    isConfirmed: confirmed,
    publicDurationHours: expiresAt == null ? null : 8,
    publicExpiresAt: expiresAt,
    publicWindowStatus: status,
  );
}

void main() {
  final now = DateTime(2026, 8, 14, 12);

  test('unlimited meetup remains published', () {
    expect(meetup(expiresAt: null).isPublishedAt(now), isTrue);
  });

  test('unconfirmed meetup is hidden exactly at its deadline', () {
    final item = meetup(expiresAt: now.add(const Duration(hours: 1)));
    expect(item.isPublishedAt(now), isTrue);
    expect(item.isPublishedAt(now.add(const Duration(hours: 1))), isFalse);
  });

  test('confirmed meetup remains published after the original deadline', () {
    final item = meetup(
      expiresAt: now.subtract(const Duration(minutes: 1)),
      confirmed: true,
      status: 'confirmed',
    );
    expect(item.isPublishedAt(now), isTrue);
    expect(item.hasPublicTimeLimit, isFalse);
  });

  test('countdown uses the requested compact English format', () {
    expect(
      MeetupPublicCountdown.format(
        const Duration(hours: 7, minutes: 23),
      ),
      '7H 23min left',
    );
    expect(
      MeetupPublicCountdown.format(const Duration(minutes: 58, seconds: 1)),
      '59min left',
    );
  });
}
