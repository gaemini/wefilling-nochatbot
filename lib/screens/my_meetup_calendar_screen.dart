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
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
      _meetupDocSubs = {};

  final Map<String, Meetup> _meetupById = {};
  Set<String> _currentMeetupIds = {};

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _format = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _startStreams();
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
      _meetupDocSubs[id] = _firestore
          .collection('meetups')
          .doc(id)
          .snapshots()
          .listen((doc) {
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
      maxParticipants: (data['maxParticipants'] is int) ? data['maxParticipants'] as int : 0,
      currentParticipants:
          (data['currentParticipants'] is int) ? data['currentParticipants'] as int : 1,
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
      isCompleted: (data['isCompleted'] is bool) ? data['isCompleted'] as bool : false,
      hasReview: (data['hasReview'] is bool) ? data['hasReview'] as bool : false,
      reviewId: data['reviewId']?.toString(),
      viewCount: (data['viewCount'] is int) ? data['viewCount'] as int : 0,
      commentCount: (data['commentCount'] is int) ? data['commentCount'] as int : 0,
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

  Widget _buildDayCell({
    required BuildContext context,
    required DateTime day,
    required bool isSelected,
    required bool isToday,
    required bool hasEvents,
    bool isOutside = false,
  }) {
    // ✅ "오늘"은 사용자가 선택해도 항상 파란색 유지
    // - 선택 색(회색)은 오늘이 아닐 때만 적용
    final fillColor = isToday
        ? AppColors.pointColor
        : (isSelected ? const Color(0xFFE5E7EB) : Colors.transparent);

    final border = hasEvents
        ? Border.all(
            color: const Color(0xFFEF4444), // ✅ 모임 있는 날: 빨간 테두리 원(1개)
            width: 1.6,
          )
        : null;

    final textColor = isOutside
        ? const Color(0xFFCBD5E1)
        : (isToday ? Colors.white : const Color(0xFF111827));

    return Center(
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fillColor,
          shape: BoxShape.circle,
          border: border,
        ),
        child: Text(
          '${day.day}',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: isSelected || isToday ? FontWeight.w900 : FontWeight.w700,
            color: textColor,
          ),
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
          title: Text(lang == 'ko' ? '내 모임 달력' : 'My meetup calendar'),
          foregroundColor: const Color(0xFF111827),
        ),
        body: Center(
          child: Text(lang == 'ko' ? '로그인이 필요해요.' : 'Login required.'),
        ),
      );
    }

    final eventsMap = _buildEventMap();
    final selected = _selectedDay ?? _focusedDay;
    final selectedEvents = eventsMap[_dayKey(selected.toLocal())] ?? const <Meetup>[];

    return Scaffold(
      backgroundColor: const Color(0xFFEBEBEB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF111827),
        title: Text(lang == 'ko' ? '내 모임 달력' : 'My meetup calendar'),
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
              calendarFormat: _format,
              startingDayOfWeek: StartingDayOfWeek.monday,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              onFormatChanged: (format) {
                setState(() => _format = format);
              },
              eventLoader: (day) => eventsMap[_dayKey(day.toLocal())] ?? const <Meetup>[],
              calendarBuilders: CalendarBuilders<Meetup>(
                // ✅ 기존 빨간 점(마커) 제거
                markerBuilder: (context, day, events) => const SizedBox.shrink(),
                defaultBuilder: (context, day, focusedDay) {
                  final hasEvents =
                      (eventsMap[_dayKey(day.toLocal())]?.isNotEmpty ?? false);
                  final isToday = isSameDay(day, DateTime.now());
                  final isSelected = isSameDay(day, _selectedDay);
                  return _buildDayCell(
                    context: context,
                    day: day,
                    isSelected: isSelected,
                    isToday: isToday,
                    hasEvents: hasEvents,
                  );
                },
                todayBuilder: (context, day, focusedDay) {
                  final hasEvents =
                      (eventsMap[_dayKey(day.toLocal())]?.isNotEmpty ?? false);
                  final isSelected = isSameDay(day, _selectedDay);
                  return _buildDayCell(
                    context: context,
                    day: day,
                    isSelected: isSelected,
                    isToday: true,
                    hasEvents: hasEvents,
                  );
                },
                selectedBuilder: (context, day, focusedDay) {
                  final hasEvents =
                      (eventsMap[_dayKey(day.toLocal())]?.isNotEmpty ?? false);
                  final isToday = isSameDay(day, DateTime.now());
                  return _buildDayCell(
                    context: context,
                    day: day,
                    isSelected: true,
                    isToday: isToday,
                    hasEvents: hasEvents,
                  );
                },
              ),
              headerStyle: const HeaderStyle(
                titleCentered: true,
                formatButtonVisible: true,
                formatButtonShowsNext: false,
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
                        lang == 'ko' ? '이 날엔 모임이 없어요.' : 'No meetups on this day.',
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

