// lib/screens/board_screen.dart
// 게시판 화면 - 게시글 목록 표시 및 관리
// 검색, 필터링, 작성 기능 포함

import 'dart:async';
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
  
  // AppLocalizations 안전 호출 헬퍼
  String _safeL10n(String Function(AppLocalizations) getter, String fallback) {
    try {
      final l10n = AppLocalizations.of(context);
      return l10n != null ? getter(l10n) : fallback;
    } catch (e) {
      return fallback;
    }
  }

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
        // 조기 반환: 로딩
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildTodayLoadingView();
        }
        
        // 조기 반환: 에러
        if (snapshot.hasError) {
          return _buildTodayErrorView();
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

        // 조기 반환: 빈 상태
        if (todayPosts.isEmpty) {
          return _buildTodayEmptyView();
        }

        // 게시글 목록 표시
        return _buildTodayPostsView(todayPosts);
      },
    );
  }
  
  // 로딩 뷰 (AdBanner + 스켈레톤)
  Widget _buildTodayLoadingView() {
    return RefreshIndicator(
      color: const Color(0xFF5865F2),
      backgroundColor: Colors.white,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          AdBannerWidget(
            key: ValueKey('board_banner_today'),
            widgetId: 'board_banner_today',
          ),
          ...List.generate(5, (index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _buildPostSkeleton(),
          )),
        ],
      ),
    );
  }
  
  // 에러 뷰 (AdBanner + 에러)
  Widget _buildTodayErrorView() {
    return RefreshIndicator(
      color: const Color(0xFF5865F2),
      backgroundColor: Colors.white,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          AdBannerWidget(
            key: ValueKey('board_banner_today'),
            widgetId: 'board_banner_today',
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildErrorWidget('데이터를 불러올 수 없습니다'),
          ),
        ],
      ),
    );
  }
  
  // 빈 상태 뷰 (AdBanner + Empty State)
  Widget _buildTodayEmptyView() {
    return RefreshIndicator(
      color: const Color(0xFF5865F2),
      backgroundColor: Colors.white,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          AdBannerWidget(
            key: ValueKey('board_banner_today'),
            widgetId: 'board_banner_today',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 120),
            child: AppEmptyState(
              icon: Icons.calendar_today,
              title: _safeL10n((l10n) => l10n.yourStoryMatters, '당신의 이야기가 중요합니다'),
              description: _safeL10n((l10n) => l10n.shareYourMoments, '순간을 공유해보세요'),
              illustration: const SizedBox.shrink(),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
  
  // 게시글 목록 뷰 (AdBanner + 게시글들)
  Widget _buildTodayPostsView(List<Post> todayPosts) {
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
        itemCount: todayPosts.length + 1, // AdBanner + 게시글들
        itemBuilder: (context, index) {
          // 첫 번째는 AdBanner
          if (index == 0) {
            return AdBannerWidget(
              key: ValueKey('board_banner_today'),
              widgetId: 'board_banner_today',
            );
          }
          
          // 게시글 표시
          final postIndex = index - 1;
          final post = todayPosts[postIndex];
          return OptimizedPostCard(
            key: ValueKey(post.id),
            post: post,
            index: postIndex,
            onTap: () => _navigateToPostDetail(post),
            preloadImage: postIndex < 3,
          );
        },
      ),
    );
  }


  /// 전체 게시글 탭
  Widget _buildAllPostsTab() {
    return StreamBuilder<List<Post>>(
      stream: _postService.getPostsStream(),
      builder: (context, snapshot) {
        // 조기 반환: 로딩
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildAllLoadingView();
        }
        
        // 조기 반환: 에러
        if (snapshot.hasError) {
          return _buildAllErrorView();
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

        // 조기 반환: 빈 상태
        if (posts.isEmpty) {
          return _buildAllEmptyView();
        }

        // 게시글 목록 표시
        return _buildAllPostsView(posts);
      },
    );
  }
  
  // 전체 탭 - 로딩 뷰
  Widget _buildAllLoadingView() {
    return RefreshIndicator(
      color: const Color(0xFF5865F2),
      backgroundColor: Colors.white,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          AdBannerWidget(
            key: ValueKey('board_banner_all'),
            widgetId: 'board_banner_all',
          ),
          ...List.generate(5, (index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _buildPostSkeleton(),
          )),
        ],
      ),
    );
  }
  
  // 전체 탭 - 에러 뷰
  Widget _buildAllErrorView() {
    return RefreshIndicator(
      color: const Color(0xFF5865F2),
      backgroundColor: Colors.white,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          AdBannerWidget(
            key: ValueKey('board_banner_all'),
            widgetId: 'board_banner_all',
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildErrorWidget('데이터를 불러올 수 없습니다'),
          ),
        ],
      ),
    );
  }
  
  // 전체 탭 - 빈 상태 뷰
  Widget _buildAllEmptyView() {
    return RefreshIndicator(
      color: const Color(0xFF5865F2),
      backgroundColor: Colors.white,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          AdBannerWidget(
            key: ValueKey('board_banner_all'),
            widgetId: 'board_banner_all',
          ),
          Padding(
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
          ),
        ],
      ),
    );
  }
  
  // 전체 탭 - 게시글 목록 뷰
  Widget _buildAllPostsView(List<Post> posts) {
    final groupedPosts = _groupPostsByDate(posts);
    
    return RefreshIndicator(
      color: const Color(0xFF5865F2),
      backgroundColor: Colors.white,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() {});
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _calculateAllItemCount(groupedPosts),
        itemBuilder: (context, index) {
          if (index == 0) {
            return AdBannerWidget(
              key: ValueKey('board_banner_all'),
              widgetId: 'board_banner_all',
            );
          }
          return _buildAllGroupedItem(groupedPosts, index - 1);
        },
      ),
    );
  }
  
  int _calculateAllItemCount(List<Map<String, dynamic>> groupedPosts) {
    int totalItems = 1; // AdBanner
    for (var group in groupedPosts) {
      totalItems += 1; // 날짜 헤더
      final groupPosts = group['posts'] as List<Post>;
      totalItems += groupPosts.length; // 게시글들
    }
    return totalItems;
  }
  
  Widget _buildAllGroupedItem(List<Map<String, dynamic>> groupedPosts, int adjustedIndex) {
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
        displayLabel = AppLocalizations.of(context)!.yesterday ?? '어제';
        break;
      case 'thisWeek':
        displayLabel = AppLocalizations.of(context)!.thisWeek ?? '이번 주';
        break;
      default: // 'previous'
        displayLabel = AppLocalizations.of(context)!.previous ?? '이전';
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

  /// 게시글 카드 스켈레톤 (로딩 시 표시)
  Widget _buildPostSkeleton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더: 작성자 정보
          Row(
            children: [
              AppSkeleton(
                width: 32,
                height: 32,
                borderRadius: BorderRadius.circular(16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeleton(
                      width: 100,
                      height: 14,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 4),
                    AppSkeleton(
                      width: 60,
                      height: 12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // 제목
          AppSkeleton(
            width: double.infinity,
            height: 18,
            borderRadius: BorderRadius.circular(4),
          ),
          
          const SizedBox(height: 8),
          
          // 내용 (2줄)
          AppSkeleton(
            width: double.infinity,
            height: 14,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 6),
          AppSkeleton(
            width: 200,
            height: 14,
            borderRadius: BorderRadius.circular(4),
          ),
          
          const SizedBox(height: 12),
          
          // 하단: 좋아요, 댓글 수
          Row(
            children: [
              AppSkeleton(
                width: 50,
                height: 12,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(width: 12),
              AppSkeleton(
                width: 50,
                height: 12,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ],
      ),
    );
  }

}
