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
import '../providers/auth_provider.dart';
import 'category_detail_screen.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';

class _CategoryDraft {
  final String name;
  final String color;
  final String iconName;

  const _CategoryDraft({
    required this.name,
    required this.color,
    required this.iconName,
  });
}

class FriendCategoriesScreen extends StatefulWidget {
  const FriendCategoriesScreen({super.key});

  @override
  State<FriendCategoriesScreen> createState() => _FriendCategoriesScreenState();
}

class _FriendCategoriesScreenState extends State<FriendCategoriesScreen> {
  final FriendCategoryService _categoryService = FriendCategoryService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late VoidCallback _cleanupCallback;

  @override
  void initState() {
    super.initState();
    
    // 스트림 정리 콜백 등록
    _cleanupCallback = () {
      _categoryService.dispose();
    };
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.registerStreamCleanup(_cleanupCallback);
    });
  }

  @override
  void dispose() {
    // AuthProvider에서 콜백 제거
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.unregisterStreamCleanup(_cleanupCallback);
    } catch (e) {
      Logger.error('AuthProvider 콜백 제거 오류: $e');
    }
    
    // 서비스 정리
    _categoryService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEBEBEB),
      body: SafeArea(
        child: StreamBuilder<List<FriendCategory>>(
        stream: _categoryService.getCategoriesStream(),
        builder: (context, snapshot) {
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

          final categories = snapshot.data ?? [];

          if (categories.isEmpty) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: AppEmptyState(
              icon: IconStyles.group,
              title: AppLocalizations.of(context)!.createFirstCategory,
              description: AppLocalizations.of(context)!.createFirstCategoryDescription,
                  // ctaText 및 onCtaPressed 제거하여 "Create New Category" 버튼 숨김
                ),
              ),
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
        onPressed: () => _showCreateCategoryDialog(),
        semanticLabel: AppLocalizations.of(context)!.newCategoryCreate,
        tooltip: AppLocalizations.of(context)!.addCategory,
        heroTag: 'add_category_fab',
      ),
    );
  }

  Widget _buildCategoryCard(FriendCategory category) {
    // 색상 안전하게 파싱 (null 체크 포함)
    final color = _parseColor(category.color ?? '#${AppColors.pointColor.value.toRadixString(16).substring(2)}');
    final iconName = _normalizeIconName(category.iconName);

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
          style: TypographyStyles.titleMedium,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6), // 간격 증가 (4 → 6)
          child: FutureBuilder<int>(
            future: _getActualFriendCount(category.friendIds),
            builder: (context, snapshot) {
              final count = snapshot.data ?? category.friendIds.length;
              return Text(
                AppLocalizations.of(context)!.friendsInGroup(count),
                style: TypographyStyles.bodySmall.copyWith(
                  color: BrandColors.textSecondary,
                ),
              );
            },
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(
            Icons.more_vert,
            color: Color(0xFF6B7280),
            size: 20,
          ),
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
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF6B7280)),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)!.editAction ?? "",
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF111827),
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline, size: 20, color: Color(0xFFEF4444)),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)!.delete, 
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFEF4444),
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
    _showCategoryDialog();
  }

  void _showEditCategoryDialog(FriendCategory category) {
    _showCategoryDialog(category: category);
  }

  Future<void> _showCategoryDialog({FriendCategory? category}) async {
    if (!mounted) return;
    
    final isEdit = category != null;
    final nameController = TextEditingController(text: category?.name ?? '');
    String selectedColor = category?.color ?? '#${AppColors.pointColor.value.toRadixString(16).substring(2)}';
    String selectedIcon = _normalizeIconName(category?.iconName);

    try {
      final draft = await showModalBottomSheet<_CategoryDraft>(
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
            final bottomSafeArea = MediaQuery.of(sheetContext).viewPadding.bottom;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + bottomSafeArea + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isEdit ? (l10n.editCategory ?? "") : l10n.newCategory,
                          style: TypographyStyles.headlineMedium.copyWith(
                            color: BrandColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: l10n.categoryName,
                      hintText: l10n.categoryNameHint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.pointColor,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildColorPicker(selectedColor, (color) {
                    setState(() => selectedColor = color);
                  }),
                  const SizedBox(height: 16),
                  _buildIconPicker(selectedIcon, (icon) {
                    setState(() => selectedIcon = icon);
                  }),
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
                          onPressed: () {
                            final name = nameController.text.trim();
                            if (name.isEmpty) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(content: Text(l10n.enterCategoryName ?? "")),
                              );
                              return;
                            }
                            Navigator.pop(
                              sheetContext,
                              _CategoryDraft(
                                name: name,
                                color: selectedColor,
                                iconName: selectedIcon,
                              ),
                            );
                          },
                          child: Text(isEdit ? (l10n.editAction ?? "") : l10n.create),
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

      if (!mounted || draft == null) return;

      bool success;
      if (isEdit) {
        success = await _categoryService.updateCategory(
          categoryId: category!.id,
          name: draft.name,
          description: '',
          color: draft.color,
          iconName: draft.iconName,
        );
      } else {
        final categoryId = await _categoryService.createCategory(
          name: draft.name,
          description: '',
          color: draft.color,
          iconName: draft.iconName,
        );
        success = categoryId != null;
      }

      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (isEdit ? (l10n.categoryUpdated ?? "") : l10n.categoryCreated)
                : (isEdit ? (l10n.categoryUpdateFailed ?? "") : l10n.categoryCreateFailed),
          ),
        ),
      );
    } finally {
      nameController.dispose();
    }
  }

  Widget _buildColorPicker(String selectedColor, Function(String) onColorSelected) {
    final colors = [
      '#${AppColors.pointColor.value.toRadixString(16).substring(2)}', '#6BC9A5', '#FF8C42', '#9B59B6', '#E74C3C',
      '#F39C12', '#27AE60', '#3498DB', '#8E44AD', '#95A5A6',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.colorSelection, 
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            final isSelected = color == selectedColor;
            return GestureDetector(
              onTap: () => onColorSelected(color),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _parseColor(color),
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: AppColors.pointColor, width: 3)
                      : Border.all(color: const Color(0xFFE5E7EB), width: 1),
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildIconPicker(String selectedIcon, Function(String) onIconSelected) {
    const icons = [
      {'name': 'shape_circle'},
      {'name': 'shape_triangle'},
      {'name': 'shape_square'},
      {'name': 'shape_star'},
      {'name': 'shape_heart'},
      {'name': 'shape_cross'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.iconSelection, 
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: icons.map((iconData) {
            final iconName = iconData['name'] as String;
            final isSelected = iconName == selectedIcon;
            // 모든 도형을 동일한 캔버스(CustomPaint)로 그리므로 크기 통일 가능
            const iconSize = 26.0;
            
            return GestureDetector(
              onTap: () => onIconSelected(iconName),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected 
                      ? _safeColorWithOpacity(AppColors.pointColor, 0.1)
                      : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected 
                        ? AppColors.pointColor 
                        : const Color(0xFFE5E7EB),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Center(
                  // 정삼각형은 커스텀 페인터로 렌더링
                  child: ShapeIcon(
                    iconName: iconName,
                    color: isSelected
                        ? AppColors.pointColor
                        : const Color(0xFF6B7280),
                    size: iconSize,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
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

    switch (iconName) {
      case 'shape_circle':
        return Icons.circle;
      case 'shape_square':
        return Icons.stop;
      case 'shape_star':
        return Icons.star;
      case 'shape_cross':
        return Icons.add;
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
      case 'shape_heart':
        return Icons.favorite;
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

  String _normalizeIconName(String? iconName) {
    const allowed = {
      'shape_triangle',
      'shape_circle',
      'shape_square',
      'shape_star',
      'shape_heart',
      'shape_cross',
    };

    if (iconName == null || iconName.isEmpty) return 'shape_circle';
    if (allowed.contains(iconName)) return iconName;

    // 구버전(8개) 아이콘 키 → 새 6개 키로 매핑
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
}
