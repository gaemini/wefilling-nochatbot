// lib/screens/mypage_screen.dart
// 사용자 프로필 화면
// Instagram 스타일 후기 탭 추가
// 기존 기능 유지 + 새로운 탭 구조

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/user_stats_service.dart';
import '../services/review_service.dart';
import '../services/post_service.dart';
import '../services/relationship_service.dart';
import '../models/review_post.dart';
import '../models/post.dart';
import '../constants/app_constants.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../utils/country_flag_helper.dart';
import '../utils/logger.dart';
import '../widgets/country_flag_circle.dart';
import 'profile_edit_screen.dart';
import 'user_meetups_screens.dart';
import 'user_posts_screen.dart';
import 'notification_settings_screen.dart';
import 'account_settings_screen.dart';
import 'post_detail_screen.dart';
import 'login_screen.dart';
import 'review_detail_screen.dart';
import 'main_screen.dart';

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
                        icon: Icon(Icons.grid_on_rounded, size: 16),
                        text: AppLocalizations.of(context)!.reviews,
                        height: 48,
                      ),
                      Tab(
                        icon: Icon(Icons.bookmark_border_rounded, size: 16),
                        text: AppLocalizations.of(context)!.saved,
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
              _buildReviewGrid(),
              _buildSavedPosts(),
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
                      const SizedBox(height: 8),
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
              
              // 설정 아이콘 (오른쪽)
              IconButton(
                icon: const Icon(Icons.settings, color: Color(0xFF9CA3AF), size: 28),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  _showSettingsBottomSheet(context);
                },
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // 통계 정보 (3개 컬럼)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem(
                AppLocalizations.of(context)!.friends, 
                isFriends: true, 
                icon: Icons.people, 
                color: const Color(0xFF5865F2),
                onTap: () => _navigateToFriendsPage(),
              ),
              Container(width: 1, height: 50, color: const Color(0xFFE5E7EB)),
              _buildStatItem(
                AppLocalizations.of(context)!.joinedMeetups, 
                isJoined: true, 
                icon: Icons.groups, 
                color: const Color(0xFF5865F2),
                onTap: () => _navigateToUserMeetups(),
              ),
              Container(width: 1, height: 50, color: const Color(0xFFE5E7EB)),
              _buildStatItem(
                AppLocalizations.of(context)!.writtenPosts, 
                isPosts: true, 
                icon: Icons.article, 
                color: const Color(0xFF5865F2),
                onTap: () => _navigateToUserPosts(),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // 프로필 편집 버튼
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
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
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE5E7EB),
                foregroundColor: const Color(0xFF111827),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                AppLocalizations.of(context)!.profileEdit,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
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
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Color(0xFFF3F4F6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.photo_library_outlined,
                    size: 32,
                    color: Color(0xFF6366F1),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.noReviewsYet,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  AppLocalizations.of(context)!.joinMeetupAndWriteReview,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
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
              AppLocalizations.of(context)!.loginToViewSavedPosts,
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
      stream: _postService.getSavedPosts(),
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
        
        final savedPosts = snapshot.data ?? [];
        
        if (savedPosts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Color(0xFFF3F4F6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.bookmark_border_rounded,
                    size: 32,
                    color: Color(0xFF6366F1),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.noSavedPosts,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  AppLocalizations.of(context)!.saveInterestingPosts,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          );
        }
        
        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: savedPosts.length,
          itemBuilder: (context, index) {
            final post = savedPosts[index];
            return Container(
              margin: EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
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
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PostDetailScreen(post: post),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
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
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: post.imageUrls.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
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
                                  height: 1.4,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 4),
                              Text(
                                post.content,
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 14,
                                  color: Color(0xFF6B7280),
                                  height: 1.5,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 8),
                              Text(
                                '${post.author} • ${_getTimeAgo(post.createdAt)}',
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 12,
                                  color: Color(0xFF9CA3AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 북마크 아이콘
                        Icon(
                          Icons.bookmark,
                          color: Color(0xFF10B981),
                          size: 20,
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
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 8),
              StreamBuilder<int>(
                stream: isFriends
                    ? _relationshipService.getFriendCount()
                    : isJoined
                        ? _userStatsService.getJoinedMeetupCount()
                        : isPosts
                            ? _userStatsService.getUserPostCount()
                            : _userStatsService.getHostedMeetupCount(),
                builder: (context, snapshot) {
                  return Text(
                    '${snapshot.data ?? 0}',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
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
                // 내 게시글 메뉴 숨김 처리
                // _buildMenuItem(context, AppLocalizations.of(context)!.myPosts, Icons.article_rounded, () {
                //   Navigator.pop(context);
                // Navigator.push(
                //   context,
                //   MaterialPageRoute(
                //     builder: (context) => const UserPostsScreen(),
                //   ),
                // );
                // }),
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
    // 친구 탭으로 이동 (하단바 유지)
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const MainScreen(initialTabIndex: 4), // 친구 탭 인덱스
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

  void _navigateToUserPosts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const UserPostsScreen(),
      ),
    );
  }

  void _showLogoutConfirmDialog(BuildContext context, AuthProvider authProvider) {
    // 햅틱 피드백 - 중요한 액션임을 알림
    HapticFeedback.mediumImpact();
    
    showDialog(
      context: context,
      barrierDismissible: false, // 로딩 중에는 외부 터치로 닫기 방지
      builder: (BuildContext context) {
        return Consumer<AuthProvider>(
          builder: (context, authProvider, _) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Row(
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      color: BrandColors.error,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.logout ?? "",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                content: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.1),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: authProvider.isLoading 
                    ? Column(
                        key: const ValueKey('loading'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '로그아웃 중...',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        key: const ValueKey('confirm'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange.shade400,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            AppLocalizations.of(context)!.logoutConfirm ?? "",
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                ),
                actions: authProvider.isLoading 
                  ? [] // 로딩 중에는 버튼 숨김
                  : [
                      TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(context);
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.cancel ?? "",
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BrandColors.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 2,
                        ),
                        onPressed: () async {
                          // 강한 햅틱 피드백 - 중요한 액션 실행
                          HapticFeedback.heavyImpact();
                          
                          try {
                            // AuthProvider에서 로그아웃 처리 (타임아웃 포함)
                            await authProvider.signOut();
                            
                            // 로그아웃 완료 후 다이얼로그 닫고 로그인 화면으로 이동
                            if (context.mounted) {
                              Navigator.pop(context); // 다이얼로그 닫기
                              
                              // 성공 햅틱 피드백
                              HapticFeedback.lightImpact();
                              
                              // 부드러운 화면 전환 애니메이션
                              Navigator.of(context).pushAndRemoveUntil(
                                PageRouteBuilder(
                                  pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(showLogoutSuccess: true),
                                  transitionDuration: const Duration(milliseconds: 600),
                                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                    return FadeTransition(
                                      opacity: CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeInOut,
                                      ),
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0, 0.1),
                                          end: Offset.zero,
                                        ).animate(CurvedAnimation(
                                          parent: animation,
                                          curve: Curves.easeOutCubic,
                                        )),
                                        child: child,
                                      ),
                                    );
                                  },
                                ),
                                (route) => false,
                              );
                            }
                          } catch (e) {
                            Logger.error('UI 레이어 로그아웃 오류: $e');
                            // AuthProvider에서 이미 상태 초기화가 완료되므로 로그인 화면으로 이동
                            if (context.mounted) {
                              Navigator.pop(context); // 다이얼로그 닫기
                              Navigator.of(context).pushAndRemoveUntil(
                                PageRouteBuilder(
                                  pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(showLogoutSuccess: true),
                                  transitionDuration: const Duration(milliseconds: 600),
                                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    );
                                  },
                                ),
                                (route) => false,
                              );
                            }
                          }
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.logout_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              AppLocalizations.of(context)!.logout ?? "",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
              ),
            );
          },
        );
      },
    );
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