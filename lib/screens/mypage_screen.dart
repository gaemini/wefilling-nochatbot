// lib/screens/mypage_screen.dart
// 사용자 프로필 화면
// Instagram 스타일 후기 탭 추가
// 기존 기능 유지 + 새로운 탭 구조

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/relationship_provider.dart';
import '../services/user_stats_service.dart';
import '../services/review_service.dart';
import '../services/post_service.dart';
import '../services/relationship_service.dart';
import '../services/cache/app_image_cache_manager.dart';
import '../services/cache/my_page_cache_service.dart';
import '../models/review_post.dart';
import '../models/post.dart';
import '../models/social_profile_data.dart';
import '../constants/app_constants.dart';
import '../design/tokens.dart';
import '../ui/dialogs/logout_dialog.dart';
import '../l10n/app_localizations.dart';
import '../utils/country_flag_helper.dart';
import '../widgets/country_flag_circle.dart';
import 'profile_edit_screen.dart';
import 'user_meetups_screens.dart';
import 'notification_settings_screen.dart';
import 'account_settings_screen.dart';
import 'post_detail_screen.dart';
import 'saved_posts_screen.dart';
import 'review_detail_screen.dart';
import 'friends_page.dart';
import 'social_tag_people_screen.dart';
import 'semester_todo_admin_screen.dart';
import '../ui/widgets/profile_image_viewer.dart';
import '../utils/profile_photo_policy.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({Key? key}) : super(key: key);

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen>
    with SingleTickerProviderStateMixin {
  final UserStatsService _userStatsService = UserStatsService();
  final ReviewService _reviewService = ReviewService();
  final PostService _postService = PostService();
  final RelationshipService _relationshipService = RelationshipService();
  final MyPageCacheService _myPageCacheService = MyPageCacheService();
  late TabController _tabController;
  bool _showPostsAsGrid = false;
  // 통계 숫자(Posts/Friends/Reviews 등) 깜빡임 방지용 마지막 값 캐시
  final Map<String, int> _statCountCache = {};

  String? _myPageCacheUserId;
  int _myPageLoadToken = 0;
  List<Post>? _userPosts;
  List<ReviewPost>? _userReviews;
  List<Post>? _savedPosts;
  Stream<int>? _friendCountStream;
  bool _isLoadingUserPosts = true;
  bool _isLoadingReviews = true;
  bool _isLoadingSavedPosts = true;
  Object? _userPostsError;
  Object? _reviewsError;
  Object? _savedPostsError;
  StreamSubscription<List<Post>>? _savedPostsSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.read<AuthProvider>().user?.uid;
    if (_myPageCacheUserId == userId) return;

    _myPageCacheUserId = userId;
    final loadToken = ++_myPageLoadToken;
    unawaited(_savedPostsSubscription?.cancel());
    _savedPostsSubscription = null;
    _friendCountStream = userId == null
        ? Stream<int>.value(0)
        : _relationshipService.getFriendCount();
    _userPosts = null;
    _userReviews = null;
    _savedPosts = null;
    _userPostsError = null;
    _reviewsError = null;
    _savedPostsError = null;
    _isLoadingUserPosts = userId != null;
    _isLoadingReviews = userId != null;
    _isLoadingSavedPosts = userId != null;

    if (userId != null && userId.isNotEmpty) {
      _loadMyPageTabs(userId, loadToken);
    }
  }

  bool _isCurrentLoad(String userId, int loadToken) {
    return mounted &&
        _myPageCacheUserId == userId &&
        _myPageLoadToken == loadToken;
  }

  void _loadMyPageTabs(String userId, int loadToken) {
    _loadUserPosts(userId, loadToken);
    _loadUserReviews(userId, loadToken);
    _loadSavedPosts(userId, loadToken);
  }

  Future<void> _loadUserPosts(String userId, int loadToken) async {
    final cached = await _myPageCacheService.readUserPosts(userId);
    if (!_isCurrentLoad(userId, loadToken)) return;

    setState(() {
      if (cached != null) _userPosts = cached.items;
      _isLoadingUserPosts = cached == null;
    });
    if (cached?.isFresh == true) return;

    try {
      final posts = await _userStatsService
          .getUserPosts()
          .first
          .timeout(const Duration(seconds: 20));
      if (!_isCurrentLoad(userId, loadToken)) return;
      await _myPageCacheService.saveUserPosts(userId, posts);
      if (!_isCurrentLoad(userId, loadToken)) return;
      setState(() {
        _userPosts = posts;
        _isLoadingUserPosts = false;
        _userPostsError = null;
      });
    } catch (error) {
      if (!_isCurrentLoad(userId, loadToken)) return;
      setState(() {
        _isLoadingUserPosts = false;
        if (_userPosts == null) _userPostsError = error;
      });
    }
  }

  Future<void> _loadUserReviews(String userId, int loadToken) async {
    final cached = await _myPageCacheService.readReviews(userId);
    if (!_isCurrentLoad(userId, loadToken)) return;

    setState(() {
      if (cached != null) _userReviews = cached.items;
      _isLoadingReviews = cached == null;
    });
    try {
      final reviews = await _reviewService
          .getUserReviews()
          .first
          .timeout(const Duration(seconds: 20));
      if (!_isCurrentLoad(userId, loadToken)) return;
      await _myPageCacheService.saveReviews(userId, reviews);
      if (!_isCurrentLoad(userId, loadToken)) return;
      setState(() {
        _userReviews = reviews;
        _isLoadingReviews = false;
        _reviewsError = null;
      });
    } catch (error) {
      if (!_isCurrentLoad(userId, loadToken)) return;
      setState(() {
        _isLoadingReviews = false;
        if (_userReviews == null) _reviewsError = error;
      });
    }
  }

  Future<void> _loadSavedPosts(String userId, int loadToken) async {
    final cached = await _myPageCacheService.readSavedPosts(userId);
    if (!_isCurrentLoad(userId, loadToken)) return;

    setState(() {
      if (cached != null) _savedPosts = cached.items;
      _isLoadingSavedPosts = cached == null;
    });

    // 저장 글은 다른 화면에서 언제든 추가/해제될 수 있다. 캐시는 초기
    // 화면에만 즉시 사용하고, freshness와 관계없이 Firestore 스트림을
    // 유지해야 마이페이지 탭도 같은 순간에 갱신된다.
    await _savedPostsSubscription?.cancel();
    if (!_isCurrentLoad(userId, loadToken)) return;
    _savedPostsSubscription = _postService.getSavedPosts().listen(
      (posts) async {
        if (!_isCurrentLoad(userId, loadToken)) return;
        setState(() {
          _savedPosts = posts;
          _isLoadingSavedPosts = false;
          _savedPostsError = null;
        });
        await _myPageCacheService.saveSavedPosts(userId, posts);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_isCurrentLoad(userId, loadToken)) return;
        setState(() {
          _isLoadingSavedPosts = false;
          if (_savedPosts == null) _savedPostsError = error;
        });
      },
    );
  }

  @override
  void dispose() {
    unawaited(_savedPostsSubscription?.cancel());
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
            final isKorean =
                Localizations.localeOf(context).languageCode == 'ko';
            final postsLabel = AppLocalizations.of(context)!.posts;
            final reviewsLabel = isKorean ? '모임 후기' : 'Meetup Reviews';
            final savedPostsLabel = isKorean ? '저장한 글' : 'Saved Posts';

            return <Widget>[
              SliverToBoxAdapter(
                child: _buildProfileHeader(),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFF111827),
                    unselectedLabelColor: const Color(0xFF9CA3AF),
                    indicatorColor: AppColors.pointColor,
                    indicatorWeight: 2,
                    dividerColor: const Color(0xFFF1F3F5),
                    labelStyle: AppTheme.labelMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    unselectedLabelStyle: AppTheme.labelMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    tabs: [
                      _buildProfileTab(
                        postsLabel,
                        sizingLabel: reviewsLabel,
                      ),
                      _buildProfileTab(
                        reviewsLabel,
                        sizingLabel: reviewsLabel,
                      ),
                      _buildProfileTab(
                        savedPostsLabel,
                        sizingLabel: reviewsLabel,
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
              _KeepAliveTab(
                key: const PageStorageKey('mypage_posts_tab'),
                child: _buildUserPosts(),
              ),
              _KeepAliveTab(
                key: const PageStorageKey('mypage_reviews_tab'),
                child: _buildReviewGrid(),
              ),
              _KeepAliveTab(
                key: const PageStorageKey('mypage_saved_posts_tab'),
                child: _buildSavedPosts(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileTab(String label, {required String sizingLabel}) {
    return Tab(
      height: 46,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ExcludeSemantics(
                child: Opacity(
                  opacity: 0,
                  child: Text(
                    sizingLabel,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
              ),
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
    // Firestore의 과거 문서에는 프로필 필드가 String 이외의 형식으로
    // 저장된 경우가 있다. 화면 build 중 강제 캐스팅이 실패하면 마이페이지
    // 전체가 빈 화면이 되므로 표시용 값은 항상 안전하게 정규화한다.
    final nickname = (userData?['nickname'] ?? '').toString().trim();
    final nationality = (userData?['nationality'] ?? '').toString().trim();
    final bio = (userData?['bio'] ?? '').toString().trim();
    final social = SocialProfileData.fromMap(userData);
    final rawPhotoUrl = (userData?['photoURL'] ?? '').toString();
    final photoUrl = ProfilePhotoPolicy.isAllowedProfilePhotoUrl(rawPhotoUrl)
        ? rawPhotoUrl
        : '';
    final profileCompletion = social.completionFor(
      hasProfilePhoto: photoUrl.isNotEmpty,
    );
    const profileSize = 100.0;
    const profileIconSize = 50.0;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        children: [
          // 프로필 사진(왼쪽) + 이름/국가(중앙) + 설정(오른쪽)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 프로필 사진 - 탭 가능
              GestureDetector(
                onTap: photoUrl.isNotEmpty
                    ? () => _openProfileImageViewer(photoUrl)
                    : null,
                child: Hero(
                  tag: 'profile_image_${user?.uid ?? 'me'}',
                  child: Container(
                    width: profileSize,
                    height: profileSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFE5E7EB),
                      // 사진이 있을 때만 탭 가능한 느낌을 주는 그림자 추가
                      boxShadow: photoUrl.isNotEmpty
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: photoUrl.isNotEmpty
                        ? ClipOval(
                            child: _buildCachedImage(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorWidget: ColoredBox(
                                color: const Color(0xFFE5E7EB),
                                child: Icon(
                                  Icons.person,
                                  size: profileIconSize,
                                  color: const Color(0xFF6B7280),
                                ),
                              ),
                              placeholder: ColoredBox(
                                color: const Color(0xFFE5E7EB),
                                child: Icon(
                                  Icons.person,
                                  size: profileIconSize,
                                  color: const Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          )
                        : Icon(
                            Icons.person,
                            size: profileIconSize,
                            color: const Color(0xFF6B7280),
                          ),
                  ),
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
                      nickname.isNotEmpty
                          ? nickname
                          : AppLocalizations.of(context)!.user,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (nationality.isNotEmpty)
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
                                      ?.getLocalizedName(
                                          Localizations.localeOf(context)
                                              .languageCode) ??
                                  nationality,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: const ['NotoSansKR'],
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
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        bio,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
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

          if (social.interests.isNotEmpty ||
              social.preferredActivities.isNotEmpty) ...[
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ...social.interests.map(
                    (id) => _socialTagLabel(
                      tagId: id,
                      kind: SocialProfileTagKind.interest,
                      label: SocialProfileCatalog.labelFor(
                        id,
                        SocialProfileCatalog.interests,
                        Localizations.localeOf(context).languageCode,
                      ),
                    ),
                  ),
                  ...social.preferredActivities.map(
                    (id) => _socialTagLabel(
                      tagId: id,
                      kind: SocialProfileTagKind.activity,
                      label: SocialProfileCatalog.labelFor(
                        id,
                        SocialProfileCatalog.activities,
                        Localizations.localeOf(context).languageCode,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (profileCompletion < 100) ...[
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfileEditScreen(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: profileCompletion / 100,
                            strokeWidth: 3,
                            backgroundColor: const Color(0xFFE2E8F0),
                            color: AppColors.pointColor,
                          ),
                          Center(
                            child: Text(
                              '$profileCompletion',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        Localizations.localeOf(context).languageCode == 'ko'
                            ? (social.interests.isEmpty
                                ? '관심사를 추가하면 비슷한 친구들이 더 쉽게 다가올 수 있어요.'
                                : '대화 질문을 설정하면 첫 DM이 더 자연스러워져요.')
                            : (social.interests.isEmpty
                                ? 'Add interests so similar people can find you.'
                                : 'Add a question to make the first DM easier.'),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF475569),
                          height: 1.4,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        size: 20, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
            ),
          ],

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
                usesCachedCount: true,
                countValue: _userPosts?.length,
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
                    countStream: _friendCountStream,
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
                usesCachedCount: true,
                countValue: _userReviews?.length,
                onTap: null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _socialTagLabel({
    required String tagId,
    required SocialProfileTagKind kind,
    required String label,
  }) {
    return Semantics(
      button: true,
      label: '#$label',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openSocialTagPeople(tagId, kind),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
            child: Text(
              '#$label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.pointColor,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openSocialTagPeople(String tagId, SocialProfileTagKind kind) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SocialTagPeopleScreen(tagId: tagId, kind: kind),
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
              color: AppColors.pointColor,
            ),
            SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.loginRequired,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.loginToViewReviews,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      );
    }

    final reviews = _userReviews;
    if (_isLoadingReviews && reviews == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.pointColor),
        ),
      );
    }

    if (_reviewsError != null && reviews == null) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.error,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: 16,
            color: Color(0xFFEF4444),
          ),
        ),
      );
    }

    if (reviews == null || reviews.isEmpty) {
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
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.joinMeetupAndWriteReview,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 15,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      key: const PageStorageKey('mypage_reviews_grid'),
      padding: const EdgeInsets.all(4),
      scrollCacheExtent: const ScrollCacheExtent.viewport(1.25),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
            color: AppTheme.backgroundSecondary,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (review.imageUrls.isNotEmpty)
                  _buildCachedImage(
                    review.imageUrls.first,
                    fit: BoxFit.cover,
                    placeholder: ColoredBox(
                      color: AppTheme.backgroundSecondary,
                    ),
                    errorWidget: ColoredBox(
                      color: AppTheme.backgroundSecondary,
                      child: Center(
                        child: Icon(
                          Icons.image_not_supported_rounded,
                          color: Colors.grey[400],
                          size: 32,
                        ),
                      ),
                    ),
                  ),
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
                            color: BrandColors.textSecondary,
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
  }

  /// 프로필 이미지 확대 뷰어 열기
  void _openProfileImageViewer(String imageUrl) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return ProfileImageViewer(
            imageUrl: imageUrl,
            heroTag:
                'profile_image_${Provider.of<AuthProvider>(context, listen: false).user?.uid ?? 'me'}',
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return child;
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
      ),
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
              color: AppColors.pointColor,
            ),
            SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.loginRequired,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            SizedBox(height: 8),
            Text(
              isKo ? '포스트를 보려면 로그인해주세요' : 'Please login to view posts',
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      );
    }

    final posts = _userPosts;
    if (_isLoadingUserPosts && posts == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.pointColor),
        ),
      );
    }

    if (_userPostsError != null && posts == null) {
      return Center(child: Text(AppLocalizations.of(context)!.error));
    }

    if (posts == null || posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.article_outlined,
                size: 48,
                color: AppColors.pointColor,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context)!.noWrittenPosts,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
          ],
        ),
      );
    }

    return _buildPostCollection(
      posts,
      showControls: true,
      storageKey: 'mypage_user_posts',
    );
  }

  Widget _buildSavedPosts() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;
    final l10n = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    if (currentUserId == null || currentUserId.isEmpty) {
      return Center(child: Text(l10n.loginRequired));
    }

    final posts = _savedPosts;
    if (_isLoadingSavedPosts && posts == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_savedPostsError != null && posts == null) {
      return Center(child: Text(l10n.error));
    }

    if (posts == null || posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.bookmark_border_rounded,
              size: 48,
              color: Color(0xFF9CA3AF),
            ),
            const SizedBox(height: 12),
            Text(
              isKo ? '저장한 글이 없습니다' : 'No saved posts yet',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
          ],
        ),
      );
    }

    return _buildPostCollection(
      posts,
      showControls: false,
      storageKey: 'mypage_saved_posts',
    );
  }

  Widget _buildPostCollection(
    List<Post> posts, {
    required bool showControls,
    required String storageKey,
  }) {
    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          if (showControls) _buildPostCollectionControls(),
          Expanded(
            child: _showPostsAsGrid
                ? _buildBorderlessPostGrid(posts, storageKey: storageKey)
                : _buildBorderlessPostList(posts, storageKey: storageKey),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCollectionControls() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 10, 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Semantics(
                    selected: true,
                    button: true,
                    child: Material(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          l10n.all,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _navigateToUserMeetups,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      l10n.myMeetups,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('mypage_posts_grid_toggle'),
            tooltip: 'Grid',
            onPressed: () => setState(() => _showPostsAsGrid = true),
            iconSize: 19,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            icon: Icon(
              Icons.grid_view_rounded,
              color: _showPostsAsGrid
                  ? AppColors.pointColor
                  : const Color(0xFF9CA3AF),
            ),
          ),
          IconButton(
            key: const ValueKey('mypage_posts_list_toggle'),
            tooltip: 'List',
            onPressed: () => setState(() => _showPostsAsGrid = false),
            iconSize: 19,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            icon: Icon(
              Icons.format_list_bulleted_rounded,
              color: !_showPostsAsGrid
                  ? AppColors.pointColor
                  : const Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBorderlessPostList(
    List<Post> posts, {
    required String storageKey,
  }) {
    final metrics = _PostListMetrics.from(context);
    return ListView.separated(
      key: PageStorageKey('$storageKey.list'),
      padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
      scrollCacheExtent: const ScrollCacheExtent.viewport(1.25),
      itemCount: posts.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        thickness: 1,
        color: Color(0xFFF1F3F5),
      ),
      itemBuilder: (context, index) => _buildBorderlessPostRow(posts[index]),
    );
  }

  Widget _buildBorderlessPostRow(Post post) {
    final l10n = AppLocalizations.of(context)!;
    final metadata = post.postCategories
        .map((category) => category.label(l10n))
        .toSet()
        .join(' · ');
    final metrics = _PostListMetrics.from(context);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _openPostDetail(post.id),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: metrics.verticalPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPostThumbnail(post, size: metrics.thumbnailSize),
              SizedBox(width: metrics.contentGap),
              Expanded(
                child: SizedBox(
                  height: metrics.rowHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.displayText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const <String>['NotoSansKR'],
                          fontSize: metrics.titleFontSize,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                          height: 1.25,
                        ),
                      ),
                      SizedBox(height: metrics.titleGap),
                      Text(
                        DateFormat('yyyy.MM.dd').format(post.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const <String>['NotoSansKR'],
                          fontSize: metrics.supportingFontSize,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF9CA3AF),
                          height: 1.2,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(height: metrics.metadataGap),
                      Row(
                        children: [
                          Icon(
                            Icons.notes_rounded,
                            size: metrics.metadataIconSize,
                            color: const Color(0xFF9CA3AF),
                          ),
                          SizedBox(width: metrics.iconGap),
                          Expanded(
                            child: Text(
                              metadata,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: const <String>[
                                  'NotoSansKR',
                                ],
                                fontSize: metrics.supportingFontSize,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF6B7280),
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: metrics.trailingGap),
              SizedBox(
                height: metrics.rowHeight,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: metrics.trailingMaxWidth,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            size: metrics.likeIconSize,
                            color: BrandColors.textSecondary,
                          ),
                          SizedBox(width: metrics.iconGap),
                          Text(
                            '${post.likes}',
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const <String>[
                                'NotoSansKR',
                              ],
                              fontSize: metrics.supportingFontSize,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF6B7280),
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBorderlessPostGrid(
    List<Post> posts, {
    required String storageKey,
  }) {
    return GridView.builder(
      key: PageStorageKey('$storageKey.grid'),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      scrollCacheExtent: const ScrollCacheExtent.viewport(1.25),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        return Semantics(
          button: true,
          label: post.displayText,
          child: InkWell(
            onTap: () => _openPostDetail(post.id),
            child: _buildPostThumbnail(post),
          ),
        );
      },
    );
  }

  Widget _buildPostThumbnail(Post post, {double? size}) {
    final image = (post.imageUrls.isNotEmpty
            ? post.imageUrls.first
            : post.linkPreview?.thumbnailUrl.trim()) ??
        '';
    final hasImage = image.isNotEmpty;
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: !hasImage
            ? const ColoredBox(
                color: Color(0xFFF3F4F6),
                child: Icon(
                  Icons.article_outlined,
                  color: Color(0xFF9CA3AF),
                  size: 28,
                ),
              )
            : _buildCachedImage(
                image,
                fit: BoxFit.cover,
                placeholder: const ColoredBox(
                  color: Color(0xFFF3F4F6),
                ),
                errorWidget: const ColoredBox(
                  color: Color(0xFFF3F4F6),
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: Color(0xFF9CA3AF),
                    size: 26,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildCachedImage(
    String imageUrl, {
    required BoxFit fit,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        final targetWidth = _cacheDimension(
          constraints.maxWidth,
          pixelRatio,
        );

        return CachedNetworkImage(
          imageUrl: imageUrl,
          cacheManager: AppImageCacheManager.instance,
          fit: fit,
          alignment: Alignment.center,
          width: double.infinity,
          height: double.infinity,
          // Supplying both cache dimensions uses ResizeImagePolicy.exact and
          // decodes every source into the viewport's aspect ratio. That makes
          // portrait and landscape photos look squashed before BoxFit.cover
          // can crop them. Constraining one axis keeps the source aspect ratio.
          memCacheWidth: targetWidth,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          useOldImageOnUrlChange: true,
          placeholder: (_, __) =>
              placeholder ??
              const ColoredBox(
                color: Color(0xFFF3F4F6),
              ),
          errorWidget: (_, __, ___) =>
              errorWidget ??
              const ColoredBox(
                color: Color(0xFFF3F4F6),
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: Color(0xFF9CA3AF),
                ),
              ),
        );
      },
    );
  }

  int? _cacheDimension(double logicalSize, double pixelRatio) {
    if (!logicalSize.isFinite || logicalSize <= 0) return null;
    return (logicalSize * pixelRatio).ceil().clamp(64, 1024).toInt();
  }

  Future<void> _openPostDetail(String postId) async {
    try {
      final fetched = await _postService.getPostById(postId);
      if (!mounted) return;

      if (fetched == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.postNotFound ?? "")),
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
    bool usesCachedCount = false,
    int? countValue,
    int badgeCount = 0,
    VoidCallback? onTap,
  }) {
    // 라벨/타입 기반으로 캐시 키 생성 (언어 변경에도 안정적으로 유지되도록 플래그 조합 사용)
    final cacheKey =
        'stat_${isFriends ? 'friends' : isJoined ? 'joined' : isPosts ? 'posts' : 'other'}_${showIcon ? 'icon' : 'noicon'}_${icon.codePoint}';
    if (usesCachedCount && countValue != null) {
      _statCountCache[cacheKey] = countValue;
    }

    final countDisplay = usesCachedCount
        ? _buildAnimatedStatCount(
            cacheKey,
            countValue ?? _statCountCache[cacheKey],
          )
        : StreamBuilder<int>(
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
              final live = snapshot.data;
              if (live != null) _statCountCache[cacheKey] = live;
              return _buildAnimatedStatCount(
                cacheKey,
                live ?? _statCountCache[cacheKey],
              );
            },
          );

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showIcon) ...[
                Icon(icon, size: 24, color: color),
                const SizedBox(height: 8),
              ],
              countDisplay,
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
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

  Widget _buildAnimatedStatCount(String cacheKey, int? value) {
    final countWidget = value != null
        ? Text(
            '$value',
            key: ValueKey<String>('count_$cacheKey:$value'),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          )
        : Text(
            '—',
            key: ValueKey<String>('count_$cacheKey:loading'),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF9CA3AF),
            ),
          );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final fade = FadeTransition(opacity: animation, child: child);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(animation),
          child: fade,
        );
      },
      child: countWidget,
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
                      ? (AppLocalizations.of(context)!.unhideReview ?? "")
                      : AppLocalizations.of(context)!.hideReview,
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
      final updatedReview = review.copyWith(hidden: !review.hidden);
      setState(() {
        _userReviews = _userReviews
            ?.map((item) => item.id == review.id ? updatedReview : item)
            .toList(growable: false);
      });
      final userId = _myPageCacheUserId;
      final reviews = _userReviews;
      if (userId != null && reviews != null) {
        await _myPageCacheService.saveReviews(userId, reviews);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            review.hidden
                ? l10n?.reviewUnhidden ?? ""
                : l10n?.reviewHidden ?? "",
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            review.hidden
                ? l10n?.reviewUnhideFailed ?? ""
                : l10n?.reviewHideFailed ?? "",
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
                _buildMenuItem(
                    context,
                    AppLocalizations.of(context)!.notificationSettings,
                    Icons.notifications_rounded, () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotificationSettingsScreen(),
                    ),
                  );
                }),
                _buildMenuItem(
                    context,
                    AppLocalizations.of(context)!.accountSettings,
                    Icons.settings_rounded, () {
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
                _buildMenuItem(context, AppLocalizations.of(context)!.logout,
                    Icons.logout_rounded, () async {
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
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
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
          backgroundColor: Colors.white,
          appBar: AppBar(
            toolbarHeight: MediaQuery.sizeOf(context).width < 360 ? 52 : 56,
            leadingWidth: MediaQuery.sizeOf(context).width < 360 ? 48 : 52,
            leading: IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              iconSize: 22,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            ),
            title: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Text(
                AppLocalizations.of(context)!.friends,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827),
                ),
              ),
            ),
            centerTitle: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            foregroundColor: const Color(0xFF111827),
            elevation: 0,
            scrolledUnderElevation: 0,
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

  void _showLogoutConfirmDialog(
      BuildContext context, AuthProvider authProvider) {
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
                      MaterialPageRoute(
                          builder: (_) => const SavedPostsScreen()),
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
                      MaterialPageRoute(
                          builder: (_) => const AccountSettingsScreen()),
                    );
                  },
                ),
                if (authProvider.userData?['isAdmin'] == true)
                  _menuItem(
                    sheetContext,
                    Localizations.localeOf(sheetContext).languageCode == 'ko'
                        ? '학기 To-do 관리'
                        : 'Semester To-do Admin',
                    Icons.admin_panel_settings_outlined,
                    () {
                      Navigator.pop(sheetContext);
                      Navigator.push(
                        rootContext,
                        MaterialPageRoute(
                          builder: (_) => const SemesterTodoAdminScreen(),
                        ),
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
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
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

class _PostListMetrics {
  const _PostListMetrics({
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.thumbnailSize,
    required this.rowHeight,
    required this.contentGap,
    required this.trailingGap,
    required this.titleGap,
    required this.metadataGap,
    required this.iconGap,
    required this.titleFontSize,
    required this.supportingFontSize,
    required this.metadataIconSize,
    required this.likeIconSize,
    required this.trailingMaxWidth,
  });

  factory _PostListMetrics.from(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final textScaler = MediaQuery.textScalerOf(context);
    final compact = width < 360;
    final wide = width >= 600;

    final horizontalPadding = compact ? 12.0 : (wide ? 24.0 : 16.0);
    final verticalPadding = compact ? 8.0 : (wide ? 12.0 : 10.0);
    final thumbnailSize = compact ? 76.0 : (wide ? 92.0 : 84.0);
    final contentGap = compact ? 10.0 : (wide ? 14.0 : 12.0);
    final trailingGap = compact ? 4.0 : (wide ? 8.0 : 6.0);
    final titleGap = compact ? 3.0 : (wide ? 5.0 : 4.0);
    final metadataGap = compact ? 3.0 : (wide ? 5.0 : 4.0);
    final iconGap = compact ? 3.0 : 4.0;
    final titleFontSize = compact ? 15.0 : (wide ? 17.0 : 16.0);
    final supportingFontSize = compact ? 12.0 : (wide ? 14.0 : 13.0);
    final metadataIconSize = compact ? 16.0 : (wide ? 18.0 : 17.0);
    final likeIconSize = compact ? 17.0 : (wide ? 19.0 : 18.0);
    final trailingMaxWidth = compact ? 56.0 : (wide ? 84.0 : 72.0);

    final titleBlockHeight = textScaler.scale(titleFontSize) * 1.25 * 2;
    final supportingLineHeight = textScaler.scale(supportingFontSize) * 1.2;
    final metadataLineHeight = math.max(
      supportingLineHeight,
      metadataIconSize,
    );
    final requiredHeight = titleBlockHeight +
        titleGap +
        supportingLineHeight +
        metadataGap +
        metadataLineHeight +
        2;

    return _PostListMetrics(
      horizontalPadding: horizontalPadding,
      verticalPadding: verticalPadding,
      thumbnailSize: thumbnailSize,
      rowHeight: math.max(thumbnailSize, requiredHeight),
      contentGap: contentGap,
      trailingGap: trailingGap,
      titleGap: titleGap,
      metadataGap: metadataGap,
      iconGap: iconGap,
      titleFontSize: titleFontSize,
      supportingFontSize: supportingFontSize,
      metadataIconSize: metadataIconSize,
      likeIconSize: likeIconSize,
      trailingMaxWidth: trailingMaxWidth,
    );
  }

  final double horizontalPadding;
  final double verticalPadding;
  final double thumbnailSize;
  final double rowHeight;
  final double contentGap;
  final double trailingGap;
  final double titleGap;
  final double metadataGap;
  final double iconGap;
  final double titleFontSize;
  final double supportingFontSize;
  final double metadataIconSize;
  final double likeIconSize;
  final double trailingMaxWidth;
}

/// TabBarView 바깥으로 잠시 이동해도 탭의 렌더 트리와 스크롤 상태를 유지한다.
class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({super.key, required this.child});

  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin<_KeepAliveTab> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
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
      color: Colors.white,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    // 탭 높이, 문구(언어), 컨트롤러가 바뀌면 고정 헤더의 child와
    // min/max extent를 함께 갱신해야 SliverGeometry 불일치가 발생하지 않는다.
    return true;
  }
}
