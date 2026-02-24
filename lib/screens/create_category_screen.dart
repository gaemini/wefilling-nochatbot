// lib/screens/create_category_screen.dart
// 친구 카테고리 생성/수정 전체 페이지 화면

import 'package:flutter/material.dart';
import '../models/friend_category.dart';
import '../constants/app_constants.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets/shape_icon.dart';

class CreateCategoryScreen extends StatefulWidget {
  final FriendCategory? category; // null이면 생성, 있으면 수정

  const CreateCategoryScreen({
    super.key,
    this.category,
  });

  @override
  State<CreateCategoryScreen> createState() => _CreateCategoryScreenState();
}

class _CreateCategoryScreenState extends State<CreateCategoryScreen> {
  late final TextEditingController _nameController;
  late String _selectedColor;
  late String _selectedIcon;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _selectedColor = widget.category?.color ?? 
        '#${AppColors.pointColor.value.toRadixString(16).substring(2)}';
    _selectedIcon = _normalizeIconName(widget.category?.iconName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.category != null;

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

  void _handleSave() {
    final name = _nameController.text.trim();
    final l10n = AppLocalizations.of(context)!;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enterCategoryName ?? "")),
      );
      return;
    }

    Navigator.pop(
      context,
      {
        'name': name,
        'color': _selectedColor,
        'iconName': _selectedIcon,
      },
    );
  }

  Widget _buildColorPicker() {
    final colors = [
      '#FF3B30', // 빨강
      '#FF9500', // 주황
      '#FFCC00', // 노랑
      '#34C759', // 초록
      '#007AFF', // 파랑
      '#5856D6', // 남색
      '#AF52DE', // 보라
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
            final isSelected = color == _selectedColor;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedColor = color;
                });
              },
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

  Widget _buildIconPicker() {
    const icons = [
      {'name': 'shape_circle'},
      {'name': 'shape_triangle'},
      {'name': 'shape_square'},
      {'name': 'shape_star'},
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
            final isSelected = iconName == _selectedIcon;
            const iconSize = 26.0;

            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedIcon = iconName;
                });
              },
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

  Color _parseColor(String hexColor) {
    if (hexColor.isEmpty) {
      return const Color(0xFF6366F1);
    }

    if (!hexColor.startsWith('#')) {
      return const Color(0xFF6366F1);
    }

    final hexPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');
    if (!hexPattern.hasMatch(hexColor)) {
      return const Color(0xFF6366F1);
    }

    try {
      final colorValue = int.parse(hexColor.replaceFirst('#', '0xFF'));
      return Color(colorValue);
    } catch (e) {
      return const Color(0xFF6366F1);
    }
  }

  Color _safeColorWithOpacity(Color color, double opacity) {
    final clampedOpacity = opacity.clamp(0.0, 1.0);
    return color.withOpacity(clampedOpacity);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEdit ? (l10n.editCategory ?? "") : l10n.newCategory,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.2,
            letterSpacing: -0.2,
            color: Color(0xFF111827),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: const Color(0xFFE6EAF0),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nameController,
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
                      autofocus: true,
                    ),
                    const SizedBox(height: 24),
                    _buildColorPicker(),
                    const SizedBox(height: 24),
                    _buildIconPicker(),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Color(0xFFE6EAF0), width: 1),
                ),
              ),
              child: SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.pointColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _isEdit ? (l10n.editAction ?? "") : l10n.create,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
