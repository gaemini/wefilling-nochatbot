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

  testWidgets('생성 버튼은 첫 화면에 보이고 아래 스크롤에서 숨었다가 위에서 다시 보인다', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 500);
    final neverCompletes = Completer<PostCategoryPage>();

    await tester.pumpWidget(_testApp(({
      required category,
      startAfter,
      pageSize = 20,
      forceRefresh = false,
    }) {
      return neverCompletes.future;
    }));
    await tester.pump();

    Finder buttonOpacity() => find.ancestor(
          of: find.byType(FloatingActionButton),
          matching: find.byType(AnimatedOpacity),
        );

    expect(tester.widget<AnimatedOpacity>(buttonOpacity()).opacity, 1);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<AnimatedOpacity>(buttonOpacity()).opacity, 0);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 140));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<AnimatedOpacity>(buttonOpacity()).opacity, 1);

    // 페이지 로더의 제품 타임아웃 타이머까지 소진해 테스트 종료 시 남는
    // 비동기 작업이 없도록 한다.
    await tester.pump(PostCategoryFeedScreen.pageLoadTimeout);
    await tester.pump();
  });
}
