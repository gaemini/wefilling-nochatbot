import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/screens/create_snapshot_screen.dart';
import 'package:wefilling/screens/post_detail_screen.dart';
import 'package:wefilling/screens/snapshot_detail_screen.dart';

// Exercise the production route transitions without Firebase or media I/O.
class _PostPreviewRoute extends PostDetailMotionRoute {
  _PostPreviewRoute()
      : super(
            post: Post(
                id: 'motion',
                title: '',
                content: '',
                author: 'A',
                userId: 'a',
                createdAt: DateTime.utc(2026)));
  @override
  Widget buildContent(BuildContext context) =>
      const Scaffold(body: Text('detail'));
}

class _SnapshotPreviewRoute extends SnapshotDetailMotionRoute {
  _SnapshotPreviewRoute() : super(snapshots: const [], initialIndex: 0);
  @override
  Widget buildContent(BuildContext context) =>
      const Scaffold(body: Text('detail'));
}

void main() {
  for (final snapshot in [false, true]) {
    testWidgets('${snapshot ? 'snapshot' : 'post'} keeps native iOS edge back',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.of(context).push(snapshot
                          ? _SnapshotPreviewRoute()
                          : _PostPreviewRoute()),
                      child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      expect(find.byType(CupertinoPageTransition), findsWidgets);
      await tester.dragFrom(const Offset(1, 200), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsNothing);
      expect(find.text('open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        '${snapshot ? 'snapshot' : 'post'} handles Android back without replacing stack',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.of(context).push(snapshot
                          ? _SnapshotPreviewRoute()
                          : _PostPreviewRoute()),
                      child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  }

  testWidgets('rapid editor reversal keeps one canvas key and media subtree',
      (tester) async {
    final canvas = GlobalKey();
    Widget view(bool editor) => MaterialApp(
            home: Scaffold(
                body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          layoutBuilder: snapshotEditorMotionLayout,
          child: editor
              ? SizedBox(
                  key: const ValueKey('editor'),
                  child:
                      RepaintBoundary(key: canvas, child: const Text('canvas')))
              : const SizedBox(
                  key: ValueKey('preview'), child: Text('preview')),
        )));
    await tester.pumpWidget(view(true));
    await tester.pumpWidget(view(false));
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text('canvas'), findsNothing);
    await tester.pumpWidget(view(true));
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.byKey(canvas), findsOneWidget);
    expect(find.text('preview'), findsNothing);
    await tester.pumpWidget(view(false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
