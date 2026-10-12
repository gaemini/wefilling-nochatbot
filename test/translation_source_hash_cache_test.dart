import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/translation_source_hash_cache.dart';

String legacyHash(Map<String, String> fields) {
  final keys = fields.keys.toList()..sort();
  return sha256
      .convert(utf8.encode(keys.map((key) {
        final normalized =
            fields[key]!.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
        final bounded = normalized.length > 12000
            ? normalized.substring(0, 12000)
            : normalized;
        return '$key\u0000$bounded';
      }).join('\u0001')))
      .toString();
}

void main() {
  test('keeps existing cache keys including Unicode, line endings and bounds',
      () {
    final cache = TranslationSourceHashCache();
    for (final fields in <Map<String, String>>[
      {},
      {'content': '9월 3일 가능해요?\r\n오후 3시 20분 🙂'},
      {'pollOption:yes': 'Yes', 'content': 'Hello\rWorld'},
      {'content': '가' * 12001},
    ]) {
      expect(cache.hashFor(fields), legacyHash(fields));
      expect(identical(cache.hashFor(fields), cache.hashFor(fields)), isTrue);
    }
    expect(
      cache.hashFor({'b': 'second', 'a': 'first'}),
      cache.hashFor({'a': 'first', 'b': 'second'}),
    );
  });

  test('an edit or field removal invalidates a mutable map fingerprint', () {
    final cache = TranslationSourceHashCache();
    final fields = {'content': 'Before', 'pollOption:a': 'Yes'};
    final before = cache.hashFor(fields);
    fields['content'] = 'After';
    final after = cache.hashFor(fields);
    expect(after, isNot(before));
    expect(after, legacyHash(fields));
    fields.remove('pollOption:a');
    expect(cache.hashFor(fields), isNot(after));
    expect(cache.hashFor(fields), legacyHash(fields));
    fields['new'] = 'Extra';
    expect(cache.hashFor(fields), legacyHash(fields));
  });

  test('benchmark repeated result notifications for 100 mounted comments', () {
    final cache = TranslationSourceHashCache();
    final sources = List.generate(
        100,
        (index) => {
              'content': '$index ${'회의 일정과 답글 내용을 확인해 주세요. ' * 15}',
            });
    // Warm both paths before comparing local work only, with no network calls.
    for (final fields in sources) {
      expect(cache.hashFor(fields), legacyHash(fields));
    }
    final legacy = Stopwatch()..start();
    for (var notification = 0; notification < 100; notification++) {
      for (final fields in sources) {
        legacyHash(fields);
      }
    }
    legacy.stop();
    final optimized = Stopwatch()..start();
    for (var notification = 0; notification < 100; notification++) {
      for (final fields in sources) {
        cache.hashFor(fields);
      }
    }
    optimized.stop();
    // Timing is reported, not asserted: machine load must not make tests flaky.
    // ignore: avoid_print
    print('Source hash benchmark: legacy=${legacy.elapsedMicroseconds}us, '
        'cached=${optimized.elapsedMicroseconds}us (10000 lookups)');
  });
}
