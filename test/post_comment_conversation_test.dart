import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/comment.dart';
import 'package:wefilling/utils/chat_date_label.dart';
import 'package:wefilling/utils/post_comment_conversation.dart';

Comment _c(
  String id, {
  String user = 'u1',
  required DateTime at,
  bool deleted = false,
  String? parent,
  String? replyTo,
}) =>
    Comment(
      id: id,
      postId: 'p',
      userId: user,
      authorNickname: user,
      authorPhotoUrl: '',
      content: id,
      createdAt: at,
      isDeleted: deleted,
      parentCommentId: parent,
      depth: parent == null ? 0 : 1,
      replyToCommentId: replyTo,
    );

void main() {
  final t0 = DateTime(2026, 10, 13, 12);

  group('shouldGroupPostComments', () {
    test('같은 사람, 5분 이내, 같은 날이면 묶는다', () {
      expect(
        shouldGroupPostComments(
          _c('a', at: t0),
          _c('b', at: t0.add(const Duration(minutes: 5))),
        ),
        isTrue,
      );
    });

    test('5분을 넘거나 다른 사람이면 묶지 않는다', () {
      expect(
        shouldGroupPostComments(
          _c('a', at: t0),
          _c('b', at: t0.add(const Duration(minutes: 5, seconds: 1))),
        ),
        isFalse,
      );
      expect(
        shouldGroupPostComments(
          _c('a', at: t0),
          _c('b', user: 'u2', at: t0.add(const Duration(minutes: 1))),
        ),
        isFalse,
      );
    });

    test('삭제·숨김·첫 메시지·자정을 넘기면 묶지 않는다', () {
      final a = _c('a', at: t0);
      final b = _c('b', at: t0.add(const Duration(minutes: 1)));
      expect(shouldGroupPostComments(null, b), isFalse);
      expect(
        shouldGroupPostComments(
            a, _c('b', at: b.createdAt, deleted: true)),
        isFalse,
      );
      expect(shouldGroupPostComments(a, b, previousHidden: true), isFalse);
      expect(shouldGroupPostComments(a, b, nextHidden: true), isFalse);
      final late = DateTime(2026, 10, 13, 23, 58);
      expect(
        shouldGroupPostComments(
          _c('x', at: late),
          _c('y', at: late.add(const Duration(minutes: 3))),
        ),
        isFalse,
      );
    });

    test('탈퇴 계정(deleted)은 묶지 않는다', () {
      expect(
        shouldGroupPostComments(
          _c('a', user: 'deleted', at: t0),
          _c('b', user: 'deleted', at: t0.add(const Duration(minutes: 1))),
        ),
        isFalse,
      );
    });
  });

  group('인용 줄', () {
    test('대상은 replyToCommentId, 없으면 parentCommentId', () {
      expect(
        postCommentQuoteTargetId(_c('r', at: t0, parent: 'p1', replyTo: 'r0')),
        'r0',
      );
      expect(postCommentQuoteTargetId(_c('r', at: t0, parent: 'p1')), 'p1');
      expect(postCommentQuoteTargetId(_c('top', at: t0)), isNull);
    });

    test('답장은 대상이 바로 앞 메시지여도 인용을 보여 준다', () {
      final target = _c('p1', at: t0);
      final reply = _c('r', at: t0, parent: 'p1');
      expect(shouldShowPostCommentQuote(reply, target), isTrue);
      expect(
        shouldShowPostCommentQuote(reply, _c('other', at: t0)),
        isTrue,
      );
      expect(shouldShowPostCommentQuote(reply, null), isTrue);
      expect(shouldShowPostCommentQuote(_c('top', at: t0), null), isFalse);
    });
  });

  group('chatDayLabel', () {
    test('오늘·어제·그 밖의 날', () {
      final now = DateTime(2026, 10, 13, 9);
      String label(DateTime d) => chatDayLabel(d,
          languageCode: 'ko', today: '오늘', yesterday: '어제', now: now);
      expect(label(DateTime(2026, 10, 13, 0, 1)), '오늘');
      expect(label(DateTime(2026, 10, 12, 23, 59)), '어제');
      expect(label(DateTime(2026, 10, 11)), '2026년 10월 11일 일요일');
    });
  });
}
