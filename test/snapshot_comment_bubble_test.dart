import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snapshot.dart';
import 'package:wefilling/screens/snapshot_comments_sheet.dart';

SnapshotComment _comment(String id, String text,
        {String user = 'u1', String? parent, String? replyNick}) =>
    SnapshotComment(
      id: id,
      snapshotId: 's1',
      userId: user,
      authorNickname: 'Wefilling',
      authorPhotoUrl: '',
      content: text,
      createdAt: DateTime(2026, 10, 13),
      parentCommentId: parent,
      replyToUserNickname: replyNick,
    );

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: ListView(children: [child])),
      ),
    );

void main() {
  testWidgets('내 말풍선은 오른쪽·파란색, 이름과 사진 없음', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(SnapshotCommentRow(
      comment: _comment('c1', '안녕하세요', user: 'me'),
      isMine: true,
      highlighted: false,
      onReply: () {},
      onMore: () {},
      replyLabel: '답글',
      deletedLabel: '삭제됨',
    )));
    expect(find.text('Wefilling'), findsNothing);
    final bubble = tester.getRect(find.text('안녕하세요'));
    expect(bubble.right, greaterThan(375 - 40));
    final decorated = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.color == const Color(0xFF2C6BC0));
    expect(decorated, isNotEmpty);
  });

  testWidgets('답글은 ↩ 이름에게 표시, 답글 글자 버튼 없음, 밀어서 답장', (tester) async {
    var replies = 0;
    await tester.binding.setSurfaceSize(const Size(375, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(SnapshotCommentRow(
      comment: _comment('c2', '맞아요', parent: 'c1', replyNick: '민수'),
      replyToLabel: '↩ 민수에게',
      highlighted: false,
      onReply: () => replies++,
      onMore: () {},
      replyLabel: '답글',
      deletedLabel: '삭제됨',
    )));
    expect(find.text('↩ 민수에게'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '답글'), findsNothing);
    await tester.fling(find.text('맞아요'), const Offset(200, 0), 1500);
    await tester.pumpAndSettle();
    expect(replies, 1);
  });

  testWidgets('길게 누르면 더보기 메뉴 콜백', (tester) async {
    var more = 0;
    await tester.pumpWidget(_host(SnapshotCommentRow(
      comment: _comment('c3', '길게 누르기'),
      highlighted: false,
      onReply: () {},
      onMore: () => more++,
      replyLabel: '답글',
      deletedLabel: '삭제됨',
    )));
    await tester.longPress(find.text('길게 누르기'));
    expect(more, 1);
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('오버플로우 없음 $width/$scale', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final text in const [
          'ㅎㅎ',
          '아주아주아주 긴 댓글입니다 아주아주아주 긴 댓글입니다 아주아주아주 긴 댓글입니다 아주아주아주 긴 댓글입니다',
          'averyveryveryveryveryverylongunbrokenwordaveryveryveryveryverylongunbrokenword',
          '这是一个非常非常长的中文评论这是一个非常非常长的中文评论这是一个非常非常长的中文评论',
        ]) {
          for (final mine in [true, false]) {
            await tester.pumpWidget(_host(
              SnapshotCommentRow(
                comment: _comment('c', text),
                isMine: mine,
                replyToLabel: '↩ seoyeon_international_student_club에게',
                highlighted: false,
                onReply: () {},
                onMore: () {},
                replyLabel: '답글',
                deletedLabel: '삭제됨',
              ),
              scale: scale,
            ));
            expect(tester.takeException(), isNull, reason: '$text $mine');
          }
        }
      });
    }
  }
}
