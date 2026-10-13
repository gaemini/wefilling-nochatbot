// lib/screens/friend_profile_screen.dart
// 관계 상태와 관계없이 같은 구조를 사용하는 네트워크 프로필 화면

import 'dart:async';

import 'package:flutter/material.dart';
import '../services/user_stats_service.dart';
import '../services/review_service.dart';
import '../services/dm_service.dart';
import '../services/relationship_service.dart';
import '../models/review_post.dart';
import '../models/relationship_status.dart';
import '../models/user_profile.dart';
import '../constants/app_constants.dart';
import '../widgets/country_flag_circle.dart'; // 국기 위젯 추가
import '../l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'review_detail_screen.dart';
import 'dm_chat_screen.dart';
import '../utils/country_flag_helper.dart';
import '../utils/logger.dart';
import '../utils/hanyang_verification_helper.dart';
import '../ui/widgets/profile_image_viewer.dart';
import 'user_friends_list_screen.dart';
import '../models/social_profile_data.dart';
import '../utils/account_status_helper.dart';
import '../services/notification_service.dart';
import '../services/active_content_registry.dart';
import '../l10n/ui_locale.dart';
import '../ui/widgets/motion_press.dart';
import '../ui/widgets/group_list_row.dart';
import '../l10n/together_strings.dart';
import '../services/together_service.dart';
import 'snack_chat_screen.dart';

class FriendProfileScreen extends StatefulWidget {
  final String userId;
  final String? nickname;
  final String? photoURL;
  final String? email;
  final String? university;

  /// 기존 호출부와의 호환을 위한 진입 힌트다. 프로필 구조는
  /// 친구/비친구가 공유하고 관계 버튼과 DM 권한만 다르게 표시한다.
  final bool allowNonFriendsPreview;

  const FriendProfileScreen({
    Key? key,
    required this.userId,
    this.nickname,
    this.photoURL,
    this.email,
    this.university,
    this.allowNonFriendsPreview = false,
  }) : super(key: key);

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen>
    with WidgetsBindingObserver {
  final UserStatsService _userStatsService = UserStatsService();
  final ReviewService _reviewService = ReviewService();
  final DMService _dmService = DMService();
  final RelationshipService _relationshipService = RelationshipService();

  Map<String, dynamic>? _userData;
  bool _isDeletedAccount = false;
  bool _profileLoadFailed = false;
  bool _isLoading = true;
  bool _isRelationshipLoading = true;
  RelationshipStatus? _relationshipStatus;
  bool _isRequestingFriend = false;
  int _profileLoadToken = 0;
  // 통계 숫자 깜빡임/0 표시 방지용 캐시
  final Map<String, int> _statCountCache = {};
  UserProfileStats? _profileStats;
  int _statsLoadToken = 0;
  ProfileFriendNetworkPage? _friendPreview;
  List<ReviewPost> _reviewPreview = const <ReviewPost>[];
  bool _isFriendPreviewLoading = true;
  bool _isReviewPreviewLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserData();
    _loadRelationshipStatus();
    _loadLatestStats();
    _loadFriendPreview();
    _loadReviewPreview();
  }

