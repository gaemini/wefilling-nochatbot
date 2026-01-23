// lib/screens/category_detail_screen.dart
// 카테고리 상세 화면 - 전체 친구 목록에서 포함/미포함을 체크로 편집 후 저장

import 'package:flutter/material.dart';
import '../models/friend_category.dart';
import '../models/user_profile.dart';
import '../design/tokens.dart';
import '../ui/widgets/empty_state.dart';
import 'friend_profile_screen.dart';
import '../l10n/app_localizations.dart';
import '../utils/country_flag_helper.dart';
import '../utils/logger.dart';
import '../constants/app_constants.dart';
import 'package:provider/provider.dart';
import '../providers/relationship_provider.dart';
import '../providers/auth_provider.dart';
import '../services/friend_category_service.dart';
import '../ui/widgets/shape_icon.dart';

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

  bool get _hasChanges => _selectedFriendIds.length != _originalFriendIds.length ||
      !_selectedFriendIds.containsAll(_originalFriendIds);

  void _ensureFriendsLoaded() {
    try {
      final authProvider = context.read<AuthProvider>();
      final relationshipProvider = context.read<RelationshipProvider>();
      relationshipProvider.setAuthProvider(authProvider);

      // loadFriends()는 stream 구독만 걸고 즉시 반환될 수 있으므로,
      // 이 화면은 provider를 구독(Consumer)해서 데이터 도착 시 자동 리빌드되도록 한다.
      if (relationshipProvider.friends.isEmpty && !relationshipProvider.isLoading) {
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
      final displayName = f.displayName.toLowerCase();
      final nickname = (f.nickname ?? '').toLowerCase();
      return dn.contains(q) || displayName.contains(q) || nickname.contains(q);
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
      body: Consumer<RelationshipProvider>(
        builder: (context, relationshipProvider, _) {
          final friends = List<UserProfile>.from(relationshipProvider.friends)
            ..sort((a, b) => a.displayNameOrNickname.compareTo(b.displayNameOrNickname));
          final filteredFriends = _computeFilteredFriends(friends);

          if (relationshipProvider.isLoading && friends.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.pointColor),
            );
          }

          if (friends.isEmpty) {
            return Center(
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
            );
          }

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: const Color(0xFFF9FAFB),
                child: Text(
                  AppLocalizations.of(context)!.friendsInGroup(_selectedFriendIds.length),
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: Color(0xFF6B7280),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // 검색바
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)!.searchByFriendName,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),

              Expanded(
                child: Builder(
                  builder: (context) {
                    final bottomPadding = MediaQuery.of(context).padding.bottom;
                    return ListView.builder(
                      padding: EdgeInsets.only(
                        top: 8,
                        bottom: bottomPadding > 0 ? bottomPadding + 8 : 8,
                      ),
                      itemCount: filteredFriends.length,
                      itemBuilder: (context, index) {
                        final friend = filteredFriends[index];
                        final isSelected = _selectedFriendIds.contains(friend.uid);
                        return _buildFriendRow(
                          friend: friend,
                          categoryColor: color,
                          isSelected: isSelected,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFriendRow({
    required UserProfile friend,
    required Color categoryColor,
    required bool isSelected,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedFriendIds.remove(friend.uid);
            } else {
              _selectedFriendIds.add(friend.uid);
            }
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                activeColor: AppColors.pointColor,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedFriendIds.add(friend.uid);
                    } else {
                      _selectedFriendIds.remove(friend.uid);
                    }
                  });
                },
              ),

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

              IconButton(
                icon: const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
                onPressed: () => _navigateToProfile(friend),
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







