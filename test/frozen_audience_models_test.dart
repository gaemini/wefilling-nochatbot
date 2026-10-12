import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/meetup.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/models/snapshot.dart';

void main() {
  const canonicalAudience = <String>['owner', 'frozen-member'];
  const legacyAudience = <String>['owner', 'wrong-legacy-member'];
  const sourceGroups = <String>['group-at-creation'];

  test('post parser prefers canonical frozen audience fields', () {
    final post = Post.fromMap({
      'ownerId': 'owner',
      'userId': 'wrong-owner',
      'visibilityMode': 'category',
      'visibility': 'public',
      'audienceUserIdsFrozen': canonicalAudience,
      'allowedUserIds': legacyAudience,
      'sourceGroupIds': sourceGroups,
      'visibleToCategoryIds': const <String>['wrong-group'],
      'visibilitySchemaVersion': 2,
      'createdAt': 1,
    }, 'post-id');

    expect(post.userId, 'owner');
    expect(post.visibility, 'category');
    expect(post.allowedUserIds, canonicalAudience);
    expect(post.visibleToCategoryIds, sourceGroups);
  });

  test('post parser falls back when transitional frozen lists are empty', () {
    final post = Post.fromMap({
      'userId': 'owner',
      'visibility': 'category',
      'audienceUserIdsFrozen': const <String>[],
      'allowedUserIds': legacyAudience,
      'sourceGroupIds': const <String>[],
      'visibleToCategoryIds': const <String>['legacy-group'],
      'createdAt': 1,
    }, 'legacy-post-id');

    expect(post.allowedUserIds, legacyAudience);
    expect(post.visibleToCategoryIds, const <String>['legacy-group']);
  });

  test('meetup parser prefers canonical frozen audience fields', () {
    final meetup = Meetup.fromJson({
      'id': 'meetup-id',
      'ownerId': 'owner',
      'userId': 'wrong-owner',
      'visibilityMode': 'category',
      'visibility': 'public',
      'audienceUserIdsFrozen': canonicalAudience,
      'allowedUserIds': legacyAudience,
      'sourceGroupIds': sourceGroups,
      'visibleToCategoryIds': const <String>['wrong-group'],
      'visibilitySchemaVersion': 2,
      'date': DateTime.utc(2026, 7, 27),
    });

    expect(meetup.userId, 'owner');
    expect(meetup.visibility, 'category');
    expect(meetup.allowedUserIds, canonicalAudience);
    expect(meetup.visibleToCategoryIds, sourceGroups);
  });

  test('meetup parser accepts callable epoch millis and legacy host', () {
    final date = DateTime.utc(2026, 9, 3, 12, 30);
    final meetup = Meetup.fromJson({
      'id': 'search-result',
      'host': 'legacy-host',
      'date': date.millisecondsSinceEpoch,
      'createdAt': date.millisecondsSinceEpoch,
    });

    expect(meetup.host, 'legacy-host');
    expect(meetup.date.millisecondsSinceEpoch, date.millisecondsSinceEpoch);
    expect(
      meetup.createdAt.millisecondsSinceEpoch,
      date.millisecondsSinceEpoch,
    );
  });

  test('post parser accepts callable epoch millis and frozen audience', () {
    final createdAt = DateTime.utc(2026, 9, 4, 1, 15);
    final post = Post.fromMap({
      'content': '검색 결과',
      'createdAt': createdAt.millisecondsSinceEpoch,
      'ownerId': 'owner',
      'visibilityMode': 'category',
      'audienceUserIdsFrozen': const ['owner', 'viewer'],
      'sourceGroupIds': const ['group'],
      'visibilitySchemaVersion': 2,
      'visibilityLockedAt': createdAt.millisecondsSinceEpoch,
    }, 'search-post');

    expect(post.id, 'search-post');
    expect(post.createdAt.millisecondsSinceEpoch,
        createdAt.millisecondsSinceEpoch);
    expect(post.userId, 'owner');
    expect(post.visibility, 'category');
    expect(post.allowedUserIds, const ['owner', 'viewer']);
  });

  test('snapshot parser prefers canonical path and audience fields', () {
    final snapshot = SnapshotItem.fromMap('snapshot-id', {
      'ownerId': 'owner',
      'authorId': 'wrong-owner',
      'visibilityMode': 'category',
      'visibility': 'public',
      'audienceUserIdsFrozen': canonicalAudience,
      'allowedUserIds': legacyAudience,
      'sourceGroupIds': sourceGroups,
      'visibleToCategoryIds': const <String>['wrong-group'],
      'imageStoragePath': 'snapshots/snapshot-id/final.jpg',
      'storagePath': 'wrong/path.jpg',
      'visibilitySchemaVersion': 2,
      'createdAt': DateTime.utc(2026, 7, 27),
      'expiresAt': DateTime.utc(2026, 7, 28),
    });

    expect(snapshot.authorId, 'owner');
    expect(snapshot.visibility, SnapshotVisibility.category);
    expect(snapshot.allowedUserIds, canonicalAudience);
    expect(snapshot.visibleToCategoryIds, sourceGroups);
    expect(snapshot.imageStoragePath, 'snapshots/snapshot-id/final.jpg');
  });
}
