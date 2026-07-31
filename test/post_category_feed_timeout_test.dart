import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/post_category.dart';
import 'package:wefilling/screens/post_category_feed_screen.dart';
import 'package:wefilling/services/post_service.dart';

Widget _testApp(PostCategoryPageLoader loader) {
  return MaterialApp(
    locale: const Locale('ko'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: PostCategoryFeedScreen(
      category: PostCategory.style,
      pageLoader: loader,
    ),
  );
}

void main() {
  testWidgets('멈춘 페이지 조회를 제한 시간 뒤 종료하고 재시도를 노출한다', (tester) async {
    final neverCompletes = Completer<PostCategoryPage>();

    await tester.pumpWidget(_testApp(({
      required category,
      startAfter,
      pageSize = 20,
      forceRefresh = false,
    }) {
      return neverCompletes.future;
    }));

    expect(find.text('다시 시도'), findsNothing);

    await tester.pump(PostCategoryFeedScreen.pageLoadTimeout);
    await tester.pump();

    expect(find.text('다시 시도'), findsOneWidget);
  });
}
