import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../constants/app_constants.dart';
import '../models/meetup.dart';
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

  StreamSubscription? _hostedSub;
  StreamSubscription? _participatingSub;
  int _friendFutureLoadToken = 0;
  Set<DateTime> _friendFutureMeetupDays = <DateTime>{}; // 날짜 키(자정) Set

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
    // ✅ 미래(오늘 이후): "친구들이 만든 모임" 체크 표시용 로드
    unawaited(_loadFriendFutureMeetupsForMonth(_focusedDay));
  }

  @override
  void dispose() {
    _hostedSub?.cancel();
    _participatingSub?.cancel();
    for (final s in _meetupDocSubs.values) {
      s.cancel();
    }
    _meetupDocSubs.clear();
    super.dispose();
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
      final hostedIds = snapshot.docs.map((d) => d.id).toSet();
      _updateMeetupIds(hostedIds, source: 'hosted');
    }, onError: (e) {
      Logger.error('내가 만든 모임 스트림 오류: $e');
    });

    // 2) 내가 참여(승인)한 모임들
    _participatingSub = _firestore
        .collection('meetup_participants')
        .where('userId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .listen((snapshot) {
      final ids = snapshot.docs
          .map((d) => (d.data()['meetupId'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
      _updateMeetupIds(ids, source: 'participating');
    }, onError: (e) {
      Logger.error('내 참여 모임 스트림 오류: $e');
    });
  }

  void _updateMeetupIds(Set<String> incoming, {required String source}) {
    // 두 스트림(호스트/참여)의 합집합을 유지해야 하므로,
    // source별로 보관하지 않고 "현재까지 알려진 id"에 merge 방식으로 처리.
    // 최신 상태를 정확히 하려면 두 소스 모두의 최신 set이 필요하지만,
    // 여기선 doc 스트림이 final truth라서 id가 빠질 때는 doc 삭제/권한 변화로 정리된다.
    final next = {..._currentMeetupIds, ...incoming};
    _syncMeetupDocSubs(next);
  }

  void _syncMeetupDocSubs(Set<String> nextIds) {
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

  /// 미래(오늘 이후) 날짜에 대해 "친구들이 만든 모임"이 있는 날을 로드합니다.
  /// - 체크 표시만 필요하므로 dayKey Set만 유지
  Future<void> _loadFriendFutureMeetupsForMonth(DateTime focusedDay) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final token = ++_friendFutureLoadToken;

    // 이번 focused 달 범위
    final monthStart = DateTime(focusedDay.year, focusedDay.month, 1);
    final nextMonthStart = (focusedDay.month == 12)
        ? DateTime(focusedDay.year + 1, 1, 1)
        : DateTime(focusedDay.year, focusedDay.month + 1, 1);
    final monthEnd = nextMonthStart.subtract(const Duration(microseconds: 1));

    // 오늘은 제외(오늘 체크표시 금지), 내일(오늘+1)부터
    final tomorrow = _startOfToday().add(const Duration(days: 1));
    final effectiveStart = monthStart.isAfter(tomorrow) ? monthStart : tomorrow;
    if (effectiveStart.isAfter(monthEnd)) {
      if (!mounted || token != _friendFutureLoadToken) return;
      setState(() => _friendFutureMeetupDays = <DateTime>{});
      return;
    }

    try {
      // 친구 ID 목록
      final friendsSnapshot = await _firestore
          .collection('relationships')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'accepted')
          .get();
      final friendIds = friendsSnapshot.docs
          .map((d) => (d.data()['friendId'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (friendIds.isEmpty) {
        if (!mounted || token != _friendFutureLoadToken) return;
        setState(() => _friendFutureMeetupDays = <DateTime>{});
        return;
      }

      // Firestore whereIn 제한(10) 대응: 청크 쿼리
      const chunkSize = 10;
      final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
      for (var i = 0; i < friendIds.length; i += chunkSize) {
        final chunk = friendIds.sublist(
          i,
          (i + chunkSize) > friendIds.length
              ? friendIds.length
              : (i + chunkSize),
        );
        futures.add(
          _firestore
              .collection('meetups')
              .where('userId', whereIn: chunk)
              .where('date', isGreaterThanOrEqualTo: effectiveStart)
              .where('date', isLessThanOrEqualTo: monthEnd)
              .orderBy('date', descending: false)
              .get(),
        );
      }

      final snapshots = await Future.wait(futures, eagerError: false);
      final meetups = <Meetup>[];
      for (final snap in snapshots) {
        for (final doc in snap.docs) {
          meetups.add(_meetupFromDoc(doc));
        }
      }

      // 공개 범위 필터(친구/카테고리 공개 포함) 적용
      final visible = await _meetupService.filterMeetupsForCurrentUser(meetups);

      // "친구들이 만든 모임" + "미래(오늘 이후)"만 dayKey Set으로
      final todayKey = _startOfToday();
      final dayKeys = visible
          .where((m) => m.userId != null && friendIds.contains(m.userId))
          .where((m) => _dayKey(m.date.toLocal()).isAfter(todayKey))
          .map((m) => _dayKey(m.date.toLocal()))
          .toSet();

      if (!mounted || token != _friendFutureLoadToken) return;
      setState(() => _friendFutureMeetupDays = dayKeys);
    } catch (e) {
      Logger.error('친구 미래 모임 로드 오류: $e');
      if (!mounted || token != _friendFutureLoadToken) return;
      setState(() => _friendFutureMeetupDays = <DateTime>{});
    }
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
    final selectedEvents =
        eventsMap[_dayKey(selected.toLocal())] ?? const <Meetup>[];

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
                // ✅ 달 이동 시 해당 월의 "친구 미래 모임" 체크 갱신
                unawaited(_loadFriendFutureMeetupsForMonth(focusedDay));
              },
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
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
                  // - 과거(<오늘): 내가 참여했던 모임만 체크(빨강)
                  // - 미래(>오늘): 친구들이 만든 모임이 있으면 체크(파랑)
                  // - 오늘: 체크 표시 없음
                  final showCheck = !isToday &&
                      ((isPast &&
                              (eventsMap[_dayKey(day.toLocal())]?.isNotEmpty ??
                                  false)) ||
                          (isFuture &&
                              _friendFutureMeetupDays
                                  .contains(_dayKey(day.toLocal()))));
                  final checkColor = isPast
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF3B82F6);
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
                  return _buildDayCell(
                    context: context,
                    day: day,
                    isSelected: isSelected,
                    isToday: true,
                    showCheck: false, // ✅ 오늘 날짜는 체크 표시 금지
                    checkColor: const Color(0xFF3B82F6),
                  );
                },
                selectedBuilder: (context, day, focusedDay) {
                  final isToday = isSameDay(day, DateTime.now());
                  final isPast = _isPastDay(day);
                  final isFuture = _isFutureDay(day);
                  final showCheck = !isToday &&
                      ((isPast &&
                              (eventsMap[_dayKey(day.toLocal())]?.isNotEmpty ??
                                  false)) ||
                          (isFuture &&
                              _friendFutureMeetupDays
                                  .contains(_dayKey(day.toLocal()))));
                  final checkColor = isPast
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF3B82F6);
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
                    _isPastDay(selected)
                        ? (lang == 'ko' ? '참여했던 모임' : 'Past meetups')
                        : (lang == 'ko' ? '참여 예정 모임' : 'Upcoming meetups'),
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                if (selectedEvents.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        lang == 'ko'
                            ? '이 날엔 모임이 없어요.'
                            : 'No meetups on this day.',
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
                  ...selectedEvents.map((m) {
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
  }

  @override
  bool shouldRepaint(covariant _MeetupCheckMarkPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
