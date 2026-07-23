// lib/screens/category_detail_screen.dart
// 카테고리 상세 화면 - 전체 친구 목록에서 그룹 포함 여부를 편집 후 저장

import 'package:flutter/material.dart';
import '../models/friend_category.dart';
import '../models/user_profile.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../constants/app_constants.dart';
import 'package:provider/provider.dart';
import '../providers/relationship_provider.dart';
import '../providers/auth_provider.dart';
import '../services/friend_category_service.dart';
import '../ui/widgets/shape_icon.dart';
import 'create_meetup_screen.dart';
import 'create_post_screen.dart';
import 'create_snack_chat_screen.dart';

class CategoryDetailScreen extends StatefulWidget {
  final FriendCategory category;

  const CategoryDetailScreen({
    Key? key,
    required this.category,
  }) : super(key: key);

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  final FriendCategoryService _categoryService = FriendCategoryService();
  final TextEditingController _searchController = TextEditingController();

  bool _isSaving = false;

  String _searchQuery = '';

  late final Set<String> _originalFriendIds;
  late Set<String> _selectedFriendIds;

  @override
  void initState() {
    super.initState();
    _originalFriendIds = widget.category.friendIds.toSet();
    _selectedFriendIds = Set<String>.from(_originalFriendIds);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureFriendsLoaded();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categoryService.dispose();
    super.dispose();
  }

  bool get _hasChanges =>
      _selectedFriendIds.length != _originalFriendIds.length ||
      !_selectedFriendIds.containsAll(_originalFriendIds);

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

