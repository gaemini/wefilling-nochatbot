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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF5865F2)))
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: const Color(0xFFF9FAFB),
                      child: Text(
                        AppLocalizations.of(context)!.friendsInGroup(_friends.length),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          color: Color(0xFF6B7280),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    
                    // 친구 목록
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: InkWell(
        onTap: () => _navigateToProfile(friend),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // 프로필 이미지
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFE5E7EB),
                ),
                child: friend.hasProfileImage
                    ? ClipOval(
                        child: Image.network(
                          friend.photoURL!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.person,
                            size: 24,
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

              const SizedBox(width: 12),

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
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (friend.nickname != null &&
                        friend.nickname != friend.displayName &&
                        friend.nickname!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        friend.displayName,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 13,
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
                            size: 13,
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
                                fontSize: 12,
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

              // 카테고리 배지
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: categoryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: categoryColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  widget.category.name,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 11,
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


