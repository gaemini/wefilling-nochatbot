import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/design/tokens.dart';
import 'package:wefilling/ui/widgets/post_action_group.dart';

void main() {
  const widths = <double>[320, 360, 390, 430, 800];

  for (final width in widths) {
    for (final textScale in <double>[1, 3]) {
      for (final compact in <bool>[false, true]) {
        testWidgets(
          'actions ${compact ? 'compact' : 'default'} without overflow at '
          '${width}px and ${textScale}x text',
          (tester) async {
            var liked = false;
            var commentOpened = false;
            var saved = false;

            await tester.pumpWidget(
              MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 900),
                    textScaler: TextScaler.linear(textScale),
                  ),
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width,
                        child: PostActionGroup(
                          likes: 1234,
                          comments: 567,
                          views: 89012,
                          isLiked: liked,
                          likeLabel: 'Like',
                          commentLabel: 'Comments',
                          viewsLabel: 'Views',
                          onLikeTapUp: (_) => liked = true,
                          onCommentTap: () => commentOpened = true,
                          showDirectMessage: true,
                          directMessageLabel: 'Direct message',
                          onDirectMessageTap: () {},
                          showSave: true,
                          saveLabel: 'Save',
                          onSaveTap: () => saved = true,
                          compact: compact,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );

            expect(tester.takeException(), isNull);
            expect(find.byType(Wrap), findsOneWidget);

            await tester.tap(find.byIcon(Icons.favorite_border_rounded));
            await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
            await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
            expect(liked, isTrue);
            expect(commentOpened, isTrue);
            expect(saved, isTrue);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('selected post heart uses dark gray instead of red',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PostActionGroup(
            likes: 2,
            comments: 0,
            views: 17,
            isLiked: true,
            likeLabel: 'Like',
            commentLabel: 'Comments',
            viewsLabel: 'Views',
          ),
        ),
      ),
    );

    final heart = tester.widget<Icon>(
      find.byIcon(Icons.favorite_rounded),
    );
    expect(heart.color, BrandColors.textSecondary);
    expect(heart.color, isNot(BrandColors.error));
  });

  testWidgets('card mode hides metric icons whose count is zero',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PostActionGroup(
            likes: 3,
            comments: 0,
            views: 18,
            isLiked: true,
            likeLabel: 'Like',
            commentLabel: 'Comments',
            viewsLabel: 'Views',
            compact: true,
            hideEmptyMetrics: true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero-like posts always keep the heart action visible',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostActionGroup(
            likes: 0,
            comments: 0,
            views: 0,
            isLiked: false,
            likeLabel: 'Like',
            commentLabel: 'Comments',
            viewsLabel: 'Views',
            hideEmptyMetrics: true,
            onLikeTapUp: (_) => tapped = true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('interactive zero-comment action remains visible',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostActionGroup(
            likes: 0,
            comments: 0,
            views: 0,
            isLiked: false,
            likeLabel: 'Like',
            commentLabel: 'Comments',
            viewsLabel: 'Views',
            hideEmptyMetrics: true,
            onCommentTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('heart comment and views stay in a left-aligned row',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: PostActionGroup(
              likes: 0,
              comments: 0,
              views: 0,
              isLiked: false,
              likeLabel: 'Like',
              commentLabel: 'Comments',
              viewsLabel: 'Views',
              compact: true,
              hideEmptyMetrics: false,
            ),
          ),
        ),
      ),
    );

    final heart = tester.getCenter(find.byIcon(Icons.favorite_border_rounded));
    final comment =
        tester.getCenter(find.byIcon(Icons.chat_bubble_outline_rounded));
    final views = tester.getCenter(find.byIcon(Icons.visibility_outlined));

    expect(heart.dx, lessThan(comment.dx));
    expect(comment.dx, lessThan(views.dx));
    expect(views.dx, lessThan(150));
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail mode keeps DM and save actions at the right edge',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(390, 900),
            textScaler: TextScaler.linear(1),
          ),
          child: Scaffold(
            body: SizedBox(
              width: 390,
              child: PostActionGroup(
                likes: 2,
                comments: 0,
                views: 48,
                isLiked: true,
                likeLabel: 'Like',
                commentLabel: 'Comments',
                viewsLabel: 'Views',
                showDirectMessage: true,
                directMessageLabel: 'Direct message',
                showSave: true,
                saveLabel: 'Save',
                compact: true,
                hideEmptyMetrics: true,
                trailingActionsAtEnd: true,
              ),
            ),
          ),
        ),
      ),
    );

    final viewsCenter =
        tester.getCenter(find.byIcon(Icons.visibility_outlined));
    final dmCenter = tester.getCenter(find.byIcon(Icons.send_rounded));
    final saveCenter =
        tester.getCenter(find.byIcon(Icons.bookmark_border_rounded));

    expect(dmCenter.dx, greaterThan(viewsCenter.dx));
    expect(saveCenter.dx, greaterThan(dmCenter.dx));
    expect(saveCenter.dx, greaterThan(350));
    expect(tester.takeException(), isNull);
  });
}
