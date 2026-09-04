import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/repositories/users_repository.dart';
import 'package:wefilling/services/post_media_prefetch_service.dart';

Post _post(String id, List<String> imageUrls) {
  return Post(
    id: id,
    title: '',
    content: id,
    author: 'author',
    createdAt: DateTime(2026, 9, 4),
    userId: 'user-$id',
    imageUrls: imageUrls,
  );
}

void main() {
  test('피드 프리페치는 카드당 대표 이미지 하나만 순서대로 고른다', () {
    final urls = selectPostMediaPrefetchUrls(
      <Post>[
        _post('one', <String>[' https://cdn.test/1.jpg ', 'ignored.jpg']),
        _post('duplicate', <String>['https://cdn.test/1.jpg']),
        _post('empty', const <String>[]),
        _post('two', <String>['https://cdn.test/2.jpg']),
        _post('three', <String>['https://cdn.test/3.jpg']),
      ],
      maxPosts: 2,
    );

    expect(
      urls,
      <String>['https://cdn.test/1.jpg', 'https://cdn.test/2.jpg'],
    );
  });

  test('프로필 UID 배치는 빈 값과 중복을 제거하고 순서를 유지한다', () {
    final batches = buildUserProfileQueryBatches(
      <String>[' a ', 'b', '', 'a', 'c', 'd', 'e'],
      batchSize: 2,
    );

    expect(
      batches,
      <List<String>>[
        <String>['a', 'b'],
        <String>['c', 'd'],
        <String>['e'],
      ],
    );
  });

  test('프로필 UID 배치는 잘못된 크기를 거절한다', () {
    expect(
      () => buildUserProfileQueryBatches(<String>['a'], batchSize: 0),
      throwsArgumentError,
    );
  });
}
