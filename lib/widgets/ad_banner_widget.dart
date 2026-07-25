// lib/widgets/ad_banner_widget.dart
// 광고 배너 위젯 - 완전히 재구현

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/ad_banner.dart';
import '../services/ad_banner_service.dart';
import '../screens/ad_showcase_screen.dart';
import '../constants/app_constants.dart';
import '../design/tokens.dart';

class AdBannerWidget extends StatefulWidget {
  final String? widgetId;

  const AdBannerWidget({
    super.key,
    this.widgetId,
  });

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  final AdBannerService _adBannerService = AdBannerService();
  Timer? _autoScrollTimer;
  int _currentIndex = 0;
  List<AdBanner> _banners = [];

  @override
  void initState() {
    super.initState();
    _loadBanners();
  }

  Future<void> _loadBanners() async {
    if (!mounted) return;

    try {
      final banners = await _adBannerService.getActiveBanners();
      if (mounted && banners.isNotEmpty) {
        setState(() {
          _banners = banners;
        });
        _startAutoScroll();
        _preloadImages();
      }
    } catch (e) {
      // 광고 배너 로드 오류 (조용히 처리)
    }
  }

  // 이미지 프리로딩
  void _preloadImages() {
    if (!mounted) return;

    for (final banner in _banners) {
      if (banner.imageUrl != null && banner.imageUrl!.isNotEmpty) {
        precacheImage(
          CachedNetworkImageProvider(banner.imageUrl!),
          context,
        );
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
                        fontFamily: 'Pretendard',
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
        // 광고 목록 페이지로 이동
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AdShowcaseScreen(),
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
                          fontFamily: 'Pretendard',
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
                          fontFamily: 'Pretendard',
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
                    fontFamily: 'Pretendard',
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
