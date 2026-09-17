import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

typedef RetryableChatImagePlaceholderBuilder = Widget Function(
  BuildContext context,
  String imageUrl,
);

typedef RetryableChatImageErrorBuilder = Widget Function(
  BuildContext context,
  String imageUrl,
  Object error,
  VoidCallback retry,
);

/// A cached chat image whose error action starts a fresh request for the same
/// URL. Only the failed URL is evicted; successful chat images stay cached.
class RetryableChatNetworkImage extends StatefulWidget {
  const RetryableChatNetworkImage({
    super.key,
    required this.imageUrl,
    required this.errorBuilder,
    this.cacheManager,
    this.imageBuilder,
    this.placeholder,
    this.fit,
    this.fadeInDuration = const Duration(milliseconds: 150),
    this.fadeOutDuration = const Duration(milliseconds: 150),
  });

  final String imageUrl;
  final BaseCacheManager? cacheManager;
  final ImageWidgetBuilder? imageBuilder;
  final RetryableChatImagePlaceholderBuilder? placeholder;
  final RetryableChatImageErrorBuilder errorBuilder;
  final BoxFit? fit;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;

  @override
  State<RetryableChatNetworkImage> createState() =>
      _RetryableChatNetworkImageState();
}

class _RetryableChatNetworkImageState extends State<RetryableChatNetworkImage> {
  var _requestGeneration = 0;
  var _retrying = false;

  @override
  void didUpdateWidget(covariant RetryableChatNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _requestGeneration = 0;
      _retrying = false;
    }
  }

  void _retry() {
    if (_retrying) return;
    setState(() => _retrying = true);
    unawaited(_evictAndReload());
  }

  Future<void> _evictAndReload() async {
    try {
      await CachedNetworkImage.evictFromCache(
        widget.imageUrl,
        cacheManager: widget.cacheManager,
      );
    } catch (_) {
      // Cache eviction is best-effort. Recreating the provider still allows a
      // transient network or decoding failure to be retried.
    }
    if (!mounted) return;
    setState(() {
      _requestGeneration++;
      _retrying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_retrying) {
      return widget.placeholder?.call(context, widget.imageUrl) ??
          const Center(
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
    }
    return CachedNetworkImage(
      key: ValueKey<String>(
        'retryable-chat-image:${widget.imageUrl}:$_requestGeneration',
      ),
      imageUrl: widget.imageUrl,
      cacheManager: widget.cacheManager,
      imageBuilder: widget.imageBuilder,
      placeholder: widget.placeholder,
      errorWidget: (context, imageUrl, error) => widget.errorBuilder(
        context,
        imageUrl,
        error,
        _retry,
      ),
      fit: widget.fit,
      fadeInDuration: widget.fadeInDuration,
      fadeOutDuration: widget.fadeOutDuration,
    );
  }
}
