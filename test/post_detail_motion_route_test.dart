import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/screens/post_detail_screen.dart';

void main() {
  final post = Post(
    id: 'post-motion-test',
    title: '',
    content: 'Content',
    author: 'Author',
    createdAt: DateTime.utc(2026),
    userId: 'author-id',
  );

  testWidgets('feed-to-detail route fades and moves without changing target',
      (tester) async {
    final route = PostDetailMotionRoute(post: post);
    expect(route.transitionDuration, const Duration(milliseconds: 280));

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => route.buildTransitions(
          context,
          const AlwaysStoppedAnimation<double>(.5),
          const AlwaysStoppedAnimation<double>(0),
          const Text('Detail'),
        ),
      ),
    ));
    expect(find.text('Detail'), findsOneWidget);
    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(SlideTransition), findsWidgets);
  });

  testWidgets('reduced motion removes the detail slide', (tester) async {
    final route = PostDetailMotionRoute(post: post);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) => route.buildTransitions(
            context,
            const AlwaysStoppedAnimation<double>(.5),
            const AlwaysStoppedAnimation<double>(0),
            const Text('Detail'),
          ),
        ),
      ),
    ));
    expect(find.text('Detail'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MediaQuery).last,
        matching: find.byType(SlideTransition),
      ),
      findsNothing,
    );
  });
}
