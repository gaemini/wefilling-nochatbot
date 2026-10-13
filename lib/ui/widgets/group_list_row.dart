// lib/ui/widgets/group_list_row.dart
// 스낵챗 탭의 그룹 목록(그룹 줄, 그룹에 없는 친구 줄)과 멤버 계산.
// 멤버는 이미 구독 중인 친구 목록과의 교집합이며 서버 조회를 하지 않는다.

import 'package:flutter/material.dart';

import '../../l10n/group_ui_strings.dart';
import '../../l10n/ui_locale.dart';
import '../../models/friend_category.dart';
import '../../utils/avatar_image.dart';

/// 그룹 줄·수정 화면이 쓰는 최소 멤버 정보.
class GroupMember {
  const GroupMember({required this.uid, required this.name, this.photoUrl = ''});

  final String uid;
  final String name;
  final String photoUrl;
}

/// 그룹의 멤버 중 지금도 친구인 사람만. 친구 목록 순서를 따른다.
/// [friends]가 null이면 아직 로딩 중이다.
List<GroupMember>? groupMembersFor(
  FriendCategory category,
  List<GroupMember>? friends,
) {
  if (friends == null) return null;
  final ids = category.friendIds.toSet();
  return friends.where((friend) => ids.contains(friend.uid)).toList();
}

/// 어떤 그룹에도 속하지 않은 친구.
List<GroupMember>? ungroupedFriendsOf(
  List<FriendCategory> categories,
  List<GroupMember>? friends,
) {
  if (friends == null) return null;
  final grouped = <String>{
    for (final category in categories) ...category.friendIds,
  };
  return friends.where((friend) => !grouped.contains(friend.uid)).toList();
}

/// 앱의 둥근 네모 프로필(모서리 = 크기 × 0.3).
class GroupMemberAvatar extends StatelessWidget {
  const GroupMemberAvatar({
    super.key,
    required this.member,
    required this.size,
  });

  final GroupMember? member;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.3);
    final name = member?.name ?? '';
    final url = member?.photoUrl ?? '';
    Widget fallback() => Center(
          child: Text(
            name.isEmpty ? '' : name.characters.first.toUpperCase(),
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: size * 0.4,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        );
    Widget child = fallback();
    if (member != null && isDisplayableAvatarUrl(url)) {
      child = Image(
        image: avatarImageProvider(
          uid: member!.uid,
          photoVersion: 0,
          photoUrl: url,
          logicalSize: size,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        ),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: member == null
            ? const Color(0xFFE5E5E5)
            : _tint(member!.uid),
        borderRadius: radius,
      ),
      clipBehavior: Clip.antiAlias,
      child: member == null ? null : child,
    );
  }

  static Color _tint(String seed) {
    const palette = <Color>[
      Color(0xFF8E9F7F),
      Color(0xFF7B879C),
      Color(0xFFB89477),
      Color(0xFF9B7F8E),
      Color(0xFF7FA08F),
      Color(0xFF8F86A8),
    ];
    return palette[seed.hashCode.abs() % palette.length];
  }
}

/// 겹친 멤버 얼굴(최대 [maxShown]) + 넘치면 `+n`. 로딩 중이면 회색 자리 표시.
class GroupFaceStack extends StatelessWidget {
  const GroupFaceStack({
    super.key,
    required this.members,
    this.avatarSize = 28,
    this.overlap = 7,
    this.maxShown = 4,
    this.reserveOverflowSlot = true,
  });

  final List<GroupMember>? members;
  final double avatarSize;
  final double overlap;
  final int maxShown;
  final bool reserveOverflowSlot;

  @override
  Widget build(BuildContext context) {
    final list = members;
    final shown = (list ?? const <GroupMember>[]).take(maxShown).toList();
    final extra = list == null ? 0 : (list.length - shown.length);
    final count = list == null ? 1 : shown.length;
    final width = count == 0
        ? 0.0
        : avatarSize + (count - 1) * (avatarSize - overlap);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: avatarSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (list == null)
                Positioned(
                  left: 0,
                  child: GroupMemberAvatar(member: null, size: avatarSize),
                )
              else
                for (var i = 0; i < shown.length; i++)
                  Positioned(
                    left: i * (avatarSize - overlap),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular((avatarSize + 4) * 0.3),
                      ),
                      padding: const EdgeInsets.all(0),
                      child: GroupMemberAvatar(
                        member: shown[i],
                        size: avatarSize,
                      ),
                    ),
                  ),
            ],
          ),
        ),
        if (reserveOverflowSlot)
          SizedBox(
            width: 24,
            child: extra > 0
                ? Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '+$extra',
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontSize: 12,
                        height: 17 / 12,
                        color: const Color(0xFF8A8A8A),
                      ),
                    ),
                  )
                : null,
          ),
      ],
    );
  }
}

/// 그룹 한 줄(높이 64): 이름·인원·멤버 이름 요약 + 얼굴 묶음 + `›`.
class GroupListRow extends StatelessWidget {
  const GroupListRow({
    super.key,
    required this.category,
    required this.members,
    required this.onTap,
    this.onLongPress,
  });

  final FriendCategory category;

  /// null이면 친구 목록 로딩 중.
  final List<GroupMember>? members;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final strings = GroupUiStrings.of(context);
    final list = members;
    final count = list?.length;
    final subtitle = list == null || list.isEmpty
        ? ''
        : strings.groupMemberNames(
            list.map((m) => m.name).toList(growable: false),
            list.length,
          );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          highlightColor: const Color(0xFFF7F7F7),
          splashColor: const Color(0xFFF7F7F7),
          child: Container(
            height: 64,
            padding: const EdgeInsets.only(left: 16, right: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF2F2F2))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              category.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: uiFontFamily(context, 'Inter'),
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 15,
                                height: 20 / 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            count == null ? '…' : '$count',
                            key: ValueKey<String>('group-count-${category.id}'),
                            style: TextStyle(
                              fontFamily: uiFontFamily(context, 'Inter'),
                              fontSize: 13,
                              height: 20 / 13,
                              color: const Color(0xFF9A9A9A),
                            ),
                          ),
                        ],
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 12,
                            height: 17 / 12,
                            color: const Color(0xFF8A8A8A),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GroupFaceStack(members: list),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Color(0xFFB0B0B0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 그룹에 없는 친구 줄(높이 60). 0명이면 호출부가 숨긴다.
class GroupUngroupedRow extends StatelessWidget {
  const GroupUngroupedRow({
    super.key,
    required this.friends,
    required this.onTap,
  });

  final List<GroupMember> friends;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = GroupUiStrings.of(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 60,
            padding: const EdgeInsets.only(left: 16, right: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF2F2F2))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.ungroupedFriends(friends.length),
                        key: const ValueKey('ungrouped_title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        strings.groupMemberNames(
                          friends.map((m) => m.name).toList(growable: false),
                          friends.length,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 12,
                          height: 17 / 12,
                          color: const Color(0xFF8A8A8A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GroupFaceStack(
                  members: friends,
                  maxShown: 3,
                  reserveOverflowSlot: false,
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Color(0xFFB0B0B0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
