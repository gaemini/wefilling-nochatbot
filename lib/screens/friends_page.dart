// lib/screens/friends_page.dart
// 친구 목록 화면
// 친구 목록 표시, 검색, 언팔 기능 제공

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/relationship_provider.dart';
import '../providers/auth_provider.dart';
import '../models/user_profile.dart';
import '../models/friend_category.dart';
import '../services/friend_category_service.dart';
import '../ui/widgets/app_icon_button.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/skeletons.dart';
import '../design/tokens.dart';
import '../constants/app_constants.dart';
import 'friend_profile_screen.dart';
import '../l10n/app_localizations.dart';
import '../utils/country_flag_helper.dart';
import '../utils/logger.dart';
import '../ui/widgets/shape_icon.dart';
import 'requests_page.dart';

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
    _categoriesSubscription?.cancel();
    _categoryService.dispose();
    _relationshipProvider?.removeListener(_handleRelationshipProviderChanged);
    super.dispose();
  }

  void _handleRelationshipProviderChanged() {
    if (!mounted) return;
    // provider.friends가 바뀌면 현재 검색어 기준으로 재필터링
    _filterFriends(_searchController.text);
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
    _categoriesSubscription = _categoryService.getCategoriesStream().listen((categories) {
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

    final filtered =
        allFriends.where((friend) {
          final name = friend.displayNameOrNickname.toLowerCase();
          final displayName = friend.displayName.toLowerCase();
          final nickname = friend.nickname?.toLowerCase() ?? '';
          final searchQuery = query.toLowerCase();

          return name.contains(searchQuery) ||
              displayName.contains(searchQuery) ||
              nickname.contains(searchQuery);
        }).toList();

    if (mounted) {
      setState(() {
        _filteredFriends = filtered;
      });
    }
  }

  /// 친구 삭제
  Future<void> _unfriend(UserProfile friend) async {
    final confirmed = await _showConfirmDialog(
      AppLocalizations.of(context)!.removeFriend,
      AppLocalizations.of(context)!.unfriendConfirm(friend.displayNameOrNickname),
    );

    if (confirmed) {
      final provider = context.read<RelationshipProvider>();
      final success = await provider.unfriend(friend.uid);

      if (success) {
        _showSnackBar(AppLocalizations.of(context)!.unfriendSuccess, Colors.red);
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
      AppLocalizations.of(context)!.blockUserConfirm(user.displayNameOrNickname),
    );

    if (confirmed) {
      final provider = context.read<RelationshipProvider>();
      final success = await provider.blockUser(user.uid);

      if (success) {
        _showSnackBar(AppLocalizations.of(context)!.userBlockedSuccess, Colors.red);
        // 필터링된 목록에서도 제거
        setState(() {
          _filteredFriends.removeWhere((f) => f.uid == user.uid);
        });
      } else {
        _showSnackBar(AppLocalizations.of(context)!.userBlockFailed, Colors.red);
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
      builder:
          (context) => AlertDialog(
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
      builder:
          (sheetContext) {
            final l10n = AppLocalizations.of(sheetContext)!;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.displayName,
                      style: TypographyStyles.headlineMedium.copyWith(
                        color: BrandColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (friend.nickname != null &&
                        friend.nickname!.isNotEmpty &&
                        friend.nickname != friend.displayName) ...[
                      const SizedBox(height: 8),
                      Text(
                        friend.nickname!,
                        style: TypographyStyles.bodyLarge.copyWith(
                          color: BrandColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
                        l10n.groupSettingsFor(friend.displayNameOrNickname) ?? "",
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
                        title: Text(category.name, style: TypographyStyles.titleMedium),
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
                          await _applyCategorySelection(friend, initialSelected, selected);
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
        await _categoryService.addFriendToCategory(categoryId: categoryId, friendId: friend.uid);
      }
      for (final categoryId in toRemove) {
        await _categoryService.removeFriendFromCategory(categoryId: categoryId, friendId: friend.uid);
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
        return Color(int.parse(colorString.substring(1), radix: 16) + 0xFF000000);
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
    return Container(
      color: const Color(0xFFEBEBEB), // 게시판과 동일한 배경색
      child: GestureDetector(
        onTap: () {
          // 빈 공간 터치시 키보드 닫기
          FocusScope.of(context).unfocus();
        },
        child: Column(
          children: [
            // 검색바
            _buildSearchBar(),

            // ✅ 들어온 친구요청 안내 배너 (친구 탭에서도 바로 확인 가능)
            Consumer<RelationshipProvider>(
              builder: (context, provider, child) {
                final incomingCount = provider.incomingRequests.length;
                final hasIncoming = incomingCount > 0;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RequestsPage()),
                      );
                    },
                    borderRadius: DesignTokens.radiusM,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: DesignTokens.radiusM,
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.mail_outline,
                              color: AppColors.pointColor,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              hasIncoming
                                  ? '친구 요청이 ${incomingCount > 99 ? '99+' : incomingCount.toString()}개 있어요'
                                  : AppLocalizations.of(context)!.checkFriendRequests,
                              style: TypographyStyles.titleMedium.copyWith(fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (hasIncoming)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                incomingCount > 99 ? '99+' : incomingCount.toString(),
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          const SizedBox(width: 6),
                          const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

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

                if (_filteredFriends.isEmpty &&
                    _searchController.text.trim().isNotEmpty) {
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: AppEmptyState.noSearchResults(
                        context: context,
                        searchQuery: _searchController.text.trim(),
                        onClearSearch: () {
                          _searchController.clear();
                          _filterFriends('');
                        },
                      ),
                    ),
                  );
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
    return Container(
      height: 60, // 검색 탭과 동일한 높이
      padding: const EdgeInsets.all(12), // 검색 탭과 동일한 패딩
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context)!.searchByFriendName,
          prefixIcon: const Icon(Icons.search),
          suffixIcon:
              _searchController.text.isNotEmpty
                  ? AppIconButton(
                    icon: Icons.clear,
                    onPressed: () {
                      _searchController.clear();
                      _filterFriends('');
                    },
                    semanticLabel: AppLocalizations.of(context)!.close,
                    tooltip: AppLocalizations.of(context)!.close,
                  )
                  : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25), // 검색 탭과 동일
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey[100], // 검색 탭과 동일
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, // 검색 탭과 동일
            vertical: 8, // 검색 탭과 동일
          ),
        ),
        onChanged: _filterFriends,
        textInputAction: TextInputAction.search,
      ),
    );
  }

  /// 친구 목록 위젯
  Widget _buildFriendsList() {
    // 안드로이드 하단 네비게이션 바 높이 감지
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return ListView.builder(
      padding: EdgeInsets.only(
        top: 8, 
        bottom: bottomPadding > 0 ? bottomPadding + 8 : 8,
      ),
      itemCount: _filteredFriends.length,
      itemBuilder: (context, index) {
        final friend = _filteredFriends[index];

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: DesignTokens.radiusM,
            border: Border.all(
              color: const Color(0xFFF3F4F6),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: InkWell(
            onTap: () => _navigateToProfile(friend),
            onLongPress: () => _showFriendOptions(friend),
            borderRadius: DesignTokens.radiusM,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 프로필 이미지
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: BrandColors.neutral200,
                      ),
                      child: friend.hasProfileImage
                          ? ClipOval(
                              child: Image.network(
                                friend.photoURL!,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.person_outline,
                                  size: 22,
                                  color: BrandColors.textTertiary,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.person_outline,
                              size: 24,
                              color: BrandColors.textTertiary,
                            ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // 사용자 정보 + 카테고리 배지 (줄바꿈 허용)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          friend.displayNameOrNickname,
                          style: TypographyStyles.titleMedium.copyWith(fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (friend.nickname != null &&
                            friend.nickname != friend.displayName &&
                            friend.nickname!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            friend.displayName,
                            style: TypographyStyles.bodySmall.copyWith(
                              color: BrandColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (friend.nationality != null && friend.nationality!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.flag_outlined,
                                size: 12,
                                color: Color(0xFF9CA3AF),
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  CountryFlagHelper.getCountryInfo(friend.nationality!)?.getLocalizedName(
                                        Localizations.localeOf(context).languageCode,
                                      ) ??
                                      friend.nationality!,
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        _buildGroupBadges(friend),
                      ],
                    ),
                  ),
                  
                  // 메뉴 버튼 (맨 오른쪽 상단에 배치)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: IconButton(
                      icon: Icon(
                        Icons.more_vert,
                        color: BrandColors.textTertiary,
                      ),
                      iconSize: 20,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () => _showFriendOptions(friend),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  /// 에러 상태 위젯
  Widget _buildErrorState(String errorMessage) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.error,
            style: TextStyle(
              fontSize: 18,
              color: Colors.red[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.red[500]),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              context.read<RelationshipProvider>().clearError();
            },
            child: Text(AppLocalizations.of(context)!.retryAction ?? ""),
          ),
        ],
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
    return ConstrainedBox(
      // 기존 대비 절반 수준으로 컴팩트하게
      constraints: const BoxConstraints(minHeight: 24, maxWidth: 88),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.35), width: 1),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ShapeIcon(
                iconName: iconName ?? 'group',
                color: color,
                size: 12,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 24, maxWidth: 64),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
              height: 1.1,
            ),
          ),
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
