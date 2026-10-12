import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snack_chat_message.dart';
import 'package:wefilling/screens/snack_chat_poll_schedule_screen.dart';
import 'package:wefilling/ui/dialogs/snack_chat_poll_dialog.dart';

Widget _app({required Widget home, Locale locale = const Locale('ko')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const <Locale>[Locale('ko'), Locale('en')],
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}

void main() {
  testWidgets('투표 생성은 바텀시트가 아닌 전체 화면에서 기존 결과를 반환한다', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    SnackChatPoll? result;

    await tester.pumpWidget(
      _app(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showSnackChatPollDialog(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackChatPollDialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('참석 투표 만들기'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextFormField).first, '이번 주 참석 여부');
    await tester.tap(find.byTooltip('만들기'));
    await tester.pumpAndSettle();

    expect(result?.question, '이번 주 참석 여부');
    expect(result?.options.length, 3);
  });

  testWidgets('날짜 선택 전체 화면은 작은 Android 화면에서도 오버플로우하지 않는다', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    final initial = DateTime.now().add(const Duration(days: 2, hours: 1));

    await tester.pumpWidget(
      _app(
        locale: const Locale('en'),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            padding: EdgeInsets.only(bottom: 24),
            viewPadding: EdgeInsets.only(bottom: 24),
            textScaler: TextScaler.linear(2),
          ),
          child: SnackChatPollScheduleScreen(
            initialDateTime: initial,
            firstDate: DateTime.now(),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('End time'), findsOneWidget);
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byType(CupertinoPicker), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
