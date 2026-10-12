import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/screens/nickname_setup_screen.dart';

class _AvailabilityProvider extends ChangeNotifier implements AuthProvider {
  final requests = <String>[];
  final responses = <Completer<NicknameAvailabilityResult>>[];
  @override
  User? get user => null;
  @override
  Future<NicknameAvailabilityResult> checkNicknameAvailability(String nickname) {
    requests.add(nickname);
    final response = Completer<NicknameAvailabilityResult>();
    responses.add(response);
    return response.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('IME commit, paste validation, debounce and stale/error responses', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = _AvailabilityProvider();
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: const MaterialApp(
        locale: Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NicknameSetupScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    final field = find.byType(TextFormField).first;
    await tester.showKeyboard(field);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '한ㄱ', composing: TextRange(start: 1, end: 2),
      selection: TextSelection.collapsed(offset: 2),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(auth.requests, isEmpty);
    expect(tester.widget<TextFormField>(field).controller!.text, '한ㄱ');
    // Composition-only commit must trigger a check even if the text is unchanged.
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '한글', composing: TextRange(start: 1, end: 2),
      selection: TextSelection.collapsed(offset: 2),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(auth.requests, isEmpty);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '한글', selection: TextSelection.collapsed(offset: 2),
    ));
    await tester.pump(const Duration(milliseconds: 301));
    expect(auth.requests, ['한글']);
    await tester.enterText(field, 'Other');
    await tester.pump(const Duration(milliseconds: 301));
    auth.responses.first.complete(const NicknameAvailabilityResult(
      available: true, nickname: '한글', nicknameKey: '한글'));
    await tester.pump();
    final l10n = AppLocalizations.of(tester.element(field))!;
    expect(find.text(l10n.nicknameAvailable), findsNothing);
    auth.responses.last.completeError(const NicknameAvailabilityException(
      NicknameAvailabilityFailureKind.network));
    await tester.pumpAndSettle();
    expect(find.text(l10n.nicknameCheckNetworkError), findsOneWidget);
    expect(find.text(l10n.nicknameAvailable), findsNothing);
    await tester.enterText(field, 'Paste_123😊');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(auth.requests.length, 2);
    expect(tester.widget<TextFormField>(field).controller!.text, 'Paste_123😊');
    expect(find.text(l10n.nicknameInvalidCharacters), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
  });
}
