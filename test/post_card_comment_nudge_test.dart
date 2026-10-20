import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/services/comment_invite_nudge_gate.dart';
import 'package:wefilling/ui/widgets/post_card_comment_invite.dart';

Post _post(String id, {String author = 'jaemin', String userId = 'author-uid'}) =>
    Post(
      id: id,
      title: '',
      content: '다음 학기 교양 추천해 주세요',
      author: author,
      createdAt: DateTime(2026, 10, 10),
      userId: userId,
    );

Widget _host(List<Widget> children,
        {Locale locale = const Locale('ko'), bool reduce = false}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: MediaQuery(
        data: MediaQueryData(
            size: const Size(400, 800), disableAnimations: reduce),
        child: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final child in children)
                Padding(padding: const EdgeInsets.all(8), child: child),
            ],
          ),
        ),
      ),
    );

Widget _invite(Post post, {String viewer = 'me'}) => PostCardCommentInvite(
      key: ValueKey('invite:${post.id}'),
      post: post,
      commentCount: 0,
      onOpenComments: () {},
      debugViewerId: viewer,
      debugBlockedIds: const {},
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    CommentInviteNudgeGate.instance.debugReset();
  });
  tearDown(() => CommentInviteNudgeGate.instance.debugReset());

  final gate = CommentInviteNudgeGate.instance;
  const phrase2 = 'jaemin에게 한마디 남겨 볼까요?';

  Future<void> settleTo(WidgetTester tester, Duration total) async {
    var left = total;
    while (left > Duration.zero) {
      final step = left > const Duration(milliseconds: 100)
          ? const Duration(milliseconds: 100)
          : left;
      await tester.pump(step);
      left -= step;
    }
  }

  testWidgets('800ms 전에는 반응하지 않고, 이후 한 번만(같은 날 다시 없음)', (tester) async {
    await tester.pumpWidget(_host([_invite(_post('p1'))]));
    await settleTo(tester, const Duration(milliseconds: 700));
    expect(gate.doneToday('p1'), isFalse);
    await settleTo(tester, const Duration(milliseconds: 300));
    expect(gate.doneToday('p1'), isTrue);
    // 2.6초 뒤 문구 2가 아래에서 올라온다.
    await settleTo(tester, const Duration(milliseconds: 2700));
    expect(find.text(phrase2), findsOneWidget);
    // 두 바퀴 뒤 문구 1에서 멈춘다(ko 화면 · 한국어 글: 문구 3 없음).
    await settleTo(tester, const Duration(seconds: 9));
    expect(find.text('어떻게 생각하세요?'), findsOneWidget);
    expect(find.textContaining('번역돼요'), findsNothing);

    // 같은 날 같은 카드를 다시 그려도 반응하지 않는다.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_host([_invite(_post('p1'))]));
    await settleTo(tester, const Duration(seconds: 4));
    expect(find.text(phrase2), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('내 글은 반응하지 않는다', (tester) async {
    await tester.pumpWidget(
        _host([_invite(_post('p2', userId: 'me'), viewer: 'me')]));
    await settleTo(tester, const Duration(seconds: 2));
    expect(gate.doneToday('p2'), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('여러 카드가 동시에 보이면 가장 위 카드만', (tester) async {
    await tester.pumpWidget(_host([
      _invite(_post('top')),
      _invite(_post('middle')),
      _invite(_post('bottom')),
    ]));
    await settleTo(tester, const Duration(seconds: 1));
    expect(gate.doneToday('top'), isTrue);
    expect(gate.doneToday('middle'), isFalse);
    expect(gate.doneToday('bottom'), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('동작 줄이기: 고리·회전·문구 회전 없이 문구 1 고정', (tester) async {
    await tester.pumpWidget(_host([_invite(_post('p3'))], reduce: true));
    await settleTo(tester, const Duration(seconds: 4));
    expect(gate.doneToday('p3'), isTrue);
    expect(find.text('어떻게 생각하세요?'), findsOneWidget);
    expect(find.text(phrase2), findsNothing);
    expect(
        find.byWidgetPredicate((w) =>
            // Y축 회전(번역 아이콘)만 본다.
            w is Transform && w.transform.storage[8].abs() > .01),
        findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('글의 원문 언어가 내 언어와 다르면 문구 3', (tester) async {
    await tester.pumpWidget(
        _host([_invite(_post('p4'))], locale: const Locale('en')));
    await settleTo(tester, const Duration(seconds: 1));
    final seen = <String>{};
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        if (t.data != null) seen.add(t.data!);
      }
    }
    expect(seen, contains('Say something to jaemin?'));
    expect(seen, contains("Write in English, they'll read it in Korean"));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('누르면 회전이 멈추고 오늘 다시 반응하지 않는다', (tester) async {
    await tester.pumpWidget(_host([_invite(_post('p5'))]));
    await tester.tap(find.byKey(const ValueKey('post-card-comment-invite:p5')));
    await tester.pumpAndSettle();
    expect(gate.doneToday('p5'), isTrue);
  });
}