  List<UserProfile> _computeFilteredFriends(List<UserProfile> friends) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return friends;
    return friends.where((f) {
      final dn = f.displayNameOrNickname.toLowerCase();
      final nickname = (f.nickname ?? '').toLowerCase();
      return dn.contains(q) || nickname.contains(q);
    }).toList();
  }

  Future<void> _save() async {
    if (_isSaving || !_hasChanges) return;

    try {
      setState(() {
        _isSaving = true;
      });

      final success = await _categoryService.updateCategoryFriendIds(
        categoryId: widget.category.id,
        friendIds: _selectedFriendIds.toList(),
      );

      if (!mounted) return;

      if (success) {
        _originalFriendIds
          ..clear()
          ..addAll(_selectedFriendIds);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.save)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.errorOccurred),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    } catch (e) {
      Logger.error('카테고리 저장 오류: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.errorOccurred),
          backgroundColor: BrandColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
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

  FriendCategory get _savedCategory => widget.category.copyWith(
        friendIds: _originalFriendIds.toList(growable: false),
      );

  @override
  Widget build(BuildContext context) {
    // 색상 안전하게 파싱 (null 체크 포함)
    final color = _parseColor(widget.category.color ?? '#6366F1');
    final iconName = widget.category.iconName ?? 'group';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 배경/테두리 없이 도형 아이콘만 표시
            ShapeIcon(iconName: iconName, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.category.name,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: Color(0xFF111827),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: (_hasChanges && !_isSaving) ? _save : null,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    AppLocalizations.of(context)!.save,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w700,
                      color: (_hasChanges && !_isSaving)
                          ? AppColors.pointColor
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCreateShortcuts(),
          Expanded(
            child: Consumer<RelationshipProvider>(
              builder: (context, relationshipProvider, _) {
                final friends =
                    List<UserProfile>.from(relationshipProvider.friends);
                final filteredFriends = _computeFilteredFriends(friends);
                final displayFriends = List<UserProfile>.from(filteredFriends)
                  ..sort(
                    (a, b) => a.displayNameOrNickname.compareTo(
                      b.displayNameOrNickname,
                    ),
                  );
                final allSortedFriends = List<UserProfile>.from(friends)
                  ..sort(
                    (a, b) => a.displayNameOrNickname.compareTo(
                      b.displayNameOrNickname,
                    ),
                  );
                final selectedFriends = allSortedFriends
                    .where(
                      (friend) => _selectedFriendIds.contains(friend.uid),
                    )
                    .toList(growable: false);

                if (relationshipProvider.isLoading && friends.isEmpty) {
                  return const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.pointColor),
                  );
                }

                if (friends.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32.0,
                        vertical: 48.0,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.noFriendsInCategory,
                            style: TypographyStyles.headlineMedium.copyWith(
                              color: BrandColors.textPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: DesignTokens.s12),
                          Text(
                            AppLocalizations.of(context)!.addFriendsToCategory,
                            style: TypographyStyles.bodyLarge.copyWith(
                              color: BrandColors.textSecondary,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                      child: SizedBox(
                        height: 92,
                        child: selectedFriends.isEmpty
                            ? Align(
                                alignment: Alignment.topLeft,
                                child: Text(
                                  AppLocalizations.of(context)!
                                      .groupNoFriendsSelected,
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
                                itemCount: selectedFriends.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 14),
                                itemBuilder: (_, index) =>
                                    _buildSelectedFriendSlot(
                                  selectedFriends[index],
                                ),
                              ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText:
                              AppLocalizations.of(context)!.searchByFriendName,
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 22),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF4F6F8),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 15),
                        ),
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        AppLocalizations.of(context)!.friends,
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
                      child: displayFriends.isEmpty
                          ? Center(
                              child: Text(
                                AppLocalizations.of(context)!
                                    .groupNoSearchResults,
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            )
                          : ListView.builder(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                              itemCount: displayFriends.length,
                              itemBuilder: (_, index) {
                                final friend = displayFriends[index];
                                return _buildFriendSelectionTile(
                                  friend,
                                  isSelected:
                                      _selectedFriendIds.contains(friend.uid),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateShortcuts() {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
      child: Row(
        children: [
          Expanded(
            child: _buildCreateShortcut(
              key: const ValueKey('create_post_shortcut'),
              icon: Icons.article_outlined,
              label: l10n.post,
              semanticLabel: l10n.createPost,
              onTap: _openCreatePost,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildCreateShortcut(
              key: const ValueKey('create_meetup_shortcut'),
              icon: Icons.groups_outlined,
              label: l10n.meetup,
              semanticLabel: l10n.createMeetup,
              onTap: _openCreateMeetup,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildCreateShortcut(
              key: const ValueKey('create_snack_chat_shortcut'),
              icon: Icons.forum_outlined,
              label: l10n.snackChat,
              semanticLabel: l10n.createSnackChat,
              onTap: _openCreateSnackChat,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateShortcut({
    required Key key,
    required IconData icon,
    required String label,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: semanticLabel,
        child: Material(
          key: key,
          color: const Color(0xFFF4F6F8),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 21, color: AppColors.pointColor),
                  const SizedBox(height: 5),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFriendSelectionTile(
    UserProfile friend, {
    required bool isSelected,
  }) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: friend.displayNameOrNickname,
      onTap: () => _toggleFriend(friend.uid),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('group_friend_${friend.uid}'),
          onTap: () => _toggleFriend(friend.uid),
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
                    color:
                        isSelected ? AppColors.pointColor : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.pointColor
                          : const Color(0xFFB8C0CC),
                      width: 1.7,
                    ),
                  ),
                  child: isSelected
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
      ),
    );
  }

  Widget _buildSelectedFriendSlot(UserProfile friend) {
    return Semantics(
      button: true,
      label: friend.displayNameOrNickname,
      hint: AppLocalizations.of(context)!.groupRemoveFriendHint,
      onTap: () => _toggleFriend(friend.uid),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _toggleFriend(friend.uid),
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
                    child: const Icon(
                      Icons.close,
                      size: 12,
                      color: Colors.white,
                    ),
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

  /// 색상 문자열을 Color 객체로 파싱 (안전한 fallback 포함)
  Color _parseColor(String colorString) {
    // null 또는 빈 문자열 체크
    if (colorString.isEmpty) {
      Logger.error('⚠️ 빈 색상 문자열 감지, 기본 색상 사용');
      return const Color(0xFF6366F1); // 명시적인 기본 색상
    }

    // '#' 접두사 확인
    if (!colorString.startsWith('#')) {
      Logger.error('⚠️ 잘못된 색상 포맷: $colorString (# 없음)');
      return const Color(0xFF6366F1);
    }

    // Hex 색상 포맷 검증 (#RRGGBB)
    final hexPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');
    if (!hexPattern.hasMatch(colorString)) {
      Logger.error('⚠️ 잘못된 Hex 색상 포맷: $colorString');
      return const Color(0xFF6366F1);
    }

    try {
      final colorValue = int.parse(colorString.replaceFirst('#', '0xFF'));
      return Color(colorValue);
    } catch (e) {
      Logger.error('❌ 색상 파싱 실패: $colorString - $e');
      return const Color(0xFF6366F1); // 안전한 fallback
    }
  }

  /// 안전하게 opacity를 적용하는 헬퍼 메서드
  Color _safeColorWithOpacity(Color color, double opacity) {
    // opacity 값을 0.0~1.0 범위로 제한
    final clampedOpacity = opacity.clamp(0.0, 1.0);
    return color.withOpacity(clampedOpacity);
  }

  /// 아이콘 이름을 IconData로 파싱 (안전한 fallback 포함)
  IconData _parseIcon(String iconName) {
    // 빈 문자열 체크
    if (iconName.isEmpty) {
      Logger.error('⚠️ 빈 아이콘 이름 감지, 기본 아이콘 사용');
      return Icons.group;
    }

    final iconMap = {
      'shape_circle': Icons.circle,
      'shape_square': Icons.stop,
      'shape_star': Icons.star,
      // 하트/십자가는 더 이상 사용하지 않음(기존 데이터는 원으로 폴백)
      'shape_cross': Icons.circle,
      'shape_circle_filled': Icons.circle,
      'shape_circle_outline': Icons.radio_button_unchecked,
      'shape_square_filled': Icons.stop,
      'shape_square_outline': Icons.crop_square,
      // 채워진 삼각형 느낌으로 통일
      'shape_triangle': Icons.navigation,
      'shape_star_filled': Icons.star,
      'shape_star_outline': Icons.star_border,
      // 하트/십자가는 더 이상 사용하지 않음(기존 데이터는 원으로 폴백)
      'shape_heart': Icons.circle,
      'school': Icons.school,
      'groups': Icons.groups,
      'palette': Icons.palette,
      'book': Icons.book,
      'sports': Icons.sports_soccer,
      'restaurant': Icons.restaurant,
      'music': Icons.music_note,
      'fitness': Icons.fitness_center,
      'travel': Icons.flight,
      'game': Icons.videogame_asset,
      'movie': Icons.movie,
      'camera': Icons.camera_alt,
      'coffee': Icons.local_cafe,
      'shopping': Icons.shopping_bag,
      'home': Icons.home,
      'work': Icons.work,
      'favorite': Icons.favorite,
      'star': Icons.star,
      'group': Icons.group,
    };

    final icon = iconMap[iconName];
    if (icon == null) {
      Logger.error('⚠️ 알 수 없는 아이콘 이름: $iconName, 기본 아이콘 사용');
    }
    return icon ?? Icons.group;
  }
}
