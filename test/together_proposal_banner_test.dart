import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snack_chat.dart';
import 'package:wefilling/ui/widgets/together_proposal_banner.dart';

Widget _host(Widget child, {Locale locale = const Locale('ko')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: Center(child: SizedBox(width: 320, child: child))),
    );

TogetherProposalBanner _banner({
  required bool recipient,
  SnackChatTogetherStatus status = SnackChatTogetherStatus.pending,
  VoidCallback? onAccept,
  VoidCallback? onLater,
}) =>
    TogetherProposalBanner(
      together: SnackChatTogether(
        fromUid: 'a',
        toUid: 'b',
        activity: '점심',
        status: status,
      ),
      isRecipient: recipient,
      otherName: '민수',
      myAvatar: const SizedBox(width: 24, height: 24),
      otherAvatar: const SizedBox(width: 24, height: 24),
      onAccept: onAccept,
      onLater: onLater,
    );

void main() {
  testWidgets('받는 사람은 [다음에]/[좋아요, 같이 해요]를 누를 수 있다', (tester) async {
    var accepted = 0;
    var later = 0;
    await tester.pumpWidget(_host(_banner(
      recipient: true,
      onAccept: () => accepted++,
      onLater: () => later++,
    )));
    expect(find.byKey(const ValueKey('together_accept')), findsOneWidget);
    expect(find.byKey(const ValueKey('together_later')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('together_accept')));
    await tester.tap(find.byKey(const ValueKey('together_later')));
    expect(accepted, 1);
    expect(later, 1);
  });

  testWidgets('보낸 사람에게는 응답 버튼이 없다', (tester) async {
    await tester.pumpWidget(_host(_banner(recipient: false)));
    expect(find.byKey(const ValueKey('together_accept')), findsNothing);
    expect(find.byKey(const ValueKey('together_later')), findsNothing);
  });

  testWidgets('수락 후에는 버튼 대신 알약이 보인다', (tester) async {
    await tester.pumpWidget(_host(_banner(
      recipient: true,
      status: SnackChatTogetherStatus.accepted,
    )));
    expect(find.byKey(const ValueKey('together_accept')), findsNothing);
    expect(find.byKey(const ValueKey('together_pill')), findsOneWidget);
  });
}
