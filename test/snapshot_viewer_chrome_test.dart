import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/snapshot/snapshot_strings.dart';
import 'package:wefilling/snapshot/snapshot_viewer_chrome.dart';

Widget _host(Widget child, {Locale locale = const Locale('ko'), double scale = 1}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(backgroundColor: Colors.black, body: child),
    ),
  );
}

void main() {
  group('남은 시간 문구', () {
    testWidgets('23시간 / 59분 / 만료, ko·en·zh', (tester) async {
      late SnapshotStrings ko;
      late SnapshotStrings en;
      late SnapshotStrings zh;
      Future<SnapshotStrings> strings(Locale l) async {
        late SnapshotStrings out;
        await tester.pumpWidget(MaterialApp(
          locale: l,
          supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(builder: (c) {
            out = SnapshotStrings.of(c);
            return const SizedBox();
          }),
        ));
        return out;
      }

      ko = await strings(const Locale('ko'));
      en = await strings(const Locale('en'));
      zh = await strings(const Locale('zh'));
      expect(snapshotRemainingLabel(ko, const Duration(hours: 23, minutes: 10)),
          '23시간 남음');
      expect(snapshotRemainingLabel(en, const Duration(hours: 11, minutes: 1)),
          '11h left');
      expect(snapshotRemainingLabel(zh, const Duration(hours: 11, minutes: 1)),
          '剩余11小时');
      expect(snapshotRemainingLabel(ko, const Duration(minutes: 59)), '59분 남음');
      expect(snapshotRemainingLabel(en, const Duration(seconds: 20)), '1m left');
      expect(snapshotRemainingLabel(ko, Duration.zero), isNull);
    });
  });

  testWidgets('진행 막대: 칸 수만큼 나누고 지난 칸은 가득', (tester) async {
    await tester.pumpWidget(_host(const Padding(
      padding: EdgeInsets.all(12),
      child: SnapshotProgressSegments(count: 4, index: 2),
    )));
    expect(find.byType(ClipRRect), findsNWidgets(4));
    final sem = tester.getSemantics(find.byType(SnapshotProgressSegments));
    expect(sem.label, '3/4');
    // 지난 칸 2개는 흰색 전체 칸을 가진다
    final fullWhite = find.byWidgetPredicate((w) =>
        w is ColoredBox && w.color == Colors.white);
    expect(fullWhite, findsNWidgets(2 + 1));
  });

  testWidgets('번역 스위치(어두운 모양): 글자 없음, 탭 콜백, 켜지면 파란 홈', (tester) async {
    var taps = 0;
    var on = false;
    await tester.pumpWidget(StatefulBuilder(builder: (context, set) {
      return _host(SnapshotTranslateChip(
        on: on,
        languageLabel: 'English',
        onTap: () {
          taps++;
          set(() => on = !on);
        },
      ));
    }));
    expect(find.text('English'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('snapshot_translate_chip')));
    await tester.pumpAndSettle();
    expect(taps, 1);
    final track = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('translate_switch_track')));
    expect((track.decoration! as BoxDecoration).color, const Color(0xFF2C6BC0));
    expect(find.text('English'), findsNothing);
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('헤더 오버플로우 없음 $width/$scale', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final name in const [
          'Wefilling',
          'seoyeon_international_student_club_with_long_name',
          '欧阳娜娜非常非常长的中文名字测试用户名',
        ]) {
          await tester.pumpWidget(_host(
            SnapshotViewerHeader(
              avatar: const ColoredBox(color: Colors.grey),
              name: name,
              subtitle: '13시간 전 · 11시간 남음',
              onAuthorTap: () {},
              onMore: () {},
              onClose: () {},
              translateChip: SnapshotTranslateChip(
                on: true,
                languageLabel: '日本語',
                onTap: () {},
              ),
            ),
            scale: scale,
          ));
          expect(tester.takeException(), isNull, reason: '$name $width $scale');
        }
      });
    }
  }
}

