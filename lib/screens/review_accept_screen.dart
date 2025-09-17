// lib/screens/review_accept_screen.dart
// 리뷰 수락/거절 화면 - Feature Flag로 보호됨
// 기존 UI 디자인과 일치하는 스타일 적용

import 'package:flutter/material.dart';
import '../models/review_request.dart';
import '../services/review_consensus_service.dart';
import '../services/feature_flag_service.dart';

class ReviewAcceptScreen extends StatefulWidget {
  final ReviewRequest reviewRequest;

  const ReviewAcceptScreen({
    super.key,
    required this.reviewRequest,
  });

  @override
  State<ReviewAcceptScreen> createState() => _ReviewAcceptScreenState();
}

class _ReviewAcceptScreenState extends State<ReviewAcceptScreen> {
  final _reviewService = ReviewConsensusService();
  final _featureFlag = FeatureFlagService();
  final _responseController = TextEditingController();

  bool _isProcessing = false;
  bool _isFeatureEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkFeatureFlag();
  }

  @override
  void dispose() {
    _responseController.dispose();
    super.dispose();
  }

  /// Feature Flag 확인
  Future<void> _checkFeatureFlag() async {
    final isEnabled = await _featureFlag.isReviewConsensusEnabled;
    setState(() {
      _isFeatureEnabled = isEnabled;
    });

    if (!isEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showFeatureDisabledDialog();
      });
    }
  }

  /// 기능 비활성화 안내 다이얼로그
  void _showFeatureDisabledDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('기능 사용 불가'),
        content: const Text('리뷰 합의 기능이 현재 비활성화되어 있습니다.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // 다이얼로그 닫기
              Navigator.of(context).pop(); // 화면 닫기
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  /// 리뷰 요청 수락
  Future<void> _acceptRequest() async {
    if (!_isFeatureEnabled) {
      _showFeatureDisabledDialog();
      return;
    }

    await _respondToRequest(true);
  }

  /// 리뷰 요청 거절
  Future<void> _rejectRequest() async {
    if (!_isFeatureEnabled) {
      _showFeatureDisabledDialog();
      return;
    }

    await _respondToRequest(false);
  }

  /// 리뷰 요청 응답 처리
  Future<void> _respondToRequest(bool accept) async {
    // 거절하는 경우 확인 다이얼로그 표시
    if (!accept) {
      final confirmed = await _showRejectConfirmDialog();
      if (!confirmed) return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final success = await _reviewService.respondToReviewRequest(
        widget.reviewRequest.meetupId,
        widget.reviewRequest.id,
        accept,
        responseMessage: _responseController.text.trim().isNotEmpty 
            ? _responseController.text.trim() 
            : null,
      );

      if (success && mounted) {
        Navigator.of(context).pop(true); // 성공 표시
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accept ? '리뷰 요청을 수락했습니다.' : '리뷰 요청을 거절했습니다.'),
            backgroundColor: accept ? Colors.green : Colors.orange,
          ),
        );
      } else if (mounted) {
        throw Exception('응답 처리에 실패했습니다.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류가 발생했습니다: $e'),
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

  /// 거절 확인 다이얼로그
  Future<bool> _showRejectConfirmDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('리뷰 요청 거절'),
        content: const Text('정말로 이 리뷰 요청을 거절하시겠습니까?\n거절한 후에는 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('거절'),
          ),
        ],
      ),
    ) ?? false;
  }

  /// 만료일까지 남은 시간 계산
  String _getTimeRemaining() {
    final now = DateTime.now();
    final expiresAt = widget.reviewRequest.expiresAt;
    
    if (expiresAt.isBefore(now)) {
      return '만료됨';
    }
    
    final duration = expiresAt.difference(now);
    
    if (duration.inDays > 0) {
      return '${duration.inDays}일 후 만료';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}시간 후 만료';
    } else {
      return '${duration.inMinutes}분 후 만료';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isFeatureEnabled) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('리뷰 요청'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 만료된 요청인지 확인
    if (widget.reviewRequest.isExpired) {
      return _buildExpiredScreen();
    }

    // 이미 응답한 요청인지 확인
    if (!widget.reviewRequest.canRespond) {
      return _buildAlreadyRespondedScreen();
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('리뷰 요청'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.grey[200],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 요청자 정보
                  _buildRequesterCard(),
                  const SizedBox(height: 24),

                  // 모임 정보
                  _buildMeetupCard(),
                  const SizedBox(height: 24),

                  // 요청 메시지
                  _buildRequestMessage(),
                  const SizedBox(height: 24),

                  // 첨부 이미지
                  if (widget.reviewRequest.imageUrls.isNotEmpty) ...[
                    _buildAttachedImages(),
                    const SizedBox(height: 24),
                  ],

                  // 응답 메시지 (선택사항)
                  _buildResponseMessage(),
                  const SizedBox(height: 24),

                  // 만료 시간 안내
                  _buildExpirationInfo(),
                ],
              ),
            ),
          ),

          // 하단 버튼들
          _buildBottomButtons(),
        ],
      ),
    );
  }

  /// 요청자 정보 카드
  Widget _buildRequesterCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3FAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E6EE)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF4A90E2),
            child: Text(
              widget.reviewRequest.requesterName.isNotEmpty 
                  ? widget.reviewRequest.requesterName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.reviewRequest.requesterName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '리뷰 요청자',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A90E2).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '리뷰를 요청합니다',
                    style: const TextStyle(
                      color: Color(0xFF4A90E2),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
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

  /// 모임 정보 카드
  Widget _buildMeetupCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E6EE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '대상 모임',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF666666),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.reviewRequest.meetupTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '함께 참여했던 모임에 대한 리뷰를 요청합니다.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 요청 메시지
  Widget _buildRequestMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E6EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '요청 메시지',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF666666),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.reviewRequest.message.isNotEmpty 
                ? widget.reviewRequest.message
                : '리뷰 요청 메시지가 없습니다.',
            style: TextStyle(
              fontSize: 16,
              color: widget.reviewRequest.message.isNotEmpty 
                  ? const Color(0xFF1A1A1A)
                  : Colors.grey[500],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 첨부 이미지
  Widget _buildAttachedImages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '첨부 이미지',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.0,
          ),
          itemCount: widget.reviewRequest.imageUrls.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () {
                // 이미지 확대 보기 (기존 이미지 뷰어 재사용)
                // _showImageDialog(widget.reviewRequest.imageUrls[index]);
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[200],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    widget.reviewRequest.imageUrls[index],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Colors.grey,
                            size: 40,
                          ),
                        ),
                      );
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// 응답 메시지 (선택사항)
  Widget _buildResponseMessage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '응답 메시지 (선택사항)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _responseController,
          maxLines: 3,
          maxLength: 200,
          decoration: InputDecoration(
            hintText: '수락 또는 거절 사유를 간단히 적어주세요. (선택사항)',
            hintStyle: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF4A90E2), width: 2),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  /// 만료 시간 안내
  Widget _buildExpirationInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule,
            size: 20,
            color: Colors.amber[700],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '만료 시간',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getTimeRemaining(),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.amber[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 하단 버튼들
  Widget _buildBottomButtons() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 
        12, 
        16, 
        MediaQuery.of(context).padding.bottom + 16
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: const Color(0xFFE6EAF0),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 거절 버튼
          Expanded(
            flex: 1,
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _isProcessing ? null : _rejectRequest,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF6B6B6B)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isProcessing 
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF6B6B6B),
                        ),
                      )
                    : const Text(
                        '거절',
                        style: TextStyle(
                          color: Color(0xFF6B6B6B),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 수락 버튼
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _acceptRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isProcessing 
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '수락하고 리뷰 작성',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 만료된 요청 화면
  Widget _buildExpiredScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('만료된 요청'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.access_time,
                size: 80,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 24),
              const Text(
                '요청이 만료되었습니다',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '이 리뷰 요청은 만료되어 더 이상 응답할 수 없습니다.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    foregroundColor: Colors.grey[700],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '확인',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
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

  /// 이미 응답한 요청 화면
  Widget _buildAlreadyRespondedScreen() {
    final statusText = widget.reviewRequest.status == ReviewRequestStatus.accepted 
        ? '이미 수락한 요청입니다'
        : '이미 거절한 요청입니다';
    
    final statusColor = widget.reviewRequest.status == ReviewRequestStatus.accepted 
        ? Colors.green 
        : Colors.red;

    return Scaffold(
      appBar: AppBar(
        title: const Text('처리 완료된 요청'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.reviewRequest.status == ReviewRequestStatus.accepted 
                    ? Icons.check_circle_outline
                    : Icons.cancel_outlined,
                size: 80,
                color: statusColor,
              ),
              const SizedBox(height: 24),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                widget.reviewRequest.respondedAt != null
                    ? '응답 시간: ${_formatDateTime(widget.reviewRequest.respondedAt!)}'
                    : '이미 처리된 요청입니다.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    foregroundColor: Colors.grey[700],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '확인',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
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

  /// 날짜 시간 포맷
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
