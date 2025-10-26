// lib/widgets/ad_banner_widget.dart
// 광고 배너 위젯 - 완전히 재구현

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/ad_banner.dart';
import '../services/ad_banner_service.dart';
import '../screens/ad_showcase_screen.dart';

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
    print('📢 AdBannerWidget 초기화: ${widget.widgetId ?? "기본"}');
    _loadBanners();
  }

  Future<void> _loadBanners() async {
    final banners = await _adBannerService.getActiveBanners();
    if (mounted && banners.isNotEmpty) {
      setState(() {
        _banners = banners;
      });
      _startAutoScroll();
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    
    if (_banners.length <= 1) {
      print('📢 [${widget.widgetId}] 광고가 1개 이하여서 자동 스크롤 비활성화');
      return;
    }

    print('📢 [${widget.widgetId}] 자동 스크롤 시작: ${_banners.length}개 광고');
    
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _currentIndex = (_currentIndex + 1) % _banners.length;
      });
      
      print('📢 [${widget.widgetId}] 인덱스 변경: $_currentIndex/${_banners.length}');
    });
  }

  @override
  void dispose() {
    print('📢 [${widget.widgetId}] AdBannerWidget dispose 호출');
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showMessage('링크를 열 수 없습니다');
      }
    } catch (e) {
      _showMessage('오류가 발생했습니다');
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_banners.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 88,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Stack(
        children: [
          // 현재 배너만 표시
          AnimatedSwitcher(
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
            child: _buildBannerCard(_banners[_currentIndex], _currentIndex),
          ),

          // 페이지 인디케이터
          if (_banners.length > 1)
            Positioned(
              bottom: 8,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentIndex + 1}/${_banners.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBannerCard(AdBanner banner, int index) {
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
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue.shade50,
              Colors.blue.shade100,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.blue.shade200,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 아이콘
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.campaign_rounded,
                  color: Colors.blue.shade600,
                  size: 28,
                ),
              ),

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
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.blue.shade900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade600,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'AD',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
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
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // 화살표 아이콘
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.blue.shade400,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}