import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/ui_locale.dart';

void main() {
  Future<String> messageFor(WidgetTester tester, Locale locale) async {
    var message = '';
    await tester.pumpWidget(
      Localizations(
        locale: locale,
        delegates: const <LocalizationsDelegate<dynamic>>[
          DefaultWidgetsLocalizations.delegate,
        ],
        child: Builder(
          builder: (context) {
            message = kickedMeetupAccessMessage(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return message;
  }

  testWidgets('removed meetup access message follows the UI locale',
      (tester) async {
    expect(
        await messageFor(tester, const Locale('ko')), '죄송합니다. 모임에 참여할 수 없습니다');
    expect(await messageFor(tester, const Locale('en')),
        "Sorry, you can't join this meetup.");
    expect(
      await messageFor(
        tester,
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      ),
      '抱歉，你无法参加该聚会。',
    );
  });
}
