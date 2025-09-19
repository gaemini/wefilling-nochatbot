// lib/screens/mypage_screen.dart
// 사용자 프로필 화면
// Instagram 스타일 후기 탭 추가
// 기존 기능 유지 + 새로운 탭 구조

import 'package:flutter/material.dart';
import 'profile_edit_screen.dart';
import 'user_meetups_screens.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/user_stats_service.dart';
import 'user_posts_screen.dart';
import 'notification_settings_screen.dart';
import 'account_settings_screen.dart';
import '../services/review_service.dart';
import '../models/review_post.dart';
import '../constants/app_constants.dart';
import '../design/tokens.dart';
import '../services/post_service.dart';
import '../models/post.dart';
import '../screens/post_detail_screen.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({Key? key}) : super(key: key);

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> with SingleTickerProviderStateMixin {
  final UserStatsService _userStatsService = UserStatsService();
  final ReviewService _reviewService = ReviewService();
  final PostService _postService = PostService();
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '내 정보',
          style: AppTheme.headlineMedium.copyWith(
            color: AppTheme.primary,
          ),
        ),
        backgroundColor: AppTheme.backgroundPrimary,
        foregroundColor: AppTheme.primary,
        elevation: 0,
      ),
      backgroundColor: AppTheme.backgroundPrimary,
      body: Column(
        children: [
          _buildProfileHeader(),
          Container(
            color: AppTheme.backgroundSecondary,
            child: TabBar(
              controller: _tabController,
              labelColor: AppTheme.primary,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppTheme.primary,
              indicatorWeight: 3,
              labelStyle: AppTheme.labelMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
              tabs: [
                Tab(
                  icon: Icon(Icons.grid_on_rounded),
                  text: '후기',
                ),
                Tab(
                  icon: Icon(Icons.bookmark_border_rounded),
                  text: '저장됨',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildReviewGrid(),
                _buildSavedPosts(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final userData = authProvider.userData;

    return Container(
              padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        gradient: AppTheme.backgroundGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(DesignTokens.r16),
          bottomRight: Radius.circular(DesignTokens.r16),
        ),
      ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 프로필 이미지
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.primaryGradient,
                ),
                padding: EdgeInsets.all(3),
                child: CircleAvatar(
                        radius: 40,
                  backgroundColor: AppTheme.backgroundPrimary,
                        backgroundImage:
                            user?.photoURL != null
                                ? NetworkImage(user!.photoURL!)
                                : null,
                        child:
                            user?.photoURL == null
                                ? Text(
                                  userData?['nickname']?.substring(0, 1) ?? 'U',
                            style: AppTheme.headlineLarge.copyWith(
                              color: AppTheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                                : null,
                ),
                      ),
                      const SizedBox(width: 16),

                      // 사용자 정보
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userData?['nickname'] ?? '사용자',
                      style: AppTheme.headlineMedium.copyWith(
                        color: AppTheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user?.email ?? '',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.primary.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (userData?['university'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: AppTheme.secondaryGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          userData!['university'],
                          style: AppTheme.labelSmall.copyWith(
                            color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                        ),
                      ),
                    ],
                  ),
              ),

              // 설정 버튼
              IconButton(
                    onPressed: () {
                  _showSettingsBottomSheet(context);
                },
                icon: Icon(
                  Icons.settings_rounded,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 활동 통계
          Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // 주최한 모임 통계
                  StreamBuilder<int>(
                    stream: _userStatsService.getHostedMeetupCount(),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      return _buildStatDisplay('주최한 모임', count.toString());
                    },
                  ),

                  // 참여했던 모임 통계
                  StreamBuilder<int>(
                    stream: _userStatsService.getJoinedMeetupCount(),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                  return _buildStatDisplay('참여한 모임', count.toString());
                    },
                  ),

              // 작성한 게시글 통계
              _buildStatDisplay('작성한 글', '0'), // TODO: getPostCount 메서드 구현 후 StreamBuilder로 변경
            ],
          ),

          const SizedBox(height: 16),

          // 프로필 편집 버튼
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileEditScreen(),
                  ),
                ).then((_) {
                  setState(() {});
                });
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.primary.withOpacity(0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.r12),
                ),
                padding: EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                '프로필 편집',
                style: AppTheme.labelMedium.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewGrid() {
    // 실제 로그인된 사용자 ID 가져오기
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;
    
    // 로그인되지 않은 경우 로그인 유도 메시지 표시
    if (currentUserId == null || currentUserId.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.login_rounded,
              size: 64,
              color: AppTheme.primary,
            ),
            SizedBox(height: 16),
            Text(
              '로그인이 필요합니다',
              style: AppTheme.headlineMedium.copyWith(
                color: AppTheme.primary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '후기를 보려면 로그인해주세요',
              style: AppTheme.bodyMedium.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }
    
    return StreamBuilder<List<ReviewPost>>(
      stream: _reviewService.getUserReviews(),
                    builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          );
        }
        
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 64,
                  color: AppTheme.accentRed,
                ),
                SizedBox(height: 16),
                Text(
                  '오류가 발생했습니다',
                  style: AppTheme.headlineMedium.copyWith(
                    color: AppTheme.accentRed,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: AppTheme.bodySmall.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }
        
        final reviews = snapshot.data ?? [];
        
        if (reviews.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.photo_library_outlined,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  '아직 작성한 후기가 없습니다',
                  style: AppTheme.headlineMedium.copyWith(
                    color: AppTheme.primary,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '모임에 참여하고 후기를 작성해보세요!',
                  style: AppTheme.bodyMedium.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    // TODO: 모임 둘러보기 화면으로 이동
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(
                    '모임 둘러보기',
                    style: AppTheme.labelMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        
        return GridView.builder(
          padding: EdgeInsets.all(2),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: reviews.length,
          itemBuilder: (context, index) {
            final review = reviews[index];
            return GestureDetector(
              onTap: () => _openReviewDetail(review),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.backgroundSecondary,
                  image: review.imageUrls.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(review.imageUrls.first),
                        fit: BoxFit.cover,
                      )
                    : null,
                ),
                child: Stack(
                  children: [
                    // 이미지가 없을 때 플레이스홀더
                    if (review.imageUrls.isEmpty)
                      Center(
                        child: Icon(
                          Icons.image_not_supported_rounded,
                          color: Colors.grey[400],
                          size: 32,
                        ),
                      ),
                    
                    // 다중 이미지 표시
                    if (review.imageUrls.length > 1)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.collections_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    
                    // 평점 표시
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              color: AppTheme.accentAmber,
                              size: 12,
                            ),
                            SizedBox(width: 2),
                            Text(
                              '${review.rating}',
                              style: AppTheme.labelSmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // 좋아요 수 표시
                    if (review.likedBy.isNotEmpty)
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.favorite_rounded,
                                color: AppTheme.accentRed,
                                size: 12,
                              ),
                              SizedBox(width: 2),
                              Text(
                                '${review.likedBy.length}',
                                style: AppTheme.labelSmall.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSavedPosts() {
    // 실제 로그인된 사용자 ID 가져오기
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;
    
    // 로그인되지 않은 경우 로그인 유도 메시지 표시
    if (currentUserId == null || currentUserId.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.login_rounded,
              size: 64,
              color: AppTheme.primary,
            ),
            SizedBox(height: 16),
            Text(
              '로그인이 필요합니다',
              style: AppTheme.headlineMedium.copyWith(
                color: AppTheme.primary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '저장된 게시물을 보려면 로그인해주세요',
              style: AppTheme.bodyMedium.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }
    
    return StreamBuilder<List<Post>>(
      stream: _postService.getSavedPosts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          );
        }
        
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 64,
                  color: AppTheme.accentRed,
                ),
                SizedBox(height: 16),
                Text(
                  '오류가 발생했습니다',
                  style: AppTheme.headlineMedium.copyWith(
                    color: AppTheme.accentRed,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: AppTheme.bodySmall.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }
        
        final savedPosts = snapshot.data ?? [];
        
        if (savedPosts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: AppTheme.secondaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.bookmark_border_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  '저장된 게시물이 없습니다',
                  style: AppTheme.headlineMedium.copyWith(
                    color: AppTheme.primary,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '관심 있는 게시물을 저장해보세요',
                  style: AppTheme.bodyMedium.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }
        
        return ListView.builder(
          padding: EdgeInsets.all(DesignTokens.s8),
          itemCount: savedPosts.length,
          itemBuilder: (context, index) {
            final post = savedPosts[index];
            return Card(
              margin: EdgeInsets.only(bottom: DesignTokens.s8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignTokens.r12),
              ),
              child: ListTile(
                leading: post.imageUrls.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          post.imageUrls.first,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 60,
                              height: 60,
                              color: Colors.grey[300],
                              child: Icon(Icons.image_not_supported),
                            );
                          },
                        ),
                      )
                    : Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.article_rounded,
                          color: AppTheme.primary,
                        ),
                      ),
                title: Text(
                  post.title,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.content,
                      style: AppTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${post.author} • ${_getTimeAgo(post.createdAt)}',
                      style: AppTheme.labelSmall.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                trailing: Icon(
                  Icons.bookmark_rounded,
                  color: AppTheme.accentEmerald,
                ),
                onTap: () {
                  // 게시물 상세 화면으로 이동
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PostDetailScreen(post: post),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
  
  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }

  Widget _buildStatDisplay(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: AppTheme.headlineMedium.copyWith(
            color: AppTheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.primary.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  void _openReviewDetail(ReviewPost review) {
    // 후기 상세 페이지로 이동하는 기능 (현재는 비활성화)
    // TODO: 후기 상세 페이지 구현 시 Navigator.push 추가
  }

  void _showSettingsBottomSheet(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DesignTokens.r16),
        ),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(DesignTokens.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: DesignTokens.s16),
              _buildMenuItem(context, '내 모임', Icons.group_rounded, () {
                Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const UserMeetupsScreen(),
                ),
              );
            }),
              _buildMenuItem(context, '내 게시글', Icons.article_rounded, () {
                Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const UserPostsScreen(),
                ),
              );
            }),
              _buildMenuItem(context, '알림 설정', Icons.notifications_rounded, () {
                Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationSettingsScreen(),
                ),
              );
            }),
              _buildMenuItem(context, '계정 설정', Icons.settings_rounded, () {
                Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AccountSettingsScreen(),
                ),
              );
            }),
              Divider(color: Colors.grey[300]),
              _buildMenuItem(context, '로그아웃', Icons.logout_rounded, () async {
                Navigator.pop(context);
              await authProvider.signOut();
              }, color: AppTheme.accentRed),
              SizedBox(height: DesignTokens.s12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap, {
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.r12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(
              icon,
              color: color ?? AppTheme.primary,
              size: 24,
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: AppTheme.bodyMedium.copyWith(
                color: color ?? AppTheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey[400],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}