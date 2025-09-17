// lib/screens/home_screen.dart
// 모임 홈 화면 - 일주일 단위 모임 목록 표시
// 탭 기반 네비게이션, 카테고리 필터, 검색 기능

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_constants.dart';
import '../models/meetup.dart';
import '../services/meetup_service.dart';
import '../ui/widgets/compact_header.dart';
import '../ui/widgets/app_icon_button.dart';
import '../ui/widgets/app_fab.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/skeletons.dart';
import '../ui/widgets/optimized_list.dart';
import '../ui/widgets/optimized_meetup_card.dart';
import '../utils/image_utils.dart';
import '../services/preload_service.dart';
import '../design/tokens.dart';
import 'create_meetup_screen.dart';
import 'meetup_detail_screen.dart';

class MeetupHomePage extends StatefulWidget {
  const MeetupHomePage({super.key});

  @override
  State<MeetupHomePage> createState() => _MeetupHomePageState();
}

class _MeetupHomePageState extends State<MeetupHomePage>
    with SingleTickerProviderStateMixin, PreloadMixin {
  late TabController _tabController;
  final List<String> _weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];
  // 기존 메모리 기반 데이터 - 필요시 폴백으로 사용
  late List<List<Meetup>> _localMeetupsByDay;
  final MeetupService _meetupService = MeetupService();

  // 검색 기능
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  // 카테고리 필터링
  final List<String> _categories = ['전체', '스터디', '식사', '취미', '문화'];
  String _selectedCategory = '전체';

  // 현재 표시할 모임 목록
  List<Meetup> _filteredMeetups = [];
  bool _isLoading = false;
  bool _isTabChanging = false;

  // 캐시 관련 변수
  final Map<int, List<Meetup>> _meetupCache = {};

  final Map<String, Map<int, List<Meetup>>> _categoryMeetupCache = {};

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
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
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
      final selectedDate = _getWeekDates()[_tabController.index];
      
      // 검색 모드일 때
      if (_isSearching && _searchController.text.isNotEmpty) {
        final searchQuery = _searchController.text.toLowerCase();
        final allMeetups = await _meetupService.searchMeetupsAsync(searchQuery);

        _filteredMeetups = allMeetups.where((meetup) {
          final matchesCategory = _selectedCategory == '전체' || meetup.category == _selectedCategory;
          return matchesCategory;
        }).toList();
      } else {
        // 일반 모드일 때 - Firebase에서 해당 날짜의 모임 가져오기
        final startOfDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
        final endOfDay = startOfDay.add(const Duration(days: 1)).subtract(const Duration(microseconds: 1));
        
        final snapshot = await _meetupService.firestore
            .collection('meetups')
            .where('date', isGreaterThanOrEqualTo: startOfDay)
            .where('date', isLessThanOrEqualTo: endOfDay)
            .orderBy('date')
            .get();

        final dayMeetups = snapshot.docs.map((doc) {
          final data = doc.data();
          return Meetup(
            id: doc.id,
            title: data['title'] ?? '',
            description: data['description'] ?? '',
            location: data['location'] ?? '',
            time: data['time'] ?? '',
            maxParticipants: data['maxParticipants'] ?? 0,
            currentParticipants: data['currentParticipants'] ?? 1,
            host: data['hostNickname'] ?? '익명',
            hostNationality: data['hostNationality'] ?? '',
            imageUrl: data['thumbnailImageUrl'] ?? AppConstants.DEFAULT_IMAGE_URL,
            thumbnailContent: data['thumbnailContent'] ?? '',
            thumbnailImageUrl: data['thumbnailImageUrl'] ?? '',
            date: (data['date'] as Timestamp).toDate(),
            category: data['category'] ?? '기타',
          );
        }).toList();

        if (_selectedCategory == '전체') {
          _filteredMeetups = dayMeetups;
        } else {
          _filteredMeetups = dayMeetups.where((meetup) => meetup.category == _selectedCategory).toList();
        }
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
    final startOfWeek = _currentWeekAnchor.subtract(Duration(days: _currentWeekAnchor.weekday - 1));
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

  // 모임 생성 다이얼로그 표시
  void _showCreateMeetupDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.2), // 개선된 오버레이 색상
      builder: (context) => CreateMeetupScreen(
        initialDayIndex: _tabController.index,
        onCreateMeetup: (index, meetup) {
          // 모임이 생성되면 캐시 클리어하고 목록 새로고침
          _meetupCache.clear();
          _categoryMeetupCache.clear();
          _loadMeetups();
        },
      ),
    );
  }

  // FAB 빌드
  Widget _buildFab() {
    return AppFab.createMeetup(
      onPressed: () => _showCreateMeetupDialog(context),
      heroTag: 'meetup_fab',
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<DateTime> weekDates = _getWeekDates();
    final selectedDayString =
        '${weekDates[_tabController.index].month}월 ${weekDates[_tabController.index].day}일';

    return Scaffold(
      body: Column(
        children: [
          // 컴팩트 헤더 (콘텐츠 노출 극대화)
          _buildCompactHeader(),

          // 컴팩트 탭바 (검색 모드가 아닐 때만 표시)
          if (!_isSearching) _buildCompactTabBar(weekDates),

          // 현재 선택된 날짜와 요일 표시 + 주차 네비게이션 (검색 모드가 아닐 때만)
          if (!_isSearching)
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: 12.0, // 위아래 간격을 약간 늘림
                horizontal: 16.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 이전 주 버튼
                  AppIconButton(
                    icon: Icons.chevron_left,
                    onPressed: _goToPreviousWeek,
                    semanticLabel: '이전 주',
                  ),
                  
                  // 현재 날짜 정보 (탭하면 오늘로 이동)
                  Expanded(
                    child: GestureDetector(
                      onTap: _goToCurrentWeek,
                      child: Text(
                        '$selectedDayString (${_weekdayNames[weekDates[_tabController.index].weekday - 1]})',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  
                  // 다음 주 버튼
                  AppIconButton(
                    icon: Icons.chevron_right,
                    onPressed: _goToNextWeek,
                    semanticLabel: '다음 주',
                  ),
                ],
              ),
            ),

          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child:
                  _isLoading || _isTabChanging
                      ? AppSkeletonList.cards(
                        itemCount: 3,
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                      )
                      : _filteredMeetups.isEmpty
                      ? AppEmptyState.noMeetups(
                        onCreateMeetup: () => _showCreateMeetupDialog(context),
                      )
                      : OptimizedListView<Meetup>(
                        key: ValueKey<String>(
                          '${_selectedCategory}_${_tabController.index}',
                        ),
                        items: _filteredMeetups,
                        keyExtractor: (meetup) => meetup.id,
                        padding: const EdgeInsets.only(
                          top: 8, // 상단 패딩 최소화
                          bottom: 16,
                        ),
                        itemBuilder: (context, meetup, index) {
                          return OptimizedMeetupCard(
                            key: ValueKey(meetup.id),
                            meetup: meetup,
                            index: index,
                            onTap: () => _navigateToMeetupDetail(meetup),
                            preloadImage: index < 3, // 상위 3개만 프리로드
                          );
                        },
                      ),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  /// 모임 상세 화면으로 이동
  void _navigateToMeetupDetail(Meetup meetup) {
    showDialog(
      context: context,
      builder:
          (context) => MeetupDetailScreen(
            meetup: meetup,
            meetupId: meetup.id,
            onMeetupDeleted: () {
              _meetupCache.clear();
              _categoryMeetupCache.clear();
              _loadMeetups(); // 모임이 삭제되면 목록 새로고침
            },
          ),
    );
  }

  /// 컴팩트 헤더 (콘텐츠 노출 극대화)
  Widget _buildCompactHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, 1),
            blurRadius: 3,
            spreadRadius: 0,
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 검색 모드에 따른 헤더
            if (_isSearching)
              CompactSearchBar(
                controller: _searchController,
                hintText: '모임 검색',
                leading: AppIconButton(
                  icon: Icons.arrow_back,
                  onPressed: () {
                    setState(() {
                      _isSearching = false;
                      _searchController.clear();
                    });
                    _loadMeetups();
                  },
                  semanticLabel: '뒤로가기',
                ),
                showClearButton: _searchController.text.isNotEmpty,
                onClearPressed: () {
                  _searchController.clear();
                  _loadMeetups();
                },
                onChanged: (value) {
                  setState(() {});
                  _loadMeetups();
                },
              )
            else
              // 기본 모드에서는 검색바 제거 - 중복 방지
              const SizedBox.shrink(),

            // 카테고리 칩 (검색 모드가 아닐 때만 표시)
            if (!_isSearching)
              CompactCategoryChips(
                categories: _categories,
                selectedCategory: _selectedCategory,
                onCategoryChanged: (category) {
                  setState(() {
                    _selectedCategory = category;
                  });
                  _loadMeetups();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 컴팩트 탭바
  Widget _buildCompactTabBar(List<DateTime> weekDates) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 56, // 컴팩트 높이
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withOpacity(0.2),
            width: 0.5,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        tabs: List.generate(
          weekDates.length,
          (index) => Tab(
            height: 48, // 터치 타깃 확보
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 요일 (일요일은 빨간색)
                Text(
                  _weekdayNames[weekDates[index].weekday - 1],
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: weekDates[index].weekday == 7 // 일요일 체크 (7 = 일요일)
                        ? Colors.red
                        : null, // 기본 색상 유지
                  ),
                ),
                const SizedBox(height: 2),
                // 날짜 (일요일은 빨간색)
                Text(
                  '${weekDates[index].day}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: weekDates[index].weekday == 7 // 일요일 체크
                        ? Colors.red
                        : null, // 기본 색상 유지
                  ),
                ),
              ],
            ),
          ),
        ),
        isScrollable: false,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
        indicatorWeight: 2,
        indicatorSize: TabBarIndicatorSize.tab,
        onTap: (index) {
          if (!_isTabChanging) {
            _isTabChanging = true;
            _loadMeetups().then((_) {
              _isTabChanging = false;
            });
          }
        },
      ),
    );
  }
}
