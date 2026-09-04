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
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/meetup_calendar_day_ring.dart';
import '../ui/widgets/meetup_home_card.dart';
import '../ui/widgets/skeletons.dart';
import '../utils/meetup_calendar_marker_policy.dart';
import '../utils/logger.dart';
import 'create_meetup_screen.dart';
import 'meetup_detail_screen.dart';
import 'review_approval_screen.dart';

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

  // PageView 컨트롤러 (날짜 슬라이드용)
  late PageController _pageController;
  static const int _initialPageIndex = 10000; // 충분히 큰 초기 인덱스 (과거/미래로 이동 가능)
  late DateTime _baseDate; // PageView 계산을 위한 기준 날짜 (고정)

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
    _baseDate = _selectedDay; // 기준 날짜 고정 (PageView 계산용)

    // PageController 초기화
    _pageController = PageController(initialPage: _initialPageIndex);

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
      if (mounted && _isCalendarExpanded) setState(() {});
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
    _pageController.dispose();
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

  /// 포스트의 `오늘의 밋업`에서 진입할 때 기존 탭 상태와 무관하게 오늘을 연다.
  void showToday() {
    if (!mounted) return;

    final today = _dayKey(DateTime.now());
    final targetPage =
        _initialPageIndex + today.difference(_dayKey(_baseDate)).inDays;

    setState(() {
      _selectedDay = today;
      _focusedMonth = DateTime(today.year, today.month);
      _ensureMonthStreams(_focusedMonth);
    });

    void moveToToday() {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(targetPage);
    }

    if (_pageController.hasClients) {
      moveToToday();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => moveToToday());
    }

    unawaited(_calendarCache.warmMonth(_focusedMonth));
    unawaited(_calendarCache.warmDay(today));
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

  String _collapsedHeaderLabel(BuildContext context, DateTime selected) {
    final code = Localizations.localeOf(context).languageCode;
    final locale = code == 'ko' ? 'ko_KR' : 'en_US';
    final local = selected.toLocal();
    if (code == 'ko') {
      return DateFormat('MM. dd EEEE', locale).format(local);
    }
    return DateFormat('MMM d, EEEE', locale).format(local);
  }

  String _expandedHeaderLabel(BuildContext context, DateTime focusedMonth) {
    final code = Localizations.localeOf(context).languageCode;
    final local = focusedMonth.toLocal();
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
              message: '죄송합니다. 모임에 참여할 수 없습니다',
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
          message: '죄송합니다. 모임에 참여할 수 없습니다',
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

  Future<void> _navigateToAllMeetups() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AllMeetupsScreen(
          meetupsStream: _allUpcomingMeetupsStream,
          categoryKeyOf: (meetup) => _normalizeCategoryKey(meetup.category),
          meetupCardBuilder: _buildMeetupCard,
          meetupSkeletonBuilder: _buildMeetupSkeleton,
          meetupCardRevision: _meetupCardRevision,
          onCreateMeetup: _navigateToCreateMeetup,
        ),
      ),
    );

    if (mounted) setState(() {});
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
            message: '죄송합니다. 모임에 참여할 수 없습니다',
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

      var errorMessage = Localizations.localeOf(context).languageCode == 'ko'
          ? '모임 나가기에 실패했습니다'
          : 'Failed to leave the meetup';
      if (e.toString().contains('permission-denied')) {
        errorMessage = Localizations.localeOf(context).languageCode == 'ko'
            ? '권한이 없습니다. 다시 시도해주세요'
            : 'You don’t have permission. Please try again.';
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

  Widget _buildCalendarHeader() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 360;
    final isExpanded = screenWidth >= 600;
    final useShortAllLabel =
        screenWidth < 370 || MediaQuery.textScalerOf(context).scale(14) > 17;
    final headerHeight = isCompact ? 48.0 : (isExpanded ? 54.0 : 52.0);
    final labelSize = isCompact ? 14.0 : (isExpanded ? 16.0 : 15.0);
    final iconSize = isCompact ? 20.0 : 22.0;
    final label = _isCalendarExpanded
        ? _expandedHeaderLabel(context, _focusedMonth)
        : _collapsedHeaderLabel(context, _selectedDay);
    final l10n = AppLocalizations.of(context)!;

    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(
            height: headerHeight,
            child: Padding(
              padding: EdgeInsets.only(
                left: isCompact ? 12 : (isExpanded ? 22 : 16),
                right: isCompact ? 4 : (isExpanded ? 12 : 8),
              ),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.2,
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            key: const Key('meetup_date_selector'),
                            onTap: () {
                              setState(() {
                                _isCalendarExpanded = !_isCalendarExpanded;
                              });
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today_outlined,
                                    size: isCompact ? 17 : 18,
                                    color: const Color(0xFF475467),
                                  ),
                                  SizedBox(width: isCompact ? 7 : 8),
                                  Flexible(
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontFamilyFallback: const [
                                          'NotoSansKR'
                                        ],
                                        fontSize: labelSize,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF111827),
                                        height: 1.15,
                                        letterSpacing: -0.15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    _isCalendarExpanded
                                        ? Icons.arrow_drop_up_rounded
                                        : Icons.arrow_drop_down_rounded,
                                    size: iconSize,
                                    color: const Color(0xFF475467),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      key: const Key('all_meetups_button'),
                      onPressed: _navigateToAllMeetups,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF475467),
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 6 : 8,
                        ),
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                      icon: Icon(
                        Icons.format_list_bulleted_rounded,
                        size: isCompact ? 18 : 19,
                      ),
                      label: Text(
                        useShortAllLabel ? l10n.all : l10n.allMeetups,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: isCompact ? 12.5 : 13,
                          fontWeight: FontWeight.w700,
                        ),
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
                          locale: lang == 'ko' ? 'ko_KR' : 'en_US',
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
                            final newDateKey = _dayKey(selectedDay);
                            setState(() {
                              _selectedDay = newDateKey;
                              _focusedMonth = focusedDay;
                              _ensureMonthStreams(focusedDay);
                            });

                            // PageView도 선택된 날짜로 이동
                            final daysDiff =
                                newDateKey.difference(_baseDate).inDays;
                            final targetPage = _initialPageIndex + daysDiff;
                            _pageController.jumpToPage(targetPage);

                            unawaited(_calendarCache.warmDay(selectedDay));
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
                                    fontFamily: 'Inter',
                                    fontFamilyFallback: const ['NotoSansKR'],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
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

  // 날짜 변경 (PageView 인덱스 기반)
  DateTime _getDateFromPageIndex(int pageIndex) {
    final offset = pageIndex - _initialPageIndex;
    return _baseDate.add(Duration(days: offset));
  }

  void _onPageChanged(int pageIndex) {
    final newDate = _getDateFromPageIndex(pageIndex);
    final newDateKey = _dayKey(newDate);

    // 선택 날짜가 실제로 바뀐 경우에만 setState
    if (newDateKey != _dayKey(_selectedDay)) {
      setState(() {
        _selectedDay = newDateKey;
        // 월이 바뀌면 focusedMonth도 업데이트
        if (_selectedDay.year != _focusedMonth.year ||
            _selectedDay.month != _focusedMonth.month) {
          _focusedMonth = DateTime(_selectedDay.year, _selectedDay.month);
          _ensureMonthStreams(_focusedMonth);
          unawaited(_calendarCache.warmMonth(_focusedMonth));
        }
      });
    }
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
                        // 상단 고정: 달력 헤더 + (펼침 시) 달력
                        _buildCalendarHeader(),
                        _buildCalendar(
                          displayByDay: displayByDay,
                          myRelevantByDay: myByDay,
                          maxHeight: calendarMaxHeight,
                        ),
                        const SizedBox(height: 4),
                        // PageView로 날짜별 리스트 슬라이드
                        Expanded(
                          child: PageView.builder(
                            controller: _pageController,
                            onPageChanged: _onPageChanged,
                            itemBuilder: (context, pageIndex) {
                              // 현재 페이지의 날짜 계산
                              final pageDate = _getDateFromPageIndex(pageIndex);
                              final pageDateKey = _dayKey(pageDate);
                              final isPagePast = _isPastDay(pageDateKey);

                              // 과거는 해당 날짜의 읽을 수 있는 전체 아카이브
                              // (공개 시간 만료 포함), 오늘·미래는 활성 모임을
                              // 사용한다. 선택 카테고리는 양쪽에 동일하게 적용된다.
                              final pageMeetups = (displayByDay[pageDateKey] ??
                                      const <Meetup>[])
                                  .toList();

                              // 스켈레톤 표시 여부
                              final pageMonthKey = _monthKey(pageDateKey);
                              final pageShowSkeleton =
                                  archiveSnap.connectionState ==
                                          ConnectionState.waiting &&
                                      !archiveSnap.hasData &&
                                      !_archiveMeetupMonthCache
                                          .containsKey(pageMonthKey);

                              return pageShowSkeleton
                                  ? ListView(
                                      padding: EdgeInsets.fromLTRB(
                                        0,
                                        4,
                                        0,
                                        88 +
                                            MediaQuery.paddingOf(context)
                                                .bottom,
                                      ),
                                      children: List.generate(
                                        3,
                                        (i) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 4),
                                          child: _buildMeetupSkeleton(),
                                        ),
                                      ),
                                    )
                                  : (pageMeetups.isEmpty
                                      ? const _MeetupEmptyContent()
                                      : RefreshIndicator(
                                          color: AppColors.pointColor,
                                          backgroundColor: Colors.white,
                                          onRefresh: () async {
                                            setState(() {});
                                            await Future.delayed(
                                              const Duration(milliseconds: 350),
                                            );
                                          },
                                          child: ListView.builder(
                                            physics:
                                                const AlwaysScrollableScrollPhysics(),
                                            padding: EdgeInsets.fromLTRB(
                                              0,
                                              4,
                                              0,
                                              88 +
                                                  MediaQuery.paddingOf(context)
                                                      .bottom,
                                            ),
                                            itemCount: pageMeetups.length,
                                            itemBuilder: (context, index) {
                                              final meetup = pageMeetups[index];
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 4),
                                                child: _buildMeetupCard(
                                                  meetup,
                                                  forceIsParticipating:
                                                      isPagePast ? false : null,
                                                  disableParticipationLookup:
                                                      isPagePast,
                                                ),
                                              );
                                            },
                                          ),
                                        ));
                            },
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
      floatingActionButton: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: AppFab.createMeetup(
          onPressed: _navigateToCreateMeetup,
          heroTag: 'meetup_home_create_fab',
        ),
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

