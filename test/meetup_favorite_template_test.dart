import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/meetup_favorite_template.dart';

void main() {
  group('MeetupFavoriteTemplate', () {
    test('loads legacy favorites with a public visibility default', () {
      final template = MeetupFavoriteTemplate.fromJson({
        'id': 'legacy',
        'name': 'Study',
        'title': 'Study meetup',
        'description': '',
        'location': 'Library',
        'categoryKey': 'study',
        'isUndecidedTime': true,
        'maxParticipants': 3,
        'updatedAt': '2026-07-24T12:00:00.000',
      });

      expect(template.visibility, 'public');
      expect(template.visibleToCategoryIds, isEmpty);
    });

    test('migrates a legacy drink category to hangout while loading', () {
      final template = MeetupFavoriteTemplate.fromJson({
        'id': 'legacy-drink',
        'name': 'Legacy',
        'title': 'Legacy meetup',
        'description': '',
        'location': 'Campus',
        'categoryKey': 'drink',
        'isUndecidedTime': true,
        'maxParticipants': 3,
        'updatedAt': '2026-07-24T12:00:00.000',
      });

      expect(template.categoryKey, 'hangout');
    });

    test('round-trips visibility and group selection', () {
      final original = MeetupFavoriteTemplate(
        id: 'group-template',
        name: 'Friends cafe',
        title: 'Friends cafe',
        description: 'Coffee together',
        location: 'Campus cafe',
        categoryKey: 'cafe',
        visibility: 'category',
        visibleToCategoryIds: const ['friends-a', 'friends-b'],
        isUndecidedTime: false,
        time: '18:30',
        maxParticipants: 4,
        thumbnailImagePath: null,
        thumbnailImageUrl: null,
        updatedAt: DateTime(2026, 7, 24),
      );

      final decoded = MeetupFavoriteTemplate.fromJson(original.toJson());

      expect(decoded.visibility, 'category');
      expect(decoded.visibleToCategoryIds, ['friends-a', 'friends-b']);
      expect(decoded.time, '18:30');
    });
  });
}
