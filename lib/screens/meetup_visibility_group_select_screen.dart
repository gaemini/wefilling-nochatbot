import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/friend_category.dart';
import '../models/user_profile.dart';
import '../repositories/users_repository.dart';

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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Text(
              m.displayNameOrNickname,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.0,
                color: Color(0xFF374151),
              ),
            ),
          ),
        if (remaining > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Text(
              '+$remaining${l10n.people ?? ''}',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.0,
                color: Color(0xFF1D4ED8),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGroupItem(AppLocalizations l10n, FriendCategory category) {
    final isSelected = _selectedCategoryIds.contains(category.id);

    final bg = isSelected ? AppColors.pointColor.withOpacity(0.10) : Colors.white;
    final border =
        isSelected ? AppColors.pointColor : const Color(0xFFE1E6EE);
    final subColor = isSelected ? const Color(0xFF374151) : const Color(0xFF6B7280);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleSelection(category.id),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: isSelected ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color:
                    isSelected ? AppColors.pointColor : const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.name,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: Color(0xFF111827),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '(${category.friendIds.length}${l10n.people ?? ''})',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  color: subColor,
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E6EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l10n.friends} (${friendCount}${l10n.people ?? ''})',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -0.1,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 12),
          if (_selectedCategoryIds.isEmpty)
            Text(
              l10n.noGroupSelectedWarning,
              style: const TextStyle(
                fontFamily: 'Pretendard',
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
                fontFamily: 'Pretendard',
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
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.selectMeetupGroupsTitle,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.2,
            letterSpacing: -0.2,
            color: Color(0xFF111827),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: const Color(0xFFE6EAF0),
          ),
        ),
      ),
      body: widget.categories.isEmpty
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  l10n.noFriendGroupsYet,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    itemCount: widget.categories.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final category = widget.categories[index];
                      return _buildGroupItem(l10n, category);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: _buildSelectedMembersSection(l10n),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.categories.isEmpty
                  ? null
                  : () {
                      Navigator.of(context).pop(_selectedCategoryIds);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.pointColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                disabledBackgroundColor: const Color(0xFFE5E7EB),
                disabledForegroundColor: const Color(0xFF9CA3AF),
              ),
              child: Text(
                l10n.done,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

