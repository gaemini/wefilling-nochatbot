import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/ui/widgets/post_card_comment_invite.dart';

Post _post({String type = 'text'}) => Post(
      id: 'p1',
      title: '',
      content: '다음 학기 교양 추천해 주세요',
      author: 'jaemin',
      createdAt: DateTime(2026, 10, 10),
      userId: 'author-uid',
      type: type,
    );

Widget _host(Widget child, {double width = 360}) => MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

void main() {
  testWidgets('댓글 수와 카드 종류에 상관없이 같은 문구 하나를 쓴다', (tester) async {
    for (final (type, count) in <(String, int)>[
      ('text', 0),
      ('text', 3),
      ('poll', 5),
    ]) {
      await tester.pumpWidget(_host(PostCardCommentInvite(
        post: _post(type: type),
        commentCount: count,
        onOpenComments: () {},
        debugViewerId: 'me',
      )));
      expect(find.text('어떻게 생각하세요?'), findsOneWidget);
    }
    expect(find.text('댓글로 대화에 참여하기'), findsNothing);
    expect(find.text('투표하고 이유를 남겨 보세요'), findsNothing);
  });

  testWidgets('좁은 화면에서도 넘치지 않고, 탭하면 카드 위에서 바로 입력 시트가 열린다',
      (tester) async {
    await tester.pumpWidget(_host(
      PostCardCommentInvite(
        post: _post(),
        commentCount: 0,
        onOpenComments: () {},
        debugViewerId: 'me',
      ),
      width: 280,
    ));
    expect(tester.takeException(), isNull);
    final pill = find.byKey(const ValueKey('post-card-comment-invite:p1'));
    expect(tester.getSize(pill).height, greaterThanOrEqualTo(36));

    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(find.text('댓글 달기…'), findsOneWidget);
    expect(find.textContaining('어떤 언어로 써도'), findsOneWidget);
    // 어떤 글에 다는 댓글인지 한 줄로 보인다.
    expect(find.textContaining('다음 학기 교양 추천해 주세요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
