import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/relationship_status.dart';
import 'package:wefilling/services/app_messenger.dart';
import 'package:wefilling/ui/widgets/post_card_friend_button.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required RelationshipStatus? status,
    Locale locale = const Locale('ko'),
    Future<bool> Function()? onSend,
    Future<bool> Function()? onCancel,
    Future<bool> Function()? onAccept,
    bool confirm = true,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: AppMessenger.scaffoldMessengerKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(375, 400),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Center(
            child: PostCardFriendButton(
              status: status,
              onSend: onSend ?? () async => true,
              onCancel: onCancel ?? () async => true,
              onAccept: onAccept ?? () async => true,
              confirmCancel: (_) async => confirm,
            ),
          ),
        ),
      ),
    ));
  }

  final button = find.byKey(const ValueKey('post-card-friend-button'));

  testWidgets('상태별 표시: none/pendingOut/pendingIn만 보이고 나머지는 숨김',
      (tester) async {
    for (final s in RelationshipStatus.values) {
      await pump(tester, status: s);
      final visible = s == RelationshipStatus.none ||
          s == RelationshipStatus.pendingOut ||
          s == RelationshipStatus.pendingIn;
      expect(button, visible ? findsOneWidget : findsNothing, reason: '$s');
    }
    await pump(tester, status: null);
    expect(button, findsNothing);
  });

  const labels = <String, List<String>>{
    'ko': ['친구 추가', '요청됨', '수락'],
    'en': ['Add Friend', 'Requested', 'Accept'],
    'zh': ['加好友', '已申请', '接受'],
  };
  for (final entry in labels.entries) {
    testWidgets('${entry.key} 문구는 기존 키를 쓴다', (tester) async {
      final locale = Locale(entry.key);
      await pump(tester, status: RelationshipStatus.none, locale: locale);
      expect(find.text(entry.value[0]), findsOneWidget);
      await pump(tester, status: RelationshipStatus.pendingOut, locale: locale);
      expect(find.text(entry.value[1]), findsOneWidget);
      await pump(tester, status: RelationshipStatus.pendingIn, locale: locale);
      expect(find.text(entry.value[2]), findsOneWidget);
    });
  }

  testWidgets('보내기: 즉시 요청됨으로 바뀌고 콜백 1회, 스낵바 없음', (tester) async {
    var calls = 0;
    final done = Completer<bool>();
    await pump(tester, status: RelationshipStatus.none, onSend: () {
      calls++;
      return done.future;
    });
    await tester.tap(button);
    await tester.pump();
    expect(find.text('요청됨'), findsOneWidget);
    // 처리 중 중복 탭은 막힌다.
    await tester.tap(button, warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);
    done.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('요청됨'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('보내기 실패: 이전 상태로 되돌리고 실패 문구', (tester) async {
    await pump(tester,
        status: RelationshipStatus.none, onSend: () async => false);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('친구 추가'), findsOneWidget);
    expect(find.text('친구요청 전송에 실패했습니다'), findsOneWidget);
  });

  testWidgets('예외도 실패로 처리해 되돌린다', (tester) async {
    await pump(tester,
        status: RelationshipStatus.pendingIn,
        onAccept: () async => throw StateError('x'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('수락'), findsOneWidget);
  });

  testWidgets('요청 취소는 확인을 거치고, 거절하면 아무것도 하지 않는다',
      (tester) async {
    var calls = 0;
    await pump(tester,
        status: RelationshipStatus.pendingOut,
        confirm: false, onCancel: () async {
      calls++;
      return true;
    });
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('요청됨'), findsOneWidget);

    await pump(tester,
        status: RelationshipStatus.pendingOut, onCancel: () async {
      calls++;
      return true;
    });
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('친구 추가'), findsOneWidget);
  });

  testWidgets('수락 성공: 버튼이 사라지고 수락 문구', (tester) async {
    await pump(tester, status: RelationshipStatus.pendingIn);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(button, findsNothing);
    expect(find.text('친구요청을 수락했습니다'), findsOneWidget);
  });

  testWidgets('다른 곳에서 관계가 바뀌면 낙관적 상태보다 실제 상태를 따른다',
      (tester) async {
    await pump(tester, status: RelationshipStatus.none);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('요청됨'), findsOneWidget);
    await pump(tester, status: RelationshipStatus.friends);
    await tester.pump();
    expect(button, findsNothing);
  });

  testWidgets('터치 영역 44 이상, 보이는 높이 30', (tester) async {
    await pump(tester, status: RelationshipStatus.none);
    final size = tester.getSize(button);
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
    final pill = tester.getSize(find.byType(AnimatedContainer));
    expect(pill.height, 30);
  });

  testWidgets('넓은 화면에서도 알약은 내용 폭만큼만(늘어나지 않음)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ko'),
      home: Scaffold(
        body: Row(children: [
          const Expanded(child: SizedBox()),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: PostCardFriendButton(
              status: RelationshipStatus.none,
              onSend: () async => true,
              onCancel: () async => true,
              onAccept: () async => true,
            ),
          ),
        ]),
      ),
    ));
    final pill = tester.getSize(find.byType(AnimatedContainer));
    expect(pill.width, lessThan(140));
    expect(pill.height, 30);
  });
}
