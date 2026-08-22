import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/post.dart';

Post _post({required String title, required String content}) {
  return Post(
    id: 'post-id',
    title: title,
    content: content,
    author: '작성자',
    createdAt: DateTime(2026, 8, 22),
    userId: 'user-id',
  );
}

void main() {
  group('Post.displayText', () {
    test('현재 포스트의 content를 단일 표시 본문으로 사용한다', () {
      final post = _post(title: '과거 제목', content: '  현재 본문  ');

      expect(post.displayText, '현재 본문');
      expect(post.getPreviewContent(), '현재 본문');
    });

    test('content가 없는 과거 데이터는 title로 폴백한다', () {
      final post = _post(title: '  과거 제목  ', content: '   ');

      expect(post.displayText, '과거 제목');
      expect(post.getPreviewContent(), '과거 제목');
    });
  });
}
