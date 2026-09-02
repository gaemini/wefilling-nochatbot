import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/screens/nickname_setup_screen.dart';

void main() {
  testWidgets('signup profile flow keeps photo and only required profile data',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NicknameSetupScreen(),
      ),
    );

    expect(find.text('Just the essentials'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('Profile photo'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.childrenDelegate.estimatedChildCount, 2);
    pageView.controller!.jumpToPage(1);
    await tester.pump();
    expect(
      find.text('What are you into these days?'),
      findsOneWidget,
    );

    expect(find.text('Skip', skipOffstage: false), findsNothing);
    expect(find.text('Student type', skipOffstage: false), findsNothing);
    expect(
        find.text('Conversation starter', skipOffstage: false), findsNothing);
  });

  testWidgets('compact signup layout stays overflow-free with keyboard insets',
      (tester) async {
    const size = Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: EdgeInsets.only(bottom: 24),
            viewPadding: EdgeInsets.only(bottom: 24),
            viewInsets: EdgeInsets.only(bottom: 260),
            textScaler: TextScaler.linear(1.3),
          ),
          child: NicknameSetupScreen(),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Nickname'), findsOneWidget);
    expect(find.text('Nationality'), findsOneWidget);

    final pageView = tester.widget<PageView>(find.byType(PageView));
    pageView.controller!.jumpToPage(1);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('What are you into these days?'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cafes'));
    await tester.pump();
    expect(find.text('1/5'), findsOneWidget);
    expect(find.text('Skip', skipOffstage: false), findsNothing);
  });
}
