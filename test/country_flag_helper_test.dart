import 'package:flutter/material.dart';
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

  group('CountryFlagHelper dropdown normalization', () {
    test('empty and unknown legacy values become an unselected value', () {
      expect(CountryFlagHelper.normalizeForDropdown(null), isNull);
      expect(CountryFlagHelper.normalizeForDropdown(''), isNull);
      expect(CountryFlagHelper.normalizeForDropdown('   '), isNull);
      expect(
        CountryFlagHelper.normalizeForDropdown('legacy-unknown-country'),
        isNull,
      );
    });

    test('Korean, English, ISO, and legacy aliases use one canonical value',
        () {
      for (final value in <Object>[
        '한국',
        'Korea',
        'KR',
        '대한민국',
        'South Korea',
        'Republic of Korea',
        'ROK',
      ]) {
        expect(CountryFlagHelper.normalizeForDropdown(value), '한국');
      }
      expect(CountryFlagHelper.normalizeForDropdown('United States'), '미국');
      expect(CountryFlagHelper.normalizeForDropdown('US'), '미국');
    });

    test('dropdown item values are non-empty and unique', () {
      final values = CountryFlagHelper.dropdownCountries
          .map((country) => country.korean)
          .toList(growable: false);

      expect(values, isNotEmpty);
      expect(values.every((value) => value.trim().isNotEmpty), isTrue);
      expect(values.toSet().length, values.length);
    });
  });

  testWidgets('an empty stored nationality renders without an assertion',
      (tester) async {
    final value = CountryFlagHelper.normalizeForDropdown('');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DropdownButtonFormField<String>(
            initialValue: value,
            hint: const Text('Country'),
            items: CountryFlagHelper.dropdownCountries
                .map(
                  (country) => DropdownMenuItem<String>(
                    value: country.korean,
                    child: Text(country.english),
                  ),
                )
                .toList(growable: false),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Country'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
