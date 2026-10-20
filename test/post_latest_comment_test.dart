import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/post.dart';

void main() {
  test('Firestore Timestamp·캐시 millis 모두 읽고, 캐시 왕복이 같다', () {
    final at = DateTime(2026, 10, 20, 9, 30);
    final parsed = PostLatestComment.tryParse({
      'commentId': 'c1',
      'authorId': 'u1',
      'authorName': 'sound',
      'isAnonymous': false,
      'text': 'ㅋㅋㅋ 수업 시간에 뭐 하는 거야',
      'createdAt': Timestamp.fromDate(at),
    })!;
    expect(parsed.authorName, 'sound');
    expect(parsed.createdAt, at);
    final post = Post(
      id: 'p1',
      title: '',
      content: 'x',
      author: 'a',
      createdAt: at,
      userId: 'a',
      latestComment: parsed,
    );
    final restored = Post.fromMap(post.toMap(), 'p1').latestComment!;
    expect(restored.text, parsed.text);
    expect(restored.createdAt, at);
    expect(post.copyWith(commentCount: 3).latestComment, same(parsed));
  });

  test('필드가 없거나 형식이 다르면 null(구버전 문서)', () {
    expect(PostLatestComment.tryParse(null), isNull);
    expect(PostLatestComment.tryParse({'text': 'x'}), isNull);
    expect(PostLatestComment.tryParse('x'), isNull);
  });
}
