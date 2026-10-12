import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/widgets/audience_ring.dart';
import 'package:wefilling/ui/widgets/meetup_calendar_day_ring.dart';
import 'package:wefilling/utils/meetup_calendar_marker_policy.dart';

void main() {
  Widget app(MeetupCalendarMarkerStyle style) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: MeetupCalendarDayRing(
            style: style,
            size: 38,
            semanticLabel: 'meetup day',
            child: const ColoredBox(
              color: Colors.white,
              child: Center(child: Text('4')),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('일반 모임은 그라데이션 없이 단색 파란 링을 사용한다', (tester) async {
    await tester.pumpWidget(app(MeetupCalendarMarkerStyle.solidBlue));

    expect(find.byType(AudienceRing), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('친구 모임은 기존 공개범위 그라데이션 링을 사용한다', (tester) async {
    await tester.pumpWidget(app(MeetupCalendarMarkerStyle.friendGradient));

    final ring = tester.widget<AudienceRing>(find.byType(AudienceRing));
    expect(ring.restricted, isTrue);
    expect(ring.emphasized, isTrue);
    expect(tester.takeException(), isNull);
  });
}
