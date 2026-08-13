import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snapshot.dart';
import 'package:wefilling/screens/snapshot_viewers_screen.dart';

void main() {
  testWidgets('조회자 목록은 작은 화면과 큰 글자에서도 오버플로우하지 않는다', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    final viewers = <SnapshotViewer>[
      SnapshotViewer(
        userId: 'viewer-1',
        displayName: '아주 긴 이름을 사용하는 조회자 테스트 사용자',
        photoUrl: '',
        photoVersion: 0,
        nationality: '대한민국',
        university: '아주 긴 대학교 이름을 사용하는 반응형 화면 테스트 캠퍼스',
        viewedAt: DateTime.now().subtract(const Duration(minutes: 4)),
      ),
      SnapshotViewer(
        userId: 'viewer-2',
        displayName: 'viewer',
        photoUrl: '',
        photoVersion: 0,
        nationality: '',
        university: '',
        viewedAt: DateTime.now().subtract(const Duration(hours: 3)),
      ),
    ];

    for (final width in <double>[320, 360, 430, 720]) {
      tester.view.physicalSize = Size(width, 720);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          supportedLocales: const [Locale('ko'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 720),
              padding: const EdgeInsets.only(bottom: 24),
              viewPadding: const EdgeInsets.only(bottom: 24),
              textScaler: const TextScaler.linear(2.2),
            ),
            child: SnapshotViewersScreen(
              snapshotId: 'snapshot-id',
              viewersStream: Stream.value(viewers),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('조회한 사람'), findsOneWidget);
      expect(find.text('2명이 이 스낵을 확인했어요'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width=$width');
    }
  });
}
