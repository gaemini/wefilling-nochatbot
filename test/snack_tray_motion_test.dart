import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/screens/snapshot_detail_screen.dart';

class _Route extends SnapshotDetailMotionRoute {
  _Route({super.originRect}) : super(snapshots: const [], initialIndex: 0);
  @override
  Widget buildContent(BuildContext context) =>
      const Scaffold(body: Text('detail'));
}

Future<void> _open(WidgetTester tester, Rect? origin) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(platform: TargetPlatform.android),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () =>
              Navigator.of(context).push(_Route(originRect: origin)),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
}

void main() {
  testWidgets('originRect가 없으면 기존 전환 그대로', (tester) async {
    await _open(tester, null);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('snapshot_origin_clip')), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('타일 위치에서 전체 화면으로 커진다', (tester) async {
    const origin = Rect.fromLTWH(20, 100, 96, 140);
    await _open(tester, origin);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final early = tester.getRect(find.byKey(const ValueKey('snapshot_origin_clip')));
    expect(early.width, lessThan(400));
    await tester.pumpAndSettle();
    final done = tester.getRect(find.byKey(const ValueKey('snapshot_origin_clip')));
    expect(done.size, tester.view.physicalSize / tester.view.devicePixelRatio);
    expect(find.text('detail'), findsOneWidget);
  });
}
