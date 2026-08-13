import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/country_flag_helper.dart';

void main() {
  group('CountryFlagHelper locale normalization', () {
    test('localizes Korean persisted values for English UI', () {
      expect(
        CountryFlagHelper.getLocalizedCountryName('한국', 'en'),
        'Korea',
      );
      expect(
        CountryFlagHelper.getLocalizedCountryName('미국', 'en'),
        'United States',
      );
      expect(
        CountryFlagHelper.getLocalizedCountryName('대한민국', 'en'),
        'Korea',
      );
    });

    test('localizes English and ISO persisted values for Korean UI', () {
      expect(
        CountryFlagHelper.getLocalizedCountryName('United States', 'ko'),
        '미국',
      );
      expect(
        CountryFlagHelper.getLocalizedCountryName('KR', 'ko'),
        '한국',
      );
    });

    test('keeps unknown legacy values instead of hiding them', () {
      expect(
        CountryFlagHelper.getLocalizedCountryName('Unknown country', 'en'),
        'Unknown country',
      );
    });
  });
}
