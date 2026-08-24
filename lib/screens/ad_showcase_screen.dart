// lib/screens/ad_showcase_screen.dart
// 광고 배너 상세 페이지 - Firebase Firestore 연동
// 모든 광고 배너를 순서대로 나열하여 보여줌

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/ad_banner.dart';
import '../services/ad_banner_service.dart';
import '../utils/logger.dart';

class AdShowcaseScreen extends StatefulWidget {
  const AdShowcaseScreen({
    super.key,
    this.initialBannerId,
    this.bannersStream,
  });

  /// 홈 배너에서 진입한 경우 상세 목록의 같은 광고로 바로 이동한다.
  final String? initialBannerId;

  /// 테스트와 프리뷰에서 Firebase 없이 광고 목록을 주입할 수 있다.
  final Stream<List<AdBanner>>? bannersStream;

  @override
  State<AdShowcaseScreen> createState() => _AdShowcaseScreenState();
}

class _AdShowcaseScreenState extends State<AdShowcaseScreen> {
  AdBannerService? _adBannerService;
  final Map<String, GlobalKey> _bannerKeys = <String, GlobalKey>{};
  bool _didRevealInitialBanner = false;

  GlobalKey _keyForBanner(String bannerId, int index) {
    final anchorId = '$index::$bannerId';
    return _bannerKeys.putIfAbsent(
      anchorId,
      () => GlobalKey(debugLabel: 'ad-showcase-$anchorId'),
    );
  }

  void _revealInitialBanner(List<AdBanner> banners) {
    final targetId = widget.initialBannerId?.trim();
    if (_didRevealInitialBanner || targetId == null || targetId.isEmpty) return;
    final targetIndex = banners.indexWhere((banner) => banner.id == targetId);
    if (targetIndex < 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didRevealInitialBanner) return;
      final targetContext = _keyForBanner(targetId, targetIndex).currentContext;
      if (targetContext == null) return;

      _didRevealInitialBanner = true;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.04,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void didUpdateWidget(covariant AdShowcaseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialBannerId != widget.initialBannerId) {
      _didRevealInitialBanner = false;
    }
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      Logger.error('URL 열기 실패: $e');
    }
  }

  Widget _buildLogo() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          'assets/icons/app_logo.png',
          width: 32,
          height: 32,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF4A90E2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.apps,
                color: Colors.white,
                size: 20,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Color(0xFF4A90E2), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Wefilling ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4A90E2),
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: 'For You',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      backgroundColor: const Color(0xFFF8F9FA),
      body: StreamBuilder<List<AdBanner>>(
        stream: widget.bannersStream ??
            (_adBannerService ??= AdBannerService()).getActiveBannersStream(),
        builder: (context, snapshot) {
          // 로딩 중
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          // 오류 발생
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 80,
                    color: Colors.red[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '광고를 불러올 수 없습니다',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }

          // 데이터 없음
          final activeAds = snapshot.data ?? [];
          if (activeAds.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.campaign_rounded,
                    size: 80,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '등록된 광고가 없습니다',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }

          _revealInitialBanner(activeAds);

          // 광고 수가 많지 않은 쇼케이스 화면이므로 모든 카드를 한 번에 빌드한다.
          // 그래야 화면 밖에 있는 선택 광고도 GlobalKey로 정확히 찾아 이동할 수 있다.
          return SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom:
                  MediaQuery.of(context).padding.bottom + 16, // 하단 시스템 UI 영역 고려
            ),
            child: Column(
              children: [
                for (var index = 0; index < activeAds.length; index++)
                  KeyedSubtree(
                    // 순번을 함께 사용해 잘못된 레거시 데이터에 중복 id가 있어도
                    // 한 Column 안에서 GlobalKey가 충돌하지 않도록 한다.
                    key: _keyForBanner(activeAds[index].id, index),
                    child: _buildAdCard(context, activeAds[index], index),
                  ),
                // 마지막 광고도 화면 상단 가까이에 정렬할 수 있는 앵커 여백.
                if (widget.initialBannerId?.trim().isNotEmpty == true)
                  SizedBox(
                    height: (MediaQuery.sizeOf(context).height - 160)
                        .clamp(0, 480)
                        .toDouble(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAdCard(BuildContext context, AdBanner banner, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _launchUrl(banner.url),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 제목과 클릭 아이콘
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        banner.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey[900],
                          height: 1.3,
                        ),
                      ),
                    ),
                    // 오른쪽 상단 클릭 아이콘
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.open_in_new,
                        color: Colors.blue[600],
                        size: 20,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 이미지 (있는 경우만 표시)
                if (banner.imageUrl != null && banner.imageUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: banner.imageUrl!,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.image_not_supported,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                      ),
                    ),
                  ),

                if (banner.imageUrl != null && banner.imageUrl!.isNotEmpty)
                  const SizedBox(height: 12),

                // 설명 (더 많은 줄 표시 가능)
                Text(
                  banner.description,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                    height: 1.5,
                  ),
                  maxLines: 5, // 최대 5줄까지 표시
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
