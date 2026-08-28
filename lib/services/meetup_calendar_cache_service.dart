import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/meetup.dart';
import '../services/content_filter_service.dart';
import '../utils/meetup_calendar_marker_policy.dart';
import '../utils/logger.dart';

/// 내 모임 달력 화면의 "친구가 만든 미래 모임"을 효율적으로 캐싱/조회하기 위한 서비스.
///
/// 목표:
/// - 화면 진입/날짜 선택마다 동일한 Firestore 쿼리를 반복하지 않기
/// - 월 단위로 한 번 로드해서 메모리에 캐시하고, 날짜 선택 시 즉시 표시
/// - 친구/카테고리 공개 범위 필터를 클라이언트에서 빠르게 적용
class MeetupCalendarCacheService extends ChangeNotifier {
  static final MeetupCalendarCacheService instance =
      MeetupCalendarCacheService._();

  MeetupCalendarCacheService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const Duration _friendContextTtl = Duration(minutes: 10);
  static const Duration _monthCacheTtl = Duration(minutes: 10);

  bool _started = false;
  DateTime? _friendContextFetchedAt;
  Set<String> _friendIds = <String>{};

  final Map<String, _MonthCache> _monthCaches = <String, _MonthCache>{};

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _getAudienceScoped(
      Query<Map<String, dynamic>> baseQuery) async {
    final user = _auth.currentUser;
    if (user == null) return const [];
    final snapshots = await Future.wait([
      baseQuery.where('visibility', isEqualTo: 'public').get(),
      baseQuery.where('allowedUserIds', arrayContains: user.uid).get(),
      baseQuery.where('userId', isEqualTo: user.uid).get(),
    ]);
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        byId[doc.id] = doc;
      }
    }
    return byId.values.toList();
  }

  void start() {
    _started = true;
  }

  /// 선택 날짜를 빠르게 표시하기 위해 해당 월 캐시를 예열합니다.
  Future<void> warmDay(DateTime day) => warmMonth(day);

  /// 해당 월의 친구 미래 모임 데이터를 캐시에 올립니다(TTL).
  Future<void> warmMonth(DateTime focusedDay) async {
    if (!_started) start();
    final user = _auth.currentUser;
    if (user == null) return;

    await _loadFriendContextIfNeeded();

    final monthKey = _monthKey(focusedDay);
    final cache = _monthCaches.putIfAbsent(monthKey, () => _MonthCache());

    if (cache.loading) return;
    final fetchedAt = cache.fetchedAt;
    if (fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _monthCacheTtl) {
      return;
    }

    cache.loading = true;
    cache.lastError = null;
    notifyListeners();

    try {
      final monthStart = DateTime(focusedDay.year, focusedDay.month, 1);
      final monthEnd = DateTime(focusedDay.year, focusedDay.month + 1, 0);

      // ✅ 인덱스 에러를 원천 차단하기 위해:
      // - 복합 인덱스가 필요한 `userId + date/dateKey range` 조합을 사용하지 않는다.
      // - 월 단위로 `dateKey range`만 조회(단일 필드 인덱스) → 친구/공개범위는 클라이언트에서 필터링
      // - 레거시(dateKey 없는 문서)까지 커버하려고, 필요 시 `date range`(userId 조건 없음)로 fallback
      final today = DateTime.now().toLocal();
      final todayStart = DateTime(today.year, today.month, today.day);
      final effectiveStart =
          monthStart.isAfter(todayStart) ? monthStart : todayStart;

      final startKey = _dateKey(effectiveStart);
      final endKey = _dateKey(monthEnd);

      final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

      // 1) 기본: dateKey range (가장 빠르고 인덱스 요구가 최소)
      try {
        final scopedDocs = await _getAudienceScoped(_firestore
            .collection('meetups')
            .where('dateKey', isGreaterThanOrEqualTo: startKey)
            .where('dateKey', isLessThanOrEqualTo: endKey)
            .orderBy('dateKey', descending: false));
        docs.addAll(scopedDocs);
      } catch (e) {
        Logger.error('친구 모임(월) dateKey 쿼리 실패: $e');
      }

      // 2) fallback: 레거시(dateKey 누락) 문서를 위해 date(Timestamp) range로 월 전체를 가져온 뒤 필터링
      if (docs.isEmpty) {
        try {
          final scopedDocs = await _getAudienceScoped(_firestore
              .collection('meetups')
              .where('date', isGreaterThanOrEqualTo: effectiveStart)
              .where(
                'date',
                isLessThanOrEqualTo: DateTime(monthEnd.year, monthEnd.month,
                    monthEnd.day, 23, 59, 59, 999),
              )
              .orderBy('date', descending: false));
          docs.addAll(scopedDocs);
        } catch (e) {
          Logger.error('친구 모임(월) date range fallback 실패: $e');
        }
      }

      final meetups = <Meetup>[];
      for (final d in docs) {
        try {
          meetups
              .add(Meetup.fromJson(<String, dynamic>{...d.data(), 'id': d.id}));
        } catch (e) {
          // 개별 파싱 실패는 무시
          Logger.error('친구 모임(월) 파싱 실패(무시): $e');
        }
      }

      // ✅ 달력에서는 "친구가 만든 모임"만 필요
      final todayKey = _dayKey(DateTime.now());
      final friendMeetups = meetups
          .where((m) => !_dayKey(m.date).isBefore(todayKey)) // 오늘 포함, 미래만
          .where(
            (m) => shouldShowFriendMeetupGradientBorder(
              meetup: m,
              viewerId: user.uid,
              friendIds: _friendIds,
            ),
          )
          .toList();

      final filteredByBlock =
          await ContentFilterService.filterMeetups(friendMeetups);

      final byDay = <DateTime, List<Meetup>>{};
      for (final m in filteredByBlock) {
        final k = _dayKey(m.date);
        (byDay[k] ??= <Meetup>[]).add(m);
      }

      for (final k in byDay.keys) {
        byDay[k]!.sort((a, b) {
          final d = a.date.compareTo(b.date);
          if (d != 0) return d;
          return _minutesFromMeetupTime(a.time)
              .compareTo(_minutesFromMeetupTime(b.time));
        });
      }

      cache.byDayKey = byDay;
      cache.fetchedAt = DateTime.now();
    } catch (e) {
      cache.lastError = e.toString();
      Logger.error('친구 모임(월) 캐시 로드 오류: $e');
    } finally {
      cache.loading = false;
      notifyListeners();
    }
  }

  List<Meetup> friendMeetupsForDay(DateTime dayKey) {
    final user = _auth.currentUser;
    if (user == null) return const <Meetup>[];
    final cache = _monthCaches[_monthKey(dayKey)];
    final cached = cache?.byDayKey[dayKey] ?? const <Meetup>[];
    return cached
        .where(
          (meetup) => shouldShowFriendMeetupGradientBorder(
            meetup: meetup,
            viewerId: user.uid,
            friendIds: _friendIds,
          ),
        )
        .toList(growable: false);
  }

  bool hasFriendMeetupOnDay(DateTime dayKey) {
    return friendMeetupsForDay(dayKey).isNotEmpty;
  }

  Future<void> _loadFriendContextIfNeeded() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final last = _friendContextFetchedAt;
    if (last != null && DateTime.now().difference(last) < _friendContextTtl) {
      return;
    }

    try {
      final friendIds = <String>{};
      final snap = await _firestore
          .collection('friendships')
          .where('uids', arrayContains: user.uid)
          .get();
      for (final d in snap.docs) {
        final data = d.data();
        final uids = (data['uids'] is List)
            ? List<String>.from(data['uids'] as List)
            : const <String>[];
        for (final uid in uids) {
          final v = uid.trim();
          if (v.isEmpty) continue;
          if (v != user.uid) friendIds.add(v);
        }
      }

      _friendIds = friendIds;
      _friendContextFetchedAt = DateTime.now();
    } catch (e) {
      Logger.error('친구 컨텍스트 로드 오류: $e');
      // 실패해도 TTL 갱신은 하지 않음(다음 warm에서 재시도)
    }
  }

  String _monthKey(DateTime d) {
    final local = d.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    return '${local.year}-$m';
  }

  DateTime _dayKey(DateTime d) {
    final local = d.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  String _dateKey(DateTime d) {
    final local = d.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$m-$day';
  }

  int _minutesFromMeetupTime(String raw) {
    final t = raw.trim();
    if (t.isEmpty || t == '미정' || t == 'Undecided' || t == 'TBD') {
      return 24 * 60 + 1;
    }
    if (!t.contains(':')) return 24 * 60 + 1;
    final start = t.split('~').first.trim();
    final parts = start.split(':');
    if (parts.length < 2) return 24 * 60 + 1;
    final h = int.tryParse(parts[0].trim()) ?? 23;
    final m = int.tryParse(parts[1].trim()) ?? 59;
    return (h.clamp(0, 23) * 60) + m.clamp(0, 59);
  }
}

class _MonthCache {
  bool loading = false;
  DateTime? fetchedAt;
  Map<DateTime, List<Meetup>> byDayKey = <DateTime, List<Meetup>>{};
  String? lastError;
}
