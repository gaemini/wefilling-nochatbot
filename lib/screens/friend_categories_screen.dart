// lib/screens/friend_categories_screen.dart
// 친구 카테고리 관리 화면

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/friend_category.dart';
import '../services/friend_category_service.dart';
import '../design/tokens.dart';
import '../ui/widgets/tab_empty_state.dart';
import 'unified_search_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/relationship_provider.dart';
import '../models/user_profile.dart';
import '../l10n/group_ui_strings.dart';
import '../ui/widgets/group_list_row.dart';
import 'category_detail_screen.dart';
import 'create_category_screen.dart';
import 'create_snack_chat_screen.dart';
import 'snack_chat_tab_view.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../l10n/ui_locale.dart';
import '../ui/widgets/motion_press.dart';
import '../ui/widgets/motion_selectable.dart';

/// Stable internal tab mapping used by direct-entry routes.
const int snackChatTabIndex = 0;
const int groupsTabIndex = 1;

class FriendCategoriesScreen extends StatefulWidget {
  final int initialTabIndex;
  const FriendCategoriesScreen({
    super.key,
    this.initialTabIndex = snackChatTabIndex,
  });

  @override
  State<FriendCategoriesScreen> createState() => _FriendCategoriesScreenState();
}

class _FriendCategoriesScreenState extends State<FriendCategoriesScreen>
    with SingleTickerProviderStateMixin {
  final FriendCategoryService _categoryService = FriendCategoryService();
  late VoidCallback _cleanupCallback;
  AuthProvider? _authProvider;
  static const int _maxCategories = FriendCategoryService.maxCategoriesPerUser;
  late TabController _tabController;

  /// 그룹 빈 화면에서 고른 이름 칩(한 번에 하나).
  String? _selectedEmptyName;

  /// 카테고리 스트림 구독 – 마지막 데이터를 state에 보관해
  /// TabBarView 탭 전환 시에도 로딩 스피너 없이 즉시 표시된다.
  StreamSubscription<List<FriendCategory>>? _categoriesSub;
  List<FriendCategory> _categories = [];
  bool _categoriesLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(
        snackChatTabIndex,
        groupsTabIndex,
      ),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _subscribeCategories();
    // 그룹 멤버 표시는 이미 구독 중인 친구 목록만 쓴다(그룹마다 서버 조회 없음).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        unawaited(
          context
              .read<RelationshipProvider>()
              .ensureInitialized()
              .catchError((Object _) {}),
        );
      } catch (_) {}
    });

    // 스트림 정리 콜백 등록
    _cleanupCallback = () {
      _categoryService.dispose();
    };

    // initState에서 listen:false로 읽는 것은 안전하며,
    // post-frame 콜백에서 (이미 dispose된) context를 조회하는 레이스를 제거한다.
    _authProvider = Provider.of<AuthProvider>(context, listen: false);
    _authProvider?.registerStreamCleanup(_cleanupCallback);
  }

  void _subscribeCategories() {
    _categoriesSub?.cancel();
    _categoriesSub = _categoryService.getCategoriesStream().listen(
      (cats) {
        if (mounted) {
          setState(() {
            _categories = cats;
            _categoriesLoading = false;
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _categoriesLoading = false);
      },
    );
  }

  @override
  void dispose() {
    // AuthProvider에서 콜백 제거
    // dispose에서는 context로 ancestor lookup을 하지 않는다.
    _authProvider?.unregisterStreamCleanup(_cleanupCallback);

    _categoriesSub?.cancel();

    // 서비스 정리
    _categoryService.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: BrandColors.surface,
      appBar: AppBar(
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(43),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: TabBar(
              controller: _tabController,
              // 선택 밑줄: 2pt, 폭 44, 검정(파란색을 아낀다).
              indicator: const _FixedWidthUnderline(width: 44, thickness: 2),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: const Color(0xFFEBEBEB),
              dividerHeight: 1,
              labelColor: Colors.black,
              unselectedLabelColor: const Color(0xFF8A8A8A),
              labelStyle: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              tabs: [
                Tab(
                  height: 42,
                  child: MotionPress(
                    pressedScale: MotionSelectable.segmentScale,
                    child: Semantics(
                      label: l10n.snackChatTabSemantic,
                      selected: _tabController.index == snackChatTabIndex,
                      button: true,
                      excludeSemantics: true,
                      child: Text(l10n.snackChat),
                    ),
                  ),
                ),
                Tab(
                  height: 42,
                  child: MotionPress(
                    pressedScale: MotionSelectable.segmentScale,
                    child: Semantics(
                      label: l10n.groupsTabSemantic,
                      selected: _tabController.index == groupsTabIndex,
                      button: true,
                      excludeSemantics: true,
                      child: Text(l10n.groups),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SizedBox(
              width: double.infinity,
              child: TabBarView(
                controller: _tabController,
                children: [
                  SnackChatTabView(
                    onCreateSnackChat: _openCreateSnackChat,
                  ),
                  _buildGroupsTab(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openCreateSnackChat() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateSnackChatScreen()),
    );
  }

  void _handleCreateCategory({String? initialName}) {
    if (_categories.length >= _maxCategories) {
      _showCategoryLimitReachedSnackBar();
      return;
    }
    _showCreateCategoryDialog(initialName: initialName);
  }

  Widget _buildGroupsTab() {
    // 최초 로드 중일 때만 스피너 표시 (탭 전환 시에는 기존 데이터 즉시 사용)
    if (_categoriesLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_categories.isEmpty) {
      return _buildGroupsEmptyState();
    }

    final strings = GroupUiStrings.of(context);
    final ready = context.select<RelationshipProvider, bool>(
      (provider) => provider.relationshipStreamsReady,
    );
    final profiles = context.select<RelationshipProvider, List<UserProfile>>(
      (provider) => provider.friends,
    );
    final List<GroupMember>? friends = ready
        ? [
            for (final profile in profiles)
              GroupMember(
                uid: profile.uid,
                name: profile.displayNameOrNickname,
                photoUrl: profile.photoURL ?? '',
              ),
          ]
        : null;
    final ungrouped = ungroupedFriendsOf(_categories, friends);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              strings.groupsIntro,
              key: const ValueKey('groups_intro'),
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 12,
                height: 17 / 12,
                color: const Color(0xFF8A8A8A),
              ),
            ),
          ),
          for (final category in _categories)
            GroupListRow(
              key: ValueKey('friend-category-${category.id}'),
              category: category,
              members: groupMembersFor(category, friends),
              onTap: () => _navigateToCategoryDetail(category),
              // 이름 변경·삭제는 수정 화면에서 하고, 길게 누르면 기존 메뉴를 띄운다.
              onLongPress: () => _showGroupMenu(category),
            ),
          if (ungrouped != null && ungrouped.isNotEmpty)
            GroupUngroupedRow(
              key: const ValueKey('groups_ungrouped_row'),
              friends: ungrouped,
              onTap: () => _handleCreateFromUngrouped(ungrouped),
            ),
          _buildCreateCategoryRow(strings),
        ],
      ),
    );
  }

  Widget _buildCreateCategoryRow(GroupUiStrings strings) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: InkWell(
        key: const ValueKey('groups_create_row'),
        onTap: _handleCreateCategory,
        child: Container(
          height: 52,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            strings.newGroup,
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2C6BC0),
            ),
          ),
        ),
      ),
    );
  }

  /// 길게 누르기: 기존 이름 변경 / 삭제 메뉴.
  Future<void> _showGroupMenu(FriendCategory category) async {
    final l10n = AppLocalizations.of(context)!;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in <(String, String, Color)>[
                ('edit', l10n.editAction ?? '', Colors.black),
                ('delete', l10n.delete, const Color(0xFFC62828)),
              ])
                InkWell(
                  key: ValueKey<String>('group_menu_${entry.$1}'),
                  onTap: () => Navigator.pop(sheetContext, entry.$1),
                  child: Container(
                    height: 56,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      entry.$2,
                      style: TextStyle(
                        fontFamily: uiFontFamily(sheetContext, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: entry.$3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      _showEditCategoryDialog(category);
    } else if (action == 'delete') {
      _showDeleteConfirmDialog(category);
    }
  }

  /// 그룹에 없는 친구 줄: 새 그룹 만들기 흐름을 열고, 만든 뒤 이 친구들을
  /// 목록 위쪽에 둔 채 수정 화면으로 이어 간다(저장된 friendIds는 바꾸지 않는다).
  Future<void> _handleCreateFromUngrouped(List<GroupMember> friends) async {
    if (_categories.length >= _maxCategories) {
      _showCategoryLimitReachedSnackBar();
      return;
    }
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => const CreateCategoryScreen()),
    );
    if (!mounted || result == null) return;
    final newId = await _categoryService.createCategory(
      name: result['name'] as String,
      description: '',
      color: result['color'] as String,
      iconName: result['iconName'] as String,
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    if (newId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.categoryCreateFailed)),
      );
      return;
    }
    final created = FriendCategory(
      id: newId,
      name: result['name'] as String,
      description: '',
      color: result['color'] as String,
      iconName: result['iconName'] as String,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      userId: '',
      friendIds: const <String>[],
    );
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => CategoryDetailScreen(
          category: created,
          prioritizedFriendIds:
              friends.map((friend) => friend.uid).toList(growable: false),
        ),
      ),
    );
  }

  Widget _buildGroupsEmptyState() {
    final strings = GroupUiStrings.of(context);
    final ready = context.select<RelationshipProvider, bool>(
      (provider) => provider.relationshipStreamsReady,
    );
    final profiles = context.select<RelationshipProvider, List<UserProfile>>(
      (provider) => provider.friends,
    );
    final friendCount = ready ? profiles.length : null;
    final noFriends = ready && profiles.isEmpty;
    final List<GroupMember>? faces = ready
        ? [
            for (final profile in profiles.take(6))
              GroupMember(
                uid: profile.uid,
                name: profile.displayNameOrNickname,
                photoUrl: profile.photoURL ?? '',
              ),
          ]
        : null;
    final chips = strings.groupNameChips;
    final selected = _selectedEmptyName;

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
                                    members: faces,
                                    avatarSize: 36,
                                    overlap: 9,
                                    maxShown: 6,
                                    borderWidth: 2.5,
                                    reserveOverflowSlot: false,
                                    placeholderCount: 6,
                                  ),
                                  if (friendCount != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      strings.friendsCount(friendCount),
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
                                      () => _selectedEmptyName =
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
                              ? _openFriendSearch
                              : () => _handleCreateCategory(
                                    initialName: selected,
                                  ),
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

  void _openFriendSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const UnifiedSearchScreen(initialTabIndex: 0),
      ),
    );
  }

  void _showCreateCategoryDialog({String? initialName}) {
    _navigateToCreateCategory(initialName: initialName);
  }

  void _showEditCategoryDialog(FriendCategory category) {
    _navigateToEditCategory(category);
  }

  Future<void> _navigateToCreateCategory({String? initialName}) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCategoryScreen(initialName: initialName),
      ),
    );

    if (!mounted || result == null) return;

    final success = await _categoryService.createCategory(
      name: result['name'] as String,
      description: '',
      color: result['color'] as String,
      iconName: result['iconName'] as String,
    );

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success != null ? l10n.categoryCreated : l10n.categoryCreateFailed,
        ),
      ),
    );
  }

  Future<void> _navigateToEditCategory(FriendCategory category) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCategoryScreen(category: category),
      ),
    );

    if (!mounted || result == null) return;

    final success = await _categoryService.updateCategory(
      categoryId: category.id,
      name: result['name'] as String,
      description: '',
      color: result['color'] as String,
      iconName: result['iconName'] as String,
    );

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (l10n.categoryUpdated ?? "")
              : (l10n.categoryUpdateFailed ?? ""),
        ),
      ),
    );
  }

  void _showCategoryLimitReachedSnackBar() {
    if (!mounted) return;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          (isChineseUi(context) ? '最多可创建10个分组。' : isKo ? '그룹은 최대 10개까지 생성할 수 있어요.' : 'You can create up to 10 groups.'),
        ),
      ),
    );
  }

  void _showDeleteConfirmDialog(FriendCategory category) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final messageParts =
        l10n.deleteCategoryConfirm(category.name).split('\n\n');
    final question = messageParts.first;
    final supportingMessage = messageParts.skip(1).join('\n\n');

    showDialog<void>(
      context: context,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      builder: (dialogContext) {
        final media = MediaQuery.of(dialogContext);
        final compact = media.size.width < 360;

        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.25,
          child: SafeArea(
            minimum: const EdgeInsets.symmetric(vertical: 16),
            child: Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 0,
              insetPadding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 20,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(compact ? 20 : 24),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 18 : 24,
                    compact ? 20 : 26,
                    compact ? 18 : 24,
                    compact ? 14 : 18,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.deleteCategory,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: compact ? 19 : 20,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                          height: isChineseUi(context) ? 1.3 : 1.2,
                          letterSpacing: -0.3,
                        ),
                      ),
                      SizedBox(height: compact ? 16 : 20),
                      Text(
                        question,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: compact ? 14 : 15,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF344054),
                          height: 1.45,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (supportingMessage.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          supportingMessage,
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: compact ? 12.5 : 13.5,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF667085),
                            height: 1.45,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                      SizedBox(height: compact ? 20 : 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF667085),
                                minimumSize: const Size(0, 44),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              child: Text(
                                l10n.cancel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: uiFontFamily(context, 'Inter'),
                                  fontFamilyFallback: ['NotoSansKR'],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: BrandColors.error,
                                minimumSize: const Size(0, 44),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () async {
                                final success = await _categoryService
                                    .deleteCategory(category.id);
                                if (!dialogContext.mounted) return;
                                Navigator.pop(dialogContext);
                                if (!mounted) return;

                                if (success) {
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    SnackBar(
                                        content: Text(l10n.categoryDeleted)),
                                  );
                                } else {
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(l10n.categoryDeleteFailed),
                                    ),
                                  );
                                }
                              },
                              child: Text(
                                l10n.delete,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: uiFontFamily(context, 'Inter'),
                                  fontFamilyFallback: ['NotoSansKR'],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _navigateToCategoryDetail(FriendCategory category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoryDetailScreen(category: category),
      ),
    );
  }

  Future<void> _createDefaultCategoriesIfNeeded() async {
    try {
      final success = await _categoryService.createDefaultCategories();
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.defaultCategoryCreated ?? ""),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('기본 카테고리 생성 UI 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context)!.defaultCategoryFailed ?? ""),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
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

/// 탭 선택 밑줄: 탭 가운데에 고정 폭으로 그린다.
class _FixedWidthUnderline extends Decoration {
  const _FixedWidthUnderline({required this.width, required this.thickness});

  final double width;
  final double thickness;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _FixedWidthUnderlinePainter(width, thickness);
}

class _FixedWidthUnderlinePainter extends BoxPainter {
  _FixedWidthUnderlinePainter(this.width, this.thickness);

  final double width;
  final double thickness;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final left = offset.dx + (size.width - width) / 2;
    final top = offset.dy + size.height - thickness;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width, thickness),
        Radius.circular(thickness / 2),
      ),
      Paint()..color = Colors.black,
    );
  }
}
