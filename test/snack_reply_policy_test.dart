import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/relationship_orbit_state.dart';
import 'package:wefilling/ui/sheets/snack_reply_sheet.dart';

Future<void> _openSheet(
  WidgetTester tester, {
  required OrbitRelationshipState relationship,
  bool friendRequestPending = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showSnackReplySheet(
            context,
            relationship: relationship,
            friendRequestPending: friendRequestPending,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  test('스낵 답장 영상은 3~5초(여유 0.6초)만 통과한다', () {
    expect(SnackReplyVideoPolicy.validate(const Duration(seconds: 1)), 'short');
    expect(SnackReplyVideoPolicy.validate(const Duration(milliseconds: 2500)),
        isNull);
    expect(SnackReplyVideoPolicy.validate(const Duration(seconds: 4)), isNull);
    expect(SnackReplyVideoPolicy.validate(const Duration(milliseconds: 5500)),
        isNull);
    expect(SnackReplyVideoPolicy.validate(const Duration(seconds: 7)), 'long');
  });

  testWidgets('친구에게는 촬영·앨범 선택만 보이고 번역 답장은 없다', (tester) async {
    await _openSheet(tester, relationship: OrbitRelationshipState.friend);
    expect(find.textContaining('친구에게 DM으로 바로 전달돼요'), findsOneWidget);
    expect(find.text('영상 촬영 (3~5초)'), findsOneWidget);
    expect(find.text('사진 촬영'), findsOneWidget);
    expect(find.text('앨범에서 선택'), findsOneWidget);
    expect(find.text('번역으로 답장하기'), findsNothing);
    expect(find.text('친구 요청 보내기'), findsNothing);
  });

  testWidgets('비친구에게는 촬영 대신 친구 요청만 보인다', (tester) async {
    await _openSheet(tester, relationship: OrbitRelationshipState.notConnected);
    expect(find.textContaining('친구끼리만'), findsOneWidget);
    expect(find.text('영상 촬영 (3~5초)'), findsNothing);
    expect(find.text('친구 요청 보내기'), findsOneWidget);
    expect(find.text('번역으로 인사하기'), findsNothing);
  });

  testWidgets('친구 요청을 보낸 상태면 요청 버튼이 비활성화된다', (tester) async {
    await _openSheet(
      tester,
      relationship: OrbitRelationshipState.requestSent,
      friendRequestPending: true,
    );
    expect(find.textContaining('수락하면 스낵으로 답장할 수 있어요'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(find.ancestor(
      of: find.text('친구 요청 보냄'),
      matching: find.byWidgetPredicate((w) => w is OutlinedButton),
    ));
    expect(button.onPressed, isNull);
  });
}
