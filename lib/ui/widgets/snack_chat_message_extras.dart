import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../../models/snack_chat_message.dart';
import '../../services/cache/app_image_cache_manager.dart';

class SnackChatStorageImage extends StatefulWidget {
  const SnackChatStorageImage({
    super.key,
    required this.storagePath,
    this.fit = BoxFit.contain,
    this.imageBuilder,
    this.loading,
    this.error,
  });

  final String storagePath;
  final BoxFit fit;
  final ImageWidgetBuilder? imageBuilder;
  final Widget? loading;
  final Widget? error;

  @override
  State<SnackChatStorageImage> createState() => _SnackChatStorageImageState();
}

class _SnackChatStorageImageState extends State<SnackChatStorageImage> {
  static const int _maxBytes = 15 * 1024 * 1024;
  static final Map<String, Future<Uint8List?>> _memoryRequests =
      <String, Future<Uint8List?>>{};
  late Future<Uint8List?> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _load(widget.storagePath);
  }

  @override
  void didUpdateWidget(covariant SnackChatStorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath) {
      _bytes = _load(widget.storagePath);
    }
  }

  Future<Uint8List?> _load(String path) {
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    if (viewerId == null || viewerId.isEmpty) {
      return Future<Uint8List?>.value(null);
    }
    final requestKey = '$viewerId::$path';
    if (!_memoryRequests.containsKey(requestKey) &&
        _memoryRequests.length >= 4) {
      _memoryRequests.remove(_memoryRequests.keys.first);
    }
    return _memoryRequests.putIfAbsent(
      requestKey,
      () async {
        try {
          final data = await FirebaseStorage.instance
              .ref(path)
              .getData(_maxBytes)
              .timeout(const Duration(seconds: 15));
          if (data == null || data.isEmpty) {
            _memoryRequests.remove(requestKey);
            return null;
          }
          return data;
        } catch (_) {
          _memoryRequests.remove(requestKey);
          return null;
        }
      },
    );
  }

  void _retry() {
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    if (viewerId != null) {
      _memoryRequests.remove('$viewerId::${widget.storagePath}');
    }
    setState(() => _bytes = _load(widget.storagePath));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data != null) {
          final imageProvider = MemoryImage(data);
          return widget.imageBuilder?.call(context, imageProvider) ??
              Image(
                image: imageProvider,
                fit: widget.fit,
                gaplessPlayback: true,
              );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.loading ??
              const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            widget.error ??
                const Center(child: Icon(Icons.broken_image_outlined)),
            Center(
              child: SizedBox.square(
                dimension: 32,
                child: IconButton(
                  onPressed: _retry,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  tooltip: '이미지 다시 불러오기',
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Sizes a Snack Chat image from its decoded aspect ratio instead of placing
/// every attachment inside the same fixed rectangle.
class SnackChatAdaptiveImage extends StatefulWidget {
  const SnackChatAdaptiveImage({
    super.key,
    required this.imageProvider,
    required this.maxWidth,
    required this.maxHeight,
    this.error,
  });

  final ImageProvider imageProvider;
  final double maxWidth;
  final double maxHeight;
  final Widget? error;

  @override
  State<SnackChatAdaptiveImage> createState() => _SnackChatAdaptiveImageState();
}

class _SnackChatAdaptiveImageState extends State<SnackChatAdaptiveImage>
    with SingleTickerProviderStateMixin {
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  double? _aspectRatio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant SnackChatAdaptiveImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) {
      _aspectRatio = null;
      _resolveImage();
    }
  }

  void _resolveImage() {
    final stream = widget.imageProvider.resolve(
      createLocalImageConfiguration(context),
    );
    if (stream.key == _imageStream?.key) return;

    _detachImageListener();
    _imageStream = stream;
    _imageStreamListener = ImageStreamListener(
      (image, synchronousCall) {
        final width = image.image.width.toDouble();
        final height = image.image.height.toDouble();
        if (width <= 0 || height <= 0 || !mounted) return;
        final ratio = width / height;
        if (_aspectRatio == ratio) return;
        if (synchronousCall) {
          _aspectRatio = ratio;
        } else {
          setState(() => _aspectRatio = ratio);
        }
      },
    );
    stream.addListener(_imageStreamListener!);
  }

  void _detachImageListener() {
    final stream = _imageStream;
    final listener = _imageStreamListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageStream = null;
    _imageStreamListener = null;
  }

  Size _displaySize() {
    // Use a compact loading frame, then animate to the decoded image ratio.
    final ratio = _aspectRatio ?? 4 / 3;
    final boundsRatio = widget.maxWidth / widget.maxHeight;
    if (ratio >= boundsRatio) {
      return Size(widget.maxWidth, widget.maxWidth / ratio);
    }
    return Size(widget.maxHeight * ratio, widget.maxHeight);
  }

  @override
  void dispose() {
    _detachImageListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = _displaySize();
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      alignment: Alignment.center,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Image(
          image: widget.imageProvider,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              widget.error ??
              const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }
}

class SnackChatReplyPreviewView extends StatelessWidget {
  const SnackChatReplyPreviewView({
    super.key,
    required this.preview,
    required this.isOutgoing,
    this.onTap,
  });

  final ReplyMessagePreview preview;
  final bool isOutgoing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = isOutgoing
        ? Colors.white.withValues(alpha: 0.82)
        : const Color(0xFF475467);
    final fileExpired = preview.type == SnackChatMessageType.file &&
        preview.fileExpiresAt != null &&
        !DateTime.now().isBefore(preview.fileExpiresAt!);
    final summary = preview.isDeleted
        ? '삭제된 메시지'
        : fileExpired
            ? '만료된 파일입니다'
            : preview.type == SnackChatMessageType.file
                ? (preview.originalFileName?.trim().isNotEmpty == true
                    ? preview.originalFileName!.trim()
                    : '파일')
                : preview.type == SnackChatMessageType.image &&
                        preview.textPreview.trim().isEmpty
                    ? '사진'
                    : preview.textPreview.trim();
    return Semantics(
      button: onTap != null,
      label: '${preview.senderName}, $summary',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 2,
                height: 34,
                color: foreground.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 8),
              if (preview.imagePath?.isNotEmpty == true ||
                  preview.imageUrl?.isNotEmpty == true) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox.square(
                    dimension: 34,
                    child: preview.imagePath?.isNotEmpty == true
                        ? SnackChatStorageImage(
                            storagePath: preview.imagePath!,
                            fit: BoxFit.cover,
                            loading: const SizedBox.shrink(),
                            error: const Icon(
                              Icons.image_not_supported_outlined,
                              size: 17,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: preview.imageUrl!,
                            cacheManager: AppImageCacheManager.instance,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Icon(
                              Icons.image_not_supported_outlined,
                              size: 17,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preview.senderName.isEmpty ? '사용자' : preview.senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
                    Text(
                      summary.isEmpty ? '메시지' : summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: foreground.withValues(alpha: 0.86),
                      ),
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
}

class SnackChatReactionBar extends StatelessWidget {
  const SnackChatReactionBar({
    super.key,
    required this.counts,
    required this.myReaction,
    required this.onToggle,
    required this.onShowUsers,
    required this.isOutgoing,
  });

  final Map<String, int> counts;
  final String? myReaction;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onShowUsers;
  final bool isOutgoing;

  @override
  Widget build(BuildContext context) {
    final visible = counts.entries.where((entry) => entry.value > 0).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        children: visible.map((entry) {
          final selected = myReaction == entry.key;
          return Semantics(
            button: true,
            selected: selected,
            label: '${entry.key} ${entry.value}명',
            child: Material(
              color: selected
                  ? (isOutgoing
                      ? Colors.white.withValues(alpha: 0.24)
                      : const Color(0x17344054))
                  : (isOutgoing
                      ? Colors.white.withValues(alpha: 0.12)
                      : const Color(0x0D344054)),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => onToggle(entry.key),
                onLongPress: () => onShowUsers(entry.key),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  child: Text(
                    '${entry.key} ${entry.value}',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color:
                          isOutgoing ? Colors.white : const Color(0xFF344054),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class SnackChatPollCard extends StatelessWidget {
  const SnackChatPollCard({
    super.key,
    required this.poll,
    required this.myOptionIds,
    required this.isOutgoing,
    required this.onVote,
    this.enabled = true,
  });

  final SnackChatPoll poll;
  final Set<String> myOptionIds;
  final bool isOutgoing;
  final ValueChanged<List<String>> onVote;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _PollCloseBoundary(
      closesAt: poll.closesAt,
      builder: _buildCard,
    );
  }

  Widget _buildCard(BuildContext context) {
    final foreground = isOutgoing ? Colors.white : const Color(0xFF101828);
    final secondary = isOutgoing
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF667085);
    final isClosed = poll.isClosed();
    final canVote = enabled && !isClosed;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 210, maxWidth: 360),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.how_to_vote_outlined, size: 17, color: secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  poll.question,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14.5,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...poll.options.map((option) {
            final selected = myOptionIds.contains(option.id);
            final count = poll.voteCounts[option.id] ?? 0;
            final denominator = poll.totalVoters == 0 ? 1 : poll.totalVoters;
            final progress = (count / denominator).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                button: canVote,
                enabled: canVote,
                selected: selected,
                label: '${option.text}, $count표',
                child: InkWell(
                  onTap: !canVote
                      ? null
                      : () {
                          final next = <String>{...myOptionIds};
                          if (poll.allowMultiple) {
                            selected
                                ? next.remove(option.id)
                                : next.add(option.id);
                          } else {
                            next
                              ..clear()
                              ..add(option.id);
                          }
                          onVote(next.toList(growable: false));
                        },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              poll.allowMultiple
                                  ? (selected
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded)
                                  : (selected
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_off_rounded),
                              size: 18,
                              color: secondary,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                option.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: foreground,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$count',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: secondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 2,
                            backgroundColor: secondary.withValues(alpha: 0.14),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              secondary.withValues(alpha: 0.62),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          Text(
            [
              '${poll.totalVoters}명 참여',
              if (poll.isAnonymous) '익명',
              if (isClosed) '종료됨',
            ].join(' · '),
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PollCloseBoundary extends StatefulWidget {
  const _PollCloseBoundary({required this.closesAt, required this.builder});

  final DateTime? closesAt;
  final WidgetBuilder builder;

  @override
  State<_PollCloseBoundary> createState() => _PollCloseBoundaryState();
}

class _PollCloseBoundaryState extends State<_PollCloseBoundary> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _PollCloseBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.closesAt != widget.closesAt) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final closesAt = widget.closesAt;
    if (closesAt == null) return;
    final delay = closesAt.difference(DateTime.now());
    if (delay <= Duration.zero) return;
    _timer = Timer(delay + const Duration(milliseconds: 50), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

class SnackChatLinkPreviewCard extends StatelessWidget {
  const SnackChatLinkPreviewCard({
    super.key,
    required this.preview,
    required this.isOutgoing,
    required this.onOpen,
    this.onRemove,
  });

  final SnackChatLinkPreview preview;
  final bool isOutgoing;
  final VoidCallback onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final foreground = isOutgoing ? Colors.white : const Color(0xFF101828);
    final secondary = isOutgoing
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF667085);
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Semantics(
        button: true,
        link: true,
        label: '${preview.domain}, ${preview.title}',
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (preview.imageUrl?.isNotEmpty == true) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: CachedNetworkImage(
                      imageUrl: preview.imageUrl!,
                      cacheManager: AppImageCacheManager.instance,
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preview.domain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: secondary,
                        ),
                      ),
                      if (preview.title.trim().isNotEmpty)
                        Text(
                          preview.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12.5,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                            color: foreground,
                          ),
                        ),
                      if (preview.description.trim().isNotEmpty)
                        Text(
                          preview.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 11,
                            height: 1.3,
                            color: secondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    onPressed: onRemove,
                    tooltip: '미리보기 제거',
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints.tightFor(width: 32, height: 32),
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.close_rounded, size: 16, color: secondary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
