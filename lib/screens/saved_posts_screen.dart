// lib/screens/saved_posts_screen.dart
// 설정에서 접근하는 '저장된 게시글' 목록 화면

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../services/post_service.dart';
import '../services/post_media_prefetch_service.dart';
import '../services/cache/app_image_cache_manager.dart';
import '../l10n/app_localizations.dart';
import '../ui/widgets/user_avatar.dart';
import '../utils/responsive_helper.dart';
import 'post_detail_screen.dart';

class SavedPostsScreen extends StatefulWidget {
  const SavedPostsScreen({Key? key}) : super(key: key);

  @override
  State<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends State<SavedPostsScreen> {
  final PostService _postService = PostService();
  final PostMediaPrefetchService _postMediaPrefetch =
      PostMediaPrefetchService.instance;

  Future<void> _openPostDetail(String postId) async {
    try {
      final fetched = await _postService.getPostById(postId);
      if (!mounted) return;

      if (fetched == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.postNotFound ?? "")),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PostDetailScreen(post: fetched),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = Provider.of<AuthProvider>(context);
    final isLoggedIn =
        authProvider.user?.uid != null && (authProvider.user!.uid).isNotEmpty;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: context.rh(56, min: 54, max: 60),
        leadingWidth: 48,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: const Color(0xFF111827),
            size: context.ri(22).clamp(21, 24).toDouble(),
          ),
          onPressed: () => Navigator.pop(context),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        ),
        title: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Text(
            isKo ? '저장된 게시글' : 'Saved Posts',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
      body: SafeArea(
        top: false,
        child: !isLoggedIn
            ? _buildStateMessage(
                icon: Icons.login_rounded,
                title: l10n.loginRequired,
                description: l10n.loginToViewSavedPosts,
              )
            : StreamBuilder<List<Post>>(
                stream: _postService.getSavedPosts(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2E90FA),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return _buildStateMessage(
                      icon: Icons.error_outline_rounded,
                      title: l10n.error,
                    );
                  }

                  final savedPosts = snapshot.data ?? [];
                  if (savedPosts.isEmpty) {
                    return _buildStateMessage(
                      icon: Icons.bookmark_border_rounded,
                      title: l10n.noSavedPosts,
                      description: l10n.saveInterestingPosts,
                    );
                  }
                  unawaited(
                    _postMediaPrefetch.prefetchPosts(savedPosts, maxPosts: 6),
                  );

                  return MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                _horizontalPadding,
                                10,
                                _horizontalPadding,
                                6,
                              ),
                              child: Text(
                                isKo
                                    ? '저장한 글 ${savedPosts.length}개'
                                    : '${savedPosts.length} saved ${savedPosts.length == 1 ? 'post' : 'posts'}',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: ['NotoSansKR'],
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF667085),
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView.separated(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                scrollCacheExtent:
                                    const ScrollCacheExtent.viewport(1),
                                padding: EdgeInsets.fromLTRB(
                                  _horizontalPadding,
                                  2,
                                  _horizontalPadding,
                                  18,
                                ),
                                itemCount: savedPosts.length,
                                separatorBuilder: (_, __) => const Divider(
                                  height: 1,
                                  color: Color(0xFFF1F3F5),
                                ),
                                itemBuilder: (context, index) =>
                                    _buildSavedPostItem(
                                  savedPosts[index],
                                  l10n,
                                  isKo,
                                ),
                              ),
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

  double get _horizontalPadding {
    final width = MediaQuery.sizeOf(context).width;
    return width < 360 ? 14 : (width < 430 ? 16 : 20);
  }

  Widget _buildStateMessage({
    required IconData icon,
    required String title,
    String? description,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: const Color(0xFF667085)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(17).clamp(16, 19).toDouble(),
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827),
              ),
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 14,
                  color: Color(0xFF667085),
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSavedPostItem(
    Post post,
    AppLocalizations l10n,
    bool isKo,
  ) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final thumbnailSize = screenWidth < 360
        ? 88.0
        : screenWidth < 430
            ? 98.0
            : 108.0;
    final thumbnailUrl = _thumbnailUrl(post);
    final authorName = post.isAnonymous ? l10n.anonymous : post.author;
    final categories = post.postCategories
        .map((category) => '#${category.label(l10n)}')
        .join('  ');

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _openPostDetail(post.id),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: context.rs(14).clamp(12, 16).toDouble(),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (thumbnailUrl.isNotEmpty) ...[
                _buildThumbnail(post, thumbnailUrl, thumbnailSize),
                SizedBox(width: context.rs(12).clamp(10, 14).toDouble()),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        UserAvatar(
                          uid: post.userId,
                          photoUrl: post.authorPhotoURL,
                          photoVersion: 0,
                          isAnonymous: post.isAnonymous,
                          size: 22,
                          placeholderIconSize: 13,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: ['NotoSansKR'],
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475467),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          post.getFormattedTime(context),
                          maxLines: 1,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: ['NotoSansKR'],
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF98A2B3),
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.bookmark_rounded,
                          size: 19,
                          color: Color(0xFF2E90FA),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      post.displayText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(15).clamp(14, 16).toDouble(),
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827),
                        height: 1.35,
                        letterSpacing: -0.15,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        if (post.type == 'poll') ...[
                          Icon(
                            Icons.poll_outlined,
                            size: 14,
                            color: const Color(0xFF2E90FA),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isKo ? '투표' : 'Poll',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: ['NotoSansKR'],
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2E90FA),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            categories,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: ['NotoSansKR'],
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2E90FA),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _buildMetric(
                          Icons.favorite_border_rounded,
                          _compactCount(post.likes),
                          isKo ? '좋아요' : 'Likes',
                        ),
                        _buildMetric(
                          Icons.mode_comment_outlined,
                          _compactCount(post.commentCount),
                          isKo ? '댓글' : 'Comments',
                        ),
                        _buildMetric(
                          Icons.visibility_outlined,
                          _compactCount(post.viewCount),
                          isKo ? '조회수' : 'Views',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(Post post, String url, double size) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final memorySize = (size * pixelRatio).round().clamp(160, 480);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: url,
              cacheManager: AppImageCacheManager.instance,
              memCacheWidth: memorySize,
              maxWidthDiskCache: 640,
              maxHeightDiskCache: 640,
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (_, __) => const ColoredBox(
                color: Color(0xFFF2F4F7),
              ),
              errorWidget: (_, __, ___) => const ColoredBox(
                color: Color(0xFFF2F4F7),
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: Color(0xFF98A2B3),
                  size: 24,
                ),
              ),
            ),
            if (post.imageUrls.length > 1)
              Positioned(
                right: 5,
                bottom: 5,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xB3111827),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${post.imageUrls.length}',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(IconData icon, String value, String label) {
    return Semantics(
      label: '$label $value',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF667085)),
          const SizedBox(width: 3),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: ['NotoSansKR'],
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF667085),
            ),
          ),
        ],
      ),
    );
  }

  String _thumbnailUrl(Post post) {
    for (final url in post.imageUrls) {
      final trimmed = url.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return post.linkPreview?.thumbnailUrl.trim() ?? '';
  }

  String _compactCount(int value) {
    if (value < 1000) return '$value';
    if (value < 1000000) {
      final number = value / 1000;
      return '${number >= 10 ? number.toStringAsFixed(0) : number.toStringAsFixed(1)}K';
    }
    final number = value / 1000000;
    return '${number >= 10 ? number.toStringAsFixed(0) : number.toStringAsFixed(1)}M';
  }
}
