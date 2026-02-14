// lib/ui/widgets/story_categories.dart
// 2024-2025 트렌드 Instagram/TikTok 영감 스토리 스타일 카테고리
// 수평 스크롤, 그라디언트 배경, 아이콘 + 텍스트 조합

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_constants.dart';

/// Instagram/TikTok 스타일 스토리 카테고리
/// 
/// ✨ 특징:
/// - 수평 스크롤 카테고리 리스트
/// - 각 카테고리마다 고유 그라디언트
/// - 아이콘 + 텍스트 조합
/// - 터치 피드백과 선택 상태 표시
/// - 부드러운 애니메이션
class StoryCategories extends StatefulWidget {
  /// 카테고리 목록
  final List<CategoryItem> categories;
  
  /// 선택된 카테고리 인덱스
  final int selectedIndex;
  
  /// 카테고리 선택 콜백
  final ValueChanged<int>? onCategorySelected;
  
  /// 카테고리 높이
  final double height;
  
  /// 카테고리 너비
  final double itemWidth;
  
  /// 카테고리 간 간격
  final double itemSpacing;
  
  /// 애니메이션 지속시간
  final Duration animationDuration;

  const StoryCategories({
    super.key,
    required this.categories,
    this.selectedIndex = 0,
    this.onCategorySelected,
    this.height = 100,
    this.itemWidth = 80,
    this.itemSpacing = 12,
    this.animationDuration = const Duration(milliseconds: 200),
  });

  /// 기본 카테고리로 생성하는 팩토리
  factory StoryCategories.defaultCategories({
    Key? key,
    int selectedIndex = 0,
    ValueChanged<int>? onCategorySelected,
    double height = 100,
  }) {
    final defaultCategories = [
      CategoryItem(
        id: 'all',
        title: '전체',
        icon: Icons.grid_view_rounded,
        gradient: AppTheme.primaryGradient,
      ),
      CategoryItem(
        id: 'study',
        title: '스터디',
        icon: Icons.school_rounded,
        gradient: AppTheme.secondaryGradient,
      ),
      CategoryItem(
        id: 'food',
        title: '밥',
        icon: Icons.restaurant_rounded,
        gradient: AppTheme.emeraldGradient,
      ),
      CategoryItem(
        id: 'hobby',
        title: '카페',
        icon: Icons.palette_rounded,
        gradient: AppTheme.amberGradient,
      ),
      CategoryItem(
        id: 'culture',
        title: '문화',
        icon: Icons.theater_comedy_rounded,
        gradient: LinearGradient(
          colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)], // Pink to Purple
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      CategoryItem(
        id: 'sports',
        title: '운동',
        icon: Icons.fitness_center_rounded,
        gradient: LinearGradient(
          colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)], // Cyan to Blue
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      CategoryItem(
        id: 'travel',
        title: '여행',
        icon: Icons.flight_rounded,
        gradient: LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFEF4444)], // Amber to Red
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    ];

    return StoryCategories(
      key: key,
      categories: defaultCategories,
      selectedIndex: selectedIndex,
      onCategorySelected: onCategorySelected,
      height: height,
    );
  }

  @override
  State<StoryCategories> createState() => _StoryCategoriesState();
}

class _StoryCategoriesState extends State<StoryCategories> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 선택된 카테고리로 스크롤
  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    
    final double targetOffset = widget.selectedIndex * 
        (widget.itemWidth + widget.itemSpacing);
    
    _scrollController.animateTo(
      targetOffset,
      duration: widget.animationDuration,
      curve: AppTheme.primaryCurve,
    );
  }

  @override
  void didUpdateWidget(StoryCategories oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelected();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: widget.categories.length,
        itemBuilder: (context, index) {
          final category = widget.categories[index];
          final isSelected = index == widget.selectedIndex;
          
          return _StoryCategoryItem(
            category: category,
            isSelected: isSelected,
            width: widget.itemWidth,
            spacing: widget.itemSpacing,
            animationDuration: widget.animationDuration,
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onCategorySelected?.call(index);
            },
          );
        },
      ),
    );
  }
}

/// 개별 스토리 카테고리 아이템
class _StoryCategoryItem extends StatefulWidget {
  final CategoryItem category;
  final bool isSelected;
  final double width;
  final double spacing;
  final Duration animationDuration;
  final VoidCallback? onTap;

  const _StoryCategoryItem({
    required this.category,
    required this.isSelected,
    required this.width,
    required this.spacing,
    required this.animationDuration,
    this.onTap,
  });

