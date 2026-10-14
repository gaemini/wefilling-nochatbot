// lib/screens/home_screen.dart
// 모임(밋업) 탭 메인 화면
// - 상단 고정 카테고리 칩
// - 기본 접힘 월간 달력(선택 날짜=오늘)
// - 선택한 날짜의 모임만 리스트로 표시

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/meetup.dart';
import '../models/meetup_participant.dart';
import '../services/meetup_service.dart';
import '../services/meetup_calendar_cache_service.dart';
import '../services/preload_service.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/widgets/app_fab.dart';
import '../ui/widgets/meetup_calendar_day_ring.dart';
import '../ui/widgets/meetup_home_card.dart';
import '../ui/widgets/skeletons.dart';
import '../utils/meetup_calendar_marker_policy.dart';
import '../utils/logger.dart';
import 'create_meetup_screen.dart';
import 'meetup_detail_screen.dart';
import 'review_approval_screen.dart';
import '../l10n/ui_locale.dart';
import '../design/tokens.dart';
import '../ui/widgets/motion_selectable.dart';

class MeetupHomePage extends StatefulWidget {
  final String? initialMeetupId; // 알림에서 전달받은 모임 ID

  const MeetupHomePage({super.key, this.initialMeetupId});

  @override
  State<MeetupHomePage> createState() => MeetupHomePageState();
}

class MeetupHomePageState extends State<MeetupHomePage> with PreloadMixin {
  static const int _maxCachedMeetupMonths = 12;
  final MeetupService _meetupService = MeetupService();
  final MeetupCalendarCacheService _calendarCache =
      MeetupCalendarCacheService.instance;

  // UI 상태
  bool _isCalendarExpanded = false; // 요구사항: 기본 접힘
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  String _selectedCategoryKey = 'all';

  // 선택한 날짜와 다가오는 밋업을 한 줄기로 보여 주는 목록.
  final ScrollController _agendaController = ScrollController();

  // ✅ 월 스트림 캐시(리빌드마다 재구독 방지 → 깜빡임 감소)
  late Stream<List<Meetup>> _calendarArchiveStream;
  late Stream<List<Meetup>> _myRelevantMonthStream;
  late Stream<List<Meetup>> _allUpcomingMeetupsStream;
  DateTime _visibleRangeStart = DateTime(1970, 1, 1);
  DateTime _visibleRangeEnd = DateTime(1970, 1, 1);
  DateTime _myStreamMonthKey = DateTime(1970, 1, 1);
  final Map<DateTime, List<Meetup>> _archiveMeetupMonthCache =
      <DateTime, List<Meetup>>{};
  final Map<DateTime, List<Meetup>> _myMeetupMonthCache =
      <DateTime, List<Meetup>>{};

  // 참여 상태 캐시 (깜빡임 방지)
  final Map<String, bool> _participationStatusCache = {};
  final Map<String, DateTime> _participationCacheTime = {};
  final ValueNotifier<int> _meetupCardRevision = ValueNotifier<int>(0);
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  // 참여/나가기 연타 방지 + 최소 로딩 표시(1초)
  final Set<String> _joinLeaveInFlight = <String>{};
  Timer? _calendarMarkerRefreshTimer;

  // 참여 상태 Stream 구독 관리
  final Map<String, StreamSubscription?> _participationSubscriptions = {};

