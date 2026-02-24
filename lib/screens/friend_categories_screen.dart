// lib/screens/friend_categories_screen.dart
// 친구 카테고리 관리 화면

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/friend_category.dart';
import '../services/friend_category_service.dart';
import '../ui/widgets/shape_icon.dart';
import '../constants/app_constants.dart';
import '../design/tokens.dart';
import '../ui/widgets/app_fab.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/category_shapes_illustration.dart';
import '../providers/auth_provider.dart';
import 'category_detail_screen.dart';
import 'create_category_screen.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';

class FriendCategoriesScreen extends StatefulWidget {
  const FriendCategoriesScreen({super.key});

  @override
  State<FriendCategoriesScreen> createState() => _FriendCategoriesScreenState();
}

class _FriendCategoriesScreenState extends State<FriendCategoriesScreen> {
  final FriendCategoryService _categoryService = FriendCategoryService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late VoidCallback _cleanupCallback;
  AuthProvider? _authProvider;
  static const int _maxCategories = FriendCategoryService.maxCategoriesPerUser;

  @override
  void initState() {
    super.initState();
    
    // 스트림 정리 콜백 등록
    _cleanupCallback = () {
      _categoryService.dispose();
    };

    // initState에서 listen:false로 읽는 것은 안전하며,
    // post-frame 콜백에서 (이미 dispose된) context를 조회하는 레이스를 제거한다.
    _authProvider = Provider.of<AuthProvider>(context, listen: false);
    _authProvider?.registerStreamCleanup(_cleanupCallback);
  }

