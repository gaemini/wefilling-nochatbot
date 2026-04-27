import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/friend_category.dart';
import '../models/user_profile.dart';
import '../repositories/users_repository.dart';
import '../services/friend_category_service.dart';
import '../services/notification_service.dart';
import '../services/snack_chat_service.dart';
import 'snack_chat_screen.dart';

class CreateSnackChatScreen extends StatefulWidget {
  const CreateSnackChatScreen({super.key});

  @override
  State<CreateSnackChatScreen> createState() => _CreateSnackChatScreenState();
}

class _CreateSnackChatScreenState extends State<CreateSnackChatScreen> {
  final _titleController = TextEditingController();
  final _friendCategoryService = FriendCategoryService();
  final _usersRepository = UsersRepository();
  final _snackChatService = SnackChatService();
  final _notificationService = NotificationService();

  List<String> _selectedCategoryIds = <String>[];
  List<UserProfile> _candidateFriends = <UserProfile>[];
  Set<String> _selectedParticipantIds = <String>{};
  bool _isLoading = true;
  bool _isSubmitting = false;
  int _retentionHours = 24;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _isLoading = true);

    // 1. 그룹(카테고리) 로드 - 공개 범위 설정용
    final categories = await _friendCategoryService
        .getCategoriesStream()
        .first
        .catchError((_) => <FriendCategory>[]);
    final allCategoryIds = categories.map((e) => e.id).toList();

    // 2. 친구 목록 직접 로드 (friendships 컬렉션 기반, 그룹 유무와 무관)
    List<UserProfile> friends = const <UserProfile>[];
    final uid = _uid;
    if (uid != null) {
      try {
        friends = await _usersRepository.getUserFriends(uid);
        friends.sort(
          (a, b) => a.displayNameOrNickname.compareTo(b.displayNameOrNickname),
        );
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _selectedCategoryIds = allCategoryIds;
      _candidateFriends = friends;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _friendCategoryService.dispose();
    super.dispose();
  }

  void _toggleParticipant(String uid) {
    final l10n = AppLocalizations.of(context)!;
    final next = Set<String>.from(_selectedParticipantIds);
    if (next.contains(uid)) {
      next.remove(uid);
    } else {
      // 본인 포함 총 6명 -> 선택 가능한 친구는 최대 5명
      if (next.length >= 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.snackChatMaxParticipants)),
        );
        return;
      }
      next.add(uid);
    }
    setState(() {
      _selectedParticipantIds = next;
    });
  }

  Future<void> _openInviteBottomSheet() async {
    final l10n = AppLocalizations.of(context)!;
    if (_candidateFriends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.snackChatNoFriendsToInvite)),
      );
      return;
    }

    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        final tempSelection = Set<String>.from(_selectedParticipantIds);
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        Text(
                          l10n.snackChatInviteFriends,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _candidateFriends.length,
                      itemBuilder: (context, index) {
                        final friend = _candidateFriends[index];
                        final selected = tempSelection.contains(friend.uid);
                        return CheckboxListTile(
                          value: selected,
                          activeColor: AppColors.pointColor,
                          title: Text(
                            friend.displayNameOrNickname,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          secondary: _buildAvatar(
                            size: 40,
                            photoUrl: friend.photoURL,
                            fallbackLabel: friend.displayNameOrNickname,
                          ),
                          onChanged: (_) {
                            if (selected) {
                              setModalState(
                                  () => tempSelection.remove(friend.uid));
                              return;
                            }
                            if (tempSelection.length >= 5) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.snackChatMaxParticipants),
                                ),
                              );
                              return;
                            }
                            setModalState(() => tempSelection.add(friend.uid));
                          },
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: AppColors.pointColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          onPressed: () =>
                              Navigator.pop(context, tempSelection),
                          child: Text(
                            l10n.snackChatSelectionComplete(
                                tempSelection.length),
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        _selectedParticipantIds = result;
      });
    }
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context)!;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.snackChatEnterTitle)),
      );
      return;
    }
    if (_selectedParticipantIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.snackChatSelectFriend)),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final id = await _snackChatService.createSnackChat(
        title: title,
        participantIds: _selectedParticipantIds.toList(),
        visibleToCategoryIds: _selectedCategoryIds,
        retentionHours: _retentionHours,
      );
      if (!mounted) return;
      if (id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.snackChatCreateFailed)),
        );
        return;
      }

      // Firestore에서 실제 닉네임 조회 (Firebase Auth displayName은 앱 닉네임과 다를 수 있음)
      String creatorName = '';
      try {
        if (_uid != null) {
          final profile = await _usersRepository.getUserProfile(_uid!);
          creatorName = profile?.nickname?.trim() ?? '';
          if (creatorName.isEmpty) {
            creatorName = profile?.displayNameOrNickname.trim() ?? '';
          }
        }
      } catch (_) {}
      if (creatorName.isEmpty) {
        creatorName =
            FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
      }

      await _notificationService.sendSnackChatInviteNotification(
        participantIds: <String>{
          ..._selectedParticipantIds,
          if (_uid != null) _uid!
        }.toList(),
        snackChatId: id,
        snackChatName: title,
        creatorId: _uid ?? '',
        creatorName: creatorName,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => SnackChatScreen(snackChatId: id)),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        foregroundColor: const Color(0xFF005BAC),
        titleSpacing: 0,
        title: Text(
          l10n.createSnackChat,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 36 / 2,
            fontWeight: FontWeight.w800,
            color: Color(0xFF005BAC),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 140),
              children: [
                Text(
                  l10n.snackChatRoomTitle,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 34 / 2,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F9FC),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: _titleController,
                    maxLength: 40,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 18 / 2 * 1.8,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.snackChatRoomTitleHint,
                      hintStyle: const TextStyle(
                        fontFamily: 'Pretendard',
                        color: Color(0xFFC7CDD7),
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.snackChatSelectParticipants,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 34 / 2,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    Text(
                      '${_selectedParticipantIds.length + 1}/6',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0A66CC),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.snackChatParticipantLimit,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F9FC),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildSelfSlot(),
                        const SizedBox(width: 16),
                        _buildInviteSlot(),
                        ..._selectedParticipants
                            .map(
                              (friend) => Padding(
                                padding: const EdgeInsets.only(left: 16),
                                child: _buildFriendSlot(friend),
                              ),
                            )
                            .toList(),
                        ...List<Widget>.generate(
                          (6 - (_selectedParticipantIds.length + 2))
                              .clamp(0, 4),
                          (_) => const Padding(
                            padding: EdgeInsets.only(left: 16),
                            child: _EmptyParticipantSlot(),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _buildRetentionSelector(),
                const SizedBox(height: 22),
                _buildGuideCard(),
              ],
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _create,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.pointColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add, size: 24),
              label: Text(
                _isSubmitting
                    ? AppLocalizations.of(context)!.snackChatCreating
                    : AppLocalizations.of(context)!.snackChatCreate,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 30 / 2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<UserProfile> get _selectedParticipants => _candidateFriends
      .where((friend) => _selectedParticipantIds.contains(friend.uid))
      .toList();

  Widget _buildSelfSlot() {
    final me = FirebaseAuth.instance.currentUser;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.pointColor, width: 2),
              ),
              child: _buildAvatar(
                size: 60,
                photoUrl: me?.photoURL,
                fallbackLabel: me?.displayName ?? l10n.snackChatMe,
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.pointColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.check, size: 12, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.snackChatMe,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0A66CC),
          ),
        ),
      ],
    );
  }

  Widget _buildInviteSlot() {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      borderRadius: BorderRadius.circular(40),
      onTap: _openInviteBottomSheet,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF9DC6F3),
                width: 2,
                style: BorderStyle.solid,
              ),
              color: const Color(0xFFEFF5FD),
            ),
            child: const Icon(
              Icons.person_add_alt_1_rounded,
              color: Color(0xFF0A66CC),
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.snackChatInvite,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0A66CC),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendSlot(UserProfile friend) {
    return GestureDetector(
      onTap: () => _toggleParticipant(friend.uid),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _buildAvatar(
                size: 64,
                photoUrl: friend.photoURL,
                fallbackLabel: friend.displayNameOrNickname,
              ),
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 70,
            child: Text(
              friend.displayNameOrNickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetentionSelector() {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isKo ? '유지 시간' : 'Retention Period',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isKo
              ? '아무도 이야기하지 않은 시간이 지나면 목록에서 숨겨져요.'
              : 'Chats are hidden after this much inactive time.',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildRetentionOption(24)),
            const SizedBox(width: 10),
            Expanded(child: _buildRetentionOption(48)),
          ],
        ),
      ],
    );
  }

  Widget _buildRetentionOption(int hours) {
    final selected = _retentionHours == hours;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _retentionHours = hours),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 58,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.pointColor.withValues(alpha: 0.12)
              : const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.pointColor : const Color(0xFFE5E7EB),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 20,
              color: selected ? AppColors.pointColor : const Color(0xFF9CA3AF),
            ),
            const SizedBox(width: 8),
            Text(
              isKo ? '$hours시간' : '$hours hours',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color:
                    selected ? AppColors.pointColor : const Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar({
    required double size,
    required String? photoUrl,
    required String fallbackLabel,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFE5E7EB),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: (photoUrl != null && photoUrl.trim().isNotEmpty)
          ? Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _avatarFallback(fallbackLabel),
            )
          : _avatarFallback(fallbackLabel),
    );
  }

  Widget _avatarFallback(String label) {
    return Center(
      child: Text(
        label.isEmpty ? '?' : label[0],
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }

  Widget _buildGuideCard() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FCFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5EEF9)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 18, 20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.snackChatGuideTitle,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 36 / 2,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.snackChatGuideDesc,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 94,
              height: 94,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.campaign_rounded,
                size: 48,
                color: Color(0xFF0A66CC),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyParticipantSlot extends StatelessWidget {
  const _EmptyParticipantSlot();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: Color(0xFFF1F5F9),
          child: Icon(Icons.person, color: Color(0xFFD1D5DB), size: 26),
        ),
        SizedBox(height: 8),
        SizedBox(width: 60),
      ],
    );
  }
}
