// lib/screens/mypage_screen.dart
// 사용자 프로필 화면
// Instagram 스타일 후기 탭 추가
// 기존 기능 유지 + 새로운 탭 구조

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../ui/widgets/motion_press.dart';
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
import '../services/post_media_prefetch_service.dart';
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
import '../l10n/ui_locale.dart';
import '../ui/widgets/motion_selectable.dart';
import '../utils/hanyang_verification_helper.dart';

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
  final PostMediaPrefetchService _postMediaPrefetch =
      PostMediaPrefetchService.instance;
  final MyPageCacheService _myPageCacheService = MyPageCacheService();
  late TabController _tabController;
  bool _showPostsAsGrid = false;
  // 통계 숫자(Posts/Friends/Reviews 등) 깜빡임 방지용 마지막 값 캐시

  String? _myPageCacheUserId;
  int _myPageLoadToken = 0;
  List<Post>? _userPosts;
  List<ReviewPost>? _userReviews;
  int? _friendCount;
  bool _isLoadingUserPosts = true;
  bool _isLoadingReviews = true;
  Object? _userPostsError;
  Object? _reviewsError;
  StreamSubscription<List<ReviewPost>>? _reviewsSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // 마이페이지에서는 친구요청 뱃지에 필요한 요청 스트림만 유지한다.
    // 친구 목록은 Friends 화면에 진입할 때 기존 방식으로 조회한다.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final authProvider = context.read<AuthProvider>();
        final relationshipProvider = context.read<RelationshipProvider>();
        relationshipProvider.setAuthProvider(authProvider);
        await Future.wait([
          relationshipProvider.loadIncomingRequests(),
          relationshipProvider.loadOutgoingRequests(),
        ]);
      } catch (_) {
        // 초기화 실패는 UI를 막지 않음 (배지는 0으로 표시됨)
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.user?.uid;
    final profileFriendCount = _parseFriendCount(authProvider.userData);

    // AuthProvider의 users/{uid} 캐시/스냅샷이 갱신되면 전체 프로필이나
    // 친구 목록을 다시 읽지 않고 숫자만 반영한다.
    if (_myPageCacheUserId == userId) {
      if (userId != null &&
          profileFriendCount != null &&
          profileFriendCount != _friendCount) {
        _friendCount = profileFriendCount;
        unawaited(
          _myPageCacheService.saveFriendCount(userId, profileFriendCount),
        );
      }
      return;
    }

    _myPageCacheUserId = userId;
    final loadToken = ++_myPageLoadToken;
    unawaited(_reviewsSubscription?.cancel() ?? Future<void>.value());
    _reviewsSubscription = null;
    _friendCount = profileFriendCount;
    _userPosts = null;
    _userReviews = null;
    _userPostsError = null;
    _reviewsError = null;
    _isLoadingUserPosts = userId != null;
    _isLoadingReviews = userId != null;

    if (userId != null && userId.isNotEmpty) {
      unawaited(
        _hydrateFriendCount(userId, loadToken, profileFriendCount),
      );
      unawaited(_refreshExactFriendCount(userId, loadToken));
      _loadMyPageTabs(userId, loadToken);
    }
  }

  int? _parseFriendCount(Map<String, dynamic>? userData) {
    if (userData == null || !userData.containsKey('friendsCount')) return null;
    final value = userData['friendsCount'];
    if (value is num) return value.toInt() < 0 ? 0 : value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null) return null;
    return parsed < 0 ? 0 : parsed;
  }

  Future<void> _hydrateFriendCount(
    String userId,
    int loadToken,
    int? profileFriendCount,
  ) async {
    if (profileFriendCount != null) {
      await _myPageCacheService.saveFriendCount(userId, profileFriendCount);
      return;
    }

    final cachedCount = await _myPageCacheService.readFriendCount(userId);
    if (cachedCount == null || !_isCurrentLoad(userId, loadToken)) return;
    setState(() => _friendCount = cachedCount);
  }

  Future<void> _refreshExactFriendCount(String userId, int loadToken) async {
    try {
      final exactCount =
          await _userStatsService.getLatestFriendCountForUser(userId);
      if (!_isCurrentLoad(userId, loadToken)) return;
      if (_friendCount != exactCount) {
        setState(() => _friendCount = exactCount);
      }
      await _myPageCacheService.saveFriendCount(userId, exactCount);
    } catch (_) {
      // 오프라인/일시적 네트워크 오류에서는 프로필 문서 또는 로컬 캐시의
      // 마지막 값을 유지한다. 친구 목록 화면과 다른 기능은 막지 않는다.
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
  }

  Future<void> _loadUserPosts(String userId, int loadToken) async {
    final cached = await _myPageCacheService.readUserPosts(userId);
    if (!_isCurrentLoad(userId, loadToken)) return;

    setState(() {
      if (cached != null) _userPosts = cached.items;
      _isLoadingUserPosts = cached == null;
    });
    if (cached != null) {
      unawaited(_postMediaPrefetch.prefetchPosts(cached.items, maxPosts: 9));
    }
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
      unawaited(_postMediaPrefetch.prefetchPosts(posts, maxPosts: 9));
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
      await _reviewService.reconcileAcceptedReviewsForCurrentProfile();
      if (!_isCurrentLoad(userId, loadToken)) return;
      await _reviewsSubscription?.cancel();
      _reviewsSubscription = _reviewService.getUserReviews().listen(
        (reviews) {
          if (!_isCurrentLoad(userId, loadToken)) return;
          setState(() {
            _userReviews = reviews;
            _isLoadingReviews = false;
            _reviewsError = null;
          });
          unawaited(_myPageCacheService.saveReviews(userId, reviews));
        },
        onError: (Object error) {
          if (!_isCurrentLoad(userId, loadToken)) return;
          setState(() {
            _isLoadingReviews = false;
            if (_userReviews == null) _reviewsError = error;
          });
        },
      );
    } catch (error) {
      if (!_isCurrentLoad(userId, loadToken)) return;
      setState(() {
        _isLoadingReviews = false;
        if (_userReviews == null) _reviewsError = error;
      });
    }
  }

  @override
  void dispose() {
    unawaited(_reviewsSubscription?.cancel() ?? Future<void>.value());
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
            final reviewsLabel = (isChineseUi(context) ? '聚会回顾' : isKorean ? '모임 후기' : 'Meetup Reviews');
            final myMeetupsLabel = AppLocalizations.of(context)!.myMeetups;

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
                        myMeetupsLabel,
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
                key: const PageStorageKey('mypage_my_meetups_tab'),
                child: const UserMeetupsView(),
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
      child: MotionPress(
        pressedScale: MotionSelectable.segmentScale,
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
    final university = (userData?['university'] ?? '').toString().trim();
    final social = SocialProfileData.fromMap(userData);
    final isSchoolVerified = isHanyangEmailVerified(userData);
    final rawPhotoUrl = (userData?['photoURL'] ?? '').toString();
    final photoUrl = ProfilePhotoPolicy.isAllowedProfilePhotoUrl(rawPhotoUrl)
        ? rawPhotoUrl
        : '';
    final profileCompletion = social.completionFor(
      hasProfilePhoto: photoUrl.isNotEmpty,
    );
    final languageCode = Localizations.localeOf(context).languageCode;
    final zh = isChineseUi(context);
    final l10n = AppLocalizations.of(context)!;
    final horizontalPadding =
        MediaQuery.sizeOf(context).width < 360 ? 16.0 : 20.0;
    const avatarSize = 76.0;

    TextStyle style(double size, FontWeight weight, Color color,
            {double? line}) =>
        TextStyle(
          fontFamily: uiFontFamily(context, 'Inter'),
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: size,
          height: line == null ? null : line / size,
          fontWeight: weight,
          color: color,
        );

    final schoolParts = <String>[
      if (university.isNotEmpty) university,
      if (isSchoolVerified && social.showDepartment && social.department.isNotEmpty)
        social.department,
      if (isSchoolVerified && social.showGrade && social.grade.isNotEmpty)
        social.grade,
    ];

    Widget count(String label, int? value) => Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value == null ? '—' : '$value',
                style: style(15, FontWeight.w700, const Color(0xFF111827)),
              ),
              TextSpan(
                text: ' $label',
                style: style(12, FontWeight.w400, const Color(0xFF707070)),
              ),
            ],
          ),
        );
    Widget dot() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('·',
              style: style(12, FontWeight.w400, const Color(0xFF9A9A9A))),
        );

    Widget actionButton({
      required Key key,
      required String label,
      required VoidCallback onTap,
      bool primary = false,
    }) {
      return SizedBox(
        height: 38,
        child: FilledButton(
          key: key,
          onPressed: onTap,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            backgroundColor:
                primary ? const Color(0xFF2C6BC0) : const Color(0xFFF2F2F2),
            foregroundColor: primary ? Colors.white : const Color(0xFF111827),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style(
              13,
              FontWeight.w600,
              primary ? Colors.white : const Color(0xFF111827),
            ),
          ),
        ),
      );
    }

    final friendLabel = zh
        ? '好友 ${_friendCount ?? 0}'
        : languageCode == 'ko'
            ? '친구 ${_friendCount ?? 0}'
            : 'Friends ${_friendCount ?? 0}';

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                MotionPress(
                  enabled: photoUrl.isNotEmpty,
                  pressedScale: .985,
                  child: GestureDetector(
                    onTap: photoUrl.isNotEmpty
                        ? () => _openProfileImageViewer(photoUrl)
                        : null,
                    child: Hero(
                      tag: 'profile_image_${user?.uid ?? 'me'}',
                      child: Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFE5E7EB),
                        ),
                        child: photoUrl.isNotEmpty
                            ? ClipOval(
                                child: _buildCachedImage(
                                  photoUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: const ColoredBox(
                                    color: Color(0xFFE5E7EB),
                                    child: Icon(Icons.person,
                                        size: 38, color: Color(0xFF6B7280)),
                                  ),
                                  placeholder: const ColoredBox(
                                    color: Color(0xFFE5E7EB),
                                    child: Icon(Icons.person,
                                        size: 38, color: Color(0xFF6B7280)),
                                  ),
                                ),
                              )
                            : const Icon(Icons.person,
                                size: 38, color: Color(0xFF6B7280)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              nickname.isNotEmpty ? nickname : l10n.user,
                              key: const ValueKey('mypage_name'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style(18, FontWeight.w700,
                                  const Color(0xFF111827),
                                  line: 24),
                            ),
                          ),
                          if (nationality.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            CountryFlagCircle(nationality: nationality, size: 16),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                CountryFlagHelper.getCountryInfo(nationality)
                                        ?.getLocalizedName(languageCode) ??
                                    nationality,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: style(13, FontWeight.w400,
                                    const Color(0xFF707070)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (schoolParts.isNotEmpty || isSchoolVerified) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (isSchoolVerified) ...[
                              const Icon(Icons.verified_rounded,
                                  size: 13, color: AppColors.pointColor),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                schoolParts.isEmpty
                                    ? 'Hanyang University'
                                    : schoolParts.join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: style(12, FontWeight.w400,
                                    const Color(0xFF5F5F5F),
                                    line: 16),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          count(l10n.posts, _userPosts?.length),
                          dot(),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _navigateToFriendsPage,
                            child: count(l10n.friends, _friendCount),
                          ),
                          dot(),
                          count(l10n.reviews, _userReviews?.length),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                bio,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: style(14, FontWeight.w400, const Color(0xFF111827),
                    line: 20),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: actionButton(
                    key: const ValueKey('mypage_edit_button'),
                    label: l10n.profileEdit,
                    primary: true,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileEditScreen(),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: actionButton(
                    key: const ValueKey('mypage_friends_button'),
                    label: friendLabel,
                    onTap: _navigateToFriendsPage,
                  ),
                ),
              ],
            ),
            if (social.interests.isNotEmpty ||
                social.preferredActivities.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
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
                        languageCode,
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
                        languageCode,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (profileCompletion < 100) ...[
              const SizedBox(height: 12),
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
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 30,
                        height: 30,
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
                                style: style(10, FontWeight.w700,
                                    const Color(0xFF475569)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          languageCode == 'ko'
                              ? (social.interests.isEmpty
                                  ? '관심사를 추가하면 비슷한 친구들이 더 쉽게 다가올 수 있어요.'
                                  : '대화 질문을 설정하면 첫 DM이 더 자연스러워져요.')
                              : (social.interests.isEmpty
                                  ? 'Add interests so similar people can find you.'
                                  : 'Add a question to make the first DM easier.'),
                          style: style(13, FontWeight.w500,
                              const Color(0xFF475569),
                              line: 18),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          size: 20, color: Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
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
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.pointColor,
                height: isChineseUi(context) ? 1.3 : 1.2,
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
                fontFamily: uiFontFamily(context, 'Inter'),
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
                fontFamily: uiFontFamily(context, 'Inter'),
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
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
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
                fontFamily: uiFontFamily(context, 'Inter'),
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
                fontFamily: uiFontFamily(context, 'Inter'),
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
        return MotionPress(
          pressedScale: .985,
          child: GestureDetector(
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
                      placeholder: ColoredBox(color: AppTheme.backgroundSecondary),
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
                              style: uiTextStyle(
                                context,
                                AppTheme.labelSmall.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
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
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            SizedBox(height: 8),
            Text(
              (isChineseUi(context) ? '请先登录再查看动态' : isKo ? '포스트를 보려면 로그인해주세요' : 'Please login to view posts'),
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
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
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
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
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
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
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
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
                    onPressed: _navigateToSavedPosts,
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
                      (isChineseUi(context) ? '收藏的动态' : isKo ? '저장한 글' : 'Saved Posts'),
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
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
          MotionSelectable(
            selected: _showPostsAsGrid,
            pressedScale: .92,
            child: IconButton(
              key: const ValueKey('mypage_posts_grid_toggle'),
              tooltip: 'Grid',
              onPressed: () => setState(() => _showPostsAsGrid = true),
              iconSize: 19,
              padding: const EdgeInsets.all(6),
              constraints:
                  const BoxConstraints.tightFor(width: 36, height: 36),
              icon: Icon(
                Icons.grid_view_rounded,
                color: _showPostsAsGrid
                    ? AppColors.pointColor
                    : const Color(0xFF9CA3AF),
              ),
            ),
          ),
          MotionSelectable(
            selected: !_showPostsAsGrid,
            pressedScale: .92,
            child: IconButton(
              key: const ValueKey('mypage_posts_list_toggle'),
              tooltip: 'List',
              onPressed: () => setState(() => _showPostsAsGrid = false),
              iconSize: 19,
              padding: const EdgeInsets.all(6),
              constraints:
                  const BoxConstraints.tightFor(width: 36, height: 36),
              icon: Icon(
                Icons.format_list_bulleted_rounded,
                color: !_showPostsAsGrid
                    ? AppColors.pointColor
                    : const Color(0xFF9CA3AF),
              ),
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
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const <String>['NotoSansKR'],
                          fontSize: metrics.titleFontSize,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                          height: isChineseUi(context) ? 1.3 : 1.25,
                        ),
                      ),
                      SizedBox(height: metrics.titleGap),
                      Text(
                        DateFormat('yyyy.MM.dd').format(post.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const <String>['NotoSansKR'],
                          fontSize: metrics.supportingFontSize,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF9CA3AF),
                          height: isChineseUi(context) ? 1.3 : 1.2,
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
                                fontFamily: uiFontFamily(context, 'Inter'),
                                fontFamilyFallback: const <String>[
                                  'NotoSansKR',
                                ],
                                fontSize: metrics.supportingFontSize,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF6B7280),
                                height: isChineseUi(context) ? 1.3 : 1.2,
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
                              fontFamily: uiFontFamily(context, 'Inter'),
                              fontFamilyFallback: const <String>[
                                'NotoSansKR',
                              ],
                              fontSize: metrics.supportingFontSize,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF6B7280),
                              height: isChineseUi(context) ? 1.3 : 1.2,
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

      final deleted = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => PostDetailScreen(post: fetched),
        ),
      );
      // 상세에서 지웠으면 목록과 기기 저장본에서도 바로 뺀다(다시 누르면
      // '찾을 수 없음'이 뜨는 남은 항목 방지).
      if (deleted == true && mounted) {
        final remaining = (_userPosts ?? const <Post>[])
            .where((post) => post.id != postId)
            .toList();
        setState(() => _userPosts = remaining);
        final uid = Provider.of<AuthProvider>(context, listen: false).user?.uid;
        if (uid != null) {
          unawaited(_myPageCacheService.saveUserPosts(uid, remaining));
        }
      }
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
                fontFamily: uiFontFamily(context, 'Inter'),
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
  Future<void> _navigateToFriendsPage() async {
    await Navigator.push(
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
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
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
    final userId = _myPageCacheUserId;
    if (!mounted || userId == null || userId.isEmpty) return;
    unawaited(_refreshExactFriendCount(userId, _myPageLoadToken));
  }

  void _navigateToSavedPosts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SavedPostsScreen(),
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
                    (isChineseUi(context) ? '学期待办管理' : Localizations.localeOf(sheetContext).languageCode == 'ko'
                        ? '학기 To-do 관리'
                        : 'Semester To-do Admin'),
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
    return MotionPress(
      pressedScale: .99,
      child: InkWell(
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
                fontFamily: uiFontFamily(context, 'Inter'),
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
