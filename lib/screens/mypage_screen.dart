// lib/screens/mypage_screen.dart
// 사용자 프로필 화면
// Instagram 스타일 후기 탭 추가
// 기존 기능 유지 + 새로운 탭 구조

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/relationship_provider.dart';
import '../services/user_stats_service.dart';
import '../services/review_service.dart';
import '../services/post_service.dart';
import '../services/relationship_service.dart';
import '../models/review_post.dart';
import '../models/post.dart';
import '../constants/app_constants.dart';
import '../design/tokens.dart';
import '../ui/dialogs/logout_dialog.dart';
import '../l10n/app_localizations.dart';
import '../utils/country_flag_helper.dart';
import '../utils/logger.dart';
import '../widgets/country_flag_circle.dart';
import 'profile_edit_screen.dart';
import 'user_meetups_screens.dart';
import 'notification_settings_screen.dart';
import 'account_settings_screen.dart';
import 'post_detail_screen.dart';
import 'saved_posts_screen.dart';
import 'review_detail_screen.dart';
import 'friends_page.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({Key? key}) : super(key: key);

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> with SingleTickerProviderStateMixin {
  final UserStatsService _userStatsService = UserStatsService();
  final ReviewService _reviewService = ReviewService();
  final PostService _postService = PostService();
  final RelationshipService _relationshipService = RelationshipService();
  late TabController _tabController;
  // 통계 숫자(Posts/Friends/Reviews 등) 깜빡임 방지용 마지막 값 캐시
  final Map<String, int> _statCountCache = {};
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // ✅ 마이페이지에서도 친구요청 뱃지/상태가 즉시 갱신되도록 관계 스트림 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final authProvider = context.read<AuthProvider>();
        final relationshipProvider = context.read<RelationshipProvider>();
        relationshipProvider.setAuthProvider(authProvider);
        await relationshipProvider.initialize();
      } catch (_) {
        // 초기화 실패는 UI를 막지 않음 (배지는 0으로 표시됨)
      }
    });
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: SafeArea(
        top: true,
        bottom: true,
        child: NestedScrollView(
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            return <Widget>[
              SliverToBoxAdapter(
                child: _buildProfileHeader(),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFF646464),
                    unselectedLabelColor: Colors.grey[400],
                    indicatorColor: const Color(0xFF646464),
                    indicatorWeight: 2.5,
                    labelStyle: AppTheme.labelMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    tabs: [
                      Tab(
                        icon: Icon(Icons.article_outlined, size: 16),
                        text: AppLocalizations.of(context)!.posts,
                        height: 48,
                      ),
                      Tab(
                        icon: Icon(Icons.grid_on_rounded, size: 16),
                        text: AppLocalizations.of(context)!.reviews,
                        height: 48,
                      ),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildUserPosts(),
              _buildReviewGrid(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final userData = authProvider.userData;
    final nationality = userData?['nationality'];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        children: [
          // 프로필 사진(왼쪽) + 이름/국가(중앙) + 설정(오른쪽)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 프로필 사진
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE5E7EB),
                ),
                child: user?.photoURL != null
                    ? ClipOval(
                        child: Image.network(
                          user!.photoURL!,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.person,
                            size: 50,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.person,
                        size: 50,
                        color: Color(0xFF6B7280),
                      ),
              ),
              
              const SizedBox(width: 16),
              
              // 이름과 국가 정보 (중앙)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      userData?['nickname'] ?? AppLocalizations.of(context)!.user,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (nationality != null && nationality.isNotEmpty)
                      Row(
                        children: [
                          CountryFlagCircle(
                            nationality: nationality,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              CountryFlagHelper.getCountryInfo(nationality)
                                  ?.getLocalizedName(Localizations.localeOf(context).languageCode) 
                                  ?? nationality,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF6B7280),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    
                    // 한 줄 소개 (국기 아래)
                    if (userData?['bio'] != null && (userData!['bio'] as String).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        userData!['bio'],
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF111827),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.left,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              
            ],
          ),
          
          const SizedBox(height: 20),
          
          // 통계 정보 (3개 컬럼)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem(
                AppLocalizations.of(context)!.posts,
                isPosts: true,
                icon: Icons.article,
                color: AppColors.pointColor,
                showIcon: false,
                onTap: null,
              ),
              Container(width: 1, height: 50, color: const Color(0xFFE5E7EB)),
              Consumer<RelationshipProvider>(
                builder: (context, provider, _) {
                  return _buildStatItem(
                    AppLocalizations.of(context)!.friends,
                    isFriends: true,
                    icon: Icons.people,
                    color: AppColors.pointColor,
                    showIcon: false,
                    badgeCount: provider.incomingRequests.length,
                    onTap: () => _navigateToFriendsPage(),
                  );
                },
              ),
              Container(width: 1, height: 50, color: const Color(0xFFE5E7EB)),
              _buildStatItem(
                AppLocalizations.of(context)!.reviews,
                icon: Icons.grid_on_rounded,
                color: AppColors.pointColor,
                showIcon: false,
                countStream: _reviewService.getUserReviews().map((list) => list.length),
                onTap: null,
              ),
            ],
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
              color: Color(0xFF6366F1),
            ),
            SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.loginRequired,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.loginToViewReviews,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                color: Color(0xFF6B7280),
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
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
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
                  color: Color(0xFFEF4444),
                ),
                SizedBox(height: 16),
                Text(
                  '오류가 발생했습니다',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEF4444),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    color: Color(0xFF6B7280),
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
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Color(0xFFF3F4F6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.photo_library_outlined,
                    size: 48,
                    color: AppColors.pointColor,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  AppLocalizations.of(context)!.noReviewsYet,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.joinMeetupAndWriteReview,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          );
        }
        
        return GridView.builder(
          padding: EdgeInsets.all(4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
            childAspectRatio: 1,
          ),
          itemCount: reviews.length,
          itemBuilder: (context, index) {
            final review = reviews[index];
            return GestureDetector(
              onTap: () => _openReviewDetail(review),
              onLongPress: () => _showReviewOptions(review),
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
                    
                    // 숨김 표시 오버레이
                    if (review.hidden)
                      Container(
                        color: Colors.black54,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.visibility_off_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                              SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(context)!.hideReview,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
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
                    
                    // 좋아요 수 표시
                    if (review.likedBy.isNotEmpty && !review.hidden)
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
                    
                    // 메뉴 버튼
                    Positioned(
                      top: 4,
                      left: 4,
                      child: GestureDetector(
                        onTap: () => _showReviewOptions(review),
                        child: Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.more_vert,
                            color: Colors.white,
                            size: 16,
                          ),
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

  Widget _buildUserPosts() {
    // 실제 로그인된 사용자 ID 가져오기
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;
    
    // 로그인되지 않은 경우 로그인 유도 메시지 표시
    if (currentUserId == null || currentUserId.isEmpty) {
      final isKo = Localizations.localeOf(context).languageCode == 'ko';
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.login_rounded,
              size: 64,
              color: Color(0xFF6366F1),
            ),
            SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.loginRequired,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            SizedBox(height: 8),
            Text(
              isKo
                  ? '게시글을 보려면 로그인해주세요'
                  : 'Please login to view posts',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      );
    }
    
    return StreamBuilder<List<Post>>(
      stream: _userStatsService.getUserPosts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
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
                  color: Color(0xFFEF4444),
                ),
                SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.error,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEF4444),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          );
        }
        
        final posts = snapshot.data ?? [];
        
        if (posts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Color(0xFFF3F4F6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.article_outlined,
                    size: 48,
                    color: AppColors.pointColor,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  AppLocalizations.of(context)!.noWrittenPosts,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          );
        }
        
        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            return Container(
              margin: EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _openPostDetail(post.id);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 썸네일 또는 아이콘
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: post.imageUrls.isNotEmpty 
                                ? Colors.transparent 
                                : Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: post.imageUrls.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    post.imageUrls.first,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Color(0xFFF3F4F6),
                                        child: Icon(
                                          Icons.image_not_supported_outlined,
                                          color: Color(0xFF9CA3AF),
                                          size: 24,
                                        ),
                                      );
                                    },
                                  ),
                                )
                              : Icon(
                                  Icons.article_outlined,
                                  color: Color(0xFF6366F1),
                                  size: 28,
                                ),
                        ),
                        SizedBox(width: 12),
                        // 텍스트 정보
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                post.title,
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827),
                                  height: 1.25,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 4),
                              Text(
                                post.content,
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827),
                                  height: 1.35,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 8),
                              Row(
                                children: [
                              Text(
                                    post.getFormattedTime(context),
                                    style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 12,
                                  color: Color(0xFF9CA3AF),
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (post.likes > 0) ...[
                                    const Icon(
                                      Icons.favorite,
                                      size: 16,
                                      color: Color(0xFFEF4444),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${post.likes}',
                                      style: const TextStyle(
                                        fontFamily: 'Pretendard',
                                        color: Color(0xFF6B7280),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  if (post.commentCount > 0) ...[
                                    const Icon(
                                      Icons.chat_bubble_outline,
                                      size: 16,
                                      color: AppColors.pointColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${post.commentCount}',
                                      style: const TextStyle(
                                        fontFamily: 'Pretendard',
                                        color: Color(0xFF6B7280),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
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
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openPostDetail(String postId) async {
    try {
      final fetched = await _postService.getPostById(postId);
      if (!mounted) return;

      if (fetched == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.postNotFound ?? "")),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PostDetailScreen(post: fetched),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')),
      );
    }
  }
  
  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    final l10n = AppLocalizations.of(context);
    
    if (difference.inDays > 0) {
      return difference.inDays == 1 
        ? '1${l10n!.dayAgo}'
        : l10n!.daysAgoCount(difference.inDays);
    } else if (difference.inHours > 0) {
      return difference.inHours == 1
        ? '1${l10n!.hourAgo}'
        : l10n!.hoursAgoCount(difference.inHours);
    } else if (difference.inMinutes > 0) {
      return difference.inMinutes == 1
        ? '1${l10n!.minuteAgo}'
        : l10n!.minutesAgoCount(difference.inMinutes);
    } else {
      return l10n?.justNowTime ?? "";
    }
  }

  Widget _buildStatItem(
    String label, {
    bool isFriends = false,
    bool isJoined = false,
    bool isPosts = false,
    required IconData icon,
    required Color color,
    bool showIcon = true,
    Stream<int>? countStream,
    int badgeCount = 0,
    VoidCallback? onTap,
  }) {
    // 라벨/타입 기반으로 캐시 키 생성 (언어 변경에도 안정적으로 유지되도록 플래그 조합 사용)
    final cacheKey =
        'stat_${isFriends ? 'friends' : isJoined ? 'joined' : isPosts ? 'posts' : 'other'}_${showIcon ? 'icon' : 'noicon'}_${icon.codePoint}';

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showIcon) ...[
                Icon(icon, size: 24, color: color),
                const SizedBox(height: 8),
              ],
              StreamBuilder<int>(
                stream: countStream ??
                    (isFriends
                        ? _relationshipService.getFriendCount()
                        : isJoined
                            ? _userStatsService.getJoinedMeetupCount()
                            : isPosts
                                ? _userStatsService.getUserPostCount()
                                : _userStatsService.getHostedMeetupCount()),
                initialData: _statCountCache[cacheKey],
                builder: (context, snapshot) {
                  // 데이터 도착 전에는 0을 보여주지 말고(어색함), 캐시/플레이스홀더를 사용
                  final int? live = snapshot.data;
                  if (live != null) {
                    _statCountCache[cacheKey] = live;
                  }

                  final int? value = live ?? _statCountCache[cacheKey];
                  final Widget countWidget = value != null
                      ? Text(
                          '$value',
                          key: ValueKey<String>('count_$cacheKey:$value'),
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        )
                      : Text(
                          '—',
                          key: ValueKey<String>('count_$cacheKey:loading'),
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF9CA3AF),
                          ),
                        );

                  // 배지를 "영역 오른쪽 끝"이 아니라 "숫자" 기준으로 붙여 자연스럽게 보이도록
                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final fade =
                              FadeTransition(opacity: animation, child: child);
                          return ScaleTransition(
                            scale: Tween<double>(begin: 0.98, end: 1.0)
                                .animate(animation),
                            child: fade,
                          );
                        },
                        child: countWidget,
                      ),
                      if (badgeCount > 0)
                        Positioned(
                          top: -10,
                          right: -14,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 18,
                            ),
                            child: Text(
                              badgeCount > 99 ? '99+' : badgeCount.toString(),
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF6B7280),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openReviewDetail(ReviewPost review) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReviewDetailScreen(review: review),
      ),
    );
  }

  void _showReviewOptions(ReviewPost review) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DesignTokens.r16),
        ),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Container(
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
                
                // 숨김/표시 옵션만 제공 (삭제는 불가)
                _buildMenuItem(
                  context,
                  review.hidden 
                    ? (AppLocalizations.of(context)!.unhideReview ?? "") : AppLocalizations.of(context)!.hideReview,
                  review.hidden 
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                  () async {
                    Navigator.pop(context);
                    await _toggleReviewHidden(review);
                  },
                ),
                
                SizedBox(height: DesignTokens.s12),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleReviewHidden(ReviewPost review) async {
    final l10n = AppLocalizations.of(context);
    
    // 확인 다이얼로그
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          review.hidden ? l10n?.unhideReview ?? "" : l10n?.hideReview ?? "",
        ),
        content: Text(
          review.hidden 
            ? l10n?.unhideReviewConfirm ?? ""
            : l10n?.hideReviewConfirm ?? "",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n?.cancel ?? ""),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n?.confirm ?? ""),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 숨김/표시 처리
    final success = review.hidden
        ? await _reviewService.unhideReview(review.id)
        : await _reviewService.hideReview(review.id);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            review.hidden ? l10n?.reviewUnhidden ?? "" : l10n?.reviewHidden ?? "",
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            review.hidden ? l10n?.reviewUnhideFailed ?? "" : l10n?.reviewHideFailed ?? "",
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 후기 삭제 기능은 제거됨 (중복 등록 및 알림 문제 방지)
  // 후기는 수정만 가능하며, 숨김 처리로 프로필에서 제외 가능
  /*
  Future<void> _deleteReview(ReviewPost review) async {
    final l10n = AppLocalizations.of(context);
    
    // 확인 다이얼로그
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n?.delete ?? ""),
        content: Text(l10n?.deleteReviewConfirmMessage ?? ""),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n?.cancel ?? ""),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: BrandColors.error,
            ),
            child: Text(l10n?.delete ?? ""),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 삭제 처리
    final success = await _reviewService.deleteReview(review.id);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n?.deleteReviewSuccess ?? ""),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n?.deleteReviewFailed ?? ""),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  */

  void _showSettingsBottomSheet(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                // 프로필 편집 (화면 버튼 대신 설정 시트에서 제공)
                _buildMenuItem(
                  context,
                  AppLocalizations.of(context)!.profileEdit,
                  Icons.edit_rounded,
                  () {
                    Navigator.pop(context);
                    Navigator.push(
                      this.context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileEditScreen(),
                      ),
                    ).then((_) {
                      if (mounted) setState(() {});
                    });
                  },
                ),
                _buildMenuItem(
                  context,
                  Localizations.localeOf(context).languageCode == 'ko'
                      ? '저장된 게시글'
                      : 'Saved Posts',
                  Icons.bookmark_border_rounded,
                  () {
                    Navigator.pop(context);
                    Navigator.push(
                      this.context,
                      MaterialPageRoute(
                        builder: (context) => const SavedPostsScreen(),
                      ),
                    );
                  },
                ),
                // 내 모임 메뉴 숨김 처리
                // _buildMenuItem(context, AppLocalizations.of(context)!.myMeetups, Icons.group_rounded, () {
                //   Navigator.pop(context);
                // Navigator.push(
                //   context,
                //   MaterialPageRoute(
                //     builder: (context) => const UserMeetupsScreen(),
                //   ),
                // );
                // }),
                // 내 게시글 메뉴 숨김 처리 (기존 UserPostsScreen 페이지 제거됨)
                _buildMenuItem(context, AppLocalizations.of(context)!.notificationSettings, Icons.notifications_rounded, () {
                  Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationSettingsScreen(),
                  ),
                );
              }),
                _buildMenuItem(context, AppLocalizations.of(context)!.accountSettings, Icons.settings_rounded, () {
                  Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AccountSettingsScreen(),
                  ),
                );
              }),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  height: 1,
                  color: const Color(0xFFE5E7EB),
                ),
                _buildMenuItem(context, AppLocalizations.of(context)!.logout, Icons.logout_rounded, () async {
                  // 햅틱 피드백 - 중요한 액션임을 알림
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                  // 로그아웃 확인 다이얼로그 표시
                  _showLogoutConfirmDialog(context, authProvider);
                }, color: const Color(0xFFEF4444)),
                const SizedBox(height: 12),
              ],
            ),
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
    final isLogout = color != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        child: Row(
          children: [
            Icon(
              icon,
              color: color ?? const Color(0xFF111827),
              size: 24,
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: color ?? const Color(0xFF111827),
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right_rounded,
              color: const Color(0xFF9CA3AF),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  // 각 통계 항목 클릭 시 해당 페이지로 이동하는 메서드들
  void _navigateToFriendsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFFEBEBEB),
          appBar: AppBar(
            title: Text(AppLocalizations.of(context)!.friends),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            foregroundColor: const Color(0xFF111827),
            elevation: 0,
          ),
          body: const SafeArea(
            top: false,
            child: FriendsPage(),
          ),
        ),
      ),
    );
  }

  void _navigateToUserMeetups() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const UserMeetupsScreen(),
      ),
    );
  }


  void _showLogoutConfirmDialog(BuildContext context, AuthProvider authProvider) {
    showLogoutConfirmDialog(context, authProvider: authProvider);
  }
}

