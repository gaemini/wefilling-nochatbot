import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/ad_banner.dart';
import 'package:wefilling/screens/ad_showcase_screen.dart';

void main() {
  testWidgets('선택한 광고가 상세 화면에 들어오면 해당 카드로 이동한다', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 480);

    final banners = List<AdBanner>.generate(
      6,
      (index) => AdBanner(
        id: 'ad-$index',
        title: '광고 ${index + 1}',
        description: '선택한 광고 위치 이동을 검증하기 위한 설명입니다.',
        url: 'https://example.com/$index',
        order: index,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdShowcaseScreen(
          initialBannerId: 'ad-5',
          bannersStream: Stream<List<AdBanner>>.value(banners),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, greaterThan(0));
    expect(find.text('광고 6'), findsOneWidget);
    expect(tester.getTopLeft(find.text('광고 6')).dy, lessThan(240));
  });

  testWidgets('레거시 광고 ID가 중복되어도 상세 화면 키가 충돌하지 않는다', (tester) async {
    final banners = <AdBanner>[
      const AdBanner(
        id: 'banner_001',
        title: '첫 번째 광고',
        description: '첫 번째 설명',
        url: 'https://example.com/first',
        order: 1,
      ),
      const AdBanner(
        id: 'banner_001',
        title: '두 번째 광고',
        description: '두 번째 설명',
        url: 'https://example.com/second',
        order: 2,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: AdShowcaseScreen(
          bannersStream: Stream<List<AdBanner>>.value(banners),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('첫 번째 광고'), findsOneWidget);
    expect(find.text('두 번째 광고'), findsOneWidget);
  });
}
