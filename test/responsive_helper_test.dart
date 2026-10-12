import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/responsive_helper.dart';

class _ResponsiveValues {
  const _ResponsiveValues({
    required this.font,
    required this.icon,
    required this.spacing,
  });

  final double font;
  final double icon;
  final double spacing;
}

Future<_ResponsiveValues> _valuesAt(
  WidgetTester tester, {
  required double width,
  double textScale = 1,
}) async {
  late _ResponsiveValues values;

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Builder(
          builder: (context) {
            values = _ResponsiveValues(
              font: context.rf(15),
              icon: context.ri(20),
              spacing: context.rs(16),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );

  return values;
}

void main() {
  testWidgets('preserves existing compact phone width scaling', (tester) async {
    final at360 = await _valuesAt(tester, width: 360);
    final at390 = await _valuesAt(tester, width: 390);
    final at430 = await _valuesAt(tester, width: 430);

    expect(at360.font, closeTo(14.4, 0.001));
    expect(at390.font, closeTo(15.6, 0.001));
    expect(at430.font, closeTo(17.2, 0.001));
  });

  testWidgets('stops font icon and spacing growth after 430dp', (tester) async {
    final at430 = await _valuesAt(tester, width: 430);

    for (final width in [600.0, 720.0, 840.0, 1024.0]) {
      final large = await _valuesAt(tester, width: width);
      expect(large.font, closeTo(at430.font, 0.001));
      expect(large.icon, closeTo(at430.icon, 0.001));
      expect(large.spacing, closeTo(at430.spacing, 0.001));
    }
  });

  testWidgets('does not counteract the system text scale', (tester) async {
    final normal = await _valuesAt(tester, width: 390);
    final enlarged = await _valuesAt(tester, width: 390, textScale: 2);

    expect(enlarged.font, closeTo(normal.font, 0.001));
  });
}
