// lib/ui/widgets/snack_chat_groups_tab_bar.dart
// 스낵챗 탭 상단의 [스낵챗 | 그룹] 탭 바.
// 높이는 탭 42 + 두께 1 = 43으로 고정하고, 어떤 기기·글자 크기에서도 아래로
// 넘치지 않도록 같은 높이로 잘라 그린다(BOTTOM OVERFLOWED 방지).

import 'package:flutter/material.dart';

import '../../l10n/ui_locale.dart';
import 'motion_press.dart';
import 'motion_selectable.dart';

class SnackChatGroupsTabBar extends StatelessWidget
    implements PreferredSizeWidget {
  const SnackChatGroupsTabBar({
    super.key,
    required this.controller,
    required this.snackChatLabel,
    required this.groupsLabel,
    required this.snackChatSemantic,
    required this.groupsSemantic,
  });

  /// 탭 높이와 TabBar가 아래에 더하는 두께(합 43).
  static const double tabHeight = 42;
  static const double indicatorWeight = 1;
  static const double totalHeight = tabHeight + indicatorWeight;

  final TabController controller;
  final String snackChatLabel;
  final String groupsLabel;
  final String snackChatSemantic;
  final String groupsSemantic;

  @override
  Size get preferredSize => const Size.fromHeight(totalHeight);

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, String semantic, int index) => Tab(
          height: tabHeight,
          child: MotionPress(
            pressedScale: MotionSelectable.segmentScale,
            child: Semantics(
              label: semantic,
              selected: controller.index == index,
              button: true,
              excludeSemantics: true,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        );
    return SizedBox(
      height: totalHeight,
      // TabBar 내부 계산이 1px라도 커도 바깥으로 넘치지 않게 잘라 낸다.
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: totalHeight + 16,
          child: SizedBox(
            height: totalHeight,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => TabBar(
                  controller: controller,
                  // 선택 밑줄: 2pt, 폭 44, 검정(파란색을 아낀다).
                  indicator:
                      const FixedWidthUnderline(width: 44, thickness: 2),
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorWeight: indicatorWeight,
                  dividerColor: const Color(0xFFEBEBEB),
                  dividerHeight: 1,
                  labelColor: Colors.black,
                  unselectedLabelColor: const Color(0xFF8A8A8A),
                  labelStyle: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: [
                    tab(snackChatLabel, snackChatSemantic, 0),
                    tab(groupsLabel, groupsSemantic, 1),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 탭 선택 밑줄: 탭 가운데에 고정 폭으로 그린다.
class FixedWidthUnderline extends Decoration {
  const FixedWidthUnderline({required this.width, required this.thickness});

  final double width;
  final double thickness;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      FixedWidthUnderlinePainter(width, thickness);
}

class FixedWidthUnderlinePainter extends BoxPainter {
  FixedWidthUnderlinePainter(this.width, this.thickness);

  final double width;
  final double thickness;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final left = offset.dx + (size.width - width) / 2;
    final top = offset.dy + size.height - thickness;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width, thickness),
        Radius.circular(thickness / 2),
      ),
      Paint()..color = Colors.black,
    );
  }
}
