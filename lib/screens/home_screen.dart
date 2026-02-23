// lib/screens/home_screen.dart
// 모임 홈 화면 - 일주일 단위 모임 목록 표시
// 탭 기반 네비게이션, 카테고리 필터, 검색 기능

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/meetup.dart';
import '../constants/app_constants.dart';
import '../models/friend_category.dart';
import '../models/meetup_participant.dart';
import '../services/meetup_service.dart';
import '../services/friend_category_service.dart';
import '../ui/widgets/app_fab.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/skeletons.dart';
import '../services/preload_service.dart';
import 'create_meetup_screen.dart';
import 'meetup_detail_screen.dart';
import 'review_approval_screen.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../utils/ui_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/widgets/meetup_home_card.dart';
import '../ui/widgets/friends_only_badge.dart';

class MeetupHomePage extends StatefulWidget {
  final String? initialMeetupId; // 알림에서 전달받은 모임 ID
  
  const MeetupHomePage({super.key, this.initialMeetupId});

  @override
  State<MeetupHomePage> createState() => _MeetupHomePageState();
}

class _MeetupHomePageState extends State<MeetupHomePage>
    with SingleTickerProviderStateMixin, PreloadMixin {
  late TabController _tabController;
  final List<String> _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final MeetupService _meetupService = MeetupService();
  final FriendCategoryService _friendCategoryService = FriendCategoryService();
  int _meetupsRefreshTick = 0; // 슬라이드/탭 재선택 시 강제 리프레시용
  
  // 친구 카테고리 스트림 구독
  StreamSubscription<List<FriendCategory>>? _friendCategoriesSubscription;

  // 검색 기능
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;
  String _selectedCategory = 'all';

  // 필요한 상태 변수들
  late List<List<Meetup>> _localMeetupsByDay;
  List<FriendCategory> _friendCategories = [];
  String _friendFilter = 'all';
  bool _showFriendFilter = false;
  List<Meetup> _filteredMeetups = [];
  bool _isRefreshing = false; // 수동 새로고침 상태

  // 캐시 관련 변수
  final Map<int, List<Meetup>> _meetupCache = {};
  final Map<String, Map<int, List<Meetup>>> _categoryMeetupCache = {};

  // 참여 상태 캐시 (깜빡임 방지)
  final Map<String, bool> _participationStatusCache = {};
  final Map<String, DateTime> _participationCacheTime = {};
  static const Duration _cacheValidDuration = Duration(minutes: 5); // 5분으로 연장

  // 참여/나가기 연타 방지 + 최소 로딩 표시(1초)
  final Set<String> _joinLeaveInFlight = <String>{};

  // Stream 구독 관리
  final Map<String, StreamSubscription?> _participationSubscriptions = {};

  // 주차 네비게이션을 위한 기준 날짜
  DateTime _currentWeekAnchor = DateTime.now();

  @override
  void initState() {
    super.initState();
    // 메모리 기반 데이터 로드 (폴백용)
    _localMeetupsByDay = _meetupService.getMeetupsByDayFromMemory();
    _tabController = TabController(length: 7, vsync: this);

    // 검색 컨트롤러에 리스너 추가
    _searchController.addListener(_onSearchChanged);

    // 탭 변경 리스너 추가
    _tabController.addListener(_onTabChanged);

    // 초기화 시 현재 주와 오늘 요일로 설정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _goToCurrentWeek();
      _loadFriendCategories();
      
      // 알림에서 전달받은 모임이 있으면 다이얼로그 표시
      if (widget.initialMeetupId != null) {
        _showMeetupFromNotification(widget.initialMeetupId!);
      }
    });
  }

  @override
  void dispose() {
    Logger.log('🔄 MeetupHomePage dispose 시작');

    // 검색 관련 정리
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();

    // 탭 컨트롤러 정리
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();

    // 스트림 구독 정리
    _friendCategoriesSubscription?.cancel();
    _friendCategoriesSubscription = null;

    // 참여 상태 Stream 구독 모두 취소
    for (final subscription in _participationSubscriptions.values) {
      subscription?.cancel();
    }
    _participationSubscriptions.clear();

    // 서비스 정리
    _friendCategoryService.dispose();

    // 캐시 정리
    _meetupCache.clear();
    _categoryMeetupCache.clear();
    _participationStatusCache.clear();
    _participationCacheTime.clear();

    Logger.log('✅ MeetupHomePage dispose 완료');
    super.dispose();
  }

  // 알림에서 전달받은 모임 표시
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

        Logger.log('✅ 모임 로드 성공, 상세 페이지로 이동');
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
                      AppLocalizations.of(context)!.meetupCancelled ??
                          '모임이 취소되었습니다',
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

  // 친구 카테고리 로드
  void _loadFriendCategories() {
    _friendCategoriesSubscription?.cancel();
    _friendCategoriesSubscription =
        _friendCategoryService.getCategoriesStream().listen((categories) {
      if (mounted) {
        setState(() {
          _friendCategories = categories;
        });
      }
    });
  }

  /// 중요 콘텐츠 프리로딩 (상위 3개 모임)
  @override
  void preloadCriticalContent() {
    if (_filteredMeetups.isNotEmpty) {
      final criticalMeetups = _filteredMeetups.take(3).toList();
      PreloadService().preloadMeetups(
        criticalMeetups,
        priority: PreloadPriority.critical,
      );
    }
  }

  /// 추가 콘텐츠 프리로딩 (나머지 모임들)
  @override
  void preloadAdditionalContent() {
    if (_filteredMeetups.length > 3) {
      final additionalMeetups = _filteredMeetups.skip(3).toList();
      PreloadService().preloadMeetups(
        additionalMeetups,
        priority: PreloadPriority.high,
      );
    }
  }

  // 탭 변경 감지
  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      // StreamBuilder가 자동으로 새 데이터를 로드하므로 별도 처리 불필요
      // 참여 상태 캐시만 클리어하여 새 탭의 모임들에 대해 재로드
      setState(() {
        _participationStatusCache.clear();
        _participationCacheTime.clear();
        _participationSubscriptions.clear();
      });
    }
  }

  // 검색어 변경 감지
  void _onSearchChanged() {
    if (_searchController.text.isNotEmpty) {
      setState(() {
        _isSearching = true;
      });
    }
    _loadMeetups();
  }

  // 모임 목록 로딩 - Firebase에서 실시간 데이터 가져오기
  Future<void> _loadMeetups() async {
    try {
      List<Meetup> allMeetups = [];
      
      // 검색 모드일 때
      if (_isSearching && _searchController.text.isNotEmpty) {
        final searchQuery = _searchController.text.toLowerCase();
        allMeetups = await _meetupService.searchMeetupsAsync(searchQuery);
      } else {
        // 친구 그룹 필터링 적용
        if (_friendFilter.startsWith('category:')) {
          // 특정 카테고리 필터링
          final categoryId = _friendFilter.substring(9);
          allMeetups =
              await _meetupService.getFilteredMeetupsByFriendCategories(
            categoryIds: [categoryId],
          );
        } else if (_friendFilter == 'friends') {
          // 모든 친구의 모임
          allMeetups =
              await _meetupService.getFilteredMeetupsByFriendCategories(
            categoryIds: null,
          );
        } else if (_friendFilter == 'public') {
          // 전체 공개 모임만
          allMeetups =
              await _meetupService.getFilteredMeetupsByFriendCategories(
            categoryIds: [],
          );
        } else {
          // 모든 모임 (기본값) - 공개 범위 필터링 적용
          allMeetups =
              await _meetupService.getFilteredMeetupsByFriendCategories(
            categoryIds: null, // null = 모든 친구 관계 기반 필터링
          );
        }
        
        // 모든 경우에 날짜 필터링 적용 (검색 모드가 아닐 때)
        final selectedDate = _getWeekDates()[_tabController.index];
        final startOfDay =
            DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
        final endOfDay = startOfDay
            .add(const Duration(days: 1))
            .subtract(const Duration(microseconds: 1));
        
        allMeetups = allMeetups.where((meetup) {
          return meetup.date.isAfter(
                  startOfDay.subtract(const Duration(microseconds: 1))) &&
              meetup.date
                  .isBefore(endOfDay.add(const Duration(microseconds: 1)));
        }).toList();
      }

      // 카테고리 필터링 적용
      if (_selectedCategory == 'all') {
        _filteredMeetups = allMeetups;
      } else {
        // 카테고리 비교: 영어 키와 Firestore의 한글 값을 매핑
        final categoryMap = {
          'study': '스터디',
          'meal': '식사',
          'cafe': '카페',
          'drink': '술',
          'culture': '문화',
          'other': '기타',
        };
        final firestoreCategory =
            categoryMap[_selectedCategory] ?? _selectedCategory;
        _filteredMeetups = allMeetups
            .where((meetup) => meetup.category == firestoreCategory)
            .toList();
      }

      // 프리로딩 실행
      preloadCriticalContent();
      Future.delayed(const Duration(milliseconds: 500), () {
        preloadAdditionalContent();
      });
    } catch (e) {
      Logger.error('모임 로드 오류: $e');
      _filteredMeetups = [];
    } finally {
      // 로딩 완료
    }
  }

  // 주간 날짜 목록 생성
  List<DateTime> _getWeekDates() {
    final startOfWeek = _currentWeekAnchor
        .subtract(Duration(days: _currentWeekAnchor.weekday - 1));
    return List.generate(7, (index) => startOfWeek.add(Duration(days: index)));
  }

  // 이전 주로 이동
  void _goToPreviousWeek() {
    setState(() {
      _currentWeekAnchor = _currentWeekAnchor.subtract(const Duration(days: 7));
      _tabController.animateTo(0); // 월요일로 이동
    });
    _loadMeetups();
  }

  // 다음 주로 이동
  void _goToNextWeek() {
    setState(() {
      _currentWeekAnchor = _currentWeekAnchor.add(const Duration(days: 7));
      _tabController.animateTo(0); // 월요일로 이동
    });
    _loadMeetups();
  }

  // 현재 주로 이동
  void _goToCurrentWeek() {
    final now = DateTime.now();
    setState(() {
      _currentWeekAnchor = now;
      // 오늘 요일로 탭 이동 (월요일=0, 일요일=6)
      final todayIndex = now.weekday - 1;
      _tabController.animateTo(todayIndex);
    });
    _loadMeetups();
  }

  // 모임 생성 화면으로 이동
  void _showCreateMeetupDialog(BuildContext context) {
    final weekDates = _getWeekDates();
    final selectedDate = weekDates[_tabController.index];
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreateMeetupScreen(
          initialDayIndex: _tabController.index,
          initialDate: selectedDate, // 실제 선택된 날짜 전달
          onCreateMeetup: (index, meetup) {
            // 모임이 생성되면 캐시 클리어하고 목록 새로고침
            _meetupCache.clear();
            _categoryMeetupCache.clear();
            _loadMeetups();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<DateTime> weekDates = _getWeekDates();
    final selectedDate = weekDates[_tabController.index];
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // 밝은 회색 배경으로 카드 구분
      body: SafeArea(
        child: Column(
          children: [
            // 카테고리 필터
            _buildCategoryFilter(),

            // 날짜 네비게이션
            _buildDateNavigation(selectedDate),

            // 요일 캘린더
            _buildWeekCalendar(weekDates),

            // 모임 목록
            Expanded(
              // 요구사항: "모임이 올라온 부분"을 좌우 슬라이드하면 요일 이동
              child: TabBarView(
                controller: _tabController,
                children: List.generate(
                  7,
                  (dayIndex) => _buildMeetupListForDay(
                    selectedDate: weekDates[dayIndex],
                    dayIndex: dayIndex,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: AppFab(
        icon: Icons.add,
        onPressed: () => _navigateToCreateMeetup(),
        semanticLabel: '모임 생성',
      ),
    );
  }

  // 카테고리 필터
  Widget _buildCategoryFilter() {
    final categories = [
      {'key': 'all', 'label': AppLocalizations.of(context)!.all},
      {'key': 'study', 'label': AppLocalizations.of(context)!.study},
      {'key': 'meal', 'label': AppLocalizations.of(context)!.meal},
      {'key': 'cafe', 'label': AppLocalizations.of(context)!.cafe},
      {'key': 'drink', 'label': AppLocalizations.of(context)!.drink},
      {'key': 'culture', 'label': AppLocalizations.of(context)!.culture},
    ];

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: categories.map((category) {
            final isSelected = _selectedCategory == category['key'];

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedCategory = category['key']!;
                  });
                },
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.pointColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.pointColor
                          : const Color(0xFFE5E7EB),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      category['label']!,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? Colors.white : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // 날짜 네비게이션
  Widget _buildDateNavigation(DateTime selectedDate) {
    final locale = Localizations.localeOf(context).languageCode;
    final selectedDayString = locale == 'ko' 
        ? '${selectedDate.month}월 ${selectedDate.day}일'
        : DateFormat('MMM d', 'en').format(selectedDate);
    
    final weekdayName = locale == 'ko'
        ? ['월', '화', '수', '목', '금', '토', '일'][selectedDate.weekday - 1]
        : _weekdayNames[selectedDate.weekday - 1];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    iconSize: 20,
            color: const Color(0xFF374151),
                    padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: _goToPreviousWeek,
                  ),
          GestureDetector(
                      onTap: _goToCurrentWeek,
                      child: Text(
                        '$selectedDayString ($weekdayName)',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
          ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    iconSize: 20,
            color: const Color(0xFF374151),
                    padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: _goToNextWeek,
                  ),
                ],
      ),
    );
  }

  // 요일 캘린더
  Widget _buildWeekCalendar(List<DateTime> weekDates) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: weekDates.asMap().entries.map((entry) {
          final index = entry.key;
          final date = entry.value;
          final isSelected = index == _tabController.index;
          final isToday = _isToday(date);

          final weekdayLabel = _weekdayNames[index];

          return Expanded(
            child: GestureDetector(
              onTap: () {
                // 같은 요일을 다시 누르면 최신 내용 강제 업데이트
                if (index == _tabController.index) {
                  _refreshCurrentDay();
                  return;
                }
                _tabController.animateTo(index);
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  children: [
                    // 요일
                    SizedBox(
                      height: 14,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            weekdayLabel,
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              // 날짜 선택 여부와 무관하게 요일 이니셜 색상은 고정
                              // (선택 강조는 날짜 원형 배경으로만 표현)
                              color: index == 6 // 일요일
                                  ? const Color(0xFFEF4444)
                                  : index == 5 // 토요일
                                      ? const Color(0xFF3B82F6)
                                      : const Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // 날짜
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.pointColor
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF111827),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // 오늘 표시 점
                    if (isToday && !isSelected)
                      Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: AppColors.pointColor,
                          shape: BoxShape.circle,
                        ),
                      )
                    else
                      const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _refreshCurrentDay() async {
    if (!mounted) return;
    setState(() {
      _isRefreshing = true;
      _participationStatusCache.clear();
      _participationCacheTime.clear();
      _participationSubscriptions.clear();
      _meetupsRefreshTick++;
    });
    // 최소한의 시각적 피드백
    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() {
      _isRefreshing = false;
    });
  }

  // 모임 목록 (요일별)
  Widget _buildMeetupListForDay({
    required DateTime selectedDate,
    required int dayIndex,
  }) {
    return Column(
      children: [
        // 상단 로딩 인디케이터
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: _isRefreshing ? 3 : 0,
          child: _isRefreshing
              ? const LinearProgressIndicator(
                  backgroundColor: Color(0xFFE5E7EB),
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.pointColor),
                )
              : null,
        ),

        // 모임 목록
          Expanded(
          child: Container(
            padding: const EdgeInsets.only(top: 16),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: _isSearching
                  ? _buildSearchResults()
                      : RefreshIndicator(
                      color: AppColors.pointColor,
                      backgroundColor: Colors.white,
                        onRefresh: () async {
                        // 새로고침 시 캐시 클리어
                        if (mounted) {
                                setState(() {
                            _isRefreshing = true;
                            _participationStatusCache.clear();
                            _participationCacheTime.clear();
                            _participationSubscriptions.clear();
                            _meetupsRefreshTick++;
                          });
                        }

                        // 시각적 피드백
                        await Future.delayed(const Duration(milliseconds: 500));

                        if (mounted) {
                          setState(() {
                            _isRefreshing = false;
                          });
                        }
                      },
                      child: StreamBuilder<List<Meetup>>(
                        key: ValueKey(
                          'meetups_${dayIndex}_${_currentWeekAnchor.toIso8601String()}_$_meetupsRefreshTick',
                        ),
                        // Today(선택한 날짜가 "오늘")에서는
                        // - 약속 날짜가 오늘인 모임 + 오늘 생성된 모임을 함께 보여준다.
                        stream: _isToday(selectedDate)
                            ? _meetupService.getTodayTabMeetups()
                            : _meetupService.getMeetupsByDay(
                                dayIndex,
                                weekAnchor: _currentWeekAnchor,
                              ),
                        builder: (context, snapshot) {
                          // 초기 로딩만 스켈레톤 표시, 새로고침 시에는 이전 데이터 유지
                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              !snapshot.hasData) {
                            return ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(
                                left: 16,
                                right: 16,
                                top: 8,
                                bottom: 80, // FAB를 위한 하단 여백
                              ),
                              children: List.generate(
                                  3,
                                  (index) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 16),
                                        child: _buildMeetupSkeleton(),
                                      )),
                            );
                          }

                          if (snapshot.hasError) {
                            return ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.5,
                                  child: Center(
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0.0, end: 1.0),
                                      duration: const Duration(milliseconds: 400),
                                      curve: Curves.easeOut,
                                      builder: (context, value, child) {
                                        return Opacity(
                                          opacity: UIUtils.safeOpacity(value),
                                          child: Transform.translate(
                                            offset: Offset(0, 20 * (1 - value)),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Container(
                                                  width: 80,
                                                  height: 80,
                                                  decoration: BoxDecoration(
                                                    color: Colors.red[50],
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    Icons.error_outline,
                                                    size: 40,
                                                    color: Colors.red[400],
                                                  ),
                                                ),
                                                const SizedBox(height: 24),
                                                Text(
                                                  '모임을 불러오는 중 문제가 발생했어요',
                                                  style: TextStyle(
                                                    fontFamily: 'Pretendard',
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.grey[800],
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  '잠시 후 다시 시도해주세요',
                                                  style: TextStyle(
                                                    fontFamily: 'Pretendard',
                                                    fontSize: 14,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                                const SizedBox(height: 24),
                                                ElevatedButton.icon(
                                                  onPressed: () {
                                                    setState(() {}); // 새로고침
                                                  },
                                                  icon: const Icon(Icons.refresh, size: 18),
                                                  label: const Text(
                                                    '다시 시도',
                                                    style: TextStyle(
                                                      fontFamily: 'Pretendard',
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: AppColors.pointColor,
                                                    foregroundColor: Colors.white,
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 24,
                                                      vertical: 12,
                                                    ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          final meetups = snapshot.data ?? [];
                          final filteredMeetups =
                              _filterMeetupsByCategory(meetups);

                          if (filteredMeetups.isEmpty) {
                            return LayoutBuilder(
                              builder: (context, constraints) {
                                return ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  children: [
                                    SizedBox(
                                      height: constraints.maxHeight,
                                      child: AppEmptyState.noMeetups(
                                        context: context,
                                        onCreateMeetup: () => _navigateToCreateMeetup(),
                                        centerVertically: true,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          }

                          return ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(
                              left: 16,
                              right: 16,
                              bottom: 80, // FAB를 위한 하단 여백
                            ),
                            itemCount: filteredMeetups.length,
                            itemBuilder: (context, index) {
                              if (!mounted) return const SizedBox.shrink();
                              final meetup = filteredMeetups[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _buildNewMeetupCard(meetup),
                              );
                            },
                          );
          },
        ),
      ),
            ),
          ),
        ),
      ],
    );
  }

  // 새로운 모임 카드 디자인
  Widget _buildNewMeetupCard(Meetup meetup) {
    final currentUser = FirebaseAuth.instance.currentUser;
    
    // 참여 상태 확인
    final cachedStatus = _getCachedParticipationStatus(meetup.id);
    final shouldLoad = cachedStatus == null && 
        currentUser != null && 
        meetup.userId != currentUser.uid;
    
    // 캐시가 없으면 백그라운드에서 로드
    if (shouldLoad && !_participationSubscriptions.containsKey(meetup.id)) {
      _loadParticipationStatus(meetup.id);
    }
    
    // 로딩 표시는 참여 상태 조회(in-flight) 중일 때만
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

  // 공개 범위 배지
  Widget _buildVisibilityBadge(Meetup meetup) {
    if (meetup.visibility == 'category') {
      return FriendsOnlyBadge(
        label: AppLocalizations.of(context)!.friendsOnlyBadge,
        iconSize: 15,
      );
    }
    return const SizedBox.shrink();
  }

  // 참여 버튼
  Widget _buildJoinButton(Meetup meetup) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const SizedBox.shrink();
    }

    // 내가 만든 모임이면 버튼 표시 안함
    if (meetup.userId == currentUser.uid) {
      return const SizedBox.shrink();
    }

    // 캐시된 상태 확인 (즉시 반영)
    final cachedStatus = _getCachedParticipationStatus(meetup.id);

    // 로딩 중일 때는 버튼 숨김 (카드 전체 로딩 표시)
    if (cachedStatus == null) {
      return const SizedBox(width: 64, height: 32); // 버튼 공간 유지
    }

    final isParticipating = cachedStatus;
    final inFlight = _joinLeaveInFlight.contains(meetup.id);

    // 모임이 완료된 경우 처리
    if (meetup.isCompleted) {
      if (isParticipating) {
        // 참여 중인 사용자: 후기가 있으면 "후기 확인하기", 없으면 "마감"
        if (meetup.hasReview == true) {
          return GestureDetector(
            onTap: () => _viewAndRespondToReview(meetup),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.rate_review, size: 12, color: Colors.green[700]),
                  const SizedBox(width: 4),
                  Text(
                    AppLocalizations.of(context)!.checkReview,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          // 후기가 없으면 "마감" 상태 표시
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 12, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  AppLocalizations.of(context)!.closedStatus,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }
      } else {
        // 참여하지 않은 사용자에게는 "마감" 상태 표시
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 12, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                AppLocalizations.of(context)!.closedStatus,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        );
      }
    }

    // 마감된 모임이지만 이미 참여 중이면 나가기 버튼 표시
    if (meetup.currentParticipants >= meetup.maxParticipants &&
        !isParticipating) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: inFlight
          ? null
          : () async {
        if (isParticipating) {
          await _leaveMeetup(meetup);
        } else {
          await _joinMeetup(meetup);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isParticipating
              ? const Color(0xFFEF4444)
              : AppColors.pointColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: inFlight
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                isParticipating
                    ? AppLocalizations.of(context)!.leaveMeetup
                    : AppLocalizations.of(context)!.joinMeetup,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

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

  // 참여 상태를 백그라운드에서 로드
  Future<void> _loadParticipationStatus(String meetupId) async {
    if (!mounted) return;

    // 이미 로딩 중이면 무시
    if (_participationSubscriptions.containsKey(meetupId)) return;

    // in-flight 플래그 설정 (로딩 오버레이 표시)
    _participationSubscriptions[meetupId] = null;

    try {
      final participant = await _meetupService
          .getUserParticipationStatus(meetupId)
          .timeout(
            const Duration(milliseconds: 500),
            onTimeout: () {
              Logger.log('⏰ 참여 상태 확인 타임아웃: $meetupId (500ms)');
              return null;
            },
          );

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
      // IMPORTANT: 로딩 플래그는 반드시 해제해야 함.
      // 해제하지 않으면 캐시가 비었을 때(혹은 만료) 무한 로딩 오버레이가 고착될 수 있음.
      if (mounted) {
        setState(() {
          _participationSubscriptions.remove(meetupId);
        });
      } else {
        _participationSubscriptions.remove(meetupId);
      }
    }
  }

  // 캐시된 참여 상태 조회
  bool? _getCachedParticipationStatus(String meetupId) {
    final cacheTime = _participationCacheTime[meetupId];
    if (cacheTime != null &&
        DateTime.now().difference(cacheTime) < _cacheValidDuration) {
      return _participationStatusCache[meetupId];
    }
    return null;
  }

  // 참여 상태 캐시 업데이트
  void _updateParticipationCache(String meetupId, bool isParticipating) {
    _participationStatusCache[meetupId] = isParticipating;
    _participationCacheTime[meetupId] = DateTime.now();
  }

  /// 후기 확인 및 수락 화면으로 이동
  Future<void> _viewAndRespondToReview(Meetup meetup) async {
    try {
      final meetupService = MeetupService();
      String? reviewId = meetup.reviewId;

      // 최신 meetups 문서로 보강 (reviewId/hasReview 누락 대비)
      if (reviewId == null || meetup.hasReview == false) {
        final fresh = await meetupService.getMeetupById(meetup.id);
        if (fresh != null) {
          reviewId = fresh.reviewId;
        }
      }

      if (reviewId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.reviewNotFound ?? "")),
          );
        }
        return;
      }

      final reviewData = await meetupService.getMeetupReview(reviewId);
      if (reviewData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.reviewLoadFailed ?? "")),
          );
        }
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 수신자용 요청 조회
      final reqQuery = await FirebaseFirestore.instance
          .collection('review_requests')
          .where('recipientId', isEqualTo: user.uid)
          .where('metadata.reviewId', isEqualTo: reviewId)
          .limit(1)
          .get();

      String requestId;
      if (reqQuery.docs.isEmpty) {
        // 없으면 생성 (알림 누락 대비)
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final recipientName = (userDoc.data()?['nickname'] ?? '').toString().trim().isNotEmpty
            ? userDoc.data()!['nickname'].toString().trim()
            : 'User';
        final requesterId = meetup.userId ?? '';
        final requesterName = reviewData['authorName'] ?? meetup.hostNickname ?? meetup.host;

        final newReq = await FirebaseFirestore.instance.collection('review_requests').add({
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
      // 이미지 URL 목록 가져오기 (여러 이미지 지원)
      final List<String> imageUrls = [];
      if (reviewData['imageUrls'] != null && reviewData['imageUrls'] is List) {
        imageUrls.addAll((reviewData['imageUrls'] as List).map((e) => e.toString()));
      } else if (reviewData['imageUrl'] != null && reviewData['imageUrl'].toString().isNotEmpty) {
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
            authorName: reviewData['authorName'] ?? AppLocalizations.of(context)!.anonymous,
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

  // 모임 참여하기
  Future<void> _joinMeetup(Meetup meetup) async {
    try {
      if (_joinLeaveInFlight.contains(meetup.id)) return;
      
      // ✅ 강퇴된 사용자는 참여 불가 + 통일된 안내 문구
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

      bool success = false;
      await _runWithMinimumButtonLoading(() async {
        success = await _meetupService.joinMeetup(meetup.id);
      });

      if (success) {
        if (mounted) {
          setState(() {
            _updateParticipationCache(meetup.id, true);
            _joinLeaveInFlight.remove(meetup.id);
          });
          AppSnackBar.show(
            context,
            message: AppLocalizations.of(context)!.meetupJoined ??
                (Localizations.localeOf(context).languageCode == 'ko'
                    ? '모임에 참여했습니다'
                    : 'Joined the meetup'),
            type: AppSnackBarType.success,
          );
        }
      } else {
        // 실패 시 캐시 롤백
        if (mounted) {
          setState(() {
            _updateParticipationCache(meetup.id, false);
            _joinLeaveInFlight.remove(meetup.id);
          });
          AppSnackBar.show(
            context,
            message: AppLocalizations.of(context)!.meetupJoinFailed ??
                (Localizations.localeOf(context).languageCode == 'ko'
                    ? '모임 참여에 실패했습니다'
                    : 'Failed to join the meetup'),
            type: AppSnackBarType.error,
          );
        }
      }
    } catch (e) {
      // 오류 시 캐시 롤백
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

  // 모임 나가기
  Future<void> _leaveMeetup(Meetup meetup) async {
    try {
      if (_joinLeaveInFlight.contains(meetup.id)) return;
      if (mounted) {
        setState(() {
          _joinLeaveInFlight.add(meetup.id);
        });
      }

      bool success = false;
      await _runWithMinimumButtonLoading(() async {
        success = await _meetupService.cancelMeetupParticipation(meetup.id);
      });

      if (success) {
        if (mounted) {
          setState(() {
            _updateParticipationCache(meetup.id, false);
            _joinLeaveInFlight.remove(meetup.id);
          });
          AppSnackBar.show(
            context,
            message: AppLocalizations.of(context)!.leaveMeetup ??
                (Localizations.localeOf(context).languageCode == 'ko'
                    ? '모임에서 나갔습니다'
                    : 'Left the meetup'),
            type: AppSnackBarType.info,
          );
        }
      } else {
        // 실패 시 캐시 롤백
        if (mounted) {
          setState(() {
            _updateParticipationCache(meetup.id, true);
            _joinLeaveInFlight.remove(meetup.id);
          });
          AppSnackBar.show(
            context,
            message: AppLocalizations.of(context)!.leaveMeetupFailed ??
                (Localizations.localeOf(context).languageCode == 'ko'
                    ? '모임 나가기에 실패했습니다'
                    : 'Failed to leave the meetup'),
            type: AppSnackBarType.error,
          );
        }
      }
    } catch (e) {
      // 오류 시 캐시 롤백
      if (mounted) {
        setState(() {
          _updateParticipationCache(meetup.id, true);
          _joinLeaveInFlight.remove(meetup.id);
        });
      }
      Logger.error('모임 나가기 오류: $e');

      String errorMessage = Localizations.localeOf(context).languageCode == 'ko'
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

  // 검색 결과
  Widget _buildSearchResults() {
    // 기존 검색 로직 유지
    return const Center(
      child: Text('검색 기능 구현 중...'),
    );
  }

  // 카테고리별 필터링
  List<Meetup> _filterMeetupsByCategory(List<Meetup> meetups) {
    if (_selectedCategory == 'all') {
      return meetups;
    }
    return meetups
        .where((meetup) => meetup.category == _selectedCategory)
        .toList();
  }

  /// 모임 상세 화면으로 이동
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
            // 모임이 삭제되면 목록 새로고침
            setState(() {});
          },
        ),
      ),
    );

    // 상세 화면에서 참여/나가기 했을 수 있으므로, 돌아오는 시점에 참여 상태를 재조회하여
    // 홈 카드 버튼 상태가 새로고침 없이도 바로 반영되도록 캐시를 갱신한다.
    if (!mounted) return;

    // 로딩/캐시 플래그 정리(이전 값이 남아있으면 카드 버튼이 안 바뀜)
    _participationSubscriptions.remove(meetup.id);
    _participationStatusCache.remove(meetup.id);
    _participationCacheTime.remove(meetup.id);

    try {
      final participant = await _meetupService
          .getUserParticipationStatus(meetup.id)
          .timeout(
            const Duration(milliseconds: 800),
            onTimeout: () => null,
          );
      final isParticipating = participant?.status == ParticipantStatus.approved;
      _updateParticipationCache(meetup.id, isParticipating);
    } catch (e) {
      // 재조회 실패 시에도 UI는 업데이트 (다음 카드 렌더 때 백그라운드 로드로 보정)
      Logger.error('참여 상태 재조회 실패(상세 화면 복귀): $e');
    }

    if (mounted) setState(() {});
  }

  /// 모임 생성 화면으로 이동
  void _navigateToCreateMeetup() {
    final weekDates = _getWeekDates();
    final selectedDate = weekDates[_tabController.index];
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateMeetupScreen(
          initialDayIndex: _tabController.index, // 현재 선택된 요일 인덱스
          initialDate: selectedDate, // 실제 선택된 날짜 전달
          onCreateMeetup: (dayIndex, meetup) {
            // 모임 생성 후 목록 새로고침
            setState(() {});
          },
        ),
      ),
    );
  }

  /// 오늘인지 확인
  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// 모임 카드 스켈레톤 (로딩 시 표시)
  Widget _buildMeetupSkeleton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목 영역
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

          // 장소와 참여자 정보
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

          // 하단: 호스트 정보와 버튼
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

  /// URL인지 확인하는 함수
  bool _isUrl(String text) {
    final urlPattern = RegExp(
      r'^(https?:\/\/)?(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
      caseSensitive: false,
    );
    return urlPattern.hasMatch(text);
  }

  /// URL을 여는 함수
  Future<void> _openUrl(String urlString) async {
    try {
      // URL이 http:// 또는 https://로 시작하지 않으면 추가
      if (!urlString.startsWith('http://') && !urlString.startsWith('https://')) {
        urlString = 'https://$urlString';
      }

      final uri = Uri.parse(urlString);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${AppLocalizations.of(context)!.error}: URL을 열 수 없습니다'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)!.error}: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }
}
