import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/relationship_status.dart';
import 'package:provider/provider.dart';
import 'package:wefilling/models/snapshot.dart';
import 'package:wefilling/models/snapshot_mutual_feel.dart';
import 'package:wefilling/providers/relationship_provider.dart';
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

Widget _host(Widget child, {double scale = 1, double width = 375}) =>
    MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(body: child),
      ),
    );

void main() {
  sheetTests();
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

  testWidgets('보조 줄에는 본 시간만 나오고 필링 여부는 없다', (tester) async {
    await pumpRow(tester, RelationshipStatus.friends, reaction: '❤️');
    expect(find.text('1시간 전'), findsOneWidget);
    expect(find.textContaining('❤️'), findsNothing);
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
          ]),
          scale: scale,
        ));
        expect(tester.takeException(), isNull);
      });
    }
  }
}

// ---- 시트 전체(스낵 v3) ----

class _FakeRelationshipProvider extends ChangeNotifier
    implements RelationshipProvider {
  _FakeRelationshipProvider(this.statuses);
  final Map<String, RelationshipStatus> statuses;
  int lookups = 0;

  @override
  RelationshipStatus? feedRelationshipStatus(String otherUserId) {
    lookups++;
    return statuses[otherUserId] ?? RelationshipStatus.none;
  }

  @override
  Future<void> ensureInitialized() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void sheetTests() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required List<SnapshotViewer> viewers,
    List<SnapshotMutualFeel> mutuals = const [],
    Map<String, RelationshipStatus> statuses = const {},
    double width = 375,
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshot = SnapshotItem.fromMap('s1', {
      'ownerId': 'me',
      'reactionCounts': {'❤️': 7},
    });
    await tester.pumpWidget(ChangeNotifierProvider<RelationshipProvider>.value(
      value: _FakeRelationshipProvider(statuses),
      child: _host(
        SnapshotActivitySheet(
          snapshot: snapshot,
          viewersStream: Stream.value(viewers),
          mutualFeelsLoader: () async => mutuals,
        ),
        scale: scale,
        width: width,
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  SnapshotMutualFeel mutual() => SnapshotMutualFeel(
        pairKey: 'a_b',
        otherUserId: 'u9',
        otherName: '율율율',
        otherPhotoUrl: '',
        otherPhotoVersion: 0,
        createdAt: DateTime(2026, 10, 13),
        mine: const SnapshotFeelThumbnail(
          snapshotId: 's1',
          expired: false,
          imageStoragePath: 'p',
          storageBucket: '',
          isVideo: false,
        ),
        theirs: const SnapshotFeelThumbnail(
          snapshotId: 's2',
          expired: true,
          imageStoragePath: '',
          storageBucket: '',
          isVideo: false,
        ),
      );

  testWidgets('머리: 필링 합계·본 사람 수·안내, 행에 필링 표시 없음', (tester) async {
    await pumpSheet(tester, viewers: [
      _viewer('u1', reaction: '❤️', name: 'jaemini'),
      _viewer('u2', name: 'lina'),
    ], statuses: {
      'u1': RelationshipStatus.friends,
    });
    expect(find.text('필링 7'), findsOneWidget);
    expect(find.text('본 사람 2'), findsNWidgets(2));
    expect(find.text('서로 필링이 되면 누가 보냈는지 알 수 있어요'), findsOneWidget);
    expect(find.text('메시지'), findsOneWidget);
    expect(find.text('친구 추가'), findsOneWidget);
    expect(find.textContaining('❤️'), findsNothing);
    expect(find.text('본 사람 목록에는 필링 여부가 표시되지 않아요'), findsOneWidget);
  });

  testWidgets('서로 필링이 있으면 인사하기 줄이 나온다', (tester) async {
    await pumpSheet(tester, viewers: [_viewer('u1')], mutuals: [mutual()]);
    expect(find.text('서로 필링'), findsOneWidget);
    expect(find.text('율율율'), findsOneWidget);
    expect(find.text('인사하기'), findsOneWidget);
  });

  testWidgets('서로 필링이 없으면 그 구역이 없다', (tester) async {
    await pumpSheet(tester, viewers: [_viewer('u1')]);
    expect(find.text('서로 필링'), findsNothing);
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('시트 오버플로우 없음 $width/$scale', (tester) async {
        await pumpSheet(
          tester,
          viewers: [
            _viewer('u1',
                name: 'seoyeon_international_student_club_with_a_very_long_name'),
            _viewer('u2', name: '欧阳娜娜非常非常长的中文名字测试用户名'),
          ],
          mutuals: [mutual()],
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
