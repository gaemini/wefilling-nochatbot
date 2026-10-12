import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/meetup.dart';

void main() {
  test('legacy meetup documents keep safe defaults', () {
    final meetup = Meetup.fromJson(<String, dynamic>{
      'id': 'meetup-1',
      'title': 'Lunch',
      'date': DateTime(2026, 7, 26),
    });

    expect(meetup.isConfirmed, isFalse);
    expect(meetup.snackChatId, isNull);
  });

  test('confirmed meetup keeps its linked Snack Chat id', () {
    final meetup = Meetup.fromJson(<String, dynamic>{
      'id': 'meetup-1',
      'title': 'Lunch',
      'date': DateTime(2026, 7, 26),
      'isConfirmed': true,
      'groupChatEnabled': true,
      'snackChatId': 'snack-chat-1',
    });

    expect(meetup.isConfirmed, isTrue);
    expect(meetup.canStartReview, isTrue);
    expect(meetup.groupChatEnabled, isTrue);
    expect(meetup.snackChatId, 'snack-chat-1');
    expect(meetup.toJson()['snackChatId'], 'snack-chat-1');
  });

  test('completed legacy meetup keeps the existing review workflow', () {
    final meetup = Meetup.fromJson(<String, dynamic>{
      'id': 'meetup-completed',
      'title': 'Completed lunch',
      'date': DateTime(2026, 7, 26),
      'isCompleted': true,
    });

    expect(meetup.isConfirmed, isFalse);
    expect(meetup.canStartReview, isTrue);
  });

  test('unconfirmed scheduled meetup cannot start a review', () {
    final meetup = Meetup.fromJson(<String, dynamic>{
      'id': 'meetup-scheduled',
      'title': 'Scheduled lunch',
      'date': DateTime(2026, 7, 26),
    });

    expect(meetup.canStartReview, isFalse);
  });

  test('category meetup preserves its resolved audience ids', () {
    final meetup = Meetup.fromJson(<String, dynamic>{
      'id': 'meetup-private',
      'title': 'Private lunch',
      'date': DateTime(2026, 7, 26),
      'visibility': 'category',
      'visibleToCategoryIds': <String>['group-a'],
      'allowedUserIds': <String>['host', 'friend-a'],
    });

    expect(meetup.allowedUserIds, <String>['host', 'friend-a']);
    expect(meetup.toJson()['allowedUserIds'], <String>['host', 'friend-a']);
  });
}
