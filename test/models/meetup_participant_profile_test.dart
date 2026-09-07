import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/meetup_participant.dart';

void main() {
  MeetupParticipant participant({
    String userId = 'active-user',
    String userName = 'Watson',
    bool isDeletedAccount = false,
  }) {
    return MeetupParticipant(
      id: 'participant-id',
      meetupId: 'meetup-id',
      userId: userId,
      userName: userName,
      userEmail: 'user@example.com',
      isDeletedAccount: isDeletedAccount,
      joinedAt: DateTime(2026, 9, 7),
      status: ParticipantStatus.approved,
    );
  }

  test('active meetup participant has a viewable profile', () {
    expect(participant().hasViewableProfile, isTrue);
  });

  test('deleted and placeholder participants cannot open a profile', () {
    expect(participant(userId: '').hasViewableProfile, isFalse);
    expect(participant(userId: 'host').hasViewableProfile, isFalse);
    expect(participant(userId: 'deleted').hasViewableProfile, isFalse);
    expect(participant(isDeletedAccount: true).hasViewableProfile, isFalse);
    expect(
      participant(userName: 'DELETED_ACCOUNT').hasViewableProfile,
      isFalse,
    );
  });
}
