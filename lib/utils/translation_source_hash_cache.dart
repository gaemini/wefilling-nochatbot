import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Retains a fingerprint only as long as its source map is alive. Comparing a
/// small snapshot first avoids hashing every mounted comment on every result
/// notification, without treating a mutable source map as immutable.
class TranslationSourceHashCache {
  static const maxSourceChars = 12000;
  final Expando<({Map<String, String> fields, String hash})> _entries =
      Expando('translation source hashes');

  String hashFor(Map<String, String> fields) {
    final cached = _entries[fields];
    if (cached != null && mapEquals(cached.fields, fields)) return cached.hash;

    final keys = fields.keys.toList(growable: false)..sort();
    final canonical = keys.map((key) {
      final normalized =
          fields[key]!.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final bounded = normalized.length <= maxSourceChars
          ? normalized
          : normalized.substring(0, maxSourceChars);
      return '$key\u0000$bounded';
    }).join('\u0001');
    final hash = sha256.convert(utf8.encode(canonical)).toString();
    _entries[fields] = (fields: Map<String, String>.of(fields), hash: hash);
    return hash;
  }
}
