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
import '../ui/widgets/meetup_home_card.dart';
import '../ui/widgets/skeletons.dart';
import '../utils/logger.dart';
import 'create_meetup_screen.dart';
import 'meetup_detail_screen.dart';
import 'review_approval_screen.dart';

class MeetupHomePage extends StatefulWidget {
  final String? initialMeetupId; // 알림에서 전달받은 모임 ID

  const MeetupHomePage({super.key, this.initialMeetupId});

  @override
  State<MeetupHomePage> createState() => _MeetupHomePageState();
}

class _MeetupHomePageState extends State<MeetupHomePage> with PreloadMixin {
  final MeetupService _meetupService = MeetupService();
  final MeetupCalendarCacheService _calendarCache = MeetupCalendarCacheService.instance;

  // UI 상태
  bool _isCalendarExpanded = false; // 요구사항: 기본 접힘
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  String _selectedCategoryKey = 'all';

  // ✅ 월 스트림 캐시(리빌드마다 재구독 방지 → 깜빡임 감소)
  late Stream<List<Meetup>> _visibleMonthStream;
  late Stream<List<Meetup>> _myRelevantMonthStream;
  DateTime _streamMonthKey = DateTime(1970, 1, 1);

  // 참여 상태 캐시 (깜빡임 방지)
  final Map<String, bool> _participationStatusCache = {};
  final Map<String, DateTime> _participationCacheTime = {};
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  // 참여/나가기 연타 방지 + 최소 로딩 표시(1초)
  final Set<String> _joinLeaveInFlight = <String>{};

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

