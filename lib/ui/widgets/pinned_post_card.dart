// lib/ui/widgets/pinned_post_card.dart
// "스낵챗에서 이어가기"로 열린 방 상단에 고정되는 포스트 카드.
// 메시지 타입을 새로 만들지 않고, 방 문서의 postId로 포스트를 읽어 그린다.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../l10n/ui_locale.dart';
import '../../models/post.dart';
import '../../screens/post_detail_screen.dart';
import '../../services/cache/app_image_cache_manager.dart';
import '../../services/post_service.dart';

const Color _kInk = Color(0xFF000000);
const Color _kInkTertiary = Color(0xFF707070);
const Color _kFillSubtle = Color(0xFFEEEEEE);
const Color _kHairline = Color(0xFFEBEBEB);

class PinnedPostCard extends StatefulWidget {
  const PinnedPostCard({super.key, required this.postId});

  final String postId;

  @override
  State<PinnedPostCard> createState() => _PinnedPostCardState();
}

class _PinnedPostCardState extends State<PinnedPostCard> {
  late Future<Post?> _post;

  @override
  void initState() {
    super.initState();
    _post = _load();
  }

  @override
  void didUpdateWidget(covariant PinnedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId) _post = _load();
  }

  // getPostById는 삭제·권한 없음·차단·숨김을 모두 null로 돌려준다.
  Future<Post?> _load() =>
      PostService().getPostById(widget.postId).catchError((_) => null);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Post?>(
      future: _post,
      builder: (context, snapshot) {
        final post = snapshot.data;
        if (post == null || post.isAnonymous) return const SizedBox.shrink();
        final thumbnail =
            post.imageUrls.isEmpty ? '' : post.imageUrls.first.trim();
        final title = post.content
            .split('\n')
            .map((line) => line.trim())
            .firstWhere((line) => line.isNotEmpty, orElse: () => post.title);
        final textStyle = TextStyle(
          fontFamily: uiFontFamily(context, 'Inter'),
          fontFamilyFallback: const ['NotoSansKR'],
        );
        return Material(
          key: const ValueKey('snack-chat-pinned-post'),
          color: Colors.white,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _kHairline)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 40,
                      height: 40,
                      color: _kFillSubtle,
                      child: thumbnail.startsWith('http')
                          ? CachedNetworkImage(
                              imageUrl: thumbnail,
                              cacheManager: AppImageCacheManager.instance,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            )
                          : const Icon(
                              Icons.article_outlined,
                              size: 18,
                              color: _kInkTertiary,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _kInk,
                          ),
                        ),
                        Text(
                          post.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle.copyWith(
                            fontSize: 12,
                            color: _kInkTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: _kInkTertiary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
