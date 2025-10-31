// lib/screens/home_screen.dart
// 모임 홈 화면 - 일주일 단위 모임 목록 표시
// 탭 기반 네비게이션, 카테고리 필터, 검색 기능

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../constants/app_constants.dart';
import '../models/meetup.dart';
import '../models/friend_category.dart';
import '../services/meetup_service.dart';
import '../services/friend_category_service.dart';
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
  // 기존 메모리 기반 데이터 - 필요시 폴백으로 사용
  late List<List<Meetup>> _localMeetupsByDay;
  final MeetupService _meetupService = MeetupService();
  final FriendCategoryService _friendCategoryService = FriendCategoryService();
  
  // 친구 카테고리 스트림 구독
  StreamSubscription<List<FriendCategory>>? _friendCategoriesSubscription;

  // 검색 기능
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  // 카테고리 필터링 (영어 키 사용)
  final List<String> _categories = ['all', 'study', 'meal', 'hobby', 'culture'];
  String _selectedCategory = 'all';

  // 친구 그룹 필터링
  List<FriendCategory> _friendCategories = [];
  String _friendFilter = 'all'; // 'all', 'public', 'friends', 'category:categoryId'
  bool _showFriendFilter = false;

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
      _loadFriendCategories();
      
      // 알림에서 전달받은 모임이 있으면 다이얼로그 표시
      if (widget.initialMeetupId != null) {
        _showMeetupFromNotification(widget.initialMeetupId!);
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _friendCategoriesSubscription?.cancel();
    _friendCategoryService.dispose();
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
                SnackBar(content: Text(AppLocalizations.of(context)!.meetupCancelled)),
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
    _friendCategoriesSubscription = _friendCategoryService.getCategoriesStream().listen((categories) {
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
          allMeetups = await _meetupService.getFilteredMeetupsByFriendCategories(
            categoryIds: [categoryId],
          );
        } else if (_friendFilter == 'friends') {
          // 모든 친구의 모임
          allMeetups = await _meetupService.getFilteredMeetupsByFriendCategories(
            categoryIds: null,
          );
        } else if (_friendFilter == 'public') {
          // 전체 공개 모임만
          allMeetups = await _meetupService.getFilteredMeetupsByFriendCategories(
            categoryIds: [],
          );
        } else {
          // 모든 모임 (기본값) - 공개 범위 필터링 적용
          allMeetups = await _meetupService.getFilteredMeetupsByFriendCategories(
            categoryIds: null, // null = 모든 친구 관계 기반 필터링
          );
        }
        
        // 모든 경우에 날짜 필터링 적용 (검색 모드가 아닐 때)
        final selectedDate = _getWeekDates()[_tabController.index];
        final startOfDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
        final endOfDay = startOfDay.add(const Duration(days: 1)).subtract(const Duration(microseconds: 1));
        
        allMeetups = allMeetups.where((meetup) {
          return meetup.date.isAfter(startOfDay.subtract(const Duration(microseconds: 1))) &&
                 meetup.date.isBefore(endOfDay.add(const Duration(microseconds: 1)));
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
        final firestoreCategory = categoryMap[_selectedCategory] ?? _selectedCategory;
        _filteredMeetups = allMeetups.where((meetup) => meetup.category == firestoreCategory).toList();
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
    final selectedDate = weekDates[_tabController.index];
    
    // 현재 로케일에 맞게 날짜 포맷팅
    final locale = Localizations.localeOf(context).languageCode;
    final selectedDayString = locale == 'ko' 
        ? '${selectedDate.month}월 ${selectedDate.day}일'
        : DateFormat('MMM d', 'en').format(selectedDate);
    
    // 요일 약어 (로케일에 따라 다름)
    final weekdayName = locale == 'ko'
        ? ['월', '화', '수', '목', '금', '토', '일'][selectedDate.weekday - 1]
        : _weekdayNames[selectedDate.weekday - 1];

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
              height: 40, // 명시적인 높이 지정으로 두께 조절
              padding: const EdgeInsets.symmetric(
                vertical: 0,
                horizontal: 16.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 이전 주 버튼
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: _goToPreviousWeek,
                  ),
                  
                  // 현재 날짜 정보 (탭하면 오늘로 이동)
                  Expanded(
                    child: GestureDetector(
                      onTap: _goToCurrentWeek,
                      child: Text(
                        '$selectedDayString ($weekdayName)',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 14,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  
                  // 다음 주 버튼
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: _goToNextWeek,
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
                        context: context,
                        onCreateMeetup: () => _showCreateMeetupDialog(context),
                      )
                      : RefreshIndicator(
                        onRefresh: () async {
                          // 캐시 클리어 및 데이터 새로고침
                          _meetupCache.clear();
                          _categoryMeetupCache.clear();
                          await _loadMeetups();
                        },
                        child: OptimizedListView<Meetup>(
                          key: ValueKey<String>(
                            '${_selectedCategory}_${_tabController.index}',
                          ),
                          items: _filteredMeetups,
                          keyExtractor: (meetup) => meetup.id,
                          padding: const EdgeInsets.only(
                            top: 8, // 상단 패딩 최소화
                            bottom: 90, // FAB을 위한 하단 여유 공간
                          ),
                          itemBuilder: (context, meetup, index) {
                            return OptimizedMeetupCard(
                              key: ValueKey(meetup.id),
                              meetup: meetup,
                              index: index,
                              onTap: () => _navigateToMeetupDetail(meetup),
                              preloadImage: index < 3, // 상위 3개만 프리로드
                              onMeetupDeleted: () {
                                // 모임 삭제 후 목록 새로고침
                                setState(() {
                                  _loadMeetups();
                                });
                              },
                            );
                          },
                        ),
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MeetupDetailScreen(
          meetup: meetup,
          meetupId: meetup.id,
          onMeetupDeleted: () {
            _meetupCache.clear();
            _categoryMeetupCache.clear();
            _loadMeetups(); // 모임이 삭제되면 목록 새로고침
          },
        ),
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
                hintText: AppLocalizations.of(context)!.enterSearchQuery,
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Container(
      height: 64, // 높이 증가 (56 → 64)
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
          (index) {
            final date = weekDates[index];
            final dateOnly = DateTime(date.year, date.month, date.day);
            final isToday = dateOnly.isAtSameMomentAs(today);
            
            return Tab(
              height: 60, // 높이 증가 (48 → 60)
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 오늘 날짜 표시 점
                  if (isToday)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(bottom: 2), // 간격 축소 (4 → 2)
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90E2), // 위필링 로고색 (파란색)
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    const SizedBox(height: 8), // 간격 축소 (10 → 8)
                  // 요일 (일요일은 빨간색, 토요일은 파란색)
                  Text(
                    _weekdayNames[date.weekday - 1],
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12, // 폰트 크기 축소 (13 → 12)
                      color: date.weekday == 7 // 일요일 체크 (7 = 일요일)
                          ? Colors.red
                          : date.weekday == 6 // 토요일 체크 (6 = 토요일)
                              ? Colors.blue
                              : null, // 기본 색상 유지
                    ),
                  ),
                  const SizedBox(height: 1), // 간격 축소 (2 → 1)
                  // 날짜 (일요일은 빨간색, 토요일은 파란색)
                  Text(
                    '${date.day}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 15, // 폰트 크기 축소 (16 → 15)
                      color: date.weekday == 7 // 일요일 체크
                          ? Colors.red
                          : date.weekday == 6 // 토요일 체크
                              ? Colors.blue
                              : null, // 기본 색상 유지
                    ),
                  ),
                ],
              ),
            );
          },
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
