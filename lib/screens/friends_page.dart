// lib/screens/friends_page.dart
// 친구 목록 화면
// 친구 목록 표시, 검색, 언팔 기능 제공

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/relationship_provider.dart';
import '../providers/auth_provider.dart';
import '../models/user_profile.dart';
import '../models/relationship_status.dart';
import '../models/friend_category.dart';
import '../services/friend_category_service.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/skeletons.dart';
import '../design/tokens.dart';
import '../constants/app_constants.dart';
import 'friend_profile_screen.dart';
import '../l10n/app_localizations.dart';
import '../utils/country_flag_helper.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';
import '../ui/widgets/shape_icon.dart';
import 'requests_page.dart';
import '../widgets/user_tile.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final TextEditingController _searchController = TextEditingController();
  final FriendCategoryService _categoryService = FriendCategoryService();
  List<UserProfile> _filteredFriends = [];
  List<FriendCategory> _friendCategories = [];
  bool _isInitialized = false;
  StreamSubscription<List<FriendCategory>>? _categoriesSubscription;
  RelationshipProvider? _relationshipProvider;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // AuthProvider 연결
      final authProvider = context.read<AuthProvider>();
      final relationshipProvider = context.read<RelationshipProvider>();
      _relationshipProvider = relationshipProvider;
      relationshipProvider.setAuthProvider(authProvider);
      // provider 변화(친구 목록 갱신 등)에 맞춰 검색 결과도 함께 동기화
      relationshipProvider.addListener(_handleRelationshipProviderChanged);

      _initializeData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    _categoriesSubscription?.cancel();
    _categoryService.dispose();
    _relationshipProvider?.removeListener(_handleRelationshipProviderChanged);
    super.dispose();
  }

  void _handleRelationshipProviderChanged() {
    if (!mounted) return;
    // provider.friends가 바뀌면 (친구 탭 기본 화면에서만) 현재 검색어 기준으로 재필터링
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      _filterFriends(q);
    }
  }

  /// 데이터 초기화
  Future<void> _initializeData() async {
    if (_isInitialized) return;

    final provider = context.read<RelationshipProvider>();
    await provider.initialize();

    // 친구 카테고리 로드
    _loadFriendCategories();

    setState(() {
      _isInitialized = true;
      _filteredFriends = provider.friends;
    });
  }

  /// 친구 카테고리 로드
  void _loadFriendCategories() {
    _categoriesSubscription?.cancel();
    _categoriesSubscription =
        _categoryService.getCategoriesStream().listen((categories) {
      if (mounted) {
        setState(() {
          _friendCategories = categories;
        });
      }
    });
  }

  /// 친구 검색 필터링
  void _filterFriends(String query) {
    if (!mounted) return;

    final provider = context.read<RelationshipProvider>();
    final allFriends = provider.friends;

    if (query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _filteredFriends = allFriends;
        });
      }
      return;
    }

    final filtered = allFriends.where((friend) {
      final name = friend.displayNameOrNickname.toLowerCase();
      final nickname = friend.nickname?.toLowerCase() ?? '';
      final searchQuery = query.toLowerCase();

      return name.contains(searchQuery) || nickname.contains(searchQuery);
    }).toList();

    if (mounted) {
      setState(() {
        _filteredFriends = filtered;
      });
    }
  }

  /// 친구 탭 검색: 친구 목록 내 검색이 아니라 "전체 유저 검색"으로도 동작
  /// - 검색어 없음: 기존 친구 리스트
  /// - 검색어 있음: SearchUsersPage/통합 검색과 동일한 유저 검색 결과(비친구 포함)
  void _onSearchChanged(String query) {
    if (!mounted) return;

    final q = query.trim();
    _searchDebounce?.cancel();

    // 검색어가 비어있으면: 유저검색 결과 클리어 + 친구 목록으로 복귀
    if (q.isEmpty) {
      context.read<RelationshipProvider>().clearSearchResults();
      _filterFriends('');
      return;
    }

    // 너무 잦은 호출 방지 (검색 UX)
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      context.read<RelationshipProvider>().searchUsers(q);
    });
  }

  Widget _buildUserSearchResults(RelationshipProvider provider, String query) {
    // 로딩
    if (provider.isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.pointColor));
    }

    if (provider.errorMessage != null) {
      return _buildErrorState(provider.errorMessage!);
    }

    if (provider.searchResults.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      // ✅ 요구사항: 결과 없을 때 중앙 "Clear search" 버튼 제거
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  Icons.search_off_outlined,
                  size: 38,
                  color: Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.noSearchResults,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '\'$query\' ${l10n.tryDifferentKeyword}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return ListView.builder(
      padding: EdgeInsets.only(
        top: 8,
        bottom: bottomPadding > 0 ? bottomPadding + 8 : 8,
      ),
      itemCount: provider.searchResults.length,
      itemBuilder: (context, index) {
        final user = provider.searchResults[index];
        final status = provider.getRelationshipStatus(user.uid);
        return UserTile(
          user: user,
          relationshipStatus: status,
          onActionPressed: () => _handleUserAction(user, status),
          onTilePressed: () => _openUserProfileFromSearch(user),
          isLoading: provider.isLoading,
          minimal: true,
        );
      },
    );
  }

  void _openUserProfileFromSearch(UserProfile user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          userId: user.uid,
          nickname: user.displayNameOrNickname,
          photoURL: user.photoURL,
          email: user.email,
          university: user.university,
          // 친구 탭 검색에서는 비친구라도 기본 프로필은 프리뷰 허용
          allowNonFriendsPreview: true,
        ),
      ),
    );
  }

  void _handleUserAction(UserProfile user, RelationshipStatus status) {
    final provider = context.read<RelationshipProvider>();
    final l10n = AppLocalizations.of(context)!;

    switch (status) {
      case RelationshipStatus.none:
        provider.sendFriendRequest(user.uid).then((ok) {
          if (!mounted) return;
          if (ok) {
            _showSnackBar(l10n.friendRequestSent, Colors.green);
          } else {
            _showSnackBar(
                provider.errorMessage ?? l10n.friendRequestFailed, Colors.red);
          }
        });
        return;
      case RelationshipStatus.pendingOut:
        provider.cancelFriendRequest(user.uid).then((ok) {
          if (!mounted) return;
          _showSnackBar(
              ok ? l10n.friendRequestCancelled : l10n.friendRequestCancelFailed,
              ok ? Colors.orange : Colors.red);
        });
        return;
      case RelationshipStatus.friends:
        _unfriend(user);
        return;
      case RelationshipStatus.blocked:
        provider.unblockUser(user.uid).then((ok) {
          if (!mounted) return;
          _showSnackBar(ok ? l10n.userUnblocked : l10n.unblockFailed,
              ok ? Colors.green : Colors.red);
        });
        return;
      case RelationshipStatus.pendingIn:
      case RelationshipStatus.blockedBy:
        return;
    }
  }

  /// 친구 삭제
  Future<void> _unfriend(UserProfile friend) async {
    final confirmed = await _showConfirmDialog(
      AppLocalizations.of(context)!.removeFriend,
      AppLocalizations.of(context)!
          .unfriendConfirm(friend.displayNameOrNickname),
    );

    if (confirmed) {
      final provider = context.read<RelationshipProvider>();
      final success = await provider.unfriend(friend.uid);

      if (success) {
        _showSnackBar(
            AppLocalizations.of(context)!.unfriendSuccess, Colors.red);
        // 필터링된 목록에서도 제거
        setState(() {
          _filteredFriends.removeWhere((f) => f.uid == friend.uid);
        });
      } else {
        _showSnackBar(AppLocalizations.of(context)!.unfriendFailed, Colors.red);
      }
    }
  }

  /// 사용자 차단
  Future<void> _blockUser(UserProfile user) async {
    final confirmed = await _showConfirmDialog(
      AppLocalizations.of(context)!.blockUser,
      AppLocalizations.of(context)!
          .blockUserConfirm(user.displayNameOrNickname),
    );

    if (confirmed) {
      final provider = context.read<RelationshipProvider>();
      final success = await provider.blockUser(user.uid);

      if (success) {
        _showSnackBar(
            AppLocalizations.of(context)!.userBlockedSuccess, Colors.red);
        // 필터링된 목록에서도 제거
        setState(() {
          _filteredFriends.removeWhere((f) => f.uid == user.uid);
        });
      } else {
        _showSnackBar(
            AppLocalizations.of(context)!.userBlockFailed, Colors.red);
      }
    }
  }

  /// 스낵바 표시
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 확인 다이얼로그 표시
  Future<bool> _showConfirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel ?? ""),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(AppLocalizations.of(context)!.confirm ?? ""),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// 친구 프로필로 이동
  void _navigateToProfile(UserProfile friend) {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FriendProfileScreen(
            userId: friend.uid,
            nickname: friend.displayNameOrNickname,
            photoURL: friend.photoURL,
            email: friend.email,
            university: friend.university,
          ),
        ),
      );
    } catch (e) {
      _showSnackBar(
        AppLocalizations.of(context)!.cannotLoadProfile,
        Colors.red,
      );
      Logger.error('프로필 이동 오류: $e');
    }
  }

  /// 친구 옵션 메뉴 표시
  void _showFriendOptions(UserProfile friend) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final l10n = AppLocalizations.of(sheetContext)!;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.displayNameOrNickname,
                  style: TypographyStyles.headlineMedium.copyWith(
                    color: BrandColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                _ActionTile(
                  icon: Icons.person_outline,
                  iconColor: BrandColors.info,
                  title: l10n.viewProfile ?? "",
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _navigateToProfile(friend);
                  },
                ),
                const Divider(height: 1),
                _ActionTile(
                  icon: Icons.category_outlined,
                  iconColor: AppColors.pointColor,
                  title: l10n.groupSettings ?? "",
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showGroupSelectionDialog(friend);
                  },
                ),
                const Divider(height: 1),
                _ActionTile(
                  icon: Icons.person_remove_outlined,
                  iconColor: BrandColors.warning,
                  title: l10n.removeFriendAction ?? "",
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _unfriend(friend);
                  },
                ),
                const Divider(height: 1),
                _ActionTile(
                  icon: Icons.block,
                  iconColor: BrandColors.error,
                  title: l10n.blockAction ?? "",
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _blockUser(friend);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 그룹 선택 다이얼로그 표시
  void _showGroupSelectionDialog(UserProfile friend) {
    final initialSelected = _friendCategories
        .where((c) => c.friendIds.contains(friend.uid))
        .map((c) => c.id)
        .toSet();
    final selected = Set<String>.from(initialSelected);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) {
          final l10n = AppLocalizations.of(sheetContext)!;
          final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.groupSettingsFor(friend.displayNameOrNickname) ??
                            "",
                        style: TypographyStyles.headlineMedium.copyWith(
                          color: BrandColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_friendCategories.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        l10n.noFriendGroupsYet,
                        style: TypographyStyles.bodyLarge.copyWith(
                          color: BrandColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _friendCategories.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final category = _friendCategories[i];
                      final checked = selected.contains(category.id);
                      final color = _parseColor(category.color);

                      return CheckboxListTile(
                        value: checked,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              selected.add(category.id);
                            } else {
                              selected.remove(category.id);
                            }
                          });
                        },
                        title: Text(category.name,
                            style: TypographyStyles.titleMedium),
                        subtitle: Text(
                          l10n.friendsInGroup(category.friendIds.length),
                          style: TypographyStyles.bodySmall.copyWith(
                            color: BrandColors.textSecondary,
                          ),
                        ),
                        // 아이콘만 보이도록 (배경/테두리 제거)
                        secondary: SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: Icon(
                              _parseIcon(category.iconName),
                              color: color,
                              size: 28,
                            ),
                          ),
                        ),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6B7280),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(l10n.cancel ?? ""),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.pointColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          await _applyCategorySelection(
                              friend, initialSelected, selected);
                        },
                        child: Text(l10n.save),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _applyCategorySelection(
    UserProfile friend,
    Set<String> before,
    Set<String> after,
  ) async {
    try {
      final toAdd = after.difference(before);
      final toRemove = before.difference(after);

      for (final categoryId in toAdd) {
        await _categoryService.addFriendToCategory(
            categoryId: categoryId, friendId: friend.uid);
      }
      for (final categoryId in toRemove) {
        await _categoryService.removeFriendFromCategory(
            categoryId: categoryId, friendId: friend.uid);
      }

      _showSnackBar(AppLocalizations.of(context)!.save, Colors.green);
    } catch (e) {
      Logger.error('그룹 배정 오류: $e');
      _showSnackBar(AppLocalizations.of(context)!.errorOccurred, Colors.red);
    }
  }

  /// 색상 문자열을 Color 객체로 변환
  Color _parseColor(String colorString) {
    try {
      if (colorString.startsWith('#')) {
        return Color(
            int.parse(colorString.substring(1), radix: 16) + 0xFF000000);
      }
      return const Color(0xFF4A90E2); // 기본 색상
    } catch (e) {
      return const Color(0xFF4A90E2); // 기본 색상
    }
  }

  /// 아이콘 이름을 IconData로 변환
  IconData _parseIcon(String iconName) {
    switch (iconName) {
      case 'shape_circle':
        return Icons.circle;
      case 'shape_square':
        return Icons.stop;
      case 'shape_star':
        return Icons.star;
      // 하트/십자가는 더 이상 사용하지 않음(기존 데이터는 원으로 폴백)
      case 'shape_cross':
        return Icons.circle;
      case 'shape_circle_filled':
        return Icons.circle;
      case 'shape_circle_outline':
        return Icons.radio_button_unchecked;
      case 'shape_square_filled':
        return Icons.stop;
      case 'shape_square_outline':
        return Icons.crop_square;
      case 'shape_triangle':
        // 채워진 삼각형 느낌으로 통일
        return Icons.navigation;
      case 'shape_star_filled':
        return Icons.star;
      case 'shape_star_outline':
        return Icons.star_border;
      // 하트/십자가는 더 이상 사용하지 않음(기존 데이터는 원으로 폴백)
      case 'shape_heart':
        return Icons.circle;
      case 'school':
        return Icons.school;
      case 'groups':
        return Icons.groups;
      case 'palette':
        return Icons.palette;
      case 'book':
        return Icons.book;
      case 'work':
        return Icons.work;
      case 'sports':
        return Icons.sports;
      case 'music_note':
        return Icons.music_note;
      case 'restaurant':
        return Icons.restaurant;
      case 'travel_explore':
        return Icons.travel_explore;
      default:
        return Icons.group;
    }
  }

  /// 친구 카테고리 뱃지들 UI 최적화
  /// - 카드에서는 최대 2개만 노출하고, 더 많으면 +N 요약 배지로 표시
  /// - 카드 폭에 따라 Wrap으로 자연스럽게 줄바꿈(카드 높이 유동)
  /// - 텍스트는 말줄임 + 내부 요소(아이콘/텍스트) 가운데 정렬
  Widget _buildGroupBadges(UserProfile friend) {
    final categories = _friendCategories
        .where((c) => c.friendIds.contains(friend.uid))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (categories.isEmpty) return const SizedBox.shrink();

    const maxVisible = 2;

    final visible = categories.take(maxVisible).toList();
    final remaining = categories.length - visible.length;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final cat in visible)
          _CategoryBadge(
            color: _parseColor(cat.color),
            iconName: cat.iconName,
            label: cat.name,
          ),
        if (remaining > 0)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showAllCategoriesSheet(categories),
            child: _OverflowBadge(label: '+$remaining'),
          ),
      ],
    );
  }

  bool _hasGroupBadges(UserProfile friend) {
    return _friendCategories.any((c) => c.friendIds.contains(friend.uid));
  }

  void _showAllCategoriesSheet(List<FriendCategory> categories) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.category,
                  style: TypographyStyles.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categories
                      .map<Widget>(
                        (cat) => _CategoryBadge(
                          color: _parseColor(cat.color),
                          iconName: cat.iconName,
                          label: cat.name,
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: GestureDetector(
        onTap: () {
          // 빈 공간 터치시 키보드 닫기
          FocusScope.of(context).unfocus();
        },
        child: Column(
          children: [
            // 검색바
            _buildSearchBar(),

            _buildFriendRequestsShortcut(),

            // 친구 목록
            Expanded(
              child: Consumer<RelationshipProvider>(
                builder: (context, provider, child) {
                  // 로딩 중일 때 스켈레톤 표시
                  if (provider.isLoading && !_isInitialized) {
                    return AppSkeletonList.listItems(
                      itemCount: 8,
                      padding: const EdgeInsets.all(16),
                    );
                  }

                  if (provider.errorMessage != null) {
                    return _buildErrorState(provider.errorMessage!);
                  }

                  // 로딩이 끝났고 친구 목록이 비어있을 때만 빈 상태 표시
                  if (!provider.isLoading && provider.friends.isEmpty) {
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: AppEmptyState.noFriends(
                          context: context,
                          onSearchFriends: () {
                            // 친구 검색 화면으로 이동하는 로직
                            // 예: Navigator.push(...);
                          },
                        ),
                      ),
                    );
                  }

                  final q = _searchController.text.trim();
                  if (q.isNotEmpty) {
                    // ✅ 친구 탭에서도 전체 유저 검색 결과 표시 (비친구 포함)
                    return _buildUserSearchResults(provider, q);
                  }

                  return _buildFriendsList();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 검색바 위젯
  Widget _buildSearchBar() {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360 ? 12.0 : (width < 600 ? 16.0 : 24.0);
    final fieldHeight = width < 360 ? 42.0 : 44.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        width < 360 ? 8 : 10,
        horizontalPadding,
        width < 360 ? 8 : 10,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, _) {
              return SizedBox(
                height: fieldHeight,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.2,
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: context.rf(14).clamp(13, 15).toDouble(),
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF111827),
                    ),
                    decoration: InputDecoration(
                      hintText:
                          AppLocalizations.of(context)!.searchByFriendName,
                      hintStyle: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF8B93A1),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: Color(0xFF4B5563),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 42,
                        minHeight: 42,
                      ),
                      suffixIcon: value.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                              color: const Color(0xFF667085),
                              tooltip: AppLocalizations.of(context)!.close,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF4F5F7),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFriendRequestsShortcut() {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360 ? 12.0 : (width < 600 ? 16.0 : 24.0);

    return Consumer<RelationshipProvider>(
      builder: (context, provider, child) {
        final incomingCount = provider.incomingRequests.length;
        final hasIncoming = incomingCount > 0;
        return Material(
          color: Colors.white,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RequestsPage()),
              );
            },
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFEAECF0)),
                    ),
                  ),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.2,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.mail_outline_rounded,
                          size: 20,
                          color: Color(0xFF475467),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.checkFriendRequests,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: context.rf(14).clamp(13, 15).toDouble(),
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827),
                            ),
                          ),
                        ),
                        if (hasIncoming) ...[
                          const SizedBox(width: 8),
                          Container(
                            constraints: const BoxConstraints(minWidth: 22),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF344054),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              incomingCount > 99 ? '99+' : '$incomingCount',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: Color(0xFF98A2B3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 친구 목록 위젯
  Widget _buildFriendsList() {
    // 안드로이드 하단 네비게이션 바 높이 감지
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 360;
    final isExpanded = screenWidth >= 600;
    final horizontalPadding = isCompact ? 12.0 : (isExpanded ? 24.0 : 16.0);
    final avatarSize = isCompact ? 40.0 : (isExpanded ? 46.0 : 44.0);
    final nameSize = isCompact ? 14.0 : (isExpanded ? 16.0 : 15.0);

    return ListView.builder(
      padding: EdgeInsets.only(
        top: 0,
        bottom: bottomPadding > 0 ? bottomPadding + 12 : 12,
      ),
      itemCount: _filteredFriends.length,
      itemBuilder: (context, index) {
        final friend = _filteredFriends[index];

        final hasGroups = _hasGroupBadges(friend);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: Colors.white,
                  child: InkWell(
                    onTap: () => _navigateToProfile(friend),
                    onLongPress: () => _showFriendOptions(friend),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        hasGroups ? 10 : 11,
                        horizontalPadding - 4,
                        hasGroups ? 9 : 11,
                      ),
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.25,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 프로필 이미지
                            Container(
                              width: avatarSize,
                              height: avatarSize,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: BrandColors.neutral200,
                              ),
                              child: friend.hasProfileImage
                                  ? ClipOval(
                                      child: Image.network(
                                        friend.photoURL!,
                                        width: avatarSize,
                                        height: avatarSize,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(
                                          Icons.person_outline_rounded,
                                          size: avatarSize * 0.5,
                                          color: BrandColors.textTertiary,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      Icons.person_outline_rounded,
                                      size: avatarSize * 0.52,
                                      color: BrandColors.textTertiary,
                                    ),
                            ),
                            SizedBox(width: isCompact ? 10 : 12),

                            // 사용자 정보 + 카테고리 메타데이터
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    friend.displayNameOrNickname,
                                    style:
                                        TypographyStyles.titleMedium.copyWith(
                                      fontSize: nameSize,
                                      fontWeight: FontWeight.w700,
                                      height: 1.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (friend.nationality != null &&
                                      friend.nationality!.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.flag_outlined,
                                          size: 13,
                                          color: Color(0xFF98A2B3),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            CountryFlagHelper.getCountryInfo(
                                                  friend.nationality!,
                                                )?.getLocalizedName(
                                                  Localizations.localeOf(
                                                    context,
                                                  ).languageCode,
                                                ) ??
                                                friend.nationality!,
                                            style: const TextStyle(
                                              fontFamily: 'Pretendard',
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF8B93A1),
                                              height: 1.2,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (hasGroups) ...[
                                    const SizedBox(height: 5),
                                    _buildGroupBadges(friend),
                                  ],
                                ],
                              ),
                            ),

                            IconButton(
                              icon: const Icon(Icons.more_vert_rounded),
                              color: const Color(0xFF667085),
                              iconSize: 19,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).moreButtonTooltip,
                              onPressed: () => _showFriendOptions(friend),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  indent:
                      horizontalPadding + avatarSize + (isCompact ? 10 : 12),
                  endIndent: horizontalPadding,
                  color: const Color(0xFFEAECF0),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 에러 상태 위젯
  Widget _buildErrorState(String errorMessage) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.25,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 34,
                color: Color(0xFF667085),
              ),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context)!.error,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  color: Color(0xFF667085),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  context.read<RelationshipProvider>().clearError();
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF344054),
                ),
                child: Text(AppLocalizations.of(context)!.retryAction ?? ''),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  final Color color;
  final String? iconName;
  final String label;

  const _CategoryBadge({
    required this.color,
    required this.iconName,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    const neutral = Color(0xFF667085);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 104),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShapeIcon(
            iconName: iconName ?? 'group',
            color: neutral,
            size: 11,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 11,
                color: neutral,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverflowBadge extends StatelessWidget {
  final String label;

  const _OverflowBadge({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF667085),
          height: 1.15,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: Icon(icon, color: iconColor, size: 26),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TypographyStyles.titleMedium.copyWith(
                  color: BrandColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
