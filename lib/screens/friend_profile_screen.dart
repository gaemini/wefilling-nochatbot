// lib/screens/friend_profile_screen.dart
// 친구 프로필 화면
// 참여한 후기만 표시

import 'package:flutter/material.dart';
import '../services/user_stats_service.dart';
import '../services/review_service.dart';
import '../models/review_post.dart';
import '../constants/app_constants.dart';
import '../design/tokens.dart';
import '../widgets/country_flag_circle.dart'; // 국기 위젯 추가
import '../l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'review_detail_screen.dart';
import '../utils/country_flag_helper.dart';

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
  
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

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
      }
    } catch (e) {
      print('사용자 데이터 로드 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.profile,
          style: AppTheme.headlineMedium.copyWith(
            color: const Color(0xFF4A90E2), // 위필링 로고색
          ),
        ),
        backgroundColor: AppTheme.backgroundPrimary,
        foregroundColor: const Color(0xFF4A90E2), // 위필링 로고색
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: AppTheme.backgroundPrimary,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildProfileHeader(),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center, // 중앙 정렬 추가
                    children: [
                      Icon(Icons.grid_on_rounded, size: 20, color: const Color(0xFF4A90E2)), // 위필링 로고색
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context)!.participatedReviews,
                        style: AppTheme.labelMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF4A90E2), // 위필링 로고색
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _buildReviewGrid(),
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

    return Container(
      padding: const EdgeInsets.all(20.0),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 프로필 이미지와 정보 (마이 프로필과 동일한 왼쪽 정렬)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 프로필 이미지 (88px)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.black,
                    width: 3,
                  ),
                ),
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.backgroundPrimary,
                  ),
                  child: photoURL != null
                      ? ClipOval(
                          child: Image.network(
                            photoURL,
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.person,
                              size: 44,
                              color: const Color(0xFF4A90E2), // 위필링 로고색
                            ),
                          ),
                        )
                      : Icon(
                          Icons.person,
                          size: 44,
                          color: const Color(0xFF4A90E2), // 위필링 로고색
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
                              CountryFlagHelper.getCountryInfo(nationality)?.getLocalizedName(
                                Localizations.localeOf(context).languageCode
                              ) ?? nationality,
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
                    // 한 줄 소개 (상태메세지)
                    if (_userData?['bio'] != null && (_userData!['bio'] as String).isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _userData!['bio'],
                        style: AppTheme.bodyMedium.copyWith(
                          color: Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
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

          // 통계 정보 (카드 형태 - 마이 프로필과 동일 스타일)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(AppLocalizations.of(context)!.hostedMeetups, widget.userId, icon: Icons.event_available, color: Colors.black),
                Container(width: 1, height: 36, color: Colors.black),
                _buildStatItem(AppLocalizations.of(context)!.joinedMeetups, widget.userId, isJoined: true, icon: Icons.groups, color: Colors.black),
                Container(width: 1, height: 36, color: Colors.black),
                _buildStatItem(AppLocalizations.of(context)!.writtenPosts, widget.userId, isPosts: true, icon: Icons.article, color: Colors.black),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String userId, {
    bool isJoined = false,
    bool isPosts = false,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 8),
          StreamBuilder<int>(
            stream: isJoined
                ? _userStatsService.getJoinedMeetupCountForUser(userId)
                : isPosts
                    ? _userStatsService.getUserPostCountForUser(userId)
                    : _userStatsService.getHostedMeetupCountForUser(userId),
            builder: (context, snapshot) {
              return Text(
                '${snapshot.data ?? 0}',
                style: AppTheme.headlineMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 24,
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              color: Colors.black87,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReviewGrid() {
    return StreamBuilder<List<ReviewPost>>(
      stream: _reviewService.getUserReviewsStream(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
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
          );
        }

        final reviews = snapshot.data ?? [];

        if (reviews.isEmpty) {
          return Center(
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
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
            childAspectRatio: 1,
          ),
          itemCount: reviews.length,
          itemBuilder: (context, index) {
            final review = reviews[index];
            return _buildReviewGridItem(review);
          },
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

}

