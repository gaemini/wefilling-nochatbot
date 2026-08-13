import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/models/post_category.dart';

void main() {
  group('Post category parsing', () {
    test('parses style', () {
      expect(PostCategory.fromKey('style'), PostCategory.style);
    });

    test('parses books_writing', () {
      expect(PostCategory.fromKey('books_writing'), PostCategory.booksWriting);
    });

    test('falls back to other for null, empty, and unknown values', () {
      expect(PostCategory.fromKey(null), PostCategory.other);
      expect(PostCategory.fromKey(''), PostCategory.other);
      expect(PostCategory.fromKey('unknown'), PostCategory.other);
    });

    test('Post.fromMap treats a missing categoryKey as other', () {
      final post = Post.fromMap(
        {
          'title': 'legacy',
          'content': 'content',
          'createdAt': 0,
        },
        'legacy-id',
      );

      expect(post.categoryKey, 'other');
      expect(post.categoryKeys, <String>['other']);
      expect(post.postCategory, PostCategory.other);
    });

    test('Post normalizes unknown keys and stores a stable key', () {
      final post = Post(
        id: 'post-id',
        title: 'title',
        content: 'content',
        author: 'author',
        categoryKey: 'books_writing',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        userId: 'user-id',
      );

      expect(post.toMap()['categoryKey'], 'books_writing');
      expect(post.toMap()['categoryKeys'], <String>['books_writing']);
      expect(post.copyWith(categoryKey: 'unsupported').categoryKey, 'other');
    });

    test('Post keeps unique supported tag keys and a primary legacy key', () {
      final post = Post(
        id: 'multi-tag-post',
        title: 'title',
        content: 'content',
        author: 'author',
        categoryKey: 'style',
        categoryKeys: const <String>['photo', 'cafe', 'photo', 'unknown'],
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        userId: 'user-id',
      );

      expect(post.categoryKey, 'photo');
      expect(post.categoryKeys, <String>['photo', 'cafe']);
      expect(
        post.postCategories,
        <PostCategory>[PostCategory.photo, PostCategory.cafe],
      );
    });
  });
}
