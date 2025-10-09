// lib/screens/friends_page.dart
// 친구 목록 화면
// 친구 목록 표시, 검색, 언팔 기능 제공

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/relationship_provider.dart';
import '../models/user_profile.dart';
import '../models/friend_category.dart';
import '../services/friend_category_service.dart';
import '../widgets/user_tile.dart';
import '../ui/widgets/app_icon_button.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/skeletons.dart';
import 'friend_profile_screen.dart';

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
    final provider = context.read<RelationshipProvider>();
    final allFriends = provider.friends;

    if (query.trim().isEmpty) {
      setState(() {
        _filteredFriends = allFriends;
      });
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

    setState(() {
      _filteredFriends = filtered;
    });
  }

  /// 친구 삭제
  Future<void> _unfriend(UserProfile friend) async {
    final confirmed = await _showConfirmDialog(
      '친구 삭제',
      '정말로 ${friend.displayNameOrNickname}님을 친구에서 삭제하시겠습니까?',
    );

    if (confirmed) {
      final provider = context.read<RelationshipProvider>();
      final success = await provider.unfriend(friend.uid);

      if (success) {
        _showSnackBar('친구를 삭제했습니다.', Colors.red);
        // 필터링된 목록에서도 제거
        setState(() {
          _filteredFriends.removeWhere((f) => f.uid == friend.uid);
        });
      } else {
        _showSnackBar('친구 삭제에 실패했습니다.', Colors.red);
      }
    }
  }

  /// 사용자 차단
  Future<void> _blockUser(UserProfile user) async {
    final confirmed = await _showConfirmDialog(
      '사용자 차단',
      '정말로 ${user.displayNameOrNickname}님을 차단하시겠습니까?\n차단된 사용자는 더 이상 친구요청을 보낼 수 없습니다.',
    );

    if (confirmed) {
      final provider = context.read<RelationshipProvider>();
      final success = await provider.blockUser(user.uid);

      if (success) {
        _showSnackBar('사용자를 차단했습니다.', Colors.red);
        // 필터링된 목록에서도 제거
        setState(() {
          _filteredFriends.removeWhere((f) => f.uid == user.uid);
        });
      } else {
        _showSnackBar('사용자 차단에 실패했습니다.', Colors.red);
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
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('확인'),
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
        '프로필을 불러올 수 없습니다.',
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
                  title: const Text('프로필 보기'),
                  onTap: () {
                    Navigator.pop(context);
                    _navigateToProfile(friend);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.group, color: Colors.green),
                  title: const Text('그룹 설정'),
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
                  title: const Text('친구 삭제'),
                  onTap: () {
                    Navigator.pop(context);
                    _unfriend(friend);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.red),
                  title: const Text('차단하기'),
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
        title: Text('${friend.displayNameOrNickname}님의 그룹 설정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 그룹 없음 옵션
              RadioListTile<String?>(
                title: const Text('그룹 없음'),
                subtitle: const Text('특정 그룹에 속하지 않습니다'),
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
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    '생성된 친구 그룹이 없습니다.\n친구 카테고리 관리에서 그룹을 만들어보세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                ...(_friendCategories.map((category) {
                  return RadioListTile<String?>(
                    title: Text(category.name),
                    subtitle: Text(
                      '${category.friendIds.length}명의 친구',
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
            child: const Text('취소'),
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
        _showSnackBar('${friend.displayNameOrNickname}님을 모든 그룹에서 제거했습니다.', Colors.blue);
      } else {
        // 선택한 그룹에 추가 (기존 그룹에서는 자동으로 제거됨)
        success = await _categoryService.addFriendToCategory(
          categoryId: categoryId,
          friendId: friend.uid,
        );
        
        if (success) {
          final selectedCategory = _friendCategories.firstWhere((cat) => cat.id == categoryId);
          _showSnackBar('${friend.displayNameOrNickname}님을 "${selectedCategory.name}" 그룹에 추가했습니다.', Colors.green);
        }
      }
      
      if (!success && categoryId != null) {
        _showSnackBar('그룹 설정에 실패했습니다. 다시 시도해주세요.', Colors.red);
      }
    } catch (e) {
      print('그룹 배정 오류: $e');
      _showSnackBar('오류가 발생했습니다. 다시 시도해주세요.', Colors.red);
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
        horizontal: 6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _parseIcon(friendCategory.iconName),
            size: 12,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            friendCategory.name,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return !_isInitialized
        ? AppSkeletonList.listItems(
          itemCount: 5,
          padding: const EdgeInsets.all(16),
        )
        : Column(
          children: [
            // 검색바
            _buildSearchBar(),

            // 친구 목록
            Expanded(
              child: Consumer<RelationshipProvider>(
                builder: (context, provider, child) {
                  // provider의 friends가 변경되면 필터링된 목록도 업데이트
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_filteredFriends.length != provider.friends.length ||
                        _searchController.text.trim().isEmpty) {
                      _filterFriends(_searchController.text);
                    }
                  });

                  if (provider.isLoading) {
                    return AppSkeletonList.listItems(
                      itemCount: 5,
                      padding: const EdgeInsets.all(16),
                    );
                  }

                  if (provider.errorMessage != null) {
                    return _buildErrorState(provider.errorMessage!);
                  }

                  if (provider.friends.isEmpty) {
                    return AppEmptyState.noFriends(
                      onSearchFriends: () {
                        // 친구 검색 화면으로 이동하는 로직
                        // 예: Navigator.push(...);
                      },
                    );
                  }

                  if (_filteredFriends.isEmpty &&
                      _searchController.text.trim().isNotEmpty) {
                    return AppEmptyState.noSearchResults(
                      searchQuery: _searchController.text.trim(),
                      onClearSearch: () {
                        _searchController.clear();
                        _filterFriends('');
                      },
                    );
                  }

                  return _buildFriendsList();
                },
              ),
            ),
          ],
        );
  }

  /// 검색바 위젯
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
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
          hintText: '친구 이름으로 검색',
          prefixIcon: const Icon(Icons.search),
          suffixIcon:
              _searchController.text.isNotEmpty
                  ? AppIconButton(
                    icon: Icons.clear,
                    onPressed: () {
                      _searchController.clear();
                      _filterFriends('');
                    },
                    semanticLabel: '검색어 지우기',
                    tooltip: '지우기',
                  )
                  : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
        onChanged: _filterFriends,
        textInputAction: TextInputAction.search,
      ),
    );
  }

  /// 친구 목록 위젯
  Widget _buildFriendsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _filteredFriends.length,
      itemBuilder: (context, index) {
        final friend = _filteredFriends[index];

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          elevation: 2,
          child: InkWell(
            onTap: () => _navigateToProfile(friend),
            onLongPress: () => _showFriendOptions(friend),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // 프로필 이미지
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[300],
                    ),
                    child: friend.hasProfileImage
                        ? ClipOval(
                            child: Image.network(
                              friend.photoURL!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.person,
                                size: 24,
                                color: Colors.grey[600],
                              ),
                            ),
                          )
                        : Icon(
                            Icons.person,
                            size: 24,
                            color: Colors.grey[600],
                          ),
                  ),

                  const SizedBox(width: 16),

                  // 사용자 정보
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          friend.displayNameOrNickname,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (friend.nickname != null &&
                            friend.nickname != friend.displayName &&
                            friend.nickname!.isNotEmpty)
                          Text(
                            friend.displayName,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        if (friend.nationality != null &&
                            friend.nationality!.isNotEmpty)
                          Row(
                            children: [
                              Icon(
                                Icons.flag,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                friend.nationality!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  // 친구 그룹 배지 및 메뉴
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 친구 상태 배지
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people, size: 16, color: Colors.green[700]),
                            const SizedBox(width: 4),
                            Text(
                              '친구',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // 그룹 배지 (그룹에 속한 경우에만 표시)
                      const SizedBox(height: 4),
                      _buildGroupBadge(friend),
                    ],
                  ),
                  
                  // 메뉴 버튼 (맨 오른쪽 상단에 배치)
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    iconSize: 20,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
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

  /// 빈 상태 위젯
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '아직 친구가 없습니다',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '사용자를 검색하여 친구를 추가해보세요',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
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
            '오류가 발생했습니다',
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
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}
