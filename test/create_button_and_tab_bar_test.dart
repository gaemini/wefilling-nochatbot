import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/app_fab.dart';
import 'package:wefilling/ui/widgets/create_action_button.dart';
import 'package:wefilling/ui/widgets/snack_chat_groups_tab_bar.dart';

class _Host extends StatefulWidget {
  const _Host({required this.child});
  final Widget Function(TabController) child;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  late final TabController c = TabController(length: 2, vsync: this);
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child(c);
}

void main() {
  for (final width in const [320.0, 360.0, 411.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0, 3.0]) {
      testWidgets('탭 바 오버플로우 없음 $width/$scale', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 700),
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(top: 40),
            ),
            child: _Host(
              child: (c) => Scaffold(
                appBar: AppBar(
                  toolbarHeight: 0,
                  bottom: SnackChatGroupsTabBar(
                    controller: c,
                    snackChatLabel: '스낵챗',
                    groupsLabel: '그룹',
                    snackChatSemantic: '스낵챗 탭',
                    groupsSemantic: '그룹 탭',
                  ),
                ),
                body: const SizedBox(),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(SnackChatGroupsTabBar)).height,
          SnackChatGroupsTabBar.totalHeight,
        );
      });
    }
  }

  testWidgets('만들기 버튼: 같은 높이 46과 오른쪽·아래 16 위치', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<Rect> rectOf(Widget fab) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: const SizedBox(), floatingActionButton: fab),
      ));
      await tester.pump();
      return tester.getRect(find.byType(CreateActionButton));
    }

    final post = await rectOf(AppFab.extended(
      onPressed: () {},
      icon: Icons.add_rounded,
      showIcon: false,
      label: '공유하기',
      semanticLabel: '공유',
    ));
    final meetup = await rectOf(AppFab.createMeetup(
      onPressed: () {},
      label: '모임 만들기',
    ));
    final message = await rectOf(AppFab.extended(
      onPressed: () {},
      icon: Icons.add_rounded,
      label: '새 메시지',
      semanticLabel: '새 메시지',
    ));
    for (final r in [post, meetup, message]) {
      expect(r.height, CreateActionButton.height);
      expect(375 - r.right, kCreateActionMargin);
      expect(700 - r.bottom, kCreateActionMargin);
    }
  });
}
