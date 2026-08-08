import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/post_category.dart';
import '../../utils/responsive_helper.dart';

IconData _categoryIcon(PostCategory category) {
  return switch (category) {
    PostCategory.style => Icons.checkroom_outlined,
    PostCategory.create => Icons.restaurant_outlined,
    PostCategory.photo => Icons.photo_camera_outlined,
    PostCategory.content => Icons.movie_outlined,
    PostCategory.cafe => Icons.local_cafe_outlined,
    PostCategory.academicStudy => Icons.school_outlined,
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
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await showModalBottomSheet<PostCategory>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
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
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: context.rf(15).clamp(14, 16).toDouble(),
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111827),
          ),
        ),
        SizedBox(height: context.rs(4)),
        Semantics(
          button: true,
          label: l10n.postCategorySelectTitle,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? () => _openPicker(context) : null,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.rs(2),
                  vertical: context.rs(9).clamp(8, 11).toDouble(),
                ),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 32,
                      child: Icon(
                        selectedCategory == null
                            ? Icons.category_outlined
                            : _categoryIcon(selectedCategory),
                        size: context.ri(20).clamp(19, 22).toDouble(),
                        color: enabled
                            ? const Color(0xFF667085)
                            : const Color(0xFFB8C0CC),
                      ),
                    ),
                    SizedBox(width: context.rs(8)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedCategory?.label(l10n) ??
                                l10n.postCategorySelectAction,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: context.rf(15).clamp(14, 16).toDouble(),
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
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize:
                                    context.rf(12).clamp(11, 13).toDouble(),
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: context.ri(21).clamp(20, 23).toDouble(),
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
        Divider(
          height: 1,
          color: showError ? const Color(0xFFDC2626) : const Color(0xFFE5E7EB),
        ),
        if (showError) ...[
          const SizedBox(height: 5),
          Text(
            l10n.postCategoryRequired,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: context.rf(12).clamp(11, 13).toDouble(),
              fontWeight: FontWeight.w700,
              color: const Color(0xFFB91C1C),
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
    final systemBottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              MediaQuery.sizeOf(context).width < 360 ? 12 : 16,
              2,
              MediaQuery.sizeOf(context).width < 360 ? 12 : 16,
              8,
            ),
            child: Text(
              l10n.postCategorySelectTitle,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: context.rf(18).clamp(16, 19).toDouble(),
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width < 360 ? 12 : 16,
                0,
                MediaQuery.sizeOf(context).width < 360 ? 12 : 16,
                16 + systemBottomInset,
              ),
              itemCount: PostCategory.ordered.length,
              itemBuilder: (context, index) {
                final category = PostCategory.ordered[index];
                final isSelected = category == selected;
                return Semantics(
                  selected: isSelected,
                  button: true,
                  child: Column(
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context, category),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: context.rs(2),
                              vertical: context.rs(10).clamp(8, 12).toDouble(),
                            ),
                            child: Row(
                              children: [
                                SizedBox.square(
                                  dimension: 34,
                                  child: Icon(
                                    _categoryIcon(category),
                                    size:
                                        context.ri(20).clamp(19, 22).toDouble(),
                                    color: isSelected
                                        ? const Color(0xFF344054)
                                        : const Color(0xFF667085),
                                  ),
                                ),
                                SizedBox(width: context.rs(8)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        category.label(l10n),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Pretendard',
                                          fontSize: context
                                              .rf(14)
                                              .clamp(13, 15)
                                              .toDouble(),
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF111827),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        category.description(l10n),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Pretendard',
                                          fontSize: context
                                              .rf(12)
                                              .clamp(11, 13)
                                              .toDouble(),
                                          color: const Color(0xFF64748B),
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
                                  size: context.ri(21).clamp(20, 23).toDouble(),
                                  color: isSelected
                                      ? const Color(0xFF344054)
                                      : const Color(0xFFCBD5E1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (index != PostCategory.ordered.length - 1)
                        const Divider(
                          height: 1,
                          indent: 42,
                          color: Color(0xFFEAECF0),
                        ),
                    ],
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
