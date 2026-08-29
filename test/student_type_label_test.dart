import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/student_type.dart';

void main() {
  testWidgets('email signup uses foreign and Korean student labels',
      (tester) async {
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('ko'),
        delegates: const <LocalizationsDelegate<dynamic>>[
          DefaultWidgetsLocalizations.delegate,
        ],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) => Column(
              children: [
                Text(StudentType.exchange.title(context)),
                Text(StudentType.korean.title(context)),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('외국인 학생'), findsOneWidget);
    expect(find.text('한국 학생'), findsOneWidget);
    expect(find.text('교환학생'), findsNothing);
    expect(find.text('한국인 학생'), findsNothing);
  });
}
