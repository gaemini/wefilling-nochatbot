// lib/ui/widgets/groups_empty_state.dart
// 그룹이 하나도 없을 때의 빈 화면: 친구 얼굴 + 제목/설명 + 이름 칩 + 버튼 하나.
// 서버를 읽지 않고 호출부가 넘긴 친구 목록만 쓴다.

import 'package:flutter/material.dart';

import '../../l10n/group_ui_strings.dart';
import '../../l10n/ui_locale.dart';
import 'group_list_row.dart';
import 'tab_empty_state.dart';

class GroupsEmptyState extends StatefulWidget {
  const GroupsEmptyState({
    super.key,
    required this.friendCount,
    required this.faces,
    required this.onCreate,
    required this.onFindFriends,
  });

  /// null이면 친구 목록 로딩 중.
  final int? friendCount;

  /// 앞 6명(없으면 로딩 중 자리 표시).
  final List<GroupMember>? faces;

  /// 고른 이름 칩(없으면 null)을 넘겨 기존 그룹 만들기 흐름을 시작한다.
  final ValueChanged<String?> onCreate;
  final VoidCallback onFindFriends;

  @override
  State<GroupsEmptyState> createState() => _GroupsEmptyStateState();
}

class _GroupsEmptyStateState extends State<GroupsEmptyState> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final strings = GroupUiStrings.of(context);
    final friendCount = widget.friendCount;
    final noFriends = friendCount != null && friendCount == 0;
    final chips = strings.groupNameChips;
    final selected = _selected;

    return SafeArea(
      top: false,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 44, bottom: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!noFriends) ...[
                          Semantics(
                            label: friendCount == null
                                ? null
                                : strings.friendsCount(friendCount),
                            child: ExcludeSemantics(
                              child: Row(
                                key: const ValueKey('groups_empty_faces'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GroupFaceStack(
                                    members: widget.faces,
                                    avatarSize: 36,
                                    overlap: 9,
                                    maxShown: 6,
                                    borderWidth: 2.5,
                                    reserveOverflowSlot: false,
                                    placeholderCount: 6,
                                  ),
                                  if (friendCount != null) ...[
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                      strings.friendsCount(friendCount),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily:
                                            uiFontFamily(context, 'Inter'),
                                        fontFamilyFallback: const [
                                          'NotoSansKR'
                                        ],
                                        fontSize: 13,
                                        height: 19 / 13,
                                        color: const Color(0xFF8A8A8A),
                                      ),
                                    ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        TabEmptyStateText(
                          title: strings.groupsEmptyTitle,
                          body: noFriends
                              ? strings.groupsNoFriends
                              : strings.groupsEmptyBody,
                        ),
                        if (!noFriends) ...[
                          const SizedBox(height: 26),
                          Text(
                            strings.groupsNamePrompt,
                            style: TextStyle(
                              fontFamily: uiFontFamily(context, 'Inter'),
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: 12,
                              height: 16 / 12,
                              color: const Color(0xFF8A8A8A),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final name in chips)
                                  _NameChip(
                                    key: ValueKey<String>('groups_chip_$name'),
                                    label: name,
                                    selected: selected == name,
                                    onTap: () => setState(
                                      () => _selected =
                                          selected == name ? null : name,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TabEmptyStateButton(
                          key: const Key('groups_empty_create_button'),
                          label: noFriends
                              ? strings.findFriendsButton
                              : (selected == null
                                  ? strings.groupsFirstButton
                                  : strings.createNamedGroup(selected)),
                          onPressed: noFriends
                              ? widget.onFindFriends
                              : () => widget.onCreate(selected),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 그룹 빈 화면의 이름 칩: 높이 34, 모서리 17. 고르면 검정 바탕 + 흰 글자.
class _NameChip extends StatelessWidget {
  const _NameChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 150),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.black : Colors.white,
            border: Border.all(
              color: selected ? Colors.black : const Color(0xFFE3E3E3),
            ),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 13,
              height: 18 / 13,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

