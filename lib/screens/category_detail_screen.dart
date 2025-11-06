// lib/screens/category_detail_screen.dart
// 카테고리 상세 화면 - 해당 카테고리의 친구 목록 표시

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/friend_category.dart';
import '../models/user_profile.dart';
import '../design/tokens.dart';
import '../ui/widgets/empty_state.dart';
import 'friend_profile_screen.dart';
import '../l10n/app_localizations.dart';
import '../utils/country_flag_helper.dart';

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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<UserProfile> _friends = [];

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final List<UserProfile> friends = [];

      // 카테고리에 속한 친구들의 정보 가져오기
      for (final friendId in widget.category.friendIds) {
        final doc = await _firestore.collection('users').doc(friendId).get();
        if (doc.exists) {
          friends.add(UserProfile.fromFirestore(doc));
        }
      }

      if (mounted) {
        setState(() {
          _friends = friends;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('친구 목록 로드 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(widget.category.color);
    final icon = _parseIcon(widget.category.iconName);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.category.name,
                style: const TextStyle(
                  color: Color(0xFF4A90E2), // 위필링 로고색 (파란색)
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF4A90E2), // 위필링 로고색 (파란색)
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.grey[200]!,
                  Colors.grey[100]!,
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _friends.isEmpty
              ? AppEmptyState(
                  icon: Icons.people_outline,
                  title: '친구가 없습니다',
                  description: '이 카테고리에 친구를 추가해보세요',
                )
              : Column(
                  children: [
                    // 친구 수 표시
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: Colors.grey[100],
                      child: Text(
                        AppLocalizations.of(context)?.friendsInGroup(_friends.length),
                        style: TextStyle(
                          color: BrandColors.neutral700,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    
                    // 친구 목록
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _friends.length,
                        itemBuilder: (context, index) {
                          final friend = _friends[index];
                          return _buildFriendCard(friend, color);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildFriendCard(UserProfile friend, Color categoryColor) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      child: InkWell(
        onTap: () => _navigateToProfile(friend),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 프로필 이미지
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[300],
                ),
                child: friend.hasProfileImage
                    ? ClipOval(
                        child: Image.network(
                          friend.photoURL!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.person,
                            size: 28,
                            color: Colors.grey[600],
                          ),
                        ),
                      )
                    : Icon(
                        Icons.person,
                        size: 28,
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
                            CountryFlagHelper.getCountryInfo(friend.nationality!)?.getLocalizedName(
                              Localizations.localeOf(context).languageCode
                            ) ?? friend.nationality!,
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

              // 카테고리 배지
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: categoryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: categoryColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  widget.category.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: categoryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToProfile(UserProfile friend) {
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
  }

  Color _parseColor(String colorString) {
    try {
      return Color(
        int.parse(colorString.replaceFirst('#', '0xFF')),
      );
    } catch (e) {
      return BrandColors.primary;
    }
  }

  IconData _parseIcon(String iconName) {
    final iconMap = {
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

    return iconMap[iconName] ?? Icons.people;
  }
}


