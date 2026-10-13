// lib/screens/new_group_screen.dart
// 새 그룹 만들기: 이름과 멤버를 한 화면에서 정하고 바로 만든다.
// 색상·도형은 고르지 않고 기본값으로 저장한다. 성공하면 만든 그룹 id를 돌려준다.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../l10n/group_ui_strings.dart';
import '../l10n/ui_locale.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/relationship_provider.dart';
import '../services/friend_category_service.dart';
import '../ui/widgets/friend_picker.dart';
import '../ui/widgets/motion_press.dart';
import '../utils/logger.dart';
import 'unified_search_screen.dart';

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({
    super.key,
    this.initialName,
    this.prioritizedFriendIds = const <String>[],
    this.existingNames = const <String>[],
    this.categoryService,
  });

  /// 빈 화면에서 이름 칩을 골라 들어온 경우의 미리 채울 이름.
  final String? initialName;

  /// 목록 위쪽에 모아 보여 줄 친구(선택하지는 않는다).
  final List<String> prioritizedFriendIds;

  /// 이미 있는 그룹 이름(같은 이름 안내와 최대 개수 판단에 쓴다).
  final List<String> existingNames;

  final FriendCategoryService? categoryService;

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  static const int _maxName = 20;
  static const String _defaultIcon = 'shape_circle';

  late final FriendCategoryService _service =
      widget.categoryService ?? FriendCategoryService();
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final Set<String> _selected = <String>{};
  int? _chipIndex;
  bool _saving = false;
  List<String>? _frozenOrder;

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialName ?? '').trim();
    if (initial.isNotEmpty) {
      _nameController.text =
          initial.length > _maxName ? initial.substring(0, _maxName) : initial;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final chips = GroupUiStrings.of(context).newGroupNameChips;
      final index = chips.indexOf(_nameController.text.trim());
      if (index >= 0) setState(() => _chipIndex = index);
      try {
        final auth = context.read<AuthProvider>();
        final relationship = context.read<RelationshipProvider>();
        relationship.setAuthProvider(auth);
        if (relationship.friends.isEmpty && !relationship.isLoading) {
          relationship.loadFriends();
        }
      } catch (e) {
        Logger.error('친구 목록 로드 오류: $e');
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    if (widget.categoryService == null) _service.dispose();
    super.dispose();
  }

  String get _name => _nameController.text.trim();
  bool get _dirty => _name.isNotEmpty || _selected.isNotEmpty;
  bool get _canCreate => _name.isNotEmpty && _selected.isNotEmpty && !_saving;
  bool get _isDuplicate {
    final lower = _name.toLowerCase();
    return lower.isNotEmpty &&
        widget.existingNames.any((n) => n.trim().toLowerCase() == lower);
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

  /// 친구가 처음 도착했을 때 한 번만 순서를 정한다: 지정 친구 먼저, 나머지는 원래 순서.
  List<UserProfile> _ordered(List<UserProfile> friends) {
    if (_frozenOrder == null && friends.isNotEmpty) {
      final priority = widget.prioritizedFriendIds.toSet();
      _frozenOrder = [
        for (final f in friends)
          if (priority.contains(f.uid)) f.uid,
        for (final f in friends)
          if (!priority.contains(f.uid)) f.uid,
      ];
    }
    final order = _frozenOrder ?? const <String>[];
    final byUid = {for (final f in friends) f.uid: f};
    final result = <UserProfile>[
      for (final uid in order)
        if (byUid[uid] != null) byUid[uid]!,
    ];
    for (final f in friends) {
      if (!order.contains(f.uid)) result.add(f);
    }
    return result;
  }

  void _toggle(String uid) {
    setState(() {
      if (!_selected.remove(uid)) _selected.add(uid);
    });
  }

  void _onChip(int index, String label) {
    setState(() {
      if (_chipIndex == index) {
        _chipIndex = null;
        _nameController.clear();
      } else {
        _chipIndex = index;
        _nameController.text = label;
        _nameController.selection =
            TextSelection.collapsed(offset: label.length);
      }
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty || _saving) return true;
    final strings = GroupUiStrings.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.discardNewGroupTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.keepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.discard),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _close() async {
    if (await _confirmDiscard() && mounted) Navigator.pop(context);
  }

  Future<void> _create() async {
    if (!_canCreate) return;
    final l10n = AppLocalizations.of(context)!;
    final strings = GroupUiStrings.of(context);
    setState(() => _saving = true);
    String? id;
    try {
      id = await _service.createCategory(
        name: _name,
        description: '',
        color:
            '#${AppColors.pointColor.toARGB32().toRadixString(16).substring(2)}',
        iconName: _defaultIcon,
        initialFriendIds: _selected.toList(),
      );
    } catch (e) {
      Logger.error('새 그룹 만들기 오류: $e');
    }
    if (!mounted) return;
    if (id == null) {
      // 입력은 그대로 두고 화면을 유지한다.
      setState(() => _saving = false);
      final limit = widget.existingNames.length >=
          FriendCategoryService.maxCategoriesPerUser;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(limit ? strings.groupLimitReached : l10n.categoryCreateFailed),
        ),
      );
      return;
    }
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final strings = GroupUiStrings.of(context);
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) Navigator.pop(context);
      },
      child: Scaffold(
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
                    builder: (context, provider, _) =>
                        _buildBody(provider, strings),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(GroupUiStrings strings) {
    final Widget action;
    if (_saving) {
      action = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (_canCreate) {
      action = Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF2C6BC0),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          strings.createWithCount(_selected.length),
          key: const ValueKey('new_group_create_label'),
          style: _style(14, FontWeight.w600, Colors.white),
        ),
      );
    } else {
      action = Text(
        strings.create,
        key: const ValueKey('new_group_create_label'),
        style: _style(14, FontWeight.w600, const Color(0xFFB0B0B0)),
      );
    }
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('new_group_close'),
            iconSize: 22,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.close_rounded, color: Colors.black),
            onPressed: _close,
          ),
          Expanded(
            child: Text(
              strings.newGroupTitle,
              textAlign: TextAlign.center,
              style: _style(16, FontWeight.w600, Colors.black),
            ),
          ),
          GestureDetector(
            key: const ValueKey('new_group_create'),
            behavior: HitTestBehavior.opaque,
            onTap: _canCreate ? _create : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.only(left: 6, right: 12),
                child: Center(widthFactor: 1, child: action),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(RelationshipProvider provider, GroupUiStrings strings) {
    final friends = List<UserProfile>.from(provider.friends);
    final loadingFriends = provider.isLoading && friends.isEmpty;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.zero,
      children: [
        _buildNameField(strings),
        _buildChips(strings),
        if (loadingFriends)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.pointColor),
            ),
          )
        else if (friends.isEmpty)
          _buildNoFriends(strings)
        else
          FriendPicker(
            orderedFriends: _ordered(friends),
            selectedIds: _selected,
            onToggle: _toggle,
          ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildNameField(GroupUiStrings strings) {
    final has = _name.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('new_group_name'),
                  controller: _nameController,
                  focusNode: _nameFocus,
                  autofocus: true,
                  maxLines: 1,
                  maxLength: _maxName,
                  textInputAction: TextInputAction.done,
                  cursorColor: const Color(0xFF2C6BC0),
                  style: _style(20, FontWeight.w700, Colors.black, line: 28),
                  onChanged: (value) => setState(() {
                    // 직접 고치면 칩 선택은 풀린다.
                    final chips = strings.newGroupNameChips;
                    if (_chipIndex != null &&
                        value.trim() != chips[_chipIndex!]) {
                      _chipIndex = null;
                    }
                  }),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    counterText: '',
                    hintText: strings.groupNameHint,
                    hintStyle: _style(
                        20, FontWeight.w700, const Color(0xFFC0C0C0),
                        line: 28),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_nameController.text.characters.length}/$_maxName',
                key: const ValueKey('new_group_counter'),
                style: _style(11, FontWeight.w400, const Color(0xFFB0B0B0)),
              ),
            ],
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 1.5,
            color: has ? const Color(0xFF2C6BC0) : const Color(0xFFEBEBEB),
          ),
          if (_isDuplicate)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                strings.duplicateGroupName,
                key: const ValueKey('new_group_duplicate'),
                style: _style(12, FontWeight.w400, const Color(0xFF8A8A8A)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChips(GroupUiStrings strings) {
    final chips = strings.newGroupNameChips;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < chips.length; i++)
            MotionPress(
              pressedScale: .97,
              child: GestureDetector(
                key: ValueKey<String>('new_group_chip_$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _onChip(i, chips[i]),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _chipIndex == i ? Colors.black : Colors.white,
                    border: Border.all(
                      color: _chipIndex == i
                          ? Colors.black
                          : const Color(0xFFE3E3E3),
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    chips[i],
                    style: _style(
                      13,
                      FontWeight.w500,
                      _chipIndex == i ? Colors.white : const Color(0xFF333333),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNoFriends(GroupUiStrings strings) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        children: [
          Text(
            strings.groupsNoFriends,
            key: const ValueKey('new_group_no_friends'),
            textAlign: TextAlign.center,
            style: _style(13, FontWeight.w400, const Color(0xFF707070),
                line: 19),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            key: const ValueKey('new_group_find_friends'),
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const UnifiedSearchScreen(initialTabIndex: 0),
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                widthFactor: 1,
                child: Text(
                  strings.findFriendsButton,
                  style: _style(14, FontWeight.w600, const Color(0xFF2C6BC0)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
