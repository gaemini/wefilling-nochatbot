import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/services/comment_invite_nudge_gate.dart';
import 'package:wefilling/ui/widgets/post_card_comment_invite.dart';

Post _post() => Post(
      id: 'p1',
      title: '',
      content: '다음 학기 교양 추천해 주세요',
      author: '아주긴닉네임을가진작성자입니다',
      createdAt: DateTime(2026, 10, 10),
      userId: 'author-uid',
      categoryKey: 'academic_study',
      latestComment: const PostLatestComment(
        commentId: 'c1',
        authorId: 'x',
        authorName: '아주아주긴이름의댓글작성자',
        text: '아주 긴 댓글 본문이라서 한 줄을 넘어갈 수도 있는 문장입니다 정말로 깁니다',
      ),
    );

/// 넘침 검사: 폭 320/375/430 × 글자 배율 1.0/1.3 × ko/en/zh,
/// 상태: 기본(최근 댓글) · 반응 중(고리 최대) · 문구 2·3 · 시트 빈 상태(추천 문장)
/// · 시트 입력 중(미리보기) · 보낸 뒤.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    CommentInviteNudgeGate.instance.debugReset();
    PostCardCommentInvite.debugAddComment = (_, __) async => true;
    PostCardCommentInvite.debugTranslateLatest = false;
  });
  tearDown(() {
    CommentInviteNudgeGate.instance.debugReset();
    PostCardCommentInvite.debugAddComment = null;
    PostCardCommentInvite.debugTranslateLatest = true;
  });

  for (final width in [320.0, 375.0, 430.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('카드 댓글 넘침 없음 ${width.toInt()} / ${scale}x', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.reset);
        for (final locale in const [Locale('ko'), Locale('en'), Locale('zh')]) {
          CommentInviteNudgeGate.instance.debugReset();
          await tester.pumpWidget(MaterialApp(
            locale: locale,
            supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: PostCardCommentInvite(
                    post: _post(),
                    commentCount: 12,
                    onOpenComments: () {},
                    debugViewerId: 'me',
                    debugBlockedIds: const {},
                  ),
                ),
              ),
            ),
          ));
          // 기본 → 반응(고리 최대 근처) → 문구 2·3.
          for (var i = 0; i < 18; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull, reason: 'nudge $locale');
          for (var i = 0; i < 60; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull, reason: 'phrases $locale');
          // 시트: 빈 상태(추천 문장) → 입력 중(미리보기) → 보낸 뒤.
          await tester.tap(
              find.byKey(const ValueKey('post-card-comment-invite:p1')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'sheet $locale');
          await tester.tap(
              find.byKey(const ValueKey('post-card-comment-suggestion-0')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'preview $locale');
          await tester
              .tap(find.byKey(const ValueKey('post-card-comment-send')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull, reason: 'sent $locale');
          await tester.pump(const Duration(seconds: 3));
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }
  }
}
