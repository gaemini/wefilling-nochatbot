import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/meetup.dart';
import '../services/content_filter_service.dart';
import '../utils/meetup_calendar_marker_policy.dart';
import '../utils/logger.dart';

/// 밋업 달력의 "현재 사용자가 볼 수 있는 미래 모임"을 월별로 캐싱한다.
///
/// 목표:
/// - 화면 진입/날짜 선택마다 동일한 Firestore 쿼리를 반복하지 않기
/// - 월 단위로 한 번 로드해서 메모리에 캐시하고, 날짜 선택 시 즉시 표시
/// - 전체 공개/고정 공개 대상 모임을 함께 보관하고 친구 모임은 별도로 분류
class MeetupCalendarCacheService extends ChangeNotifier {
  static final MeetupCalendarCacheService instance =
      MeetupCalendarCacheService._();

  MeetupCalendarCacheService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const Duration _monthCacheTtl = Duration(minutes: 10);

  bool _started = false;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _friendshipsSubscription;
  String? _friendContextUserId;
  int _friendContextGeneration = 0;
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
    if (!_started) {
      _authSubscription ??= _auth.authStateChanges().listen(
        (user) => _bindFriendContext(user?.uid),
        onError: (Object error) {
          Logger.error('달력 친구 인증 상태 구독 오류: $error');
        },
      );
    }
    _started = true;
    _bindFriendContext(_auth.currentUser?.uid);
  }

  /// 선택 날짜를 빠르게 표시하기 위해 해당 월 캐시를 예열합니다.
  Future<void> warmDay(DateTime day) => warmMonth(day);

  /// 해당 월의 공개 대상 미래 모임 데이터를 캐시에 올립니다(TTL).
  Future<void> warmMonth(DateTime focusedDay) async {
    if (!_started) start();
    final user = _auth.currentUser;
    if (user == null) return;

    _bindFriendContext(user.uid);

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

      final today = DateTime.now().toLocal();
      final todayStart = DateTime(today.year, today.month, today.day);
      if (monthEnd.isBefore(todayStart)) {
        // 이 캐시는 활성 친구 모임 링 전용이다. 과거 원은 표시하지 않으므로
        // 지난 달을 탐색할 때 의미 없는 Firestore 쿼리를 만들지 않는다.
        cache.visibleByDayKey = <DateTime, List<Meetup>>{};
        cache.friendByDayKey = <DateTime, List<Meetup>>{};
        cache.fetchedAt = DateTime.now();
        return;
      }

      // ✅ 인덱스 에러를 원천 차단하기 위해:
      // - 복합 인덱스가 필요한 `userId + date/dateKey range` 조합을 사용하지 않는다.
      // - 월 단위로 `dateKey range`만 조회(단일 필드 인덱스) → 친구/공개범위는 클라이언트에서 필터링
      // - 레거시(dateKey 없는 문서)까지 커버하려고, 필요 시 `date range`(userId 조건 없음)로 fallback
      final effectiveStart =
          monthStart.isAfter(todayStart) ? monthStart : todayStart;

      final startKey = _dateKey(effectiveStart);
      final endKey = _dateKey(monthEnd);

      final docsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

      // 1) 기본: dateKey range (가장 빠르고 인덱스 요구가 최소)
      try {
        final scopedDocs = await _getAudienceScoped(_firestore
            .collection('meetups')
            .where('dateKey', isGreaterThanOrEqualTo: startKey)
            .where('dateKey', isLessThanOrEqualTo: endKey)
            .orderBy('dateKey', descending: false));
        for (final doc in scopedDocs) {
          docsById[doc.id] = doc;
        }
      } catch (e) {
        Logger.error('달력 모임(월) dateKey 쿼리 실패: $e');
      }

      // 2) dateKey가 없는 레거시 문서도 일부만 섞여 있을 수 있으므로 date
      // 범위를 항상 병합한다. dateKey 결과가 하나라도 있다는 이유로 fallback을
      // 건너뛰면 같은 달의 전체 공개 모임이 목록에서 누락될 수 있다.
      try {
        final scopedDocs = await _getAudienceScoped(_firestore
            .collection('meetups')
            .where('date', isGreaterThanOrEqualTo: effectiveStart)
            .where(
              'date',
              isLessThanOrEqualTo: DateTime(
                  monthEnd.year, monthEnd.month, monthEnd.day, 23, 59, 59, 999),
            )
            .orderBy('date', descending: false));
        for (final doc in scopedDocs) {
          docsById[doc.id] = doc;
        }
      } catch (e) {
        Logger.error('모임(월) date range 보완 쿼리 실패: $e');
      }

      final meetups = <Meetup>[];
      for (final d in docsById.values) {
        try {
          meetups
              .add(Meetup.fromJson(<String, dynamic>{...d.data(), 'id': d.id}));
        } catch (e) {
          // 개별 파싱 실패는 무시
          Logger.error('달력 모임(월) 파싱 실패(무시): $e');
        }
      }

      final todayKey = _dayKey(DateTime.now());
      final visibleMeetups = meetups
          .where((m) => !_dayKey(m.date).isBefore(todayKey)) // 오늘 포함, 미래만
          .where(
            (m) => shouldShowVisibleMeetupBorder(
              meetup: m,
              viewerId: user.uid,
            ),
          )
          .toList();

      final filteredVisible =
          await ContentFilterService.filterMeetups(visibleMeetups);
      final friendMeetups = filteredVisible
          .where(
            (m) => shouldShowFriendMeetupGradientBorder(
              meetup: m,
              viewerId: user.uid,
              friendIds: _friendIds,
            ),
          )
          .toList(growable: false);

      Map<DateTime, List<Meetup>> groupByDay(Iterable<Meetup> source) {
        final byDay = <DateTime, List<Meetup>>{};
        for (final m in source) {
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
        return byDay;
      }

      cache.visibleByDayKey = groupByDay(filteredVisible);
      cache.friendByDayKey = groupByDay(friendMeetups);
      cache.fetchedAt = DateTime.now();
    } catch (e) {
      cache.lastError = e.toString();
      Logger.error('달력 모임(월) 캐시 로드 오류: $e');
    } finally {
      cache.loading = false;
      notifyListeners();
    }
  }

  List<Meetup> visibleMeetupsForDay(DateTime dayKey) {
    final cache = _monthCaches[_monthKey(dayKey)];
    final cached = cache?.visibleByDayKey[_dayKey(dayKey)] ?? const <Meetup>[];
    return cached.where((meetup) {
      final user = _auth.currentUser;
      if (user == null) return false;
      return shouldShowVisibleMeetupBorder(
        meetup: meetup,
        viewerId: user.uid,
      );
    }).toList(growable: false);
  }

  List<Meetup> friendMeetupsForDay(DateTime dayKey) {
    final cache = _monthCaches[_monthKey(dayKey)];
    final cached = cache?.visibleByDayKey[_dayKey(dayKey)] ?? const <Meetup>[];
    return cached.where(isVisibleFriendMeetup).toList(growable: false);
  }

  /// 실시간 밋업 쿼리에서 받은 항목이 친구 테두리 대상인지 판정한다.
  /// 날짜별 마커는 TTL 월 캐시가 아니라 이 판정과 실시간 목록을 결합해야
  /// 삭제된 문서가 즉시 달력에서도 사라진다.
  bool isVisibleFriendMeetup(Meetup meetup) {
    final user = _auth.currentUser;
    if (user == null) return false;
    return shouldShowFriendMeetupGradientBorder(
      meetup: meetup,
      viewerId: user.uid,
      friendIds: _friendIds,
    );
  }

  bool hasFriendMeetupOnDay(DateTime dayKey) {
    return friendMeetupsForDay(dayKey).isNotEmpty;
  }

  void _bindFriendContext(String? rawUserId) {
    final userId = rawUserId?.trim() ?? '';
    if (_friendContextUserId == userId &&
        (_friendshipsSubscription != null || userId.isEmpty)) {
      return;
    }

    _friendContextUserId = userId;
    final generation = ++_friendContextGeneration;
    final previousSubscription = _friendshipsSubscription;
    _friendshipsSubscription = null;
    if (previousSubscription != null) {
      unawaited(previousSubscription.cancel());
    }

    final hadFriendIds = _friendIds.isNotEmpty;
    _friendIds = <String>{};
    // 공개 대상이 로그인 계정마다 다르므로 계정이 바뀌면 월 캐시도 버린다.
    _monthCaches.clear();

    if (userId.isEmpty) {
      if (hadFriendIds) notifyListeners();
      return;
    }

    _friendshipsSubscription = _firestore
        .collection('friendships')
        .where('uids', arrayContains: userId)
        .snapshots()
        .listen(
      (snapshot) {
        if (generation != _friendContextGeneration ||
            _friendContextUserId != userId) {
          return;
        }
        final uidLists = <Iterable<Object?>>[];
        for (final document in snapshot.docs) {
          final rawUids = document.data()['uids'];
          if (rawUids is Iterable) {
            uidLists.add(rawUids.cast<Object?>());
          }
        }
        final nextFriendIds = friendIdsFromFriendshipUidLists(
          viewerId: userId,
          friendshipUidLists: uidLists,
        );
        if (setEquals(_friendIds, nextFriendIds)) return;
        _friendIds = nextFriendIds;
        notifyListeners();
      },
      onError: (Object error) {
        if (generation != _friendContextGeneration) return;
        Logger.error('달력 친구 관계 구독 오류: $error');
      },
    );
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
  Map<DateTime, List<Meetup>> visibleByDayKey = <DateTime, List<Meetup>>{};
  Map<DateTime, List<Meetup>> friendByDayKey = <DateTime, List<Meetup>>{};
  String? lastError;
}