  @override
  void initState() {
    super.initState();

    // 초기 선택 날짜 = 오늘
    final now = DateTime.now().toLocal();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _focusedMonth = _selectedDay;

    _ensureMonthStreams(_focusedMonth);
    // 전체 목록은 화면 진입 때 한 번만 스트림을 만들고 재사용한다. 빌드마다
    // 새 Firestore 구독을 만들지 않아 기존 월간 화면의 조회 흐름에 영향을 주지 않는다.
    _allUpcomingMeetupsStream = _meetupService.getMeetupsByCategory('전체');

    // 친구공개(친구 모임) 마커 캐시 구동
    _calendarCache.start();
    _calendarCache.addListener(_onCalendarCacheChanged);
    unawaited(_calendarCache.warmMonth(_focusedMonth));
    // 모임 일정이 지나면 Firestore 변경이 없어도 테두리가 사라져야 한다.
    _calendarMarkerRefreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) {
      // 주간 날짜 줄이 항상 보이므로 접힘 여부와 무관하게 갱신한다.
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 알림에서 전달받은 모임이 있으면 상세로 이동
      if (widget.initialMeetupId != null) {
        _showMeetupFromNotification(widget.initialMeetupId!);
      }
    });
  }

  @override
  void dispose() {
    _agendaController.dispose();
    _calendarMarkerRefreshTimer?.cancel();
    _calendarCache.removeListener(_onCalendarCacheChanged);
    _meetupCardRevision.dispose();
    for (final subscription in _participationSubscriptions.values) {
      subscription?.cancel();
    }
    _participationSubscriptions.clear();
    super.dispose();
  }

  void _onCalendarCacheChanged() {
    if (!mounted) return;
    setState(() {});
  }

  DateTime _monthKey(DateTime d) {
    final local = d.toLocal();
    return DateTime(local.year, local.month, 1);
  }

  void _ensureMonthStreams(DateTime month) {
    final key = _monthKey(month);
    final visibleRangeContainsMonth =
        !key.isBefore(_visibleRangeStart) && !key.isAfter(_visibleRangeEnd);
    if (!visibleRangeContainsMonth) {
      // 현재 월 양옆을 같은 스트림에 포함해 한 달 경계의 첫 스와이프가
      // 네트워크 재구독과 스켈레톤 전환을 기다리지 않게 한다.
      _visibleRangeStart = DateTime(key.year, key.month - 1, 1);
      _visibleRangeEnd = DateTime(key.year, key.month + 1, 1);
      // 같은 월 쿼리에서 활성 모임과 과거 아카이브를 함께 받아 화면에서
      // 분리한다. 과거 날짜를 눌렀을 때 추가 쿼리가 생기지 않는다.
      _calendarArchiveStream =
          _meetupService.watchReadableMeetupArchiveForMonthRange(
        firstMonth: _visibleRangeStart,
        lastMonth: _visibleRangeEnd,
      );
    }
    if (key != _myStreamMonthKey) {
      _myStreamMonthKey = key;
      _myRelevantMonthStream =
          _meetupService.watchMyRelevantMeetupsForMonth(key);
    }
  }

  void _cacheMeetupsByMonth(
    Map<DateTime, List<Meetup>> cache,
    Iterable<Meetup> meetups,
    Iterable<DateTime> months,
  ) {
    final grouped = <DateTime, List<Meetup>>{};
    for (final meetup in meetups) {
      (grouped[_monthKey(meetup.date)] ??= <Meetup>[]).add(meetup);
    }
    for (final rawMonth in months) {
      final month = _monthKey(rawMonth);
      cache.remove(month);
      cache[month] = grouped[month] ?? const <Meetup>[];
    }
    while (cache.length > _maxCachedMeetupMonths) {
      cache.remove(cache.keys.first);
    }
  }

  List<Meetup> _cachedArchiveRangeMeetups() => <Meetup>[
        for (var month = _visibleRangeStart;
            !month.isAfter(_visibleRangeEnd);
            month = DateTime(month.year, month.month + 1, 1))
          ...?_archiveMeetupMonthCache[month],
      ];

  /// 다른 화면에서 밋업 탭으로 진입할 때 기존 탭 상태와 무관하게 오늘을 연다.
  void showToday() {
    if (!mounted) return;
    _selectDay(DateTime.now(), collapseCalendar: true);
  }

  /// 날짜를 고르면 그 날짜의 주/월 데이터를 준비하고 목록을 맨 위로 올린다.
  void _selectDay(DateTime day, {bool collapseCalendar = false}) {
    final key = _dayKey(day);
    setState(() {
      _selectedDay = key;
      _focusedMonth = DateTime(key.year, key.month);
      _ensureMonthStreams(_focusedMonth);
      if (collapseCalendar) _isCalendarExpanded = false;
    });
    unawaited(_calendarCache.warmMonth(_focusedMonth));
    unawaited(_calendarCache.warmDay(key));
    if (_agendaController.hasClients) {
      if (MotionTokens.reduceMotion(context)) {
        _agendaController.jumpTo(0);
      } else {
        unawaited(_agendaController.animateTo(
          0,
          duration: MotionTokens.medium,
          curve: MotionTokens.curve,
        ));
      }
    }
  }

  /// 접힌 상태에서는 한 주, 펼친 상태에서는 한 달씩 이동한다.
  void _shiftPeriod(int delta) {
    if (_isCalendarExpanded) {
      final month = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
      setState(() {
        _focusedMonth = month;
        _ensureMonthStreams(month);
      });
      unawaited(_calendarCache.warmMonth(month));
      return;
    }
    _selectDay(_selectedDay.add(Duration(days: 7 * delta)));
  }

  // ===== 날짜/포맷 유틸 =====

  DateTime _dayKey(DateTime d) {
    final local = d.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  bool _isPastDay(DateTime day) {
    final today = _dayKey(DateTime.now());
    return _dayKey(day).isBefore(today);
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

  String _firestoreCategoryForKey(String key) {
    // NOTE:
    // - 레거시 문서는 '스터디/식사/...'로 저장된 케이스가 있고
    // - 신규/수정 플로우는 'study/meal/...' 키로 저장한다.
    // 홈(밋업 탭) 필터는 키 기반으로 동작하되, 레거시 값은 정규화로 대응한다.
    return key;
  }

  String _normalizeCategoryKey(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return 'etc';
    final lower = v.toLowerCase();
    switch (lower) {
      case 'study':
      case '스터디':
        return 'study';
      case 'meal':
      case '식사':
      case 'food':
      case '밥':
        return 'meal';
      case 'cafe':
      case '카페':
        return 'cafe';
      case 'trip':
      case 'travel':
      case '여행':
        return 'trip';
      case 'drink':
      case 'drinks':
      case '술':
      case 'hangout':
      case '행아웃':
        return 'hangout';
      case 'culture':
      case '문화':
        return 'culture';
      case 'etc':
      case '기타':
        return 'etc';
      default:
        return lower;
    }
  }

  List<Meetup> _applyCategoryFilter(List<Meetup> meetups) {
    if (_selectedCategoryKey == 'all') return meetups;
    final wantedKey = _firestoreCategoryForKey(_selectedCategoryKey);
    return meetups
        .where((m) => _normalizeCategoryKey(m.category) == wantedKey)
        .toList();
  }

  Map<DateTime, List<Meetup>> _groupByDay(List<Meetup> meetups) {
    final map = <DateTime, List<Meetup>>{};
    for (final m in meetups) {
      final k = _dayKey(m.date);
      (map[k] ??= <Meetup>[]).add(m);
    }
    for (final k in map.keys) {
      map[k]!.sort((a, b) {
        final d = a.date.compareTo(b.date);
        if (d != 0) return d;
        return _minutesFromMeetupTime(a.time)
            .compareTo(_minutesFromMeetupTime(b.time));
      });
    }
    return map;
  }

  String _expandedHeaderLabel(BuildContext context, DateTime focusedMonth) {
    final code = Localizations.localeOf(context).languageCode;
    final local = focusedMonth.toLocal();
    if (code == 'zh') return '${local.month}月';
    if (code == 'ko') {
      return '${local.month}월';
    }
    return DateFormat('MMMM', 'en_US').format(local);
  }

  // ===== 프리로딩(선택 날짜 상위 3개) =====
  @override
  void preloadCriticalContent() {
    // Stream 기반이라 즉시 목록을 알기 어려우므로, 여기서는 no-op 처리
    // (필요하면 추후 선택 날짜 리스트를 state로 보관해 활용 가능)
  }

  @override
  void preloadAdditionalContent() {}

  // ===== 알림에서 모임 상세 열기 =====
  Future<void> _showMeetupFromNotification(String meetupId) async {
    try {
      if (Logger.isVerboseEnabled) Logger.log('🔔 알림에서 모임 로드: $meetupId');
      final meetup = await _meetupService.getMeetupById(meetupId);

      if (meetup != null && mounted) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final kicked = await _meetupService.isUserKickedFromMeetup(
            meetupId: meetupId,
            userId: user.uid,
          );
          if (!mounted) return;
          if (kicked) {
            AppSnackBar.show(
              context,
              message: kickedMeetupAccessMessage(context),
              type: AppSnackBarType.error,
            );
            return;
          }
        }

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeetupDetailScreen(
              meetup: meetup,
              meetupId: meetupId,
              onMeetupDeleted: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.meetupCancelled,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      } else {
        if (Logger.isVerboseEnabled) Logger.log('❌ 모임을 찾을 수 없음: $meetupId');
      }
    } catch (e) {
      Logger.error('❌ 알림 모임 로드 오류: $e');
    }
  }

  // ===== 참여 상태 캐시 =====
  bool? _getCachedParticipationStatus(String meetupId) {
    final cacheTime = _participationCacheTime[meetupId];
    if (cacheTime != null &&
        DateTime.now().difference(cacheTime) < _cacheValidDuration) {
      return _participationStatusCache[meetupId];
    }
    return null;
  }

  void _updateParticipationCache(String meetupId, bool isParticipating) {
    _participationStatusCache[meetupId] = isParticipating;
    _participationCacheTime[meetupId] = DateTime.now();
    _meetupCardRevision.value++;
  }

  Future<void> _loadParticipationStatus(String meetupId) async {
    if (!mounted) return;
    if (_participationSubscriptions.containsKey(meetupId)) return;

    // in-flight 플래그 설정 (카드 로딩 오버레이 표시)
    _participationSubscriptions[meetupId] = null;

    try {
      final participant = await _meetupService
          .getUserParticipationStatus(meetupId)
          .timeout(const Duration(milliseconds: 500), onTimeout: () => null);
      final isParticipating = participant?.status == ParticipantStatus.approved;
      if (mounted) {
        _updateParticipationCache(meetupId, isParticipating);
      }
    } catch (e) {
      Logger.error('❌ 참여 상태 로드 오류: $e');
      if (mounted) {
        _updateParticipationCache(meetupId, false);
      }
    } finally {
      if (mounted) {
        setState(() {
          _participationSubscriptions.remove(meetupId);
        });
      } else {
        _participationSubscriptions.remove(meetupId);
      }
    }
  }

  // ===== 네비게이션 =====
  Future<void> _navigateToMeetupDetail(Meetup meetup) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final kicked = await _meetupService.isUserKickedFromMeetup(
        meetupId: meetup.id,
        userId: user.uid,
      );
      if (!mounted) return;
      if (kicked) {
        AppSnackBar.show(
          context,
          message: kickedMeetupAccessMessage(context),
          type: AppSnackBarType.error,
        );
        return;
      }
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MeetupDetailScreen(
          meetup: meetup,
          meetupId: meetup.id,
          onMeetupDeleted: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    );

    // 상세 화면에서 상태가 바뀌었을 수 있으므로 캐시 정리
    if (!mounted) return;
    _participationSubscriptions.remove(meetup.id);
    _participationStatusCache.remove(meetup.id);
    _participationCacheTime.remove(meetup.id);

    try {
      final participant = await _meetupService
          .getUserParticipationStatus(meetup.id)
          .timeout(const Duration(milliseconds: 800), onTimeout: () => null);
      final isParticipating = participant?.status == ParticipantStatus.approved;
      _updateParticipationCache(meetup.id, isParticipating);
    } catch (e) {
      Logger.error('참여 상태 재조회 실패(상세 화면 복귀): $e');
    }

    if (mounted) setState(() {});
  }

  void _navigateToCreateMeetup() {
    final selected = _dayKey(_selectedDay);
    final dayIndex = (selected.weekday - 1).clamp(0, 6);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateMeetupScreen(
          initialDayIndex: dayIndex,
          initialDate: selected,
          onCreateMeetup: (dayIndex, meetup) {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  // ===== 후기 확인/수락 화면 =====
  Future<void> _viewAndRespondToReview(Meetup meetup) async {
    try {
      final meetupService = MeetupService();
      String? reviewId = meetup.reviewId;

      if (reviewId == null || meetup.hasReview == false) {
        final fresh = await meetupService.getMeetupById(meetup.id);
        if (fresh != null) {
          reviewId = fresh.reviewId;
        }
      }

      if (reviewId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(AppLocalizations.of(context)!.reviewNotFound)),
          );
        }
        return;
      }

      final reviewData = await meetupService.getMeetupReview(reviewId);
      if (reviewData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(AppLocalizations.of(context)!.reviewLoadFailed)),
          );
        }
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final reqQuery = await FirebaseFirestore.instance
          .collection('review_requests')
          .where('recipientId', isEqualTo: user.uid)
          .where('metadata.reviewId', isEqualTo: reviewId)
          .limit(1)
          .get();

      String requestId;
      if (reqQuery.docs.isEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final recipientName =
            (userDoc.data()?['nickname'] ?? '').toString().trim().isNotEmpty
                ? userDoc.data()!['nickname'].toString().trim()
                : 'User';
        final requesterId = meetup.userId ?? '';
        final requesterName =
            reviewData['authorName'] ?? meetup.hostNickname ?? meetup.host;

        final newReq =
            await FirebaseFirestore.instance.collection('review_requests').add({
          'meetupId': meetup.id,
          'requesterId': requesterId,
          'requesterName': requesterName,
          'recipientId': user.uid,
          'recipientName': recipientName,
          'meetupTitle': meetup.title,
          'message': reviewData['content'] ?? '',
          'imageUrls': [reviewData['imageUrl'] ?? ''],
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'respondedAt': null,
          'expiresAt':
              Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
          'metadata': {'reviewId': reviewId},
        });
        requestId = newReq.id;
      } else {
        requestId = reqQuery.docs.first.id;
      }

      if (!mounted) return;
      final List<String> imageUrls = [];
      if (reviewData['imageUrls'] != null && reviewData['imageUrls'] is List) {
        imageUrls.addAll(
          (reviewData['imageUrls'] as List).map((e) => e.toString()),
        );
      } else if (reviewData['imageUrl'] != null &&
          reviewData['imageUrl'].toString().isNotEmpty) {
        imageUrls.add(reviewData['imageUrl'].toString());
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReviewApprovalScreen(
            requestId: requestId,
            reviewId: reviewId!,
            meetupTitle: meetup.title,
            imageUrl: imageUrls.isNotEmpty ? imageUrls.first : '',
            imageUrls: imageUrls.isNotEmpty ? imageUrls : null,
            content: reviewData['content'] ?? '',
            authorName: reviewData['authorName'] ??
                AppLocalizations.of(context)!.anonymous,
          ),
        ),
      );
    } catch (e) {
      Logger.error('후기 확인 이동 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')),
        );
      }
    }
  }

  // ===== 참여/나가기 =====
  Future<void> _runWithMinimumButtonLoading(
      Future<void> Function() operation) async {
    final start = DateTime.now();
    try {
      await operation();
    } finally {
      final elapsed = DateTime.now().difference(start);
      const min = Duration(seconds: 1);
      if (elapsed < min) {
        await Future.delayed(min - elapsed);
      }
    }
  }

  Future<void> _joinMeetup(Meetup meetup) async {
    try {
      if (_joinLeaveInFlight.contains(meetup.id)) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final kicked = await _meetupService.isUserKickedFromMeetup(
          meetupId: meetup.id,
          userId: user.uid,
        );
        if (!mounted) return;
        if (kicked) {
          AppSnackBar.show(
            context,
            message: kickedMeetupAccessMessage(context),
            type: AppSnackBarType.error,
          );
          return;
        }
      }

      if (mounted) {
        setState(() {
          _joinLeaveInFlight.add(meetup.id);
        });
      }

      var success = false;
      await _runWithMinimumButtonLoading(() async {
        success = await _meetupService.joinMeetup(meetup.id);
      });

      if (!mounted) return;
      if (success) {
        setState(() {
          _updateParticipationCache(meetup.id, true);
          _joinLeaveInFlight.remove(meetup.id);
        });
        AppSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.meetupJoined,
          type: AppSnackBarType.success,
        );
      } else {
        setState(() {
          _updateParticipationCache(meetup.id, false);
          _joinLeaveInFlight.remove(meetup.id);
        });
        AppSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.meetupJoinFailed,
          type: AppSnackBarType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _updateParticipationCache(meetup.id, false);
          _joinLeaveInFlight.remove(meetup.id);
        });
      }
      Logger.error('모임 참여 오류: $e');
      if (mounted) {
        AppSnackBar.show(
          context,
          message: '${AppLocalizations.of(context)!.error}: $e',
          type: AppSnackBarType.error,
        );
      }
    }
  }

  Future<void> _leaveMeetup(Meetup meetup) async {
    try {
      if (_joinLeaveInFlight.contains(meetup.id)) return;
      if (mounted) {
        setState(() {
          _joinLeaveInFlight.add(meetup.id);
        });
      }

      var success = false;
      await _runWithMinimumButtonLoading(() async {
        success = await _meetupService.cancelMeetupParticipation(meetup.id);
      });

      if (!mounted) return;
      if (success) {
        setState(() {
          _updateParticipationCache(meetup.id, false);
          _joinLeaveInFlight.remove(meetup.id);
        });
        AppSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.leaveMeetup,
          type: AppSnackBarType.info,
        );
      } else {
        setState(() {
          _updateParticipationCache(meetup.id, true);
          _joinLeaveInFlight.remove(meetup.id);
        });
        AppSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.leaveMeetupFailed,
          type: AppSnackBarType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _updateParticipationCache(meetup.id, true);
          _joinLeaveInFlight.remove(meetup.id);
        });
      }
      Logger.error('모임 나가기 오류: $e');

      var errorMessage = (isChineseUi(context)
          ? '退出聚会失败'
          : Localizations.localeOf(context).languageCode == 'ko'
              ? '모임 나가기에 실패했습니다'
              : 'Failed to leave the meetup');
      if (e.toString().contains('permission-denied')) {
        errorMessage = (isChineseUi(context)
            ? '暂无权限，请重试。'
            : Localizations.localeOf(context).languageCode == 'ko'
                ? '권한이 없습니다. 다시 시도해주세요'
                : 'You don’t have permission. Please try again.');
      }

      if (mounted) {
        AppSnackBar.show(
          context,
          message: errorMessage,
          type: AppSnackBarType.error,
        );
      }
    }
  }

  // ===== 카드 빌더 =====
  Widget _buildMeetupCard(
    Meetup meetup, {
    bool? forceIsParticipating,
    bool disableParticipationLookup = false,
  }) {
    final currentUser = FirebaseAuth.instance.currentUser;

    final cachedStatus =
        forceIsParticipating ?? _getCachedParticipationStatus(meetup.id);
    final shouldLoad = !disableParticipationLookup &&
        cachedStatus == null &&
        currentUser != null &&
        meetup.userId != currentUser.uid;

    if (shouldLoad && !_participationSubscriptions.containsKey(meetup.id)) {
      _loadParticipationStatus(meetup.id);
    }

    final isLoadingStatus = shouldLoad &&
        _participationSubscriptions.containsKey(meetup.id) &&
        _participationSubscriptions[meetup.id] == null;

    return MeetupHomeCard(
      meetup: meetup,
      isParticipating: cachedStatus,
      isParticipationStatusLoading: isLoadingStatus,
      isJoinLeaveInFlight: _joinLeaveInFlight.contains(meetup.id),
      onTap: () => _navigateToMeetupDetail(meetup),
      onJoin: () => _joinMeetup(meetup),
      onLeave: () => _leaveMeetup(meetup),
      onViewReview: () => _viewAndRespondToReview(meetup),
    );
  }

  // ===== 상단 고정 카테고리 칩 =====
  Widget _buildCategoryChips() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 360;
    final isExpanded = screenWidth >= 600;
    // Keep the top filter bar compact on large phones. These values use
    // breakpoints instead of scaling continuously with the device size.
    final itemHeight = isCompact ? 30.0 : (isExpanded ? 34.0 : 32.0);
    final outerVerticalPadding = isCompact ? 5.0 : 6.0;
    final labelSize = isCompact ? 12.5 : (isExpanded ? 13.5 : 13.0);
    final categories = [
      {'key': 'all', 'label': AppLocalizations.of(context)!.all},
      {'key': 'meal', 'label': AppLocalizations.of(context)!.meal},
      {'key': 'cafe', 'label': AppLocalizations.of(context)!.cafe},
      {'key': 'hangout', 'label': AppLocalizations.of(context)!.hangout},
      {'key': 'trip', 'label': AppLocalizations.of(context)!.trip},
      {'key': 'study', 'label': AppLocalizations.of(context)!.study},
      {'key': 'culture', 'label': AppLocalizations.of(context)!.culture},
      {'key': 'etc', 'label': AppLocalizations.of(context)!.other},
    ];

    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 10 : (isExpanded ? 20 : 14),
              vertical: outerVerticalPadding,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                height: itemHeight,
                child: Row(
                  children: [
                    for (var i = 0; i < categories.length; i++) ...[
                      if (i != 0) SizedBox(width: isCompact ? 5 : 8),
                      _CategoryTabItem(
                        label: categories[i]['label']!,
                        selected: _selectedCategoryKey == categories[i]['key']!,
                        height: itemHeight,
                        fontSize: labelSize,
                        horizontalPadding: isCompact ? 8 : 10,
                        onTap: () {
                          setState(() {
                            _selectedCategoryKey = categories[i]['key']!;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===== 날짜 바: 월 이름(달력 펼침), 오늘, 이전/다음 =====
  Widget _buildDateBar() {
    final strings = _MeetupAgendaStrings.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 360;
    final isExpanded = screenWidth >= 600;
    final today = _dayKey(DateTime.now());
    final showTodayButton = !isSameDay(_selectedDay, today) ||
        (_isCalendarExpanded &&
            (_focusedMonth.year != today.year ||
                _focusedMonth.month != today.month));
    final monthSource = _isCalendarExpanded ? _focusedMonth : _selectedDay;
    final monthLabel = monthSource.year == today.year
        ? _expandedHeaderLabel(context, monthSource)
        : strings.yearMonth(monthSource, _expandedHeaderLabel(context, monthSource));
    final previousLabel =
        _isCalendarExpanded ? strings.previousMonth : strings.previousWeek;
    final nextLabel = _isCalendarExpanded ? strings.nextMonth : strings.nextWeek;

    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: EdgeInsets.only(
              left: isCompact ? 8 : (isExpanded ? 18 : 12),
              right: isCompact ? 2 : (isExpanded ? 10 : 4),
            ),
            child: SizedBox(
              height: isCompact ? 46 : 50,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.2,
                child: Row(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: const Key('meetup_date_selector'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() {
                          _isCalendarExpanded = !_isCalendarExpanded;
                          if (_isCalendarExpanded) {
                            _focusedMonth = DateTime(
                              _selectedDay.year,
                              _selectedDay.month,
                            );
                            _ensureMonthStreams(_focusedMonth);
                          }
                        }),
                        child: Semantics(
                          button: true,
                          expanded: _isCalendarExpanded,
                          label: _isCalendarExpanded
                              ? strings.collapseCalendar
                              : strings.expandCalendar,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 44),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    monthLabel,
                                    style: TextStyle(
                                      fontFamily: uiFontFamily(context, 'Inter'),
                                      fontFamilyFallback: const ['NotoSansKR'],
                                      fontSize: isCompact ? 17 : 18,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF111827),
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  AnimatedRotation(
                                    turns: _isCalendarExpanded ? .5 : 0,
                                    duration: MotionTokens.of(
                                      context,
                                      MotionTokens.state,
                                    ),
                                    child: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 22,
                                      color: Color(0xFF475467),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (showTodayButton)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: TextButton(
                          key: const Key('meetup_today_button'),
                          onPressed: () =>
                              _selectDay(today, collapseCalendar: true),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.pointColor,
                            minimumSize: const Size(44, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: const BorderSide(color: Color(0xFFD0D5DD)),
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            strings.today,
                            style: TextStyle(
                              fontFamily: uiFontFamily(context, 'Inter'),
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    IconButton(
                      key: const Key('meetup_previous_period'),
                      onPressed: () => _shiftPeriod(-1),
                      tooltip: previousLabel,
                      icon: const Icon(
                        Icons.chevron_left_rounded,
                        color: Color(0xFF344054),
                      ),
                    ),
                    IconButton(
                      key: const Key('meetup_next_period'),
                      onPressed: () => _shiftPeriod(1),
                      tooltip: nextLabel,
                      icon: const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF344054),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===== 주간 날짜 줄: 월 달력과 같은 표시를 한 주만 보여 준다 =====
  Widget _buildWeekStrip({
    required Map<DateTime, List<Meetup>> displayByDay,
    required Map<DateTime, List<Meetup>> myRelevantByDay,
  }) {
    final today = _dayKey(DateTime.now());
    final selected = _dayKey(_selectedDay);
    final weekStart = selected.subtract(Duration(days: selected.weekday % 7));
    final strings = _MeetupAgendaStrings.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 360;

    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            // 좌우로 밀어 이전/다음 주로 이동한다.
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity.abs() < 200) return;
              _shiftPeriod(velocity < 0 ? 1 : -1);
            },
            child: Padding(
              padding: EdgeInsets.fromLTRB(isCompact ? 4 : 8, 0, isCompact ? 4 : 8, 6),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.15,
                child: Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Builder(builder: (context) {
                          final day = weekStart.add(Duration(days: i));
                          final isToday = isSameDay(day, today);
                          final isSelected = isSameDay(day, selected);
                          final weekdayColor = day.weekday == DateTime.sunday
                              ? const Color(0xFFEF4444)
                              : day.weekday == DateTime.saturday
                                  ? const Color(0xFF3B82F6)
                                  : const Color(0xFF6B7280);
                          return Semantics(
                            button: true,
                            selected: isSelected,
                            label: _dayHeaderLabel(day),
                            excludeSemantics: true,
                            child: InkWell(
                              key: ValueKey<String>(
                                'meetup_week_day_${day.year}_${day.month}_${day.day}',
                              ),
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _selectDay(day),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      strings.weekdayShort(day),
                                      style: TextStyle(
                                        fontFamily:
                                            uiFontFamily(context, 'Inter'),
                                        fontFamilyFallback: const [
                                          'NotoSansKR'
                                        ],
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: weekdayColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    _CalendarDayCell(
                                      day: day,
                                      isSelected: isSelected,
                                      isToday: isToday,
                                      showCheck: !isToday &&
                                          shouldShowPastParticipationCheck(
                                            day: day,
                                            myRelevantByDay: myRelevantByDay,
                                            today: today,
                                          ),
                                      showMeetupBorder:
                                          shouldShowActiveMeetupRing(
                                        day: day,
                                        displayByDay: displayByDay,
                                        today: today,
                                      ),
                                      showFriendMeetupBorder:
                                          !_dayKey(day).isBefore(today) &&
                                              (displayByDay[_dayKey(day)]?.any(
                                                    _calendarCache
                                                        .isVisibleFriendMeetup,
                                                  ) ??
                                                  false),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// '오늘 · 10월 10일 (금)'처럼 상대 날짜와 실제 날짜를 함께 쓴다.
  String _dayHeaderLabel(DateTime day) {
    final strings = _MeetupAgendaStrings.of(context);
    final key = _dayKey(day);
    final today = _dayKey(DateTime.now());
    final diff = key.difference(today).inDays;
    final relative = switch (diff) {
      0 => strings.today,
      1 => strings.tomorrow,
      -1 => strings.yesterday,
      _ => null,
    };
    final date = strings.date(key);
    return relative == null ? date : '$relative · $date';
  }

  Widget _buildCalendar({
    required Map<DateTime, List<Meetup>> displayByDay,
    required Map<DateTime, List<Meetup>> myRelevantByDay,
    required double maxHeight,
  }) {
    final lang = Localizations.localeOf(context).languageCode;
    final today = _dayKey(DateTime.now());

    bool hasPastParticipatedMeetupOnDay(DateTime day) {
      return shouldShowPastParticipationCheck(
        day: day,
        myRelevantByDay: myRelevantByDay,
        today: today,
      );
    }

    bool hasVisibleFriendMeetupOnDay(DateTime day) {
      final key = _dayKey(day);
      if (key.isBefore(today)) return false;
      // 친구가 만든 모임 중 현재 사용자가 카드를 볼 수 있고, 공개 시간과
      // 실제 일정이 모두 만료되지 않은 모임이 하나라도 있을 때 표시한다.
      // 목록은 실시간 쿼리 결과이므로 마지막 모임 문서가 삭제된 순간 false가
      // 되어 10분 TTL 월 캐시의 오래된 테두리가 남지 않는다.
      return displayByDay[key]?.any(_calendarCache.isVisibleFriendMeetup) ??
          false;
    }

    bool hasVisibleMeetupOnDay(DateTime day) {
      return shouldShowActiveMeetupRing(
        day: day,
        displayByDay: displayByDay,
        today: today,
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: _isCalendarExpanded
          ? ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ColoredBox(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: TableCalendar<Meetup>(
                          firstDay: DateTime.utc(2020, 1, 1),
                          lastDay: DateTime.utc(2035, 12, 31),
                          focusedDay: _focusedMonth,
                          locale: lang == 'zh'
                              ? 'zh_CN'
                              : lang == 'ko'
                                  ? 'ko_KR'
                                  : 'en_US',
                          calendarFormat: CalendarFormat.month,
                          rowHeight:
                              MediaQuery.sizeOf(context).width < 360 ? 40 : 44,
                          daysOfWeekHeight: 30,
                          startingDayOfWeek: StartingDayOfWeek.sunday,
                          onPageChanged: (focusedDay) {
                            setState(() {
                              _focusedMonth = focusedDay;
                              _ensureMonthStreams(focusedDay);
                            });
                            unawaited(_calendarCache.warmMonth(focusedDay));
                          },
                          selectedDayPredicate: (day) =>
                              isSameDay(_selectedDay, day),
                          onDaySelected: (selectedDay, focusedDay) {
                            // 월 달력에서 날짜를 고르면 주간 보기로 접고
                            // 아래 목록이 그 날짜부터 보이게 한다.
                            _selectDay(selectedDay, collapseCalendar: true);
                          },
                          // 마커는 직접 그릴 것이므로 비활성
                          eventLoader: (_) => const <Meetup>[],
                          calendarBuilders: CalendarBuilders<Meetup>(
                            dowBuilder: (context, day) {
                              final isSat = day.weekday == DateTime.saturday;
                              final isSun = day.weekday == DateTime.sunday;
                              final color = isSun
                                  ? const Color(0xFFEF4444)
                                  : (isSat
                                      ? const Color(0xFF3B82F6)
                                      : const Color(0xFF6B7280));
                              final label = lang == 'ko'
                                  ? const [
                                      '일',
                                      '월',
                                      '화',
                                      '수',
                                      '목',
                                      '금',
                                      '토'
                                    ][day.weekday % 7]
                                  : DateFormat('EEE', 'en_US')
                                      .format(day)
                                      .substring(0, 1);
                              return Center(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontFamily: uiFontFamily(context, 'Inter'),
                                    fontFamilyFallback: const ['NotoSansKR'],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                  ),
                                ),
                              );
                            },
                            defaultBuilder: (context, day, focusedDay) {
                              return _CalendarDayCell(
                                day: day,
                                isSelected: isSameDay(day, _selectedDay),
                                isToday: isSameDay(day, DateTime.now()),
                                // ✅ 요구사항: 과거에 참여했던 모임이 있는 날만 빨간 체크
                                showCheck: hasPastParticipatedMeetupOnDay(day),
                                showMeetupBorder: hasVisibleMeetupOnDay(day),
                                showFriendMeetupBorder:
                                    hasVisibleFriendMeetupOnDay(day),
                              );
                            },
                            todayBuilder: (context, day, focusedDay) {
                              return _CalendarDayCell(
                                day: day,
                                isSelected: isSameDay(day, _selectedDay),
                                isToday: true,
                                // ✅ 요구사항: 오늘은 체크 표시하지 않음
                                showCheck: false,
                                showMeetupBorder: hasVisibleMeetupOnDay(day),
                                showFriendMeetupBorder:
                                    hasVisibleFriendMeetupOnDay(day),
                              );
                            },
                            selectedBuilder: (context, day, focusedDay) {
                              return _CalendarDayCell(
                                day: day,
                                isSelected: true,
                                isToday: isSameDay(day, DateTime.now()),
                                showCheck: hasPastParticipatedMeetupOnDay(day),
                                showMeetupBorder: hasVisibleMeetupOnDay(day),
                                showFriendMeetupBorder:
                                    hasVisibleFriendMeetupOnDay(day),
                              );
                            },
                            markerBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                          headerStyle: const HeaderStyle(
                            titleCentered: true,
                            formatButtonVisible: false,
                            leftChevronVisible: false,
                            rightChevronVisible: false,
                            headerPadding: EdgeInsets.zero,
                            titleTextStyle: TextStyle(fontSize: 0),
                          ),
                          calendarStyle: const CalendarStyle(
                            outsideDaysVisible: false,
                            todayDecoration: BoxDecoration(
                              color: Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            selectedDecoration: BoxDecoration(
                              color: Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  // ===== 목록: 선택한 날짜 + 다가오는 모든 밋업 =====
  Widget _buildAgenda({
    required Map<DateTime, List<Meetup>> displayByDay,
    required bool archiveLoading,
  }) {
    return StreamBuilder<List<Meetup>>(
      stream: _allUpcomingMeetupsStream,
      builder: (context, allSnap) {
        final strings = _MeetupAgendaStrings.of(context);
        final selectedKey = _dayKey(_selectedDay);
        final isSelectedPast = _isPastDay(selectedKey);
        // 과거 날짜는 읽을 수 있는 전체 아카이브(공개 시간 만료 포함),
        // 오늘·미래는 활성 모임을 쓴다. 카테고리는 양쪽에 같이 적용된다.
        final dayMeetups =
            (displayByDay[selectedKey] ?? const <Meetup>[]).toList();

        final upcomingLoading =
            allSnap.connectionState == ConnectionState.waiting &&
                !allSnap.hasData;
        final upcoming = _applyCategoryFilter(
          allSnap.data ?? const <Meetup>[],
        )
            .where((meetup) {
              final key = _dayKey(meetup.date);
              return !_isPastDay(key) && key != selectedKey;
            })
            .toList()
          ..sort((a, b) {
            final byDate = a.date.toLocal().compareTo(b.date.toLocal());
            if (byDate != 0) return byDate;
            return a.time.compareTo(b.time);
          });

        final items = <Widget>[
          _AgendaSectionHeader(
            key: const ValueKey<String>('agenda_selected_day_header'),
            icon: Icons.event_available_rounded,
            title: _dayHeaderLabel(selectedKey),
            count: archiveLoading ? null : dayMeetups.length,
          ),
          if (archiveLoading)
            for (var i = 0; i < 2; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _buildMeetupSkeleton(),
              )
          else if (dayMeetups.isEmpty)
            _AgendaMessage(
              text: isSelectedPast ? strings.pastDayEmpty : strings.dayEmpty,
            )
          else
            for (final meetup in dayMeetups)
              Padding(
                key: ValueKey<String>('agenda_day_${meetup.id}'),
                padding: const EdgeInsets.only(bottom: 4),
                child: _buildMeetupCard(
                  meetup,
                  forceIsParticipating: isSelectedPast ? false : null,
                  disableParticipationLookup: isSelectedPast,
                ),
              ),
          const SizedBox(height: 10),
          _AgendaSectionHeader(
            key: const ValueKey<String>('agenda_upcoming_header'),
            icon: Icons.format_list_bulleted_rounded,
            title: strings.upcomingTitle,
            count: upcomingLoading || allSnap.hasError ? null : upcoming.length,
          ),
        ];

        if (upcomingLoading) {
          for (var i = 0; i < 3; i++) {
            items.add(Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _buildMeetupSkeleton(),
            ));
          }
        } else if (allSnap.hasError) {
          items.add(_AgendaMessage(
            text: AppLocalizations.of(context)!.meetupLoadError,
          ));
        } else if (upcoming.isEmpty) {
          items.add(_AgendaMessage(text: strings.upcomingEmpty));
        } else {
          DateTime? lastDay;
          for (final meetup in upcoming) {
            final key = _dayKey(meetup.date);
            if (lastDay == null || key != lastDay) {
              lastDay = key;
              items.add(_AgendaDateLabel(
                key: ValueKey<String>(
                  'agenda_date_${key.year}_${key.month}_${key.day}',
                ),
                text: _dayHeaderLabel(key),
                onTap: () => _selectDay(key),
              ));
            }
            items.add(Padding(
              key: ValueKey<String>('agenda_upcoming_${meetup.id}'),
              padding: const EdgeInsets.only(bottom: 4),
              child: _buildMeetupCard(meetup),
            ));
          }
        }

        return ValueListenableBuilder<int>(
          valueListenable: _meetupCardRevision,
          builder: (context, _, __) => RefreshIndicator(
            color: AppColors.pointColor,
            backgroundColor: Colors.white,
            onRefresh: () async {
              setState(() {});
              await Future.delayed(const Duration(milliseconds: 350));
            },
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView.builder(
                  key: const PageStorageKey<String>('meetup_agenda_list'),
                  controller: _agendaController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    0,
                    4,
                    0,
                    88 + MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) => items[index],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: StreamBuilder<List<Meetup>>(
          key: ValueKey<String>(
            'meetup-archive-${_visibleRangeStart.year}-'
            '${_visibleRangeStart.month}-${_visibleRangeEnd.year}-'
            '${_visibleRangeEnd.month}',
          ),
          stream: _calendarArchiveStream,
          builder: (context, archiveSnap) {
            return StreamBuilder<List<Meetup>>(
              key: ValueKey<String>(
                'meetup-my-${_myStreamMonthKey.year}-'
                '${_myStreamMonthKey.month}',
              ),
              stream: _myRelevantMonthStream,
              builder: (context, mySnap) {
                if (archiveSnap.hasData) {
                  _cacheMeetupsByMonth(
                    _archiveMeetupMonthCache,
                    archiveSnap.data ?? const <Meetup>[],
                    <DateTime>[
                      _visibleRangeStart,
                      DateTime(
                        _visibleRangeStart.year,
                        _visibleRangeStart.month + 1,
                        1,
                      ),
                      _visibleRangeEnd,
                    ],
                  );
                }
                if (mySnap.hasData) {
                  _cacheMeetupsByMonth(
                    _myMeetupMonthCache,
                    mySnap.data ?? const <Meetup>[],
                    <DateTime>[_myStreamMonthKey],
                  );
                }
                final archiveMeetupsRaw =
                    archiveSnap.data ?? _cachedArchiveRangeMeetups();
                final myMeetupsRaw = mySnap.data ??
                    _myMeetupMonthCache[_myStreamMonthKey] ??
                    const <Meetup>[];

                final archiveMeetups = _applyCategoryFilter(archiveMeetupsRaw);
                final now = DateTime.now();
                final visibleMeetups = archiveMeetups
                    .where((meetup) => meetup.isPublishedAt(now))
                    .toList(growable: false);
                final myMeetups = _applyCategoryFilter(myMeetupsRaw);

                final visibleByDay = _groupByDay(visibleMeetups);
                final archiveByDay = _groupByDay(archiveMeetups);
                final myByDay = _groupByDay(myMeetups);
                final displayByDay = buildMeetupCalendarDisplayByDay(
                  visibleByDay: visibleByDay,
                  pastArchiveByDay: archiveByDay,
                );

                return LayoutBuilder(
                  builder: (context, constraints) {
                    // 작은 안드로이드 화면과 가로 모드에서도 달력이 목록 영역을
                    // 밀어내지 않도록 최소 목록 높이를 먼저 확보한다. 필요한 경우
                    // 달력만 세로 스크롤되며 날짜/목록의 기존 동작은 그대로 유지된다.
                    final calendarMaxHeight = (constraints.maxHeight - 196)
                        .clamp(0.0, 320.0)
                        .toDouble();
                    return Column(
                      children: [
                        // 상단 고정: 카테고리 칩
                        _buildCategoryChips(),
                        // 날짜 바 + 주간 날짜 줄(접힘) 또는 월 달력(펼침)
                        _buildDateBar(),
                        _buildCalendar(
                          displayByDay: displayByDay,
                          myRelevantByDay: myByDay,
                          maxHeight: calendarMaxHeight,
                        ),
                        if (!_isCalendarExpanded)
                          _buildWeekStrip(
                            displayByDay: displayByDay,
                            myRelevantByDay: myByDay,
                          ),
                        const Divider(
                          height: 1,
                          thickness: 1,
                          color: Color(0xFFEAECF0),
                        ),
                        // 선택한 날짜의 밋업과 다가오는 모든 밋업을 첫 화면부터
                        // 한 목록으로 보여 준다.
                        Expanded(
                          child: _buildAgenda(
                            displayByDay: displayByDay,
                            archiveLoading: archiveSnap.connectionState ==
                                    ConnectionState.waiting &&
                                !archiveSnap.hasData &&
                                !_archiveMeetupMonthCache
                                    .containsKey(_monthKey(_selectedDay)),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
      // 스낵챗 열기 버튼과 같은 크기·위치(오른쪽 16, 아래 16).
      floatingActionButton: AppFab.createMeetup(
        onPressed: _navigateToCreateMeetup,
        label: AppLocalizations.of(context)!.createMeetup,
        heroTag: 'meetup_home_create_fab',
      ),
    );
  }

  // 기존 스켈레톤 컴포넌트(로딩 시 사용)
  Widget _buildMeetupSkeleton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
      child: Row(
        children: [
          AppSkeleton(
            width: 66,
            height: 66,
            borderRadius: BorderRadius.circular(16),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AppSkeleton(
                        height: 16,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    AppSkeleton(
                      width: 19,
                      height: 19,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    AppSkeleton(
                      width: 15,
                      height: 15,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: AppSkeleton(
                        height: 12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    AppSkeleton(
                      width: 20,
                      height: 20,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AppSkeleton(
                        height: 12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    AppSkeleton(
                      width: 40,
                      height: 12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTabItem extends StatelessWidget {
  final String label;
  final bool selected;
  final double height;
  final double fontSize;
  final double horizontalPadding;
  final VoidCallback onTap;

  const _CategoryTabItem({
    required this.label,
    required this.selected,
    required this.height,
    required this.fontSize,
    required this.horizontalPadding,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const selectedText = Color(0xFF111827);
    const unselectedText = Color(0xFF667085);

    return MotionSelectable(
      selected: selected,
      pressedScale: MotionSelectable.segmentScale,
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          height: height,
          duration: MotionTokens.of(context, MotionTokens.state),
          curve: MotionTokens.curve,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: selected
                ? const Border(
                    bottom: BorderSide(color: Color(0xFF111827), width: 2),
                  )
                : null,
          ),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: AnimatedDefaultTextStyle(
              duration: MotionTokens.of(context, MotionTokens.state),
              curve: MotionTokens.curve,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: fontSize,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? selectedText : unselectedText,
                height: isChineseUi(context) ? 1.3 : 1.1,
              ),
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final bool showCheck;
  final bool showMeetupBorder;
  final bool showFriendMeetupBorder;

  const _CalendarDayCell({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.showCheck,
    required this.showMeetupBorder,
    required this.showFriendMeetupBorder,
  });

  Color _weekdayColor(DateTime d) {
    if (d.weekday == DateTime.saturday) return const Color(0xFF3B82F6);
    if (d.weekday == DateTime.sunday) return const Color(0xFFEF4444);
    return const Color(0xFF4B5563); // 부드러운 회색으로 변경
  }

  @override
  Widget build(BuildContext context) {
    // 요구사항:
    // - 오늘: 항상 파란색(선택 여부와 무관)
    // - 선택 날짜(오늘이 아닌 경우): 회색으로 표시
    final fill = isToday
        ? AppColors.pointColor
        : (isSelected ? const Color(0xFFE5E7EB) : Colors.transparent);
    final textColor = isToday
        ? Colors.white
        : (isSelected
            ? const Color(0xFF4B5563)
            : _weekdayColor(day)); // 선택된 날짜도 부드러운 회색
    final dateContent = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
      ),
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontFamily: uiFontFamily(context, 'Inter'),
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: 14,
          fontWeight:
              (isToday || isSelected) ? FontWeight.w700 : FontWeight.w600,
          color: textColor,
        ),
      ),
    );
    final markerStyle = showFriendMeetupBorder
        ? MeetupCalendarMarkerStyle.friendGradient
        : showMeetupBorder
            ? MeetupCalendarMarkerStyle.solidBlue
            : MeetupCalendarMarkerStyle.none;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final dayContent = MeetupCalendarDayRing(
      style: markerStyle,
      size: 38,
      strokeWidth: 2.5,
      semanticLabel: markerStyle == MeetupCalendarMarkerStyle.friendGradient
          ? ((isChineseUi(context)
              ? '好友创建聚会的日期'
              : isKo
                  ? '친구가 만든 모임이 있는 날짜'
                  : 'Date with a meetup created by a friend'))
          : markerStyle == MeetupCalendarMarkerStyle.solidBlue
              ? ((isChineseUi(context)
                  ? '有可见聚会的日期'
                  : isKo
                      ? '볼 수 있는 모임이 있는 날짜'
                      : 'Date with a visible meetup'))
              : null,
      child: dateContent,
    );

    return Center(
      child: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: dayContent,
            ),
            if (showCheck && !isToday)
              const Positioned(
                right: -1,
                top: -1,
                child: _MeetupCheckMark(
                  size: 16,
                  color: Color(0xFFEF4444),
                  strokeWidth: 2.6,
                ),
              ),
          ],
        ),
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

/// 목록 섹션 머리말: 아이콘, 제목, 개수.
class _AgendaSectionHeader extends StatelessWidget {
  const _AgendaSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.count,
  });

  final IconData icon;
  final String title;

  /// null이면 불러오는 중이라 개수를 숨긴다.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF111827),
      letterSpacing: -0.2,
      height: isChineseUi(context) ? 1.3 : 1.2,
    );
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF111827)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Text(
                '$count',
                style: style.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF6B7280),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// '다가오는 모든 밋업' 안의 날짜 구분. 누르면 그 날짜를 선택한다.
class _AgendaDateLabel extends StatelessWidget {
  const _AgendaDateLabel({
    super.key,
    required this.text,
    required this.onTap,
  });

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF475467),
            ),
          ),
        ),
      ),
    );
  }
}

/// 섹션 안의 짧은 빈 상태/오류 안내.
class _AgendaMessage extends StatelessWidget {
  const _AgendaMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF667085),
            height: 19 / 13,
          ),
        ),
      ),
    );
  }
}

/// 밋업 탭 날짜 바·목록 문구(한/영/중).
class _MeetupAgendaStrings {
  const _MeetupAgendaStrings._(this.code);

  final String code;

  static _MeetupAgendaStrings of(BuildContext context) =>
      _MeetupAgendaStrings._(Localizations.localeOf(context).languageCode);

  String _t(String ko, String en, String zh) =>
      code == 'zh' ? zh : (code == 'ko' ? ko : en);

  String get today => _t('오늘', 'Today', '今天');
  String get tomorrow => _t('내일', 'Tomorrow', '明天');
  String get yesterday => _t('어제', 'Yesterday', '昨天');
  String get upcomingTitle =>
      _t('다가오는 모든 밋업', 'All upcoming meetups', '所有即将举行的聚会');
  String get dayEmpty =>
      _t('이날 예정된 밋업이 없어요.', 'No meetups on this day.', '这一天没有聚会。');
  String get pastDayEmpty =>
      _t('이날 열린 밋업이 없어요.', 'No meetups were held this day.', '这一天没有举行聚会。');
  String get upcomingEmpty => _t(
        '아직 다가오는 밋업이 없어요. 첫 밋업을 열어 보세요.',
        'No upcoming meetups yet. Start the first one.',
        '还没有即将举行的聚会，来发起第一个吧。',
      );
  String get previousWeek => _t('이전 주', 'Previous week', '上一周');
  String get nextWeek => _t('다음 주', 'Next week', '下一周');
  String get previousMonth => _t('이전 달', 'Previous month', '上个月');
  String get nextMonth => _t('다음 달', 'Next month', '下个月');
  String get expandCalendar =>
      _t('월 달력 펼치기', 'Show month calendar', '展开月历');
  String get collapseCalendar =>
      _t('월 달력 접기', 'Hide month calendar', '收起月历');

  String yearMonth(DateTime month, String monthLabel) =>
      code == 'en' || (code != 'ko' && code != 'zh')
          ? '$monthLabel ${month.year}'
          : code == 'zh'
              ? '${month.year}年$monthLabel'
              : '${month.year}년 $monthLabel';

  static const List<String> _koWeekdays = ['일', '월', '화', '수', '목', '금', '토'];
  static const List<String> _zhWeekdays = ['日', '一', '二', '三', '四', '五', '六'];
  static const List<String> _enWeekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  static const List<String> _enWeekdaysLong = [
    'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat',
  ];
  static const List<String> _enMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String weekdayShort(DateTime day) {
    final index = day.weekday % 7;
    return code == 'ko'
        ? _koWeekdays[index]
        : code == 'zh'
            ? _zhWeekdays[index]
            : _enWeekdays[index];
  }

  /// 10월 10일 (금) / 10月10日 周五 / Fri, Oct 10
  String date(DateTime day) {
    final index = day.weekday % 7;
    if (code == 'ko') return '${day.month}월 ${day.day}일 (${_koWeekdays[index]})';
    if (code == 'zh') return '${day.month}月${day.day}日 周${_zhWeekdays[index]}';
    return '${_enWeekdaysLong[index]}, ${_enMonths[day.month - 1]} ${day.day}';
  }
}