  @override
  State<_StoryCategoryItem> createState() => _StoryCategoryItemState();
}

class _StoryCategoryItemState extends State<_StoryCategoryItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _borderAnimation;
  
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: AppTheme.microMedium, // 180ms
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.92,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: AppTheme.primaryCurve,
    ));

    _borderAnimation = Tween<double>(
      begin: 0.0,
      end: 3.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: AppTheme.primaryCurve,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _animationController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Container(
            width: widget.width,
            margin: EdgeInsets.only(right: widget.spacing),
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 카테고리 아이콘 컨테이너
                  AnimatedContainer(
                    duration: widget.animationDuration,
                    curve: AppTheme.primaryCurve,
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: widget.category.gradient,
                      borderRadius: BorderRadius.circular(20),
                      border: widget.isSelected ? Border.all(
                        color: Colors.white,
                        width: 3 + _borderAnimation.value,
                      ) : null,
                      boxShadow: [
                        BoxShadow(
                          color: widget.category.gradient.colors.first.withOpacity(
                            widget.isSelected ? 0.4 : 0.2
                          ),
                          blurRadius: widget.isSelected ? 20 : 12,
                          offset: Offset(0, widget.isSelected ? 8 : 4),
                          spreadRadius: widget.isSelected ? 2 : 0,
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.category.icon,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // 카테고리 텍스트
                  AnimatedDefaultTextStyle(
                    duration: widget.animationDuration,
                    curve: AppTheme.primaryCurve,
                    style: AppTheme.labelSmall.copyWith(
                      color: widget.isSelected 
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                      fontWeight: widget.isSelected 
                          ? FontWeight.w700 
                          : FontWeight.w500,
                      fontSize: widget.isSelected ? 13 : 12,
                    ),
                    child: Text(
                      widget.category.title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 카테고리 아이템 데이터 클래스
class CategoryItem {
  /// 카테고리 고유 ID
  final String id;
  
  /// 표시할 제목
  final String title;
  
  /// 카테고리 아이콘
  final IconData icon;
  
  /// 배경 그라디언트
  final LinearGradient gradient;
  
  /// 카테고리 설명 (옵션)
  final String? description;
  
  /// 카테고리 색상 (단일 색상 사용 시)
  final Color? color;

  const CategoryItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.gradient,
    this.description,
    this.color,
  });

  /// 단일 색상으로 그라디언트 생성
  factory CategoryItem.withColor({
    required String id,
    required String title,
    required IconData icon,
    required Color color,
    String? description,
  }) {
    return CategoryItem(
      id: id,
      title: title,
      icon: icon,
      gradient: LinearGradient(
        colors: [
          color,
          color.withOpacity(0.8),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      description: description,
      color: color,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 스토리 카테고리용 간단한 래퍼
class CompactStoryCategories extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String>? onCategoryChanged;

  const CompactStoryCategories({
    super.key,
    required this.categories,
    required this.selectedCategory,
    this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final categoryItems = categories.asMap().entries.map((entry) {
      final index = entry.key;
      final category = entry.value;
      
      return CategoryItem(
        id: category,
        title: category,
        icon: _getCategoryIcon(category),
        gradient: _getCategoryGradient(index),
      );
    }).toList();

    final selectedIndex = categories.indexOf(selectedCategory);

    return StoryCategories(
      categories: categoryItems,
      selectedIndex: selectedIndex >= 0 ? selectedIndex : 0,
      onCategorySelected: (index) {
        if (index >= 0 && index < categories.length) {
          onCategoryChanged?.call(categories[index]);
        }
      },
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case '전체':
        return Icons.grid_view_rounded;
      case '스터디':
        return Icons.school_rounded;
      case '식사':
      case '밥':
        return Icons.restaurant_rounded;
      case '카페':
        return Icons.palette_rounded;
      case '문화':
        return Icons.theater_comedy_rounded;
      case '운동':
        return Icons.fitness_center_rounded;
      case '여행':
        return Icons.flight_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  LinearGradient _getCategoryGradient(int index) {
    final gradients = [
      AppTheme.primaryGradient,
      AppTheme.secondaryGradient,
      AppTheme.emeraldGradient,
      AppTheme.amberGradient,
      LinearGradient(colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)]),
      LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)]),
      LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFEF4444)]),
    ];
    
    return gradients[index % gradients.length];
  }
}

