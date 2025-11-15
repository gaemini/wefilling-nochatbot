// lib/screens/meetup_review_screen.dart
// 모임 후기 확인 전체 페이지
// 주최자가 작성한 후기를 참여자가 확인하는 화면

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/meetup.dart';
import '../services/meetup_service.dart';
import '../l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class MeetupReviewScreen extends StatefulWidget {
  final String meetupId;
  final String? reviewId;

  const MeetupReviewScreen({
    super.key,
    required this.meetupId,
    this.reviewId,
  });

  @override
  State<MeetupReviewScreen> createState() => _MeetupReviewScreenState();
}

class _MeetupReviewScreenState extends State<MeetupReviewScreen> {
  final MeetupService _meetupService = MeetupService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoading = true;
  bool _isProcessing = false;
  Meetup? _meetup;
  Map<String, dynamic>? _reviewData;
  bool _hasUserAccepted = false;
  late final PageController _imagePageController;
  int _currentImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _imagePageController = PageController();
    _loadData();
  }

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
  }

  /// URL 여부 확인
  bool _isUrl(String text) {
    final uri = Uri.tryParse(text);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// 외부 브라우저로 링크 열기
  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('링크를 열 수 없습니다.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('링크 열기 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // 모임 정보 로드
      final meetup = await _meetupService.getMeetupById(widget.meetupId);
      if (meetup == null) {
        _showErrorAndClose('모임을 찾을 수 없습니다.');
        return;
      }

      // 후기 정보 로드
      Map<String, dynamic>? reviewData;
      if (meetup.reviewId != null) {
        reviewData = await _meetupService.getMeetupReview(meetup.reviewId!);
      }

      if (reviewData == null) {
        _showErrorAndClose('후기를 찾을 수 없습니다.');
        return;
      }

      // 사용자가 이미 후기를 확인했는지 체크
      // 과거: meetups.reviewAcceptedBy 사용 → 현재: meetup_reviews.approvedParticipants 사용
      final user = _auth.currentUser;
      bool hasAccepted = false;
      if (user != null) {
        final approved = (reviewData['approvedParticipants'] as List?)?.cast<dynamic>() ?? const [];
        hasAccepted = approved.contains(user.uid);
      }

      setState(() {
        _meetup = meetup;
        _reviewData = reviewData;
        _hasUserAccepted = hasAccepted;
        _isLoading = false;
      });
    } catch (e) {
      print('후기 로드 오류: $e');
      _showErrorAndClose('후기를 불러오는 중 오류가 발생했습니다.');
    }
  }

  void _showErrorAndClose(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmReview() async {
    if (_isProcessing || _hasUserAccepted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // 규칙 허용 경로로 처리: meetup_reviews(pending→approved) + review_requests 상태 동기화
      final reviewId = _meetup?.reviewId ?? widget.reviewId;
      if (reviewId == null) {
        throw Exception('reviewId가 없습니다.');
      }
      final success = await _meetupService.acceptMeetupReview(
        meetupId: widget.meetupId,
        reviewId: reviewId,
      );
      
      if (success) {
        setState(() {
          _hasUserAccepted = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.reviewAccepted),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('후기 확인 처리 중 오류가 발생했습니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('후기 확인 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('후기 확인 처리 중 오류가 발생했습니다.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          AppLocalizations.of(context)!.checkMeetupReview,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: 'Pretendard',
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_meetup == null || _reviewData == null) {
      return const Center(
        child: Text('후기 정보를 불러올 수 없습니다.'),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 모임 정보
                _buildMeetupInfo(),
                const SizedBox(height: 24),
                
                // 후기 내용
                _buildReviewContent(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
        
        // 하단 버튼
        _buildBottomButton(),
      ],
    );
  }

  Widget _buildMeetupInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _meetup!.title,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.person, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                _reviewData!['authorName'] ?? '익명',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final location = _meetup!.location;
                    final isUrl = _isUrl(location);
                    if (isUrl) {
                      return GestureDetector(
                        onTap: () => _openUrl(location),
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            color: Color(0xFF5865F2),
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }
                    return Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReviewContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '모임 후기',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            fontFamily: 'Pretendard',
          ),
        ),
        const SizedBox(height: 16),
        
        // 후기 이미지들
        if (_reviewData!['imageUrls'] != null && 
            (_reviewData!['imageUrls'] as List).isNotEmpty)
          _buildReviewImages(),
        
        // 후기 텍스트
        if (_reviewData!['content'] != null && 
            _reviewData!['content'].toString().isNotEmpty)
          _buildReviewText(),
      ],
    );
  }

  Widget _buildReviewImages() {
    final imageUrls = _reviewData!['imageUrls'] as List;
    final screenWidth = MediaQuery.of(context).size.width;
    // 게시글 상세와 유사한 시원한 크기: 정사각에 가깝게 넓게 표시
    final imageHeight = screenWidth; // 정사각 비율
    return Column(
      children: [
        SizedBox(
          height: imageHeight,
          width: double.infinity,
          child: PageView.builder(
            controller: _imagePageController,
            onPageChanged: (i) => setState(() => _currentImageIndex = i),
            itemCount: imageUrls.length,
            itemBuilder: (context, index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => Scaffold(
                            backgroundColor: Colors.black,
                            body: SafeArea(
                              child: Stack(
                                children: [
                                  Center(
                                    child: InteractiveViewer(
                                      minScale: 0.5,
                                      maxScale: 4.0,
                                      child: Image.network(
                                        imageUrls[index],
                                        fit: BoxFit.contain,
                                        width: double.infinity,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 16,
                                    right: 16,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    child: Image.network(
                      imageUrls[index],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: imageHeight,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[200],
                          child: const Icon(
                            Icons.image_not_supported,
                            color: Colors.grey,
                            size: 50,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (imageUrls.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                imageUrls.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _currentImageIndex == index ? 8 : 6,
                  height: _currentImageIndex == index ? 8 : 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentImageIndex == index
                        ? Colors.black.withOpacity(0.6)
                        : Colors.grey[400],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildReviewText() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Text(
        _reviewData!['content'],
        style: const TextStyle(
          fontSize: 16,
          height: 1.5,
          fontFamily: 'Pretendard',
        ),
      ),
    );
  }

  Widget _buildBottomButton() {
    // 이미 수락한 경우 버튼 자체를 숨김 (다시 방문해도 계속 숨김)
    if (_hasUserAccepted) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : _confirmReview,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    AppLocalizations.of(context)!.confirmReview,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Pretendard',
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
