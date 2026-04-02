import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/snack_chat.dart';
import '../models/user_profile.dart';
import '../repositories/users_repository.dart';
import '../services/notification_service.dart';
import '../services/snack_chat_service.dart';
import '../utils/country_flag_helper.dart';
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
  Future<List<UserProfile>>? _participantsFuture;
  String _participantsSignature = '';
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

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

    final remaining = 6 - room.participantCount;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo ? '참여 인원은 최대 6명입니다.' : 'Maximum participants is 6.',
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
                      padding: EdgeInsets.fromLTRB(20, 14, 20, 10),
                      child: Row(
                        children: [
                          Text(
                            isKo ? '참여자 초대' : 'Invite Participants',
                            style: TextStyle(
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
                              if (selected.length >= remaining) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isKo
                                          ? '최대 $remaining명까지 선택할 수 있습니다.'
                                          : 'You can select up to $remaining people.',
                                    ),
                                  ),
                                );
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
    await _snackChatService.toggleFavorite(room.id, !room.isFavorited);
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
        final sheetIsKo =
            Localizations.localeOf(ctx).languageCode == 'ko';
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

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
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
        return Scaffold(
          backgroundColor: const Color(0xFFF4F6FB),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text(
              'Snack Chat',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          body: FutureBuilder<List<UserProfile>>(
            future: _participantsFuture,
            builder: (context, usersSnap) {
              final participants = usersSnap.data ?? const <UserProfile>[];
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF5FD),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.group,
                              color: AppColors.pointColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                room.title,
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 28 / 2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isKo
                                    ? '${room.participantCount}명 참여'
                                    : '${room.participantCount} Participants',
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.star, color: Color(0xFFF4B400)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isKo ? '채팅 즐겨찾기' : 'Favorite this chat',
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Switch(
                          value: room.isFavorited,
                          onChanged: (_) => _toggleFavorite(room),
                          activeColor: AppColors.pointColor,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isKo ? '접속 중인 멤버' : 'ONLINE MEMBERS',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6B7280),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      if (isHost)
                        IconButton(
                          onPressed:
                              _isInviting ? null : () => _openInviteSheet(room),
                          icon: _isInviting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(
                                  Icons.add_circle,
                                  color: AppColors.pointColor,
                                ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (usersSnap.connectionState == ConnectionState.waiting)
                    const Center(child: CircularProgressIndicator())
                  else
                    ...participants.map((user) => _MemberTile(user: user)),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: isHost
                        ? Text(
                            isKo
                                ? '방장은 채팅방을 나갈 수 없어요'
                                : 'Host cannot leave this room.',
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF9CA3AF),
                            ),
                          )
                        : _isLeaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : TextButton.icon(
                                onPressed: () => _leaveRoom(room),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF6B7280),
                                  backgroundColor: const Color(0xFFF3F4F6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 9),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.logout_rounded,
                                  size: 16,
                                  color: Color(0xFF6B7280),
                                ),
                                label: Text(
                                  isKo ? '채팅방 나가기' : 'Leave Room',
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _MemberTile extends StatelessWidget {
  final UserProfile user;
  const _MemberTile({required this.user});

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
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
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      user.displayNameOrNickname,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (user.nationality != null &&
                      user.nationality!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        CountryFlagHelper.getFlagEmoji(user.nationality!),
                        style: const TextStyle(fontSize: 16, height: 1.0),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chat_bubble_outline,
                color: Color(0xFF98A2B3), size: 18),
          ],
        ),
      ),
    );
  }
}
