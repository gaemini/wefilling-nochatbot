import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/post_category.dart';
import '../../widgets/ad_banner_widget.dart';

class PostCategoryExplorer extends StatelessWidget {
  const PostCategoryExplorer({
    super.key,
    required this.onSelected,
    this.scrollController,
    this.advertisement,
  });

  final ValueChanged<PostCategory> onSelected;
  final ScrollController? scrollController;
  final Widget? advertisement;

  static IconData iconFor(PostCategory category) {
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360 ? 16.0 : 20.0;
    final columns = width >= 720 ? 3 : 2;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final cardExtent = 124.0 + ((textScale - 1).clamp(0, 2) * 36);

    return CustomScrollView(
      key: const PageStorageKey('board_all_category_explorer'),
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            DesignTokens.s16,
            horizontalPadding,
            0,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: cardExtent,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final category = PostCategory.ordered[index];
                return _CategoryTile(
                  category: category,
                  onTap: () => onSelected(category),
                );
              },
              childCount: PostCategory.ordered.length,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(top: DesignTokens.s20),
          sliver: SliverToBoxAdapter(
            child: advertisement ??
                const AdBannerWidget(
                  key: ValueKey('board_banner_all_categories'),
                  widgetId: 'board_banner_all',
                ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final PostCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = category.label(l10n);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: BrandColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.r12),
          side: const BorderSide(color: BrandColors.divider),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesignTokens.r12),
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  PostCategoryExplorer.iconFor(category),
                  color: AppColors.pointColor,
                  size: 24,
                ),
                const Spacer(),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: DesignTokens.s4),
                Text(
                  category.description(l10n),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: BrandColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
