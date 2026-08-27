// lib/widgets/ad_banner_widget.dart
// 광고 배너 위젯 - 완전히 재구현

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/ad_banner.dart';
import '../services/ad_banner_service.dart';
import '../services/cache/app_image_cache_manager.dart';
import '../screens/ad_showcase_screen.dart';
import '../constants/app_constants.dart';
import '../design/tokens.dart';
import '../utils/logger.dart';

class AdBannerWidget extends StatefulWidget {
  final String? widgetId;
  final Stream<List<AdBanner>>? bannersStream;

  const AdBannerWidget({
    super.key,
    this.widgetId,
    this.bannersStream,
  });

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  AdBannerService? _adBannerService;
  Timer? _autoScrollTimer;
  StreamSubscription<List<AdBanner>>? _bannerSubscription;
  int _currentIndex = 0;
  List<AdBanner> _banners = [];
  bool _hasReceivedLiveBanners = false;

  @override
  void initState() {
    super.initState();
    if (widget.bannersStream == null) _loadBanners();
    _listenForBannerUpdates();
  }

  AdBannerService get _service => _adBannerService ??= AdBannerService();

  @override
  void didUpdateWidget(covariant AdBannerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.bannersStream, widget.bannersStream)) return;
    unawaited(_bannerSubscription?.cancel());
    _bannerSubscription = null;
    _hasReceivedLiveBanners = false;
    if (widget.bannersStream == null) _loadBanners();
    _listenForBannerUpdates();
  }

  Future<void> _loadBanners() async {
    if (!mounted) return;

    try {
      final banners = await _service.getActiveBanners();
      // Firestore의 최신 snapshot이 먼저 도착했다면 오래된 로컬 캐시로
      // 화면을 되돌리지 않는다.
      if (mounted && !_hasReceivedLiveBanners && banners.isNotEmpty) {
        _applyBanners(banners);
      }
    } catch (e) {
      // 광고 배너 로드 오류 (조용히 처리)
    }
  }

  void _listenForBannerUpdates() {
    _bannerSubscription =
        (widget.bannersStream ?? _service.getActiveBannersStream()).listen(
      (banners) {
        if (!mounted) return;
        _hasReceivedLiveBanners = true;
        _applyBanners(banners);
      },
      // 네트워크/권한 오류가 나도 먼저 표시한 로컬 캐시는 유지한다.
      onError: (_) {},
    );
  }

  void _applyBanners(List<AdBanner> banners) {
    final currentBannerId = _banners.isNotEmpty &&
            _currentIndex >= 0 &&
            _currentIndex < _banners.length
        ? _banners[_currentIndex].id
        : null;
    final nextBanners = List<AdBanner>.unmodifiable(banners);
    var nextIndex = currentBannerId == null
        ? 0
        : nextBanners.indexWhere((banner) => banner.id == currentBannerId);
    if (nextIndex < 0) nextIndex = 0;

    setState(() {
      _banners = nextBanners;
      _currentIndex = nextIndex;
    });
    _startAutoScroll();
    _preloadImages();
  }

  // 이미지 프리로딩
  void _preloadImages() {
    if (!mounted) return;

    for (final banner in _banners) {
      if (banner.imageUrl != null && banner.imageUrl!.isNotEmpty) {
        precacheImage(
          CachedNetworkImageProvider(
            banner.imageUrl!,
            cacheManager: AppImageCacheManager.instance,
          ),
          context,
        ).catchError((_) {});
      }
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;

    if (_banners.length <= 1) {
      return;
    }

    if (!mounted) {
      return;
    }

    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        _autoScrollTimer = null;
        return;
      }

      if (mounted) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % _banners.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    unawaited(_bannerSubscription?.cancel());
    _bannerSubscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!mounted || _banners.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final isCompact = width < 360;
        final isExpanded = width >= 600;
        final height = isCompact ? 100.0 : (isExpanded ? 116.0 : 108.0);
        final horizontalPadding = isCompact ? 12.0 : (isExpanded ? 20.0 : 16.0);
        final verticalPadding = isCompact ? 8.0 : 10.0;
        final imageSize = isCompact ? 72.0 : (isExpanded ? 84.0 : 80.0);
        final titleSize = isCompact ? 13.0 : (isExpanded ? 15.0 : 14.0);
        final descriptionSize = isCompact ? 11.0 : (isExpanded ? 12.0 : 11.5);

        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            decoration: const BoxDecoration(
              color: BrandColors.surface,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 현재 배너만 표시
                ClipRect(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(1.0, 0.0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: _buildBannerContent(
                      _banners[_currentIndex],
                      _currentIndex,
                      imageSize: imageSize,
                      titleSize: titleSize,
                      descriptionSize: descriptionSize,
                      compact: isCompact,
                    ),
                  ),
                ),

                // 페이지 인디케이터
                if (_banners.length > 1)
                  Positioned(
                    top: 0,
                    right: 2,
                    child: Text(
                      '${_currentIndex + 1}/${_banners.length}',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        color: const Color(0xFF6B7280),
                        fontSize: isCompact ? 10 : 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBannerContent(
    AdBanner banner,
    int index, {
    required double imageSize,
    required double titleSize,
    required double descriptionSize,
    required bool compact,
  }) {
    return GestureDetector(
      key: ValueKey('banner_$index'), // AnimatedSwitcher를 위한 고유 키
      onTap: () {
        // 광고 목록 페이지에서 사용자가 누른 광고 위치로 바로 이동한다.
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AdShowcaseScreen(
              initialBannerId: banner.id,
            ),
          ),
        );
      },
      child: Row(
        children: [
          // 이미지 또는 아이콘
          banner.imageUrl != null && banner.imageUrl!.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(compact ? 10 : 12),
                  child: CachedNetworkImage(
                    imageUrl: banner.imageUrl!,
                    cacheManager: AppImageCacheManager.instance,
                    width: imageSize,
                    height: imageSize,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: imageSize,
                      height: imageSize,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(compact ? 10 : 12),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) {
                      Logger.error(
                        '광고 이미지 로드 실패: ${banner.id} '
                        '(${error.runtimeType}: $error)',
                      );
                      return _buildIconPlaceholder(imageSize);
                    },
                    memCacheWidth: 200,
                    memCacheHeight: 200,
                    maxWidthDiskCache: 400,
                    maxHeightDiskCache: 400,
                  ),
                )
              : _buildIconPlaceholder(imageSize),

          SizedBox(width: compact ? 10 : 12),

          // 텍스트 영역
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 타이틀 + AD 배지
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        banner.title,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: titleSize,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                          height: 1.2,
                        ),
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: compact ? 4 : 6),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 5 : 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.black, width: 1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'AD',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: compact ? 8 : 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: compact ? 3 : 4),

                Text(
                  banner.description,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: descriptionSize,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                    height: 1.35,
                  ),
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          SizedBox(width: compact ? 6 : 8),

          Icon(
            Icons.arrow_forward_ios,
            color: Colors.grey[400],
            size: compact ? 14 : 16,
          ),
        ],
      ),
    );
  }

  /// 이미지가 없을 때 표시할 아이콘 플레이스홀더
  Widget _buildIconPlaceholder(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.pointColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size < 80 ? 10 : 12),
        border: Border.all(
          color: AppColors.pointColor.withValues(alpha: 0.2),
          width: 2,
        ),
      ),
      child: Icon(
        Icons.campaign_rounded,
        color: AppColors.pointColor,
        size: size * 0.48,
      ),
    );
  }
}
