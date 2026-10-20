import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../snackbar/app_snackbar.dart';

import '../../l10n/app_localizations.dart';
import '../../models/interest_overview.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'friend_request_button.dart';
import 'overlap_person_card.dart';
import 'shared_tag_tile.dart';
import 'snap_to_item_physics.dart';
import 'stagger_in.dart';
import 'wf_colors.dart';

/// 처음 보일 때·되돌리기: 10px 아래에서 400ms(Cubic(.2,.8,.3,1)), 60ms 간격(앞 4장).
const peopleAppearCurve = Cubic(.2, .8, .3, 1);
const peopleAppearDuration = Duration(milliseconds: 400);

/// 숨기기: 0–45% 투명·0.9배 → 45–100% 폭 접힘(420ms).
const peopleHideCurve = Cubic(.65, 0, .35, 1);
const peopleHideDuration = Duration(milliseconds: 420);

/// 섹션 머리: '새로 알게 될 사람  12' + '모두 보기 ›' / '내 관심사와 많이 겹치는 순이에요'.
class OverlapPeopleHeader extends StatelessWidget {
  const OverlapPeopleHeader({
    super.key,
    required this.title,
    required this.count,
    required this.onSeeAll,
  });

  final String title;
  final int? count;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: title),
                    if (count != null && count! > 0)
                      TextSpan(
                        text: '  $count',
                        style: tagTextStyle(
                            context, 17, FontWeight.w700, WfColors.ink4),
                      ),
                  ]),
                  key: const ValueKey('overlap-people-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      tagTextStyle(context, 20, FontWeight.w800, WfColors.ink)
                          .copyWith(letterSpacing: -.5),
                ),
              ),
              TextButton(
                key: const ValueKey('overlap_see_all'),
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  foregroundColor: WfColors.ink3,
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text('${l10n.peopleSeeAll} ›',
                    style: tagTextStyle(
                        context, 14, FontWeight.w600, WfColors.ink3)),
              ),
            ],
          ),
          Text(l10n.peopleSortHint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tagTextStyle(context, 13, FontWeight.w500, WfColors.ink3)),
        ],
      ),
    );
  }
}

/// 0명일 때: 회색 한 줄 카드 + '관심사 더 고르기 ›'.
class OverlapPeopleEmpty extends StatelessWidget {
  const OverlapPeopleEmpty({super.key, required this.onPickMore});

  final VoidCallback onPickMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        key: const ValueKey('overlap-people-empty'),
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        decoration: BoxDecoration(
          color: WfColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(l10n.peopleEmpty,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tagTextStyle(
                      context, 13.5, FontWeight.w500, WfColors.ink2)),
            ),
            TextButton(
              onPressed: onPickMore,
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              child: Text(l10n.peopleMoreTagsCta,
                  style: tagTextStyle(
                      context, 13.5, FontWeight.w700, WfColors.brand)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 가로 레일: 좌우 20, 간격 10, 카드 252, 카드 단위로 멈춤. 다음 카드가 ~80px 보인다.
/// 끝에서 3장 전에 [onLoadMore]. 스크롤하면 말풍선을 닫는다.
class OverlapPeopleRail extends StatelessWidget {
  const OverlapPeopleRail({
    super.key,
    required this.people,
    required this.relationOf,
    required this.onOpenProfile,
    this.onHide,
    this.onLoadMore,
    this.collapsing = const {},
    this.onCollapsed,
  });

  final List<OverlapPerson> people;

  /// 접히는 중인 카드(×). 다 접히면 [onCollapsed].
  final Set<String> collapsing;
  final ValueChanged<OverlapPerson>? onCollapsed;
  final PeopleRelation Function(OverlapPerson person) relationOf;
  final ValueChanged<OverlapPerson> onOpenProfile;
  final ValueChanged<OverlapPerson>? onHide;
  final VoidCallback? onLoadMore;

  static const double gap = 10;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          SharedTagTile.closeTooltips();
        }
        if (notification.metrics.extentAfter <
            (OverlapPersonCard.width + gap) * 3) {
          onLoadMore?.call();
        }
        return false;
      },
      child: SizedBox(
        height: OverlapPersonCard.heightFor(context),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          physics:
              const SnapToItemPhysics(extent: OverlapPersonCard.width + gap),
          itemCount: people.length,
          itemBuilder: (context, index) {
            final person = people[index];
            Widget card = Padding(
              padding:
                  EdgeInsets.only(right: index == people.length - 1 ? 0 : gap),
              child: Align(
                alignment: Alignment.topCenter,
                child: OverlapPersonCard(
                  key: ValueKey('overlap_card_${person.uid}'),
                  person: person,
                  relation: relationOf(person),
                  onOpenProfile: () => onOpenProfile(person),
                  onHide: onHide == null ? null : () => onHide!(person),
                ),
              ),
            );
            if (collapsing.contains(person.uid)) {
              card = _Collapse(
                key: ValueKey('overlap_collapse_${person.uid}'),
                onDone: () => onCollapsed?.call(person),
                child: card,
              );
            }
            return index < 4
                ? StaggerIn(
                    key: ValueKey('overlap_in_${person.uid}'),
                    index: index,
                    step: const Duration(milliseconds: 60),
                    duration: peopleAppearDuration,
                    curve: peopleAppearCurve,
                    child: card,
                  )
                : card;
          },
        ),
      ),
    );
  }
}

/// × 숨기기: 0–45% 투명·0.9배 → 45–100% 폭(간격 포함)이 0으로(420ms). 동작 줄이기면 바로.
class _Collapse extends StatefulWidget {
  const _Collapse({super.key, required this.child, required this.onDone});

  final Widget child;
  final VoidCallback onDone;

  @override
  State<_Collapse> createState() => _CollapseState();
}

class _CollapseState extends State<_Collapse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: peopleHideDuration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.value > 0) return;
    if (MotionTokens.reduceMotion(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
      return;
    }
    _controller.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, .45, curve: peopleHideCurve));
    final size = CurvedAnimation(
        parent: _controller,
        curve: const Interval(.45, 1, curve: peopleHideCurve));
    return SizeTransition(
      sizeFactor: ReverseAnimation(size),
      axis: Axis.horizontal,
      alignment: AlignmentDirectional.centerStart,
      child: FadeTransition(
        opacity: ReverseAnimation(fade),
        child: ScaleTransition(
          scale: Tween<double>(begin: 1, end: .9).animate(fade),
          child: widget.child,
        ),
      ),
    );
  }
}

/// '{name}님을 추천에서 숨겼어요' + 4초 '되돌리기'.
void showPeopleHiddenUndo(
  BuildContext context,
  OverlapPerson person, {
  required VoidCallback onUndo,
}) {
  final l10n = AppLocalizations.of(context)!;
  AppSnackBar.show(
    context,
    message: l10n.peopleHidden(person.name.isEmpty ? l10n.user : person.name),
    duration: const Duration(seconds: 4),
    action: SnackBarAction(
      label: l10n.peopleUndo,
      onPressed: () {
        HapticFeedback.selectionClick();
        onUndo();
      },
    ),
  );
}
