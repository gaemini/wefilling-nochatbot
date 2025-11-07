// lib/screens/friends_page.dart
// 친구 목록 화면
// 친구 목록 표시, 검색, 언팔 기능 제공

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/relationship_provider.dart';
import '../models/user_profile.dart';
import '../models/friend_category.dart';
import '../services/friend_category_service.dart';
import '../ui/widgets/app_icon_button.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/skeletons.dart';
import 'friend_profile_screen.dart';
import '../l10n/app_localizations.dart';
import '../utils/country_flag_helper.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categoriesSubscription?.cancel();
    _categoryService.dispose();
    super.dispose();
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
      print('프로필 이동 오류: $e');
    }
  }

  /// 친구 옵션 메뉴 표시
  void _showFriendOptions(UserProfile friend) {
    showModalBottomSheet(
      context: context,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.person, color: Colors.blue),
                  title: Text(AppLocalizations.of(context)!.viewProfile ?? ""),
                  onTap: () {
                    Navigator.pop(context);
                    _navigateToProfile(friend);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.group, color: Colors.green),
                  title: Text(AppLocalizations.of(context)!.groupSettings ?? ""),
                  onTap: () {
                    Navigator.pop(context);
                    _showGroupSelectionDialog(friend);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.person_remove,
                    color: Colors.orange,
                  ),
                  title: Text(AppLocalizations.of(context)!.removeFriendAction ?? ""),
                  onTap: () {
                    Navigator.pop(context);
                    _unfriend(friend);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.red),
                  title: Text(AppLocalizations.of(context)!.blockAction ?? ""),
                  onTap: () {
                    Navigator.pop(context);
                    _blockUser(friend);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  /// 그룹 선택 다이얼로그 표시
  void _showGroupSelectionDialog(UserProfile friend) {
    // 현재 친구가 속한 그룹 찾기
    String? currentCategoryId;
    for (final category in _friendCategories) {
      if (category.friendIds.contains(friend.uid)) {
        currentCategoryId = category.id;
        break;
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.groupSettingsFor(friend.displayNameOrNickname) ?? ""),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 그룹 없음 옵션
              RadioListTile<String?>(
                title: Text(AppLocalizations.of(context)!.noGroup ?? ""),
                subtitle: Text(AppLocalizations.of(context)!.notInAnyGroup ?? ""),
                value: null,
                groupValue: currentCategoryId,
                onChanged: (value) {
                  Navigator.pop(context);
                  _assignToGroup(friend, null);
                },
                contentPadding: EdgeInsets.zero,
              ),
              
              const Divider(),
              
              // 친구 그룹 목록
              if (_friendCategories.isEmpty)
                Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    AppLocalizations.of(context)!.noFriendGroupsYet,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                )
              else
                ...(_friendCategories.map((category) {
                  return RadioListTile<String?>(
                    title: Text(category.name),
                    subtitle: Text(
                      AppLocalizations.of(context)!.friendsInGroup(category.friendIds.length),
                    ),
                    value: category.id,
                    groupValue: currentCategoryId,
                    onChanged: (value) {
                      Navigator.pop(context);
                      _assignToGroup(friend, value);
                    },
                    contentPadding: EdgeInsets.zero,
                    secondary: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _parseColor(category.color).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _parseColor(category.color).withOpacity(0.3),
                        ),
                      ),
                      child: Icon(
                        _parseIcon(category.iconName),
                        color: _parseColor(category.color),
                        size: 20,
                      ),
                    ),
                  );
                })),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel ?? ""),
          ),
        ],
      ),
    );
  }

  /// 친구를 그룹에 배정
  Future<void> _assignToGroup(UserProfile friend, String? categoryId) async {
    try {
      bool success = false;
      
      if (categoryId == null) {
        // 모든 그룹에서 제거
        for (final category in _friendCategories) {
          if (category.friendIds.contains(friend.uid)) {
            await _categoryService.removeFriendFromCategory(
              categoryId: category.id,
              friendId: friend.uid,
            );
          }
        }
        success = true;
        _showSnackBar(AppLocalizations.of(context)!.removedFromAllGroups(friend.displayNameOrNickname), Colors.blue);
      } else {
        // 선택한 그룹에 추가 (기존 그룹에서는 자동으로 제거됨)
        success = await _categoryService.addFriendToCategory(
          categoryId: categoryId,
          friendId: friend.uid,
        );
        
        if (success) {
          final selectedCategory = _friendCategories.firstWhere((cat) => cat.id == categoryId);
          _showSnackBar(
            AppLocalizations.of(context)!.addedToGroup(friend.displayNameOrNickname, selectedCategory.name),
            Colors.green
          );
        }
      }
      
      if (!success && categoryId != null) {
        _showSnackBar(AppLocalizations.of(context)!.groupAssignmentFailed, Colors.red);
      }
    } catch (e) {
      print('그룹 배정 오류: $e');
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

  /// 친구 그룹 배지 빌드
  Widget _buildGroupBadge(UserProfile friend) {
    // 친구가 속한 그룹 찾기
    FriendCategory? friendCategory;
    for (final category in _friendCategories) {
      if (category.friendIds.contains(friend.uid)) {
        friendCategory = category;
        break;
      }
    }

    if (friendCategory == null) {
      return const SizedBox.shrink(); // 그룹에 속하지 않으면 표시하지 않음
    }

    final color = _parseColor(friendCategory.color);
    
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10, // 6 -> 10 (67% 증가)
        vertical: 5, // 2 -> 5 (150% 증가)
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15), // 0.1 -> 0.15 (배경 조금 더 진하게)
        borderRadius: BorderRadius.circular(12), // 8 -> 12
        border: Border.all(
          color: color.withOpacity(0.4), // 0.3 -> 0.4 (테두리 조금 더 진하게)
          width: 1, // 0.5 -> 1
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _parseIcon(friendCategory.iconName),
            size: 16, // 12 -> 16 (33% 증가)
            color: color,
          ),
          const SizedBox(width: 6), // 3 -> 6 (100% 증가)
          Text(
            friendCategory.name,
            style: TextStyle(
              fontSize: 13, // 10 -> 13 (30% 증가)
              color: color,
              fontWeight: FontWeight.w600, // w500 -> w600 (더 진하게)
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // 빈 공간 터치시 키보드 닫기
        FocusScope.of(context).unfocus();
      },
      child: Column(
        children: [
          // 검색바
          _buildSearchBar(),

          // 친구 목록
          Expanded(
            child: Consumer<RelationshipProvider>(
              builder: (context, provider, child) {
                // provider의 friends가 변경되면 필터링된 목록도 업데이트
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && (_filteredFriends.length != provider.friends.length ||
                      _searchController.text.trim().isEmpty)) {
                    _filterFriends(_searchController.text);
                  }
                });

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
    );
  }

  /// 검색바 위젯
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context)!.searchByFriendName,
          hintStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: Color(0xFF9CA3AF),
          ),
          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF6B7280)),
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
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 4,
          ),
          isDense: true,
        ),
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Color(0xFF111827),
        ),
        onChanged: _filterFriends,
        textInputAction: TextInputAction.search,
      ),
    );
  }

  /// 친구 목록 위젯
  Widget _buildFriendsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _filteredFriends.length,
      itemBuilder: (context, index) {
        final friend = _filteredFriends[index];

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
          ),
          child: InkWell(
            onTap: () => _navigateToProfile(friend),
            onLongPress: () => _showFriendOptions(friend),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  // 프로필 이미지
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFE5E7EB),
                    ),
                    child: friend.hasProfileImage
                        ? ClipOval(
                            child: Image.network(
                              friend.photoURL!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.person,
                                size: 22,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            size: 24,
                            color: Color(0xFF6B7280),
                          ),
                  ),

                  const SizedBox(width: 10),

                  // 사용자 정보
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          friend.displayNameOrNickname,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (friend.nickname != null &&
                            friend.nickname != friend.displayName &&
                            friend.nickname!.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            friend.displayName,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF6B7280),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (friend.nationality != null &&
                            friend.nationality!.isNotEmpty) ...[
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
                                    Localizations.localeOf(context).languageCode
                                  ) ?? friend.nationality!,
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
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // 그룹 배지만 표시 (친구 상태 배지 제거)
                  _buildGroupBadge(friend),
                  
                  // 메뉴 버튼 (맨 오른쪽 상단에 배치)
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: Color(0xFF6B7280)),
                    iconSize: 20,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () => _showFriendOptions(friend),
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
