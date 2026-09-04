// lib/screens/review_detail_screen.dart
// 후기 상세 화면 - 좋아요, 댓글 기능 포함

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/review_post.dart';
import '../l10n/app_localizations.dart';
import '../services/review_service.dart';
import '../services/meetup_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'review_comments_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../ui/widgets/fullscreen_image_viewer.dart';
import '../ui/widgets/adaptive_post_image_frame.dart';
import '../services/cache/app_image_cache_manager.dart';
import '../utils/logger.dart';
import '../utils/account_status_helper.dart';
import '../services/user_info_cache_service.dart';
import '../utils/responsive_helper.dart';

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
      if (Logger.isVerboseEnabled)
        Logger.log('🔍 참여자 로드 시작: meetupId=${widget.review.meetupId}');

      // 항상 meetup_participants(approved) 기준으로 참여자 로드하고,
      // 호스트 ID는 meetup_reviews 또는 meetups에서 가져와 결합한다.

      String? hostId;

      // 1) meetup_reviews에서 호스트 확인
      if (widget.review.sourceReviewId != null &&
          widget.review.sourceReviewId!.isNotEmpty) {
        try {
          final reviewDoc = await _firestore
              .collection('meetup_reviews')
              .doc(widget.review.sourceReviewId)
              .get();
          if (reviewDoc.exists) {
            hostId = (reviewDoc.data() ?? const {})['authorId'] as String?;
            if (Logger.isVerboseEnabled)
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
            if (Logger.isVerboseEnabled)
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
        if (Logger.isVerboseEnabled)
          Logger.log('✅ 참여자 ${_participants.length}명 로드 완료 (호스트 포함)');
      }
    } catch (e) {
      Logger.error('❌ 참여자 로드 오류: $e');
    }
  }

  Future<void> _processParticipants(Map<String, dynamic> reviewData) async {
    final authorId = reviewData['authorId'] as String;
    final approvedParticipants =
        List<String>.from(reviewData['approvedParticipants'] ?? []);

    if (Logger.isVerboseEnabled) Logger.log('👥 호스트: $authorId');
    if (Logger.isVerboseEnabled)
      Logger.log('👥 수락한 참여자: ${approvedParticipants.length}명');
    if (Logger.isVerboseEnabled)
      Logger.log('📋 수락한 참여자 ID 목록: $approvedParticipants');

    // 모든 참여자 ID (호스트 + 수락한 참여자)
    final allParticipantIds = [authorId, ...approvedParticipants];
    if (Logger.isVerboseEnabled)
      Logger.log(
          '📋 전체 참여자 ID 목록 (${allParticipantIds.length}명): $allParticipantIds');

    // 각 참여자의 정보 가져오기
    final participantsList = <Map<String, dynamic>>[];

    for (int i = 0; i < allParticipantIds.length; i++) {
      final userId = allParticipantIds[i];
      if (Logger.isVerboseEnabled)
        Logger.log(
            '🔄 [${i + 1}/${allParticipantIds.length}] 참여자 처리 중: $userId');
      await _addParticipantInfo(participantsList, userId, userId == authorId);
    }

    if (mounted) {
      setState(() {
        _participants = participantsList;
      });
      if (Logger.isVerboseEnabled)
        Logger.log('✅ 최종 참여자 ${_participants.length}명 로드 완료');
      if (Logger.isVerboseEnabled)
        Logger.log(
            '📋 최종 참여자 목록: ${_participants.map((p) => p['nickname']).toList()}');
    }
  }

  Future<void> _addParticipantInfo(
      List<Map<String, dynamic>> list, String userId, bool isHost) async {
    try {
      if (Logger.isVerboseEnabled)
        Logger.log('🔍 참여자 정보 조회 시작: userId=$userId');

      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists || isUnavailableUserAccountData(userDoc.data())) {
        if (Logger.isVerboseEnabled)
          Logger.log('❌ 사용자 문서 없음 (탈퇴한 사용자): $userId');
        // 탈퇴한 사용자 정보 추가
        final deletedLabel =
            AppLocalizations.of(context)?.deletedAccount ?? '탈퇴한 계정';
        final participantInfo = {
          'userId': userId,
          'nickname': deletedLabel,
          'photoURL': '',
          'isHost': isHost,
        };
        list.add(participantInfo);
        if (Logger.isVerboseEnabled)
          Logger.log('✅ 탈퇴한 참여자 추가 완료 - 현재 총 ${list.length}명');
        return;
      }

      final userData = userDoc.data();
      if (userData == null) {
        if (Logger.isVerboseEnabled) Logger.log('❌ 사용자 데이터 null: $userId');
        return;
      }

      // 닉네임 우선, 없으면 displayName, 둘 다 없으면 익명
      final displayName = (userData['nickname'] ?? '').toString().trim();
      final finalName = displayName.isEmpty ? '익명' : displayName;

      if (Logger.isVerboseEnabled)
        Logger.log('📋 사용자 정보: displayName=$displayName, final=$finalName');

      final participantInfo = {
        'userId': userId,
        'nickname': finalName,
        'photoURL': userData['photoURL'] ?? '',
        'isHost': isHost,
      };

      list.add(participantInfo);
      if (Logger.isVerboseEnabled)
        Logger.log(
            '✅ 참여자 추가 완료: $finalName (${isHost ? "호스트" : "참여자"}) - 현재 총 ${list.length}명');
    } catch (e, stackTrace) {
      Logger.error('❌ 참여자 정보 조회 오류: $userId');
      Logger.error('   에러: $e');
      if (Logger.isVerboseEnabled) Logger.log('   스택: $stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentUser = _auth.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: context.rh(56, min: 54, max: 60),
        leadingWidth: 48,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            Icons.arrow_back_rounded,
            size: context.ri(22).clamp(21, 24).toDouble(),
            color: const Color(0xFF111827),
          ),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        ),
        title: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Text(
            l10n?.reviewDetails ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              color: const Color(0xFF111827),
              fontSize: context.rf(18).clamp(16, 19).toDouble(),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: StreamBuilder<ReviewPost?>(
          stream: _reviewService.getReviewStream(
              widget.review.id, widget.review.authorId),
          initialData: widget.review,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF2E90FA)),
              );
            }

            if (!snapshot.hasData || snapshot.data == null) {
              return Center(
                child: Text(
                  l10n?.reviewNotFound ?? '',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: ['NotoSansKR'],
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF667085),
                  ),
                ),
              );
            }

            final review = snapshot.data!;
            final isLiked =
                currentUser != null && review.isLikedByUser(currentUser.uid);
            return MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.25,
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAuthorHeader(review, l10n),
                        _buildContent(review),
                        if (review.imageUrls.isNotEmpty) ...[
                          _buildImage(review),
                          _buildImageDotsIndicator(review.imageUrls.length),
                        ],
                        _buildMeetupMeta(review),
                        _buildActionButtons(review, isLiked, currentUser),
                        if (_participants.isNotEmpty) ...[
                          SizedBox(
                            height: context.rs(24).clamp(20, 28).toDouble(),
                          ),
                          _buildParticipantsSection(l10n),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  double get _horizontalPadding {
    final width = MediaQuery.sizeOf(context).width;
    return width < 360 ? 14 : (width < 430 ? 16 : 20);
  }

  Widget _buildAuthorHeader(ReviewPost review, AppLocalizations? l10n) {
    final deletedLabel = l10n?.deletedAccount ?? 'Deleted Account';
    if (review.authorId.isEmpty || review.authorId == 'deleted') {
      return _buildAuthorHeaderContent(
        review: review,
        displayName: deletedLabel,
        photoURL: '',
      );
    }
    final cache = UserInfoCacheService();
    return StreamBuilder<DMUserInfo?>(
      stream: cache.watchUserInfo(review.authorId),
      initialData: cache.getCachedUserInfo(review.authorId),
      builder: (context, snapshot) {
        final latest = snapshot.data;
        final isDeleted = latest?.isDeletedAccount == true;
        return _buildAuthorHeaderContent(
          review: review,
          displayName: isDeleted
              ? deletedLabel
              : ((latest?.nickname ?? '').trim().isNotEmpty
                  ? latest!.nickname
                  : review.authorName),
          photoURL: isDeleted
              ? ''
              : ((latest?.photoURL ?? '').trim().isNotEmpty
                  ? latest!.photoURL
                  : review.authorProfileImage),
        );
      },
    );
  }

  Widget _buildAuthorHeaderContent({
    required ReviewPost review,
    required String displayName,
    required String photoURL,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _horizontalPadding,
        context.rs(10).clamp(8, 12).toDouble(),
        _horizontalPadding,
        context.rs(4).clamp(3, 6).toDouble(),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: context.rs(20).clamp(19, 21).toDouble(),
            backgroundImage: photoURL.isNotEmpty
                ? CachedNetworkImageProvider(
                    photoURL,
                    cacheManager: AppImageCacheManager.instance,
                  )
                : null,
            backgroundColor: const Color(0xFFF2F4F7),
            child: photoURL.isEmpty
                ? Icon(
                    Icons.person_outline_rounded,
                    color: const Color(0xFF667085),
                    size: context.ri(19).clamp(18, 21).toDouble(),
                  )
                : null,
          ),
          SizedBox(width: context.rs(7).clamp(6, 8).toDouble()),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(15).clamp(14, 16).toDouble(),
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827),
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  '·',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF98A2B3),
                    height: 1,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    _formatReviewDate(review.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(12.5).clamp(11.5, 13).toDouble(),
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF98A2B3),
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatReviewDate(DateTime createdAt) {
    final locale = Localizations.localeOf(context);
    final pattern = locale.languageCode.toLowerCase() == 'ko'
        ? 'yyyy년 M월 d일'
        : 'MMM d, yyyy';
    return DateFormat(pattern, locale.toLanguageTag()).format(createdAt);
  }

  Widget _buildImage(ReviewPost review) {
    if (review.imageUrls.isEmpty) return const SizedBox.shrink();

    final maximumHeight =
        (MediaQuery.sizeOf(context).height * 0.44).clamp(250.0, 420.0);
    final imagePadding = context.rs(8).clamp(7, 10).toDouble();

    return Padding(
      padding: EdgeInsets.fromLTRB(imagePadding, 8, imagePadding, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maximumHeight),
          child: AdaptivePostImageFrame(
            imageUrl: review.imageUrls.first,
            cacheWidth: 1000,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _pageController,
                  itemCount: review.imageUrls.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentImageIndex = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final imageUrl = review.imageUrls[index];
                    return Semantics(
                      button: true,
                      label:
                          Localizations.localeOf(context).languageCode == 'ko'
                              ? '리뷰 이미지 확대'
                              : 'Open review image',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          showFullscreenImageViewer(
                            context,
                            imageUrls: review.imageUrls,
                            initialIndex: index,
                            heroTag: 'review_image_$index',
                          );
                        },
                        child: Hero(
                          tag: 'review_image_$index',
                          child: ColoredBox(
                            color: const Color(0xFFF2F4F7),
                            child: CachedNetworkImage(
                              imageUrl: imageUrl,
                              cacheManager: AppImageCacheManager.instance,
                              memCacheWidth: 1000,
                              maxWidthDiskCache: 1600,
                              fit: BoxFit.cover,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              placeholder: (_, __) => const ColoredBox(
                                color: Color(0xFFF2F4F7),
                              ),
                              errorWidget: (_, __, ___) => Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: const Color(0xFF98A2B3),
                                  size: context.ri(38).clamp(34, 42).toDouble(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (review.imageUrls.length > 1)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x99111827),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_currentImageIndex + 1}/${review.imageUrls.length}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: ['NotoSansKR'],
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
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

  Widget _buildImageDotsIndicator(int count) {
    if (count <= 1) return const SizedBox(height: 6);

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          count,
          (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: _currentImageIndex == index ? 16 : 5,
            height: 5,
            decoration: BoxDecoration(
              color: _currentImageIndex == index
                  ? const Color(0xFF2E90FA)
                  : const Color(0xFFD0D5DD),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMeetupMeta(ReviewPost review) {
    final meetupTitle = review.meetupTitle.trim();
    final category = review.category.trim();
    if (meetupTitle.isEmpty && category.isEmpty && review.rating <= 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _horizontalPadding,
        review.imageUrls.length > 1 ? 8 : 10,
        _horizontalPadding,
        0,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.event_outlined,
            size: 17,
            color: Color(0xFF667085),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              meetupTitle.isNotEmpty ? meetupTitle : category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(13).clamp(12.5, 14).toDouble(),
                fontWeight: FontWeight.w600,
                color: const Color(0xFF475467),
              ),
            ),
          ),
          if (review.rating > 0) ...[
            const SizedBox(width: 10),
            const Icon(
              Icons.star_rounded,
              size: 16,
              color: Color(0xFFF79009),
            ),
            const SizedBox(width: 3),
            Text(
              '${review.rating}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF667085),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(
      ReviewPost review, bool isLiked, User? currentUser) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _horizontalPadding - 7,
        context.rs(5).clamp(4, 7).toDouble(),
        _horizontalPadding,
        0,
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 40,
            child: IconButton(
              onPressed: currentUser != null && !_isLiking ? _handleLike : null,
              padding: EdgeInsets.zero,
              tooltip: l10n?.likes ?? '',
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  key: ValueKey(isLiked),
                  color: isLiked
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF111827),
                  size: context.ri(23).clamp(22, 25).toDouble(),
                ),
              ),
            ),
          ),
          if (review.likeCount > 0) ...[
            Text(
              '${review.likeCount}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF475467),
              ),
            ),
            const SizedBox(width: 5),
          ],
          SizedBox.square(
            dimension: 40,
            child: IconButton(
              onPressed: () => _navigateToComments(review),
              padding: EdgeInsets.zero,
              tooltip: l10n?.comments ?? '',
              icon: Icon(
                Icons.mode_comment_outlined,
                color: const Color(0xFF111827),
                size: context.ri(22).clamp(21, 24).toDouble(),
              ),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: InkWell(
              onTap: () => _navigateToComments(review),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      review.commentCount > 0
                          ? l10n!.viewAllComments(review.commentCount)
                          : l10n?.writeComment ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(13).clamp(12, 14).toDouble(),
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF667085),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF98A2B3),
                    size: 17,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ReviewPost review) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _horizontalPadding,
        context.rs(5).clamp(4, 7).toDouble(),
        _horizontalPadding,
        context.rs(8).clamp(7, 10).toDouble(),
      ),
      child: Text(
        review.content,
        style: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: context.rf(15).clamp(14, 16).toDouble(),
          fontWeight: FontWeight.w500,
          color: const Color(0xFF111827),
          height: 1.4,
          letterSpacing: -0.15,
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
          padding: EdgeInsets.fromLTRB(
            _horizontalPadding,
            0,
            _horizontalPadding,
            context.rs(11).clamp(9, 13).toDouble(),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.groups_rounded,
                size: 17,
                color: Color(0xFF667085),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n!.meetupParticipants(_participants.length),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: context.rf(14).clamp(13, 14.5).toDouble(),
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
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
                          radius: context.rs(22).clamp(21, 24).toDouble(),
                          backgroundImage: participant['photoURL'] != null &&
                                  participant['photoURL'].toString().isNotEmpty
                              ? CachedNetworkImageProvider(
                                  participant['photoURL'].toString(),
                                  cacheManager: AppImageCacheManager.instance,
                                )
                              : null,
                          backgroundColor: const Color(0xFFF2F4F7),
                          child: participant['photoURL'] == null ||
                                  participant['photoURL'].toString().isEmpty
                              ? Icon(
                                  Icons.person_outline_rounded,
                                  color: const Color(0xFF667085),
                                  size: context.ri(21).clamp(20, 23).toDouble(),
                                )
                              : null,
                        ),

                        // 호스트 배지
                        if (participant['isHost'] == true)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: const BoxDecoration(
                                color: Color(0xFF2E90FA),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.star_rounded,
                                size: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 52,
                      child: Text(
                        participant['nickname'] ?? '익명',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: ['NotoSansKR'],
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475467),
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
        SizedBox(height: context.rs(12).clamp(10, 14).toDouble()),
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
