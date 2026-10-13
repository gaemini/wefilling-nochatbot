// lib/snapshot/mutual_feel_shown_store.dart
// 서로 필링 순간 오버레이를 같은 쌍에 다시 띄우지 않도록 기기에 기록한다.

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MutualFeelShownStore {
  MutualFeelShownStore._();

  static final MutualFeelShownStore instance = MutualFeelShownStore._();

  static const int _maximumEntries = 100;

  String get _key => 'snapshot_mutual_shown_v1:'
      '${FirebaseAuth.instance.currentUser?.uid ?? ''}';

  Future<Map<String, int>> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return <String, int>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      final result = <String, int>{};
      decoded.forEach((key, value) {
        if (key is String && value is int) result[key] = value;
      });
      return result;
    } catch (_) {
      return <String, int>{};
    }
  }

  /// [createdAtMs]는 서로 필링이 열린 시각. 같은 쌍이 30일 뒤 다시 열리면
  /// 시각이 달라져 새로 보여 준다.
  Future<bool> wasShown(String pairKey, int createdAtMs) async {
    final map = await _read();
    return map[pairKey] == createdAtMs;
  }

  Future<void> markShown(String pairKey, int createdAtMs) async {
    try {
      final map = await _read();
      map[pairKey] = createdAtMs;
      if (map.length > _maximumEntries) {
        final ordered = map.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        for (final entry in ordered.take(map.length - _maximumEntries)) {
          map.remove(entry.key);
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(map));
    } catch (_) {}
  }
}
