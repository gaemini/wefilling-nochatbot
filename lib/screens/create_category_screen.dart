// lib/screens/create_category_screen.dart
// 친구 카테고리 생성/수정 전체 페이지 화면

import 'package:flutter/material.dart';
import '../models/friend_category.dart';
import '../constants/app_constants.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets/shape_icon.dart';
import '../utils/responsive_helper.dart';

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
        '#${AppColors.pointColor.toARGB32().toRadixString(16).substring(2)}';
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
        SnackBar(content: Text(l10n.enterCategoryName)),
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
    const colors = [
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
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontWeight: FontWeight.w800,
            fontSize: context.rf(15).clamp(14, 16).toDouble(),
            color: const Color(0xFF111827),
          ),
        ),
        SizedBox(height: context.rs(14).clamp(12, 16).toDouble()),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 330;
            return Wrap(
              alignment: compact ? WrapAlignment.center : WrapAlignment.start,
              spacing: compact ? 0 : 7,
              runSpacing: context.rs(8).clamp(6, 10).toDouble(),
              children: [
                for (var index = 0; index < colors.length; index++)
                  SizedBox(
                    width: compact ? constraints.maxWidth / 4 : 44,
                    child: Center(
                      child: _ColorChoice(
                        color: _parseColor(colors[index]),
                        selected: colors[index] == _selectedColor,
                        semanticLabel: _colorSemanticLabel(index),
                        onTap: () {
                          setState(() {
                            _selectedColor = colors[index];
                          });
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _colorSemanticLabel(int index) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    const ko = ['빨강', '주황', '노랑', '초록', '파랑', '남색', '보라'];
    const en = ['Red', 'Orange', 'Yellow', 'Green', 'Blue', 'Indigo', 'Purple'];
    return (isKo ? ko : en)[index];
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
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontWeight: FontWeight.w800,
            fontSize: context.rf(15).clamp(14, 16).toDouble(),
            color: const Color(0xFF111827),
          ),
        ),
        SizedBox(height: context.rs(12).clamp(10, 14).toDouble()),
        Wrap(
          spacing: context.rs(8).clamp(6, 10).toDouble(),
          runSpacing: context.rs(8).clamp(6, 10).toDouble(),
          children: icons.map((iconData) {
            final iconName = iconData['name'] as String;
            final isSelected = iconName == _selectedIcon;

            return Semantics(
              button: true,
              selected: isSelected,
              label: _iconSemanticLabel(iconName),
              child: Material(
                color: Colors.transparent,
                child: InkResponse(
                  onTap: () {
                    setState(() {
                      _selectedIcon = iconName;
                    });
                  },
                  radius: 24,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedScale(
                          scale: isSelected ? 1.08 : 1,
                          duration: DesignTokens.normal,
                          child: ShapeIcon(
                            iconName: iconName,
                            color: isSelected
                                ? _parseColor(_selectedColor)
                                : const Color(0xFF667085),
                            size: context.ri(26).clamp(24, 29).toDouble(),
                          ),
                        ),
                        if (isSelected)
                          const PositionedDirectional(
                            end: -1,
                            bottom: 1,
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 15,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _iconSemanticLabel(String iconName) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    const ko = {
      'shape_circle': '원',
      'shape_triangle': '삼각형',
      'shape_square': '사각형',
      'shape_star': '별',
    };
    const en = {
      'shape_circle': 'circle',
      'shape_triangle': 'triangle',
      'shape_square': 'square',
      'shape_star': 'star',
    };
    return (isKo ? ko : en)[iconName] ?? iconName;
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

  double get _toolbarHeight {
    final base = context.rh(56, min: 54, max: 60);
    final scaledTitle = MediaQuery.textScalerOf(context).scale(
      context.rf(18).clamp(16, 19).toDouble(),
    );
    final accessible = scaledTitle * 1.2 + DesignTokens.s24;
    return accessible > base ? accessible.clamp(base, 96).toDouble() : base;
  }

  Widget _buildCenteredTitle(String title) {
    final horizontalClearance =
        MediaQuery.sizeOf(context).width < 360 ? 88.0 : 110.0;
    return SafeArea(
      bottom: false,
      child: IgnorePointer(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalClearance),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(18).clamp(16, 19).toDouble(),
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827),
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppLocalizations l10n) {
    final title = _isEdit ? l10n.editCategory : l10n.newCategory;
    final actionLabel = _isEdit ? l10n.editAction : l10n.create;
    final useCompactAction = MediaQuery.sizeOf(context).width < 340 ||
        MediaQuery.textScalerOf(context).scale(14) > 24;

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.white,
      toolbarHeight: _toolbarHeight,
      automaticallyImplyLeading: false,
      leadingWidth: 48,
      leading: IconButton(
        icon: Icon(
          Icons.close_rounded,
          color: const Color(0xFF111827),
          size: context.ri(22).clamp(21, 24).toDouble(),
        ),
        onPressed: () => Navigator.pop(context),
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
      ),
      flexibleSpace: _buildCenteredTitle(title),
      actions: [
        if (useCompactAction)
          SizedBox.square(
            dimension: 48,
            child: IconButton(
              onPressed: _handleSave,
              tooltip: actionLabel,
              icon: Icon(
                Icons.check_rounded,
                size: context.ri(21).clamp(20, 23).toDouble(),
              ),
              color: const Color(0xFF111827),
            ),
          )
        else
          TextButton.icon(
            onPressed: _handleSave,
            icon: Icon(
              Icons.check_rounded,
              size: context.ri(18).clamp(17, 20).toDouble(),
            ),
            label: Text(
              actionLabel,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(14).clamp(13, 15).toDouble(),
                fontWeight: FontWeight.w700,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF111827),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(44, 44),
            ),
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Inter',
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: context.rf(15).clamp(14, 16).toDouble(),
        fontWeight: FontWeight.w800,
        color: const Color(0xFF111827),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(l10n),
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = MediaQuery.sizeOf(context).width;
            final systemBottomInset = MediaQuery.viewPaddingOf(context).bottom;
            final horizontalPadding = screenWidth < 360
                ? 14.0
                : screenWidth < 430
                    ? 16.0
                    : 20.0;

            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                context.rs(12).clamp(10, 16).toDouble(),
                horizontalPadding,
                DesignTokens.s24 + systemBottomInset,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionLabel(l10n.categoryName),
                      const Divider(height: 18, color: Color(0xFFE5E7EB)),
                      TextField(
                        controller: _nameController,
                        autofocus: true,
                        maxLines: 1,
                        decoration: InputDecoration(
                          hintText: l10n.categoryNameHint,
                          hintStyle: TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: context.rf(15).clamp(14, 16).toDouble(),
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF9CA3AF),
                          ),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.fromLTRB(0, 2, 0, 12),
                        ),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(15).clamp(14, 16).toDouble(),
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF111827),
                          height: 1.4,
                        ),
                      ),
                      SizedBox(
                        height: context.rs(22).clamp(18, 26).toDouble(),
                      ),
                      _buildColorPicker(),
                      SizedBox(
                        height: context.rs(26).clamp(22, 30).toDouble(),
                      ),
                      _buildIconPicker(),
                      SizedBox(
                        height: constraints.maxHeight < 500
                            ? context.rs(12)
                            : context.rs(24),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;

  Color get _checkColor =>
      color.computeLuminance() > 0.55 ? const Color(0xFF111827) : Colors.white;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox.square(
            dimension: 44,
            child: Center(
              child: AnimatedContainer(
                duration: DesignTokens.normal,
                width: selected ? 36 : 32,
                height: selected ? 36 : 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        color: _checkColor,
                        size: 19,
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
