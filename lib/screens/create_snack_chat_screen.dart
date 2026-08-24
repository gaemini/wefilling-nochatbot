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
import '../utils/responsive_helper.dart';
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
    final initialParticipantIds =
        initialAudienceCategory?.friendIds.where(friendIds.contains).toSet() ??
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
    if (_isSubmitting) return;

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
          foregroundColor: const Color(0xFF111827),
          toolbarHeight: context.rh(56, min: 54, max: 60),
          leadingWidth: 48,
          leading: IconButton(
            iconSize: context.ri(22).clamp(21, 24).toDouble(),
            onPressed: _isSubmitting
                ? null
                : () {
                    if (_stepIndex == 1) {
                      setState(() => _stepIndex = 0);
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          centerTitle: true,
          title: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: Text(
              _stepIndex == 0
                  ? l10n.snackChatInviteStepTitle
                  : l10n.createSnackChat,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(18).clamp(16, 19).toDouble(),
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827),
              ),
            ),
          ),
          actions: [
            if (_stepIndex == 0)
              TextButton(
                onPressed:
                    canContinue ? () => setState(() => _stepIndex = 1) : null,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF344054),
                  disabledForegroundColor: const Color(0xFFCBD5E1),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_selectedParticipantIds.length}',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.next,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              )
            else
              TextButton(
                onPressed: _isSubmitting || !canCreate
                    ? null
                    : () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        _create();
                      },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF111827),
                  disabledForegroundColor: const Color(0xFFCBD5E1),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: _isSubmitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF344054),
                        ),
                      )
                    : Text(
                        l10n.confirm,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 8),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _stepIndex == 0
                      ? _buildInviteStep(key: const ValueKey('invite'))
                      : _buildDetailsStep(key: const ValueKey('details')),
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

    final horizontalPadding = _pageHorizontalPadding(context);

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            12,
            horizontalPadding,
            8,
          ),
          child: SizedBox(
            height: 76,
            child: selected.isEmpty
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      l10n.snackChatNoFriendsSelected,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: selected.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, index) =>
                        _buildFriendSlot(selected[index]),
                  ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            12,
          ),
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: l10n.searchByName,
                hintStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _searchController.clear,
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                filled: true,
                fillColor: const Color(0xFFF4F6F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Text(
            l10n.snackChatFriendList,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: visibleFriends.isEmpty
              ? Center(
                  child: Text(
                    l10n.snackChatNoFriendsToInvite,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      color: Color(0xFF64748B),
                    ),
                  ),
                )
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding - 12,
                    0,
                    horizontalPadding - 12,
                    20,
                  ),
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
    return Semantics(
      button: true,
      selected: selected,
      label: friend.displayNameOrNickname,
      onTap: () => _toggleParticipant(friend.uid),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _toggleParticipant(friend.uid),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                _buildAvatar(
                  size: 44,
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
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.pointColor : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? AppColors.pointColor
                          : const Color(0xFFB8C0CC),
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: Colors.white,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsStep({Key? key}) {
    final l10n = AppLocalizations.of(context)!;
    final horizontalPadding = _pageHorizontalPadding(context);
    return ListView(
      key: key,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        context.rs(20).clamp(16, 24).toDouble(),
        horizontalPadding,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.snackChatRoomTitle,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(15).clamp(14, 16).toDouble(),
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  SizedBox(height: context.rs(2)),
                  TextField(
                    controller: _titleController,
                    maxLength: 40,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_isSubmitting &&
                          _titleController.text.trim().isNotEmpty) {
                        _create();
                      }
                    },
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(15).clamp(14, 16).toDouble(),
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                      color: const Color(0xFF111827),
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.snackChatRoomTitleHint,
                      hintStyle: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(15).clamp(14, 16).toDouble(),
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF98A2B3),
                      ),
                      counterText: '',
                      border: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFFEAECF0)),
                      ),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFFEAECF0)),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Color(0xFF667085),
                          width: 1.4,
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: context.rs(12).clamp(10, 14).toDouble(),
                      ),
                    ),
                  ),
                  SizedBox(height: context.rs(24).clamp(20, 28).toDouble()),
                  Text(
                    l10n.snackChatVisibilityDuration,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(15).clamp(14, 16).toDouble(),
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  SizedBox(height: context.rs(4)),
                  Text(
                    l10n.snackChatVisibilityDurationHint,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(12.5).clamp(12, 13.5).toDouble(),
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                      color: const Color(0xFF667085),
                    ),
                  ),
                  SizedBox(height: context.rs(8).clamp(6, 10).toDouble()),
                  _buildDurationSelector(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDurationSelector() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360 || context.isCompactLayout) {
          return Column(
            children: [
              _buildDurationOption(24),
              _buildDurationOption(0),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: _buildDurationOption(24)),
            SizedBox(width: context.rs(12).clamp(8, 14).toDouble()),
            Expanded(child: _buildDurationOption(0)),
          ],
        );
      },
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
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _activeDurationHours = hours),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: BoxConstraints(
              minHeight: context.rh(48, min: 46, max: 52),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected
                      ? const Color(0xFF344054)
                      : const Color(0xFFEAECF0),
                  width: selected ? 2 : 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hours == 0
                      ? Icons.all_inclusive_rounded
                      : Icons.schedule_rounded,
                  color: selected
                      ? const Color(0xFF344054)
                      : const Color(0xFF98A2B3),
                  size: context.ri(19).clamp(18, 21).toDouble(),
                ),
                SizedBox(width: context.rs(8)),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(14).clamp(13, 15).toDouble(),
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected
                          ? const Color(0xFF111827)
                          : const Color(0xFF475467),
                    ),
                  ),
                ),
                SizedBox(width: context.rs(6)),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: context.ri(20).clamp(19, 22).toDouble(),
                  color: selected
                      ? const Color(0xFF475467)
                      : const Color(0xFFD0D5DD),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFriendSlot(UserProfile friend) {
    return Semantics(
      button: true,
      label: friend.displayNameOrNickname,
      onTap: () => _toggleParticipant(friend.uid),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _toggleParticipant(friend.uid),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _buildAvatar(
                  size: 52,
                  photoUrl: friend.photoURL,
                  fallbackLabel: friend.displayNameOrNickname,
                ),
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.25),
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 62,
              child: Text(
                friend.displayNameOrNickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
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
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      clipBehavior: Clip.antiAlias,
      child: (photoUrl != null && photoUrl.trim().isNotEmpty)
          ? Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  _avatarFallback(fallbackLabel, size),
            )
          : _avatarFallback(fallbackLabel, size),
    );
  }

  Widget _avatarFallback(String label, double avatarSize) {
    return Center(
      child: Text(
        label.isEmpty ? '?' : label[0],
        style: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: avatarSize * 0.34,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF6B7280),
        ),
      ),
    );
  }

  double _pageHorizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360) return 12;
    if (width < 600) return 16;
    return 24;
  }
}