/// 마이페이지 설정 시트 (상단 앱바/내 프로필 어디서든 재사용 가능)
class MyPageSettingsSheet {
  static void show(
    BuildContext context, {
    VoidCallback? onProfileUpdated,
  }) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final rootContext = context;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                _menuItem(
                  sheetContext,
                  AppLocalizations.of(sheetContext)!.profileEdit,
                  Icons.edit_rounded,
                  () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      rootContext,
                      MaterialPageRoute(
                        builder: (_) => const ProfileEditScreen(),
                      ),
                    ).then((_) {
                      if (onProfileUpdated != null) onProfileUpdated();
                    });
                  },
                ),
                _menuItem(
                  sheetContext,
                  Localizations.localeOf(sheetContext).languageCode == 'ko'
                      ? '저장된 게시글'
                      : 'Saved Posts',
                  Icons.bookmark_border_rounded,
                  () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      rootContext,
                      MaterialPageRoute(builder: (_) => const SavedPostsScreen()),
                    );
                  },
                ),
                _menuItem(
                  sheetContext,
                  AppLocalizations.of(sheetContext)!.notificationSettings,
                  Icons.notifications_rounded,
                  () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      rootContext,
                      MaterialPageRoute(
                        builder: (_) => const NotificationSettingsScreen(),
                      ),
                    );
                  },
                ),
                _menuItem(
                  sheetContext,
                  AppLocalizations.of(sheetContext)!.accountSettings,
                  Icons.settings_rounded,
                  () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      rootContext,
                      MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
                    );
                  },
                ),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  height: 1,
                  color: const Color(0xFFE5E7EB),
                ),
                _menuItem(
                  sheetContext,
                  AppLocalizations.of(sheetContext)!.logout ?? "",
                  Icons.logout_rounded,
                  () async {
                    HapticFeedback.lightImpact();
                    Navigator.pop(sheetContext);
                    _showLogoutConfirmDialog(rootContext, authProvider);
                  },
                  color: const Color(0xFFEF4444),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _menuItem(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap, {
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        child: Row(
          children: [
            Icon(
              icon,
              color: color ?? const Color(0xFF111827),
              size: 24,
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: color ?? const Color(0xFF111827),
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF9CA3AF),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  static void _showLogoutConfirmDialog(
    BuildContext context,
    AuthProvider authProvider,
  ) {
    showLogoutConfirmDialog(context, authProvider: authProvider);
  }
}

// SliverPersistentHeader를 위한 Delegate 클래스
class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context, 
    double shrinkOffset, 
    bool overlapsContent,
  ) {
    return Container(
      color: AppTheme.backgroundSecondary,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}