import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/post.dart';
import '../../services/cache/app_image_cache_manager.dart';

class ProfileSharingPostCard extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;
  final String? currentUserId;
  final int? commentCountOverride;

  const ProfileSharingPostCard({
    super.key,
    required this.post,
    required this.onTap,
    this.currentUserId,
    this.commentCountOverride,
  });

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = post.imageUrls.isNotEmpty ? post.imageUrls.first : '';
    final title =
        post.title.trim().isNotEmpty ? post.title.trim() : post.content;
    final sharingLocation = post.sharingLocation.trim();
    final commentCount = commentCountOverride ?? post.commentCount;
    final isLiked =
        currentUserId != null && post.likedBy.contains(currentUserId);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 180,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildThumbnail(thumbnailUrl),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                              height: 1.12,
                              letterSpacing: -0.4,
                            ),
                          ),
                          if (sharingLocation.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              sharingLocation,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF374151),
                                height: 1.15,
                              ),
                            ),
                          ],
                          const SizedBox(height: 5),
                          Text(
                            post.getFormattedTime(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF9CA3AF),
                              height: 1.15,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (post.schoolOnly) _buildUnivBadge(),
                              const Spacer(),
                              Flexible(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: _buildMetrics(
                                    isLiked: isLiked,
                                    likes: post.likes,
                                    comments: commentCount,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(height: 1, color: const Color(0xFFE5E7EB)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(String thumbnailUrl) {
    const width = 144.0;
    const height = 170.0;
    return thumbnailUrl.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: thumbnailUrl,
            cacheManager: AppImageCacheManager.instance,
            memCacheWidth: 520,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => _buildImageFallback(width, height),
          )
        : _buildImageFallback(width, height);
  }

  Widget _buildImageFallback(double width, double height) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFE5E7EB),
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Color(0xFF9CA3AF),
      ),
    );
  }

  Widget _buildUnivBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF244BFF),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text(
        'Univ.',
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _buildMetrics({
    required bool isLiked,
    required int likes,
    required int comments,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 18,
            color: const Color(0xFF111827),
          ),
          const SizedBox(width: 3),
          Text(
            '$likes',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.chat_bubble_outline_rounded,
            size: 18,
            color: Color(0xFF111827),
          ),
          const SizedBox(width: 3),
          Text(
            '$comments',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}
