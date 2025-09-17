// lib/screens/meetup_search_screen.dart
// 모임 검색 화면
// 검색 기능 및 결과 표시

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/meetup.dart';
import '../services/meetup_service.dart';
import '../services/storage_service.dart';
import '../widgets/country_flag_circle.dart';

class MeetupSearchScreen extends StatefulWidget {
  const MeetupSearchScreen({Key? key}) : super(key: key);

  @override
  State<MeetupSearchScreen> createState() => _MeetupSearchScreenState();
}

class _MeetupSearchScreenState extends State<MeetupSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MeetupService _meetupService = MeetupService();
  String _searchQuery = '';
  bool _isLoading = false;
  List<Meetup> _searchResults = [];

  // 포커스 관리용 노드
  final FocusNode _searchFocusNode = FocusNode();

  // 검색 필터 옵션
  String? _selectedDay;
  final List<String> _dayOptions = ['전체', '월', '화', '수', '목', '금', '토', '일'];

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose(); // 포커스 노드 해제
    // 화면 방향 제한 해제
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  // 검색 실행 함수
  Future<void> _performSearch() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 모임 서비스를 통해 검색 실행
      _meetupService
          .searchMeetups(_searchQuery)
          .listen(
            (results) {
              if (mounted) {
                setState(() {
                  _searchResults = results;
                  _isLoading = false;
                });
              }
            },
            onError: (e) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('검색 중 오류가 발생했습니다: $e')));
              }
            },
          );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('검색 중 오류가 발생했습니다: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 화면 가로 모드 제한
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // 키보드가 열렸을 때 패딩 계산
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('모임 검색'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        // GestureDetector로 감싸서 빈 공간 탭하면 키보드 닫히도록 함
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.translucent, // 투명한 영역까지 탭 감지
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(), // 항상 스크롤 가능하도록 설정
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 키보드가 나타날 때 패딩 추가
                SizedBox(height: MediaQuery.of(context).padding.top),

                // 검색 입력 영역
                Padding(
                  padding: EdgeInsets.only(
                    left: 16.0,
                    right: 16.0,
                    top: 8.0,
                    bottom: 8.0,
                  ),
                  child: Column(
                    children: [
                      // 검색창
                      TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode, // 포커스 노드 연결
                        decoration: InputDecoration(
                          hintText: '모임 이름, 장소, 내용으로 검색',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon:
                              _searchQuery.isNotEmpty
                                  ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _searchQuery = '';
                                      });
                                    },
                                  )
                                  : null,
                          filled: true,
                          fillColor: Colors.grey[200],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                        onSubmitted: (_) {
                          _performSearch();
                        },
                      ),

                      const SizedBox(height: 12),

                      // 필터 영역 (요일 필터)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            const Text(
                              '요일: ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            ..._dayOptions.map((day) {
                              final isSelected =
                                  _selectedDay == day ||
                                  (_selectedDay == null && day == '전체');
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: ChoiceChip(
                                  label: Text(day),
                                  selected: isSelected,
                                  selectedColor: Colors.blue[100],
                                  onSelected: (selected) {
                                    setState(() {
                                      _selectedDay = day == '전체' ? null : day;
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 검색 버튼
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              _searchQuery.isNotEmpty
                                  ? () {
                                    _searchFocusNode.unfocus(); // 키보드 숨기기
                                    _performSearch();
                                  }
                                  : null,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child:
                              _isLoading
                                  ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Text('검색하기'),
                        ),
                      ),
                    ],
                  ),
                ),

                // 검색 결과 영역
                _isLoading
                    ? Container(
                      height: 200,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(),
                    )
                    : _searchResults.isEmpty
                    ? Container(
                      height: 200,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _searchQuery.isEmpty
                                ? Icons.search
                                : Icons.search_off,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty ? '검색어를 입력하세요' : '검색 결과가 없습니다',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                    : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: _searchResults.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final meetup = _searchResults[index];
                        return MeetupCard(meetup: meetup);
                      },
                    ),

                // 키보드 패딩 추가 - 키보드가 올라왔을 때 컨텐츠가 가려지지 않도록
                SizedBox(height: bottomPadding > 0 ? bottomPadding : 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 모임 카드 위젯 (검색 결과 표시용)
class MeetupCard extends StatelessWidget {
  final Meetup meetup;

  const MeetupCard({Key? key, required this.meetup}) : super(key: key);

  // 썸네일 위젯 생성
  Widget _buildThumbnail() {
    // 썸네일 이미지가 있는 경우 (URL이 있는 경우)
    if (meetup.thumbnailImageUrl != null &&
        meetup.thumbnailImageUrl.isNotEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          image: DecorationImage(
            image: NetworkImage(
              StorageService.correctFirebaseStorageUrl(
                meetup.thumbnailImageUrl,
              ),
            ),
            fit: BoxFit.cover,
          ),
        ),
        alignment: Alignment.center,
        child:
            meetup.thumbnailContent != null &&
                    meetup.thumbnailContent.isNotEmpty
                ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    meetup.thumbnailContent,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                )
                : null,
      );
    }
    // 썸네일 이미지가 없고 텍스트만 있는 경우
    else if (meetup.thumbnailContent != null &&
        meetup.thumbnailContent.isNotEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          color: _getCategoryColor(meetup.category).withValues(alpha: 76),
        ),
        alignment: Alignment.center,
        child: Text(
          meetup.thumbnailContent,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _getCategoryColor(meetup.category),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      );
    }
    // 썸네일이 없는 경우 카테고리 기반 배너
    else {
      return Container(
        height: 80,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          color: _getCategoryColor(meetup.category).withValues(alpha: 51),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getCategoryIcon(meetup.category),
              color: _getCategoryColor(meetup.category),
              size: 30,
            ),
            const SizedBox(width: 8),
            Text(
              meetup.category,
              style: TextStyle(
                color: _getCategoryColor(meetup.category),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }
  }

  // 카테고리별 아이콘
  IconData _getCategoryIcon(String category) {
    switch (category) {
      case '스터디':
        return Icons.book;
      case '식사':
        return Icons.restaurant;
      case '취미':
        return Icons.sports_basketball;
      case '문화':
        return Icons.theater_comedy;
      default:
        return Icons.category;
    }
  }

  // 카테고리별 색상
  Color _getCategoryColor(String category) {
    switch (category) {
      case '스터디':
        return Colors.blue;
      case '식사':
        return Colors.orange;
      case '취미':
        return Colors.green;
      case '문화':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        // 모임 상세 페이지로 이동
      },
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias, // 모서리가 잘리지 않도록 설정
        child: Column(
          children: [
            // 썸네일 영역
            _buildThumbnail(),

            // 컨텐츠 영역
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 제목과 상태
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meetup.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(meetup.getStatus()),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          meetup.getStatus(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // 설명
                  if (meetup.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      meetup.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 8),

                  // 장소 및 시간
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          meetup.location,
                          style: TextStyle(color: Colors.grey[700]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_getFormattedDate(meetup.date)} ${meetup.time}',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // 인원 및 주최자
                  Row(
                    children: [
                      Icon(Icons.group, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '${meetup.currentParticipants}/${meetup.maxParticipants}명',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.person, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '주최: ${meetup.host}',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      if (meetup.hostNationality != null &&
                          meetup.hostNationality.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CountryFlagCircle(
                            nationality: meetup.hostNationality,
                            size: 18,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 날짜 포맷 함수
  String _getFormattedDate(DateTime date) {
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[date.weekday - 1];
    return '${date.month}/${date.day}($weekday)';
  }

  // 상태에 따른 색상
  Color _getStatusColor(String status) {
    switch (status) {
      case '예정':
        return Colors.blue;
      case '진행중':
        return Colors.green;
      case '종료':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }
}
