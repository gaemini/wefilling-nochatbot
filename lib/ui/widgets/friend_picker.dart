// lib/ui/widgets/friend_picker.dart
// 그룹 만들기·그룹 수정이 함께 쓰는 친구 선택 영역:
// `멤버 n` 가로 줄 + 검색 + `친구 n` 목록(선택 원).
// 순서는 호출하는 화면이 정해서 넘기며, 선택을 바꿔도 다시 섞지 않는다.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/group_ui_strings.dart';
import '../../l10n/ui_locale.dart';
import '../../models/user_profile.dart';
import 'group_list_row.dart';

class FriendPicker extends StatefulWidget {
  const FriendPicker({
    super.key,
    required this.orderedFriends,
    required this.selectedIds,
    required this.onToggle,
    this.initialMembers = const <String>{},
  });

  /// 표시 순서가 정해진 전체 친구.
  final List<UserProfile> orderedFriends;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  /// 처음부터 멤버였던 사람(추가 애니메이션 없이 그린다).
  final Set<String> initialMembers;

  @override
  State<FriendPicker> createState() => _FriendPickerState();
}

class _FriendPickerState extends State<FriendPicker> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  TextStyle _style(double size, FontWeight weight, Color color,
          {double? line}) =>
      TextStyle(
        fontFamily: uiFontFamily(context, 'Inter'),
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: size,
        height: line == null ? null : line / size,
        fontWeight: weight,
        color: color,
      );

  List<UserProfile> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.orderedFriends;
    return widget.orderedFriends.where((f) {
      final dn = f.displayNameOrNickname.toLowerCase();
      final nickname = (f.nickname ?? '').toLowerCase();
      return dn.contains(q) || nickname.contains(q);
    }).toList();
  }

  GroupMember _member(UserProfile friend) => GroupMember(
        uid: friend.uid,
        name: friend.displayNameOrNickname,
        photoUrl: friend.photoURL ?? '',
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final strings = GroupUiStrings.of(context);
    final selected = [
      for (final f in widget.orderedFriends)
        if (widget.selectedIds.contains(f.uid)) f,
    ];
    final display = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            strings.membersLabel(selected.length),
            key: const ValueKey('group_members_label'),
            style: _style(12, FontWeight.w600, const Color(0xFF8A8A8A)),
          ),
        ),
        SizedBox(
          height: 82,
          child: selected.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      strings.pickFriendsHint,
                      style:
                          _style(12, FontWeight.w400, const Color(0xFF9A9A9A)),
                    ),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: selected.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, index) =>
                      _buildSelectedSlot(selected[index], l10n),
                ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildSearch(l10n),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(
            strings.friendsLabel(widget.orderedFriends.length),
            style: _style(12, FontWeight.w600, const Color(0xFF8A8A8A)),
          ),
        ),
        if (display.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                l10n.groupNoSearchResults,
                style: _style(14, FontWeight.w500, const Color(0xFF707070)),
              ),
            ),
          )
        else
          for (final friend in display)
            _buildFriendRow(
              friend,
              selected: widget.selectedIds.contains(friend.uid),
            ),
      ],
    );
  }

  Widget _buildSearch(AppLocalizations l10n) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        key: const ValueKey('group_search'),
        controller: _searchController,
        textInputAction: TextInputAction.search,
        style: _style(14, FontWeight.w400, Colors.black),
        decoration: InputDecoration(
          hintText: l10n.searchByFriendName,
          hintStyle: _style(14, FontWeight.w400, const Color(0xFF9A9A9A)),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 16,
            color: Color(0xFF9A9A9A),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 38),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 38, height: 38),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged: (value) => setState(() => _query = value),
      ),
    );
  }

  Widget _buildFriendRow(UserProfile friend, {required bool selected}) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      checked: selected,
      button: true,
      label: friend.displayNameOrNickname,
      onTap: () => widget.onToggle(friend.uid),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('group_friend_${friend.uid}'),
        onTap: () => widget.onToggle(friend.uid),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              GroupMemberAvatar(member: _member(friend), size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  friend.displayNameOrNickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _style(14, FontWeight.w500, Colors.black),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration:
                    reduce ? Duration.zero : const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color:
                      selected ? const Color(0xFF2C6BC0) : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF2C6BC0)
                        : const Color(0xFFD0D0D0),
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded,
                        size: 12, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedSlot(UserProfile friend, AppLocalizations l10n) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final animate = !widget.initialMembers.contains(friend.uid) && !reduce;
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('member-${friend.uid}'),
      tween: Tween<double>(begin: animate ? .8 : 1, end: 1),
      duration: animate ? const Duration(milliseconds: 180) : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        child: Opacity(opacity: scale.clamp(0.0, 1.0), child: child),
      ),
      child: Semantics(
        button: true,
        label: friend.displayNameOrNickname,
        hint: l10n.groupRemoveFriendHint,
        onTap: () => widget.onToggle(friend.uid),
        excludeSemantics: true,
        child: SizedBox(
          width: 54,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 54,
                height: 54,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 3,
                      top: 3,
                      child: GroupMemberAvatar(
                        member: _member(friend),
                        size: 48,
                      ),
                    ),
                    // 빼기 버튼: 눈에 보이는 지름 18, 터치 영역 32.
                    Positioned(
                      right: -8,
                      top: -8,
                      child: GestureDetector(
                        key: ValueKey<String>('group_remove_${friend.uid}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onToggle(friend.uid),
                        child: SizedBox.square(
                          dimension: 32,
                          child: Center(
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 8,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                friend.displayNameOrNickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _style(11, FontWeight.w400, const Color(0xFF444444),
                    line: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
