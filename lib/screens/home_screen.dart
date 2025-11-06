// lib/screens/home_screen.dart
// 모임 홈 화면 - 일주일 단위 모임 목록 표시
// 탭 기반 네비게이션, 카테고리 필터, 검색 기능

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/meetup.dart';
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
import '../l10n/app_localizations.dart';

class MeetupHomePage extends StatefulWidget {
  final String? initialMeetupId; // 알림에서 전달받은 모임 ID

  const MeetupHomePage({super.key, this.initialMeetupId});

  @override
  State<MeetupHomePage> createState() => _MeetupHomePageState();
}

class _MeetupHomePageState extends State<MeetupHomePage>
    with SingleTickerProviderStateMixin, PreloadMixin {
  late TabController _tabController;
  final List<String> _weekdayNames = ['M', 'Tu', 'W', 'Th', 'F', 'Sa', 'Su'];
  final MeetupService _meetupService = MeetupService();
  final FriendCategoryService _friendCategoryService = FriendCategoryService();

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
  bool _isLoading = false;
  bool _isTabChanging = false;
  bool _isRefreshing = false; // 수동 새로고침 상태
  int _refreshKey = 0; // Stream 재구독을 위한 키

  // 캐시 관련 변수
  final Map<int, List<Meetup>> _meetupCache = {};
  final Map<String, Map<int, List<Meetup>>> _categoryMeetupCache = {};

  // 참여 상태 캐시 (깜빡임 방지)
  final Map<String, bool> _participationStatusCache = {};
  final Map<String, DateTime> _participationCacheTime = {};
  static const Duration _cacheValidDuration = Duration(seconds: 30);

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
    print('🔄 MeetupHomePage dispose 시작');

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

    print('✅ MeetupHomePage dispose 완료');
    super.dispose();
  }

  // 알림에서 전달받은 모임 표시
  Future<void> _showMeetupFromNotification(String meetupId) async {
    try {
      print('🔔 알림에서 모임 로드: $meetupId');
      final meetup = await _meetupService.getMeetupById(meetupId);

      if (meetup != null && mounted) {
        print('✅ 모임 로드 성공, 다이얼로그 표시');
        showDialog(
          context: context,
          builder: (dialogContext) => MeetupDetailScreen(
            meetup: meetup,
            meetupId: meetupId,
            onMeetupDeleted: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        AppLocalizations.of(context)!.meetupCancelled ??
                            '모임이 취소되었습니다')),
              );
            },
          ),
        );
      } else {
        print('❌ 모임을 찾을 수 없음: $meetupId');
      }
    } catch (e) {
      print('❌ 알림 모임 로드 오류: $e');
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
    if (_tabController.indexIsChanging ||
        _tabController.index != _tabController.previousIndex) {
      // 탭이 변경됐을 때 해당 요일의 모임만 불러오기
      if (!_isTabChanging) {
        _isTabChanging = true;
        _loadMeetups().then((_) {
          _isTabChanging = false;
        });
      }
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
    setState(() {
      _isLoading = true;
    });

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
          'hobby': '카페',
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
      print('모임 로드 오류: $e');
      _filteredMeetups = [];
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreateMeetupScreen(
          initialDayIndex: _tabController.index,
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
      backgroundColor: Colors.white,
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
              child: _buildMeetupList(selectedDate),
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
      {'key': 'all', 'label': '전체'},
      {'key': 'study', 'label': '스터디'},
      {'key': 'meal', 'label': '식사'},
      {'key': 'cafe', 'label': '카페'},
      {'key': 'culture', 'label': '문화'},
    ];

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: categories.map((category) {
          final isSelected = _selectedCategory == category['key'];

          return Flexible(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCategory = category['key']!;
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color:
                      isSelected ? const Color(0xFF5865F2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF5865F2)
                        : const Color(0xFFE5E7EB),
                    width: 1,
                  ),
                ),
                child: Text(
                  category['label']!,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : const Color(0xFF6B7280),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }).toList(),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            iconSize: 24,
            color: const Color(0xFF374151),
            onPressed: _goToPreviousWeek,
          ),
          GestureDetector(
            onTap: _goToCurrentWeek,
            child: Text(
              '$selectedDayString ($weekdayName)',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            iconSize: 24,
            color: const Color(0xFF374151),
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

          final locale = Localizations.localeOf(context).languageCode;
          final weekdayLabel = locale == 'ko'
              ? ['M', 'Tu', 'W', 'Th', 'F', 'Sa', 'Su'][index]
              : _weekdayNames[index];

          return Expanded(
            child: GestureDetector(
              onTap: () {
                _tabController.animateTo(index);
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  children: [
                    // 요일
                    Text(
                      weekdayLabel,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isSelected
                            ? const Color(0xFF5865F2)
                            : index == 6 // 일요일
                                ? const Color(0xFFEF4444)
                                : index == 5 // 토요일
                                    ? const Color(0xFF3B82F6)
                                    : const Color(0xFF6B7280),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // 날짜
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF5865F2)
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
                          color: Color(0xFF5865F2),
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

  // 모임 목록
  Widget _buildMeetupList(DateTime selectedDate) {
    return Column(
      children: [
        // 상단 로딩 인디케이터
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: _isRefreshing ? 3 : 0,
          child: _isRefreshing
              ? const LinearProgressIndicator(
                  backgroundColor: Color(0xFFE5E7EB),
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF5865F2)),
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
                      color: const Color(0xFF5865F2),
                      backgroundColor: Colors.white,
                      onRefresh: () async {
                        // Stream 재구독을 통한 최신 데이터 로드
                        if (mounted) {
                          setState(() {
                            _isRefreshing = true;
                            _refreshKey++; // 키 변경으로 StreamBuilder 재생성
                            _participationStatusCache.clear(); // 참여 상태 캐시 클리어
                            _participationCacheTime.clear();
                          });
                        }

                        // 최소 시각적 피드백 시간
                        await Future.delayed(const Duration(milliseconds: 800));

                        if (mounted) {
                          setState(() {
                            _isRefreshing = false;
                          });
                        }
                      },
                      child: StreamBuilder<List<Meetup>>(
                        key: ValueKey('meetup_stream_$_refreshKey'), // 키로 재생성
                        stream: _meetupService
                            .getMeetupsByDay(_tabController.index),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
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
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.error_outline,
                                          size: 48,
                                          color: Colors.red[300],
                                        ),
                                        const SizedBox(height: 16),
                                        Text('오류가 발생했습니다: ${snapshot.error}'),
                                        const SizedBox(height: 8),
                                        TextButton(
                                          onPressed: () {
                                            setState(() {}); // 새로고침
                                          },
                                          child: const Text(
                                            '다시 시도',
                                            style: TextStyle(
                                              fontFamily: 'Pretendard',
                                              fontSize: 14,
                                              color: Color(0xFF5865F2),
                                            ),
                                          ),
                                        ),
                                      ],
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
                            return ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.5,
                                  child: AppEmptyState.noMeetups(
                                    context: context,
                                    onCreateMeetup: () =>
                                        _navigateToCreateMeetup(),
                                  ),
                                ),
                              ],
                            );
                          }

                          return ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
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
    return GestureDetector(
      onTap: () => _navigateToMeetupDetail(meetup),
      child: Container(
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
            // 상단: 제목과 공개 범위 배지
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      meetup.title,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildVisibilityBadge(meetup),
                ],
              ),
            ),

            // 중간: 장소와 참여자 수
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: Color(0xFF6B7280),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          meetup.location,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            color: Color(0xFF6B7280),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.people_outline,
                        size: 16,
                        color: Color(0xFF6B7280),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${meetup.currentParticipants}/${meetup.maxParticipants}명',
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 하단: 호스트 정보와 참여 버튼
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFF9FAFB),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  // 호스트 프로필
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFE5E7EB),
                    backgroundImage: meetup.hostPhotoURL.isNotEmpty
                        ? NetworkImage(meetup.hostPhotoURL)
                        : null,
                    child: meetup.hostPhotoURL.isEmpty
                        ? const Icon(
                            Icons.person,
                            size: 16,
                            color: Color(0xFF6B7280),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      meetup.hostNickname ?? '익명',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF374151),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // 참여 버튼
                  _buildJoinButton(meetup),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 공개 범위 배지
  Widget _buildVisibilityBadge(Meetup meetup) {
    if (meetup.visibility == 'category') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '친구공개',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Color(0xFFD97706),
          ),
        ),
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

    // 캐시가 없으면 백그라운드에서 로드
    if (cachedStatus == null &&
        !_participationSubscriptions.containsKey(meetup.id)) {
      _loadParticipationStatus(meetup.id);
    }

    final isParticipating = cachedStatus ?? false;

    // 마감된 모임이지만 이미 참여 중이면 나가기 버튼 표시
    if (meetup.currentParticipants >= meetup.maxParticipants &&
        !isParticipating) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () async {
        if (isParticipating) {
          await _leaveMeetup(meetup);
        } else {
          await _joinMeetup(meetup);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isParticipating
              ? const Color(0xFFEF4444)
              : const Color(0xFF5865F2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          isParticipating ? '나가기' : '참여하기',
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

  // 참여 상태를 백그라운드에서 로드
  void _loadParticipationStatus(String meetupId) {
    if (!mounted) return;

    // 이미 구독이 있으면 무시
    if (_participationSubscriptions.containsKey(meetupId)) return;

    _participationSubscriptions[meetupId] = null; // 플래그 설정

    _meetupService.getUserParticipationStatus(meetupId).then((participant) {
      if (mounted) {
        final isParticipating =
            participant?.status == ParticipantStatus.approved;
        _updateParticipationCache(meetupId, isParticipating);
        // 상태가 변경되었으면 UI 업데이트
        setState(() {});
      }
    }).catchError((e) {
      print('참여 상태 로드 오류: $e');
    });
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

  // 모임 참여하기
  Future<void> _joinMeetup(Meetup meetup) async {
    // 즉시 캐시 업데이트 (깜빡임 방지)
    if (mounted) {
      setState(() {
        _updateParticipationCache(meetup.id, true);
      });
    }

    try {
      final success = await _meetupService.joinMeetup(meetup.id);

      if (success) {
        if (mounted) {
          setState(() {
            _updateParticipationCache(meetup.id, true);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.meetupJoined ?? '모임에 참여했습니다'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // 실패 시 캐시 롤백
        if (mounted) {
          setState(() {
            _updateParticipationCache(meetup.id, false);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.meetupJoinFailed ??
                  '모임 참여에 실패했습니다'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      // 오류 시 캐시 롤백
      if (mounted) {
        setState(() {
          _updateParticipationCache(meetup.id, false);
        });
      }
      print('모임 참여 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)!.error ?? '오류'}: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // 모임 나가기
  Future<void> _leaveMeetup(Meetup meetup) async {
    // 즉시 캐시 업데이트 (깜빡임 방지)
    if (mounted) {
      setState(() {
        _updateParticipationCache(meetup.id, false);
      });
    }

    try {
      final success = await _meetupService.cancelMeetupParticipation(meetup.id);

      if (success) {
        if (mounted) {
          setState(() {
            _updateParticipationCache(meetup.id, false);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.leaveMeetup ?? '모임에서 나갔습니다'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // 실패 시 캐시 롤백
        if (mounted) {
          setState(() {
            _updateParticipationCache(meetup.id, true);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.leaveMeetupFailed ??
                  '모임 나가기에 실패했습니다'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      // 오류 시 캐시 롤백
      if (mounted) {
        setState(() {
          _updateParticipationCache(meetup.id, true);
        });
      }
      print('모임 나가기 오류: $e');

      String errorMessage = '모임 나가기에 실패했습니다';
      if (e.toString().contains('permission-denied')) {
        errorMessage = '권한이 없습니다. 다시 시도해주세요';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
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
  void _navigateToMeetupDetail(Meetup meetup) {
    Navigator.push(
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
  }

  /// 모임 생성 화면으로 이동
  void _navigateToCreateMeetup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateMeetupScreen(
          initialDayIndex: 0,
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
}
