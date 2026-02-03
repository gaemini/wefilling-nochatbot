import 'package:flutter/material.dart';
import '../models/friend_category.dart';
import '../l10n/app_localizations.dart';

enum FriendCategorySelectorStyle { chips, list }

class FriendCategorySelector extends StatelessWidget {
  final List<FriendCategory> categories;
  final List<String> selectedCategoryIds;
  final Function(List<String>) onSelectionChanged;
  final Color selectedColor;
  final Color unselectedBorderColor;
  final FriendCategorySelectorStyle style;

  const FriendCategorySelector({
    super.key,
    required this.categories,
    required this.selectedCategoryIds,
    required this.onSelectionChanged,
    this.selectedColor = const Color(0xFF4A90E2),
    this.unselectedBorderColor = const Color(0xFFE1E6EE),
    this.style = FriendCategorySelectorStyle.chips,
  });

  void _toggle(String id) {
    final newSelection = List<String>.from(selectedCategoryIds);
    if (newSelection.contains(id)) {
      newSelection.remove(id);
    } else {
      newSelection.add(id);
    }
    onSelectionChanged(newSelection);
  }

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          AppLocalizations.of(context)!.noFriendGroupsYet,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
      );
    }

    if (style == FriendCategorySelectorStyle.list) {
      return Column(
        children: [
          for (int i = 0; i < categories.length; i++) ...[
            _CategoryListItem(
              category: categories[i],
              isSelected: selectedCategoryIds.contains(categories[i].id),
              selectedColor: selectedColor,
              unselectedBorderColor: unselectedBorderColor,
              peopleLabel: AppLocalizations.of(context)!.people ?? '',
              onTap: () => _toggle(categories[i].id),
            ),
            if (i != categories.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: categories.map((category) {
        final isSelected = selectedCategoryIds.contains(category.id);
        return InkWell(
          onTap: () {
            _toggle(category.id);
          },
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? selectedColor : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected 
                    ? selectedColor 
                    : unselectedBorderColor,
                width: 1.2,
              ),
              // 다른 화면들과 톤 통일: 플랫(그림자 제거)
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 왼쪽에 "선택 시스템"이 보이도록 미선택도 아이콘 노출
                Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: isSelected ? Colors.white : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 6),
                Text(
                  category.name,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF111827),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${category.friendIds.length}${AppLocalizations.of(context)!.people ?? ''})',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white.withOpacity(0.9) : const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CategoryListItem extends StatelessWidget {
  final FriendCategory category;
  final bool isSelected;
  final Color selectedColor;
  final Color unselectedBorderColor;
  final String peopleLabel;
  final VoidCallback onTap;

  const _CategoryListItem({
    required this.category,
    required this.isSelected,
    required this.selectedColor,
    required this.unselectedBorderColor,
    required this.peopleLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isSelected ? selectedColor.withOpacity(0.10) : Colors.white;
    final border = isSelected ? selectedColor : unselectedBorderColor;
    final textColor = isSelected ? const Color(0xFF111827) : const Color(0xFF111827);
    final subColor = isSelected ? const Color(0xFF374151) : const Color(0xFF6B7280);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: isSelected ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: isSelected ? selectedColor : const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.name,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '(${category.friendIds.length}$peopleLabel)',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: subColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
