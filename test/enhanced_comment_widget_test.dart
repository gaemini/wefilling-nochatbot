import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/constants/app_constants.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/comment.dart';
import 'package:wefilling/ui/widgets/enhanced_comment_widget.dart';

import 'support/translation_test_backend.dart';

const _me = 'comment-test-me';
const _other = 'comment-test-other';
const _postId = 'comment-test-post';

Comment _comment({
  String id = 'c1',
  String userId = _other,
  String content = '하이템플러가 있네요?',
  int likeCount = 0,
  List<String> likedBy = const [],
  String gifStoragePath = '',
  int depth = 0,
  String? replyTo,
}) =>
    Comment(
      id: id,
      postId: _postId,
      userId: userId,
      authorNickname: 'A commenter with a deliberately long nickname here',
      authorPhotoUrl: '',
      content: content,
      gifStoragePath: gifStoragePath,
      createdAt: DateTime.now().subtract(const Duration(minutes: 17)),
      depth: depth,
      parentCommentId: depth > 0 ? 'parent' : null,
      replyToUserId: replyTo == null ? null : 'reply-target',
      replyToUserNickname: replyTo,
      likeCount: likeCount,
      likedBy: likedBy,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = TranslationTestBackend();
  setUpAll(() async {
    await backend.initialize();
    await backend.setAccount(_me);
  });
  tearDownAll(backend.close);

  Future<void> pump(
    WidgetTester tester,
    Comment comment, {
    PostCommentQuote? quote,
    bool showHeader = true,
    bool groupedWithPrevious = false,
    bool groupedWithNext = false,
    bool anonymous = false,
    double width = 375,
    double textScale = 1,
    Locale locale = const Locale('ko'),
  }) async {
    final size = Size(width, 900);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: EnhancedCommentWidget(
                comment: comment,
                postId: _postId,
                quote: quote,
                showHeader: showHeader,
                groupedWithPrevious: groupedWithPrevious,
                groupedWithNext: groupedWithNext,
                isAnonymousPost: anonymous,
                getDisplayName: (_) => '익명 1',
                watchAuthorProfile: false,
              ),
            ),
          ),
        ),
      ),
    );
    // 번역 큐의 배치 타이머가 끝나도록 충분히 흘려보낸다.
    await tester.pump(const Duration(seconds: 30));
  }

  // 번역 큐가 비동기 응답 뒤에 예약하는 타이머까지 테스트 안에서 비운다.
  void testComment(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 5));
    });
  }

  Finder badge(String id) =>
      find.byKey(ValueKey<String>('comment-like-badge:$id'));

  testComment('likeCount 0이면 배지가 없다', (tester) async {
    await pump(tester, _comment());
    expect(find.byKey(const ValueKey('comment-bubble:c1')), findsOneWidget);
    expect(badge('c1'), findsNothing);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
  });

  testComment('좋아요가 있으면 배지가 보이고 내가 누른 상태는 point 색이다',
      (tester) async {
    await pump(tester, _comment(likeCount: 2, likedBy: const [_me, 'x']));
    expect(badge('c1'), findsOneWidget);
    final count = tester.widget<Text>(
      find.byKey(const ValueKey('comment-like-count:c1')),
    );
    expect(count.data, '2');
    expect(count.style?.color, AppColors.pointColor);
    // 배지 터치 영역은 44 이상이다.
    final hit = tester.getSize(badge('c1'));
    expect(hit.width, greaterThanOrEqualTo(44));
    expect(hit.height, greaterThanOrEqualTo(44));
  });

  testComment('남이 누른 좋아요만 있으면 배지는 tertiary 색이다', (tester) async {
    await pump(tester, _comment(likeCount: 1, likedBy: const ['x']));
    final count = tester.widget<Text>(
      find.byKey(const ValueKey('comment-like-count:c1')),
    );
    expect(count.style?.color, isNot(AppColors.pointColor));
  });

  testComment('내 댓글은 오른쪽 정렬이고 아바타가 없다', (tester) async {
    await pump(tester, _comment(userId: _me, content: '와 출근을 안했다라...?'));
    final bubble = tester.getRect(find.byKey(const ValueKey('comment-bubble:c1')));
    expect(bubble.right, closeTo(375 - 16, 1));
    expect(find.byIcon(Icons.person), findsNothing);
    expect(
      find.text('A commenter with a deliberately long nickname here'),
      findsNothing,
    );
  });

  testComment('다른 사람 댓글은 왼쪽 정렬이고 아바타가 있다', (tester) async {
    await pump(tester, _comment());
    final bubble = tester.getRect(find.byKey(const ValueKey('comment-bubble:c1')));
    expect(bubble.left, lessThan(375 / 2));
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testComment('익명 포스트에서는 아바타가 없다', (tester) async {
    await pump(tester, _comment(), anonymous: true);
    expect(find.byIcon(Icons.person), findsNothing);
    expect(find.text('익명 1'), findsOneWidget);
  });

  testComment('대화형 보기: 답글은 @아이디 대신 인용 줄을 말풍선 안에 그린다',
      (tester) async {
    await pump(
      tester,
      _comment(id: 'r1', depth: 1, content: '토요일 간거입니다', replyTo: 'JBum'),
      quote: const PostCommentQuote(
        targetId: 'c0',
        authorName: 'JBum',
        text: '와 출근을 안했다라...?',
      ),
    );
    expect(find.byKey(const ValueKey('comment-quote:r1')), findsOneWidget);
    expect(find.text('JBum'), findsOneWidget);
    expect(find.text('와 출근을 안했다라...?'), findsOneWidget);
    expect(find.textContaining('@JBum'), findsNothing);
  });

  testComment('인용 대상이 삭제됐으면 기존 문구, 사진만이면 사진', (tester) async {
    await pump(
      tester,
      _comment(id: 'r1', depth: 1, content: '응'),
      quote: const PostCommentQuote(
        targetId: 'c0',
        authorName: 'A',
        text: '',
        isDeleted: true,
      ),
    );
    expect(find.text('삭제된 댓글입니다.'), findsOneWidget);
    await pump(
      tester,
      _comment(id: 'r2', depth: 1, content: '응'),
      quote: const PostCommentQuote(
        targetId: 'c0',
        authorName: 'A',
        text: '',
        isMedia: true,
      ),
    );
    expect(find.text('사진'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testComment('묶음 안의 메시지는 아바타·이름·시간이 없다', (tester) async {
    await pump(tester, _comment(), showHeader: false, groupedWithPrevious: true);
    expect(find.byIcon(Icons.person), findsNothing);
    expect(
      find.text('A commenter with a deliberately long nickname here'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('comment-bubble:c1')), findsOneWidget);
  });

  testComment('삭제된 댓글은 가운데 한 줄 시스템 표시다', (tester) async {
    await pump(
      tester,
      Comment(
        id: 'd1',
        postId: _postId,
        userId: _other,
        authorNickname: 'x',
        authorPhotoUrl: '',
        content: '',
        createdAt: DateTime.now(),
        isDeleted: true,
      ),
    );
    final text = tester.widget<Text>(find.text('삭제된 댓글입니다.'));
    expect(text.textAlign, TextAlign.center);
    expect(text.style?.fontSize, 12);
  });

  const contents = <String, String>{
    'short': 'ㅋ',
    'long': '문화의 도시 안산에서 이렇게 긴 댓글을 남기면 말풍선이 화면 끝까지 붙지 않고 오른쪽에 여백을 남겨야 합니다.',
    'multiline': '첫째 줄\n둘째 줄\n셋째 줄',
    'emoji': '😀🎉👍🏽🇰🇷 좋아요!!',
    'english': 'This is a reasonably long English comment that should wrap nicely.',
    'chinese': '这是一个比较长的中文评论，用来检查换行和行高是否正常显示。',
    'link': '여기 보세요 https://example.com/a/very/long/path?with=query&and=more',
    'unbroken': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  };

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testComment('오버플로우 없음 width=$width scale=$scale', (tester) async {
        for (final entry in contents.entries) {
          for (final mine in const [false, true]) {
            await pump(
              tester,
              _comment(
                id: '${entry.key}-$mine',
                userId: mine ? _me : _other,
                content: entry.value,
                likeCount: 12,
                likedBy: const [_me],
              ),
              quote: PostCommentQuote(
                targetId: 'quoted',
                authorName: 'KyJung with a very long display name indeed',
                text: entry.value,
              ),
              width: width,
              textScale: scale,
              locale: entry.key == 'chinese'
                  ? const Locale('zh')
                  : const Locale('ko'),
            );
            expect(tester.takeException(), isNull,
                reason: '${entry.key} mine=$mine');
          }
        }
      });
    }
  }

  testComment('GIF 댓글은 본문 없이도 오버플로우가 없다', (tester) async {
    await pump(
      tester,
      _comment(
        content: '',
        gifStoragePath: 'post_comment_gifs/$_postId/c1.gif',
        likeCount: 1,
      ),
      width: 320,
      textScale: 2,
    );
    expect(find.byKey(const ValueKey('comment-bubble:c1')), findsNothing);
    expect(badge('c1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
