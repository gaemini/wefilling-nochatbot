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
