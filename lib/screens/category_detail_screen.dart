// lib/screens/category_detail_screen.dart
// 그룹 수정 화면 — 이름은 제목 자리에서 바로 고치고, 멤버와 친구 목록을
// 촘촘하게 보여 준다. 저장·삭제·이동 로직은 기존과 같다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../l10n/group_ui_strings.dart';
import '../l10n/ui_locale.dart';
import '../models/friend_category.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/relationship_provider.dart';
import '../services/friend_category_service.dart';
import '../ui/widgets/friend_picker.dart';
import '../ui/widgets/motion_press.dart';
import '../utils/logger.dart';
import 'create_meetup_screen.dart';
import 'create_post_screen.dart';
import 'create_snack_chat_screen.dart';
import 'create_snapshot_screen.dart';

class CategoryDetailScreen extends StatefulWidget {
  final FriendCategory category;

  /// 새 그룹을 만든 직후처럼, 멤버가 아니어도 목록 위쪽에 먼저 보여 줄 친구들.
  /// 표시 순서에만 쓰고 저장되는 friendIds는 바꾸지 않는다.
  final List<String> prioritizedFriendIds;

  /// 테스트용. 없으면 기본 서비스를 쓴다.
  final FriendCategoryService? categoryService;

  /// 테스트용. 없으면 스낵 만들기 화면을 연다.
  final Widget Function(FriendCategory category)? snapshotScreenBuilder;

  const CategoryDetailScreen({
    Key? key,
    required this.category,
    this.prioritizedFriendIds = const <String>[],
    this.categoryService,
    this.snapshotScreenBuilder,
  }) : super(key: key);

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  late final FriendCategoryService _categoryService =
      widget.categoryService ?? FriendCategoryService();
  late final TextEditingController _nameController;
  final FocusNode _nameFocus = FocusNode();

  bool _isSaving = false;
  bool _isDeleting = false;
  bool _showSaved = false;
  Timer? _savedTimer;

  late String _originalName;
  late final Set<String> _originalFriendIds;
  late Set<String> _selectedFriendIds;

  /// 화면에 들어올 때 한 번 정한 친구 표시 순서(선택을 바꿔도 다시 섞지 않는다).
  List<String>? _frozenOrder;

  /// 처음부터 멤버였던 사람(추가 애니메이션 없이 그린다).
  late final Set<String> _initialMembers;

  @override
  void initState() {
    super.initState();
    _originalName = widget.category.name;
    _nameController = TextEditingController(text: widget.category.name);
    _originalFriendIds = widget.category.friendIds.toSet();
    _initialMembers = Set<String>.from(_originalFriendIds);
    _selectedFriendIds = Set<String>.from(_originalFriendIds);
    _nameFocus.addListener(() {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureFriendsLoaded();
    });
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    _nameController.dispose();
    _nameFocus.dispose();
    if (widget.categoryService == null) _categoryService.dispose();
    super.dispose();
  }

  bool get _nameChanged {
    final trimmed = _nameController.text.trim();
    return trimmed != _originalName;
  }

  bool get _membersChanged =>
      _selectedFriendIds.length != _originalFriendIds.length ||
      !_selectedFriendIds.containsAll(_originalFriendIds);

  bool get _hasChanges => _membersChanged || _nameChanged;

  void _ensureFriendsLoaded() {
    try {
      final authProvider = context.read<AuthProvider>();
      final relationshipProvider = context.read<RelationshipProvider>();
      relationshipProvider.setAuthProvider(authProvider);

      // loadFriends()는 stream 구독만 걸고 즉시 반환될 수 있으므로,
      // 이 화면은 provider를 구독(Consumer)해서 데이터 도착 시 자동 리빌드되도록 한다.
      if (relationshipProvider.friends.isEmpty &&
          !relationshipProvider.isLoading) {
        relationshipProvider.loadFriends();
      }
    } catch (e) {
      Logger.error('❌ 친구 목록 로드 오류: $e');
    }
  }

