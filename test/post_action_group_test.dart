import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/post_action_group.dart';

void main() {
  const widths = <double>[320, 360, 390, 430, 800];

  for (final width in widths) {
    for (final textScale in <double>[1, 3]) {
      testWidgets(
        'actions wrap without overflow at ${width}px and ${textScale}x text',
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
