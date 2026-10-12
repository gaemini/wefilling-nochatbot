import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/category_create_shortcut_bar.dart';

void main() {
  testWidgets('상단 생성 버튼은 좁은 Android 화면과 큰 글자에서도 넘치지 않는다', (tester) async {
    const surfaceSize = Size(320, 568);
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var tapped = '';
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: surfaceSize,
            textScaler: TextScaler.linear(1.5),
            viewPadding: EdgeInsets.only(bottom: 24),
          ),
          child: Scaffold(
            body: CategoryCreateShortcutBar(
              postLabel: 'Post',
              meetupLabel: 'Meetup',
              snackChatLabel: 'Snack Chat',
              createPostLabel: 'Create post',
              createMeetupLabel: 'Create meetup',
              createSnackChatLabel: 'Create snack chat',
              onCreatePost: () => tapped = 'post',
              onCreateMeetup: () => tapped = 'meetup',
              onCreateSnackChat: () => tapped = 'snack',
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('create_post_shortcut')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('create_meetup_shortcut')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('create_snack_chat_shortcut')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('create_snack_chat_shortcut')));
    expect(tapped, 'snack');
  });
}
