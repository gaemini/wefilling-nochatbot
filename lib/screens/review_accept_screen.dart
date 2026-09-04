// lib/screens/review_accept_screen.dart
// 리뷰 수락/거절 화면 - Feature Flag로 보호됨
// 기존 UI 디자인과 일치하는 스타일 적용

import 'package:flutter/material.dart';
import '../models/review_request.dart';
import '../services/review_consensus_service.dart';
import '../services/feature_flag_service.dart';
import '../utils/responsive_helper.dart';

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
        ) ??
        false;
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
        backgroundColor: Colors.white,
        appBar: _buildAppBar('리뷰 요청'),
        body: const SafeArea(
          top: false,
          child: Center(
            child: CircularProgressIndicator(color: Color(0xFF2E90FA)),
          ),
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
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar('리뷰 요청'),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  _horizontalPadding,
                  12,
                  _horizontalPadding,
                  28,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRequesterCard(),
                        const SizedBox(height: 26),
                        _buildMeetupCard(),
                        const SizedBox(height: 26),
                        _buildRequestMessage(),
                        if (widget.reviewRequest.imageUrls.isNotEmpty) ...[
                          const SizedBox(height: 26),
                          _buildAttachedImages(),
                        ],
                        const SizedBox(height: 28),
                        _buildResponseMessage(),
                        const SizedBox(height: 24),
                        _buildExpirationInfo(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _buildBottomButtons(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(String title) {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      toolbarHeight: context.rh(56, min: 54, max: 60),
      leadingWidth: 48,
      leading: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: Icon(
          Icons.arrow_back_rounded,
          color: const Color(0xFF111827),
          size: context.ri(22).clamp(21, 24).toDouble(),
        ),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      ),
      title: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: Text(
          title,
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
    );
  }

  double get _horizontalPadding {
    final width = MediaQuery.sizeOf(context).width;
    return width < 360 ? 14 : (width < 430 ? 16 : 20);
  }

  /// 요청자 정보 카드
  Widget _buildRequesterCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '리뷰 요청자',
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF667085),
          ),
        ),
        const SizedBox(height: 11),
        Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: const Color(0xFFF2F4F7),
              child: Text(
                widget.reviewRequest.requesterName.isNotEmpty
                    ? widget.reviewRequest.requesterName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: Color(0xFF475467),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                widget.reviewRequest.requesterName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(16).clamp(15, 17).toDouble(),
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '리뷰 요청',
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                color: Color(0xFF2E90FA),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 모임 정보 카드
  Widget _buildMeetupCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '대상 모임',
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF667085),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.reviewRequest.meetupTitle,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(18).clamp(16, 19).toDouble(),
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          '함께 참여했던 모임에 대한 리뷰를 요청합니다.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 13,
            color: Color(0xFF667085),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  /// 요청 메시지
  Widget _buildRequestMessage() {
    final hasMessage = widget.reviewRequest.message.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '요청 메시지',
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF667085),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hasMessage ? widget.reviewRequest.message : '리뷰 요청 메시지가 없습니다.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(15).clamp(14, 16).toDouble(),
            color:
                hasMessage ? const Color(0xFF111827) : const Color(0xFF98A2B3),
            height: 1.55,
          ),
        ),
      ],
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
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 138,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.reviewRequest.imageUrls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              return SizedBox(
                width: 138,
                child: GestureDetector(
                  onTap: () {
                    // 이미지 확대 보기 (기존 이미지 뷰어 재사용)
                    // _showImageDialog(widget.reviewRequest.imageUrls[index]);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      widget.reviewRequest.imageUrls[index],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const ColoredBox(
                          color: Color(0xFFF2F4F7),
                          child: Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: Color(0xFF98A2B3),
                              size: 32,
                            ),
                          ),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const ColoredBox(
                          color: Color(0xFFF2F4F7),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF2E90FA),
                              strokeWidth: 2,
                            ),
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
      ],
    );
  }

  /// 응답 메시지 (선택사항)
  Widget _buildResponseMessage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '응답 메시지 (선택사항)',
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(15).clamp(14, 16).toDouble(),
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _responseController,
          minLines: 3,
          maxLines: 5,
          maxLength: 200,
          decoration: InputDecoration(
            hintText: '수락 또는 거절 사유를 간단히 적어주세요. (선택사항)',
            hintStyle: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: ['NotoSansKR'],
              fontSize: 14,
              color: Color(0xFF98A2B3),
            ),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF2E90FA), width: 1.5),
            ),
            counterStyle: const TextStyle(
              fontSize: 11,
              color: Color(0xFF98A2B3),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 14,
            color: Color(0xFF111827),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  /// 만료 시간 안내
  Widget _buildExpirationInfo() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.schedule_rounded,
            size: 18,
            color: Color(0xFF667085),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '만료 시간',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475467),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _getTimeRemaining(),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 12,
                  color: Color(0xFF667085),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 하단 버튼들
  Widget _buildBottomButtons() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _horizontalPadding,
        10,
        _horizontalPadding,
        12,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Row(
            children: [
              // 거절 버튼
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: context.rh(50, min: 48, max: 54),
                  child: TextButton(
                    onPressed: _isProcessing ? null : _rejectRequest,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF667085),
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
                              color: Color(0xFF667085),
                            ),
                          )
                        : const Text(
                            '거절',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: ['NotoSansKR'],
                              color: Color(0xFF667085),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
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
                  height: context.rh(50, min: 48, max: 54),
                  child: FilledButton(
                    onPressed: _isProcessing ? null : _acceptRequest,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E90FA),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE4E7EC),
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
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '수락하고 리뷰 작성',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: ['NotoSansKR'],
                              fontSize: 15,
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
    );
  }

  /// 만료된 요청 화면
  Widget _buildExpiredScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar('만료된 요청'),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: EdgeInsets.all(_horizontalPadding + 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 52,
                    color: Color(0xFF98A2B3),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '요청이 만료되었습니다',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(21).clamp(19, 23).toDouble(),
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 9),
                  const Text(
                    '이 리뷰 요청은 만료되어 더 이상 응답할 수 없습니다.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: ['NotoSansKR'],
                      fontSize: 14,
                      color: Color(0xFF667085),
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E90FA),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '확인',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: ['NotoSansKR'],
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 이미 응답한 요청 화면
  Widget _buildAlreadyRespondedScreen() {
    final statusText =
        widget.reviewRequest.status == ReviewRequestStatus.accepted
            ? '이미 수락한 요청입니다'
            : '이미 거절한 요청입니다';

    final statusColor =
        widget.reviewRequest.status == ReviewRequestStatus.accepted
            ? Colors.green
            : Colors.red;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar('처리 완료된 요청'),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: EdgeInsets.all(_horizontalPadding + 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.reviewRequest.status == ReviewRequestStatus.accepted
                        ? Icons.check_circle_outline
                        : Icons.cancel_outlined,
                    size: 52,
                    color: statusColor,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(21).clamp(19, 23).toDouble(),
                      fontWeight: FontWeight.w700,
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
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 14,
                      color: const Color(0xFF667085),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E90FA),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '확인',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: ['NotoSansKR'],
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
