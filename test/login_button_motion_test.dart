import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/screens/login_screen.dart';
import 'package:wefilling/ui/motion/auth_gate_hold.dart';

class _FakeAuth extends Fake with ChangeNotifier implements AuthProvider {
  Completer<bool>? pending;
  bool loggedIn = false;
  bool throwError = false;
  bool cancelled = false;

  @override
  bool get isLoading => false;
  @override
  bool get isLoggedIn => loggedIn;
  @override
  bool get isRegistrationComplete => true;
  @override
  bool get lastGoogleSignInWasCancelled => cancelled;
  @override
  bool consumeSignupRequiredFlag() => false;

  @override
  Future<bool> signInWithGoogle({
    bool skipEmailVerifiedCheck = false,
    bool organizationInviteMode = false,
  }) async {
    if (throwError) throw StateError('network');
    pending = Completer<bool>();
    return pending!.future;
  }
}

Widget _app(_FakeAuth auth, {bool gate = true}) =>
    ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: gate
            ? const AuthGateScope(child: LoginScreen())
            : const LoginScreen(),
      ),
    );

Finder _googleButton(WidgetTester tester) {
  final label = AppLocalizations.of(
    tester.element(find.byType(LoginScreen)),
  )!
      .googleLogin;
  return find.text(label);
}

void main() {
  tearDown(() => AuthGateHold.instance.release());

  testWidgets('누른 버튼에만 스피너, 아래 스피너 줄 없음', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(auth));
    await tester.pumpAndSettle();
    await tester.tap(_googleButton(tester));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('login_button_spinner')), findsOneWidget);
    // 별도 스피너 줄(CircularProgressIndicator 2개 이상) 없음
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(AuthGateHold.instance.armed, isTrue);

    auth.cancelled = true;
    auth.pending!.complete(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login_button_spinner')), findsNothing);
    expect(find.byKey(const ValueKey('login_inline_error')), findsNothing);
    expect(AuthGateHold.instance.armed, isFalse);
  });

  testWidgets('성공: 체크 뒤 게이트가 화면을 바꾸도록 잡아 둔 것을 푼다(직접 이동 없음)',
      (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(auth));
    await tester.pumpAndSettle();
    await tester.tap(_googleButton(tester));
    await tester.pump();
    auth.loggedIn = true;
    auth.pending!.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('login_button_check')), findsOneWidget);
    expect(AuthGateHold.instance.armed, isTrue);
    await tester.pump(const Duration(milliseconds: 300));
    expect(AuthGateHold.instance.armed, isFalse);
    // 게이트 안에서는 스스로 화면을 바꾸지 않는다.
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('오류: 버튼 아래 한 줄, 두 번째 실패부터 이메일 로그인 안내, 5초 뒤 사라짐',
      (tester) async {
    final auth = _FakeAuth()..throwError = true;
    await tester.pumpWidget(_app(auth));
    await tester.pumpAndSettle();
    await tester.tap(_googleButton(tester));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login_inline_error')), findsOneWidget);
    expect(find.byKey(const ValueKey('login_error_email_link')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(_googleButton(tester));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login_error_email_link')), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login_inline_error')), findsNothing);
  });
}
