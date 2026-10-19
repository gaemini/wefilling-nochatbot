import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'wf_colors.dart';

/// 마이페이지 탭 하나: 이름(15/w700) + 보조 개수(13, ink4).
class ProfileTabLabel {
  const ProfileTabLabel(this.label, {this.count});

  final String label;
  final int? count;
}

/// 관심 | 활동 탭. 두 탭은 같은 폭, 2.5px ink 밑줄이 탭 폭의 50%로 미끄러진다
/// (320ms, 살짝 넘침). 아래 1px 선.
class ProfileTabBar extends StatelessWidget implements PreferredSizeWidget {
  const ProfileTabBar({
    super.key,
    required this.controller,
    required this.tabs,
  });

  final TabController controller;
  final List<ProfileTabLabel> tabs;

  static const double height = 48;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ColoredBox(
        color: Colors.white,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final selected = controller.index;
            return Stack(
              children: [
                Row(
                  children: [
                    for (var i = 0; i < tabs.length; i++)
                      Expanded(
                        child: Semantics(
                          selected: i == selected,
                          button: true,
                          child: InkWell(
                            key: ValueKey('profile_tab_$i'),
                            onTap: () {
                              if (i != selected) HapticFeedback.selectionClick();
                              controller.animateTo(i);
                            },
                            child: SizedBox(
                              height: height,
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text.rich(
                                    TextSpan(children: [
                                      TextSpan(text: tabs[i].label),
                                      if (tabs[i].count != null)
                                        TextSpan(
                                          text: '  ${tabs[i].count}',
                                          style: tagTextStyle(context, 13,
                                              FontWeight.w600, WfColors.ink4),
                                        ),
                                    ]),
                                    maxLines: 1,
                                    style: tagTextStyle(
                                      context,
                                      15,
                                      FontWeight.w700,
                                      i == selected
                                          ? WfColors.ink
                                          : WfColors.ink4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ColoredBox(
                      color: WfColors.line, child: SizedBox(height: 1)),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedAlign(
                      duration: MotionTokens.of(
                          context, const Duration(milliseconds: 320)),
                      curve: MotionTokens.springOut,
                      alignment: Alignment(
                        tabs.length <= 1
                            ? 0
                            : -1 + 2 * selected / (tabs.length - 1),
                        1,
                      ),
                      child: FractionallySizedBox(
                        widthFactor: 1 / tabs.length,
                        child: const Center(
                          heightFactor: 1,
                          child: FractionallySizedBox(
                            widthFactor: .5,
                            child: SizedBox(
                              height: 2.5,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: WfColors.ink,
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(2)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
