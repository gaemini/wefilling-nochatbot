// lib/screens/review_approval_screen.dart
// 후기 수락/거절 화면
// 모임장이 작성한 후기를 확인하고 수락 또는 거절

import 'package:flutter/material.dart';
import '../services/meetup_service.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../constants/app_constants.dart';
import '../ui/widgets/fullscreen_image_viewer.dart';

class ReviewApprovalScreen extends StatefulWidget {
  final String requestId;
  final String reviewId;
  final String meetupTitle;
  final String imageUrl; // 단일 이미지 (하위 호환성)
  final List<String>? imageUrls; // 여러 이미지 지원
  final String content;
  final String authorName;

  const ReviewApprovalScreen({
    Key? key,
    required this.requestId,
    required this.reviewId,
    required this.meetupTitle,
    required this.imageUrl,
    this.imageUrls,
    required this.content,
    required this.authorName,
  }) : super(key: key);

  @override
  State<ReviewApprovalScreen> createState() => _ReviewApprovalScreenState();
}

class _ReviewApprovalScreenState extends State<ReviewApprovalScreen> {
  final MeetupService _meetupService = MeetupService();
  bool _isProcessing = false;
  bool _isLoading = true;
  String? _currentStatus; // 'pending', 'accepted', 'rejected'
  late PageController _pageController;
  int _currentImageIndex = 0;
  late List<String> _imageUrls;

  @override
  void initState() {
    super.initState();
    // 이미지 URL 목록 초기화 (여러 이미지 또는 단일 이미지)
    _imageUrls = widget.imageUrls ?? [widget.imageUrl];
    _pageController = PageController();
    _checkRequestStatus();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 요청의 현재 상태 확인
  Future<void> _checkRequestStatus() async {
    try {
      final requestDoc = await _meetupService.getReviewRequestStatus(widget.requestId);
      
      if (mounted) {
        setState(() {
          _currentStatus = requestDoc?['status'] as String?;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('❌ 요청 상태 확인 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleResponse(bool accept) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final success = await _meetupService.respondToReviewRequest(
        requestId: widget.requestId,
        accept: accept,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(accept
                  ? (AppLocalizations.of(context)!.reviewAccepted ?? "") : AppLocalizations.of(context)!.reviewRejected),
            ),
          );
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.reviewProcessError ?? "")),
          );
        }
      }
    } catch (e) {
      Logger.error('❌ 후기 수락/거절 처리 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.error ?? "")),
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
    final l10n = AppLocalizations.of(context);
    
    // 로딩 중
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            l10n?.reviewApprovalRequest ?? "",
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.pointColor),
          ),
        ),
      );
    }

    // 이미 응답한 요청
    final alreadyResponded = _currentStatus != null && _currentStatus != 'pending';
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n?.reviewApprovalRequest ?? "",
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ),
      body: Column(
        children: [
          // 스크롤 가능한 콘텐츠 영역
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: alreadyResponded ? 20 : 0, // 응답 완료 시 하단 여백
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 모임 정보 헤더
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.pointColor.withOpacity(0.05),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.grey[200]!,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.pointColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.event,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.meetupTitle,
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    AppLocalizations.of(context)!.reviewByAuthor(widget.authorName),
                                    style: TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 후기 이미지 (전체 너비, 슬라이드 지원)
                  Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        height: 400,
                        color: Colors.black,
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: _imageUrls.length,
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
                                  imageUrls: _imageUrls,
                                  initialIndex: index,
                                  heroTag: 'review_approval_image_$index',
                                );
                              },
                              child: Hero(
                                tag: 'review_approval_image_$index',
                                child: Image.network(
                                  _imageUrls[index],
                                  fit: BoxFit.contain,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Center(
                                      child: CircularProgressIndicator(
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded /
                                                loadingProgress.expectedTotalBytes!
                                            : null,
                                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.pointColor),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey[200],
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                                            const SizedBox(height: 8),
                                            Text(
                                              '이미지를 불러올 수 없습니다',
                                              style: TextStyle(
                                                fontFamily: 'Pretendard',
                                                fontSize: 14,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
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
                      
                      // 이미지 개수 인디케이터 (2장 이상일 때만 표시)
                      if (_imageUrls.length > 1)
                        Positioned(
                          top: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '${_currentImageIndex + 1} / ${_imageUrls.length}',
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      
                      // 페이지 인디케이터 점 (하단 중앙, 2장 이상일 때만)
                      if (_imageUrls.length > 1)
                        Positioned(
                          bottom: 16,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              _imageUrls.length,
                              (index) => Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: 6,
                                height: 6,
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
                  ),

                  // 후기 내용
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.reviewContent,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Text(
                            widget.content,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              height: 1.6,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 안내 문구
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.amber[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber[200]!),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, color: Colors.amber[800], size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  AppLocalizations.of(context)!.reviewApprovalInfo,
                                  style: TextStyle(
                                    fontFamily: 'Pretendard',
                                    color: Colors.amber[900],
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 이미 응답한 경우 상태 표시
                        if (alreadyResponded) ...[
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _currentStatus == 'accepted' ? Colors.green[50] : Colors.red[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _currentStatus == 'accepted' ? Colors.green[200]! : Colors.red[200]!,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _currentStatus == 'accepted' ? Icons.check_circle : Icons.cancel,
                                  color: _currentStatus == 'accepted' ? Colors.green[700] : Colors.red[700],
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _currentStatus == 'accepted'
                                        ? l10n?.reviewAlreadyAccepted ?? ""
                                        : l10n?.reviewAlreadyRejected ?? "",
                                    style: TextStyle(
                                      fontFamily: 'Pretendard',
                                      color: _currentStatus == 'accepted' ? Colors.green[900] : Colors.red[900],
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 하단 고정 버튼 (응답하지 않은 경우에만)
          if (!alreadyResponded)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    offset: const Offset(0, -2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: SafeArea(
                minimum: const EdgeInsets.only(bottom: 8), // 갤럭시 하단바 추가 여백
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _isProcessing ? null : () => _handleResponse(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                            side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            disabledForegroundColor: Colors.grey[400],
                            disabledBackgroundColor: Colors.grey[100],
                          ),
                          child: _isProcessing
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEF4444)),
                                  ),
                                )
                              : Text(
                                  l10n?.reject ?? "",
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isProcessing ? null : () => _handleResponse(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.pointColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            disabledBackgroundColor: Colors.grey[300],
                            disabledForegroundColor: Colors.grey[500],
                          ),
                          child: _isProcessing
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  l10n?.accept ?? "",
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

