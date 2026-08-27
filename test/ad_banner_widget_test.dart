import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as fcm;
import 'package:wefilling/models/ad_banner.dart';
import 'package:wefilling/services/cache/app_image_cache_manager.dart';
import 'package:wefilling/widgets/ad_banner_widget.dart';

void main() {
  testWidgets('광고의 디스크 리사이즈를 지원하는 이미지 캐시를 사용한다', (tester) async {
    expect(
      AppImageCacheManager.instance,
      isA<fcm.ImageCacheManager>(),
    );
  });

  testWidgets('실시간 광고 갱신에서 추가된 이미지 URL을 배너에 반영한다', (tester) async {
    final banners = StreamController<List<AdBanner>>();
    addTearDown(banners.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdBannerWidget(bannersStream: banners.stream),
        ),
      ),
    );

    const bannerWithoutImage = AdBanner(
      id: 'banner_001',
      title: 'MCPC 중앙동아리',
      description: '동아리 설명',
      url: 'https://example.com',
      order: 1,
    );
    banners.add(const [bannerWithoutImage]);
    await tester.pump();

    expect(find.byIcon(Icons.campaign_rounded), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);

    const imageUrl = 'https://example.com/ad.png';
    banners.add(const [
      AdBanner(
        id: 'banner_001',
        title: 'MCPC 중앙동아리',
        description: '동아리 설명',
        url: 'https://example.com',
        imageUrl: imageUrl,
        order: 1,
      ),
    ]);
    await tester.pump();
    await tester.pump();

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.imageUrl, imageUrl);
  });
}
