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

    return Container(
      height: 116,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
              transitionBuilder: (Widget child, Animation<double> animation) {
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
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: Color(0xFF6B7280),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBannerContent(AdBanner banner, int index) {
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
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: banner.imageUrl!,
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) {
                      // 이미지 로드 실패 시 아이콘 표시
                      return _buildIconPlaceholder();
                    },
                    // 이미지 캐싱 설정
                    memCacheWidth: 200, // 메모리 캐시 너비 제한
                    memCacheHeight: 200, // 메모리 캐시 높이 제한
                    maxWidthDiskCache: 400, // 디스크 캐시 너비 제한
                    maxHeightDiskCache: 400, // 디스크 캐시 높이 제한
                  ),
                )
              : _buildIconPlaceholder(),

          const SizedBox(width: 12),

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
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.black, width: 1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'AD',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // 설명
                Text(
                  banner.description,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // 화살표 아이콘
          Icon(
            Icons.arrow_forward_ios,
            color: Colors.grey[400],
            size: 16,
          ),
        ],
      ),
    );
  }

  /// 이미지가 없을 때 표시할 아이콘 플레이스홀더
  Widget _buildIconPlaceholder() {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        color: AppColors.pointColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.pointColor.withValues(alpha: 0.2),
          width: 2,
        ),
      ),
      child: const Icon(
        Icons.campaign_rounded,
        color: AppColors.pointColor,
        size: 40,
      ),
    );
  }
}
