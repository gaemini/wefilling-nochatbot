import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/relationship_status.dart';
import 'package:wefilling/models/snapshot.dart';
import 'package:wefilling/screens/snapshot_activity_sheet.dart';

SnapshotViewer _viewer(String id, {String reaction = '', String name = 'Mina'}) =>
    SnapshotViewer(
      userId: id,
      displayName: name,
      photoUrl: '',
      photoVersion: 0,
      nationality: '',
      university: '',
      viewedAt: DateTime(2026, 10, 13, 9),
      reaction: reaction,
    );

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: child),
      ),
    );

void main() {
  Future<List<String>> pumpRow(
    WidgetTester tester,
    RelationshipStatus? status, {
    String reaction = '',
  }) async {
    final taps = <String>[];
    await tester.pumpWidget(_host(SnapshotActivityViewerRow(
      viewer: _viewer('u1', reaction: reaction),
      status: status,
      now: DateTime(2026, 10, 13, 10),
      onAddFriend: () => taps.add('add'),
      onMessage: () => taps.add('message'),
    )));
    return taps;
  }

  testWidgets('친구가 아니면 친구 추가, 그 밖에는 메시지', (tester) async {
    var taps = await pumpRow(tester, RelationshipStatus.none);
    expect(find.text('친구 추가'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('viewer-action-u1')));
    expect(taps, ['add']);

    taps = await pumpRow(tester, RelationshipStatus.friends);
    expect(find.text('메시지'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('viewer-action-u1')));
    expect(taps, ['message']);

    taps = await pumpRow(tester, null);
    expect(find.text('메시지'), findsOneWidget);
  });

  testWidgets('요청 보낸 상태는 비활성 표시', (tester) async {
    final taps = await pumpRow(tester, RelationshipStatus.pendingOut);
    expect(find.text('요청함'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('viewer-action-u1')));
    expect(taps, isEmpty);
  });

  testWidgets('보조 줄에 받은 반응과 본 시간', (tester) async {
    await pumpRow(tester, RelationshipStatus.friends, reaction: '❤️');
    expect(find.text('❤️ · 1시간 전'), findsOneWidget);
  });

  testWidgets('받는 방식은 현재 값만 강조하고 읽기 전용', (tester) async {
    await tester.pumpWidget(_host(const SnapshotReceiveModeSegments(
      mode: SnapshotResponseMode.reactions,
    )));
    expect(find.text('반응까지'), findsOneWidget);
    expect(find.text('반응과 모두의 한마디를 받아요.'), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('오버플로우 없음 $width/$scale', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_host(
          Column(children: [
            SnapshotActivityViewerRow(
              viewer: _viewer(
                'u1',
                reaction: '👏',
                name: 'seoyeon_international_student_club_with_a_very_long_name',
              ),
              status: RelationshipStatus.none,
              now: DateTime(2026, 10, 13, 10),
              onAddFriend: () {},
              onMessage: () {},
            ),
            SnapshotActivityViewerRow(
              viewer: _viewer('u2', name: '欧阳娜娜非常非常长的中文名字测试用户名'),
              status: RelationshipStatus.friends,
              now: DateTime(2026, 10, 13, 10),
              onAddFriend: () {},
              onMessage: () {},
            ),
            const SnapshotReceiveModeSegments(
              mode: SnapshotResponseMode.replies,
            ),
          ]),
          scale: scale,
        ));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
