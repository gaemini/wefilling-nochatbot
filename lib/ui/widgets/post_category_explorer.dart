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

  static String? backgroundAssetFor(PostCategory category) {
    return switch (category) {
      PostCategory.style => 'assets/images/post_categories/style.png',
      PostCategory.create => 'assets/images/post_categories/restaurant.png',
      PostCategory.photo => 'assets/images/post_categories/photo.png',
      PostCategory.content => 'assets/images/post_categories/content.png',
      PostCategory.cafe => 'assets/images/post_categories/cafe.png',
      PostCategory.academicStudy => 'assets/images/post_categories/study.png',
      PostCategory.booksWriting => 'assets/images/post_categories/books.png',
      PostCategory.travelLocal => 'assets/images/post_categories/travel.png',
      PostCategory.global => 'assets/images/post_categories/global.png',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaWidth = MediaQuery.sizeOf(context).width;
        final width =
            constraints.maxWidth.isFinite && constraints.maxWidth < mediaWidth
                ? constraints.maxWidth
                : mediaWidth;
        final isCompact = width < 360;
        final isExpanded = width >= 600;
        final horizontalPadding = isCompact ? 10.0 : (isExpanded ? 16.0 : 12.0);
        final columns = isExpanded ? 3 : 2;
        final effectiveTextScale =
            MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.25);
        final baseCardExtent = isCompact ? 140.0 : (isExpanded ? 148.0 : 144.0);
        final cardExtent = baseCardExtent + ((effectiveTextScale - 1) * 24);
        final tilePadding = isCompact ? 12.0 : (isExpanded ? 16.0 : 14.0);
        final iconSize = isCompact ? 21.0 : (isExpanded ? 24.0 : 22.0);
        final titleSize = isCompact ? 14.0 : (isExpanded ? 16.0 : 15.0);
        final descriptionSize = isCompact ? 11.0 : (isExpanded ? 12.0 : 11.5);

        return CustomScrollView(
          key: const PageStorageKey('board_all_category_explorer'),
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                DesignTokens.s12,
                horizontalPadding,
                0,
              ),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: cardExtent,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final category = PostCategory.ordered[index];
                    return PostCategoryTile(
                      category: category,
                      contentPadding: tilePadding,
                      iconSize: iconSize,
                      titleSize: titleSize,
                      descriptionSize: descriptionSize,
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
      },
    );
  }
}

class PostCategoryTile extends StatelessWidget {
  const PostCategoryTile({
    super.key,
    required this.category,
    required this.contentPadding,
    required this.iconSize,
    required this.titleSize,
    required this.descriptionSize,
    required this.onTap,
  });

  final PostCategory category;
  final double contentPadding;
  final double iconSize;
  final double titleSize;
  final double descriptionSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = category.label(l10n);
    final backgroundAsset = PostCategoryExplorer.backgroundAssetFor(category);
    final foregroundColor =
        backgroundAsset == null ? BrandColors.textPrimary : Colors.white;
    final secondaryForegroundColor =
        backgroundAsset == null ? BrandColors.textSecondary : Colors.white;
    final iconColor =
        backgroundAsset == null ? AppColors.pointColor : Colors.white;

    final standardContent = MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: Padding(
        padding: EdgeInsets.all(contentPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              PostCategoryExplorer.iconFor(category),
              color: iconColor,
              size: iconSize,
            ),
            const Spacer(),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: titleSize,
                fontWeight: FontWeight.w800,
                color: foregroundColor,
                height: 1.2,
              ),
            ),
            const SizedBox(height: DesignTokens.s4),
            Text(
              category.description(l10n),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: descriptionSize,
                fontWeight: FontWeight.w500,
                color: secondaryForegroundColor,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );

    final inkWell = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.r12),
      child: standardContent,
    );

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: BrandColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.r12),
          side: const BorderSide(color: BrandColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: backgroundAsset == null
            ? inkWell
            : Ink.image(
                key: ValueKey('post_category_background_${category.key}'),
                image: AssetImage(backgroundAsset),
                fit: BoxFit.cover,
                child: inkWell,
              ),
      ),
    );
  }
}
