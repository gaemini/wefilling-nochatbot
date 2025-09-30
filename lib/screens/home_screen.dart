// lib/screens/home_screen.dart
// 모임 홈 화면 - 일주일 단위 모임 목록 표시
// 탭 기반 네비게이션, 카테고리 필터, 검색 기능

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

class MeetupHomePage extends StatefulWidget {
  const MeetupHomePage({super.key});

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

  // 검색 기능
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  // 카테고리 필터링
  final List<String> _categories = ['전체', '스터디', '식사', '취미', '문화'];
  String _selectedCategory = '전체';

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
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _friendCategoryService.dispose();
    super.dispose();
  }

  // 친구 카테고리 로드
  void _loadFriendCategories() {
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
          
          // 날짜 필터링 추가 적용
          final selectedDate = _getWeekDates()[_tabController.index];
          final startOfDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
          final endOfDay = startOfDay.add(const Duration(days: 1)).subtract(const Duration(microseconds: 1));
          
          allMeetups = allMeetups.where((meetup) {
            return meetup.date.isAfter(startOfDay.subtract(const Duration(microseconds: 1))) &&
                   meetup.date.isBefore(endOfDay.add(const Duration(microseconds: 1)));
          }).toList();
        }
      }

      // 카테고리 필터링 적용
      if (_selectedCategory == '전체') {
        _filteredMeetups = allMeetups;
      } else {
        _filteredMeetups = allMeetups.where((meetup) => meetup.category == _selectedCategory).toList();
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
                hintText: '검색어를 입력하세요',
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

            // 친구 그룹 필터 (검색 모드가 아닐 때만 표시)
            if (!_isSearching)
              _buildFriendGroupFilter(),
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
                // 요일 (일요일은 빨간색, 토요일은 파란색)
                Text(
                  _weekdayNames[weekDates[index].weekday - 1],
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: weekDates[index].weekday == 7 // 일요일 체크 (7 = 일요일)
                        ? Colors.red
                        : weekDates[index].weekday == 6 // 토요일 체크 (6 = 토요일)
                            ? Colors.blue
                            : null, // 기본 색상 유지
                  ),
                ),
                const SizedBox(height: 2),
                // 날짜 (일요일은 빨간색, 토요일은 파란색)
                Text(
                  '${weekDates[index].day}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: weekDates[index].weekday == 7 // 일요일 체크
                        ? Colors.red
                        : weekDates[index].weekday == 6 // 토요일 체크
                            ? Colors.blue
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

  // 친구 그룹 필터 UI 빌드
  Widget _buildFriendGroupFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 필터 버튼
          OutlinedButton.icon(
            onPressed: () {
              _showFriendFilterBottomSheet();
            },
            icon: Icon(
              Icons.filter_list,
              size: 18,
              color: _friendFilter != 'all' 
                ? const Color(0xFF4A90E2) 
                : const Color(0xFF666666),
            ),
            label: Text(
              _getFriendFilterDisplayText(),
              style: TextStyle(
                fontSize: 13,
                color: _friendFilter != 'all' 
                  ? const Color(0xFF4A90E2) 
                  : const Color(0xFF666666),
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 32),
              side: BorderSide(
                color: _friendFilter != 'all' 
                  ? const Color(0xFF4A90E2) 
                  : const Color(0xFFDDDDDD),
                width: 1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          
          // 필터 초기화 버튼 (필터가 적용된 경우에만 표시)
          if (_friendFilter != 'all') ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _friendFilter = 'all';
                });
                _loadMeetups();
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFFF5F5F5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: Color(0xFF666666),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 친구 필터 표시 텍스트 가져오기
  String _getFriendFilterDisplayText() {
    switch (_friendFilter) {
      case 'public':
        return '전체 공개만';
      case 'friends':
        return '친구 모임만';
      default:
        if (_friendFilter.startsWith('category:')) {
          final categoryId = _friendFilter.substring(9);
          final category = _friendCategories.firstWhere(
            (cat) => cat.id == categoryId,
            orElse: () => FriendCategory(
              id: '',
              name: '알 수 없음',
              description: '',
              color: '',
              iconName: '',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              userId: '',
              friendIds: [],
            ),
          );
          return '${category.name} 그룹';
        }
        return '모든 모임';
    }
  }

  // 친구 필터 바텀시트 표시
  void _showFriendFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '모임 필터',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // 필터 옵션들
              _buildFilterOption(
                title: '모든 모임',
                subtitle: '볼 수 있는 모든 모임을 표시합니다',
                value: 'all',
                icon: Icons.public,
              ),
              _buildFilterOption(
                title: '전체 공개만',
                subtitle: '누구나 볼 수 있도록 공개된 모임만 표시',
                value: 'public',
                icon: Icons.language,
              ),
              _buildFilterOption(
                title: '친구 모임만',
                subtitle: '친구들이 만든 모든 모임을 표시',
                value: 'friends',
                icon: Icons.people,
              ),
              
              // 친구 그룹별 필터
              if (_friendCategories.isNotEmpty) ...[
                const Divider(height: 24),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.blue[600],
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '특정 친구 그룹만 보기',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '선택한 그룹에 공개된 모임만 표시됩니다',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF888888),
                  ),
                ),
                const SizedBox(height: 8),
                
                ...(_friendCategories.map((category) => _buildFilterOption(
                  title: category.name,
                  subtitle: '${category.friendIds.length}명의 친구 · 이 그룹에 공개된 모임만 표시',
                  value: 'category:${category.id}',
                  icon: Icons.group,
                ))),
              ],
              
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // 필터 옵션 아이템 빌드
  Widget _buildFilterOption({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
  }) {
    final isSelected = _friendFilter == value;
    
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? const Color(0xFF4A90E2) : const Color(0xFF666666),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? const Color(0xFF4A90E2) : null,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: isSelected 
        ? const Icon(Icons.check, color: Color(0xFF4A90E2))
        : null,
      onTap: () {
        setState(() {
          _friendFilter = value;
        });
        Navigator.pop(context);
        _loadMeetups();
      },
    );
  }
}