  /// 처음 친구 목록이 도착했을 때 한 번만 순서를 정한다: 우선 지정 친구,
  /// 이미 멤버인 친구, 나머지 순(각 그룹 안에서는 이름순).
  List<String> _orderFor(List<UserProfile> friends) {
    final existing = _frozenOrder;
    if (existing != null) return existing;
    if (friends.isEmpty) return const <String>[];
    final sorted = List<UserProfile>.from(friends)
      ..sort((a, b) =>
          a.displayNameOrNickname.compareTo(b.displayNameOrNickname));
    final priority = widget.prioritizedFriendIds.toSet();
    int rank(UserProfile f) {
      if (priority.contains(f.uid)) return 0;
      if (_originalFriendIds.contains(f.uid)) return 1;
      return 2;
    }

    final ordered = <String>[];
    for (var tier = 0; tier <= 2; tier++) {
      ordered.addAll(
        sorted.where((f) => rank(f) == tier).map((f) => f.uid),
      );
    }
    _frozenOrder = ordered;
    return ordered;
  }

  List<UserProfile> _orderedFriends(List<UserProfile> friends) {
    final order = _orderFor(friends);
    final byUid = {for (final f in friends) f.uid: f};
    final result = <UserProfile>[
      for (final uid in order)
        if (byUid[uid] != null) byUid[uid]!,
    ];
    // 순서를 정한 뒤에 새로 도착한 친구는 뒤에 붙인다.
    for (final f in friends) {
      if (!order.contains(f.uid)) result.add(f);
    }
    return result;
  }

