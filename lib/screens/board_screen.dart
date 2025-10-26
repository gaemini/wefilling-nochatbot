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
    _tabController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
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
      backgroundColor: Colors.white,
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
              labelColor: Colors.blue[600],
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: Colors.blue[600],
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
          // 광고 배너 (고유 ID 부여로 완전히 독립적으로 작동)
          AdBannerWidget(
            key: ValueKey('board_banner'),
            widgetId: 'board_banner',
          ),
          // 게시글 목록
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return AppSkeletonList.cards(
            itemCount: 5,
            padding: const EdgeInsets.all(16),
          );
        }

        if (snapshot.hasError) {
          return _buildErrorWidget(snapshot.error.toString());
        }

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

        if (todayPosts.isEmpty) {
          return AppEmptyState(
            icon: Icons.calendar_today,
            title: AppLocalizations.of(context)!.yourStoryMatters,
            description: AppLocalizations.of(context)!.shareYourMoments,
            ctaText: AppLocalizations.of(context)!.writeStory,
            ctaIcon: Icons.edit,
            onCtaPressed: () {
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
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: todayPosts.length,
            itemBuilder: (context, index) {
              final post = todayPosts[index];
              return OptimizedPostCard(
                key: ValueKey(post.id),
                post: post,
                index: index,
                onTap: () => _navigateToPostDetail(post),
                preloadImage: index < 3,
              );
            },
          ),
        );
      },
    );
  }

  /// 전체 게시글 탭
  Widget _buildAllPostsTab() {
    return StreamBuilder<List<Post>>(
      stream: _postService.getPostsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return AppSkeletonList.cards(
            itemCount: 5,
            padding: const EdgeInsets.all(16),
          );
        }

        if (snapshot.hasError) {
          return _buildErrorWidget(snapshot.error.toString());
        }

        List<Post> posts = snapshot.data ?? [];

        // 검색 필터링
        if (_isSearching && _searchController.text.isNotEmpty) {
          final searchQuery = _searchController.text.toLowerCase();
          posts = posts.where((post) {
            return post.title.toLowerCase().contains(searchQuery) ||
                post.content.toLowerCase().contains(searchQuery);
          }).toList();
        }

        if (posts.isEmpty) {
          if (_isSearching) {
            return AppEmptyState.noSearchResults(
              context: context,
              searchQuery: _searchController.text,
              onClearSearch: _clearSearch,
            );
          } else {
            return AppEmptyState.noPosts(
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
            );
          }
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: _buildGroupedPostsList(posts),
        );
      },
    );
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

  /// 날짜별로 그룹화된 게시글 목록 빌드
  Widget _buildGroupedPostsList(List<Post> posts) {
    final groupedPosts = _groupPostsByDate(posts);
    
    return ListView.builder(
      itemCount: groupedPosts.length,
      itemBuilder: (context, groupIndex) {
        final group = groupedPosts[groupIndex];
        final dateLabel = group['dateLabel'] as String;
        final groupPosts = group['posts'] as List<Post>;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 날짜 헤더
            _buildDateHeader(dateLabel),
            
            // 해당 날짜의 게시글들
            ...groupPosts.asMap().entries.map((entry) {
              final index = entry.key;
              final post = entry.value;
              final globalIndex = _getGlobalIndex(posts, post);
              
              return OptimizedPostCard(
                key: ValueKey(post.id),
                post: post,
                index: globalIndex,
                onTap: () => _navigateToPostDetail(post),
                preloadImage: globalIndex < 3, // 상위 3개만 프리로드
              );
            }).toList(),
            
            // 그룹 간 여백
            if (groupIndex < groupedPosts.length - 1)
              const SizedBox(height: 8),
          ],
        );
      },
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
    String displayLabel;
    
    switch (dateLabel) {
      case 'today':
        displayLabel = AppLocalizations.of(context)!.today;
        break;
      case 'yesterday':
        displayLabel = AppLocalizations.of(context)!.yesterday;
        break;
      case 'thisWeek':
        displayLabel = AppLocalizations.of(context)!.thisWeek;
        break;
      default: // 'previous'
        displayLabel = AppLocalizations.of(context)!.previous;
    }
    
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.transparent, // 배경색 제거
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black, width: 1.5), // 진한 검은색 테두리
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 아이콘 제거
          Text(
            displayLabel,
            style: const TextStyle(
              color: Colors.black, // 진한 검은색 글씨
              fontSize: 14,
              fontWeight: FontWeight.w700, // 더 진하게
            ),
          ),
        ],
      ),
    );
  }

  /// 전체 목록에서의 인덱스 찾기
  int _getGlobalIndex(List<Post> allPosts, Post targetPost) {
    return allPosts.indexWhere((post) => post.id == targetPost.id);
  }

}
