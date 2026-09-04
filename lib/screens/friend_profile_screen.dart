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
import 'social_tag_people_screen.dart';
import '../utils/account_status_helper.dart';

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
              isKo ? '프로필을 불러오지 못했어요' : 'Unable to load profile',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isKo ? '잠시 후 다시 시도해 주세요.' : 'Please try again in a moment.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: _retryProfileLoad,
              icon: const Icon(Icons.refresh_rounded, size: 19),
              label: Text(isKo ? '다시 시도' : 'Retry'),
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
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isKo
                  ? '탈퇴하여 더 이상 조회할 수 없는 계정입니다.'
                  : 'This account is no longer available.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
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
              isKo ? '프로필을 볼 수 없어요' : 'Profile unavailable',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isKo
                  ? '차단 관계에서는 프로필과 친구 목록이 표시되지 않아요.'
                  : 'Profiles and friend lists are hidden when an account is blocked.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
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
        (_userData?['university'] ?? widget.university)?.toString().trim();
    final isSchoolVerified = isHanyangEmailVerified(_userData);
    final nationality = _userData?['nationality'];
    final bio = _userData?['bio'];
    final social = SocialProfileData.fromMap(_userData);
    final l10n = AppLocalizations.of(context)!;
    final currentUserId = _relationshipService.currentUserId;
    final isMe = currentUserId != null && currentUserId == widget.userId;
    final isFriends = _relationshipStatus == RelationshipStatus.friends;
    final status = _relationshipStatus ?? RelationshipStatus.none;
    final canRequest = status == RelationshipStatus.none;
    final isPending = status == RelationshipStatus.pendingOut;
    final hasIncomingRequest = status == RelationshipStatus.pendingIn;

    final horizontalPadding =
        MediaQuery.sizeOf(context).width < 360 ? 16.0 : 20.0;
    return Container(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        16,
        horizontalPadding,
        20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 프로필 이미지와 정보 (마이 프로필과 동일한 왼쪽 정렬)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 프로필 이미지 (88px) - 탭 가능
              GestureDetector(
                onTap: photoURL != null && photoURL.isNotEmpty
                    ? () => _openProfileImageViewer(photoURL)
                    : null,
                child: Hero(
                  tag: 'profile_image_${widget.userId}',
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // 사진이 있을 때만 탭 가능한 느낌을 주는 그림자 추가
                      boxShadow: photoURL != null && photoURL.isNotEmpty
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFE5E7EB),
                      ),
                      child: photoURL != null && photoURL.isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                photoURL,
                                width: 88,
                                height: 88,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person,
                                  size: 44,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.person,
                              size: 44,
                              color: Color(0xFF6B7280),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // 사용자 정보 (오른쪽)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nickname,
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
                    // 한 줄 소개 (Bio)
                    if (bio != null && bio.toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        bio.toString(),
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
                    if ((university?.isNotEmpty ?? false) ||
                        isSchoolVerified) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            isSchoolVerified
                                ? Icons.verified_rounded
                                : Icons.school_outlined,
                            size: 18,
                            color: isSchoolVerified
                                ? AppColors.pointColor
                                : Colors.black54,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${(university?.isNotEmpty ?? false) ? university : 'Hanyang University'}${isSchoolVerified ? ' · ${Localizations.localeOf(context).languageCode == 'ko' ? '인증됨' : 'Verified'}' : ''}',
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

          if (social.interests.isNotEmpty ||
              social.preferredActivities.isNotEmpty ||
              social.friendshipPrompt.isNotEmpty ||
              social.conversationStarter.isNotEmpty ||
              (isSchoolVerified &&
                  social.showDepartment &&
                  social.department.isNotEmpty) ||
              (isSchoolVerified &&
                  social.showGrade &&
                  social.grade.isNotEmpty)) ...[
            const SizedBox(height: 24),
            _buildSocialProfileDetails(
              social,
              showSchoolInfo: isSchoolVerified,
            ),
          ],

          const SizedBox(height: 20),

          // 통계 정보 (마이 프로필과 동일)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 친구 수 - 클릭 가능
              Expanded(
                child: InkWell(
                  onTap: _navigateToFriendsList,
                  borderRadius: BorderRadius.circular(8),
                  child: _buildStatItemContent(
                    AppLocalizations.of(context)!.friends,
                    cacheKey: 'friend_profile_friends',
                    isFriends: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildStatItem(
                AppLocalizations.of(context)!.joinedMeetups,
                cacheKey: 'friend_profile_joined_meetups',
                isJoined: true,
              ),
              const SizedBox(width: 8),
              _buildStatItem(
                AppLocalizations.of(context)!.writtenPosts,
                cacheKey: 'friend_profile_written_posts',
                isPosts: true,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 보드/댓글 진입(비친구 프리뷰)에서는 DM 대신 "친구요청" 버튼을 DM 자리로 노출
          if (isNonFriendPreview)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: (!canRequest || _isRequestingFriend)
                    ? null
                    : _sendFriendRequestFromProfile,
                icon: _isRequestingFriend
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1, size: 20),
                label: Text(
                  isPending
                      ? l10n.requestPending
                      : hasIncomingRequest
                          ? (Localizations.localeOf(context).languageCode ==
                                  'ko'
                              ? '받은 친구 요청이 있어요'
                              : 'Friend request received')
                          : l10n.friendRequest,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.pointColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                  disabledForegroundColor: const Color(0xFF9CA3AF),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          else
            // 친구(또는 본인) 화면은 기존 DM 버튼 유지
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _openDM,
                icon: const Icon(Icons.message, size: 20),
                label: Text(
                  AppLocalizations.of(context)!.sendMessage,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF3F4F6),
                  foregroundColor: const Color(0xFF111827),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSocialProfileDetails(
    SocialProfileData profile, {
    required bool showSchoolInfo,
  }) {
    final languageCode = Localizations.localeOf(context).languageCode;

    Widget tags({
      required String title,
      required List<String> ids,
      required List<SocialProfileOption> catalog,
      required SocialProfileTagKind kind,
    }) {
      if (ids.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 7,
            children: ids.map(
              (id) {
                final label = SocialProfileCatalog.labelFor(
                  id,
                  catalog,
                  languageCode,
                );
                return Semantics(
                  button: true,
                  label: '#$label',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openSocialTagPeople(id, kind),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 7,
                        ),
                        child: Text(
                          '#$label',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.pointColor,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ).toList(growable: false),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSchoolInfo &&
            ((profile.showDepartment && profile.department.isNotEmpty) ||
                (profile.showGrade && profile.grade.isNotEmpty)))
          Row(
            children: [
              const Icon(Icons.verified_outlined,
                  size: 18, color: AppColors.pointColor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  [
                    if (profile.showDepartment) profile.department,
                    if (profile.showGrade) profile.grade,
                  ].where((value) => value.isNotEmpty).join(' · '),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
        if (profile.interests.isNotEmpty) ...[
          const SizedBox(height: 18),
          tags(
            title: languageCode == 'ko' ? '요즘 관심 있는 것' : 'Into these days',
            ids: profile.interests,
            catalog: SocialProfileCatalog.interests,
            kind: SocialProfileTagKind.interest,
          ),
        ],
        if (profile.preferredActivities.isNotEmpty) ...[
          const SizedBox(height: 18),
          tags(
            title: languageCode == 'ko' ? '같이 하고 싶은 것' : 'Let\'s do together',
            ids: profile.preferredActivities,
            catalog: SocialProfileCatalog.activities,
            kind: SocialProfileTagKind.activity,
          ),
        ],
        if (profile.friendshipPrompt.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            profile.friendshipPrompt,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
              height: 1.45,
            ),
          ),
        ],
        if (profile.conversationStarter.isNotEmpty) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  languageCode == 'ko'
                      ? '그대에게 물어보고 싶어요'
                      : "I'd like to ask you",
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: ['NotoSansKR'],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  profile.conversationStarter,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: ['NotoSansKR'],
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _openSocialTagPeople(String tagId, SocialProfileTagKind kind) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SocialTagPeopleScreen(tagId: tagId, kind: kind),
      ),
    );
  }

  Widget _buildFriendPreviewSection() {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    if (_isFriendPreviewLoading) {
      return const _ProfileSectionSkeleton(height: 150);
    }
    final preview = _friendPreview;
    if (preview == null) return const SizedBox.shrink();

    final horizontalPadding =
        MediaQuery.sizeOf(context).width < 360 ? 16.0 : 20.0;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isKo ? '친구' : 'Friends',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: ['NotoSansKR'],
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _navigateToFriendsList,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF475569),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(44, 36),
                  ),
                  child: Text(
                    isKo ? '전체 보기' : 'View all',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: ['NotoSansKR'],
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              isKo
                  ? '친구 ${preview.totalCount}명'
                      '${preview.mutualCount > 0 ? ' · 함께 아는 친구 ${preview.mutualCount}명' : ''}'
                  : '${preview.totalCount} friends'
                      '${preview.mutualCount > 0 ? ' · ${preview.mutualCount} mutual' : ''}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 14),
            if (preview.friends.isEmpty)
              Text(
                isKo ? '공개된 친구가 아직 없어요.' : 'No public friends yet.',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 13,
                  color: Color(0xFF94A3B8),
                ),
              )
            else
              SizedBox(
                height: 82,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: preview.friends.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final member = preview.friends[index];
                    return _buildFriendPreviewMember(member);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendPreviewMember(ProfileFriendNetworkMember member) {
    final profile = member.profile;
    return Semantics(
      button: true,
      label: profile.displayNameOrNickname,
      child: InkWell(
        onTap: () => _openFriendFromPreview(profile),
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 62,
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: const Color(0xFFF1F5F9),
                    backgroundImage: profile.hasProfileImage
                        ? NetworkImage(profile.photoURL!)
                        : null,
                    child: profile.hasProfileImage
                        ? null
                        : const Icon(Icons.person_outline_rounded,
                            color: Color(0xFF94A3B8)),
                  ),
                  if (member.isMutual)
                    const Positioned(
                      right: -2,
                      bottom: -1,
                      child: CircleAvatar(
                        radius: 8,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.people_alt_rounded,
                            size: 11, color: AppColors.pointColor),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                profile.displayNameOrNickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFriendFromPreview(UserProfile profile) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          userId: profile.uid,
          nickname: profile.displayNameOrNickname,
          photoURL: profile.photoURL,
          university: profile.university,
          allowNonFriendsPreview: true,
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
              isKo ? '함께한 모임 후기' : 'Meetup moments together',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 14),
            if (_reviewPreview.isEmpty)
              Text(
                isKo ? '아직 공개된 모임 후기가 없어요.' : 'No public meetup reviews yet.',
                style: const TextStyle(
                  fontFamily: 'Inter',
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
        ? (isKo ? '모임장' : 'Host')
        : (isKo ? '참여자' : 'Participant');
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
                    style: const TextStyle(
                      fontFamily: 'Inter',
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
                    style: const TextStyle(
                      fontFamily: 'Inter',
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
                      style: const TextStyle(
                        fontFamily: 'Inter',
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

  Widget _buildStatItem(
    String label, {
    required String cacheKey,
    bool isJoined = false,
    bool isPosts = false,
    bool isFriends = false,
  }) {
    return Expanded(
      child: _buildStatItemContent(
        label,
        cacheKey: cacheKey,
        isJoined: isJoined,
        isPosts: isPosts,
        isFriends: isFriends,
      ),
    );
  }

  Widget _buildStatItemContent(
    String label, {
    required String cacheKey,
    bool isJoined = false,
    bool isPosts = false,
    bool isFriends = false,
  }) {
    final latestValue = isFriends
        ? _profileStats?.friendCount
        : isJoined
            ? _profileStats?.joinedMeetupCount
            : isPosts
                ? _profileStats?.writtenPostCount
                : null;
    final value = latestValue ?? _statCountCache[cacheKey];
    final Widget countWidget = value != null
        ? Text(
            '$value',
            key: ValueKey<String>('count_$cacheKey:$value'),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
              fontSize: 20,
            ),
          )
        : const Text(
            '—',
            key: ValueKey<String>('count_loading'),
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontWeight: FontWeight.w700,
              color: Color(0xFF9CA3AF),
              fontSize: 20,
            ),
          );

    return Column(
      children: [
        AnimatedSwitcher(
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
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            color: Color(0xFF6B7280),
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildReviewGridSliver() {
    return StreamBuilder<List<ReviewPost>>(
      stream: _reviewService.getUserReviewsStream(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.cannotLoadReviews,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
        }

        final reviews = snapshot.data ?? [];

        if (reviews.isEmpty) {
          return SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.photo_library_outlined,
                      size: 32,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.noReviewsYet,
                    style: AppTheme.bodyMedium.copyWith(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppLocalizations.of(context)!.joinMeetupAndWriteReview,
                    style: AppTheme.bodySmall.copyWith(
                      color: Colors.grey[500],
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.all(4),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final review = reviews[index];
                return _buildReviewGridItem(review);
              },
              childCount: reviews.length,
            ),
          ),
        );
      },
    );
  }

  Widget _buildReviewGridItem(ReviewPost review) {
    return GestureDetector(
      onTap: () {
        // 후기 상세 화면으로 이동 (댓글, 좋아요 기능 포함)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReviewDetailScreen(review: review),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          children: [
            // 이미지 또는 플레이스홀더
            Positioned.fill(
              child: review.imageUrls.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        review.imageUrls.first,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildReviewPlaceholder(review);
                        },
                      ),
                    )
                  : _buildReviewPlaceholder(review),
            ),

            // 좋아요 및 댓글 수 표시
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite, color: Colors.white, size: 12),
                    const SizedBox(width: 3),
                    Text(
                      '${review.likeCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.comment, color: Colors.white, size: 12),
                    const SizedBox(width: 3),
                    Text(
                      '${review.commentCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
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
