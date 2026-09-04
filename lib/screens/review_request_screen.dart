// lib/screens/review_request_screen.dart
// 리뷰 요청 화면 - Feature Flag로 보호됨
// 기존 UI 패턴과 일치하는 디자인 적용

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/meetup.dart';
import '../utils/category_label_utils.dart';
import '../models/review_request.dart';
import '../services/review_consensus_service.dart';
import '../services/feature_flag_service.dart';
import '../utils/responsive_helper.dart';

class ReviewRequestScreen extends StatefulWidget {
  final Meetup meetup;
  final String recipientId;
  final String recipientName;

  const ReviewRequestScreen({
    super.key,
    required this.meetup,
    required this.recipientId,
    required this.recipientName,
  });

  @override
  State<ReviewRequestScreen> createState() => _ReviewRequestScreenState();
}

class _ReviewRequestScreenState extends State<ReviewRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  final _reviewService = ReviewConsensusService();
  final _featureFlag = FeatureFlagService();
  final ImagePicker _picker = ImagePicker();

  List<File> _selectedImages = [];
  bool _isSubmitting = false;
  bool _isFeatureEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkFeatureFlag();
  }

  @override
  void dispose() {
    _messageController.dispose();
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

  /// 이미지 선택
  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (images.isNotEmpty) {
        setState(() {
          _selectedImages = images.map((image) => File(image.path)).toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('이미지 선택 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 이미지 제거
  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  /// 리뷰 요청 제출
  Future<void> _submitRequest() async {
    if (!_isFeatureEnabled) {
      _showFeatureDisabledDialog();
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      // 이미지 업로드 (임시 ID 사용)
      List<String> imageUrls = [];
      if (_selectedImages.isNotEmpty) {
        final tempReviewId = DateTime.now().millisecondsSinceEpoch.toString();
        imageUrls = await _reviewService.uploadReviewImages(
          _selectedImages,
          widget.meetup.id,
          tempReviewId,
        );
      }

      // 리뷰 요청 생성
      final requestData = CreateReviewRequestData(
        meetupId: widget.meetup.id,
        recipientId: widget.recipientId,
        message: _messageController.text.trim(),
        imageUrls: imageUrls,
      );

      final requestId = await _reviewService.createReviewRequest(requestData);

      if (requestId != null && mounted) {
        Navigator.of(context).pop(true); // 성공 표시
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('리뷰 요청이 전송되었습니다.'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        throw Exception('리뷰 요청 생성에 실패했습니다.');
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
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isFeatureEnabled) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(),
        body: const SafeArea(
          top: false,
          child: Center(
            child: CircularProgressIndicator(color: Color(0xFF2E90FA)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
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
                          _buildMeetupCard(),
                          const SizedBox(height: 24),
                          _buildRecipientCard(),
                          const SizedBox(height: 28),
                          _buildMessageInput(),
                          const SizedBox(height: 28),
                          _buildImageAttachment(),
                          const SizedBox(height: 26),
                          _buildGuideText(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _buildBottomButton(),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
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
          '리뷰 요청',
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

  /// 모임 정보 카드
  Widget _buildMeetupCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizedCategoryLabel(context, widget.meetup.category),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            color: Color(0xFF2E90FA),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          widget.meetup.title,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(18).clamp(16, 19).toDouble(),
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(
              Icons.location_on_outlined,
              size: 17,
              color: Color(0xFF667085),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.meetup.location,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 14,
                  color: Color(0xFF667085),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            const Icon(
              Icons.schedule_rounded,
              size: 17,
              color: Color(0xFF667085),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${widget.meetup.date.month}/${widget.meetup.date.day} ${widget.meetup.time}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 14,
                  color: Color(0xFF667085),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 수신자 정보 카드
  Widget _buildRecipientCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '요청 대상',
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
              radius: 20,
              backgroundColor: const Color(0xFFF2F4F7),
              child: Text(
                widget.recipientName.isNotEmpty
                    ? widget.recipientName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Color(0xFF475467),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.recipientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: ['NotoSansKR'],
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '리뷰를 요청받을 사용자',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: ['NotoSansKR'],
                      fontSize: 12,
                      color: Color(0xFF98A2B3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 메시지 입력
  Widget _buildMessageInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '요청 메시지',
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(15).clamp(14, 16).toDouble(),
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _messageController,
          minLines: 4,
          maxLines: 7,
          maxLength: 500,
          decoration: InputDecoration(
            hintText: '리뷰 요청 사유를 입력해주세요.\n예: 모임이 어땠는지 솔직한 후기를 부탁드립니다.',
            hintStyle: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: ['NotoSansKR'],
              fontSize: 14,
              color: Color(0xFF98A2B3),
              height: 1.5,
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
              fontFamily: 'Inter',
              fontFamilyFallback: ['NotoSansKR'],
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
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '요청 메시지를 입력해주세요';
            }
            if (value.trim().length < 10) {
              return '메시지는 최소 10자 이상 입력해주세요';
            }
            return null;
          },
        ),
      ],
    );
  }

  /// 이미지 첨부
  Widget _buildImageAttachment() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                '이미지 첨부 (선택사항)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(15).clamp(14, 16).toDouble(),
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827),
                ),
              ),
            ),
            if (_selectedImages.isNotEmpty)
              Text(
                '${_selectedImages.length}/5',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 12,
                  color: Color(0xFF667085),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (_selectedImages.length < 5)
          TextButton.icon(
            onPressed: _pickImages,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF475467),
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
              minimumSize: const Size(0, 42),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 21),
            label: const Text(
              '이미지 추가',
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (_selectedImages.isNotEmpty) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 94,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return SizedBox.square(
                  dimension: 94,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: DecorationImage(
                              image: FileImage(_selectedImages[index]),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: SizedBox.square(
                          dimension: 30,
                          child: IconButton.filled(
                            onPressed: () => _removeImage(index),
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xB3111827),
                            ),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 17,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  /// 안내 텍스트
  Widget _buildGuideText() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Color(0xFF667085),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '리뷰 요청 안내',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475467),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '요청은 7일 후 자동으로 만료됩니다.\n'
                '상대방이 수락하면 리뷰 작성이 시작됩니다.\n'
                '거절하거나 응답이 없으면 다른 참여자에게 요청할 수 있습니다.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 12,
                  color: Color(0xFF667085),
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 하단 버튼
  Widget _buildBottomButton() {
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
          child: SizedBox(
            width: double.infinity,
            height: context.rh(50, min: 48, max: 54),
            child: FilledButton(
              onPressed: _isSubmitting ? null : _submitRequest,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E90FA),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE4E7EC),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '리뷰 요청 보내기',
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
      ),
    );
  }
}