class _AllMeetupsScreen extends StatefulWidget {
  final Stream<List<Meetup>> meetupsStream;
  final String Function(Meetup meetup) categoryKeyOf;
  final Widget Function(Meetup meetup) meetupCardBuilder;
  final Widget Function() meetupSkeletonBuilder;
  final ValueNotifier<int> meetupCardRevision;
  final VoidCallback onCreateMeetup;

  const _AllMeetupsScreen({
    required this.meetupsStream,
    required this.categoryKeyOf,
    required this.meetupCardBuilder,
    required this.meetupSkeletonBuilder,
    required this.meetupCardRevision,
    required this.onCreateMeetup,
  });

  @override
  State<_AllMeetupsScreen> createState() => _AllMeetupsScreenState();
}

class _AllMeetupsScreenState extends State<_AllMeetupsScreen> {
  String _selectedCategoryKey = 'all';

  List<Map<String, String>> _categories(BuildContext context) => [
        {'key': 'all', 'label': AppLocalizations.of(context)!.all},
        {'key': 'meal', 'label': AppLocalizations.of(context)!.meal},
        {'key': 'cafe', 'label': AppLocalizations.of(context)!.cafe},
        {'key': 'hangout', 'label': AppLocalizations.of(context)!.hangout},
        {'key': 'trip', 'label': AppLocalizations.of(context)!.trip},
        {'key': 'study', 'label': AppLocalizations.of(context)!.study},
        {'key': 'culture', 'label': AppLocalizations.of(context)!.culture},
        {'key': 'etc', 'label': AppLocalizations.of(context)!.other},
      ];

