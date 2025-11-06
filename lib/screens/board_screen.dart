// lib/screens/board_screen.dart
// 게시판 화면 - 게시글 목록 표시 및 관리
// 검색, 필터링, 작성 기능 포함

import 'package:flutter/material.dart';
import '../models/post.dart';
import '../services/post_service.dart';
import '../ui/widgets/app_fab.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/skeletons.dart';
import '../ui/widgets/optimized_post_card.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';
import '../widgets/ad_banner_widget.dart';
import '../l10n/app_localizations.dart';

class BoardScreen extends StatefulWidget {
  final String? searchQuery;
  
  const BoardScreen({super.key, this.searchQuery});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> with SingleTickerProviderStateMixin {
  final PostService _postService = PostService();
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(_onSearchChanged);
    // 외부에서 전달된 검색어가 있으면 설정
    if (widget.searchQuery != null && widget.searchQuery!.isNotEmpty) {
      _searchController.text = widget.searchQuery!;
      _isSearching = true;
    }
  }

  @override
  void dispose() {
    print('🔄 BoardScreen dispose 시작');
    _tabController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    print('✅ BoardScreen dispose 완료');
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _isSearching = _searchController.text.isNotEmpty;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
    });
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEBEBEB), // 연한 회색 배경 (L: 92%, 친구 카드와 6% 명도 차이)
      body: Column(
        children: [
          // 탭 바
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF5865F2), // 위필링 시그니처 파란색으로 통일
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: const Color(0xFF5865F2), // 위필링 시그니처 파란색으로 통일
              labelStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(text: 'Today'),
                Tab(text: 'All'),
              ],
            ),
          ),
          // 게시글 목록 (광고 배너가 스크롤 영역 안으로 이동)
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 오늘 탭
                _buildTodayPostsTab(),
                // 전체 탭
                _buildAllPostsTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: AppFab.write(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => CreatePostScreen(
                    onPostCreated: () {
                      // 게시글이 작성되면 화면 새로고침 (스트림이므로 자동으로 업데이트됨)
                      setState(() {});
                    },
                  ),
            ),
          );
        },
        heroTag: 'board_write_fab',
      ),
    );
  }

  /// 오늘 게시글 탭
  Widget _buildTodayPostsTab() {
    return StreamBuilder<List<Post>>(
      stream: _postService.getPostsStream(),
      builder: (context, snapshot) {
        if (!mounted) {
          return const SizedBox.shrink();
        }
        
        // 로딩 중이고 데이터가 없으면 스켈레톤 표시
        final bool isInitialLoading = snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;
        
        List<Post> posts = snapshot.data ?? [];

        // 검색 필터링
        if (_isSearching && _searchController.text.isNotEmpty) {
          final searchQuery = _searchController.text.toLowerCase();
          posts = posts.where((post) {
            return post.title.toLowerCase().contains(searchQuery) ||
                post.content.toLowerCase().contains(searchQuery);
          }).toList();
        }

        // 오늘 날짜의 게시글만 필터링
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final todayPosts = posts.where((post) {
          final postDate = DateTime(
            post.createdAt.year,
            post.createdAt.month,
            post.createdAt.day,
          );
          return postDate.isAtSameMomentAs(today);
        }).toList();

        return RefreshIndicator(
          color: const Color(0xFF5865F2),
          backgroundColor: Colors.white,
          onRefresh: () async {
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted) setState(() {});
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _calculateItemCount(isInitialLoading, snapshot.hasError, todayPosts),
            itemBuilder: (context, index) {
              if (!mounted) return const SizedBox.shrink();
              return _buildTodayTabItem(context, isInitialLoading, snapshot.hasError, todayPosts, index);
            },
          ),
        );
      },
    );
  }

  int _calculateItemCount(bool isInitialLoading, bool hasError, List<Post> todayPosts) {
    if (isInitialLoading) {
      return 6; // 광고 배너 + 스켈레톤 5개
    }
    
    if (hasError) {
      return 2; // 광고 배너 + 에러 위젯
    }
    
    if (todayPosts.isEmpty) {
      return 2; // 광고 배너 + Empty State
    }
    
    return todayPosts.length + 1; // 광고 배너 + 게시글들
  }

  Widget _buildTodayTabItem(BuildContext context, bool isInitialLoading, bool hasError, List<Post> todayPosts, int index) {
    // 첫 번째 아이템은 항상 광고 배너
    if (index == 0) {
      return AdBannerWidget(
        key: ValueKey('board_banner_today'),
        widgetId: 'board_banner_today',
      );
    }

    // 로딩 중
    if (isInitialLoading) {
      if (index <= 5) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: AppSkeletonList.cards(
            itemCount: 1,
            padding: EdgeInsets.zero,
          ),
        );
      }
      return const SizedBox.shrink();
    }

    // 에러 상태
    if (hasError) {
      if (index == 1) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: _buildErrorWidget('데이터를 불러올 수 없습니다'),
        );
      }
      return const SizedBox.shrink();
    }

    // 빈 상태
    if (todayPosts.isEmpty) {
      if (index == 1) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 120),
          child: AppEmptyState(
            icon: Icons.calendar_today,
            title: AppLocalizations.of(context)?.yourStoryMatters ?? '당신의 이야기가 중요합니다',
            description: AppLocalizations.of(context)?.shareYourMoments ?? '순간을 공유해보세요',
            illustration: const SizedBox.shrink(),
            padding: EdgeInsets.zero,
          ),
        );
      }
      return const SizedBox.shrink();
    }

    // 게시글 표시
    final postIndex = index - 1;
    if (postIndex < todayPosts.length) {
      final post = todayPosts[postIndex];
      return OptimizedPostCard(
        key: ValueKey(post.id),
        post: post,
        index: postIndex,
        onTap: () => _navigateToPostDetail(post),
        preloadImage: postIndex < 3,
      );
    }

    return const SizedBox.shrink();
  }

  /// 전체 게시글 탭
  Widget _buildAllPostsTab() {
    return StreamBuilder<List<Post>>(
      stream: _postService.getPostsStream(),
      builder: (context, snapshot) {
        if (!mounted) {
          return const SizedBox.shrink();
        }
        
        // 로딩 중이고 데이터가 없으면 스켈레톤 표시
        final bool isInitialLoading = snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;
        
        List<Post> posts = snapshot.data ?? [];

        // 검색 필터링
        if (_isSearching && _searchController.text.isNotEmpty) {
          final searchQuery = _searchController.text.toLowerCase();
          posts = posts.where((post) {
            return post.title.toLowerCase().contains(searchQuery) ||
                post.content.toLowerCase().contains(searchQuery);
          }).toList();
        }

        return RefreshIndicator(
          color: const Color(0xFF5865F2),
          backgroundColor: Colors.white,
          onRefresh: () async {
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted) setState(() {});
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _calculateAllTabItemCount(isInitialLoading, snapshot.hasError, posts),
            itemBuilder: (context, index) {
              if (!mounted) return const SizedBox.shrink();
              return _buildAllTabItem(context, isInitialLoading, snapshot.hasError, posts, index);
            },
          ),
        );
      },
    );
  }

  int _calculateAllTabItemCount(bool isInitialLoading, bool hasError, List<Post> posts) {
    if (isInitialLoading) {
      return 6; // 광고 배너 + 스켈레톤 5개
    }
    
    if (hasError) {
      return 2; // 광고 배너 + 에러 위젯
    }
    
    if (posts.isEmpty) {
      return 2; // 광고 배너 + Empty State
    }
    
    final groupedPosts = _groupPostsByDate(posts);
    int totalItems = 1; // 광고 배너
    
    for (var group in groupedPosts) {
      totalItems += 1; // 날짜 헤더
      final groupPosts = group['posts'] as List<Post>;
      totalItems += groupPosts.length; // 게시글들
    }
    
    return totalItems;
  }

  Widget _buildAllTabItem(BuildContext context, bool isInitialLoading, bool hasError, List<Post> posts, int index) {
    // 첫 번째 아이템은 항상 광고 배너
    if (index == 0) {
      return AdBannerWidget(
        key: ValueKey('board_banner_all'),
        widgetId: 'board_banner_all',
      );
    }

    // 로딩 중
    if (isInitialLoading) {
      if (index <= 5) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: AppSkeletonList.cards(
            itemCount: 1,
            padding: EdgeInsets.zero,
          ),
        );
      }
      return const SizedBox.shrink();
    }

    // 에러 상태
    if (hasError) {
      if (index == 1) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: _buildErrorWidget('데이터를 불러올 수 없습니다'),
        );
      }
      return const SizedBox.shrink();
    }

    // 빈 상태
    if (posts.isEmpty) {
      if (index == 1) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 120),
          child: _isSearching
              ? AppEmptyState.noSearchResults(
                  context: context,
                  searchQuery: _searchController.text,
                  onClearSearch: _clearSearch,
                )
              : AppEmptyState.noPosts(
                  onCreatePost: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CreatePostScreen(
                          onPostCreated: () {
                            setState(() {});
                          },
                        ),
                      ),
                    );
                  },
                ),
        );
      }
      return const SizedBox.shrink();
    }

    // 그룹화된 게시글 표시
    return _buildGroupedPostItem(posts, index - 1);
  }

  Widget _buildGroupedPostItem(List<Post> posts, int adjustedIndex) {
    final groupedPosts = _groupPostsByDate(posts);
    int currentIndex = 0;
    
    for (var group in groupedPosts) {
      final dateLabel = group['dateLabel'] as String;
      final groupPosts = group['posts'] as List<Post>;
      
      // 날짜 헤더
      if (currentIndex == adjustedIndex) {
        return _buildDateHeader(dateLabel);
      }
      currentIndex++;
      
      // 게시글들
      for (int i = 0; i < groupPosts.length; i++) {
        if (currentIndex == adjustedIndex) {
          return OptimizedPostCard(
            key: ValueKey(groupPosts[i].id),
            post: groupPosts[i],
            index: i,
            onTap: () => _navigateToPostDetail(groupPosts[i]),
            preloadImage: i < 3,
          );
        }
        currentIndex++;
      }
    }
    
    return const SizedBox.shrink();
  }

  /// 게시글 상세 화면으로 이동
  void _navigateToPostDetail(Post post) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => PostDetailScreen(post: post)),
    );

    // 게시글이 삭제되었으면 목록 새로고침
    if (result == true) {
      setState(() {}); // Stream이므로 자동으로 갱신됨
    }
  }

  /// 에러 위젯 빌드
  Widget _buildErrorWidget(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            '오류가 발생했습니다',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {}); // 새로고침
            },
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }


  /// 날짜별로 게시글 그룹화
  List<Map<String, dynamic>> _groupPostsByDate(List<Post> posts) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
    
    final Map<String, List<Post>> groups = {
      'today': [],
      'yesterday': [],
      'thisWeek': [],
      'previous': [],
    };
    
    for (final post in posts) {
      final postDate = DateTime(
        post.createdAt.year,
        post.createdAt.month,
        post.createdAt.day,
      );
      
      if (postDate.isAtSameMomentAs(today)) {
        groups['today']!.add(post);
      } else if (postDate.isAtSameMomentAs(yesterday)) {
        groups['yesterday']!.add(post);
      } else if (postDate.isAfter(thisWeekStart.subtract(const Duration(days: 1))) && 
                 postDate.isBefore(yesterday)) {
        groups['thisWeek']!.add(post);
      } else {
        groups['previous']!.add(post);
      }
    }
    
    // 비어있지 않은 그룹만 반환
    return groups.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => {
              'dateLabel': entry.key,
              'posts': entry.value,
            })
        .toList();
  }

  /// 날짜 헤더 빌드
  Widget _buildDateHeader(String dateLabel) {
    // '오늘'은 표시하지 않음
    if (dateLabel == 'today') {
      return const SizedBox.shrink();
    }
    
    String displayLabel;
    
    switch (dateLabel) {
      case 'yesterday':
        displayLabel = AppLocalizations.of(context)?.yesterday ?? '어제';
        break;
      case 'thisWeek':
        displayLabel = AppLocalizations.of(context)?.thisWeek ?? '이번 주';
        break;
      default: // 'previous'
        displayLabel = AppLocalizations.of(context)?.previous ?? '이전';
    }
    
    // 테두리 없이 폰트로만 구분
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12), // 좌우 패딩 동일하게
      child: Center( // 가운데 정렬 ✨
        child: Text(
          displayLabel,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            color: Color(0xFF18181B), // 진한 검은색 (N-900)
            fontSize: 20, // 크게
            fontWeight: FontWeight.w800, // 매우 진하게
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }

  /// 전체 목록에서의 인덱스 찾기
  int _getGlobalIndex(List<Post> allPosts, Post targetPost) {
    return allPosts.indexWhere((post) => post.id == targetPost.id);
  }

}
