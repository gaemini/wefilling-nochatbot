// lib/screens/friend_categories_screen.dart
// 친구 카테고리 관리 화면

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/friend_category.dart';
import '../services/friend_category_service.dart';
import '../design/tokens.dart';
import '../ui/widgets/app_fab.dart';
import '../ui/widgets/empty_state.dart';
import '../providers/auth_provider.dart';
import 'category_detail_screen.dart';
import '../l10n/app_localizations.dart';

class FriendCategoriesScreen extends StatefulWidget {
  const FriendCategoriesScreen({super.key});

  @override
  State<FriendCategoriesScreen> createState() => _FriendCategoriesScreenState();
}

class _FriendCategoriesScreenState extends State<FriendCategoriesScreen> {
  final FriendCategoryService _categoryService = FriendCategoryService();
  bool _isInitialized = false;
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
      print('AuthProvider 콜백 제거 오류: $e');
    }
    
    // 서비스 정리
    _categoryService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.friendCategoriesManagement,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
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
      body: StreamBuilder<List<FriendCategory>>(
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
            // 첫 번째 로딩이고 카테고리가 없으면 기본 카테고리 생성
            if (!_isInitialized) {
              _isInitialized = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _createDefaultCategoriesIfNeeded();
              });
            }
            
            return AppEmptyState(
              icon: IconStyles.group,
              title: AppLocalizations.of(context)!.createFirstCategory,
              description: AppLocalizations.of(context)!.createFirstCategoryDescription,
              ctaText: AppLocalizations.of(context)!.newCategoryCreate,
              ctaIcon: IconStyles.add,
              onCtaPressed: () => _showCreateCategoryDialog(),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return _buildCategoryCard(category);
            },
          );
        },
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
    final color = _parseColor(category.color);
    final icon = _parseIcon(category.iconName);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: ComponentStyles.cardDecoration,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            color: color,
            size: 24,
          ),
        ),
        title: Text(
          category.name,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            AppLocalizations.of(context)!.friendsInGroup(category.friendIds.length),
            style: TextStyle(
              color: BrandColors.neutral500,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(
            IconStyles.more,
            color: BrandColors.neutral500,
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
                  Icon(IconStyles.edit, size: 20),
                  const SizedBox(width: 12),
                  Text(AppLocalizations.of(context)!.editAction ?? ""),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 20, color: BrandColors.error),
                  const SizedBox(width: 12),
                  Text(AppLocalizations.of(context)!.delete, style: TextStyle(color: BrandColors.error)),
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

  void _showCategoryDialog({FriendCategory? category}) {
    if (!mounted) return;
    
    final isEdit = category != null;
    final nameController = TextEditingController(text: category?.name ?? '');
    String selectedColor = category?.color ?? '#4A90E2';
    String selectedIcon = category?.iconName ?? 'group';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isEdit ? (AppLocalizations.of(context)!.editCategory ?? "") : AppLocalizations.of(context)!.newCategory),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.categoryName,
                    hintText: AppLocalizations.of(context)!.categoryNameHint,
                  ),
                ),
                const SizedBox(height: 16),
                _buildColorPicker(selectedColor, (color) {
                  setState(() {
                    selectedColor = color;
                  });
                }),
                const SizedBox(height: 16),
                _buildIconPicker(selectedIcon, (icon) {
                  setState(() {
                    selectedIcon = icon;
                  });
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.cancel ?? ""),
            ),
            ElevatedButton(
              style: ComponentStyles.primaryButton,
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(AppLocalizations.of(context)!.enterCategoryName ?? "")),
                  );
                  return;
                }

                bool success;
                if (isEdit) {
                  success = await _categoryService.updateCategory(
                    categoryId: category!.id,
                    name: name,
                    description: '',
                    color: selectedColor,
                    iconName: selectedIcon,
                  );
                } else {
                  final categoryId = await _categoryService.createCategory(
                    name: name,
                    description: '',
                    color: selectedColor,
                    iconName: selectedIcon,
                  );
                  success = categoryId != null;
                }

                if (success) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEdit ? (AppLocalizations.of(context)!.categoryUpdated ?? "") : AppLocalizations.of(context)!.categoryCreated),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEdit ? (AppLocalizations.of(context)!.categoryUpdateFailed ?? "") : AppLocalizations.of(context)!.categoryCreateFailed),
                    ),
                  );
                }
              },
              child: Text(isEdit ? (AppLocalizations.of(context)!.editAction ?? "") : AppLocalizations.of(context)!.create),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPicker(String selectedColor, Function(String) onColorSelected) {
    const colors = [
      '#4A90E2', '#6BC9A5', '#FF8C42', '#9B59B6', '#E74C3C',
      '#F39C12', '#27AE60', '#3498DB', '#8E44AD', '#95A5A6',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.of(context)!.colorSelection, style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
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
                      ? Border.all(color: BrandColors.primary, width: 3)
                      : Border.all(color: Colors.grey.shade300, width: 1),
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
      {'name': 'group', 'icon': Icons.group},
      {'name': 'school', 'icon': Icons.school},
      {'name': 'work', 'icon': Icons.work},
      {'name': 'palette', 'icon': Icons.palette},
      {'name': 'sports', 'icon': Icons.sports_soccer},
      {'name': 'music', 'icon': Icons.music_note},
      {'name': 'book', 'icon': Icons.book},
      {'name': 'home', 'icon': Icons.home},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.of(context)!.iconSelection, style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: icons.map((iconData) {
            final iconName = iconData['name'] as String;
            final icon = iconData['icon'] as IconData;
            final isSelected = iconName == selectedIcon;
            
            return GestureDetector(
              onTap: () => onIconSelected(iconName),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected ? BrandColors.primary.withOpacity(0.1) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? BrandColors.primary : Colors.grey.shade300,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? BrandColors.primary : BrandColors.neutral600,
                  size: 24,
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
        title: Text(AppLocalizations.of(context)!.deleteCategory ?? ""),
        content: Text(
          AppLocalizations.of(context)!.deleteCategoryConfirm(category.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel ?? ""),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: BrandColors.error,
              foregroundColor: Colors.white,
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
            child: Text(AppLocalizations.of(context)!.delete ?? ""),
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
      print('기본 카테고리 생성 UI 오류: $e');
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

  Color _parseColor(String hexColor) {
    try {
      return Color(int.parse(hexColor.replaceFirst('#', '0xFF')));
    } catch (e) {
      return BrandColors.primary;
    }
  }

  IconData _parseIcon(String iconName) {
    switch (iconName) {
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
      default:
        return Icons.group;
    }
  }
}
