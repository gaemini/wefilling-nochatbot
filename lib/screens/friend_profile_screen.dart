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
import 'package:cloud_firestore/cloud_firestore.dart';

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
          '프로필',
          style: AppTheme.headlineMedium.copyWith(
            color: AppTheme.primary,
          ),
        ),
        backgroundColor: AppTheme.backgroundPrimary,
        foregroundColor: AppTheme.primary,
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
                      Icon(Icons.grid_on_rounded, size: 20, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '참여한 후기',
                        style: AppTheme.labelMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
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
    final nickname = _userData?['nickname'] ?? widget.nickname ?? '사용자';
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
        children: [
          // 프로필 이미지와 정보 (중앙 정렬)
          Column(
            children: [
              // 프로필 이미지
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(4),
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.backgroundPrimary,
                  ),
                  child: photoURL != null
                      ? ClipOval(
                          child: Image.network(
                            photoURL,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.person,
                              size: 50,
                              color: AppTheme.primary,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.person,
                          size: 50,
                          color: AppTheme.primary,
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // 사용자 정보
              Text(
                nickname,
                style: AppTheme.headlineMedium.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (nationality != null && nationality.isNotEmpty) ...[
                    CountryFlagCircle(
                      nationality: nationality,
                      size: 28, // 국기 크기
                    ),
                    const SizedBox(width: 8), // 간격
                    Text(
                      nationality,
                      style: AppTheme.bodyMedium.copyWith(
                        color: Colors.black54,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (university != null) ...[
                      const SizedBox(width: 8),
                      Text('•', style: TextStyle(color: Colors.black54)),
                      const SizedBox(width: 8),
                    ],
                  ],
                  if (university != null)
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.school, size: 22, color: Colors.black54), // 16 → 22
                          const SizedBox(width: 6), // 4 → 6
                          Flexible(
                            child: Text(
                              university,
                              style: AppTheme.bodyMedium.copyWith(
                                color: Colors.black54,
                                fontSize: 15, // 14 → 15
                                fontWeight: FontWeight.w500, // 굵기 추가
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 20),

          // 통계 정보 (카드 형태)
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('주최한 모임', widget.userId, icon: Icons.event_available, color: Colors.blue),
                Container(width: 1, height: 40, color: Colors.grey[300]),
                _buildStatItem('참여한 모임', widget.userId, isJoined: true, icon: Icons.groups, color: Colors.green),
                Container(width: 1, height: 40, color: Colors.grey[300]),
                _buildStatItem('작성한 글', widget.userId, isPosts: true, icon: Icons.article, color: Colors.orange),
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
                  '후기를 불러올 수 없습니다',
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
                  '아직 작성한 후기가 없습니다',
                  style: AppTheme.bodyMedium.copyWith(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '모임에 참여하고 후기를 작성해보세요!',
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
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
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
        // 후기 상세 보기 (선택사항)
        _showReviewDetail(review);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(4),
        ),
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

  void _showReviewDetail(ReviewPost review) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: const Text('후기'),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.meetupTitle,
                        style: const TextStyle(
                          fontSize: 20, // 18 → 20
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10), // 8 → 10
                      Text(
                        '평점: ${'⭐' * review.rating}',
                        style: const TextStyle(fontSize: 18), // 16 → 18
                      ),
                      const SizedBox(height: 16),
                      Text(
                        review.content,
                        style: const TextStyle(
                          fontSize: 15, // 명시적 크기 지정
                          height: 1.5, // 줄 높이 추가
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (review.imageUrls.isNotEmpty)
                        ...review.imageUrls.map((url) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Image.network(url),
                            )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