  Future<void> _save() async {
    if (_isSaving || !_hasChanges) return;
    final strings = GroupUiStrings.of(context);
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.groupNameRequired)),
      );
      return;
    }

    setState(() => _isSaving = true);
    var ok = true;
    var nameFailed = false;
    try {
      if (_membersChanged) {
        final success = await _categoryService.updateCategoryFriendIds(
          categoryId: widget.category.id,
          friendIds: _selectedFriendIds.toList(),
        );
        if (success) {
          _originalFriendIds
            ..clear()
            ..addAll(_selectedFriendIds);
        } else {
          ok = false;
        }
      }
      if (ok && _nameChanged) {
        // 기존 이름 변경 서비스 호출. 색과 아이콘 값은 건드리지 않는다.
        final success = await _categoryService.updateCategory(
          categoryId: widget.category.id,
          name: newName,
        );
        if (success) {
          _originalName = newName;
        } else {
          ok = false;
          nameFailed = true;
        }
      }
    } catch (e) {
      Logger.error('카테고리 저장 오류: $e');
      ok = false;
    }
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (ok) {
      setState(() => _showSaved = true);
      _savedTimer?.cancel();
      _savedTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showSaved = false);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nameFailed
                ? strings.renameFailed
                : AppLocalizations.of(context)!.errorOccurred,
          ),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    }
  }

  void _openCreatePost() {
    final savedCategory = _savedCategory;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreatePostScreen(
          initialAudienceCategory: savedCategory,
          onPostCreated: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  void _openCreateMeetup() {
    final today = DateUtils.dateOnly(DateTime.now());
    final savedCategory = _savedCategory;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreateMeetupScreen(
          initialDayIndex: (today.weekday - 1).clamp(0, 6),
          initialDate: today,
          initialAudienceCategory: savedCategory,
          onCreateMeetup: (_, __) {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  void _openCreateSnackChat() {
    final savedCategory = _savedCategory;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreateSnackChatScreen(
          initialAudienceCategory: savedCategory,
        ),
      ),
    );
  }

  /// 스낵 만들기: 공개 범위를 그룹, 이 카테고리 선택으로 미리 채워 이동한다.
  void _openCreateSnapshot() {
    final savedCategory = _savedCategory;
    final builder = widget.snapshotScreenBuilder;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => builder != null
            ? builder(savedCategory)
            : CreateSnapshotScreen(initialAudienceCategory: savedCategory),
      ),
    );
  }

  FriendCategory get _savedCategory => widget.category.copyWith(
        name: _originalName,
        friendIds: _originalFriendIds.toList(growable: false),
      );

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteCategory),
        content: Text(l10n.deleteCategoryConfirm(_originalName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('group_delete_confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              l10n.delete,
              style: const TextStyle(color: Color(0xFFC62828)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _isDeleting) return;
    _isDeleting = true;
    final bool success;
    try {
      success = await _categoryService.deleteCategory(widget.category.id);
    } finally {
      _isDeleting = false;
    }
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.categoryDeleted)),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.categoryDeleteFailed)),
      );
    }
  }

  TextStyle _style(
    double size,
    FontWeight weight,
    Color color, {
    double? line,
  }) =>
      TextStyle(
        fontFamily: uiFontFamily(context, 'Inter'),
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: size,
        height: line == null ? null : line / size,
        fontWeight: weight,
        color: color,
      );

  @override
  Widget build(BuildContext context) {
    final strings = GroupUiStrings.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Column(
            children: [
              _buildTopBar(strings),
              Expanded(
                child: Consumer<RelationshipProvider>(
                  builder: (context, relationshipProvider, _) =>
                      _buildBody(context, relationshipProvider, strings),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(GroupUiStrings strings) {
    final canSave = _hasChanges && !_isSaving;
    Widget saveChild;
    if (_isSaving) {
      saveChild = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (_showSaved && !_hasChanges) {
      saveChild = Text(
        strings.saved,
        style: _style(14, FontWeight.w600, const Color(0xFF8A8A8A)),
      );
    } else if (canSave) {
      saveChild = Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF2C6BC0),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          strings.save,
          style: _style(14, FontWeight.w600, Colors.white),
        ),
      );
    } else {
      saveChild = Text(
        strings.save,
        style: _style(14, FontWeight.w600, const Color(0xFFB0B0B0)),
      );
    }
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('group_back'),
            iconSize: 22,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: TextField(
              key: const ValueKey('group_name_field'),
              controller: _nameController,
              focusNode: _nameFocus,
              maxLines: 1,
              maxLength: 30,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              cursorColor: const Color(0xFF2C6BC0),
              style: _style(17, FontWeight.w700, Colors.black, line: 22),
              decoration: InputDecoration(
                isCollapsed: true,
                counterText: '',
                hintText: strings.groupNameHint,
                hintStyle: _style(17, FontWeight.w700, const Color(0xFFB0B0B0),
                    line: 22),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF2C6BC0), width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            key: const ValueKey('group_save'),
            behavior: HitTestBehavior.opaque,
            onTap: canSave ? _save : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(widthFactor: 1, child: saveChild),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    RelationshipProvider relationshipProvider,
    GroupUiStrings strings,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final friends = List<UserProfile>.from(relationshipProvider.friends);
    if (relationshipProvider.isLoading && friends.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.pointColor),
      );
    }
    final ordered = _orderedFriends(friends);

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.zero,
      children: [
        _buildShortcuts(strings),
        if (friends.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: Column(
              children: [
                Text(
                  l10n.noFriendsInCategory,
                  textAlign: TextAlign.center,
                  style: _style(15, FontWeight.w600, Colors.black),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.addFriendsToCategory,
                  textAlign: TextAlign.center,
                  style: _style(13, FontWeight.w400, const Color(0xFF707070),
                      line: 19),
                ),
              ],
            ),
          )
        else
          FriendPicker(
            orderedFriends: ordered,
            selectedIds: _selectedFriendIds,
            initialMembers: _initialMembers,
            onToggle: _toggleFriend,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
          child: Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              key: const ValueKey('group_delete'),
              behavior: HitTestBehavior.opaque,
              onTap: _confirmDelete,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    strings.deleteGroup,
                    style: _style(13, FontWeight.w600, const Color(0xFFC62828)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// `이 그룹에게` + 글자 버튼 4개(아이콘 없음).
  Widget _buildShortcuts(GroupUiStrings strings) {
    final items = <(String, VoidCallback)>[
      (strings.shareSnack, _openCreateSnapshot),
      (strings.sharePost, _openCreatePost),
      (strings.shareMeetup, _openCreateMeetup),
      (strings.shareSnackChat, _openCreateSnackChat),
    ];
    // 한 줄: `이 그룹에게` + 글자 버튼 4개. 좁은 화면에서는 가로로 스크롤한다.
    return SizedBox(
      height: 32 + 20,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
        child: Row(
          children: [
            Text(
              strings.toThisGroup,
              style: _style(12, FontWeight.w400, const Color(0xFF8A8A8A)),
            ),
            for (final item in items) ...[
              const SizedBox(width: 8),
              MotionPress(
                pressedScale: .97,
                child: GestureDetector(
                  key: ValueKey<String>('group_share_${item.$1}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: item.$2,
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE3E3E3)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      item.$1,
                      style: _style(13, FontWeight.w500, Colors.black),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _toggleFriend(String uid) {
    setState(() {
      if (_selectedFriendIds.contains(uid)) {
        _selectedFriendIds.remove(uid);
      } else {
        _selectedFriendIds.add(uid);
      }
    });
  }
}