  List<Meetup> _filteredAndSorted(List<Meetup> source) {
    final filtered = _selectedCategoryKey == 'all'
        ? source.toList()
        : source
            .where((meetup) =>
                widget.categoryKeyOf(meetup) == _selectedCategoryKey)
            .toList();
    filtered.sort((a, b) {
      final byDate = a.date.toLocal().compareTo(b.date.toLocal());
      if (byDate != 0) return byDate;
      return a.time.compareTo(b.time);
    });
    return filtered;
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: width < 360 ? 52 : 56,
      leadingWidth: 48,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(
          Icons.arrow_back_rounded,
          color: Color(0xFF111827),
          size: 22,
        ),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      ),
      centerTitle: true,
      title: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: Text(
          AppLocalizations.of(context)!.allMeetups,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: width < 360 ? 17 : 18,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 360;
    final isExpanded = width >= 600;
    final categories = _categories(context);

    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 10 : (isExpanded ? 20 : 14),
              isCompact ? 5 : 7,
              isCompact ? 10 : (isExpanded ? 20 : 14),
              isCompact ? 7 : 9,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                height: isCompact ? 30 : 32,
                child: Row(
                  children: [
                    for (var index = 0; index < categories.length; index++) ...[
                      if (index != 0) SizedBox(width: isCompact ? 5 : 8),
                      _CategoryTabItem(
                        label: categories[index]['label']!,
                        selected:
                            _selectedCategoryKey == categories[index]['key']!,
                        height: isCompact ? 30 : 32,
                        fontSize: isCompact ? 12.5 : 13,
                        horizontalPadding: isCompact ? 8 : 10,
                        onTap: () {
                          setState(() {
                            _selectedCategoryKey = categories[index]['key']!;
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

  Widget _buildLoadingList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: widget.meetupSkeletonBuilder(),
      ),
    );
  }

  Widget _buildMeetupList(BuildContext context, List<Meetup> meetups) {
    if (meetups.isEmpty) return const _MeetupEmptyContent();

    return ValueListenableBuilder<int>(
      valueListenable: widget.meetupCardRevision,
      builder: (context, _, __) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView.builder(
              key: const PageStorageKey<String>('all_meetups_list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 88),
              itemCount: meetups.length,
              itemBuilder: (context, index) {
                final meetup = meetups[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: widget.meetupCardBuilder(meetup),
                );
              },
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
      appBar: _buildAppBar(context),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildCategoryFilter(context),
            Expanded(
              child: StreamBuilder<List<Meetup>>(
                stream: widget.meetupsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return _buildLoadingList(context);
                  }
                  if (snapshot.hasError) {
                    return AppErrorState(
                      description:
                          AppLocalizations.of(context)!.meetupLoadError,
                    );
                  }
                  return _buildMeetupList(
                    context,
                    _filteredAndSorted(snapshot.data ?? const <Meetup>[]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: AppFab.createMeetup(
          onPressed: widget.onCreateMeetup,
          heroTag: 'all_meetups_create_fab',
        ),
      ),
    );
  }
}

class _MeetupEmptyContent extends StatelessWidget {
  const _MeetupEmptyContent();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 360 || size.height < 650;
    final horizontal = size.width < 360 ? 20.0 : 28.0;
    final padding = EdgeInsets.fromLTRB(
      horizontal,
      compact ? 18 : 28,
      horizontal,
      88,
    );
    final l10n = AppLocalizations.of(context)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? (constraints.maxHeight - padding.vertical)
                .clamp(0.0, double.infinity)
                .toDouble()
            : 0.0;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.2,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/wefilling_logo.png',
                        width: compact ? 58 : 66,
                        height: compact ? 58 : 66,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(height: compact ? 18 : 24),
                      Text(
                        l10n.wefillingMeaning,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: compact ? 18 : 20,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                          height: 1.3,
                          letterSpacing: -0.25,
                        ),
                      ),
                      SizedBox(height: compact ? 10 : 12),
                      Text(
                        l10n.wefillingExplanation,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: compact ? 13.5 : 14.5,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF667085),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          height: height,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
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
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: fontSize,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? selectedText : unselectedText,
                height: 1.1,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
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
          fontFamily: 'Inter',
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
          ? (isKo
              ? '친구가 만든 모임이 있는 날짜'
              : 'Date with a meetup created by a friend')
          : markerStyle == MeetupCalendarMarkerStyle.solidBlue
              ? (isKo ? '볼 수 있는 모임이 있는 날짜' : 'Date with a visible meetup')
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
