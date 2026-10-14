import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/screens/email_login_screen.dart';
import 'package:wefilling/screens/login_screen.dart';
import 'package:wefilling/ui/widgets/app_start_motion.dart';
import 'package:wefilling/ui/widgets/post_loading_transition.dart';

class FakeStartupAuth extends Fake with ChangeNotifier implements AuthProvider {
  bool loading = false;
  int requests = 0;
  Completer<bool>? pending;
  @override
  bool get isLoading => loading;
  @override
  bool get isLoggedIn => false;
  @override
  bool get lastGoogleSignInWasCancelled => true;
  @override
  bool consumeSignupRequiredFlag() => false;
  Future<bool> submit() async {
    requests++;
    loading = true;
    notifyListeners();
    pending = Completer<bool>();
    final result = await pending!.future;
    loading = false;
    notifyListeners();
    return result;
  }

  @override
  Future<bool> signInWithGoogle(
          {bool skipEmailVerifiedCheck = false,
          bool organizationInviteMode = false}) =>
      submit();
  @override
  Future<bool> signInWithEmail(
          {required String email,
          required String password,
          bool organizationInviteMode = false}) =>
      submit();
}

Widget app(Widget child,
    {FakeStartupAuth? auth, bool reduced = false, String locale = 'en'}) {
  final root = MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced), child: child),
  );
  return auth == null
      ? root
      : ChangeNotifierProvider<AuthProvider>.value(value: auth, child: root);
}

void main() {
  testWidgets(
      'delayed boot hint does not move the logo or animate while hidden',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      tester.view.physicalSize = Size(width, 568);
      for (final scale in [1.0, 1.3, 2.0]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(top: 24, bottom: 48),
            ),
            child: const AppBootScreen(animateLogo: false),
          ),
        ));
        await tester.pump();
        final logo = tester.getRect(find.byType(Image));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pump(const Duration(milliseconds: 751));
        expect(tester.getRect(find.byType(Image)), logo);
        // 스피너 대신 점 3개 힌트(2부 A-1).
        expect(find.byKey(const ValueKey('boot_loading_dots')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'boot waits only for real work and cancels the delayed hint on exit',
      (tester) async {
    await tester.pumpWidget(app(const AppBootScreen()));
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 751));
    expect(find.text('Loading'), findsOneWidget);
    await tester.pumpWidget(app(const Scaffold(body: Text('ready'))));
    expect(find.text('ready'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'boot failure is readable on small screens and does not retry services',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    for (final locale in ['ko', 'en', 'zh']) {
      await tester.pumpWidget(MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MediaQuery(
              data: MediaQueryData(
                  textScaler: TextScaler.linear(2),
                  padding: EdgeInsets.only(bottom: 48)),
              child: AppBootScreen(failed: true))));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Text), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'auth restoring shows boot; submitting and failure preserve the login input',
      (tester) async {
    final controller = TextEditingController(text: '한글 English 中文');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    Widget view(bool restoring, bool keepLogin) => app(AppLoginSurface(
        restoring: restoring,
        keepLogin: keepLogin,
        login: Scaffold(
            body: TextField(controller: controller, focusNode: focus))));
    await tester.pumpWidget(view(true, false));
    expect(find.byType(AppBootScreen), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(view(false, true));
    focus.requestFocus();
    await tester.pump();
    final state = tester.state(find.byType(EditableText));
    await tester.pumpWidget(view(true, true));
    expect(tester.state(find.byType(EditableText)), same(state));
    await tester.pumpWidget(view(false, true));
    expect(focus.hasFocus, isTrue);
    expect(controller.text, '한글 English 中文');
    expect(find.byType(AppBootScreen), findsNothing);
  });

  testWidgets(
      'entry fade keeps cached child mounted and reduced motion is immediate',
      (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    Widget view(bool reduced) =>
        app(AppEntryFade(child: Scaffold(body: TextField(focusNode: focus))),
            reduced: reduced);
    await tester.pumpWidget(view(false));
    final state = tester.state(find.byType(EditableText));
    await tester.pumpAndSettle();
    await tester.pumpWidget(view(false));
    expect(tester.state(find.byType(EditableText)), same(state));
    expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 1);
    await tester.pumpWidget(view(true));
    expect(
        tester
            .widget<TweenAnimationBuilder<double>>(
                find.byType(TweenAnimationBuilder<double>))
            .duration,
        Duration.zero);
    expect(tester.state(find.byType(EditableText)), same(state));
  });

  testWidgets(
      'Google submitting disables repeats and cancellation allows retry',
      (tester) async {
    final auth = FakeStartupAuth();
    addTearDown(auth.dispose);
    await tester
        .pumpWidget(app(const LoginScreen(), auth: auth, reduced: true));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(LoginScreen));
    final label = AppLocalizations.of(context)!.googleLogin;
    await tester.tap(find.text(label));
    expect(auth.requests, 1);
    await tester.tap(find.text(label));
    expect(auth.requests, 1);
    await tester.pump();
    auth.pending!.complete(false);
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.tap(find.text(label));
    expect(auth.requests, 2);
    auth.pending!.complete(false);
    await tester.pumpAndSettle();
  });

  testWidgets('email failure retains values and permits a new request',
      (tester) async {
    final auth = FakeStartupAuth();
    addTearDown(auth.dispose);
    await tester
        .pumpWidget(app(const EmailLoginScreen(), auth: auth, reduced: true));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'someone@example.com');
    await tester.enterText(fields.at(1), 'password123');
    final button = find.byType(FilledButton);
    await tester.ensureVisible(button);
    await tester.tap(button);
    expect(auth.requests, 1);
    await tester.tap(button);
    expect(auth.requests, 1);
    await tester.pump();
    auth.pending!.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('someone@example.com'), findsOneWidget);
    expect(tester.widget<TextFormField>(fields.at(1)).controller!.text,
        'password123');
    await tester.tap(button);
    expect(auth.requests, 2);
    auth.pending!.complete(false);
    await tester.pumpAndSettle();
  });

  testWidgets('outgoing feed placeholder cannot intercept the loaded action',
      (tester) async {
    var old = 0;
    var current = 0;
    Widget view(bool loading) => app(Scaffold(
        body: PostLoadingTransition(
            loading: loading,
            child: TextButton(
                onPressed: () => loading ? old++ : current++,
                child: Text(loading ? 'old' : 'current')))));
    await tester.pumpWidget(view(true));
    await tester.pumpWidget(view(false));
    await tester.tap(find.text('current'));
    expect(current, 1);
    expect(old, 0);
    await tester.pumpAndSettle();
  });
}
