import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/friend_category.dart';
import '../models/user_profile.dart';
import '../repositories/users_repository.dart';
import '../services/friend_category_service.dart';
import '../services/snack_chat_service.dart';
import '../ui/widgets/snack_chat_participant_picker.dart';
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
  final _friendCategoryService = FriendCategoryService();
  final _usersRepository = UsersRepository();
  final _snackChatService = SnackChatService();

  List<String> _selectedCategoryIds = <String>[];
  List<UserProfile> _candidateFriends = <UserProfile>[];
  Map<String, UserProfile> _selectedParticipants = <String, UserProfile>{};
  int _activeDurationHours = 24;
  int _stepIndex = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_refreshButtonState);
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
      _selectedParticipants = <String, UserProfile>{
        for (final friend in friends)
          if (initialParticipantIds.contains(friend.uid)) friend.uid: friend,
      };
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _titleController.removeListener(_refreshButtonState);
    _titleController.dispose();
    _friendCategoryService.dispose();
    super.dispose();
  }

  void _toggleParticipant(UserProfile profile) {
    final next = Map<String, UserProfile>.from(_selectedParticipants);
    if (next.containsKey(profile.uid)) {
      next.remove(profile.uid);
    } else {
      next[profile.uid] = profile;
    }
    setState(() => _selectedParticipants = next);
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
    if (_selectedParticipants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.snackChatSelectFriend)),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final id = await _snackChatService.createSnackChat(
        title: title,
        participantIds: _selectedParticipants.keys.toList(),
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
    final canContinue = _selectedParticipants.isNotEmpty;
    final canCreate = _titleController.text.trim().isNotEmpty;
    final pageTitle =
        _stepIndex == 0 ? l10n.snackChatInviteStepTitle : l10n.createSnackChat;

    return PopScope(
      canPop: _stepIndex == 0 && !_isSubmitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _isSubmitting) return;
        if (_stepIndex == 1) setState(() => _stepIndex = 0);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.white,
          foregroundColor: const Color(0xFF111827),
          toolbarHeight: _toolbarHeight,
          automaticallyImplyLeading: false,
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
          flexibleSpace: _buildCenteredTitle(pageTitle),
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
                      '${_selectedParticipants.length}',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(14).clamp(13, 15).toDouble(),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.next,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(14).clamp(13, 15).toDouble(),
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
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(14).clamp(13, 15).toDouble(),
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
    return SnackChatParticipantPicker(
      key: key,
      friends: _candidateFriends,
      selectedProfiles: _selectedParticipants,
      onToggle: _toggleParticipant,
      maxSelectionCount: 49,
    );
  }

  double get _toolbarHeight {
    final base = context.rh(56, min: 54, max: 60);
    final scaledTitle = MediaQuery.textScalerOf(context).scale(
      context.rf(18).clamp(16, 19).toDouble(),
    );
    final accessible = scaledTitle * 1.2 + 24;
    return accessible > base ? accessible.clamp(base, 96).toDouble() : base;
  }

  Widget _buildCenteredTitle(String title) {
    final horizontalClearance =
        MediaQuery.sizeOf(context).width < 360 ? 88.0 : 104.0;
    return SafeArea(
      bottom: false,
      child: IgnorePointer(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalClearance),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(18).clamp(16, 19).toDouble(),
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827),
                ),
              ),
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

  double _pageHorizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360) return 12;
    if (width < 600) return 16;
    return 24;
  }
}
