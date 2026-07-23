import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../l10n/app_localizations.dart';
import '../../models/post_category.dart';

IconData _categoryIcon(PostCategory category) {
  return switch (category) {
    PostCategory.style => Icons.checkroom_outlined,
    PostCategory.create => Icons.draw_outlined,
    PostCategory.photo => Icons.photo_camera_outlined,
    PostCategory.content => Icons.movie_outlined,
    PostCategory.cafe => Icons.local_cafe_outlined,
    PostCategory.booksWriting => Icons.auto_stories_outlined,
    PostCategory.travelLocal => Icons.explore_outlined,
    PostCategory.global => Icons.public_outlined,
    PostCategory.other => Icons.more_horiz_rounded,
  };
}

class PostCategorySelector extends StatelessWidget {
  const PostCategorySelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.showError = false,
  });

  final PostCategory? selected;
  final ValueChanged<PostCategory> onChanged;
  final bool enabled;
  final bool showError;

  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<PostCategory>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFF8FAFC),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _PostCategorySheet(selected: selected),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selectedCategory = selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.postCategorySelectTitle,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          button: true,
          label: l10n.postCategorySelectTitle,
          child: Material(
            color: enabled ? const Color(0xFFF8FAFC) : const Color(0xFFF3F4F6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: showError
                    ? const Color(0xFFDC2626)
                    : selectedCategory == null
                        ? const Color(0xFFE5E7EB)
                        : AppColors.pointColor,
                width: selectedCategory == null ? 1 : 1.4,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? () => _openPicker(context) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: selectedCategory == null
                            ? const Color(0xFFEFF2F6)
                            : const Color(0xFFEAF4FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        selectedCategory == null
                            ? Icons.category_outlined
                            : _categoryIcon(selectedCategory),
                        size: 22,
                        color: selectedCategory == null
                            ? const Color(0xFF64748B)
                            : AppColors.pointColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedCategory?.label(l10n) ??
                                l10n.postCategorySelectAction,
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: selectedCategory == null
                                  ? const Color(0xFF475569)
                                  : const Color(0xFF111827),
                            ),
                          ),
                          if (selectedCategory != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              selectedCategory.description(l10n),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: enabled
                          ? const Color(0xFF64748B)
                          : const Color(0xFFCBD5E1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showError) ...[
          const SizedBox(height: 6),
          Text(
            l10n.postCategoryRequired,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB91C1C),
            ),
          ),
        ],
      ],
    );
  }
}

class _PostCategorySheet extends StatelessWidget {
  const _PostCategorySheet({required this.selected});

  final PostCategory? selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              l10n.postCategorySelectTitle,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              itemCount: PostCategory.ordered.length,
              itemBuilder: (context, index) {
                final category = PostCategory.ordered[index];
                final isSelected = category == selected;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Semantics(
                    selected: isSelected,
                    button: true,
                    child: Material(
                      color:
                          isSelected ? const Color(0xFFEAF4FF) : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isSelected
                              ? AppColors.pointColor
                              : const Color(0xFFE5E7EB),
                          width: isSelected ? 1.4 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.pop(context, category),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  _categoryIcon(category),
                                  size: 21,
                                  color: isSelected
                                      ? AppColors.pointColor
                                      : const Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      category.label(l10n),
                                      style: const TextStyle(
                                        fontFamily: 'Pretendard',
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      category.description(l10n),
                                      style: const TextStyle(
                                        fontFamily: 'Pretendard',
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.chevron_right_rounded,
                                size: 22,
                                color: isSelected
                                    ? AppColors.pointColor
                                    : const Color(0xFFCBD5E1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
