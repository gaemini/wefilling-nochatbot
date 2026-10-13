import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/app_notification.dart';
import 'package:wefilling/models/relationship_status.dart';
import 'package:wefilling/snapshot/snack_feel_icon.dart';
import 'package:wefilling/ui/sheets/mutual_feel_sheet.dart';
import 'package:wefilling/widgets/notification_list_item.dart';

Widget _host(Widget child, {double width = 375, double scale = 1, Locale locale = const Locale('ko')}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(bottom: 34),
        ),
        child: Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: child),
        ),
      ),
    );

MutualFeelSheet _sheet(RelationshipStatus? status,
        {void Function()? onMessage, void Function()? onAdd}) =>
    MutualFeelSheet(
      otherName: '율율율',
      status: status,
      myAvatar: const ColoredBox(color: Colors.orange),
      otherAvatar: const ColoredBox(color: Colors.brown),
      onMessage: onMessage ?? () {},
      onAddFriend: onAdd ?? () {},
    );

void main() {
  testWidgets('친구가 아니면 메시지 보내기와 친구 추가', (tester) async {
    var messages = 0;
    var adds = 0;
    await tester.pumpWidget(_host(_sheet(
      RelationshipStatus.none,
      onMessage: () => messages++,
      onAdd: () => adds++,
    )));
    await tester.pumpAndSettle();
    expect(find.text('서로 필링했어요'), findsOneWidget);
    expect(find.textContaining('율율율님도 내 스낵에 필링했어요.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mutual_feel_message')));
    await tester.tap(find.byKey(const ValueKey('mutual_feel_add_friend')));
    expect(messages, 1);
    expect(adds, 1);
  });

  testWidgets('이미 친구면 친구 추가 숨김, 요청 보냄이면 요청됨(비활성)', (tester) async {
    await tester.pumpWidget(_host(_sheet(RelationshipStatus.friends)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mutual_feel_add_friend')), findsNothing);

    var adds = 0;
    await tester.pumpWidget(_host(_sheet(
      RelationshipStatus.pendingOut,
      onAdd: () => adds++,
    )));
    await tester.pumpAndSettle();
    expect(find.text('요청됨'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mutual_feel_add_friend')));
    expect(adds, 0);
  });

  testWidgets('시트 글자 크기는 표를 넘지 않는다(18/15/13)', (tester) async {
    await tester.pumpWidget(_host(_sheet(RelationshipStatus.none)));
    await tester.pumpAndSettle();
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.style?.fontSize ?? 14, lessThanOrEqualTo(18));
    }
    expect(
      tester.widget<Text>(find.text('서로 필링했어요')).style!.fontSize,
      18,
    );
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('시트 오버플로우 없음 $width/$scale', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final locale in const [Locale('ko'), Locale('en'), Locale('zh')]) {
          await tester.pumpWidget(_host(
            _sheet(RelationshipStatus.none),
            width: width,
            scale: scale,
            locale: locale,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('새 형식 필링 알림(actorId 없음): 2줄 표시와 개수', (tester) async {
    final notification = AppNotification(
      id: 'snapshot_feel_s1',
      userId: 'me',
      title: '누군가 내 스낵에 필링했어요',
      message: '필링 7개',
      type: 'snapshot_reaction',
      data: const {'snapshotId': 's1', 'feelCount': 7, 'anonymous': true},
      createdAt: DateTime(2026, 10, 13),
    );
    var taps = 0;
    await tester.pumpWidget(_host(
      NotificationListItem(
        notification: notification,
        primaryText: notification.message,
        timeText: '3분 전',
        onTap: () => taps++,
      ),
    ));
    await tester.pump();
    expect(find.text('누군가 내 스낵에 필링했어요'), findsOneWidget);
    expect(find.text('필링 7개 · 3분 전'), findsOneWidget);
    expect(find.byType(SnackFeelIcon), findsOneWidget);
    await tester.tap(find.text('누군가 내 스낵에 필링했어요'));
    expect(taps, 1);
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.style?.fontSize ?? 14, lessThanOrEqualTo(14));
    }
  });

  testWidgets('필링 아이콘은 외곽선/채움 상태 모두 그려진다', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Row(children: [
        SnackFeelIcon(size: 20),
        SnackFeelIcon(size: 88, filled: true),
      ]),
    ));
    expect(find.byType(SnackFeelIcon), findsNWidgets(2));
    expect(tester.getSize(find.byType(SnackFeelIcon).last), const Size(88, 88));
    expect(tester.takeException(), isNull);
  });
}