    // 친구공개(친구 모임) 마커 캐시 구동
    _calendarCache.start();
    _calendarCache.addListener(_onCalendarCacheChanged);
    unawaited(_calendarCache.warmMonth(_focusedMonth));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 알림에서 전달받은 모임이 있으면 상세로 이동
      if (widget.initialMeetupId != null) {
        _showMeetupFromNotification(widget.initialMeetupId!);
      }
    });
  }

  @override
  void dispose() {
    _calendarCache.removeListener(_onCalendarCacheChanged);
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
    if (key == _streamMonthKey) return;
    _streamMonthKey = key;
    _visibleMonthStream = _meetupService.watchVisibleMeetupsForMonth(key);
    _myRelevantMonthStream = _meetupService.watchMyRelevantMeetupsForMonth(key);
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
      case 'drink':
      case '술':
        return 'drink';
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
    return meetups.where((m) => _normalizeCategoryKey(m.category) == wantedKey).toList();
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
        return _minutesFromMeetupTime(a.time).compareTo(_minutesFromMeetupTime(b.time));
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
      Logger.log('🔔 알림에서 모임 로드: $meetupId');
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
        Logger.log('❌ 모임을 찾을 수 없음: $meetupId');
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
            SnackBar(content: Text(AppLocalizations.of(context)!.reviewNotFound)),
          );
        }
        return;
      }

      final reviewData = await meetupService.getMeetupReview(reviewId);
      if (reviewData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.reviewLoadFailed)),
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
        final userDoc =
            await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final recipientName = (userDoc.data()?['nickname'] ?? '')
                .toString()
                .trim()
                .isNotEmpty
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
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
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
            authorName:
                reviewData['authorName'] ?? AppLocalizations.of(context)!.anonymous,
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
  Future<void> _runWithMinimumButtonLoading(Future<void> Function() operation) async {
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
    final categories = [
      {'key': 'all', 'label': AppLocalizations.of(context)!.all},
      {'key': 'study', 'label': AppLocalizations.of(context)!.study},
      {'key': 'meal', 'label': AppLocalizations.of(context)!.meal},
      {'key': 'cafe', 'label': AppLocalizations.of(context)!.cafe},
      {'key': 'drink', 'label': AppLocalizations.of(context)!.drink},
      {'key': 'culture', 'label': AppLocalizations.of(context)!.culture},
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicHeight(
          child: Row(
            children: [
              for (var i = 0; i < categories.length; i++) ...[
                if (i != 0)
                  const VerticalDivider(
                    width: 22,
                    thickness: 1.5,
                    color: Color(0xFFD1D5DB),
                    indent: 6,
                    endIndent: 6,
                  ),
                _CategoryTabItem(
                  label: categories[i]['label']!,
                  selected: _selectedCategoryKey == categories[i]['key']!,
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
    );
  }

  Widget _buildCalendarHeader() {
    final label = _isCalendarExpanded
        ? _expandedHeaderLabel(context, _focusedMonth)
        : _collapsedHeaderLabel(context, _selectedDay);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          setState(() {
            _isCalendarExpanded = !_isCalendarExpanded;
          });
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              const SizedBox(width: 28), // 좌우 균형(아이콘 자리)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
              ),
              Icon(
                _isCalendarExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 28,
                color: const Color(0xFF111827),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendar({
    required Map<DateTime, List<Meetup>> visibleByDay,
    required Map<DateTime, List<Meetup>> myByDay,
  }) {
    final lang = Localizations.localeOf(context).languageCode;
    final today = _dayKey(DateTime.now());

    bool hasPastParticipatedMeetupOnDay(DateTime day) {
      final key = _dayKey(day);
      if (!key.isBefore(today)) return false; // 과거만
      // ✅ 요구사항: "과거에 내가 참여했던 모임"(승인 참여 + 내가 호스트)만 체크 표시
      return (myByDay[key]?.isNotEmpty ?? false);
    }

    bool hasFriendsOnlyBadgeMeetupOnFutureDay(DateTime day) {
      final key = _dayKey(day);
      if (!key.isAfter(today)) return false; // 미래만 (오늘 제외)
      // ✅ 요구사항: 해당 날짜 모임 중 "Friends Only 배지"가 있는 모임만 주황 세모 표시
      // - 카드 배지 기준: visibility == 'category'
      final meetups = visibleByDay[key] ?? const <Meetup>[];
      return meetups.any((m) => m.visibility == 'category');
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: _isCalendarExpanded
          ? Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: TableCalendar<Meetup>(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2035, 12, 31),
                focusedDay: _focusedMonth,
                locale: lang == 'ko' ? 'ko_KR' : 'en_US',
                calendarFormat: CalendarFormat.month,
                startingDayOfWeek: StartingDayOfWeek.sunday,
                onPageChanged: (focusedDay) {
                  setState(() {
                    _focusedMonth = focusedDay;
                    _ensureMonthStreams(focusedDay);
                  });
                  unawaited(_calendarCache.warmMonth(focusedDay));
                },
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = _dayKey(selectedDay);
                    _focusedMonth = focusedDay;
                    _ensureMonthStreams(focusedDay);
                  });
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
                        : (isSat ? const Color(0xFF3B82F6) : const Color(0xFF6B7280));
                    final label = lang == 'ko'
                        ? const ['일', '월', '화', '수', '목', '금', '토'][day.weekday % 7]
                        : DateFormat('EEE', 'en_US').format(day).substring(0, 1);
                    return Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
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
                      // ✅ 요구사항: 미래 날짜 중 Friends Only 배지 모임이 있는 날만 주황 세모
                      showFriendOnlyTriangle:
                          hasFriendsOnlyBadgeMeetupOnFutureDay(day),
                    );
                  },
                  todayBuilder: (context, day, focusedDay) {
                    return _CalendarDayCell(
                      day: day,
                      isSelected: isSameDay(day, _selectedDay),
                      isToday: true,
                      // ✅ 요구사항: 오늘은 체크 표시하지 않음
                      showCheck: false,
                      // ✅ 요구사항: 오늘은 "미래"가 아니므로 주황 세모도 표시하지 않음
                      showFriendOnlyTriangle: false,
                    );
                  },
                  selectedBuilder: (context, day, focusedDay) {
                    return _CalendarDayCell(
                      day: day,
                      isSelected: true,
                      isToday: isSameDay(day, DateTime.now()),
                      showCheck: hasPastParticipatedMeetupOnDay(day),
                      showFriendOnlyTriangle:
                          hasFriendsOnlyBadgeMeetupOnFutureDay(day),
                    );
                  },
                  markerBuilder: (_, __, ___) => const SizedBox.shrink(),
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
            )
          : const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedKey = _dayKey(_selectedDay);
    final isPastSelected = _isPastDay(selectedKey);

    return Scaffold(
      backgroundColor: const Color(0xFFEBEBEB),
      body: SafeArea(
        top: false,
        child: StreamBuilder<List<Meetup>>(
          stream: _visibleMonthStream,
          builder: (context, visibleSnap) {
            return StreamBuilder<List<Meetup>>(
              stream: _myRelevantMonthStream,
              builder: (context, mySnap) {
                final visibleMeetupsRaw = visibleSnap.data ?? const <Meetup>[];
                final myMeetupsRaw = mySnap.data ?? const <Meetup>[];

                final visibleMeetups = _applyCategoryFilter(visibleMeetupsRaw);
                final myMeetups = _applyCategoryFilter(myMeetupsRaw);

                final visibleByDay = _groupByDay(visibleMeetups);
                final myByDay = _groupByDay(myMeetups);

                final selectedMeetups = (isPastSelected
                        ? (myByDay[selectedKey] ?? const <Meetup>[])
                        : (visibleByDay[selectedKey] ?? const <Meetup>[]))
                    .toList();

                final showSkeleton = isPastSelected
                    ? (mySnap.connectionState == ConnectionState.waiting &&
                        !mySnap.hasData)
                    : (visibleSnap.connectionState == ConnectionState.waiting &&
                        !visibleSnap.hasData);

                return Column(
                  children: [
                    // 상단 고정: 카테고리 칩
                    _buildCategoryChips(),
                    // 상단 고정: 달력 헤더 + (펼침 시) 달력
                    _buildCalendarHeader(),
                    _buildCalendar(visibleByDay: visibleByDay, myByDay: myByDay),
                    const SizedBox(height: 8),
                    // 리스트(스크롤)
                    Expanded(
                      child: showSkeleton
                          ? ListView(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                              children: List.generate(
                                3,
                                (i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildMeetupSkeleton(),
                                ),
                              ),
                            )
                          : (selectedMeetups.isEmpty
                              ? ListView(
                                  children: [
                                    SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height * 0.55,
                                      child: AppEmptyState.noMeetups(
                                        context: context,
                                        onCreateMeetup: _navigateToCreateMeetup,
                                        centerVertically: true,
                                      ),
                                    ),
                                  ],
                                )
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
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding:
                                        const EdgeInsets.fromLTRB(12, 8, 12, 90),
                                    itemCount: selectedMeetups.length,
                                    itemBuilder: (context, index) {
                                      final meetup = selectedMeetups[index];
                                      // ✅ 과거 리스트는 이미 "내 관련 모임"이므로
                                      // 참여 상태 조회/오버레이 로딩을 돌리지 않아도 된다(깜빡임 방지).
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: _buildMeetupCard(
                                          meetup,
                                          forceIsParticipating:
                                              isPastSelected ? true : null,
                                          disableParticipationLookup:
                                              isPastSelected,
                                        ),
                                      );
                                    },
                                  ),
                                )),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: AppFab(
        icon: Icons.add,
        onPressed: _navigateToCreateMeetup,
        semanticLabel: '모임 생성',
      ),
    );
  }

  // 기존 스켈레톤 컴포넌트(로딩 시 사용)
  Widget _buildMeetupSkeleton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: AppSkeleton(
                    height: 20,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                AppSkeleton(
                  width: 60,
                  height: 24,
                  borderRadius: BorderRadius.circular(12),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    AppSkeleton(
                      width: 16,
                      height: 16,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: AppSkeleton(
                        height: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    AppSkeleton(
                      width: 16,
                      height: 16,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    const SizedBox(width: 4),
                    AppSkeleton(
                      width: 60,
                      height: 14,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                AppSkeleton(
                  width: 32,
                  height: 32,
                  borderRadius: BorderRadius.circular(16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppSkeleton(
                    height: 14,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                AppSkeleton(
                  width: 70,
                  height: 32,
                  borderRadius: BorderRadius.circular(16),
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
  final VoidCallback onTap;

  const _CategoryTabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 스크린샷 기준: 연한 하늘색 배경 + 흰 글자(선택), 나머지 검정 굵은 글자
    const selectedBg = Color(0xFF6CCFF6);
    const selectedText = Colors.white;
    const unselectedText = Color(0xFF111827);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? selectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: selected ? selectedText : unselectedText,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
  final bool showFriendOnlyTriangle;

  const _CalendarDayCell({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.showCheck,
    required this.showFriendOnlyTriangle,
  });

  Color _weekdayColor(DateTime d) {
    if (d.weekday == DateTime.saturday) return const Color(0xFF3B82F6);
    if (d.weekday == DateTime.sunday) return const Color(0xFFEF4444);
    return const Color(0xFF111827);
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
        : (isSelected ? const Color(0xFF111827) : _weekdayColor(day));

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
                  color: fill,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight:
                        (isToday || isSelected) ? FontWeight.w900 : FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
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
            if (showFriendOnlyTriangle)
              const Positioned(
                bottom: -7,
                left: 0,
                right: 0,
                child: Center(
                  child: _OrangeTriangleMarker(size: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrangeTriangleMarker extends StatelessWidget {
  final double size;

  const _OrangeTriangleMarker({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _OrangeTrianglePainter(),
      ),
    );
  }
}

class _OrangeTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const color = Color(0xFFF97316); // orange
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(0, h)
      ..lineTo(w, h)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

