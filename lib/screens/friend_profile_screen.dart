// lib/screens/friend_profile_screen.dart
// 친구 프로필 화면
// 참여한 후기만 표시

import 'package:flutter/material.dart';
import '../services/user_stats_service.dart';
import '../services/review_service.dart';
import '../services/dm_service.dart';
import '../models/review_post.dart';
import '../constants/app_constants.dart';
import '../design/tokens.dart';
import '../widgets/country_flag_circle.dart'; // 국기 위젯 추가
import '../l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'review_detail_screen.dart';
import 'dm_chat_screen.dart';
import '../utils/country_flag_helper.dart';
import '../utils/logger.dart';
import '../ui/widgets/profile_image_viewer.dart';
import 'user_friends_list_screen.dart';

class FriendProfileScreen extends StatefulWidget {
  final String userId;
  final String? nickname;
  final String? photoURL;
  final String? email;
  final String? university;

  const FriendProfileScreen({
    Key? key,
    required this.userId,
    this.nickname,
    this.photoURL,
    this.email,
    this.university,
  }) : super(key: key);

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  final UserStatsService _userStatsService = UserStatsService();
  final ReviewService _reviewService = ReviewService();
  final DMService _dmService = DMService();
  
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  // 통계 숫자 깜빡임/0 표시 방지용 캐시
  final Map<String, int> _statCountCache = {};

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      
      if (doc.exists && mounted) {
        setState(() {
          _userData = doc.data();
          _isLoading = false;
        });
      } else if (!doc.exists && mounted) {
        // 탈퇴한 사용자 처리
        Logger.log('⚠️ 탈퇴한 사용자: ${widget.userId}');
        setState(() {
          final deletedLabel = AppLocalizations.of(context)?.deletedAccount ?? '탈퇴한 계정';
          _userData = {
            'nickname': deletedLabel,
            'displayName': deletedLabel,
            'photoURL': '',
            'bio': '',
          };
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('사용자 데이터 로드 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 안드로이드 하단 네비게이션 바 높이 감지
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildProfileHeader()),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverToBoxAdapter(child: _buildParticipatedReviewsHeader()),
                const SliverToBoxAdapter(child: Divider(height: 1, color: Color(0xFFE5E7EB))),
                _buildReviewGridSliver(),
                // 안드로이드 하단 네비게이션 바를 위한 여백 추가
                SliverToBoxAdapter(
                  child: SizedBox(height: bottomPadding > 0 ? bottomPadding + 16 : 16),
                ),
              ],
            ),
    );
  }

  Widget _buildProfileHeader() {
    final nickname = _userData?['nickname'] ?? widget.nickname ?? AppLocalizations.of(context)!.user;
    final email = _userData?['email'] ?? widget.email ?? '';
    final photoURL = _userData?['photoURL'] ?? widget.photoURL;
    final university = _userData?['university'] ?? widget.university;
    final nationality = _userData?['nationality'];
    final bio = _userData?['bio'];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                              CountryFlagHelper.getCountryInfo(nationality)?.getLocalizedName(
                                Localizations.localeOf(context).languageCode
                              ) ?? nationality,
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
                    // 한 줄 소개 (Bio)
                    if (bio != null && bio.toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        bio.toString(),
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
                    if (university != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.school, size: 18, color: Colors.black54),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              university,
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
          
          const SizedBox(height: 20),

          // 통계 정보 (마이 프로필과 동일)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 친구 수 - 클릭 가능
              Expanded(
                child: InkWell(
                  onTap: () => _navigateToFriendsList(),
                  borderRadius: BorderRadius.circular(8),
                  child: _buildStatItemContent(
                    AppLocalizations.of(context)!.friends,
                    widget.userId,
                    cacheKey: 'friend_profile_friends',
                    isFriends: true,
                  ),
                ),
              ),
              Container(width: 1, height: 50, color: const Color(0xFFE5E7EB)),
              _buildStatItem(
                AppLocalizations.of(context)!.joinedMeetups,
                widget.userId,
                cacheKey: 'friend_profile_joined_meetups',
                isJoined: true,
              ),
              Container(width: 1, height: 50, color: const Color(0xFFE5E7EB)),
              _buildStatItem(
                AppLocalizations.of(context)!.writtenPosts,
                widget.userId,
                cacheKey: 'friend_profile_written_posts',
                isPosts: true,
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // DM 버튼 (마이 프로필의 "프로필 편집" 버튼과 동일한 스타일)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _openDM,
              icon: const Icon(Icons.message, size: 20),
              label: Flexible(
                child: Text(
                  AppLocalizations.of(context)!.sendMessage,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
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

  Widget _buildParticipatedReviewsHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.grid_on_rounded, size: 20, color: AppColors.pointColor),
          const SizedBox(width: 8),
          Text(
            AppLocalizations.of(context)!.participatedReviews,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontWeight: FontWeight.w600,
              color: AppColors.pointColor,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String userId, {
    required String cacheKey,
    bool isJoined = false,
    bool isPosts = false,
    bool isFriends = false,
  }) {
    return Expanded(
      child: _buildStatItemContent(
        label,
        userId,
        cacheKey: cacheKey,
        isJoined: isJoined,
        isPosts: isPosts,
        isFriends: isFriends,
      ),
    );
  }

  Widget _buildStatItemContent(
    String label,
    String userId, {
    required String cacheKey,
    bool isJoined = false,
    bool isPosts = false,
    bool isFriends = false,
  }) {
    return Column(
      children: [
        StreamBuilder<int>(
          stream: isFriends
              ? _userStatsService.getFriendCountForUser(userId)
              : isJoined
                  ? _userStatsService.getJoinedMeetupCountForUser(userId)
                  : isPosts
                      ? _userStatsService.getUserPostCountForUser(userId)
                      : _userStatsService.getHostedMeetupCountForUser(userId),
          initialData: _statCountCache[cacheKey],
          builder: (context, snapshot) {
            // 데이터 도착 전 0을 먼저 보여주지 않고(어색함), 캐시/플레이스홀더를 사용
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
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                      fontSize: 20,
                    ),
                  )
                : const Text(
                    '—',
                    key: ValueKey<String>('count_loading'),
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF9CA3AF),
                      fontSize: 20,
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
          },
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Pretendard',
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
                        fit: BoxFit.cover,
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
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: ProfileImageViewer(
              imageUrl: imageUrl,
              heroTag: 'profile_image_${widget.userId}',
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  /// 친구 목록 화면으로 이동
  void _navigateToFriendsList() {
    final nickname = _userData?['nickname'] ?? widget.nickname ?? AppLocalizations.of(context)!.user;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserFriendsListScreen(
          userId: widget.userId,
          userName: nickname,
        ),
      ),
    );
  }

  /// DM 대화방 열기
  Future<void> _openDM() async {
    try {
      // Firebase Auth UID 형식 검증 (20~30자 영숫자, 언더스코어 포함 가능)
      final uidPattern = RegExp(r'^[a-zA-Z0-9_-]{20,30}$');
      if (!uidPattern.hasMatch(widget.userId)) {
        Logger.log('❌ 잘못된 userId 형식: ${widget.userId} (길이: ${widget.userId.length}자)');
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

