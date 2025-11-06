// lib/ui/widgets/compact_header.dart
// 첫 화면 콘텐츠 노출 극대화를 위한 컴팩트 헤더
// 44-48dp 검색바, 32-36dp 카테고리 칩, 최소 상단 패딩

import 'package:flutter/material.dart';
import '../../design/tokens.dart';
import '../../utils/accessibility_utils.dart';
import '../../l10n/app_localizations.dart';
import 'app_icon_button.dart';

/// 컴팩트 검색바
/// 높이: 44-48dp, 상단 패딩: 8-12dp
class CompactSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final VoidCallback? onSearchPressed;
  final VoidCallback? onClearPressed;
  final ValueChanged<String>? onChanged;
  final bool showClearButton;
  final bool enabled;
  final Widget? leading;
  final List<Widget>? actions;

  const CompactSearchBar({
    super.key,
    this.controller,
    this.hintText = '검색',
    this.onSearchPressed,
    this.onClearPressed,
    this.onChanged,
    this.showClearButton = false,
    this.enabled = true,
    this.leading,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 텍스트 스케일에 따른 패딩 조정
    final adjustedPadding = context.adjustedPadding(
      const EdgeInsets.only(
        top: DesignTokens.s8, // 8dp 상단 패딩 (최소화)
        left: DesignTokens.s12,
        right: DesignTokens.s12,
        bottom: DesignTokens.s8,
      ),
    );

    return Container(
      padding: adjustedPadding,
      child: Row(
        children: [
          // 선택적 leading 위젯
          if (leading != null) ...[
            leading!,
            const SizedBox(width: DesignTokens.s8),
          ],

          // 검색바
          Expanded(
            child: Container(
              height: 44, // 44dp 고정 높이
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.7),
                borderRadius: BorderRadius.circular(DesignTokens.r16),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.2),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  // 검색 아이콘
                  Padding(
                    padding: const EdgeInsets.only(left: DesignTokens.s12),
                    child: Icon(
                      Icons.search,
                      size: 20, // 컴팩트 크기
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),

                  // 접근성이 개선된 텍스트 필드
                  Expanded(
                    child: Semantics(
                      label: hintText,
                      hint: '검색어를 입력하세요',
                      textField: true,
                      child: TextField(
                        controller: controller,
                        onChanged: onChanged,
                        enabled: enabled,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height:
                              context.isLargeTextScale
                                  ? 1.4
                                  : 1.2, // 큰 텍스트 스케일 고려
                          color: AccessibilityUtils.ensureAccessibleColor(
                            foreground:
                                theme.textTheme.bodyMedium?.color ??
                                colorScheme.onSurface,
                            background: colorScheme.surfaceVariant,
                            fallbackForeground: colorScheme.onSurface,
                          ),
                        ),
                        decoration: InputDecoration(
                          hintText: hintText,
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: AccessibilityUtils.ensureAccessibleColor(
                              foreground: colorScheme.onSurfaceVariant
                                  .withOpacity(0.7),
                              background: colorScheme.surfaceVariant,
                              fallbackForeground: colorScheme.onSurfaceVariant,
                            ),
                            height: context.isLargeTextScale ? 1.4 : 1.2,
                          ),
                          border: InputBorder.none,
                          contentPadding: context.adjustedPadding(
                            const EdgeInsets.symmetric(
                              horizontal: DesignTokens.s8,
                              vertical: 0, // 세로 패딩 최소화
                            ),
                          ),
                          isDense: true, // 컴팩트 모드
                        ),
                      ),
                    ),
                  ),

                  // 지우기 버튼
                  if (showClearButton)
                    Padding(
                      padding: const EdgeInsets.only(right: DesignTokens.s4),
                      child: AppIconButton(
                        icon: Icons.clear,
                        onPressed: onClearPressed,
                        semanticLabel: '검색어 지우기',
                        iconColor: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 선택적 actions
          if (actions != null) ...[
            const SizedBox(width: DesignTokens.s8),
            ...actions!,
          ],
        ],
      ),
    );
  }
}

/// 컴팩트 카테고리 칩 목록
/// 높이: 32-36dp, 페이드 인디케이터 포함
class CompactCategoryChips extends StatefulWidget {
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String>? onCategoryChanged;
  final EdgeInsets padding;

  const CompactCategoryChips({
    super.key,
    required this.categories,
    required this.selectedCategory,
    this.onCategoryChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
  });

  @override
  State<CompactCategoryChips> createState() => _CompactCategoryChipsState();
}

class _CompactCategoryChipsState extends State<CompactCategoryChips> {
  final ScrollController _scrollController = ScrollController();
  bool _showStartFade = false;
  bool _showEndFade = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateFadeIndicators);
    // 첫 프레임 후 페이드 상태 업데이트
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateFadeIndicators();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateFadeIndicators);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateFadeIndicators() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    setState(() {
      _showStartFade = position.pixels > 20;
      _showEndFade = position.pixels < position.maxScrollExtent - 20;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 52, // 칩 + 패딩 포함 전체 높이 (약간 증가)
      child: Stack(
        children: [
          // 스크롤 가능한 칩 목록
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: widget.padding,
              child: Row(
                children:
                    widget.categories.asMap().entries.map((entry) {
                      final index = entry.key;
                      final category = entry.value;
                      final isSelected = category == widget.selectedCategory;

                      return Padding(
                        padding: EdgeInsets.only(
                          right:
                              index < widget.categories.length - 1
                                  ? DesignTokens.s8
                                  : 0,
                        ),
                        child: _CompactChip(
                          label: category,
                          isSelected: isSelected,
                          onTap: () => widget.onCategoryChanged?.call(category),
                        ),
                      );
                    }).toList(),
              ),
            ),
          ),

          // 시작 페이드 인디케이터
          if (_showStartFade)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 20,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      colorScheme.surface,
                      colorScheme.surface.withOpacity(0),
                    ],
                  ),
                ),
              ),
            ),

          // 끝 페이드 인디케이터
          if (_showEndFade)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 20,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [
                      colorScheme.surface,
                      colorScheme.surface.withOpacity(0),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 개별 컴팩트 칩
class _CompactChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  const _CompactChip({
    required this.label,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // 라벨 번역
    String displayLabel = _getLocalizedLabel(context, label);

    // 텍스트 스케일에 따른 높이 조정
    final adjustedHeight = context.adjustedHeight(32.0);
    final adjustedPadding = context.adjustedPadding(
      const EdgeInsets.symmetric(
        horizontal: DesignTokens.s12,
        vertical: DesignTokens.s4,
      ),
    );

    // 접근성을 고려한 색상 선택 (그라데이션 적용)
    final backgroundColor =
        isSelected
            ? null // 그라데이션 사용 시 null
            : colorScheme.surfaceVariant.withOpacity(0.5);
    final gradient = isSelected
        ? LinearGradient(
            colors: [
              const Color(0xFF4A90E2), // Primary
              const Color(0xFF7DD3FC), // Secondary
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : null;
    final textColor = AccessibilityUtils.ensureAccessibleColor(
      foreground:
          isSelected ? Colors.white : colorScheme.onSurfaceVariant,
      background: isSelected ? const Color(0xFF4A90E2) : (backgroundColor ?? colorScheme.surfaceVariant),
      fallbackForeground: isSelected ? Colors.white : colorScheme.onSurface,
    );

    return Semantics(
      label: '$displayLabel ${AppLocalizations.of(context)!.category}${isSelected ? ", ${AppLocalizations.of(context)!.selected}" : ""}',
      button: true,
      selected: isSelected,
      onTapHint: '${isSelected ? (AppLocalizations.of(context)!.cancel ?? "") : AppLocalizations.of(context)!.select}',
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          gradient: gradient,
          borderRadius: BorderRadius.circular(12), // 12px 둥근 모서리
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap:
                onTap != null
                    ? () {
                      context.accessibleFeedback(
                        HapticFeedbackType.selectionClick,
                      );
                      onTap!();
                    }
                    : null,
            borderRadius: BorderRadius.circular(12),
            splashColor: colorScheme.primary.withOpacity(0.12),
            highlightColor: colorScheme.primary.withOpacity(0.08),
            child: Container(
              height:
                  context.isLargeTextScale
                      ? null
                      : adjustedHeight, // 큰 텍스트에서는 유연한 높이
              constraints: BoxConstraints(minHeight: adjustedHeight),
              padding: adjustedPadding,
              child: Center(
                child: Text(
                  displayLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: textColor,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    height: context.isLargeTextScale ? 1.3 : 1.0,
                  ),
                  maxLines: context.isLargeTextScale ? 2 : 1, // 큰 텍스트에서는 2줄 허용
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 컴팩트 카드 레이아웃
/// 외부 마진 s12-s16, 내부 패딩 s12-s16, 요소 간 s8
class CompactCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? margin;
  final EdgeInsets? padding;
  final Color? backgroundColor;
  final bool elevated;

  const CompactCard({
    super.key,
    required this.child,
    this.onTap,
    this.margin,
    this.padding,
    this.backgroundColor,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final effectiveMargin =
        margin ??
        const EdgeInsets.symmetric(
          horizontal: DesignTokens.s12,
          vertical: DesignTokens.s8, // 세로 마진 최소화
        );

    final effectivePadding = padding ?? const EdgeInsets.all(DesignTokens.s12);

    return Container(
      margin: effectiveMargin,
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.surface,
        borderRadius: BorderRadius.circular(DesignTokens.r16),
        boxShadow:
            elevated ? DesignTokens.shadowMedium : DesignTokens.shadowLight,
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DesignTokens.r16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesignTokens.r16),
          child: Padding(padding: effectivePadding, child: child),
        ),
      ),
    );
  }
}

/// 컴팩트 앱바 (최소 높이)
class CompactAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double elevation;

  const CompactAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppBar(
      title: title != null ? Text(title!) : null,
      actions: actions,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: backgroundColor ?? colorScheme.surface,
      foregroundColor: foregroundColor ?? colorScheme.onSurface,
      elevation: elevation,
      toolbarHeight: 48, // 최소 높이로 설정
      titleSpacing: DesignTokens.s12,
      titleTextStyle: theme.textTheme.titleMedium?.copyWith(
        color: foregroundColor ?? colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(48);
}

/// 카테고리 라벨을 번역하는 헬퍼 함수
String _getLocalizedLabel(BuildContext context, String label) {
  final localizations = AppLocalizations.of(context)!;
  
  switch (label) {
    case 'all':
      return localizations.all;
    case 'study':
      return localizations.study;
    case 'meal':
      return localizations.meal;
    case 'hobby':
      return localizations.hobby;
    case 'culture':
      return localizations.culture;
    case 'other':
      return localizations.other;
    default:
      return label; // 번역이 없으면 원본 반환
  }
}
