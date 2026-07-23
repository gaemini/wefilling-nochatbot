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
import '../utils/logger.dart';
import 'snack_chat_screen.dart';

class CreateSnackChatScreen extends StatefulWidget {
  final FriendCategory? initialAudienceCategory;

  const CreateSnackChatScreen({
    super.key,
    this.initialAudienceCategory,
  });

  @override
  State<CreateSnackChatScreen> createState() => _CreateSnackChatScreenState();
}

class _CreateSnackChatScreenState extends State<CreateSnackChatScreen> {
  final _titleController = TextEditingController();
  final _searchController = TextEditingController();
  final _friendCategoryService = FriendCategoryService();
  final _usersRepository = UsersRepository();
  final _snackChatService = SnackChatService();
  final _notificationService = NotificationService();

  List<String> _selectedCategoryIds = <String>[];
  List<UserProfile> _candidateFriends = <UserProfile>[];
  Set<String> _selectedParticipantIds = <String>{};
  int _activeDurationHours = 24;
  int _stepIndex = 0;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isSubmitting = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_refreshButtonState);
    _searchController.addListener(() {
      final next = _searchController.text.trim().toLowerCase();
      if (next != _searchQuery && mounted) {
        setState(() => _searchQuery = next);
      }
    });
    _init();
  }

  void _refreshButtonState() {
    if (mounted) setState(() {});
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
    final initialAudienceCategory = widget.initialAudienceCategory;
    final friendIds = friends.map((friend) => friend.uid).toSet();
    final initialParticipantIds = initialAudienceCategory?.friendIds
            .where(friendIds.contains)
            .toSet() ??
        <String>{};
    setState(() {
      _selectedCategoryIds = initialAudienceCategory == null
          ? allCategoryIds
          : <String>[initialAudienceCategory.id];
      _candidateFriends = friends;
      _selectedParticipantIds = initialParticipantIds;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _titleController.removeListener(_refreshButtonState);
    _titleController.dispose();
    _searchController.dispose();
    _friendCategoryService.dispose();
    super.dispose();
  }

  void _toggleParticipant(String uid) {
    final next = Set<String>.from(_selectedParticipantIds);
    if (next.contains(uid)) {
      next.remove(uid);
    } else {
      next.add(uid);
    }
    setState(() {
      _selectedParticipantIds = next;
    });
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
        activeDurationHours: _activeDurationHours,
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
    } catch (error, stackTrace) {
      Logger.error('Snack Chat 생성 실패', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.snackChatCreateFailed)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canContinue = _selectedParticipantIds.isNotEmpty;
    final canCreate = _titleController.text.trim().isNotEmpty;

    return PopScope(
      canPop: _stepIndex == 0 && !_isSubmitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _isSubmitting) return;
        if (_stepIndex == 1) setState(() => _stepIndex = 0);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.white,
          foregroundColor: const Color(0xFF005BAC),
          leading: IconButton(
            onPressed: _isSubmitting
                ? null
                : () {
                    if (_stepIndex == 1) {
                      setState(() => _stepIndex = 0);
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
          ),
          centerTitle: true,
          title: Text(
            _stepIndex == 0
                ? l10n.snackChatInviteStepTitle
                : l10n.createSnackChat,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF005BAC),
            ),
          ),
          actions: [
            if (_stepIndex == 0)
              TextButton(
                onPressed:
                    canContinue ? () => setState(() => _stepIndex = 1) : null,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.pointColor,
                  disabledForegroundColor: const Color(0xFFCBD5E1),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_selectedParticipantIds.length}',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.next,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              )
            else
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(right: 20),
                  child: Text(
                    '2/2',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _stepIndex == 0
                    ? _buildInviteStep(key: const ValueKey('invite'))
                    : _buildDetailsStep(key: const ValueKey('details')),
              ),
        bottomNavigationBar: _stepIndex == 0
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting || !canCreate ? null : _create,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: AppColors.pointColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFE2E8F0),
                        disabledForegroundColor: const Color(0xFF94A3B8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
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
                          : const Icon(Icons.add_rounded, size: 22),
                      label: Text(
                        _isSubmitting
                            ? l10n.snackChatCreating
                            : l10n.snackChatCreate,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildInviteStep({Key? key}) {
    final l10n = AppLocalizations.of(context)!;
    final selected = _selectedParticipants;
    final visibleFriends = _candidateFriends.where((friend) {
      if (_searchQuery.isEmpty) return true;
      return friend.displayNameOrNickname.toLowerCase().contains(_searchQuery);
    }).toList(growable: false);

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
          child: SizedBox(
            height: 92,
            child: selected.isEmpty
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      l10n.snackChatNoFriendsSelected,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: selected.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (_, index) =>
                        _buildFriendSlot(selected[index]),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l10n.searchByName,
              prefixIcon: const Icon(Icons.search_rounded, size: 22),
              filled: true,
              fillColor: const Color(0xFFF4F6F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            l10n.snackChatFriendList,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: visibleFriends.isEmpty
              ? Center(
                  child: Text(
                    l10n.snackChatNoFriendsToInvite,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      color: Color(0xFF64748B),
                    ),
                  ),
                )
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: visibleFriends.length,
                  itemBuilder: (_, index) =>
                      _buildFriendSelectionTile(visibleFriends[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildFriendSelectionTile(UserProfile friend) {
    final selected = _selectedParticipantIds.contains(friend.uid);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleParticipant(friend.uid),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _buildAvatar(
                size: 52,
                photoUrl: friend.photoURL,
                fallbackLabel: friend.displayNameOrNickname,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  friend.displayNameOrNickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: selected ? AppColors.pointColor : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? AppColors.pointColor
                        : const Color(0xFFB8C0CC),
                    width: 1.7,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsStep({Key? key}) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      key: key,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
      children: [
        Text(
          l10n.snackChatDetailsStepTitle,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          l10n.snackChatDetailsStepHint(
            _selectedParticipantIds.length + 1,
          ),
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          l10n.snackChatRoomTitle,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _titleController,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
          decoration: InputDecoration(
            hintText: l10n.snackChatRoomTitleHint,
            counterText: '',
            filled: true,
            fillColor: const Color(0xFFF7F9FC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: AppColors.pointColor,
                width: 1.4,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          l10n.snackChatVisibilityDuration,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          l10n.snackChatVisibilityDurationHint,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _buildDurationOption(24)),
            const SizedBox(width: 12),
            Expanded(child: _buildDurationOption(0)),
          ],
        ),
      ],
    );
  }

  List<UserProfile> get _selectedParticipants => _candidateFriends
      .where((friend) => _selectedParticipantIds.contains(friend.uid))
      .toList();

  Widget _buildDurationOption(int hours) {
    final selected = _activeDurationHours == hours;
    final label = hours == 24
        ? AppLocalizations.of(context)!.snackChatDuration24Hours
        : AppLocalizations.of(context)!.snackChatDurationNoEnd;
    return GestureDetector(
      onTap: () => setState(() => _activeDurationHours = hours),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF3FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.pointColor : const Color(0xFFD1D5DB),
            width: selected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              hours == 0 ? Icons.all_inclusive_rounded : Icons.schedule_rounded,
              color: selected ? AppColors.pointColor : const Color(0xFF9CA3AF),
              size: 21,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color:
                    selected ? AppColors.pointColor : const Color(0xFF111827),
              ),
            ),
          ],
        ),
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

  Widget _buildAvatar({
    required double size,
    required String? photoUrl,
    required String fallbackLabel,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(size * 0.28),
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
}
