import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/friend_category.dart';
import '../models/user_profile.dart';
import '../repositories/users_repository.dart';
import '../utils/responsive_helper.dart';

class MeetupVisibilityGroupSelectScreen extends StatefulWidget {
  final List<FriendCategory> categories;
  final List<String> initialSelectedCategoryIds;

  const MeetupVisibilityGroupSelectScreen({
    super.key,
    required this.categories,
    required this.initialSelectedCategoryIds,
  });

  @override
  State<MeetupVisibilityGroupSelectScreen> createState() =>
      _MeetupVisibilityGroupSelectScreenState();
}

class _MeetupVisibilityGroupSelectScreenState
    extends State<MeetupVisibilityGroupSelectScreen> {
  late List<String> _selectedCategoryIds;

  final UsersRepository _usersRepository = UsersRepository();
  List<UserProfile> _selectedMembers = [];
  bool _isLoadingSelectedMembers = false;
  int _membersLoadSeq = 0;

  @override
  void initState() {
    super.initState();
    _selectedCategoryIds = List<String>.from(widget.initialSelectedCategoryIds);
    // 초기 선택이 있다면 포함 친구 목록을 미리 로드
    if (_selectedCategoryIds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshSelectedMembers();
      });
    }
  }

  void _toggleSelection(String categoryId) {
    final next = List<String>.from(_selectedCategoryIds);
    if (next.contains(categoryId)) {
      next.remove(categoryId);
    } else {
      next.add(categoryId);
    }
    setState(() {
      _selectedCategoryIds = next;
    });
    _refreshSelectedMembers();
  }

  Set<String> _selectedFriendIds() {
    final selectedSet = _selectedCategoryIds.toSet();
    final ids = <String>{};
    for (final c in widget.categories) {
      if (!selectedSet.contains(c.id)) continue;
      ids.addAll(c.friendIds);
    }
    return ids;
  }

  Future<void> _refreshSelectedMembers() async {
    final currentSeq = ++_membersLoadSeq;
    final friendIds = _selectedFriendIds().toList();

    if (friendIds.isEmpty) {
      if (!mounted) return;
      setState(() {
        _selectedMembers = [];
        _isLoadingSelectedMembers = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoadingSelectedMembers = true;
    });

    final profiles = await _usersRepository.getUserProfilesBatch(friendIds);
    profiles.sort(
      (a, b) => a.displayNameOrNickname.compareTo(b.displayNameOrNickname),
    );

    if (!mounted) return;
    if (currentSeq != _membersLoadSeq) return; // 가장 최신 요청만 반영

    setState(() {
      _selectedMembers = profiles;
      _isLoadingSelectedMembers = false;
    });
  }

  Widget _buildMemberChips(AppLocalizations l10n, List<UserProfile> members) {
    // 너무 길어지지 않도록 UI에서 일부만 보여주고 나머지는 요약
    const maxVisible = 18;
    final visible = members.take(maxVisible).toList();
    final remaining = members.length - visible.length;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in visible)
          Text(
            m.displayNameOrNickname,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: context.rf(13).clamp(12, 14).toDouble(),
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: const Color(0xFF475467),
            ),
          ),
        if (remaining > 0)
          Text(
            '+$remaining${l10n.people ?? ''}',
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: context.rf(13).clamp(12, 14).toDouble(),
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: const Color(0xFF344054),
            ),
          ),
      ],
    );
  }

  Widget _buildGroupItem(AppLocalizations l10n, FriendCategory category) {
    final isSelected = _selectedCategoryIds.contains(category.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleSelection(category.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 11),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFEAECF0)),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: context.ri(21).clamp(20, 23).toDouble(),
                color: isSelected
                    ? const Color(0xFF475467)
                    : const Color(0xFFD0D5DD),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.name,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: context.rf(14).clamp(13, 15).toDouble(),
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    height: 1.2,
                    color: const Color(0xFF111827),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '(${category.friendIds.length}${l10n.people ?? ''})',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(12).clamp(11, 13).toDouble(),
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  color: const Color(0xFF667085),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedMembersSection(AppLocalizations l10n) {
    final friendCount = _selectedFriendIds().length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l10n.friends} (${friendCount}${l10n.people ?? ''})',
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: context.rf(14).clamp(13, 15).toDouble(),
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -0.1,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 10),
          if (_selectedCategoryIds.isEmpty)
            Text(
              l10n.noGroupSelectedWarning,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.25,
                color: Color(0xFF6B7280),
              ),
            )
          else if (_isLoadingSelectedMembers)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_selectedMembers.isEmpty)
            Text(
              l10n.noFriendsYet,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.25,
                color: Color(0xFF6B7280),
              ),
            )
          else
            _buildMemberChips(l10n, _selectedMembers),
        ],
      ),
    );
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
        centerTitle: true,
        toolbarHeight: context.rh(56, min: 54, max: 60),
        leadingWidth: 48,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: const Color(0xFF111827),
            size: context.ri(22).clamp(21, 24).toDouble(),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Text(
            l10n.selectMeetupGroupsTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: context.rf(18).clamp(16, 19).toDouble(),
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -0.2,
              color: const Color(0xFF111827),
            ),
          ),
        ),
      ),
      body: widget.categories.isEmpty
          ? SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).width < 360 ? 12 : 16,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      l10n.noFriendGroupsYet,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(14).clamp(13, 15).toDouble(),
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                        color: const Color(0xFF667085),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width < 360 ? 12 : 16,
                8,
                MediaQuery.sizeOf(context).width < 360 ? 12 : 16,
                12,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: widget.categories.length + 1,
              itemBuilder: (context, index) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: index < widget.categories.length
                        ? _buildGroupItem(l10n, widget.categories[index])
                        : _buildSelectedMembersSection(l10n),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 360 ? 12 : 16,
            8,
            MediaQuery.sizeOf(context).width < 360 ? 12 : 16,
            10,
          ),
          // bottomNavigationBar의 loose constraint에서 Center가 남은 높이를
          // 모두 차지하지 않도록 콘텐츠 높이로 축소한다.
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SizedBox(
                height: context.rh(48, min: 44, max: 50),
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.categories.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).pop(_selectedCategoryIds);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF344054),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                    disabledBackgroundColor: const Color(0xFFE5E7EB),
                    disabledForegroundColor: const Color(0xFF9CA3AF),
                  ),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.2,
                    child: Text(
                      l10n.done,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(15).clamp(14, 16).toDouble(),
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
