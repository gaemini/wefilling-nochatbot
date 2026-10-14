import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/screens/login_screen.dart';
import 'package:wefilling/ui/motion/auth_gate_hold.dart';
import 'package:wefilling/ui/widgets/wefilling_mark.dart';

class _FakeAuth extends Fake with ChangeNotifier implements AuthProvider {
  Completer<bool>? pending;
  bool loggedIn = false;
  bool registrationComplete = true;
  bool throwError = false;
  bool cancelled = false;
  bool signupRequired = false;
  String nickname = '하늘';

  @override
  bool get isLoading => false;
  @override
  bool get isLoggedIn => loggedIn;
  @override
  bool get isRegistrationComplete => registrationComplete;
  @override
  Map<String, dynamic>? get userData => {'nickname': nickname};
  @override
  bool get lastGoogleSignInWasCancelled => cancelled;
  @override
  bool consumeSignupRequiredFlag() {
    final value = signupRequired;
    signupRequired = false;
    return value;
  }

  @override
  Future<bool> signInWithGoogle({
    bool skipEmailVerifiedCheck = false,
    bool organizationInviteMode = false,
  }) async {
    if (throwError) throw StateError('network');
    pending = Completer<bool>();
    return pending!.future;
  }

  void succeed() {
    loggedIn = true;
    pending!.complete(true);
    notifyListeners();
  }
}

/// main.dart 인증 게이트와 같은 규칙: 로그인됐고 붙잡혀 있지 않으면 메인.
class _FakeGate extends StatefulWidget {
  const _FakeGate({required this.auth});
  final _FakeAuth auth;

  @override
  State<_FakeGate> createState() => _FakeGateState();
}

int _gateSwitches = 0;

class _FakeGateState extends State<_FakeGate> {
  String _last = 'login';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.auth, AuthGateHold.instance]),
      builder: (context, _) {
        final kind = widget.auth.loggedIn && !AuthGateHold.instance.armed
            ? (widget.auth.registrationComplete ? 'main' : 'nickname')
            : 'login';
        if (kind != _last) _gateSwitches++;
        _last = kind;
        return switch (kind) {
          'main' => const Text('MAIN'),
          'nickname' => const Text('NICKNAME'),
          _ => const AuthGateScope(child: LoginScreen()),
        };
      },
    );
  }
}

Widget _app(_FakeAuth auth) => ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _FakeGate(auth: auth),
      ),
    );

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(LoginScreen)))!;

Finder _googleButton(WidgetTester tester) =>
    find.text(_l10n(tester).googleLogin);

double _opacityOf(WidgetTester tester, String label) => tester
    .widget<AnimatedOpacity>(find
        .ancestor(of: find.text(label), matching: find.byType(AnimatedOpacity))
        .first)
    .opacity;

