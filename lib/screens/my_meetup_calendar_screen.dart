import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../constants/app_constants.dart';
import '../models/meetup.dart';
import '../services/meetup_calendar_cache_service.dart';
import '../services/meetup_service.dart';
import '../ui/widgets/board_meetup_card.dart';
import '../utils/logger.dart';
import 'meetup_detail_screen.dart';

class MyMeetupCalendarScreen extends StatefulWidget {
  const MyMeetupCalendarScreen({super.key});

  @override
  State<MyMeetupCalendarScreen> createState() => _MyMeetupCalendarScreenState();
}

class _MyMeetupCalendarScreenState extends State<MyMeetupCalendarScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _meetupService = MeetupService();
  final _calendarCache = MeetupCalendarCacheService.instance;

  StreamSubscription? _hostedSub;
  StreamSubscription? _participatingSub;
  Set<String> _hostedMeetupIds = <String>{};
  // ✅ "내 참여 모임" = 승인(approved) + 참여 신청(pending) 모두 포함
  // - 요구사항: 미래 모임에서 "참여 신청한 모임"도 보여야 함
  Set<String> _participatingApprovedMeetupIds = <String>{};

  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
      _meetupDocSubs = {};

  final Map<String, Meetup> _meetupById = {};
  Set<String> _currentMeetupIds = {};

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  String _monthName(int month) {
    const names = <int, String>{
      1: 'January',
      2: 'February',
      3: 'March',
      4: 'April',
      5: 'May',
      6: 'June',
      7: 'July',
      8: 'August',
      9: 'September',
      10: 'October',
      11: 'November',
      12: 'December',
    };
    return names[month] ?? '';
  }

  String _dowLabel(BuildContext context, DateTime day) {
    final code = Localizations.localeOf(context).languageCode;
    // DateTime.weekday: Mon=1 ... Sun=7
    if (code == 'ko') {
      const labels = {
        1: '월',
        2: '화',
        3: '수',
        4: '목',
        5: '금',
        6: '토',
        7: '일',
      };
      return labels[day.weekday] ?? '';
    }
    const labels = {
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
      7: 'Sun',
    };
    return labels[day.weekday] ?? '';
  }

  Color _weekdayColor(DateTime day) {
    // DateTime.weekday: Mon=1 ... Sun=7
    if (day.weekday == DateTime.saturday)
      return const Color(0xFF3B82F6); // blue
    if (day.weekday == DateTime.sunday) return const Color(0xFFEF4444); // red
    return const Color(0xFF6B7280);
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _startStreams();

    // ✅ 친구 미래 모임은 "월 단위 캐시"로 동작 (페이지 재진입 시 재조회 최소화)
    _calendarCache.addListener(_handleCalendarCacheUpdated);
    _calendarCache.start();
    unawaited(_calendarCache.warmMonth(_focusedDay));
    unawaited(_calendarCache.warmDay(_selectedDay!));
  }

  @override
  void dispose() {
    _hostedSub?.cancel();
    _participatingSub?.cancel();
    for (final s in _meetupDocSubs.values) {
      s.cancel();
    }
    _meetupDocSubs.clear();
    _calendarCache.removeListener(_handleCalendarCacheUpdated);
    super.dispose();
  }

  void _handleCalendarCacheUpdated() {
    if (!mounted) return;
    setState(() {});
  }

  void _startStreams() {
    final user = _auth.currentUser;
    if (user == null) return;

    // 1) 내가 호스트인 모임들
    _hostedSub = _firestore
        .collection('meetups')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
      _hostedMeetupIds = snapshot.docs.map((d) => d.id).toSet();
      _recomputeAndSyncMeetupIds();
    }, onError: (e) {
      Logger.error('내가 만든 모임 스트림 오류: $e');
    });

    // 2) 내가 참여(승인/신청)한 모임들
    _participatingSub = _firestore
        .collection('meetup_participants')
        .where('userId', isEqualTo: user.uid)
        // 승인 + 신청(대기) 모두 포함
        .where('status', whereIn: const ['approved', 'pending'])
        .snapshots()
        .listen((snapshot) {
          _participatingApprovedMeetupIds = snapshot.docs
              .map((d) => (d.data()['meetupId'] ?? '').toString())
              .where((id) => id.isNotEmpty)
              .toSet();
          _recomputeAndSyncMeetupIds();
        }, onError: (e) {
          Logger.error('내 참여 모임 스트림 오류: $e');
        });
  }

  void _recomputeAndSyncMeetupIds() {
    final next = <String>{
      ..._hostedMeetupIds,
      ..._participatingApprovedMeetupIds,
    };
    _syncMeetupDocSubs(next);
  }

  void _syncMeetupDocSubs(Set<String> nextIds) {
    // unsubscribe removed
    final removed = _currentMeetupIds.difference(nextIds);
    for (final id in removed) {
      _meetupDocSubs[id]?.cancel();
      _meetupDocSubs.remove(id);
      _meetupById.remove(id);
    }

    // subscribe new
    for (final id in nextIds) {
      if (_meetupDocSubs.containsKey(id)) continue;
      _meetupDocSubs[id] =
          _firestore.collection('meetups').doc(id).snapshots().listen((doc) {
        if (!doc.exists || doc.data() == null) {
          _meetupById.remove(id);
        } else {
          final meetup = _meetupFromDoc(doc);
          _meetupById[id] = meetup;
        }
        if (mounted) setState(() {});
      }, onError: (e) {
        Logger.error('모임 문서 스트림 오류($id): $e');
      });
    }

    _currentMeetupIds = nextIds;
  }

  Meetup _meetupFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final date = _parseDate(data['date']);

    final rawUrls = data['imageUrls'];
    final parsedUrls = (rawUrls is List)
        ? rawUrls
            .map((e) => e.toString())
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : <String>[];

    return Meetup(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      location: (data['location'] ?? '').toString(),
      time: (data['time'] ?? '').toString(),
      maxParticipants:
          (data['maxParticipants'] is int) ? data['maxParticipants'] as int : 0,
      currentParticipants: (data['currentParticipants'] is int)
          ? data['currentParticipants'] as int
          : 1,
      host: (data['host'] ?? data['hostNickname'] ?? '').toString(),
      hostNationality: (data['hostNationality'] ?? '').toString(),
      hostPhotoURL: (data['hostPhotoURL'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? '').toString(),
      thumbnailContent: (data['thumbnailContent'] ?? '').toString(),
      thumbnailImageUrl: (data['thumbnailImageUrl'] ?? '').toString(),
      imageUrls: parsedUrls,
      date: date,
      category: (data['category'] ?? '기타').toString(),
      userId: data['userId']?.toString(),
      hostNickname: data['hostNickname']?.toString(),
      visibility: (data['visibility'] ?? 'public').toString(),
      visibleToCategoryIds: (data['visibleToCategoryIds'] is List)
          ? List<String>.from(data['visibleToCategoryIds'] as List)
          : const [],
      isCompleted:
          (data['isCompleted'] is bool) ? data['isCompleted'] as bool : false,
      hasReview:
          (data['hasReview'] is bool) ? data['hasReview'] as bool : false,
      reviewId: data['reviewId']?.toString(),
      viewCount: (data['viewCount'] is int) ? data['viewCount'] as int : 0,
      commentCount:
          (data['commentCount'] is int) ? data['commentCount'] as int : 0,
    );
  }

  DateTime _parseDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) {
      final s = raw.trim();
      if (s.isNotEmpty) {
        final normalized = s.replaceAll('.', '-').replaceAll('/', '-');
        final datePart = normalized.split(' ').first;
        final parts = datePart.split('-');
        if (parts.length >= 3) {
          final y = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final d = int.tryParse(parts[2]);
          if (y != null && m != null && d != null) {
            return DateTime(y, m, d);
          }
        }
      }
    }
    return DateTime.now();
  }

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _startOfToday() {
    final now = DateTime.now().toLocal();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isToday(DateTime day) => isSameDay(day, DateTime.now());

  bool _isFutureDay(DateTime day) {
    final d = _dayKey(day.toLocal());
    return d.isAfter(_startOfToday());
  }

  Map<DateTime, List<Meetup>> _buildEventMap() {
    final map = <DateTime, List<Meetup>>{};
    for (final m in _meetupById.values) {
      final key = _dayKey(m.date.toLocal());
      (map[key] ??= <Meetup>[]).add(m);
    }
    // 간단 정렬: 시간 문자열 시작 HH:mm 우선
    int minutes(String raw) {
      final t = raw.trim();
      if (!t.contains(':')) return 24 * 60 + 1;
      final start = t.split('~').first.trim();
      final parts = start.split(':');
      final h = int.tryParse(parts[0].trim()) ?? 23;
      final m = int.tryParse(parts[1].trim()) ?? 59;
      return (h.clamp(0, 23) * 60) + m.clamp(0, 59);
    }

    for (final k in map.keys) {
      map[k]!.sort((a, b) => minutes(a.time).compareTo(minutes(b.time)));
    }
    return map;
  }

  DateTime _monthStartKey(DateTime focusedDay) =>
      DateTime(focusedDay.year, focusedDay.month, 1);

  DateTime _monthEndKey(DateTime focusedDay) {
    final monthStart = _monthStartKey(focusedDay);
    final nextMonthStart = (monthStart.month == 12)
        ? DateTime(monthStart.year + 1, 1, 1)
        : DateTime(monthStart.year, monthStart.month + 1, 1);
    return nextMonthStart.subtract(const Duration(days: 1));
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

  List<Meetup> _eventsFor(DateTime day) {
    final map = _buildEventMap();
    return map[_dayKey(day.toLocal())] ?? const <Meetup>[];
  }

  bool _isPastDay(DateTime day) {
    final now = DateTime.now().toLocal();
    final startToday = DateTime(now.year, now.month, now.day);
    final d = _dayKey(day.toLocal());
    return d.isBefore(startToday);
  }

  Widget _buildDayCell({
    required BuildContext context,
    required DateTime day,
    required bool isSelected,
    required bool isToday,
    required bool showCheck,
    required Color checkColor,
    bool isOutside = false,
  }) {
    // ✅ "오늘"은 사용자가 선택해도 항상 파란색 유지
    // - 선택 색(회색)은 오늘이 아닐 때만 적용
    final fillColor = isToday
        ? AppColors.pointColor
        : (isSelected ? const Color(0xFFE5E7EB) : Colors.transparent);

    final weekendColor = day.weekday == DateTime.saturday
        ? const Color(0xFF3B82F6)
        : (day.weekday == DateTime.sunday
            ? const Color(0xFFEF4444)
            : const Color(0xFF111827));

    final textColor = isOutside
        ? const Color(0xFFCBD5E1)
        : (isToday ? Colors.white : weekendColor);

    return Center(
      child: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fillColor,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: isSelected || isToday
                        ? FontWeight.w900
                        : FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
            ),
            if (showCheck)
              Positioned(
                right: -1,
                top: -1,
                child: _MeetupCheckMark(
                  size: 16,
                  color: checkColor,
                  strokeWidth: 2.6, // 기존보다 2배 정도 더 두껍게
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMeetup(Meetup meetup) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeetupDetailScreen(
          meetup: meetup,
          meetupId: meetup.id,
          onMeetupDeleted: () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final lang = Localizations.localeOf(context).languageCode;

    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFEBEBEB),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          title: Text(
            lang == 'ko' ? '내 모임 달력' : 'My meetup calendar',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
              letterSpacing: -0.2,
            ),
          ),
          foregroundColor: const Color(0xFF111827),
        ),
        body: Center(
          child: Text(lang == 'ko' ? '로그인이 필요해요.' : 'Login required.'),
        ),
      );
    }

    final eventsMap = _buildEventMap();
    final selected = _selectedDay ?? _focusedDay;
    final selectedKey = _dayKey(selected.toLocal());
    final todayKey = _startOfToday();

    // ✅ 요구사항: "선택한 날짜"의 모임만 표시(미래 모임들만)
    // - 오늘/미래 날짜: 내 모임 + 친구가 만든 모임(참여 여부 무관) 합쳐서 표시
    // - 과거 날짜: 표시하지 않음
    final isFutureOrToday = !selectedKey.isBefore(todayKey);
    final selectedMyMeetups = eventsMap[selectedKey] ?? const <Meetup>[];
    final selectedFriendMeetups =
        _calendarCache.friendMeetupsForDay(selectedKey);

    // ✅ 요구사항:
    // - 오늘/미래: 선택 날짜의 (내 모임 + 친구 모임[나에게 보이는 공개범위])만 표시
    // - 과거: 선택 날짜의 (내가 참여 신청/참가한 모임 + 내가 만든 모임)만 표시
    final selectedMeetups = (() {
      final byId = <String, Meetup>{};
      if (isFutureOrToday) {
        for (final m in selectedMyMeetups) {
          byId[m.id] = m;
        }
        for (final m in selectedFriendMeetups) {
          byId[m.id] = m;
        }
      } else {
        // 과거는 내 모임(내가 만든/참여 신청/참가)만
        for (final m in selectedMyMeetups) {
          byId[m.id] = m;
        }
      }

      final merged = byId.values.toList()
        ..sort((a, b) {
          final d = a.date.compareTo(b.date);
          if (d != 0) return d;
          return _minutesFromMeetupTime(a.time)
              .compareTo(_minutesFromMeetupTime(b.time));
        });
      return merged;
    })();

    final bool isSelectedToday = isSameDay(selected, DateTime.now());
    final String listTitle = _isPastDay(selected)
        ? (lang == 'ko' ? '지난 모임(신청/참여)' : 'Past meetups')
        : (isSelectedToday
            ? (lang == 'ko' ? '오늘 모임' : "Today's meetups")
            : (lang == 'ko'
                ? '${selected.month}월 ${selected.day}일 모임'
                : 'Meetups on ${_monthName(selected.month)} ${selected.day}'));

    return Scaffold(
      backgroundColor: const Color(0xFFEBEBEB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF111827),
        title: Text(
          lang == 'ko' ? '내 모임 달력' : 'My meetup calendar',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TableCalendar<Meetup>(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2035, 12, 31),
              focusedDay: _focusedDay,
              // ✅ 한국어 화면인데도 월이 영어로 나오는 문제 방지:
              // table_calendar는 locale을 명시하지 않으면 header formatter에 null이 전달될 수 있음.
              locale: lang == 'ko' ? 'ko_KR' : 'en_US',
              calendarFormat: CalendarFormat.month,
              // 요구사항: 일요일(Sun)부터 시작
              startingDayOfWeek: StartingDayOfWeek.sunday,
              onPageChanged: (focusedDay) {
                setState(() => _focusedDay = focusedDay);
                // ✅ 달 이동 시: 친구 미래 모임 월 캐시 예열
                unawaited(_calendarCache.warmMonth(focusedDay));
              },
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
                // ✅ 날짜 선택 시: 해당 월 캐시가 없으면 예열(쿼리 1회)
                unawaited(_calendarCache.warmDay(selectedDay));
              },
              eventLoader: (day) =>
                  eventsMap[_dayKey(day.toLocal())] ?? const <Meetup>[],
              calendarBuilders: CalendarBuilders<Meetup>(
                // 요일 헤더: Sat 파랑, Sun 빨강 + Bold
                dowBuilder: (context, day) {
                  return Center(
                    child: Text(
                      _dowLabel(context, day),
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _weekdayColor(day),
                      ),
                    ),
                  );
                },
                // ✅ 기존 빨간 점(마커) 제거
                markerBuilder: (context, day, events) =>
                    const SizedBox.shrink(),
                defaultBuilder: (context, day, focusedDay) {
                  final isToday = isSameDay(day, DateTime.now());
                  final isSelected = isSameDay(day, _selectedDay);
                  final isPast = _isPastDay(day);
                  final isFuture = _isFutureDay(day);
                  // 요구사항:
                  // - 과거(<오늘): 수정 전 동작 유지(해당 날짜에 모임이 있으면 체크, 빨강)
                  // - 미래(>오늘): 해당 날짜에 모임이 있으면 체크(파랑/로고색)
                  // - 오늘: 체크 표시 없음
                  final key = _dayKey(day.toLocal());
                  final futureHasAny = (eventsMap[key]?.isNotEmpty ?? false) ||
                      _calendarCache.hasFriendMeetupOnDay(key);
                  final showCheck =
                      (isPast && (eventsMap[key]?.isNotEmpty ?? false)) ||
                          (isFuture && futureHasAny);
                  final checkColor =
                      isPast ? const Color(0xFFEF4444) : AppColors.pointColor;
                  return _buildDayCell(
                    context: context,
                    day: day,
                    isSelected: isSelected,
                    isToday: isToday,
                    showCheck: showCheck,
                    checkColor: checkColor,
                  );
                },
                todayBuilder: (context, day, focusedDay) {
                  final isSelected = isSameDay(day, _selectedDay);
                  final key = _dayKey(day.toLocal());
                  final hasAnyToday = (eventsMap[key]?.isNotEmpty ?? false) ||
                      _calendarCache.hasFriendMeetupOnDay(key);
                  return _buildDayCell(
                    context: context,
                    day: day,
                    isSelected: isSelected,
                    isToday: true,
                    showCheck: hasAnyToday, // ✅ 오늘도 모임이 있으면 체크 표시
                    checkColor: AppColors.pointColor,
                  );
                },
                selectedBuilder: (context, day, focusedDay) {
                  final isToday = isSameDay(day, DateTime.now());
                  final isPast = _isPastDay(day);
                  final isFuture = _isFutureDay(day);
                  final key = _dayKey(day.toLocal());
                  final futureHasAny = (eventsMap[key]?.isNotEmpty ?? false) ||
                      _calendarCache.hasFriendMeetupOnDay(key);
                  final showCheck =
                      (isPast && (eventsMap[key]?.isNotEmpty ?? false)) ||
                          (isFuture && futureHasAny);
                  final checkColor =
                      isPast ? const Color(0xFFEF4444) : AppColors.pointColor;
                  return _buildDayCell(
                    context: context,
                    day: day,
                    isSelected: true,
                    isToday: isToday,
                    showCheck: showCheck,
                    checkColor: checkColor,
                  );
                },
              ),
              headerStyle: HeaderStyle(
                titleCentered: true,
                // ✅ "Month" 포맷 버튼 제거 + 제목을 정확히 중앙으로
                formatButtonVisible: false,
                leftChevronMargin: EdgeInsets.zero,
                rightChevronMargin: EdgeInsets.zero,
                leftChevronPadding: EdgeInsets.zero,
                rightChevronPadding: EdgeInsets.zero,
                titleTextFormatter: (date, locale) {
                  final loc = locale.toString().toLowerCase();
                  final isKo = loc.startsWith('ko');
                  return isKo
                      ? '${date.year}년 ${date.month}월'
                      : '${_monthName(date.month)} ${date.year}';
                },
                titleTextStyle: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                  letterSpacing: -0.2,
                ),
              ),
              calendarStyle: const CalendarStyle(
                outsideDaysVisible: false,
                todayDecoration: BoxDecoration(
                  color: AppColors.pointColor,
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: Color(0xFFE5E7EB), // ✅ 선택 날짜: 회색
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                  child: Text(
                    listTitle,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                if (selectedMeetups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        lang == 'ko'
                            ? (_isPastDay(selected)
                                ? '이 날엔 신청/참여한 모임이 없어요.'
                                : '이 날엔 모임이 없어요.')
                            : (isFutureOrToday
                                ? 'No meetups on this day.'
                                : 'No meetups on this day.'),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  )
                else
                  ...selectedMeetups.map((m) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: StreamBuilder<int>(
                        stream: _meetupService.participantCountStream(
                          m.id,
                          fallback: m.currentParticipants,
                        ),
                        builder: (context, snap) {
                          final count = snap.data ?? m.currentParticipants;
                          return BoardMeetupCard(
                            meetup: m,
                            currentParticipants: count,
                            onTap: () => _openMeetup(m),
                          );
                        },
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MeetupCheckMark extends StatelessWidget {
  final double size;
  final Color color;
  final double strokeWidth;

  const _MeetupCheckMark({
    required this.size,
    required this.color,
    required this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MeetupCheckMarkPainter(
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _MeetupCheckMarkPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const _MeetupCheckMarkPainter({
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 16x16 기준으로 보기 좋은 체크 형태.
    // 크기가 바뀌어도 비율 유지되도록 size 기반으로 좌표를 잡는다.
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.18, h * 0.58)
      ..lineTo(w * 0.42, h * 0.80)
      ..lineTo(w * 0.84, h * 0.28);

    canvas.drawPath(path, paint);
  }  @override
  bool shouldRepaint(covariant _MeetupCheckMarkPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
