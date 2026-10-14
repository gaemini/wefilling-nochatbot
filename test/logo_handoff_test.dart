import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/ui/motion/logo_handoff.dart';
import 'package:wefilling/ui/widgets/app_start_motion.dart';

Widget _app(Widget home, {bool reduce = false}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: LogoHandoffLayer(child: child!),
      ),
      home: home,
    );

Widget _loginLike() => const Scaffold(
      body: Align(
        alignment: Alignment(0, -.6),
        child: LogoHandoffTargetSlot(
          target: LogoHandoffTarget.login,
          child: SizedBox.square(
            key: ValueKey('real_logo'),
            dimension: 100,
          ),
        ),
      ),
    );

double _slotOpacity(WidgetTester tester) => tester
    .widget<Opacity>(find
        .ancestor(
          of: find.byKey(const ValueKey('real_logo')),
          matching: find.byType(Opacity),
        )
        .first)
    .opacity;

void main() {
  setUp(() => LogoHandoff.instance.debugReset());

  testWidgets('이동 중에는 로고가 한 장(진짜 로고 숨김), 도착하면 진짜 로고만',
      (tester) async {
    await tester.pumpWidget(_app(_loginLike()));
    LogoHandoff.instance.start(LogoHandoffTarget.login);
    await tester.pump(); // 같은 프레임: 진짜 로고 숨김
    expect(_slotOpacity(tester), 0);
    await tester.pump(); // 측정 후 출발
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.byKey(const ValueKey('logo_handoff_flying')), findsOneWidget);
    expect(_slotOpacity(tester), 0);
    // 중간 위치: 가운데(130)와 목표 사이.
    final mid = tester.getRect(find.byKey(const ValueKey('logo_handoff_flying')));
    expect(mid.width, lessThan(130));
    expect(mid.width, greaterThan(100));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('logo_handoff_flying')), findsNothing);
    expect(_slotOpacity(tester), 1);
    expect(LogoHandoff.instance.flight, isNull);
  });

  testWidgets('목표 자리가 없으면 제자리에서 사라지고 남지 않는다', (tester) async {
    await tester.pumpWidget(_app(const Scaffold(body: SizedBox())));
    LogoHandoff.instance.start(LogoHandoffTarget.main);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('logo_handoff_flying')), findsNothing);
    expect(LogoHandoff.instance.flight, isNull);
  });

  testWidgets('부트 화면: 로고는 화면 정가운데 130, 750ms 뒤 점 3개 힌트',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(const AppBootScreen()));
    final logo = tester.getRect(find.byKey(const ValueKey('boot_logo')));
    expect(logo.size, const Size(130, 130));
    expect(logo.center, const Offset(195, 422));
    final hint = find.byKey(const ValueKey('boot_loading_dots'));
    expect(
      tester
          .widget<AnimatedOpacity>(
              find.ancestor(of: hint, matching: find.byType(AnimatedOpacity)))
          .opacity,
      0,
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      tester
          .widget<AnimatedOpacity>(
              find.ancestor(of: hint, matching: find.byType(AnimatedOpacity)))
          .opacity,
      1,
    );
    // 힌트가 나타나도 로고는 움직이지 않는다.
    expect(tester.getRect(find.byKey(const ValueKey('boot_logo'))), logo);
    await tester.pumpWidget(const SizedBox());
  });
}
