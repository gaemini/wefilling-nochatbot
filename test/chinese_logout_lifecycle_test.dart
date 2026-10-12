import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/screens/login_screen.dart';
import 'package:wefilling/ui/dialogs/logout_dialog.dart';

import 'chinese_ui_localization_test.dart'
    show app, chinese, smallScreen, capture;

class _LogoutAuth extends Fake with ChangeNotifier implements AuthProvider {
  final completion = Completer<void>();
  bool loading = false;
  int signOutCalls = 0;

  @override
  bool get isLoading => loading;
  @override
  bool consumeSignupRequiredFlag() => false;
  @override
  Future<void> signOut() async {
    signOutCalls++;
    loading = true;
    notifyListeners();
    await completion.future;
    loading = false;
    notifyListeners();
  }

  void refresh() => notifyListeners();
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
  testWidgets('Chinese logout dialog survives removal of its opening screen',
      (tester) async {
    smallScreen(tester);
    final auth = _LogoutAuth();
    final showOrigin = ValueNotifier(true);
    addTearDown(auth.dispose);
    addTearDown(showOrigin.dispose);
    late BuildContext origin;
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: app(ValueListenableBuilder<bool>(
        valueListenable: showOrigin,
        builder: (_, visible, __) => visible
            ? Builder(builder: (context) {
                origin = context;
                return Scaffold(
                    body: TextButton(
                  onPressed: () =>
                      showLogoutConfirmDialog(context, authProvider: auth),
                  child: const Text('open'),
                ));
              })
            : const Scaffold(body: Text('replacement')),
      )),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '退出登录'));
    await tester.pump();
    // Authentication can replace the underlying screen before the dialog's
    // listener or signOut future finishes. mounted checks alone are not enough.
    showOrigin.value = false;
    await tester.pump();
    expect(origin.mounted, isFalse);
    auth.refresh();
    await tester.pump();
    expect(tester.takeException(), isNull);
    auth.completion.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Dialog), findsNothing);
    expect(auth.signOutCalls, 1);
  });

  for (final locale in [const Locale('ko'), const Locale('en'), chinese]) {
    testWidgets('logout navigation remains safe for ${locale.toLanguageTag()}',
        (tester) async {
      smallScreen(tester);
      final auth = _LogoutAuth();
      addTearDown(auth.dispose);
      await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: app(
            Builder(
                builder: (context) => Scaffold(
                        body: TextButton(
                      onPressed: () =>
                          showLogoutConfirmDialog(context, authProvider: auth),
                      child: const Text('open'),
                    ))),
            locale: locale),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final label = locale.languageCode == 'ko'
          ? '로그아웃'
          : locale.languageCode == 'en'
              ? 'Logout'
              : '退出登录';
      await tester.tap(find.widgetWithText(TextButton, label));
      await tester.pump();
      auth.completion.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(auth.signOutCalls, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('finishing logout after dialog removal does not pop a new route',
      (tester) async {
    final auth = _LogoutAuth();
    addTearDown(auth.dispose);
    late NavigatorState navigator;
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: app(Builder(builder: (context) {
        navigator = Navigator.of(context);
        return Scaffold(
            body: TextButton(
          onPressed: () => showLogoutConfirmDialog(context, authProvider: auth),
          child: const Text('open'),
        ));
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '退出登录'));
    await tester.pump();
    navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('new route'))),
        (_) => false);
    await tester.pumpAndSettle();
    auth.completion.complete();
    await tester.pumpAndSettle();
    expect(find.text('new route'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 568),
    const Size(360, 640),
    const Size(390, 844),
    const Size(430, 932),
    const Size(568, 320)
  ]) {
    for (final scale in [1.3, 2.0]) {
      testWidgets(
          'Chinese login and logout fit $size at ${scale}x with Android bars',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
        addTearDown(tester.view.reset);
        final auth = _LogoutAuth();
        addTearDown(auth.dispose);
        await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
            value: auth, child: app(const LoginScreen(), scale: scale)));
        await tester.pumpAndSettle();
        expect(find.text('/'), findsNWidgets(2));
        for (final label in ['KOR', 'ENG', '简体中文']) {
          final finder = find.text(label);
          final rect = tester.getRect(finder);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.top, greaterThanOrEqualTo(24));
          expect(tester.renderObject<RenderParagraph>(finder).didExceedMaxLines,
              isFalse);
        }
        expect(tester.takeException(), isNull);
        if (size.width == 390 && scale == 1.3)
          await capture(tester, 'login-refined');
        await tester.ensureVisible(find.text('注册'));
        await tester.pumpAndSettle();
        expect(tester.getBottomRight(find.text('注册')).dy,
            lessThanOrEqualTo(size.height - 48));
        final loginContext = tester.element(find.byType(LoginScreen));
        unawaited(showLogoutConfirmDialog(loginContext, authProvider: auth));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final cancel = find.widgetWithText(TextButton, '取消');
        await tester.ensureVisible(cancel);
        await tester.pumpAndSettle();
        expect(tester.getBottomRight(cancel).dy,
            lessThanOrEqualTo(size.height - 48));
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(auth.signOutCalls, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
