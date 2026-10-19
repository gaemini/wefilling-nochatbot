import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 카드 댓글 입력 줄의 '화면에 들어올 때 한 번' 반응을 고르는 피드 전역 잠금.
/// - 같은 카드는 하루 한 번만(기기에 postId → yyyy-MM-dd, 최근 500개).
/// - 한 번 발동하면 1.5초 동안 다른 카드는 발동하지 않는다.
/// - 같은 순간 여러 카드가 조건을 채우면 잠깐 모아 가장 위(top이 작은) 카드 하나만.
class CommentInviteNudgeGate {
  CommentInviteNudgeGate._();
  static final instance = CommentInviteNudgeGate._();

  static const _prefsKey = 'comment_invite_nudge_days_v1';
  static const maxRecords = 500;
  static const cooldown = Duration(milliseconds: 1500);
  static const gatherWindow = Duration(milliseconds: 60);

  /// 테스트에서 시간을 바꿔 끼운다.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  final Map<String, String> _days = {};
  bool _loaded = false;
  Future<void>? _loading;
  DateTime? _lastGrant;
  Timer? _gather;
  final _pending = <String, ({double top, VoidCallback onGranted})>{};

  String _today() {
    final t = now();
    return '${t.year.toString().padLeft(4, '0')}-'
        '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  Future<void> _ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey);
        if (raw != null) {
          final map = jsonDecode(raw);
          if (map is Map) {
            for (final entry in map.entries) {
              if (entry.value is String) {
                _days[entry.key.toString()] = entry.value as String;
              }
            }
          }
        }
      } catch (_) {
        // 기록을 못 읽어도 반응만 한 번 더 할 뿐이다.
      }
      _loaded = true;
    }();
  }

  /// 오늘 이 카드에서 이미 반응했거나 댓글을 남겼다.
  bool doneToday(String postId) => _days[postId] == _today();

  /// 조건을 채운 카드가 부른다. 잠깐 모은 뒤 가장 위 카드 하나만 [onGranted].
  Future<void> request(String postId, double top, VoidCallback onGranted) async {
    await _ensureLoaded();
    if (doneToday(postId)) return;
    _pending[postId] = (top: top, onGranted: onGranted);
    _gather ??= Timer(gatherWindow, _decide);
  }

  /// 화면에서 벗어난 카드는 후보에서 뺀다.
  void cancel(String postId) => _pending.remove(postId);

  void _decide() {
    _gather = null;
    if (_pending.isEmpty) return;
    final last = _lastGrant;
    final t = now();
    if (last != null && t.difference(last) < cooldown) {
      _pending.clear();
      return;
    }
    final winner = _pending.entries
        .where((e) => !doneToday(e.key))
        .fold<MapEntry<String, ({double top, VoidCallback onGranted})>?>(
            null, (best, e) => best == null || e.value.top < best.value.top ? e : best);
    _pending.clear();
    if (winner == null) return;
    _lastGrant = t;
    markDone(winner.key);
    winner.value.onGranted();
  }

  /// 반응했거나 댓글을 남긴 카드는 오늘 다시 반응하지 않는다.
  void markDone(String postId) {
    _days.remove(postId);
    _days[postId] = _today();
    while (_days.length > maxRecords) {
      _days.remove(_days.keys.first);
    }
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_days));
    } catch (_) {}
  }

  @visibleForTesting
  void debugReset() {
    _days.clear();
    _loaded = false;
    _loading = null;
    _lastGrant = null;
    _gather?.cancel();
    _gather = null;
    _pending.clear();
    now = DateTime.now;
  }
}
