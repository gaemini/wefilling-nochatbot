import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wefilling/models/relationship_status.dart';
import 'package:wefilling/models/snapshot.dart';
import 'package:wefilling/providers/relationship_provider.dart';
import 'package:wefilling/snapshot/snapshot_feel_bar.dart';

class _FakeRelationshipProvider extends ChangeNotifier
    implements RelationshipProvider {
  _FakeRelationshipProvider(this.status);
  final RelationshipStatus? status;
  int lookups = 0;

  @override
  RelationshipStatus? feedRelationshipStatus(String otherUserId) {
    lookups++;
    return status;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SnapshotItem _snapshot(SnapshotResponseMode mode, {Map<String, int>? counts}) =>
    SnapshotItem.fromMap('s1', {
      'authorId': 'author',
      'authorName': 'm1nz1',
      'responseMode': mode.value,
      'reactionCounts': counts ?? const <String, int>{},
    });

class _Log {
  int feels = 0;
  int cameras = 0;
  int viewers = 0;
  final List<String> dm = [];
}

Future<_Log> _pump(
  WidgetTester tester, {
  required SnapshotResponseMode mode,
  RelationshipStatus? status,
  bool isOwner = false,
  bool feelSent = false,
  bool canFeel = true,
  Map<String, int>? counts,
  double width = 375,
  double scale = 1,
  Locale locale = const Locale('ko'),
}) async {
  final log = _Log();
  await tester.binding.setSurfaceSize(Size(width, 500));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider<RelationshipProvider>.value(
    value: _FakeRelationshipProvider(status),
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 500),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SnapshotFeelBar(
                snapshot: _snapshot(mode, counts: counts),
                service: null,
                viewersStream: Stream.value(const <SnapshotViewer>[]),
                isOwner: isOwner,
                feelSent: feelSent,
                canFeel: canFeel,
                onFeel: () => log.feels++,
                onDmReply: (text) async => log.dm.add(text),
                onViewers: () => log.viewers++,
                onSnackReply: () => log.cameras++,
                onFocusChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  return log;
}

void main() {
  const pill = ValueKey('snapshot_feel_pill');
  const friendButton = ValueKey('snapshot_feel_button');
  const input = ValueKey('snapshot_dm_reply_input');
  const camera = ValueKey('snapshot_video_reply_button');

  testWidgets('친구가 아니면 필링 알약 하나(모드 무관)', (tester) async {
    for (final mode in SnapshotResponseMode.values) {
      final log = await _pump(tester,
          mode: mode, status: RelationshipStatus.none);
      expect(find.byKey(pill), findsOneWidget, reason: '$mode');
      expect(find.byKey(input), findsNothing);
      expect(find.byKey(camera), findsNothing);
      await tester.tap(find.byKey(pill));
      expect(log.feels, 1);
    }
  });

  testWidgets('친구 + 친구 답장도: 입력·카메라·필링 버튼', (tester) async {
    final log = await _pump(tester,
        mode: SnapshotResponseMode.replies, status: RelationshipStatus.friends);
    expect(find.byKey(input), findsOneWidget);
    expect(find.text('m1nz1에게 DM으로 답장'), findsOneWidget);
    await tester.tap(find.byKey(camera));
    expect(log.cameras, 1); // 탭 한 번으로 컴포저가 열린다
    await tester.tap(find.byKey(friendButton));
    expect(log.feels, 1);
    expect(find.byKey(pill), findsNothing);
  });

  testWidgets('친구 + 필링만: 알약 하나', (tester) async {
    await _pump(tester,
        mode: SnapshotResponseMode.reactions, status: RelationshipStatus.friends);
    expect(find.byKey(pill), findsOneWidget);
    expect(find.byKey(input), findsNothing);
  });

  testWidgets('보낸 뒤: 문구가 바뀌고 탭이 막힌다(취소 없음)', (tester) async {
    final log = await _pump(tester,
        mode: SnapshotResponseMode.reactions,
        status: RelationshipStatus.none,
        feelSent: true,
        canFeel: false);
    expect(find.text('필링을 보냈어요'), findsOneWidget);
    await tester.tap(find.byKey(pill));
    expect(log.feels, 0);
  });

  testWidgets('글 답장은 DM 전송 콜백으로 전달된다', (tester) async {
    final log = await _pump(tester,
        mode: SnapshotResponseMode.replies, status: RelationshipStatus.friends);
    await tester.enterText(find.byKey(input), '안녕하세요');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('snapshot_dm_reply_send')));
    await tester.pump();
    expect(log.dm, ['안녕하세요']);
  });

  testWidgets('작성자: 필링 n · 본 사람 m 알약만 보이고 개수 노출은 작성자에게만',
      (tester) async {
    final log = await _pump(tester,
        mode: SnapshotResponseMode.replies,
        isOwner: true,
        counts: {'❤️': 7});
    expect(find.text('필링 7 · 본 사람 0'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('snapshot_owner_activity_pill')));
    expect(log.viewers, 1);
    // 보는 사람 화면에는 개수가 없다.
    await _pump(tester,
        mode: SnapshotResponseMode.replies,
        status: RelationshipStatus.none,
        counts: {'❤️': 7});
    expect(find.textContaining('7'), findsNothing);
  });

  testWidgets('글자 크기: 표를 넘는 글자가 없다', (tester) async {
    await _pump(tester,
        mode: SnapshotResponseMode.replies, status: RelationshipStatus.friends);
    for (final text in tester.widgetList<EditableText>(find.byType(EditableText))) {
      expect(text.style.fontSize, lessThanOrEqualTo(15));
    }
    await _pump(tester,
        mode: SnapshotResponseMode.reactions, status: RelationshipStatus.none);
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.style?.fontSize ?? 14, lessThanOrEqualTo(15));
    }
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      for (final locale in const [Locale('ko'), Locale('en'), Locale('zh')]) {
        testWidgets('오버플로우 없음 $width/$scale/${locale.languageCode}',
            (tester) async {
          for (final config in [
            (SnapshotResponseMode.replies, RelationshipStatus.friends, false),
            (SnapshotResponseMode.reactions, RelationshipStatus.none, false),
            (SnapshotResponseMode.replies, RelationshipStatus.none, true),
          ]) {
            await _pump(
              tester,
              mode: config.$1,
              status: config.$2,
              isOwner: config.$3,
              counts: {'❤️': 12345},
              width: width,
              scale: scale,
              locale: locale,
            );
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  }
}
