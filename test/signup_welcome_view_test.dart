import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/signup_welcome_view.dart';

void main() {
  testWidgets('환영 화면: 사진 자리와 이름, 탭하면 바로 넘어감', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: SignupWelcomeView(nickname: '민수', onTap: () => taps++),
    ));
    final title = find.byKey(const ValueKey('signup_welcome_title'));
    expect(
      tester
          .widget<AnimatedOpacity>(
              find.ancestor(of: title, matching: find.byType(AnimatedOpacity)))
          .opacity,
      0,
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester
          .widget<AnimatedOpacity>(
              find.ancestor(of: title, matching: find.byType(AnimatedOpacity)))
          .opacity,
      1,
    );
    expect(find.text('환영해요, 민수'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('signup_welcome')));
    expect(taps, 1);
    await tester.pumpAndSettle();
  });
}
