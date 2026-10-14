import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/screens/login_screen.dart';
import 'package:wefilling/ui/widgets/login_chat_scene.dart';
import 'package:wefilling/ui/widgets/wefilling_mark.dart';

import 'chinese_ui_localization_test.dart' show app, chinese, capture;

class _LoginAuth extends Fake with ChangeNotifier implements AuthProvider {
  @override
  bool get isLoading => false;
  @override
  bool consumeSignupRequiredFlag() => false;
}

void main() {
  setUpAll(() async {
    for (final entry in {
      'Inter': 'assets/fonts/Inter/Inter-Variable.ttf',
      'NotoSansKR': 'assets/fonts/NotoSansKR/NotoSansKR-Variable.ttf',
      'NotoSansSC': 'assets/fonts/NotoSansSC/NotoSansSC-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value)))
          .load();
    }
  });
  setUp(() => WefillingAmbientMotion.enabled = false);
  tearDown(() => WefillingAmbientMotion.enabled = true);

  // 오버플로우 없음: 폭 320/375/430 × 높이 640/812 × 배율 1.0/1.3/2.0 × ko·en·zh.
  for (final width in [320.0, 375.0, 430.0]) {
    for (final height in [640.0, 812.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        final size = Size(width, height);
        testWidgets('login layout at $size / ${scale}x', (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
          tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
          addTearDown(tester.view.reset);
          final auth = _LoginAuth();
          addTearDown(auth.dispose);

          for (final locale in [
            const Locale('ko'),
            const Locale('en'),
            chinese
          ]) {
            await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
              value: auth,
              child: app(const LoginScreen(), locale: locale, scale: scale),
            ));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final context = tester.element(find.byType(LoginScreen));
            final strings = AppLocalizations.of(context)!;

            // 파란 위쪽 영역(고정 색 그라데이션).
            final top = tester.widget<DecoratedBox>(
                find.byKey(const ValueKey('login_top_area')));
            expect(
              (top.decoration as BoxDecoration).gradient,
              const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF1F64BC),
                  Color(0xFF2C74CE),
                  Color(0xFF3B84DA)
                ],
                stops: [0, .55, 1],
              ),
            );

            // 로고 48 + 이름: 화면 안, 언어 선택과 겹치지 않음.
            final mark = tester.getRect(find.byType(WefillingMark));
            expect(mark.size, const Size(48, 48));
            final brand =
                tester.getRect(find.byKey(const ValueKey('login_brand_name')));
            expect(brand.left, greaterThanOrEqualTo(0));
            expect(brand.right, lessThanOrEqualTo(width));
            final kor = tester.getRect(find.text('KOR'));
            expect(mark.top, greaterThan(kor.bottom));

            // 언어 선택: 글자 잘림 없음, 순서대로, 밑줄 하나가 선택한 글자 아래.
            double previousRight = 0;
            for (final label in ['KOR', 'ENG', '简体中文']) {
              final finder = find.text(label);
              final rect = tester.getRect(finder);
              expect(rect.left, greaterThanOrEqualTo(previousRight));
              expect(rect.right, lessThanOrEqualTo(width));
              expect(rect.top, greaterThanOrEqualTo(24));
              expect(
                  tester.renderObject<RenderParagraph>(finder).didExceedMaxLines,
                  isFalse);
              previousRight = rect.right;
            }
            final selected = locale.languageCode == 'ko'
                ? 'KOR'
                : locale.languageCode == 'en'
                    ? 'ENG'
                    : '简体中文';
            final underline = tester.getRect(
                find.byKey(const ValueKey('login_language_underline')));
            final selectedRect = tester.getRect(find.text(selected));
            expect(underline.height, 3);
            expect(underline.width, closeTo(selectedRect.width, 1.5));
            expect(underline.center.dx, closeTo(selectedRect.center.dx, 1.5));
            expect(underline.top, greaterThan(selectedRect.bottom));

            // 시트: 화면 아래에 붙고, 버튼 52(회원가입 42).
            final sheet =
                tester.getRect(find.byKey(const ValueKey('login_sheet')));
            expect(sheet.bottom, closeTo(height, .5));
            expect(sheet.top, greaterThanOrEqualTo(mark.bottom));
            for (final label in [
              strings.appleLogin,
              strings.googleLogin,
              strings.emailLogin
            ]) {
              final button = find.ancestor(
                  of: find.text(label), matching: find.byType(FilledButton));
              expect(tester.getSize(button).height, 52, reason: label);
            }
            expect(
                tester
                    .getSize(find.ancestor(
                        of: find.text(strings.signUp),
                        matching: find.byType(FilledButton)))
                    .height,
                42);

            // 대화 장면: 있으면 로고 아래, 시트와 겹치지 않음.
            final scene = find.byKey(const ValueKey('login_chat_scene'));
            if (scene.evaluate().isNotEmpty) {
              final rect = tester.getRect(scene);
              expect(rect.top, greaterThan(mark.bottom));
              expect(rect.bottom, lessThanOrEqualTo(sheet.top));
              expect(rect.width, lessThanOrEqualTo(420));
            } else {
              expect(height, lessThan(700));
            }

            // 약관은 시트 안 회원가입 아래(시트 안 스크롤로 보인다).
            final terms = find.text(strings.loginTermsNotice);
            expect(tester.getTopLeft(terms).dy,
                greaterThan(tester.getBottomLeft(find.text(strings.signUp)).dy));
            await tester.ensureVisible(terms);
            await tester.pumpAndSettle();
            expect(tester.getBottomRight(terms).dy,
                lessThanOrEqualTo(height - 48));
            expect(tester.takeException(), isNull);
            if (size == const Size(375, 812) && scale == 1.0) {
              await capture(tester, 'login-v2-${locale.languageCode}');
            }
            await tester.pumpWidget(const SizedBox.shrink());
          }
        });
      }
    }
  }

  testWidgets('태블릿: 시트 최대 480, 대화 장면 최대 420, 가운데', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(820, 1180);
    addTearDown(tester.view.reset);
    final auth = _LoginAuth();
    addTearDown(auth.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: app(const LoginScreen(), locale: const Locale('ko'), scale: 1),
    ));
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byKey(const ValueKey('login_sheet')));
    expect(sheet.width, 480);
    expect(sheet.center.dx, 410);
    final scene = tester.getRect(find.byType(LoginChatScene));
    expect(scene.width, 420);
    expect(scene.center.dx, 410);
  });
}
