// lib/screens/review_detail_screen.dart
// 후기 상세 화면 - 좋아요, 댓글 기능 포함

import 'package:flutter/material.dart';
import '../models/review_post.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import '../services/review_service.dart';
import '../services/meetup_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'review_comments_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../ui/widgets/fullscreen_image_viewer.dart';
import '../utils/logger.dart';

class ReviewDetailScreen extends StatefulWidget {
  final ReviewPost review;

  const ReviewDetailScreen({
    Key? key,
    required this.review,
  }) : super(key: key);

  @override
  State<ReviewDetailScreen> createState() => _ReviewDetailScreenState();
}

class _ReviewDetailScreenState extends State<ReviewDetailScreen> {
  final ReviewService _reviewService = ReviewService();
  final MeetupService _meetupService = MeetupService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLiking = false;
  List<Map<String, dynamic>> _participants = [];
  int _currentImageIndex = 0; // 현재 이미지 인덱스
  final PageController _pageController = PageController();
  
  @override
  void initState() {
    super.initState();
    _loadParticipants();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
  

  Future<void> _loadParticipants() async {
    try {
      Logger.log('🔍 참여자 로드 시작: meetupId=${widget.review.meetupId}');

      // 항상 meetup_participants(approved) 기준으로 참여자 로드하고,
      // 호스트 ID는 meetup_reviews 또는 meetups에서 가져와 결합한다.

      String? hostId;

      // 1) meetup_reviews에서 호스트 확인
      if (widget.review.sourceReviewId != null && widget.review.sourceReviewId!.isNotEmpty) {
        try {
          final reviewDoc = await _firestore
              .collection('meetup_reviews')
              .doc(widget.review.sourceReviewId)
              .get();
          if (reviewDoc.exists) {
            hostId = (reviewDoc.data() ?? const {})['authorId'] as String?;
            Logger.log('📝 meetup_reviews에서 호스트 확인: $hostId');
          }
        } catch (e) {
          Logger.error('⚠️ meetup_reviews 조회 실패(무시하고 계속): $e');
        }
      }

      // 2) 없으면 meetups에서 호스트 확인
      if (hostId == null && widget.review.meetupId.isNotEmpty) {
        try {
          final meetupDoc = await _firestore
              .collection('meetups')
              .doc(widget.review.meetupId)
              .get();
          if (meetupDoc.exists) {
            hostId = (meetupDoc.data() ?? const {})['userId'] as String?;
            Logger.log('📋 meetups에서 호스트 확인: $hostId');
          }
        } catch (e) {
          Logger.error('⚠️ meetups 조회 실패(무시하고 계속): $e');
        }
      }

      // 3) meetup_participants에서 승인된 참여자 모두 가져오기
      final participantsQuery = await _firestore
          .collection('meetup_participants')
          .where('meetupId', isEqualTo: widget.review.meetupId)
          .where('status', isEqualTo: 'approved')
          .get();

      final participantsList = <Map<String, dynamic>>[];
      final added = <String>{};

      // 호스트 우선 추가
      if (hostId != null && hostId!.isNotEmpty) {
        await _addParticipantInfo(participantsList, hostId!, true);
        added.add(hostId!);
      }

      // 승인된 참여자 추가 (중복 제외)
      for (final doc in participantsQuery.docs) {
        final data = doc.data();
        final userId = data['userId'] as String?;
        if (userId == null || userId.isEmpty) continue;
        if (added.contains(userId)) continue;
        await _addParticipantInfo(participantsList, userId, false);
        added.add(userId);
      }

      if (mounted) {
        setState(() {
          _participants = participantsList;
        });
        Logger.log('✅ 참여자 ${_participants.length}명 로드 완료 (호스트 포함)');
      }
    } catch (e) {
      Logger.error('❌ 참여자 로드 오류: $e');
    }
  }
  
  Future<void> _processParticipants(Map<String, dynamic> reviewData) async {
    final authorId = reviewData['authorId'] as String;
    final approvedParticipants = List<String>.from(reviewData['approvedParticipants'] ?? []);
    
    Logger.log('👥 호스트: $authorId');
    Logger.log('👥 수락한 참여자: ${approvedParticipants.length}명');
    Logger.log('📋 수락한 참여자 ID 목록: $approvedParticipants');
    
    // 모든 참여자 ID (호스트 + 수락한 참여자)
    final allParticipantIds = [authorId, ...approvedParticipants];
    Logger.log('📋 전체 참여자 ID 목록 (${allParticipantIds.length}명): $allParticipantIds');
    
    // 각 참여자의 정보 가져오기
    final participantsList = <Map<String, dynamic>>[];
    
    for (int i = 0; i < allParticipantIds.length; i++) {
      final userId = allParticipantIds[i];
      Logger.log('🔄 [${i + 1}/${allParticipantIds.length}] 참여자 처리 중: $userId');
      await _addParticipantInfo(participantsList, userId, userId == authorId);
    }
    
    if (mounted) {
      setState(() {
        _participants = participantsList;
      });
      Logger.log('✅ 최종 참여자 ${_participants.length}명 로드 완료');
      Logger.log('📋 최종 참여자 목록: ${_participants.map((p) => p['nickname']).toList()}');
    }
  }
  
  Future<void> _addParticipantInfo(List<Map<String, dynamic>> list, String userId, bool isHost) async {
    try {
      Logger.log('🔍 참여자 정보 조회 시작: userId=$userId');
      
      final userDoc = await _firestore.collection('users').doc(userId).get();
      
      if (!userDoc.exists) {
        Logger.log('❌ 사용자 문서 없음 (탈퇴한 사용자): $userId');
        // 탈퇴한 사용자 정보 추가
        final deletedLabel = AppLocalizations.of(context)?.deletedAccount ?? '탈퇴한 계정';
        final participantInfo = {
          'userId': userId,
          'nickname': deletedLabel,
          'photoURL': '',
          'isHost': isHost,
        };
        list.add(participantInfo);
        Logger.log('✅ 탈퇴한 참여자 추가 완료 - 현재 총 ${list.length}명');
        return;
      }
      
      final userData = userDoc.data();
      if (userData == null) {
        Logger.log('❌ 사용자 데이터 null: $userId');
        return;
      }
      
      // 닉네임 우선, 없으면 displayName, 둘 다 없으면 익명
      final nickname = userData['nickname'];
      // nickname 단일 소스
      final displayName = (userData['nickname'] ?? '').toString().trim();
      final finalName = nickname ?? displayName ?? '익명';
      
      Logger.log('📋 사용자 정보: nickname=$nickname, displayName=$displayName, final=$finalName');
      
      final participantInfo = {
        'userId': userId,
        'nickname': finalName,
        'photoURL': userData['photoURL'] ?? '',
        'isHost': isHost,
      };
      
      list.add(participantInfo);
      Logger.log('✅ 참여자 추가 완료: $finalName (${isHost ? "호스트" : "참여자"}) - 현재 총 ${list.length}명');
      
    } catch (e, stackTrace) {
      Logger.error('❌ 참여자 정보 조회 오류: $userId');
      Logger.error('   에러: $e');
      Logger.log('   스택: $stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentUser = _auth.currentUser;
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: StreamBuilder<ReviewPost?>(
        stream: _reviewService.getReviewStream(widget.review.id, widget.review.authorId),
        initialData: widget.review,
        builder: (context, snapshot) {
          // 로딩 중
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          
          // 데이터 없음
          if (!snapshot.hasData || snapshot.data == null) {
            return Center(
              child: Text(
                l10n?.reviewNotFound ?? "",
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  color: BrandColors.textSecondary,
                ),
              ),
            );
          }

          final review = snapshot.data!;
          final isLiked = currentUser != null && review.isLikedByUser(currentUser.uid);

          return CustomScrollView(
            slivers: [
              // 앱바
              SliverAppBar(
                pinned: true,
                elevation: 0,
                backgroundColor: Colors.white,
                leading: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.arrow_back, color: BrandColors.textPrimary),
                ),
                title: Text(
                  l10n?.reviewDetails ?? "",
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    color: BrandColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // 콘텐츠
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 작성자 정보
                    _buildAuthorHeader(review, l10n),
                    
                    // 게시글 내용 (이미지 위에 표시)
                    _buildContent(review, l10n),
                    
                    // 이미지
                    _buildImage(review),
                    
                    // 좋아요/댓글 액션 버튼
                    _buildActionButtons(review, isLiked, currentUser),
                    
                    // 좋아요 수
                    _buildLikeCount(review, l10n),
                    
                    // 작성 시간
                    _buildTimestamp(review),
                    
                    const SizedBox(height: 16),
                    Divider(height: 1, color: BrandColors.neutral200),
                    
                    // 참여자 섹션
                    if (_participants.isNotEmpty)
                      _buildParticipantsSection(l10n),
                    
                    // 하단 네비게이션 바를 고려한 여백 추가
                    SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 80,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAuthorHeader(ReviewPost review, AppLocalizations? l10n) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // 프로필 이미지
          CircleAvatar(
            radius: 20,
            backgroundImage: review.authorProfileImage.isNotEmpty
                ? NetworkImage(review.authorProfileImage)
                : null,
            backgroundColor: BrandColors.neutral100,
            child: review.authorProfileImage.isEmpty
                ? Icon(Icons.person, color: BrandColors.textSecondary, size: 20)
                : null,
          ),
          const SizedBox(width: 12),
          
          // 작성자 이름
          Expanded(
            child: Text(
              review.authorName,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: BrandColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage(ReviewPost review) {
    if (review.imageUrls.isEmpty) {
      return Container(
        width: double.infinity,
        height: 400,
        color: BrandColors.neutral100,
        child: Center(
          child: Icon(
            Icons.image_not_supported_rounded,
            color: BrandColors.textTertiary,
            size: 64,
          ),
        ),
      );
    }

    return Stack(
      children: [
        // 이미지 PageView
        AspectRatio(
          aspectRatio: 1,
          child: PageView.builder(
            controller: _pageController,
            itemCount: review.imageUrls.length,
            onPageChanged: (index) {
              setState(() {
                _currentImageIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () {
                  // 전체화면 이미지 뷰어 열기
                  showFullscreenImageViewer(
                    context,
                    imageUrls: review.imageUrls,
                    initialIndex: index,
                    heroTag: 'review_image_$index',
                  );
                },
                child: Hero(
                  tag: 'review_image_$index',
                  child: Image.network(
                    review.imageUrls[index],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: BrandColors.neutral100,
                        child: Center(
                          child: Icon(
                            Icons.broken_image_rounded,
                            color: BrandColors.textTertiary,
                            size: 64,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
        
        // 이미지 개수 인디케이터 (2장 이상일 때 항상 표시)
        if (review.imageUrls.length > 1)
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${_currentImageIndex + 1}/${review.imageUrls.length}',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        
        // 도트 인디케이터 (2장 이상일 때 표시)
        if (review.imageUrls.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                review.imageUrls.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentImageIndex == index
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActionButtons(ReviewPost review, bool isLiked, User? currentUser) {
    final l10n = AppLocalizations.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 좋아요 버튼
          GestureDetector(
            onTap: currentUser != null && !_isLiking ? _handleLike : null,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                key: ValueKey(isLiked),
                color: isLiked ? Colors.red : BrandColors.textPrimary,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 16),
          
          // 댓글 버튼
          GestureDetector(
            onTap: () => _navigateToComments(review),
            child: Icon(
              Icons.mode_comment_outlined,
              color: BrandColors.textPrimary,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          
          // View all comments 버튼
          Expanded(
            child: GestureDetector(
              onTap: () => _navigateToComments(review),
              child: Row(
                children: [
                  Text(
                    review.commentCount > 0 
                            ? l10n!.viewAllComments(review.commentCount)
                        : l10n?.writeComment ?? "",
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: BrandColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: BrandColors.textTertiary, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLikeCount(ReviewPost review, AppLocalizations? l10n) {
    if (review.likeCount == 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
            l10n!.likesCount(review.likeCount),
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: BrandColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildContent(ReviewPost review, AppLocalizations? l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 카테고리 배지 제거 (요청사항)
          const SizedBox(height: 4),
          
          // 후기 내용 (작성자 이름 제거 - 헤더에 이미 표시됨)
          Text(
            review.content,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              color: BrandColors.textPrimary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimestamp(ReviewPost review) {
    // 로케일에 따라 날짜를 포맷 (ko → 'yyyy년 M월 d일', 기타 → 'MMM d, yyyy')
    final locale = Localizations.localeOf(context);
    final isKorean = locale.languageCode.toLowerCase() == 'ko';
    final pattern = isKorean ? 'yyyy년 M월 d일' : 'MMM d, yyyy';
    final dateFormat = DateFormat(pattern, locale.toLanguageTag());
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        dateFormat.format(review.createdAt),
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 12,
          color: BrandColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildParticipantsSection(AppLocalizations? l10n) {
    // 참여자가 없으면 섹션 숨김
    if (_participants.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Icon(
                Icons.groups_rounded,
                size: 18,
                color: BrandColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                    l10n!.meetupParticipants(_participants.length),
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: BrandColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        
        // 참여자 목록 (하단바를 고려한 padding 추가)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: _participants.map((participant) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      children: [
                        // 프로필 이미지
                        CircleAvatar(
                          radius: 28,
                          backgroundImage: participant['photoURL'] != null && 
                                  participant['photoURL'].toString().isNotEmpty
                              ? NetworkImage(participant['photoURL'])
                              : null,
                          backgroundColor: BrandColors.neutral100,
                          child: participant['photoURL'] == null || 
                                  participant['photoURL'].toString().isEmpty
                              ? Icon(Icons.person, color: BrandColors.textSecondary, size: 28)
                              : null,
                        ),
                        
                        // 호스트 배지
                        if (participant['isHost'] == true)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: BrandColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(
                                Icons.star,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 닉네임
                    SizedBox(
                      width: 60,
                      child: Text(
                        participant['nickname'] ?? '익명',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 12,
                          color: BrandColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        
        const SizedBox(height: 8),
      ],
    );
  }


  Future<void> _handleLike() async {
    if (_isLiking) return;

    setState(() {
      _isLiking = true;
    });

    try {
      final success = await _reviewService.toggleReviewLike(
        widget.review.id,
        widget.review.authorId,
      );

      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.error ?? ""),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLiking = false;
        });
      }
    }
  }

  void _navigateToComments(ReviewPost review) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReviewCommentsScreen(review: review),
      ),
    );
  }
}