  @override
  void dispose() {
    // AuthProvider에서 콜백 제거
    // dispose에서는 context로 ancestor lookup을 하지 않는다.
    _authProvider?.unregisterStreamCleanup(_cleanupCallback);
    
    // 서비스 정리
    _categoryService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FriendCategory>>(
      stream: _categoryService.getCategoriesStream(),
      builder: (context, snapshot) {
        final categories = snapshot.data ?? const <FriendCategory>[];

        return Scaffold(
          backgroundColor: const Color(0xFFEBEBEB),
          body: SafeArea(
            child: Builder(
              builder: (context) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          IconStyles.error,
                          size: 64,
                          color: BrandColors.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(context)!.error,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${snapshot.error}',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                if (categories.isEmpty) {
                  return AppEmptyState(
                    icon: IconStyles.group,
                    title: AppLocalizations.of(context)!.createFirstCategory,
                    description: AppLocalizations.of(context)!.createFirstCategoryDescription,
                    illustration: const Center(
                      child: CategoryShapesIllustration(),
                    ),
                    centerVertically: true,
                    // ctaText 및 onCtaPressed 제거하여 버튼 숨김 (FAB로 생성 유도)
                  );
                }

                // 안드로이드 하단 네비게이션 바 높이 감지
                final bottomPadding = MediaQuery.of(context).padding.bottom;

                return ListView.builder(
                  padding: EdgeInsets.only(
                    top: 8,
                    bottom: bottomPadding > 0 ? bottomPadding + 8 : 8,
                  ),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return _buildCategoryCard(category);
                  },
                );
              },
            ),
          ),
          floatingActionButton: AppFab(
            icon: IconStyles.add,
            onPressed: () {
              if (categories.length >= _maxCategories) {
                _showCategoryLimitReachedSnackBar();
                return;
              }
              _showCreateCategoryDialog();
            },
            semanticLabel: AppLocalizations.of(context)!.newCategoryCreate,
            tooltip: AppLocalizations.of(context)!.addCategory,
            heroTag: 'add_category_fab',
          ),
        );
      },
    );
  }

  Widget _buildCategoryCard(FriendCategory category) {
    // 색상 안전하게 파싱 (null 체크 포함)
    final color = _parseColor(category.color ?? '#${AppColors.pointColor.value.toRadixString(16).substring(2)}');
    final iconName = _normalizeIconName(category.iconName);
    final l10n = AppLocalizations.of(context)!;

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
            color: _safeColorWithOpacity(Colors.black, 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        // 아이콘만 보이도록 (배경/테두리 제거) - 크기만 유지
        leading: SizedBox(
          width: 46,
          height: 46,
          child: Center(
            child: ShapeIcon(iconName: iconName, color: color, size: 34),
          ),
        ),
        title: Text(
          category.name,
          style: TypographyStyles.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6), // 간격 증가 (4 → 6)
          child: FutureBuilder<int>(
            future: _getActualFriendCount(category.friendIds),
            builder: (context, snapshot) {
              final count = snapshot.data ?? category.friendIds.length;
              final isKo = Localizations.localeOf(context).languageCode == 'ko';
              final baseStyle = TypographyStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF4B5563), // 기존보다 한 톤 진하게
              );

              // 숫자가 묻히지 않도록 숫자만 굵기/색을 더 강하게 준다.
              return Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$count',
                      style: baseStyle.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    TextSpan(
                      text: isKo ? '명의 친구' : ' friend(s)',
                      style: baseStyle,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        trailing: PopupMenuButton<String>(
          // 흰 카드 위에서 버튼/배경이 섞이지 않도록 "버튼" 형태를 부여
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
            ),
            child: const Center(
              child: Icon(
                IconStyles.more,
                color: Color(0xFF6B7280),
                size: 18,
              ),
            ),
          ),
          padding: EdgeInsets.zero,
          // 메뉴 컨테이너도 배경과 구분되도록 테두리/틴트 적용
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
          ),
          elevation: 4,
          color: const Color(0xFFFCFCFD), // pure white보다 살짝 틴트
          surfaceTintColor: const Color(0xFFFCFCFD),
          shadowColor: const Color(0x1A000000), // 대비를 조금 더
          offset: const Offset(0, 8),
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _showEditCategoryDialog(category);
                break;
              case 'delete':
                _showDeleteConfirmDialog(category);
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'edit',
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B7280).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFE5E7EB),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      IconStyles.edit,
                      size: 16,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n.editAction ?? "",
                    style: TypographyStyles.labelLarge.copyWith(
                      color: BrandColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(height: 1),
            PopupMenuItem(
              value: 'delete',
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _safeColorWithOpacity(BrandColors.error, 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFFEE2E2),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: BrandColors.error,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n.delete,
                    style: TypographyStyles.labelLarge.copyWith(
                      color: BrandColors.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        onTap: () {
          // 카테고리 상세 화면으로 이동 (친구 목록 표시)
          _navigateToCategoryDetail(category);
        },
      ),
    );
  }

  void _showCreateCategoryDialog() {
    _navigateToCreateCategory();
  }

  void _showEditCategoryDialog(FriendCategory category) {
    _navigateToEditCategory(category);
  }

  Future<void> _navigateToCreateCategory() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => const CreateCategoryScreen(),
      ),
    );

    if (!mounted || result == null) return;

    final success = await _categoryService.createCategory(
      name: result['name'] as String,
      description: '',
      color: result['color'] as String,
      iconName: result['iconName'] as String,
    );

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success != null ? l10n.categoryCreated : l10n.categoryCreateFailed,
        ),
      ),
    );
  }

  Future<void> _navigateToEditCategory(FriendCategory category) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCategoryScreen(category: category),
      ),
    );

    if (!mounted || result == null) return;

    final success = await _categoryService.updateCategory(
      categoryId: category.id,
      name: result['name'] as String,
      description: '',
      color: result['color'] as String,
      iconName: result['iconName'] as String,
    );

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (l10n.categoryUpdated ?? "")
              : (l10n.categoryUpdateFailed ?? ""),
        ),
      ),
    );
  }

  void _showCategoryLimitReachedSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('그룹은 최대 10개까지 생성할 수 있어요.'),
      ),
    );
  }

  void _showDeleteConfirmDialog(FriendCategory category) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          AppLocalizations.of(context)!.deleteCategory ?? "",
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        content: Text(
          AppLocalizations.of(context)!.deleteCategoryConfirm(category.name),
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFF6B7280),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.cancel ?? "",
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              final success = await _categoryService.deleteCategory(category.id);
              Navigator.pop(context);
              
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLocalizations.of(context)!.categoryDeleted ?? "")),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLocalizations.of(context)!.categoryDeleteFailed ?? "")),
                );
              }
            },
            child: Text(
              AppLocalizations.of(context)!.delete ?? "",
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToCategoryDetail(FriendCategory category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoryDetailScreen(category: category),
      ),
    );
  }

  /// 실제 존재하는 친구 수 확인
  Future<int> _getActualFriendCount(List<String> friendIds) async {
    int count = 0;
    for (final friendId in friendIds) {
      final doc = await _firestore.collection('users').doc(friendId).get();
      if (doc.exists) {
        count++;
      }
    }
    return count;
  }

  Future<void> _createDefaultCategoriesIfNeeded() async {
    try {
      final success = await _categoryService.createDefaultCategories();
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.defaultCategoryCreated ?? ""),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('기본 카테고리 생성 UI 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.defaultCategoryFailed ?? ""),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  /// 색상 문자열을 Color 객체로 파싱 (안전한 fallback 포함)
  Color _parseColor(String hexColor) {
    // null 또는 빈 문자열 체크
    if (hexColor.isEmpty) {
      Logger.error('⚠️ 빈 색상 문자열 감지, 기본 색상 사용');
      return const Color(0xFF6366F1); // 명시적인 기본 색상
    }

    // '#' 접두사 확인
    if (!hexColor.startsWith('#')) {
      Logger.error('⚠️ 잘못된 색상 포맷: $hexColor (# 없음)');
      return const Color(0xFF6366F1);
    }

    // Hex 색상 포맷 검증 (#RRGGBB)
    final hexPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');
    if (!hexPattern.hasMatch(hexColor)) {
      Logger.error('⚠️ 잘못된 Hex 색상 포맷: $hexColor');
      return const Color(0xFF6366F1);
    }

    try {
      final colorValue = int.parse(hexColor.replaceFirst('#', '0xFF'));
      return Color(colorValue);
    } catch (e) {
      Logger.error('❌ 색상 파싱 실패: $hexColor - $e');
      return const Color(0xFF6366F1); // 안전한 fallback
    }
  }

  /// 안전하게 opacity를 적용하는 헬퍼 메서드
  Color _safeColorWithOpacity(Color color, double opacity) {
    final clampedOpacity = opacity.clamp(0.0, 1.0);
    return color.withOpacity(clampedOpacity);
  }

  String _normalizeIconName(String? iconName) {
    const allowed = {
      'shape_triangle',
      'shape_circle',
      'shape_square',
      'shape_star',
    };

    if (iconName == null || iconName.isEmpty) return 'shape_circle';
    if (allowed.contains(iconName)) return iconName;

    // 더 이상 제공하지 않는 아이콘은 원으로 폴백
    if (iconName == 'shape_heart' || iconName == 'shape_cross') {
      return 'shape_circle';
    }

    // 구버전 아이콘 키 → 새 키로 매핑
    switch (iconName) {
      case 'shape_circle_filled':
      case 'shape_circle_outline':
        return 'shape_circle';
      case 'shape_square_filled':
      case 'shape_square_outline':
        return 'shape_square';
      case 'shape_star_filled':
      case 'shape_star_outline':
        return 'shape_star';
      default:
        return 'shape_circle';
    }
  }

  /// 아이콘 이름을 IconData로 파싱 (안전한 fallback 포함)
  IconData _parseIcon(String iconName) {
    // 빈 문자열 체크
    if (iconName.isEmpty) {
      Logger.error('⚠️ 빈 아이콘 이름 감지, 기본 아이콘 사용');
      return Icons.group;
    }

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
      case 'work':
        return Icons.work;
      case 'palette':
        return Icons.palette;
      case 'sports':
        return Icons.sports_soccer;
      case 'music':
        return Icons.music_note;
      case 'book':
        return Icons.book;
      case 'home':
        return Icons.home;
      case 'group':
        return Icons.group;
      default:
        Logger.error('⚠️ 알 수 없는 아이콘 이름: $iconName, 기본 아이콘 사용');
        return Icons.group;
    }
  }
}
