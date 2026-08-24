import 'dart:collection';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../services/cache/app_image_cache_manager.dart';

/// 원본 비율을 사용하되 소셜 피드에서 과도하게 크거나 납작해지지 않도록
/// 4:5~1.91:1 범위와 화면 기준 최대 높이를 적용한다.
class AdaptivePostImageFrame extends StatefulWidget {
  const AdaptivePostImageFrame({
    super.key,
    required this.imageUrl,
    required this.child,
  });

  final String imageUrl;
  final Widget child;

  @override
  State<AdaptivePostImageFrame> createState() => _AdaptivePostImageFrameState();
}

class _AdaptivePostImageFrameState extends State<AdaptivePostImageFrame> {
  static const double _fallbackAspectRatio = 4 / 3;
  static const double _minimumAspectRatio = 4 / 5;
  static const double _maximumAspectRatio = 1.91;
  static const double _absoluteMaximumHeight = 480;
  static const int _maximumCachedRatios = 300;
  static final LinkedHashMap<String, double> _aspectRatioCache =
      LinkedHashMap<String, double>();

  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  double? _sourceAspectRatio;
  String? _resolvedUrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveAspectRatio();
  }

  @override
  void didUpdateWidget(covariant AdaptivePostImageFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _stopListening();
      _sourceAspectRatio = null;
      _resolvedUrl = null;
      _resolveAspectRatio();
    }
  }

  void _resolveAspectRatio() {
    final url = widget.imageUrl.trim();
    if (url.isEmpty || _resolvedUrl == url) return;
    _resolvedUrl = url;

    final cachedRatio = _aspectRatioCache.remove(url);
    if (cachedRatio != null) {
      _aspectRatioCache[url] = cachedRatio;
      _sourceAspectRatio = cachedRatio;
      return;
    }

    final provider = CachedNetworkImageProvider(
      url,
      cacheManager: AppImageCacheManager.instance,
    );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (imageInfo, synchronousCall) {
        final width = imageInfo.image.width;
        final height = imageInfo.image.height;
        if (width <= 0 || height <= 0) return;
        final ratio = width / height;
        _rememberAspectRatio(url, ratio);
        _stopListening();
        if (!mounted || _resolvedUrl != url) return;
        if (synchronousCall) {
          _sourceAspectRatio = ratio;
        } else {
          setState(() => _sourceAspectRatio = ratio);
        }
      },
      onError: (_, __) => _stopListening(),
    );
    _imageStream = stream;
    _imageStreamListener = listener;
    stream.addListener(listener);
  }

  static void _rememberAspectRatio(String url, double ratio) {
    _aspectRatioCache.remove(url);
    _aspectRatioCache[url] = ratio;
    while (_aspectRatioCache.length > _maximumCachedRatios) {
      _aspectRatioCache.remove(_aspectRatioCache.keys.first);
    }
  }

  void _stopListening() {
    final stream = _imageStream;
    final listener = _imageStreamListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageStream = null;
    _imageStreamListener = null;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final aspectRatio = (_sourceAspectRatio ?? _fallbackAspectRatio).clamp(
          _minimumAspectRatio,
          _maximumAspectRatio,
        );
        final screenHeight = MediaQuery.sizeOf(context).height;
        final maximumHeight = math.min(
          _absoluteMaximumHeight,
          screenHeight * 0.56,
        );
        final desiredHeight = availableWidth / aspectRatio;
        final height = math.min(desiredHeight, maximumHeight);

        return AnimatedSize(
          duration: DesignTokens.normal,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: double.infinity,
            height: height,
            child: widget.child,
          ),
        );
      },
    );
  }
}
