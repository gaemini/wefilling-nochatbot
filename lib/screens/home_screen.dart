// 모임 메인 화면
// 날짜별 모임 목록 표시
// 모임 생성 기능 제공

import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/meetup.dart';
import '../services/meetup_service.dart';
import 'create_meetup_screen.dart';
import 'meetup_detail_screen.dart';

class MeetupHomePage extends StatefulWidget {
  const MeetupHomePage({super.key});

  @override
  State<MeetupHomePage> createState() => _MeetupHomePageState();
}

class _MeetupHomePageState extends State<MeetupHomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];
  // 기존 메모리 기반 데이터 - 필요시 폴백으로 사용
  late List<List<Meetup>> _localMeetupsByDay;
  final MeetupService _meetupService = MeetupService();

  // 검색 관련 변수
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  // 카테고리 필터링 관련 변수
  String _selectedCategory = '전체';
  final List<String> _categories = ['전체', '오늘', '스터디', '식사', '취미', '문화', '기타'];

  // 카테고리별로 필터링된 모임 목록을 담을 변수
  List<Meetup> _filteredMeetups = [];
  bool _isLoading = true;
  // 탭 변경 중 플래그
  bool _isTabChanging = false;
  // 요일별 모임 캐시 추가
  final Map<int, List<Meetup>> _meetupCache = {};

  final Map<String, Map<int, List<Meetup>>> _categoryMeetupCache = {};

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

    // 초기 탭은 항상 첫 번째 탭 (오늘)
    _tabController.animateTo(0);

    // 전체 모임 목록을 가져옴
    _loadMeetups();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  // 탭 변경 감지
  void _onTabChanged() {
    if (_tabController.indexIsChanging || _tabController.index != _tabController.previousIndex) {
      // 탭이 변경됐을 때 해당 요일의 모임만 불러오기
      if (!_isSearching) {
        setState(() {
          _isTabChanging = true; // 탭 변경 중 플래그 설정
        });

        // 약간의 지연 후 데이터 로드 (부드러운 전환을 위해)
        Future.delayed(const Duration(milliseconds: 150), () {
          // 현재 선택된 카테고리와 탭에 대한 캐시가 있는지 확인
          if (_categoryMeetupCache.containsKey(_selectedCategory) &&
              _categoryMeetupCache[_selectedCategory]!.containsKey(_tabController.index)) {
            setState(() {
              _filteredMeetups = _categoryMeetupCache[_selectedCategory]![_tabController.index]!;
              _isTabChanging = false;
              _isLoading = false;
            });
          } else {
            _loadMeetups();
          }
        });
      }
    }
  }

  void _showCreateMeetupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return CreateMeetupScreen(
          initialDayIndex: _tabController.index,
          onCreateMeetup: (dayIndex, newMeetup) async {
            // CreateMeetupScreen에서 이미 Firebase에 저장됨
            // 해당 요일 탭으로 이동
            _tabController.animateTo(dayIndex);
          },
        );
      },
    );
  }

  // 검색어 변경 감지
  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      if (_searchQuery.isEmpty) {
        _isSearching = false;
      } else {
        _isSearching = true;
      }
    });

    // 검색 실행
    if (_isSearching) {
      _searchMeetups();
    } else {
      _loadMeetups(); // 검색어가 없으면 기본 모임 목록 로드
    }
  }

  // 검색 실행
  void _searchMeetups() {
    setState(() {
      _isLoading = true;
    });

    _meetupService.searchMeetups(_searchQuery).listen((meetups) {
      if (mounted) {
        setState(() {
          _filteredMeetups = meetups;
          _isLoading = false;
        });
      }
    }, onError: (error) {
      if (mounted) {
        setState(() {
          _filteredMeetups = [];
          _isLoading = false;
        });
        print('모임 검색 중 오류 발생: $error');
      }
    });
  }

  // 카테고리별 모임 로드
  void _loadMeetups() {
    // 검색 중이면 검색 결과만 표시
    if (_isSearching) {
      _searchMeetups();
      return;
    }

    // 현재 선택된 탭(요일) 인덱스
    final currentTabIndex = _tabController.index;

    // 카테고리 캐시에 해당 탭의 데이터가 있는 경우 캐시 사용
    if (_categoryMeetupCache.containsKey(_selectedCategory) &&
        _categoryMeetupCache[_selectedCategory]!.containsKey(currentTabIndex)) {
      setState(() {
        _filteredMeetups = _categoryMeetupCache[_selectedCategory]![currentTabIndex]!;
        _isTabChanging = false;
        _isLoading = false;
      });
      return;
    }

    // 로딩 중이 아닌 경우만 로딩 상태 설정
    if (!_isTabChanging) {
      setState(() {
        _isLoading = true;
      });
    }

    // 해당 요일에 해당하는 날짜 계산
    final selectedDate = _meetupService.getDayDate(currentTabIndex);

    late Stream<List<Meetup>> meetupStream;

    if (_selectedCategory == '전체') {
      // 선택된 날짜의 모임만 가져오기
      print('전체 카테고리: 날짜별 데이터 로드 - 탭=$currentTabIndex');
      meetupStream = _meetupService.getMeetupsByDay(currentTabIndex);
    } else if (_selectedCategory == '오늘') {
      print('오늘 카테고리: 오늘 데이터 로드');
      meetupStream = _meetupService.getTodayMeetups();
    } else {
      // 선택된 날짜와 카테고리에 맞는 모임 필터링
      print('특정 카테고리: $_selectedCategory - 날짜로 필터링 예정');

      // 카테고리별 모든 데이터 가져오기
      meetupStream = _meetupService.getMeetupsByCategory(_selectedCategory);

      // 스트림 변환: 카테고리로 먼저 필터링된 결과를 날짜로 추가 필터링
      meetupStream = meetupStream.map((allCategoryMeetups) {
        print('카테고리 $_selectedCategory 모임 총: ${allCategoryMeetups.length}개');

        // 현재 선택된 날짜의 모임만 필터링
        final filteredByDate = allCategoryMeetups.where((meetup) {
          final meetupDate = DateTime(meetup.date.year, meetup.date.month, meetup.date.day);
          final targetDate = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
          return meetupDate.isAtSameMomentAs(targetDate);
        }).toList();

        print('날짜 필터링 후 $_selectedCategory 모임: ${filteredByDate.length}개');
        return filteredByDate;
      });
    }

    // 구독
    meetupStream.listen((meetups) {
      if (mounted) {
        setState(() {
          _filteredMeetups = meetups;
          _isLoading = false;
          _isTabChanging = false;

          // 카테고리별 캐시에 저장
          if (!_categoryMeetupCache.containsKey(_selectedCategory)) {
            _categoryMeetupCache[_selectedCategory] = {};
          }
          _categoryMeetupCache[_selectedCategory]![currentTabIndex] = meetups;

          // 전체 카테고리인 경우 일반 캐시에도 저장
          if (_selectedCategory == '전체') {
            _meetupCache[currentTabIndex] = meetups;
          }
        });
      }
    }, /* ... */);
  }

  @override
  Widget build(BuildContext context) {
    // 현재 날짜 기준 일주일 날짜 계산 (오늘부터 6일 후까지)
    final List<DateTime> weekDates = _meetupService.getWeekDates();

    // 선택된 요일의 날짜 문자열 미리 계산
    final selectedDayString = '${weekDates[_tabController.index].month}월 ${weekDates[_tabController.index].day}일';

    return Scaffold(
      body: Column(
        children: [
          // 검색 모드인지 기본 모드인지에 따라 다른 헤더 표시
          _isSearching
              ? _buildSearchHeader()
              : _buildNormalHeader(),

          // 탭바 (검색 모드가 아닐 때만 표시)
          if (!_isSearching)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey[300]!,
                    width: 1.0,
                  ),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                tabs: List.generate(
                  weekDates.length,
                      (index) => Tab(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 요일 (월, 화, 수, ...)
                        Text(_weekdayNames[weekDates[index].weekday - 1]),
                        // 날짜 (1, 2, 3, ...)
                        Text(
                          '${weekDates[index].day}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                isScrollable: false,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
                labelColor: Colors.blue[600],
                unselectedLabelColor: Colors.grey[800],
                indicatorColor: Colors.blue[600],
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.tab,
              ),
            ),

          // 현재 선택된 날짜와 요일 표시 (검색 모드가 아닐 때만)
          if (!_isSearching)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(Icons.event, color: Colors.blue[600], size: 20.0),  // 날짜 아이콘 추가
                  const SizedBox(width: 8.0),
                  Text(
                    selectedDayString,
                    style: TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(width: 4.0),
                  Text(
                    '(${_weekdayNames[weekDates[_tabController.index].weekday - 1]})',  // 요일 추가
                    style: TextStyle(
                      fontSize: 14.0,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

          // 카테고리별 모임 목록
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: _isLoading || _isTabChanging
                  ? const Center(
                key: ValueKey<String>('loading'),
                child: CircularProgressIndicator(),
              )
                  : _filteredMeetups.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                key: ValueKey<String>('${_selectedCategory}_${_tabController.index}'),
                padding: const EdgeInsets.all(16),
                itemCount: _filteredMeetups.length,
                itemBuilder: (context, index) {
                  final meetup = _filteredMeetups[index];
                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: InkWell(
                      onTap: () {
                        // 상세 화면으로 이동
                        showDialog(
                          context: context,
                          builder: (context) => MeetupDetailScreen(
                            meetup: meetup,
                            meetupId: meetup.id,
                            onMeetupDeleted: () {
                              _meetupCache.clear();
                              _categoryMeetupCache.clear();
                              _loadMeetups(); // 모임이 삭제되면 목록 새로고침
                            },
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 카테고리 뱃지
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (meetup.category == '스터디')
                                    ? Colors.blue.shade700.withValues(alpha: 26)  // 0.1 * 255 ≈ 26
                                    : (meetup.category == '식사')
                                    ? Colors.orange.shade700.withValues(alpha: 26)
                                    : (meetup.category == '취미')
                                    ? Colors.green.shade700.withValues(alpha: 26)
                                    : (meetup.category == '문화')
                                    ? Colors.purple.shade700.withValues(alpha: 26)
                                    : Colors.grey.shade700.withValues(alpha: 26),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: (meetup.category == '스터디')
                                      ? Colors.blue.shade700.withValues(alpha: 128)  // 0.5 * 255 = 128
                                      : (meetup.category == '식사')
                                      ? Colors.orange.shade700.withValues(alpha: 128)
                                      : (meetup.category == '취미')
                                      ? Colors.green.shade700.withValues(alpha: 128)
                                      : (meetup.category == '문화')
                                      ? Colors.purple.shade700.withValues(alpha: 128)
                                      : Colors.grey.shade700.withValues(alpha: 128),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                meetup.category,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: (meetup.category == '스터디')
                                      ? Colors.blue.shade700
                                      : (meetup.category == '식사')
                                      ? Colors.orange.shade700
                                      : (meetup.category == '취미')
                                      ? Colors.green.shade700
                                      : (meetup.category == '문화')
                                      ? Colors.purple.shade700
                                      : Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              meetup.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // 위치
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 16),
                                const SizedBox(width: 4),
                                Text(meetup.location),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // 시간
                            Row(
                              children: [
                                const Icon(Icons.access_time, size: 16),
                                const SizedBox(width: 4),
                                Text(meetup.time),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // 참가자
                            Row(
                              children: [
                                const Icon(Icons.people, size: 16),
                                const SizedBox(width: 4),
                                Text('${meetup.currentParticipants}/${meetup.maxParticipants}명'),
                                const Spacer(),
                                // 참여 버튼
                                ElevatedButton(
                                  onPressed: () async {
                                    try {
                                      final success = await _meetupService.joinMeetup(meetup.id);
                                      if (success) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('${meetup.title}${AppConstants.JOINED_MEETUP}')),
                                        );
                                        // 모임 목록 다시 로드
                                        _loadMeetups();
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('모임 참여에 실패했습니다. 다시 시도해주세요.')),
                                        );
                                      }
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('오류가 발생했습니다: $e')),
                                      );
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: meetup.currentParticipants >= meetup.maxParticipants
                                        ? Colors.grey
                                        : Colors.blue.shade600,
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                  ),
                                  child: Text(
                                    meetup.currentParticipants >= meetup.maxParticipants
                                        ? '마감'
                                        : '참여',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showCreateMeetupDialog(context);
        },
        tooltip: AppConstants.CREATE_MEETUP,
        child: const Icon(Icons.add),
      ),
    );
  }

  // 검색 모드 헤더
  Widget _buildSearchHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.blue.shade700,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 검색바
            Row(
              children: [
                // 뒤로가기 버튼
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _isSearching = false;
                      _searchController.clear();
                    });
                    _loadMeetups();
                  },
                ),
                // 검색 입력 필드
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: '모임 검색',
                        hintStyle: TextStyle(color: Colors.white70),
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(color: Colors.white),
                      autofocus: true,
                    ),
                  ),
                ),
                // 지우기 버튼 (검색어가 있을 때만 표시)
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white),
                    onPressed: () {
                      _searchController.clear();
                    },
                  ),
              ],
            ),
            // 검색 결과 요약
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(left: 16, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                  children: [
                    const TextSpan(text: '검색: '),
                    TextSpan(
                      text: '"$_searchQuery"',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: ' (${_filteredMeetups.length}개)'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 일반 모드 헤더
  Widget _buildNormalHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade100, Colors.blue.shade200],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "함께하는 모임",
              style: TextStyle(
                fontSize: 26.0,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "새로운 친구들과 커피챗을 시작해보세요",
              style: TextStyle(
                fontSize: 14.0,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 16),

            // 검색창 추가
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '모임 검색하기',
                  prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      _searchController.clear();
                    },
                  )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 15,
                  ),
                ),
                textInputAction: TextInputAction.search,
              ),
            ),

            const SizedBox(height: 16),

            // 카테고리 필터 칩
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.map((category) {
                  final bool isSelected = _selectedCategory == category;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      // 카테고리 필터 칩 - onTap 핸들러 수정
                      onTap: () {
                        final previousCategory = _selectedCategory;
                        setState(() {
                          _selectedCategory = category;
                          _isLoading = true;

                          // 카테고리가 변경되면 해당 카테고리의 캐시를 비움
                          if (previousCategory != category) {
                            _categoryMeetupCache.remove(category);
                          }
                        });

                        // 데이터 즉시 로드
                        _loadMeetups();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.blue.shade500 : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? Colors.blue.shade500 : Colors.grey.shade300,
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isSelected ? 0.15 : 0.08),
                              blurRadius: isSelected ? 6 : 3,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          category,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 빈 상태 위젯 추가
  Widget _buildEmptyState() {
    return Center(
      key: ValueKey<String>('empty_${_selectedCategory}_${_tabController.index}'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '모임을 찾을 수 없습니다',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '다른 카테고리를 선택하거나 새 모임을 만들어보세요',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              _showCreateMeetupDialog(context);
            },
            icon: const Icon(Icons.add),
            label: const Text('새 모임 만들기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}