void main() {
  setUp(() {
    WefillingAmbientMotion.enabled = false;
    _gateSwitches = 0;
  });
  tearDown(() {
    AuthGateHold.instance.release();
    WefillingAmbientMotion.enabled = true;
  });

  testWidgets('누른 버튼에만 18px 스피너, 다른 버튼 .4·비활성, 아래 스피너 줄 없음',
      (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(auth));
    await tester.pumpAndSettle();
    final l10n = _l10n(tester);
    await tester.tap(_googleButton(tester));
    await tester.pump(const Duration(milliseconds: 300));
    final spinner = find.byKey(const ValueKey('login_button_spinner'));
    expect(spinner, findsOneWidget);
    expect(tester.getSize(spinner), const Size(18, 18));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_opacityOf(tester, l10n.googleLogin), 1);
    for (final label in [l10n.appleLogin, l10n.emailLogin, l10n.signUp]) {
      expect(_opacityOf(tester, label), .4, reason: label);
      final button = tester.widget<FilledButton>(find.ancestor(
          of: find.text(label), matching: find.byType(FilledButton)));
      expect(button.onPressed, isNull, reason: label);
    }
    expect(AuthGateHold.instance.armed, isTrue);

    // 취소: 아무 표시 없이 원래대로.
    auth.cancelled = true;
    auth.pending!.complete(false);
    await tester.pumpAndSettle();
    expect(spinner, findsNothing);
    expect(find.byKey(const ValueKey('login_inline_error')), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(AuthGateHold.instance.armed, isFalse);
    expect(_opacityOf(tester, l10n.appleLogin), 1);
  });

  testWidgets('성공(가입 완료): 환영 문구 → 1.8초 뒤 게이트가 메인으로 1번만 바꾼다',
      (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(auth));
    await tester.pumpAndSettle();
    await tester.tap(_googleButton(tester));
    await tester.pump();
    auth.succeed();
    await tester.pump();
    expect(AuthGateHold.instance.armed, isTrue);
    expect(find.text('MAIN'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('환영해요, 하늘'), findsOneWidget);
    expect(find.text('친구들이 기다리고 있어요'), findsOneWidget);
    expect(find.text('MAIN'), findsNothing);
    expect(_gateSwitches, 0);

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    expect(AuthGateHold.instance.armed, isFalse);
    expect(find.text('MAIN'), findsOneWidget);
    expect(_gateSwitches, 1);
    await tester.pumpAndSettle();
    expect(_gateSwitches, 1);
  });

  testWidgets('성공 연출 중 탭하면 바로 넘어간다(이름 없으면 이름 없는 문구)', (tester) async {
    final auth = _FakeAuth()..nickname = '';
    await tester.pumpWidget(_app(auth));
    await tester.pumpAndSettle();
    await tester.tap(_googleButton(tester));
    await tester.pump();
    auth.succeed();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('환영해요!'), findsOneWidget);
    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    expect(find.text('MAIN'), findsOneWidget);
    expect(_gateSwitches, 1);
    await tester.pumpAndSettle();
    expect(_gateSwitches, 1);
  });

  testWidgets('성공(가입 미완료): 연출 없이 바로 닉네임 단계', (tester) async {
    final auth = _FakeAuth()..registrationComplete = false;
    await tester.pumpWidget(_app(auth));
    await tester.pumpAndSettle();
    await tester.tap(_googleButton(tester));
    await tester.pump();
    auth.succeed();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('login_welcome_back')), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('NICKNAME'), findsOneWidget);
    expect(_gateSwitches, 1);
  });

  testWidgets('실패: 시트 위 흰 알약 → 5초 뒤 사라짐, 두 번째 실패부터 이메일 안내',
      (tester) async {
    final auth = _FakeAuth()..throwError = true;
    await tester.pumpWidget(_app(auth));
    await tester.pumpAndSettle();
    await tester.tap(_googleButton(tester));
    await tester.pumpAndSettle();
    final pill = find.byKey(const ValueKey('login_inline_error'));
    expect(pill, findsOneWidget);
    expect(tester.widget<Text>(pill).data, _l10n(tester).loginErrorInline);
    expect(tester.widget<Text>(pill).style!.color, const Color(0xFFB42318));
    // 시트 위쪽 바깥 10.
    final sheetTop =
        tester.getTopLeft(find.byKey(const ValueKey('login_sheet'))).dy;
    final pillBox = find
        .ancestor(of: pill, matching: find.byType(Container))
        .first;
    expect(tester.getBottomLeft(pillBox).dy, closeTo(sheetTop - 10, .5));
    expect(find.byKey(const ValueKey('login_error_email_link')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(_googleButton(tester));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login_error_email_link')), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(pill, findsNothing);
  });

  testWidgets('회원가입 필요: 기존 다이얼로그 그대로', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(auth));
    await tester.pumpAndSettle();
    await tester.tap(_googleButton(tester));
    await tester.pump();
    auth.signupRequired = true;
    auth.pending!.complete(false);
    await tester.pumpAndSettle();
    expect(find.text(_l10n(tester).registrationRequired), findsOneWidget);
    expect(find.text(_l10n(tester).signUpFirstMessage), findsOneWidget);
  });
}
