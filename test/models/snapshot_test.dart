import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snapshot.dart';

void main() {
  group('SnapshotItem', () {
    test('parses only the supported visibility values', () {
      expect(
        SnapshotVisibility.fromValue('friends'),
        SnapshotVisibility.friends,
      );
      expect(
        SnapshotVisibility.fromValue('public'),
        SnapshotVisibility.public,
      );
      expect(
        SnapshotVisibility.fromValue('category'),
        SnapshotVisibility.category,
      );
      expect(
        SnapshotVisibility.fromValue('unexpected'),
        SnapshotVisibility.friends,
      );
      expect(
        SnapshotVisibility.fromValue('school'),
        SnapshotVisibility.friends,
      );
    });

    test('expires at the exact absolute expiresAt instant', () {
      final createdAt = DateTime.utc(2026, 7, 25, 14, 30, 10);
      final item = SnapshotItem.fromMap('snapshot-id', {
        'authorId': 'author',
        'storagePath': 'snapshots/snapshot-id/final.jpg',
        'visibility': 'friends',
        'createdAt': createdAt,
        'expiresAt': createdAt.add(const Duration(hours: 24)),
        'aspectRatio': 0.8,
      });

      expect(
        item.isExpiredAt(
          createdAt.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
        ),
        isFalse,
      );
      expect(
        item.isExpiredAt(createdAt.add(const Duration(hours: 24))),
        isTrue,
      );
    });

    test('normalizes overlay coordinates and reaction counts', () {
      final item = SnapshotItem.fromMap('snapshot-id', {
        'authorId': 'author',
        'storagePath': 'snapshots/snapshot-id/final.jpg',
        'visibility': 'friends',
        'createdAt': DateTime.utc(2026, 7, 25),
        'expiresAt': DateTime.utc(2026, 7, 26),
        'overlay': {
          'text': 'hello',
          'x': 2,
          'y': -1,
          'lightText': false,
          'fontScale': 3,
        },
        'reactionCounts': {'👏': 2.6, '❤️': '3'},
      });

      expect(item.overlay.x, 1);
      expect(item.overlay.y, 0);
      expect(item.overlay.lightText, isFalse);
      expect(item.overlay.fontScale, 1.75);
      expect(item.reactionCounts['👏'], 3);
      expect(item.reactionCounts['❤️'], 3);
    });
  });
}
