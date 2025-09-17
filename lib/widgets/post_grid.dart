// lib/widgets/post_grid.dart
// 포스트 그리드 컴포넌트
// 3열 그리드, 2dp gap, lazy loading, center-crop 썸네일
// 접근성 지원

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/profile_grid_adapter_service.dart';
import '../services/feature_flag_service.dart';

enum PostDisplayMode { grid, list, tagged }

class PostGrid extends StatefulWidget {
  final String userId;
  final PostDisplayMode displayMode;
  final Function(ProfilePost)? onPostTap;
  final bool isOwnProfile;

  const PostGrid({
    Key? key,
    required this.userId,
    this.displayMode = PostDisplayMode.grid,
    this.onPostTap,
    this.isOwnProfile = false,
  }) : super(key: key);

  @override
  State<PostGrid> createState() => _PostGridState();
}

class _PostGridState extends State<PostGrid> {
  final ProfileDataAdapter _profileAdapter = ProfileDataAdapter();
  final List<ProfilePost> _posts = [];
  final ScrollController _scrollController = ScrollController();
  
  DocumentSnapshot? _lastDocument;
  bool _isLoading = false;
  bool _hasMoreData = true;
  static const int _pageSize = 24;

  @override
  void initState() {
    super.initState();
    _loadInitialPosts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 초기 포스트 로드
  void _loadInitialPosts() {
    if (!FeatureFlagService().isFeatureEnabled(FeatureFlagService.FEATURE_PROFILE_GRID)) {
      return;
    }

    _profileAdapter.streamUserPosts(
      widget.userId,
      pageSize: _pageSize,
    ).listen((posts) {
      if (mounted) {
        setState(() {
          _posts.clear();
          _posts.addAll(posts);
          _hasMoreData = posts.length == _pageSize;
        });
      }
    });
  }

  /// 스크롤 이벤트 처리 (lazy loading)
  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMorePosts();
    }
  }

  /// 추가 포스트 로드
  Future<void> _loadMorePosts() async {
    if (_isLoading || !_hasMoreData) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 마지막 문서 기준으로 다음 페이지 로드
      // 실제 구현에서는 Firestore pagination 사용
      await Future.delayed(const Duration(milliseconds: 500)); // 시뮬레이션
      
      // 여기서는 더 이상 로드할 데이터가 없다고 가정
      setState(() {
        _hasMoreData = false;
      });
    } catch (e) {
      print('추가 포스트 로드 오류: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Feature Flag 체크
    if (!FeatureFlagService().isFeatureEnabled(FeatureFlagService.FEATURE_PROFILE_GRID)) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Text(
          '포스트 그리드 기능이 비활성화되어 있습니다.',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_posts.isEmpty && !_isLoading) {
      return _buildEmptyState();
    }

    switch (widget.displayMode) {
      case PostDisplayMode.grid:
        return _buildGridView();
      case PostDisplayMode.list:
        return _buildListView();
      case PostDisplayMode.tagged:
        return _buildTaggedView();
    }
  }

  /// 그리드 뷰 구성
  Widget _buildGridView() {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(1), // 외부 여백
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index < _posts.length) {
                  return _buildGridItem(_posts[index]);
                } else if (_isLoading) {
                  return _buildLoadingItem();
                } else {
                  return const SizedBox.shrink();
                }
              },
              childCount: _posts.length + (_isLoading ? 3 : 0), // 로딩 인디케이터 3개
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, // 3열
              crossAxisSpacing: 2, // 2dp gap
              mainAxisSpacing: 2, // 2dp gap
              childAspectRatio: 1, // 정사각형
            ),
          ),
        ),
      ],
    );
  }

  /// 개별 그리드 아이템 구성
  Widget _buildGridItem(ProfilePost post) {
    return GestureDetector(
      onTap: () => widget.onPostTap?.call(post),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 포스트 이미지 또는 텍스트 미리보기
            _buildPostThumbnail(post),
            
            // 포스트 타입 인디케이터
            if (post.type != 'image') _buildTypeIndicator(post),
            
            // 접근성을 위한 Semantics
            Semantics(
              label: '${post.type == 'image' ? '이미지' : '텍스트'} 포스트. ${post.text}',
              button: true,
              child: Container(),
            ),
          ],
        ),
      ),
    );
  }

  /// 포스트 썸네일 구성
  Widget _buildPostThumbnail(ProfilePost post) {
    if (post.coverPhotoUrl != null && post.coverPhotoUrl!.isNotEmpty) {
      // 이미지 포스트: center-crop으로 표시
      return CachedNetworkImage(
        imageUrl: post.coverPhotoUrl!,
        fit: BoxFit.cover, // center-crop
        placeholder: (context, url) => Container(
          color: Colors.grey[200],
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (context, url, error) => _buildTextThumbnail(post),
      );
    } else {
      // 텍스트 포스트: 텍스트 미리보기
      return _buildTextThumbnail(post);
    }
  }

  /// 텍스트 포스트 썸네일
  Widget _buildTextThumbnail(ProfilePost post) {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.grey[100],
      child: Center(
        child: Text(
          post.text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: Colors.grey[700],
          ),
        ),
      ),
    );
  }

  /// 포스트 타입 인디케이터
  Widget _buildTypeIndicator(ProfilePost post) {
    IconData icon;
    switch (post.type) {
      case 'meetup_review':
        icon = Icons.people;
        break;
      case 'text':
        icon = Icons.text_fields;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Positioned(
      top: 4,
      right: 4,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 12,
          color: Colors.white,
        ),
      ),
    );
  }

  /// 로딩 아이템
  Widget _buildLoadingItem() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  /// 리스트 뷰 구성 (미구현 - 기본 그리드로 대체)
  Widget _buildListView() {
    return _buildGridView();
  }

  /// 태그된 포스트 뷰 구성 (미구현 - 기본 그리드로 대체)
  Widget _buildTaggedView() {
    return _buildGridView();
  }

  /// 빈 상태 구성
  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 64,
            color: colorScheme.onSurface.withOpacity(0.3),
          ),
          
          const SizedBox(height: 16),
          
          Text(
            widget.isOwnProfile ? '첫 번째 포스트를 공유해보세요' : '아직 포스트가 없습니다',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          
          const SizedBox(height: 8),
          
          if (widget.isOwnProfile)
            Text(
              '사진이나 동영상을 공유하면 프로필에 표시됩니다.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.4),
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

/// 포스트 디스플레이 모드 토글 위젯
class PostDisplayModeToggle extends StatelessWidget {
  final PostDisplayMode currentMode;
  final Function(PostDisplayMode) onModeChanged;

  const PostDisplayModeToggle({
    Key? key,
    required this.currentMode,
    required this.onModeChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outline.withOpacity(0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildModeButton(
            context,
            PostDisplayMode.grid,
            Icons.grid_on,
            '그리드',
          ),
          _buildModeButton(
            context,
            PostDisplayMode.list,
            Icons.list,
            '리스트',
          ),
          _buildModeButton(
            context,
            PostDisplayMode.tagged,
            Icons.person_pin,
            '태그됨',
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(
    BuildContext context,
    PostDisplayMode mode,
    IconData icon,
    String label,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = currentMode == mode;

    return Expanded(
      child: GestureDetector(
        onTap: () => onModeChanged(mode),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            border: isSelected
                ? Border(
                    bottom: BorderSide(
                      color: colorScheme.primary,
                      width: 1,
                    ),
                  )
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected 
                    ? colorScheme.primary
                    : colorScheme.onSurface.withOpacity(0.6),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: isSelected 
                      ? colorScheme.primary
                      : colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
