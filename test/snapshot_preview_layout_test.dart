import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/snapshot/snapshot_today_section.dart';

void main() {
  test('portrait snack cards use the parent width and a 9:16 preview', () {
    for (final width in <double>[320, 360, 390, 430, 600]) {
      const padding = 8.0;
      final cardWidth = SnackPreviewLayout.widthFor(width, padding);
      final layout = SnackPreviewLayout.resolve(
        cardWidth: cardWidth,
        viewportHeight: 844,
        myLabelHeight: 18,
        landscape: false,
      );

      expect(cardWidth, inInclusiveRange(92, 120));
      expect(layout.cardHeight, closeTo(cardWidth * 16 / 9, .001));
      expect(layout.sectionHeight, layout.cardHeight + 24);
      expect(layout.myImageHeight, greaterThan(layout.myInfoHeight));
    }
  });

  test('short screens compact the artwork without clipping My Snack text', () {
    final layout = SnackPreviewLayout.resolve(
      cardWidth: 103,
      viewportHeight: 520,
      myLabelHeight: 18,
      landscape: true,
    );
    expect(layout.cardHeight, 150);
    expect(layout.myInfoHeight, greaterThanOrEqualTo(18 + 38));
    expect(layout.myImageHeight, greaterThanOrEqualTo(70));
  });

  test('large localized labels grow the information area and card', () {
    final layout = SnackPreviewLayout.resolve(
      cardWidth: 150,
      viewportHeight: 844,
      myLabelHeight: 108,
      landscape: false,
    );
    expect(layout.myInfoHeight, greaterThanOrEqualTo(108 + 38));
    expect(layout.myImageHeight, greaterThanOrEqualTo(150 * .9));
  });

  test('a narrow split view never overflows the available tray width', () {
    expect(SnackPreviewLayout.widthFor(100, 8), 84);
  });
}
