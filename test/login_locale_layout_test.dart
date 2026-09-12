import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/screens/login_screen.dart';

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

  for (final size in [
    const Size(320, 568),
    const Size(360, 640),
    const Size(390, 844),
    const Size(430, 932),
    const Size(568, 320),
  ]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('shared login layout at $size / ${scale}x', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
        addTearDown(tester.view.reset);
        final auth = _LoginAuth();
        addTearDown(auth.dispose);
        Rect? originalLogo;
        double? originalTaglineTop;
        double? originalWelcomeTop;
        List<Object?>? originalLayout;

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
          final context = tester.element(find.byType(LoginScreen));
          await tester.runAsync(() async {
            await precacheImage(
                const AssetImage('assets/images/wefilling_boot_logo.png'),
                context);
            await precacheImage(
                const AssetImage('assets/icons/google_logo.png'), context);
          });
          await tester.pumpAndSettle();
          final strings = AppLocalizations.of(context)!;
          final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
          final background = scaffold.body! as Container;
          expect(
              background.decoration,
              BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.blue.shade100,
                    Colors.blue.shade50,
                    Colors.white
                  ],
                ),
              ));

          final logo = find.byWidgetPredicate((widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage)
                  .assetName
                  .endsWith('wefilling_boot_logo.png'));
          final brand = find.byKey(const ValueKey('login_brand_name'));
          final tagline = find.text(strings.appTagline);
          final welcome = find.text(strings.welcomeTitle);
          originalLogo ??= tester.getRect(logo);
          if (locale.languageCode == 'en') {
            originalTaglineTop = tester.getTopLeft(tagline).dy;
            originalWelcomeTop = tester.getTopLeft(welcome).dy;
          }
          expect(tester.getRect(logo), originalLogo);
          expect(tester.getCenter(brand).dx, size.width / 2);
          if (locale.languageCode == 'zh') {
            expect(strings.appName, '微邻');
            expect(tester.getTopLeft(tagline).dy, originalTaglineTop);
            expect(tester.getTopLeft(welcome).dy, originalWelcomeTop);
            final brandRect = tester.getRect(brand);
            expect(brandRect.left, greaterThanOrEqualTo(0));
            expect(brandRect.right, lessThanOrEqualTo(size.width));
          }
          expect(
            tester.widget<Text>(brand).style!.fontFamily,
            locale.languageCode == 'zh' ? 'NotoSansSC' : 'Inter',
          );

          // Compare authored layout/style properties, not translated paragraph
          // heights: existing Korean/English descriptions already wrap differently.
          final layout = <Object?>[
            for (final widget in tester.widgetList(find.descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byWidgetPredicate((widget) =>
                  widget is Container ||
                  widget is Positioned ||
                  widget is SingleChildScrollView ||
                  widget is Image),
            )))
              if (widget is Container) ...[
                widget.padding,
                widget.margin,
                widget.decoration,
                widget.constraints,
              ] else if (widget is Positioned) ...[
                widget.top,
                widget.right,
                widget.bottom,
                widget.left,
              ] else if (widget is SingleChildScrollView)
                widget.padding
              else if (widget is Image) ...[
                widget.width,
                widget.height,
                widget.fit
              ],
          ];
          originalLayout ??= layout;
          expect(layout, originalLayout);
          for (final button
              in tester.widgetList<FilledButton>(find.byType(FilledButton))) {
            expect(tester.getSize(find.byWidget(button)).height, 48);
            expect(button.style!.padding!.resolve({}),
                const EdgeInsets.symmetric(horizontal: 18));
            expect(
                button.style!.shape!.resolve({}),
                RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)));
          }

          final separators = find.text('/');
          expect(separators, findsNWidgets(2));
          final selector = find
              .ancestor(of: separators.first, matching: find.byType(Row))
              .first;
          final row = tester.widget<Row>(selector);
          expect(row.mainAxisSize, MainAxisSize.min);
          expect(row.children.length, 5);
          expect(((row.children[1] as Padding).child! as Text).data, '/');
          expect(((row.children[3] as Padding).child! as Text).data, '/');
          final items = [
            find.text('KOR'),
            separators.at(0),
            find.text('ENG'),
            separators.at(1),
            find.text('简体中文')
          ];
          double previousRight = 0;
          for (final item in items) {
            final rect = tester.getRect(item);
            expect(rect.left, greaterThanOrEqualTo(previousRight));
            expect(rect.right, lessThanOrEqualTo(size.width));
            expect(rect.top, greaterThanOrEqualTo(24));
            expect(rect.overlaps(tester.getRect(selector)), isTrue);
            expect(tester.renderObject<RenderParagraph>(item).didExceedMaxLines,
                isFalse);
            previousRight = rect.right;
          }
          final firstGap = tester.getRect(find.text('ENG')).left -
              tester.getRect(separators.at(0)).right;
          final chineseGap = tester.getRect(find.text('简体中文')).left -
              tester.getRect(separators.at(1)).right;
          expect(chineseGap, closeTo(firstGap, 1));
          for (final label in ['KOR', 'ENG', '简体中文']) {
            final selected = label ==
                (locale.languageCode == 'ko'
                    ? 'KOR'
                    : locale.languageCode == 'en'
                        ? 'ENG'
                        : '简体中文');
            final choice = find
                .ancestor(
                    of: find.text(label), matching: find.byType(InkResponse))
                .first;
            expect(tester.widget<InkResponse>(choice).onTap, isNotNull);
            final underline = tester.widget<AnimatedContainer>(find.descendant(
                of: choice, matching: find.byType(AnimatedContainer)));
            expect(underline.constraints!.maxWidth, selected ? 18 : 0);
          }
          expect(tester.takeException(), isNull);
          if (size == const Size(390, 844) && scale == 1.0) {
            await capture(tester, 'login-shared-${locale.languageCode}');
          }
          await tester.ensureVisible(find.text(strings.loginTermsNotice));
          await tester.pumpAndSettle();
          expect(tester.getBottomRight(find.text(strings.loginTermsNotice)).dy,
              lessThanOrEqualTo(size.height - 48));
          expect(tester.takeException(), isNull);
          // Reset scroll state before the next locale comparison.
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }
  }
}
