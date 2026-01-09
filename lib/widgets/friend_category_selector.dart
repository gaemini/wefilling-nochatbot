import 'package:flutter/material.dart';
import '../models/friend_category.dart';
import '../l10n/app_localizations.dart';

class FriendCategorySelector extends StatelessWidget {
  final List<FriendCategory> categories;
  final List<String> selectedCategoryIds;
  final Function(List<String>) onSelectionChanged;

  const FriendCategorySelector({
    super.key,
    required this.categories,
    required this.selectedCategoryIds,
    required this.onSelectionChanged,
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
              color: isSelected ? const Color(0xFF4A90E2) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected 
                    ? const Color(0xFF4A90E2) 
                    : const Color(0xFFE1E6EE),
                width: 1.2,
              ),
              boxShadow: isSelected ? [
                BoxShadow(
                  color: const Color(0xFF4A90E2).withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ] : null,
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
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF333333),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${category.friendIds.length}${AppLocalizations.of(context)!.people ?? ''})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: isSelected ? Colors.white.withOpacity(0.9) : const Color(0xFF999999),
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
