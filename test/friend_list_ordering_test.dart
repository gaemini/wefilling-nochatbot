import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/repositories/users_repository.dart';

void main() {
  group('buildNewestFriendIdOrder', () {
    test('orders friends by friendship creation time descending', () {
      final result = buildNewestFriendIdOrder(
        <Map<String, dynamic>>[
          <String, dynamic>{
            '_documentId': 'owner__old',
            'uids': <String>['owner', 'old'],
            'createdAt': DateTime.utc(2026, 1, 1),
          },
          <String, dynamic>{
            '_documentId': 'owner__new',
            'uids': <String>['new', 'owner'],
            'createdAt': DateTime.utc(2026, 9, 7),
          },
        ],
        ownerUid: 'owner',
      );

      expect(result, <String>['new', 'old']);
    });

    test('deduplicates relationships using the newest record', () {
      final result = buildNewestFriendIdOrder(
        <Map<String, dynamic>>[
          <String, dynamic>{
            '_documentId': 'duplicate-old',
            'uids': <String>['owner', 'same'],
            'createdAt': DateTime.utc(2025, 1, 1),
          },
          <String, dynamic>{
            '_documentId': 'other',
            'uids': <String>['owner', 'other'],
            'createdAt': DateTime.utc(2026, 1, 1),
          },
          <String, dynamic>{
            '_documentId': 'duplicate-new',
            'uids': <String>['same', 'owner'],
            'createdAt': DateTime.utc(2026, 9, 7),
          },
        ],
        ownerUid: 'owner',
      );

      expect(result, <String>['same', 'other']);
    });

    test('keeps legacy records last and ignores unrelated malformed records',
        () {
      final result = buildNewestFriendIdOrder(
        <Map<String, dynamic>>[
          <String, dynamic>{
            '_documentId': 'legacy-b',
            'uids': <String>['owner', 'legacyB'],
          },
          <String, dynamic>{
            '_documentId': 'unrelated',
            'uids': <String>['one', 'two'],
            'createdAt': DateTime.utc(2030),
          },
          <String, dynamic>{'uids': 'not-a-list'},
          <String, dynamic>{
            '_documentId': 'current',
            'uids': <String>['owner', 'current'],
            'createdAt': DateTime.utc(2026, 9, 7),
          },
          <String, dynamic>{
            '_documentId': 'legacy-a',
            'uids': <String>['owner', 'legacyA'],
          },
        ],
        ownerUid: 'owner',
      );

      expect(result, <String>['current', 'legacyB', 'legacyA']);
    });
  });
}