  @override
  void dispose() {
    ActiveContentRegistry.unregister(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadLatestStats());
    }
  }

  Future<void> _loadLatestStats() async {
    final token = ++_statsLoadToken;
    try {
      final stats =
          await _userStatsService.getLatestProfileStatsForUser(widget.userId);
      if (!mounted || token != _statsLoadToken) return;
      setState(() {
        _profileStats = stats;
        _statCountCache['friend_profile_friends'] = stats.friendCount;
        _statCountCache['friend_profile_joined_meetups'] =
            stats.joinedMeetupCount;
        _statCountCache['friend_profile_written_posts'] =
            stats.writtenPostCount;
      });
    } catch (error) {
      Logger.error('최신 프로필 통계 로드 오류: $error');
    }
  }

  Future<void> _refreshProfile() async {
    await Future.wait<void>([
      _loadUserData(),
      _loadRelationshipStatus(),
      _loadLatestStats(),
      _loadFriendPreview(forceRefresh: true),
      _loadReviewPreview(),
    ]);
  }

  Future<void> _loadFriendPreview({bool forceRefresh = false}) async {
    if (mounted && forceRefresh) {
      setState(() => _isFriendPreviewLoading = true);
    }
    try {
      final preview = await _relationshipService.getProfileFriendNetwork(
        targetUid: widget.userId,
        pageSize: 6,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _friendPreview = preview;
        _isFriendPreviewLoading = false;
      });
    } catch (error) {
      Logger.error('친구 미리보기 로드 오류: $error');
      if (mounted) setState(() => _isFriendPreviewLoading = false);
    }
  }

  Future<void> _loadReviewPreview() async {
    try {
      final reviews = await _reviewService.getPublicUserReviewPreview(
        widget.userId,
        limit: 3,
      );
      if (!mounted) return;
      setState(() {
        _reviewPreview = reviews;
        _isReviewPreviewLoading = false;
      });
    } catch (error) {
      Logger.error('공개 후기 미리보기 로드 오류: $error');
      if (mounted) setState(() => _isReviewPreviewLoading = false);
    }
  }

  Future<void> _loadRelationshipStatus() async {
    try {
      final currentUserId = _relationshipService.currentUserId;
      if (currentUserId == null || currentUserId == widget.userId) {
        if (mounted) {
          setState(() {
            _relationshipStatus = RelationshipStatus.friends;
            _isRelationshipLoading = false;
          });
        }
        return;
      }

      final status =
          await _relationshipService.getRelationshipStatus(widget.userId);
      if (mounted) {
        setState(() {
          _relationshipStatus = status;
          _isRelationshipLoading = false;
        });
      }
    } catch (e) {
      Logger.error('관계 상태 로드 오류: $e');
      if (mounted) {
        setState(() {
          _relationshipStatus = RelationshipStatus.none;
          _isRelationshipLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserData() async {
    final readContext = NotificationService.captureReadContext();
    final token = ++_profileLoadToken;
    try {
      final targetFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get(const GetOptions(source: Source.server));
      final doc = await targetFuture;
      final targetData = doc.data();
      final targetIsDeleted = !doc.exists ||
          targetData == null ||
          isUnavailableUserAccountData(targetData);

      if (!mounted || token != _profileLoadToken) return;
      if (!targetIsDeleted) {
        unawaited(NotificationService().markRelatedNotificationsAsRead(
          types: const {'friend_request_accepted'},
          readContext: readContext,
          targets: {'actorId': widget.userId},
        ));
        ActiveContentRegistry.register(this,
            types: const {'friend_request_accepted'},
            targets: {'actorId': widget.userId});
        setState(() {
          _userData = targetData;
          _isDeletedAccount = false;
          _profileLoadFailed = false;
          _isLoading = false;
        });
      } else {
        // 탈퇴한 사용자 처리
        if (Logger.isVerboseEnabled) Logger.log('⚠️ 탈퇴한 사용자: ${widget.userId}');
        setState(() {
          final deletedLabel =
              AppLocalizations.of(context)?.deletedAccount ?? '탈퇴한 계정';
          _userData = {
            'nickname': deletedLabel,
            'displayName': deletedLabel,
            'photoURL': '',
            'bio': '',
          };
          _isDeletedAccount = true;
          _profileLoadFailed = false;
          _isRelationshipLoading = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('사용자 데이터 로드 오류: $e');
      final fallbackData =
          await _loadCachedProfileData() ?? _profileDataFromNavigationHint();
      if (!mounted || token != _profileLoadToken) return;
      setState(() {
        // 네트워크/App Check의 일시 오류를 탈퇴 계정으로 오인하지 않는다.
        // 학교 인증 여부는 프로필 조회 권한과 무관하며, 포스트·밋업의
        // 한양인 공개 콘텐츠는 각 콘텐츠 전용 게이트에서 계속 제한한다.
        _userData = fallbackData;
        _isDeletedAccount = false;
        _profileLoadFailed = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _retryProfileLoad() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await _loadUserData();
  }

  Future<Map<String, dynamic>?> _loadCachedProfileData() async {
    try {
      final cached = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get(const GetOptions(source: Source.cache));
      final data = cached.data();
      if (!cached.exists || isUnavailableUserAccountData(data)) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _profileDataFromNavigationHint() {
    final nickname = (widget.nickname ?? '').trim();
    final photoURL = (widget.photoURL ?? '').trim();
    final university = (widget.university ?? '').trim();
    if (nickname.isEmpty && photoURL.isEmpty && university.isEmpty) return null;
    return <String, dynamic>{
      if (nickname.isNotEmpty) ...{
        'nickname': nickname,
        'displayName': nickname,
      },
      'photoURL': photoURL,
      'university': university,
      'bio': '',
    };
  }

  @override
  Widget build(BuildContext context) {
    // 안드로이드 하단 네비게이션 바 높이 감지
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final l10n = AppLocalizations.of(context)!;

    final currentUserId = _relationshipService.currentUserId;
    final isMe = currentUserId != null && currentUserId == widget.userId;
    final isFriends = _relationshipStatus == RelationshipStatus.friends;
    final isNonFriendPreview = !isMe && !isFriends;
    final isBlocked = _relationshipStatus == RelationshipStatus.blocked ||
        _relationshipStatus == RelationshipStatus.blockedBy;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: MediaQuery.sizeOf(context).width < 360 ? 52 : 56,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              size: 22, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: Colors.white,
      body: (_isLoading || _isRelationshipLoading)
          ? _buildProfileLoadingView()
          : _profileLoadFailed && _userData == null
              ? _buildProfileLoadError()
              : _isDeletedAccount
                  ? _buildDeletedAccountProfile(l10n)
                  : isBlocked
                      ? _buildLockedProfile(l10n)
                      : RefreshIndicator(
                          onRefresh: _refreshProfile,
                          child: CustomScrollView(
                            key: PageStorageKey<String>(
                              'friend_profile_${widget.userId}',
                            ),
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverToBoxAdapter(
                                child: _buildProfileHeader(
                                    isNonFriendPreview: isNonFriendPreview),
                              ),
                              SliverToBoxAdapter(
                                child: _buildFriendPreviewSection(),
                              ),
                              SliverToBoxAdapter(
                                child: _buildSocialProfileDetails(
                                  SocialProfileData.fromMap(_userData),
                                  showSchoolInfo:
                                      isHanyangEmailVerified(_userData),
                                  // 기본 정책: 친구에게만 제안할 수 있다.
                                  canPropose: isFriends && !isMe,
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: _buildReviewPreviewSection(),
                              ),
                              // 안드로이드 하단 네비게이션 바를 위한 여백 추가
                              SliverToBoxAdapter(
                                child: SizedBox(
                                  height: bottomPadding > 0
                                      ? bottomPadding + 16
                                      : 16,
                                ),
                              ),
                            ],
                          ),
                        ),
    );
  }

  Widget _buildProfileLoadError() {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.person_outline_rounded,
              size: 48,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(height: 16),
            Text(
              (isChineseUi(context) ? '资料加载失败' : isKo ? '프로필을 불러오지 못했어요' : 'Unable to load profile'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              (isChineseUi(context) ? '请稍后重试。' : isKo ? '잠시 후 다시 시도해 주세요.' : 'Please try again in a moment.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: _retryProfileLoad,
              icon: const Icon(Icons.refresh_rounded, size: 19),
              label: Text((isChineseUi(context) ? '重试' : isKo ? '다시 시도' : 'Retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileLoadingView() {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottom + 20),
      children: const [
        Row(
          children: [
            CircleAvatar(radius: 44, backgroundColor: Color(0xFFF1F5F9)),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonLine(width: 124, height: 18),
                  SizedBox(height: 12),
                  _SkeletonLine(width: 172, height: 13),
                  SizedBox(height: 9),
                  _SkeletonLine(width: 148, height: 13),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 28),
        _ProfileSectionSkeleton(height: 126),
        _ProfileSectionSkeleton(height: 176),
      ],
    );
  }

  Widget _buildDeletedAccountProfile(AppLocalizations l10n) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 48,
              backgroundColor: Color(0xFFF1F5F9),
              child: Icon(
                Icons.person_off_outlined,
                size: 42,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.deletedAccount,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              (isChineseUi(context) ? '此账号已不可用。' : isKo
                  ? '탈퇴하여 더 이상 조회할 수 없는 계정입니다.'
                  : 'This account is no longer available.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.45,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedProfile(AppLocalizations l10n) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.lock_outline,
                color: Color(0xFF6B7280),
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              (isChineseUi(context) ? '无法查看资料' : isKo ? '프로필을 볼 수 없어요' : 'Profile unavailable'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              (isChineseUi(context) ? '账号被拉黑时，资料和好友列表将隐藏。' : isKo
                  ? '차단 관계에서는 프로필과 친구 목록이 표시되지 않아요.'
                  : 'Profiles and friend lists are hidden when an account is blocked.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Color(0xFF6B7280),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendFriendRequestFromProfile() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isDeletedAccount) return;
    final currentUserId = _relationshipService.currentUserId;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.loginRequired)),
      );
      return;
    }

    setState(() {
      _isRequestingFriend = true;
    });

    try {
      final ok = await _relationshipService.sendFriendRequest(widget.userId);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _relationshipStatus = RelationshipStatus.pendingOut;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.friendRequestSent)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (msg.startsWith('Exception: ')) {
        msg = msg.substring('Exception: '.length);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isRequestingFriend = false;
      });
    }
  }

  Widget _buildProfileHeader({required bool isNonFriendPreview}) {
    final nickname = _userData?['nickname'] ??
        widget.nickname ??
        AppLocalizations.of(context)!.user;
    final photoURL = _userData?['photoURL'] ?? widget.photoURL;
    final university =
        (_userData?['university'] ?? widget.university)?.toString().trim() ??
            '';
    final isSchoolVerified = isHanyangEmailVerified(_userData);
    final nationality = _userData?['nationality'];
    final bio = _userData?['bio'];
    final social = SocialProfileData.fromMap(_userData);
    final l10n = AppLocalizations.of(context)!;
    final languageCode = Localizations.localeOf(context).languageCode;
    final zh = isChineseUi(context);
    final currentUserId = _relationshipService.currentUserId;
    final isMe = currentUserId != null && currentUserId == widget.userId;
    final isFriends = _relationshipStatus == RelationshipStatus.friends;
    final status = _relationshipStatus ?? RelationshipStatus.none;
    final canRequest = status == RelationshipStatus.none;
    final isPending = status == RelationshipStatus.pendingOut;
    final hasIncomingRequest = status == RelationshipStatus.pendingIn;

    final horizontalPadding =
        MediaQuery.sizeOf(context).width < 360 ? 16.0 : 20.0;
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

    // 학교 줄: [인증 배지] 학교 · 학과 · 학번(공개 설정을 따른다, 인증 표시는 한 번).
    final schoolParts = <String>[
      if (university.isNotEmpty) university,
      if (isSchoolVerified && social.showDepartment && social.department.isNotEmpty)
        social.department,
      if (isSchoolVerified && social.showGrade && social.grade.isNotEmpty)
        social.grade,
    ];

    Widget stat(String label, String cacheKey,
        {bool friends = false, bool joined = false, bool posts = false}) {
      final latest = friends
          ? _profileStats?.friendCount
          : joined
              ? _profileStats?.joinedMeetupCount
              : posts
                  ? _profileStats?.writtenPostCount
                  : null;
      final value = latest ?? _statCountCache[cacheKey];
      final text = Text.rich(
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
      if (!friends) return text;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _navigateToFriendsList,
        child: text,
      );
    }

    Widget dot() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('·',
              style: style(12, FontWeight.w400, const Color(0xFF9A9A9A))),
        );

    final hasPhoto = photoURL != null && photoURL.toString().isNotEmpty;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                MotionPress(
                  enabled: hasPhoto,
                  pressedScale: .985,
                  child: GestureDetector(
                    onTap: hasPhoto
                        ? () => _openProfileImageViewer(photoURL.toString())
                        : null,
                    child: Hero(
                      tag: 'profile_image_${widget.userId}',
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFE5E7EB),
                        ),
                        child: hasPhoto
                            ? ClipOval(
                                child: Image.network(
                                  photoURL.toString(),
                                  width: 76,
                                  height: 76,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.person,
                                    size: 38,
                                    color: Color(0xFF6B7280),
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
                              nickname.toString(),
                              key: const ValueKey('profile_name'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style(18, FontWeight.w700,
                                  const Color(0xFF111827),
                                  line: 24),
                            ),
                          ),
                          if (nationality != null &&
                              nationality.toString().isNotEmpty) ...[
                            const SizedBox(width: 6),
                            CountryFlagCircle(
                              nationality: nationality.toString(),
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                CountryFlagHelper.getCountryInfo(
                                            nationality.toString())
                                        ?.getLocalizedName(languageCode) ??
                                    nationality.toString(),
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
                              const Icon(
                                Icons.verified_rounded,
                                size: 13,
                                color: AppColors.pointColor,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                schoolParts.isEmpty
                                    ? 'Hanyang University'
                                    : schoolParts.join(' · '),
                                key: const ValueKey('profile_school'),
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
                      // 숫자 한 줄. 글 숫자는 탭 동작이 없다.
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          stat(l10n.friends, 'friend_profile_friends',
                              friends: true),
                          dot(),
                          stat(l10n.joinedMeetups,
                              'friend_profile_joined_meetups',
                              joined: true),
                          dot(),
                          stat(l10n.writtenPosts,
                              'friend_profile_written_posts',
                              posts: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (bio != null && bio.toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                bio.toString(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: style(14, FontWeight.w400, const Color(0xFF111827),
                    line: 20),
              ),
            ],
            if (social.friendshipPrompt.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                social.friendshipPrompt,
                style: style(13, FontWeight.w400, const Color(0xFF5F5F5F),
                    line: 18),
              ),
            ],
            if (!isMe) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: FilledButton(
                        key: const ValueKey('profile_message_button'),
                        onPressed: _openDM,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2C6BC0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          l10n.sendMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: style(14, FontWeight.w600, Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    height: 38,
                    child: FilledButton(
                      key: const ValueKey('profile_relation_button'),
                      onPressed: isNonFriendPreview &&
                              canRequest &&
                              !_isRequestingFriend
                          ? _sendFriendRequestFromProfile
                          : null,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: const Color(0xFFF2F2F2),
                        disabledBackgroundColor: const Color(0xFFF2F2F2),
                        foregroundColor: Colors.black,
                        disabledForegroundColor: const Color(0xFF5F5F5F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _isRequestingFriend
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              isFriends
                                  ? (zh ? '好友 ✓' : languageCode == 'ko' ? '친구 ✓' : 'Friends ✓')
                                  : isPending
                                      ? l10n.requestPending
                                      : hasIncomingRequest
                                          ? (zh
                                              ? '收到申请'
                                              : languageCode == 'ko'
                                                  ? '요청 받음'
                                                  : 'Requested you')
                                          : (zh
                                              ? '加好友'
                                              : languageCode == 'ko'
                                                  ? '친구 추가'
                                                  : 'Add friend'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style(13, FontWeight.w600,
                                  const Color(0xFF111827)),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 같이하기 상태: 활동 id → 진행 중 / 완료.
  final Map<String, bool> _togetherLoading = <String, bool>{};
  final Map<String, String> _togetherRoomIds = <String, String>{};

  Future<void> _proposeTogether(String activityId, {required bool allowed}) async {
    final strings = TogetherStrings.of(context);
    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.friendsOnly)),
      );
      return;
    }
    if (_togetherLoading[activityId] == true) return;
    final done = _togetherRoomIds[activityId];
    setState(() => _togetherLoading[activityId] = true);
    try {
      final roomId = done ??
          await TogetherService.instance.propose(
            targetUid: widget.userId,
            activityId: activityId,
          );
      if (!mounted) return;
      setState(() {
        _togetherRoomIds[activityId] = roomId;
        _togetherLoading[activityId] = false;
      });
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => SnackChatScreen(snackChatId: roomId),
        ),
      );
    } on TogetherProposeException catch (error) {
      if (!mounted) return;
      setState(() => _togetherLoading[activityId] = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            switch (error.reason) {
              TogetherProposeFailure.notFriends => strings.friendsOnly,
              TogetherProposeFailure.tooMany => strings.tooMany,
              _ => strings.failed,
            },
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _togetherLoading[activityId] = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.failed)),
      );
    }
  }

  /// [답하기]: DM을 열고 입력창에 질문을 인용해 둔다(자동 전송하지 않는다).
  void _answerQuestion(String question) {
    if (_isDeletedAccount) return;
    final conversationId = _dmService.generateConversationId(
      widget.userId,
      isOtherUserAnonymous: false,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DMChatScreen(
          conversationId: conversationId,
          otherUserId: widget.userId,
          initialDraftText: '“$question”\n',
        ),
      ),
    );
  }

  Widget _buildSocialProfileDetails(
    SocialProfileData profile, {
    required bool showSchoolInfo,
    required bool canPropose,
  }) {
    final languageCode = Localizations.localeOf(context).languageCode;
    final zh = isChineseUi(context);
    final strings = TogetherStrings.of(context);
    final nickname = (_userData?['nickname'] ?? widget.nickname ?? '').toString();
    final horizontalPadding =
        MediaQuery.sizeOf(context).width < 360 ? 16.0 : 20.0;
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
    String label(String id, List<SocialProfileOption> catalog) =>
        SocialProfileCatalog.labelFor(id, catalog, languageCode);

    final sections = <Widget>[];
    if (profile.interests.isNotEmpty) {
      sections.add(Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              zh ? '最近感兴趣' : languageCode == 'ko' ? '요즘 관심 있는 것' : 'Into these days',
              style: style(12, FontWeight.w600, const Color(0xFF8A8A8A)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in profile.interests)
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '#${label(id, SocialProfileCatalog.interests)}',
                      style: style(13, FontWeight.w400, const Color(0xFF333333)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ));
    }
    if (profile.preferredActivities.isNotEmpty) {
      sections.add(Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.sectionTitle,
                    style: style(12, FontWeight.w600, const Color(0xFF8A8A8A)),
                  ),
                ),
                if (canPropose)
                  Flexible(
                    child: Text(
                      strings.hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style(11, FontWeight.w400, const Color(0xFF9A9A9A)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in profile.preferredActivities)
                  _TogetherChip(
                    key: ValueKey<String>('together_chip_$id'),
                    label: label(id, SocialProfileCatalog.activities),
                    loading: _togetherLoading[id] == true,
                    done: _togetherRoomIds.containsKey(id),
                    enabled: canPropose,
                    onTap: () => unawaited(
                      _proposeTogether(id, allowed: canPropose),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ));
    }
    if (profile.conversationStarter.isNotEmpty) {
      sections.add(Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    zh
                        ? '$nickname的提问'
                        : languageCode == 'ko'
                            ? '$nickname의 질문'
                            : "$nickname's question",
                    style: style(12, FontWeight.w600, const Color(0xFF8A8A8A)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile.conversationStarter,
                    key: const ValueKey('profile_question'),
                    style: style(15, FontWeight.w600, const Color(0xFF111827),
                        line: 21),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              key: const ValueKey('profile_answer_button'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _answerQuestion(profile.conversationStarter),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    zh ? '回答' : languageCode == 'ko' ? '답하기' : 'Answer',
                    style: style(13, FontWeight.w600, const Color(0xFF2C6BC0)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ));
    }
    if (sections.isEmpty) return const SizedBox.shrink();
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: sections,
        ),
      ),
    );
  }

  /// 함께 아는 친구 한 줄: 얼굴 4개 + `A, B 외 n명과 함께 아는 친구` + `›`.
  Widget _buildFriendPreviewSection() {
    final preview = _friendPreview;
    if (_isFriendPreviewLoading || preview == null) {
      return const SizedBox.shrink();
    }
    final mutual = preview.friends.where((m) => m.isMutual).toList();
    final count = preview.mutualCount;
    if (count <= 0) return const SizedBox.shrink();
    final languageCode = Localizations.localeOf(context).languageCode;
    final zh = isChineseUi(context);
    final names = mutual
        .take(2)
        .map((m) => m.profile.displayNameOrNickname)
        .where((n) => n.isNotEmpty)
        .toList();
    final rest = (count - names.length).clamp(0, 1 << 20);
    final joined = zh ? names.join('、') : names.join(', ');
    final text = names.isEmpty
        ? (zh
            ? '$count位共同好友'
            : languageCode == 'ko'
                ? '함께 아는 친구 $count명'
                : '$count mutual friends')
        : rest > 0
            ? (zh
                ? '$joined等$rest人是共同好友'
                : languageCode == 'ko'
                    ? '$joined 외 $rest명과 함께 아는 친구'
                    : '$joined and $rest more mutual friends')
            : (zh
                ? '$joined是共同好友'
                : languageCode == 'ko'
                    ? '$joined님과 함께 아는 친구'
                    : '$joined are mutual friends');
    final horizontalPadding =
        MediaQuery.sizeOf(context).width < 360 ? 16.0 : 20.0;
    final faces = mutual.take(4).toList();
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: InkWell(
        key: const ValueKey('profile_mutual_row'),
        onTap: _navigateToFriendsList,
        child: Container(
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(
            children: [
              SizedBox(
                width: faces.isEmpty ? 0 : 24.0 + (faces.length - 1) * 18,
                height: 24,
                child: Stack(
                  children: [
                    for (var i = 0; i < faces.length; i++)
                      Positioned(
                        left: i * 18.0,
                        child: GroupMemberAvatar(
                          member: GroupMember(
                            uid: faces[i].profile.uid,
                            name: faces[i].profile.displayNameOrNickname,
                            photoUrl: faces[i].profile.photoURL ?? '',
                          ),
                          size: 24,
                        ),
                      ),
                  ],
                ),
              ),
              if (faces.isNotEmpty) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 12,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: Color(0xFFB0B0B0)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReviewPreviewSection() {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    if (_isReviewPreviewLoading) {
      return const _ProfileSectionSkeleton(height: 190);
    }
    final horizontalPadding =
        MediaQuery.sizeOf(context).width < 360 ? 16.0 : 20.0;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (isChineseUi(context) ? '一起聚会的瞬间' : isKo ? '함께한 모임 후기' : 'Meetup moments together'),
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 14),
            if (_reviewPreview.isEmpty)
              Text(
                (isChineseUi(context) ? '暂无公开聚会回顾。' : isKo ? '아직 공개된 모임 후기가 없어요.' : 'No public meetup reviews yet.'),
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 13,
                  color: Color(0xFF94A3B8),
                ),
              )
            else
              ..._reviewPreview.map(_buildReviewPreviewItem),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewPreviewItem(ReviewPost review) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final date = '${review.createdAt.year}.'
        '${review.createdAt.month.toString().padLeft(2, '0')}.'
        '${review.createdAt.day.toString().padLeft(2, '0')}';
    final role = review.participationRole == 'host'
        ? ((isChineseUi(context) ? '发起人' : isKo ? '모임장' : 'Host'))
        : ((isChineseUi(context) ? '参与者' : isKo ? '참여자' : 'Participant'));
    final imageSize = MediaQuery.sizeOf(context).width < 360 ? 68.0 : 76.0;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReviewDetailScreen(review: review)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: imageSize,
                height: imageSize,
                child: review.imageUrls.isNotEmpty
                    ? Image.network(
                        review.imageUrls.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _buildCompactReviewPlaceholder(),
                      )
                    : _buildCompactReviewPlaceholder(),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    review.meetupTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: ['NotoSansKR'],
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${review.category} · $date · $role',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: ['NotoSansKR'],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  if (review.content.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      review.content.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: ['NotoSansKR'],
                        fontSize: 12,
                        height: 1.35,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactReviewPlaceholder() {
    return const ColoredBox(
      color: Color(0xFFF1F5F9),
      child: Icon(Icons.groups_2_outlined, color: Color(0xFF94A3B8)),
    );
  }

  Widget _buildReviewPlaceholder(ReviewPost review) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.rate_review, size: 28, color: Colors.grey[400]), // 24 → 28
          const SizedBox(height: 6), // 4 → 6
          Text(
            review.meetupTitle,
            style: TextStyle(
              fontSize: 12, // 10 → 12
              color: Colors.grey[600],
              fontWeight: FontWeight.w500, // 굵기 추가
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
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
            heroTag: 'profile_image_${widget.userId}',
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

  /// 친구 목록 화면으로 이동
  Future<void> _navigateToFriendsList() async {
    final nickname = _userData?['nickname'] ??
        widget.nickname ??
        AppLocalizations.of(context)!.user;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserFriendsListScreen(
          userId: widget.userId,
          userName: nickname,
        ),
      ),
    );
    if (mounted) {
      await _loadLatestStats();
    }
  }

  /// DM 대화방 열기
  Future<void> _openDM() async {
    if (_isDeletedAccount) return;
    try {
      // Firebase Auth UID 형식 검증 (20~30자 영숫자, 언더스코어 포함 가능)
      final uidPattern = RegExp(r'^[a-zA-Z0-9_-]{20,30}$');
      if (!uidPattern.hasMatch(widget.userId)) {
        if (Logger.isVerboseEnabled) {
          Logger.log(
              '❌ 잘못된 userId 형식: ${widget.userId} (길이: ${widget.userId.length}자)');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('이 사용자에게는 메시지를 보낼 수 없습니다'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // 대화방 ID 생성 (실제 생성은 메시지 전송 시)
      final conversationId = _dmService.generateConversationId(
        widget.userId,
        isOtherUserAnonymous: false,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DMChatScreen(
              conversationId: conversationId,
              otherUserId: widget.userId,
            ),
          ),
        );
      }
    } catch (e) {
      Logger.error('❌ DM 열기 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.cannotSendDM ?? ""),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}

class _ProfileSectionSkeleton extends StatelessWidget {
  const _ProfileSectionSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 132,
              height: 16,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}

/// 같이하기 제안 버튼: 높이 34, 끝에 ↗ 원. 성공하면 파란 바탕으로 바뀐다.
class _TogetherChip extends StatelessWidget {
  const _TogetherChip({
    super.key,
    required this.label,
    required this.loading,
    required this.done,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final bool done;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 200);
    final background = done
        ? const Color(0xFF2C6BC0)
        : (enabled ? const Color(0xFFF2F7FD) : const Color(0xFFF2F2F2));
    final foreground = done
        ? Colors.white
        : (enabled ? const Color(0xFF0D2A52) : const Color(0xFF9A9A9A));
    final circle = done
        ? Colors.white
        : (enabled ? const Color(0xFF2C6BC0) : const Color(0xFFC8C8C8));
    return Semantics(
      button: true,
      enabled: !loading,
      label: label,
      excludeSemantics: true,
      child: MotionPress(
        enabled: !loading,
        pressedScale: .96,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: loading ? null : onTap,
          child: AnimatedContainer(
            duration: duration,
            height: 34,
            padding: const EdgeInsets.only(left: 13, right: 5),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: duration,
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: circle,
                    shape: BoxShape.circle,
                  ),
                  child: loading
                      ? Padding(
                          padding: const EdgeInsets.all(6),
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: done ? const Color(0xFF2C6BC0) : Colors.white,
                          ),
                        )
                      : AnimatedRotation(
                          turns: done ? .125 : 0,
                          duration: duration,
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            size: 12,
                            color: done ? const Color(0xFF2C6BC0) : Colors.white,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
