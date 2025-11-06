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
import '../widgets/country_flag_circle.dart'; // 국기 위젯 추가
import '../l10n/app_localizations.dart';
import '../utils/country_flag_helper.dart';
import 'login_screen.dart';
import 'review_detail_screen.dart';

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
    // 화면 크기 가져오기 (다양한 기종 대응)
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final statusBarHeight = mediaQuery.padding.top;
    
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: SafeArea(
        top: true,
        bottom: true,
        child: Column(
          children: [
            _buildProfileHeader(),
            Container(
              color: AppTheme.backgroundSecondary,
              child: TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF646464), // 회색으로 변경
                unselectedLabelColor: Colors.grey[400],
                indicatorColor: const Color(0xFF646464), // 회색으로 변경
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
      ),
    );
  }

  Widget _buildProfileHeader() {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final userData = authProvider.userData;
    final nationality = userData?['nationality'];
    
    // 반응형 패딩 (화면 크기에 따라 조정)
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    
    // 작은 화면에서는 패딩을 더 줄임
    final verticalPadding = screenHeight < 700 ? 8.0 : 12.0;
    final horizontalPadding = 16.0;

    return Container(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        verticalPadding,
        horizontalPadding,
        verticalPadding,
      ),
      decoration: BoxDecoration(
        gradient: AppTheme.backgroundGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(DesignTokens.r16),
          bottomRight: Radius.circular(DesignTokens.r16),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: screenHeight < 700 ? 4 : 8),
              
              // 프로필 사진(왼쪽) + 이름/국가(오른쪽)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 프로필 이미지
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF646464), // 회색 톤
                        width: 3,
                      ),
                    ),
                    child: Container(
                      width: screenHeight < 700 ? 80 : 88,
                      height: screenHeight < 700 ? 80 : 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.backgroundPrimary,
                      ),
                      child: user?.photoURL != null
                          ? ClipOval(
                              child: Image.network(
                                user!.photoURL!,
                                width: screenHeight < 700 ? 80 : 88,
                                height: screenHeight < 700 ? 80 : 88,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.person,
                                  size: screenHeight < 700 ? 40 : 44,
                                  color: const Color(0xFF4A90E2), // 위필링 로고색
                                ),
                              ),
                            )
                          : Icon(
                              Icons.person,
                              size: screenHeight < 700 ? 40 : 44,
                              color: const Color(0xFF4A90E2), // 위필링 로고색
                            ),
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // 이름과 국가 정보 (오른쪽)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userData?['nickname'] ?? AppLocalizations.of(context)!.user,
                          style: AppTheme.headlineMedium.copyWith(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        if (nationality != null && nationality.isNotEmpty)
                          Row(
                            children: [
                              CountryFlagCircle(
                                nationality: nationality,
                                size: 26,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  CountryFlagHelper.getCountryInfo(nationality)
                                      ?.getLocalizedName(Localizations.localeOf(context).languageCode) 
                                      ?? nationality,
                                  style: AppTheme.bodyMedium.copyWith(
                                    color: Colors.black87,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        // 한 줄 소개 (프로필에서만 표시)
                        if (userData?['bio'] != null && (userData!['bio'] as String).isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            userData!['bio'],
                            style: AppTheme.bodyMedium.copyWith(
                              color: Colors.black87,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (userData?['university'] != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.school, size: 18, color: Colors.black54),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  userData!['university'],
                                  style: AppTheme.bodyMedium.copyWith(
                                    color: Colors.black54,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              
              SizedBox(height: screenHeight < 700 ? 10 : 14), // 간격 증가

              // 통계 정보 (원래 위치 - 카드 형태)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF646464), width: 1.5), // 회색 테두리
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: EdgeInsets.symmetric(
                  vertical: screenHeight < 700 ? 10 : 12,
                  horizontal: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(AppLocalizations.of(context)!.hostedMeetups, icon: Icons.event_available, color: const Color(0xFF646464)), // 회색 아이콘
                    Container(width: 1, height: screenHeight < 700 ? 32 : 36, color: const Color(0xFF646464)), // 회색 구분선
                    _buildStatItem(AppLocalizations.of(context)!.joinedMeetups, isJoined: true, icon: Icons.groups, color: const Color(0xFF646464)),
                    Container(width: 1, height: screenHeight < 700 ? 32 : 36, color: const Color(0xFF646464)),
                    _buildStatItem(AppLocalizations.of(context)!.writtenPosts, isPosts: true, icon: Icons.article, color: const Color(0xFF646464)),
                  ],
                ),
              ),

              SizedBox(height: screenHeight < 700 ? 8 : 12), // 반응형 간격

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
                    side: BorderSide(color: const Color(0xFF646464), width: 1.5), // 회색 테두리
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DesignTokens.r12),
                    ),
                    padding: EdgeInsets.symmetric(
                      vertical: screenHeight < 700 ? 8 : 10, // 반응형 패딩
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.profileEdit,
                    style: AppTheme.labelMedium.copyWith(
                      color: Colors.black, // 텍스트는 검은색 유지 (가독성)
                      fontWeight: FontWeight.bold,
                      fontSize: screenHeight < 700 ? 13 : 14, // 반응형 텍스트
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          // 설정 버튼 (오른쪽 상단 절대 위치)
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              onPressed: () {
                _showSettingsBottomSheet(context);
              },
              icon: Icon(
                Icons.settings_rounded,
                color: Colors.black87,
                size: 22,
              ),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(),
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
              AppLocalizations.of(context)!.loginRequired,
              style: AppTheme.headlineMedium.copyWith(
                color: AppTheme.primary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.loginToViewReviews,
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
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.photo_library_outlined,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.noReviewsYet,
                  style: AppTheme.headlineMedium.copyWith(
                    color: AppTheme.primary,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  AppLocalizations.of(context)!.joinMeetupAndWriteReview,
                  style: AppTheme.bodyMedium.copyWith(
                    color: Colors.grey[600],
                    fontSize: 13,
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
              color: AppTheme.primary,
            ),
            SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.loginRequired,
              style: AppTheme.headlineMedium.copyWith(
                color: AppTheme.primary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.loginToViewSavedPosts,
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
                  AppLocalizations.of(context)!.error,
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
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: AppTheme.secondaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.bookmark_border_rounded,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.noSavedPosts,
                  style: AppTheme.headlineMedium.copyWith(
                    color: AppTheme.primary,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  AppLocalizations.of(context)!.saveInterestingPosts,
                  style: AppTheme.bodyMedium.copyWith(
                    color: Colors.grey[600],
                    fontSize: 13,
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
    bool isJoined = false,
    bool isPosts = false,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: color), // 22 → 20
          const SizedBox(height: 6), // 8 → 6
          StreamBuilder<int>(
            stream: isJoined
                ? _userStatsService.getJoinedMeetupCount()
                : isPosts
                    ? _userStatsService.getUserPostCount()
                    : _userStatsService.getHostedMeetupCount(),
            builder: (context, snapshot) {
              return Text(
                '${snapshot.data ?? 0}',
                style: AppTheme.headlineMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 22, // 24 → 22
                ),
              );
            },
          ),
          const SizedBox(height: 3), // 4 → 3
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              color: Colors.black,
              fontSize: 10, // 11 → 10
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
                _buildMenuItem(context, AppLocalizations.of(context)!.myMeetups, Icons.group_rounded, () {
                  Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const UserMeetupsScreen(),
                  ),
                );
              }),
                _buildMenuItem(context, AppLocalizations.of(context)!.myPosts, Icons.article_rounded, () {
                  Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const UserPostsScreen(),
                  ),
                );
              }),
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
                Divider(color: Colors.grey[300]),
                _buildMenuItem(context, AppLocalizations.of(context)!.logout, Icons.logout_rounded, () async {
                  Navigator.pop(context);
                  // 로그아웃 확인 다이얼로그 표시
                  _showLogoutConfirmDialog(context, authProvider);
                }, color: BrandColors.error),
                SizedBox(height: DesignTokens.s12),
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

  void _showLogoutConfirmDialog(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.logout ?? ""),
          content: Text(AppLocalizations.of(context)!.logoutConfirm ?? ""),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.cancel ?? ""),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: BrandColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(context);
                
                // 로딩 인디케이터 표시
                if (context.mounted) {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                
                try {
                  await authProvider.signOut();
                  
                  // 로딩 다이얼로그 닫기 후 로그인 화면으로 이동(스택 초기화)
                  if (context.mounted) {
                    Navigator.pop(context);
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  }
                } catch (e) {
                  // 로딩 다이얼로그 닫기
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context)!.logoutError ?? ""),
                        backgroundColor: BrandColors.error,
                        duration: const Duration(seconds: 3),
                        action: SnackBarAction(
                          label: AppLocalizations.of(context)!.retry,
                          textColor: Colors.white,
                          onPressed: () {
                            // 재시도 로직
                            _showLogoutConfirmDialog(context, authProvider);
                          },
                        ),
                      ),
                    );
                  }
                  print('로그아웃 UI 오류: $e');
                }
              },
              child: Text(AppLocalizations.of(context)!.logout ?? ""),
            ),
          ],
        );
      },
    );
  }
}