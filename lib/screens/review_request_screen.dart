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
import '../design/theme.dart';

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
        appBar: AppBar(
          title: const Text('리뷰 요청'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
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
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 모임 정보 카드
                    _buildMeetupCard(),
                    const SizedBox(height: 24),

                    // 수신자 정보
                    _buildRecipientCard(),
                    const SizedBox(height: 24),

                    // 메시지 입력
                    _buildMessageInput(),
                    const SizedBox(height: 24),

                    // 이미지 첨부
                    _buildImageAttachment(),
                    const SizedBox(height: 24),

                    // 안내 텍스트
                    _buildGuideText(),
                  ],
                ),
              ),
            ),

            // 하단 버튼
            _buildBottomButton(),
          ],
        ),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90E2).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  localizedCategoryLabel(context, widget.meetup.category),
                  style: const TextStyle(
                    color: Color(0xFF4A90E2),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.meetup.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 16,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.meetup.location,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: 16,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Text(
                '${widget.meetup.date.month}/${widget.meetup.date.day} ${widget.meetup.time}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 수신자 정보 카드
  Widget _buildRecipientCard() {
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
            radius: 20,
            backgroundColor: const Color(0xFF4A90E2),
            child: Text(
              widget.recipientName.isNotEmpty 
                  ? widget.recipientName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.recipientName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                Text(
                  '리뷰를 요청받을 사용자',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 메시지 입력
  Widget _buildMessageInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '요청 메시지',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _messageController,
          maxLines: 4,
          maxLength: 500,
          decoration: InputDecoration(
            hintText: '리뷰 요청 사유를 입력해주세요.\n예: 모임이 어땠는지 솔직한 후기를 부탁드립니다.',
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
            const Text(
              '이미지 첨부 (선택사항)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
            if (_selectedImages.isNotEmpty)
              Text(
                '${_selectedImages.length}/5',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // 이미지 추가 버튼
        if (_selectedImages.length < 5)
          GestureDetector(
            onTap: _pickImages,
            child: Container(
              width: double.infinity,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFE6EAF0),
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 32,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '이미지 추가',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 선택된 이미지들
        if (_selectedImages.isNotEmpty) ...[
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _selectedImages.length,
            itemBuilder: (context, index) {
              return Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      image: DecorationImage(
                        image: FileImage(_selectedImages[index]),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removeImage(index),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  /// 안내 텍스트
  Widget _buildGuideText() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outlined,
                size: 20,
                color: Colors.orange[700],
              ),
              const SizedBox(width: 8),
              Text(
                '리뷰 요청 안내',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '• 요청은 7일 후 자동으로 만료됩니다\n'
            '• 상대방이 수락하면 리뷰 작성이 시작됩니다\n'
            '• 거절하거나 무응답 시 다른 참여자에게 요청할 수 있습니다',
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange[700],
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// 하단 버튼
  Widget _buildBottomButton() {
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
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _submitRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4A90E2),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  '리뷰 요청 보내기',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}
