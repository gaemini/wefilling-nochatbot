import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/post_loading_transition.dart';

void main() {
  Widget feedItem({
    required bool loading,
    required String label,
    double height = 240,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PostLoadingTransition(
          loading: loading,
          child: SizedBox(
            height: height,
            child: Text(label),
          ),
        ),
      ),
    );
  }

  testWidgets('only skeleton to content crossfades', (tester) async {
    await tester.pumpWidget(feedItem(loading: true, label: 'Skeleton'));
    await tester.pumpWidget(feedItem(loading: false, label: 'Post A'));
    expect(find.text('Skeleton'), findsOneWidget);
    expect(find.text('Post A'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 90));
    expect(
      find.descendant(
        of: find.byType(PostLoadingTransition),
        matching: find.byType(FadeTransition),
      ),
      findsNWidgets(2),
    );
    await tester.pumpAndSettle();
    expect(find.text('Skeleton'), findsNothing);

    await tester.pumpWidget(feedItem(loading: false, label: 'Post B'));
    expect(find.text('Post A'), findsNothing);
    expect(find.text('Post B'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('different skeleton and post heights stay top-aligned',
      (tester) async {
    await tester.pumpWidget(
      feedItem(loading: true, label: 'Skeleton', height: 220),
    );
    await tester.pumpWidget(
      feedItem(loading: false, label: 'Post', height: 500),
    );
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      tester.getTopLeft(find.text('Skeleton')).dy,
      tester.getTopLeft(find.text('Post')).dy,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion removes the skeleton immediately',
      (tester) async {
    Widget item(bool loading) => MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: PostLoadingTransition(
                loading: loading,
                child: Text(loading ? 'Skeleton' : 'Post'),
              ),
            ),
          ),
        );

    await tester.pumpWidget(item(true));
    await tester.pumpWidget(item(false));
    await tester.pump();
    expect(find.text('Skeleton'), findsNothing);
    expect(find.text('Post'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
