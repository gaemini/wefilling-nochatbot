import 'package:flutter/material.dart';
import '../models/friend_category.dart';
import '../l10n/app_localizations.dart';

class FriendCategorySelector extends StatelessWidget {
  final List<FriendCategory> categories;
  final List<String> selectedCategoryIds;
  final Function(List<String>) onSelectionChanged;
  final Color selectedColor;
  final Color unselectedBorderColor;

  const FriendCategorySelector({
    super.key,
    required this.categories,
    required this.selectedCategoryIds,
    required this.onSelectionChanged,
    this.selectedColor = const Color(0xFF4A90E2),
    this.unselectedBorderColor = const Color(0xFFE1E6EE),
  });

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

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: categories.map((category) {
        final isSelected = selectedCategoryIds.contains(category.id);
        return InkWell(
          onTap: () {
            final newSelection = List<String>.from(selectedCategoryIds);
            if (isSelected) {
              newSelection.remove(category.id);
            } else {
              newSelection.add(category.id);
            }
            onSelectionChanged(newSelection);
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
                // 선택 여부와 관계없이 아이콘 공간을 확보하여 레이아웃 변경 방지
                Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: isSelected ? Colors.white : Colors.transparent,
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
