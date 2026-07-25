import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/snack_chat.dart';
import '../models/user_profile.dart';
import '../repositories/users_repository.dart';
import '../services/notification_service.dart';
import '../services/snack_chat_service.dart';
import '../ui/sheets/snack_chat_unfavorite_sheet.dart';
import '../utils/country_flag_helper.dart';
import '../utils/responsive_helper.dart';
import 'friend_profile_screen.dart';

class SnackChatInfoScreen extends StatefulWidget {
  final String snackChatId;

  const SnackChatInfoScreen({super.key, required this.snackChatId});

  @override
  State<SnackChatInfoScreen> createState() => _SnackChatInfoScreenState();
}

class _SnackChatInfoScreenState extends State<SnackChatInfoScreen> {
  final SnackChatService _snackChatService = SnackChatService();
  final UsersRepository _usersRepository = UsersRepository();
  final NotificationService _notificationService = NotificationService();

  bool _isInviting = false;
  bool _isLeaving = false;
  bool _isMuted = false;
  Future<List<UserProfile>>? _participantsFuture;
  String _participantsSignature = '';
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadMuteState();
  }

  Future<void> _loadMuteState() async {
    final muted = await _snackChatService.isSnackChatMuted(widget.snackChatId);
    if (mounted) setState(() => _isMuted = muted);
  }

  Future<void> _toggleMute() async {
    final newVal = !_isMuted;
    setState(() => _isMuted = newVal);
    await _snackChatService.toggleMuteSnackChat(widget.snackChatId, newVal);
  }

  Future<List<UserProfile>> _loadParticipants(SnackChat room) async {
    if (room.participantIds.isEmpty) return const <UserProfile>[];
    final users =
        await _usersRepository.getUserProfilesBatch(room.participantIds);
    users.sort(
        (a, b) => a.displayNameOrNickname.compareTo(b.displayNameOrNickname));
    return users;
  }

  void _ensureParticipantsFuture(SnackChat room) {
    final signature = room.participantIds.toList()..sort();
    final key = signature.join('|');
    if (_participantsFuture == null || _participantsSignature != key) {
      _participantsSignature = key;
      _participantsFuture = _loadParticipants(room);
    }
  }

  Future<void> _openInviteSheet(SnackChat room) async {
    if (_uid == null || _uid != room.creatorId || _isInviting) return;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final myFriends = await _usersRepository.getUserFriends(_uid!);
    final currentIds = room.participantIds.toSet();
    final candidates =
        myFriends.where((f) => !currentIds.contains(f.uid)).toList();
    if (!mounted) return;

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo ? '초대 가능한 친구가 없습니다.' : 'No friends available to invite.',
          ),
        ),
      );
      return;
    }

    final selected = <String>{};
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.72,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                      child: Row(
                        children: [
                          Text(
                            isKo ? '참여자 초대' : 'Invite Participants',
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final friend = candidates[index];
                          final checked = selected.contains(friend.uid);
                          return CheckboxListTile(
                            value: checked,
                            activeColor: AppColors.pointColor,
                            onChanged: (_) {
                              if (checked) {
                                setSheetState(
                                    () => selected.remove(friend.uid));
                                return;
                              }
                              setSheetState(() => selected.add(friend.uid));
                            },
                            secondary: CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFFE5E7EB),
                              backgroundImage: (friend.photoURL != null &&
                                      friend.photoURL!.isNotEmpty)
                                  ? NetworkImage(friend.photoURL!)
                                  : null,
                              child: (friend.photoURL == null ||
                                      friend.photoURL!.isEmpty)
                                  ? Text(
                                      friend.displayNameOrNickname.isEmpty
                                          ? '?'
                                          : friend.displayNameOrNickname[0]
                                              .toUpperCase(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(
                              friend.displayNameOrNickname,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.pointColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () =>
                              Navigator.pop(sheetContext, selected),
                          child: Text(
                            isKo
                                ? '초대하기 (${selected.length}명)'
                                : 'Invite (${selected.length})',
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || result.isEmpty || !mounted) return;

    setState(() => _isInviting = true);
    try {
      final invited = await _snackChatService.inviteParticipants(
        room.id,
        participantIds: result.toList(),
      );
      if (invited.isEmpty || !mounted) return;

      // 닉네임을 Firestore에서 직접 조회 (Firebase Auth displayName은 동기화 안 될 수 있음)
      String creatorName = '';
      try {
        final profiles =
            await _usersRepository.getUserProfilesBatch([_uid ?? '']);
        if (profiles.isNotEmpty) {
          creatorName = profiles.first.nickname?.trim() ?? '';
          if (creatorName.isEmpty) {
            creatorName = profiles.first.displayNameOrNickname.trim();
          }
        }
      } catch (_) {}
      if (creatorName.isEmpty) {
        creatorName =
            FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
      }
      await _notificationService.sendSnackChatInviteNotification(
        participantIds: invited,
        snackChatId: room.id,
        snackChatName: room.title,
        creatorId: _uid ?? '',
        creatorName: creatorName,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo
                ? '${invited.length}명을 초대했습니다.'
                : 'Invited ${invited.length} participants.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo ? '초대 실패: $e' : 'Invite failed: $e',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isInviting = false);
    }
  }

  Future<void> _toggleFavorite(SnackChat room) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final nextValue = !room.isFavoritedBy(currentUserId);
    if (!nextValue) {
      final confirmed = await showSnackChatUnfavoriteSheet(context);
      if (!confirmed) return;
    }
    await _snackChatService.toggleFavorite(room.id, nextValue);
  }

  Future<void> _leaveRoom(SnackChat room) async {
    if (_isLeaving) return;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        // 바텀시트는 별도 컨텍스트로 열리므로 locale을 직접 읽어 한/영 정확도 보장
        final sheetIsKo = Localizations.localeOf(ctx).languageCode == 'ko';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 핸들 바
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                // 아이콘 + 제목
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: Color(0xFFEF4444),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      sheetIsKo ? '채팅방 나가기' : 'Leave Room',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  sheetIsKo
                      ? '채팅방에서 나가면 대화 내용이 삭제되고\n다시 초대를 받아야 참여할 수 있습니다.'
                      : 'Once you leave, your messages will be removed\nand you must be re-invited to rejoin.',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B7280),
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 28),
                // 버튼 행
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx, false),
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            sheetIsKo ? '취소' : 'Cancel',
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx, true),
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            sheetIsKo ? '나가기' : 'Leave',
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
    if (confirm != true || !mounted) return;
    setState(() => _isLeaving = true);
    try {
      await _snackChatService.leaveRoom(room.id);
      if (!mounted) return;
      // 정보 화면 + 채팅 화면을 한 번에 안전하게 닫기
      // popUntil로 SnackChatInfoScreen과 SnackChatScreen을 함께 제거
      int popCount = 0;
      Navigator.of(context).popUntil((route) {
        if (popCount >= 2 || route.isFirst) return true;
        popCount++;
        return false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isKo ? '나가기 실패: $e' : 'Failed to leave: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLeaving = false);
    }
  }

  Widget _buildRoomSummary(
    BuildContext context,
    SnackChat room,
    AppLocalizations l10n,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: context.rs(16).clamp(14, 18).toDouble(),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: context.ri(36).clamp(34, 38).toDouble(),
            child: Center(
              child: Icon(
                Icons.forum_outlined,
                size: context.ri(22).clamp(20, 23).toDouble(),
                color: const Color(0xFF475467),
              ),
            ),
          ),
          SizedBox(width: context.rs(10).clamp(8, 12).toDouble()),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: context.rf(16).clamp(15, 17).toDouble(),
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                    height: 1.25,
                  ),
                ),
                SizedBox(height: context.rs(6).clamp(4, 7).toDouble()),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l10n.snackChatParticipantCount(room.participantCount),
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: context.rf(12.5).clamp(12, 13.5).toDouble(),
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF667085),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          room.hasNoExpiration
                              ? Icons.all_inclusive_rounded
                              : Icons.schedule_rounded,
                          size: context.ri(14).clamp(13, 15).toDouble(),
                          color: const Color(0xFF667085),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          room.hasNoExpiration
                              ? l10n.snackChatDurationNoEnd
                              : l10n.snackChatDuration24Hours,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize:
                                context.rf(12.5).clamp(12, 13.5).toDouble(),
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF667085),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Semantics(
      toggled: value,
      label: title,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 32,
              child: Center(
                child: Icon(
                  icon,
                  color: iconColor,
                  size: context.ri(19).clamp(18, 20).toDouble(),
                ),
              ),
            ),
            SizedBox(width: context.rs(8)),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: context.rf(14.5).clamp(13.5, 15.5).toDouble(),
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1F2937),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 46,
              height: 38,
              child: FittedBox(
                fit: BoxFit.contain,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: const Color(0xFF344054),
                  activeTrackColor: const Color(0xFFD0D5DD),
                  inactiveThumbColor: const Color(0xFF98A2B3),
                  inactiveTrackColor: const Color(0xFFEAECF0),
                  trackOutlineColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final l10n = AppLocalizations.of(context)!;
    return StreamBuilder<SnackChat?>(
      stream: _snackChatService.watchSnackChat(widget.snackChatId),
      builder: (context, snap) {
        final room = snap.data;
        if (room == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text(
                'Snack Chat',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            body: Center(
              child: Text(
                isKo
                    ? '채팅방 정보를 불러올 수 없습니다.'
                    : 'Unable to load chat room information.',
              ),
            ),
          );
        }
        _ensureParticipantsFuture(room);

        final isHost = _uid == room.creatorId;
        final screenWidth = MediaQuery.sizeOf(context).width;
        final pagePadding = screenWidth < 360
            ? 16.0
            : screenWidth < 600
                ? 20.0
                : 24.0;
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            toolbarHeight: context.rh(54, min: 52, max: 58),
            leadingWidth: 48,
            leading: IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: Icon(
                Icons.arrow_back_rounded,
                size: context.ri(22).clamp(21, 24).toDouble(),
              ),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            ),
            titleSpacing: 0,
            title: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Text(
                'Snack Chat',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: context.rf(18).clamp(17, 19).toDouble(),
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827),
                ),
              ),
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: FutureBuilder<List<UserProfile>>(
                future: _participantsFuture,
                builder: (context, usersSnap) {
                  final participants = usersSnap.data ?? const <UserProfile>[];
                  return ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      pagePadding,
                      2,
                      pagePadding,
                      24 + MediaQuery.paddingOf(context).bottom,
                    ),
                    children: [
                      _buildRoomSummary(context, room, l10n),
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      _buildSettingRow(
                        context: context,
                        icon: room.isFavoritedBy(_uid)
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        iconColor: const Color(0xFF667085),
                        title: isKo ? '채팅 즐겨찾기' : 'Favorite this chat',
                        value: room.isFavoritedBy(_uid),
                        onChanged: (_) => _toggleFavorite(room),
                      ),
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      _buildSettingRow(
                        context: context,
                        icon: _isMuted
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_none_rounded,
                        iconColor: const Color(0xFF667085),
                        title: isKo ? '알림' : 'Notifications',
                        value: !_isMuted,
                        onChanged: (_) => _toggleMute(),
                      ),
                      SizedBox(height: context.rs(18).clamp(16, 22).toDouble()),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isKo ? '참여 멤버' : 'MEMBERS',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize:
                                    context.rf(13).clamp(12, 14).toDouble(),
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF667085),
                                letterSpacing: isKo ? 0 : 0.7,
                              ),
                            ),
                          ),
                          if (isHost)
                            SizedBox.square(
                              dimension: 40,
                              child: IconButton(
                                onPressed: _isInviting
                                    ? null
                                    : () => _openInviteSheet(room),
                                padding: EdgeInsets.zero,
                                style: IconButton.styleFrom(
                                  foregroundColor: const Color(0xFF475467),
                                  disabledForegroundColor:
                                      const Color(0xFF98A2B3),
                                ),
                                tooltip: isKo ? '멤버 초대' : 'Invite members',
                                icon: _isInviting
                                    ? const SizedBox.square(
                                        dimension: 17,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        Icons.person_add_alt_1_rounded,
                                        size: context
                                            .ri(19)
                                            .clamp(18, 20)
                                            .toDouble(),
                                        color: const Color(0xFF475467),
                                      ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: context.rs(4)),
                      if (usersSnap.connectionState ==
                              ConnectionState.waiting &&
                          participants.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else if (participants.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            isKo ? '표시할 멤버가 없습니다.' : 'No members to show.',
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 13,
                              color: Color(0xFF98A2B3),
                            ),
                          ),
                        )
                      else
                        ...List.generate(
                          participants.length,
                          (index) => _MemberTile(
                            user: participants[index],
                            showDivider: index < participants.length - 1,
                          ),
                        ),
                      SizedBox(height: context.rs(14)),
                      if (isHost)
                        Text(
                          isKo
                              ? '방장은 채팅방을 나갈 수 없어요.'
                              : 'Host cannot leave this room.',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize:
                                context.rf(12.5).clamp(12, 13.5).toDouble(),
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF98A2B3),
                          ),
                        )
                      else if (_isLeaving)
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _leaveRoom(room),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF667085),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                            ),
                            icon: const Icon(Icons.logout_rounded, size: 17),
                            label: Text(
                              isKo ? '채팅방 나가기' : 'Leave Room',
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MemberTile extends StatelessWidget {
  final UserProfile user;
  final bool showDivider;

  const _MemberTile({
    required this.user,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          button: true,
          label: user.displayNameOrNickname,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FriendProfileScreen(
                    userId: user.uid,
                    nickname: user.displayNameOrNickname,
                    photoURL: user.photoURL,
                    email: user.email,
                    university: user.university,
                    allowNonFriendsPreview: true,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.rs(2),
                  vertical: context.rs(7).clamp(6, 9).toDouble(),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: context.ri(19).clamp(18, 20).toDouble(),
                      backgroundColor: const Color(0xFFE5E7EB),
                      backgroundImage:
                          (user.photoURL != null && user.photoURL!.isNotEmpty)
                              ? NetworkImage(user.photoURL!)
                              : null,
                      child: (user.photoURL == null || user.photoURL!.isEmpty)
                          ? Text(
                              user.displayNameOrNickname.isEmpty
                                  ? '?'
                                  : user.displayNameOrNickname[0].toUpperCase(),
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize:
                                    context.rf(13).clamp(12, 14).toDouble(),
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF475467),
                              ),
                            )
                          : null,
                    ),
                    SizedBox(width: context.rs(10).clamp(8, 11).toDouble()),
                    Expanded(
                      child: Text(
                        user.displayNameOrNickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize:
                              context.rf(14.5).clamp(13.5, 15.5).toDouble(),
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF111827),
                        ),
                      ),
                    ),
                    if (user.nationality != null &&
                        user.nationality!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        CountryFlagHelper.getFlagEmoji(user.nationality!),
                        style: TextStyle(
                          fontSize: context.rf(15).clamp(14, 16).toDouble(),
                          height: 1,
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: const Color(0xFF98A2B3),
                      size: context.ri(18).clamp(17, 19).toDouble(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            indent: 50,
            color: Color(0xFFEAECF0),
          ),
      ],
    );
  }
}
