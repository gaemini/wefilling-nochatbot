// lib/snapshot/snapshot_seen_store.dart
// 이 기기에서 본 스낵 id를 24시간 동안 기억한다(홈 트레이의 "본 스낵" 링 표시용).
// 서버 스키마와 무관하며, 계정별로 키를 나눈다.

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SnapshotSeenStore extends ChangeNotifier {
  SnapshotSeenStore._();

  static final SnapshotSeenStore instance = SnapshotSeenStore._();

  static const Duration retention = Duration(hours: 24);
  static const int _maximumEntries = 400;

  final Map<String, Map<String, int>> _seenByUser =
      <String, Map<String, int>>{};
  final Set<String> _loadingUsers = <String>{};

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _key(String uid) => 'snapshot_seen_v1:$uid';

  bool isSeen(String snapshotId) {
    if (snapshotId.isEmpty) return false;
    final stamp = _seenByUser[_uid]?[snapshotId];
    if (stamp == null) return false;
    return DateTime.now().millisecondsSinceEpoch - stamp <
        retention.inMilliseconds;
  }

  Future<void> ensureLoaded() async {
    final uid = _uid;
    if (uid.isEmpty ||
        _seenByUser.containsKey(uid) ||
        !_loadingUsers.add(uid)) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(uid));
      final loaded = <String, int>{};
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final now = DateTime.now().millisecondsSinceEpoch;
          decoded.forEach((key, value) {
            if (key is String && value is int) {
              if (now - value < retention.inMilliseconds) loaded[key] = value;
            }
          });
        }
      }
      // 로드 중에 기록된 항목을 덮어쓰지 않는다.
      final current = _seenByUser[uid];
      if (current != null) loaded.addAll(current);
      _seenByUser[uid] = loaded;
      notifyListeners();
    } catch (_) {
      _seenByUser.putIfAbsent(uid, () => <String, int>{});
    } finally {
      _loadingUsers.remove(uid);
    }
  }

  /// 스낵을 봤다고 기록한다. 저장 실패는 화면 표시에만 영향을 주므로 삼킨다.
  Future<void> markSeen(String snapshotId) async {
    final uid = _uid;
    if (uid.isEmpty || snapshotId.isEmpty) return;
    final map = _seenByUser.putIfAbsent(uid, () => <String, int>{});
    final already = map.containsKey(snapshotId);
    map[snapshotId] = DateTime.now().millisecondsSinceEpoch;
    if (!already) notifyListeners();
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      map.removeWhere((_, stamp) => now - stamp >= retention.inMilliseconds);
      if (map.length > _maximumEntries) {
        final ordered = map.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        for (final entry in ordered.take(map.length - _maximumEntries)) {
          map.remove(entry.key);
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(uid), jsonEncode(map));
    } catch (_) {}
  }
}
