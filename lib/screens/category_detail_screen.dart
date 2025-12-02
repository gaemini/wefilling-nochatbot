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
import '../utils/logger.dart';

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
      final List<String> missingUserIds = [];

      Logger.log('🔍 카테고리 친구 로드: ${widget.category.name}');
      Logger.log('  - category.friendIds: ${widget.category.friendIds.length}개');

      // 카테고리에 속한 친구들의 정보 가져오기
      for (final friendId in widget.category.friendIds) {
        final doc = await _firestore.collection('users').doc(friendId).get();
        if (doc.exists) {
          friends.add(UserProfile.fromFirestore(doc));
          Logger.log('  ✅ 로드 성공: $friendId');
        } else {
          missingUserIds.add(friendId);
          Logger.log('  ❌ 사용자 문서 없음: $friendId');
        }
      }

      Logger.log('📊 로드 결과:');
      Logger.log('  - 성공: ${friends.length}명');
      Logger.error('  - 실패: ${missingUserIds.length}명');

      if (mounted) {
        setState(() {
          _friends = friends;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('❌ 친구 목록 로드 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 색상 안전하게 파싱 (null 체크 포함)
    final color = _parseColor(widget.category.color ?? '#6366F1');
    // 아이콘 안전하게 파싱 (null 체크 포함)
    final icon = _parseIcon(widget.category.iconName ?? 'group');

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
                color: _safeColorWithOpacity(color, 0.1),
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
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
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
                      child: Builder(
                        builder: (context) {
                          // 안드로이드 하단 네비게이션 바 높이 감지
                          final bottomPadding = MediaQuery.of(context).padding.bottom;
                          
                          return ListView.builder(
                            padding: EdgeInsets.only(
                              top: 8,
                              bottom: bottomPadding > 0 ? bottomPadding + 8 : 8,
                            ),
                            itemCount: _friends.length,
                            itemBuilder: (context, index) {
                              final friend = _friends[index];
                              return _buildFriendCard(friend, color);
                            },
                          );
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
                  color: _safeColorWithOpacity(categoryColor, 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _safeColorWithOpacity(categoryColor, 0.3),
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







