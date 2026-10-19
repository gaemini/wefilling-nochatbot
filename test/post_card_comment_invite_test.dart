import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:wefilling/services/comment_invite_nudge_gate.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/ui/widgets/post_action_group.dart';
import 'package:wefilling/ui/widgets/post_card_comment_invite.dart';

Post _post({String type = 'text', PostLatestComment? latest}) => Post(
      id: 'p1',
      title: '',
      content: '다음 학기 교양 추천해 주세요',
      author: 'jaemin',
      createdAt: DateTime(2026, 10, 10),
      userId: 'author-uid',
      type: type,
      latestComment: latest,
    );

const _latest = PostLatestComment(
  commentId: 'c1',
  authorId: 'sound-uid',
  authorName: 'sound',
  text: 'ㅋㅋㅋ 수업 시간에 뭐 하는 거야',
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 가시성 감지는 테스트에서 프레임마다(앱 설정은 그대로).
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    CommentInviteNudgeGate.instance.debugReset();
  });
  tearDown(() => CommentInviteNudgeGate.instance.debugReset());

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

  testWidgets('좁은 화면에서도 넘치지 않고, 누르면 시트 없이 카드 위에서 바로 입력',
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
    // 시트·어두운 배경 없이 카드 안 입력칸이 포커스를 받는다.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const ValueKey('post-card-comment-composer:p1')),
        findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  group('① 최근 댓글 한 줄', () {
    Widget invite({PostLatestComment? latest, int count = 4, Set<String>? blocked}) =>
        _host(PostCardCommentInvite(
          post: _post(latest: latest),
          commentCount: count,
          onOpenComments: () {},
          debugViewerId: 'me',
          debugBlockedIds: blocked ?? const {},
        ));

    testWidgets('있으면 이름·본문 한 줄 + 댓글 n개 모두 보기', (tester) async {
      await tester.pumpWidget(invite(latest: _latest));
      expect(find.textContaining('sound', findRichText: true), findsOneWidget);
      expect(find.textContaining('ㅋㅋㅋ 수업 시간에', findRichText: true),
          findsOneWidget);
      expect(find.text('댓글 4개 모두 보기'), findsOneWidget);
    });

    testWidgets('없거나 댓글 0개면 둘 다 숨기고 입력 줄만', (tester) async {
      await tester.pumpWidget(invite());
      expect(find.textContaining('모두 보기'), findsNothing);
      await tester.pumpWidget(invite(latest: _latest, count: 0));
      expect(find.textContaining('sound', findRichText: true), findsNothing);
      expect(find.textContaining('모두 보기'), findsNothing);
      expect(find.text('어떻게 생각하세요?'), findsOneWidget);
    });

    testWidgets('차단 관계면 숨기고, 익명은 익명으로', (tester) async {
      await tester.pumpWidget(invite(latest: _latest, blocked: {'sound-uid'}));
      expect(find.textContaining('ㅋㅋㅋ', findRichText: true), findsNothing);
      await tester.pumpWidget(invite(
          latest: const PostLatestComment(
              commentId: 'c2', authorId: 'x', isAnonymous: true, text: '좋아요')));
      expect(find.textContaining('익명', findRichText: true), findsOneWidget);
    });
  });

  group('④ 보낸 뒤', () {
    tearDown(() => PostCardCommentInvite.debugAddComment = null);

    Future<void> send(WidgetTester tester, String text) async {
      await tester.tap(find.byKey(const ValueKey('post-card-comment-invite:p1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), text);
      // 보내기 버튼이 톡 나타날 때까지.
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-card-comment-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('성공: 내 댓글 줄로 바뀌고 ✓ 알약이 2.2초 뒤 사라진다', (tester) async {
      PostCardCommentInvite.debugAddComment = (_, __) async => true;
      await tester.pumpWidget(_host(PostCardCommentInvite(
        post: _post(latest: _latest),
        commentCount: 4,
        onOpenComments: () {},
        debugViewerId: 'me',
        debugBlockedIds: const {},
      )));
      await send(tester, '저도 궁금해요');
      expect(find.textContaining('저도 궁금해요', findRichText: true), findsOneWidget);
      expect(find.textContaining('ㅋㅋㅋ', findRichText: true), findsNothing);
      expect(find.text('댓글을 남겼어요'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2300));
      await tester.pumpAndSettle();
      expect(find.text('댓글을 남겼어요'), findsNothing);
    });

    testWidgets('실패: 시트에 실패 표시, 카드는 그대로', (tester) async {
      PostCardCommentInvite.debugAddComment = (_, __) async => false;
      await tester.pumpWidget(_host(PostCardCommentInvite(
        post: _post(latest: _latest),
        commentCount: 4,
        onOpenComments: () {},
        debugViewerId: 'me',
        debugBlockedIds: const {},
      )));
      await send(tester, '저도 궁금해요');
      expect(find.text('댓글을 남기지 못했어요.'), findsOneWidget);
      expect(find.text('댓글을 남겼어요'), findsNothing);
    });
  });

  testWidgets('④ 댓글 수가 늘면 숫자가 톡 튄다(줄면 그대로)', (tester) async {
    Widget group(int comments) => _host(PostActionGroup(
          likes: 5,
          comments: comments,
          views: 21,
          isLiked: false,
          likeLabel: 'like',
          commentLabel: 'comment',
          viewsLabel: 'views',
          onCommentTap: () {},
          compact: true,
        ));
    Finder popped() => find.byWidgetPredicate((w) =>
        w is Transform &&
        w.transform.getMaxScaleOnAxis() > 1.05 &&
        w.transform.getMaxScaleOnAxis() < 1.2);
    await tester.pumpWidget(group(4));
    await tester.pumpWidget(group(5));
    await tester.pump(const Duration(milliseconds: 140));
    expect(popped(), findsWidgets);
    await tester.pumpAndSettle();
    expect(popped(), findsNothing);
    await tester.pumpWidget(group(4));
    await tester.pump(const Duration(milliseconds: 140));
    expect(popped(), findsNothing);
    await tester.pumpAndSettle();
  });

  group('③ 하단 시트', () {
    var sent = 0;
    setUp(() {
      sent = 0;
      PostCardCommentInvite.debugAddComment = (_, __) async {
        sent++;
        return true;
      };
    });
    tearDown(() => PostCardCommentInvite.debugAddComment = null);

    Widget sheetHost({Locale locale = const Locale('ko'), String category = 'other'}) =>
        MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: PostCardCommentInvite(
              post: Post(
                id: 'p1',
                title: '',
                content: '다음 학기 교양 추천해 주세요',
                author: 'jaemin',
                createdAt: DateTime(2026, 10, 10),
                userId: 'author-uid',
                categoryKey: category,
              ),
              commentCount: 0,
              onOpenComments: () {},
              debugViewerId: 'me',
              debugBlockedIds: const {},
            ),
          ),
        );

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('post-card-comment-invite:p1')));
      await tester.pumpAndSettle();
    }

    double sendScale(WidgetTester tester) => tester
        .widget<AnimatedScale>(find.ancestor(
            of: find.byKey(const ValueKey('post-card-comment-send')),
            matching: find.byType(AnimatedScale)))
        .scale;

    testWidgets('분류별 추천 문장, 누르면 채우기만(전송 없음), 보내기 버튼 등장', (tester) async {
      await tester.pumpWidget(sheetHost(category: 'academic_study'));
      await open(tester);
      expect(find.text('수업 화이팅!'), findsOneWidget);
      expect(find.text('무슨 수업이에요?'), findsOneWidget);
      expect(sendScale(tester), 0);
      await tester.tap(find.byKey(const ValueKey('post-card-comment-suggestion-1')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '무슨 수업이에요?');
      expect(field.controller!.selection.baseOffset, '무슨 수업이에요?'.length);
      expect(sent, 0);
      expect(sendScale(tester), 1);
      // 글자가 생기면 추천 문장은 사라진다.
      expect(find.text('수업 화이팅!'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(sendScale(tester), 0);
    });

    testWidgets('미리보기: 추천 문장은 작성자 언어 버전을 번역 호출 없이', (tester) async {
      await tester.pumpWidget(sheetHost(locale: const Locale('en')));
      await open(tester);
      await tester.tap(find.text('Nice!'));
      await tester.pumpAndSettle();
      expect(
          find.text('jaemin sees it in Korean · 좋네요!', findRichText: true),
          findsOneWidget);
      // 직접 쓴 글은 언어 안내까지만(목표 언어 번역 경로가 없다).
      await tester.enterText(find.byType(TextField), 'Where is this place?');
      await tester.pumpAndSettle();
      expect(find.text('jaemin sees it in Korean', findRichText: true),
          findsOneWidget);
    });

    testWidgets('작성자 언어가 내 언어와 같으면 미리보기 없음', (tester) async {
      await tester.pumpWidget(sheetHost());
      await open(tester);
      await tester.enterText(find.byType(TextField), '좋아요');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('post-card-comment-preview')), findsNothing);
    });

    testWidgets('비운 채로 포커스를 잃으면 원래 입력 줄로', (tester) async {
      await tester.pumpWidget(sheetHost());
      await open(tester);
      tester.widget<TextField>(find.byType(TextField)).focusNode!.unfocus();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('post-card-comment-composer:p1')),
          findsNothing);
      expect(find.text('어떻게 생각하세요?'), findsOneWidget);
    });
  });
}
