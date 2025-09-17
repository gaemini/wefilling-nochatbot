// lib/screens/board_screen.dart
// 게시판 화면 - 게시글 목록 표시 및 관리
// 검색, 필터링, 작성 기능 포함

import 'package:flutter/material.dart';
import '../models/post.dart';
import '../services/post_service.dart';
import '../widgets/country_flag_circle.dart';
import '../ui/widgets/app_fab.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/skeletons.dart';
import '../ui/widgets/optimized_list.dart';
import '../ui/widgets/optimized_post_card.dart';
import '../utils/image_utils.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';

import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../ui/widgets/app_icon_button.dart';

class BoardScreen extends StatefulWidget {
  final String? searchQuery;
  
  const BoardScreen({super.key, this.searchQuery});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  final PostService _postService = PostService();
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    // 외부에서 전달된 검색어가 있으면 설정
    if (widget.searchQuery != null && widget.searchQuery!.isNotEmpty) {
      _searchController.text = widget.searchQuery!;
      _isSearching = true;
    }
  }

  @override
  void dispose() {
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
          // 게시글 목록
          Expanded(
            child: StreamBuilder<List<Post>>(
              stream: _postService.getPostsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return AppSkeletonList.cards(
                    itemCount: 5,
                    padding: const EdgeInsets.all(16),
                  );
                }

                if (snapshot.hasError) {
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
                          '${snapshot.error}',
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

                List<Post> posts = snapshot.data ?? [];

                // 검색 필터링
                if (_isSearching && _searchController.text.isNotEmpty) {
                  final searchQuery = _searchController.text.toLowerCase();
                  posts =
                      posts.where((post) {
                        return post.title.toLowerCase().contains(searchQuery) ||
                            post.content.toLowerCase().contains(searchQuery);
                      }).toList();
                }

                if (posts.isEmpty) {
                  if (_isSearching) {
                    return AppEmptyState.noSearchResults(
                      searchQuery: _searchController.text,
                      onClearSearch: _clearSearch,
                    );
                  } else {
                    return AppEmptyState.noPosts(
                      onCreatePost: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => CreatePostScreen(
                                  onPostCreated: () {
                                    setState(() {}); // 새로고침
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
                    setState(() {}); // 새로고침 효과
                  },
                  child: ListView.builder(
                    itemCount: posts.length,
                    itemBuilder: (context, index) {
                      final post = posts[index];
                      return OptimizedPostCard(
                        key: ValueKey(post.id),
                        post: post,
                        index: index,
                        onTap: () => _navigateToPostDetail(post),
                        preloadImage: index < 3, // 상위 3개만 프리로드
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: AppFab.extended(
        icon: Icons.edit,
        label: '글쓰기',
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
        semanticLabel: '새 글 작성하기',
        heroTag: 'board_write_fab',
      ),
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

}
