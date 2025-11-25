// lib/screens/create_meetup_review_screen.dart
// 모임 후기 작성 화면
// 사진 1장과 글을 작성하여 참여자들에게 후기 수락 요청

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/meetup.dart';
import '../services/meetup_service.dart';
import '../l10n/app_localizations.dart';
import '../design/tokens.dart';
import 'main_screen.dart';

class CreateMeetupReviewScreen extends StatefulWidget {
  final Meetup meetup;
  final String? existingReviewId; // 수정 모드일 경우
  final String? existingImageUrl; // 하위 호환성을 위해 유지
  final List<String>? existingImageUrls; // 여러 이미지 지원
  final String? existingContent;

  const CreateMeetupReviewScreen({
    Key? key,
    required this.meetup,
    this.existingReviewId,
    this.existingImageUrl,
    this.existingImageUrls,
    this.existingContent,
  }) : super(key: key);

  @override
  State<CreateMeetupReviewScreen> createState() => _CreateMeetupReviewScreenState();
}

class _CreateMeetupReviewScreenState extends State<CreateMeetupReviewScreen> {
  final MeetupService _meetupService = MeetupService();
  final TextEditingController _contentController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  
  List<File> _selectedImages = []; // 최대 5장
  List<String> _imageUrls = []; // 기존 이미지 URL들
  bool _isLoading = false;
  bool _isUploading = false;
  static const int maxImages = 5;

  @override
  void initState() {
    super.initState();
    if (widget.existingContent != null) {
      _contentController.text = widget.existingContent!;
    }
    
    // 여러 이미지 URL 로드 (우선순위: existingImageUrls > existingImageUrl)
    if (widget.existingImageUrls != null && widget.existingImageUrls!.isNotEmpty) {
      _imageUrls = List<String>.from(widget.existingImageUrls!);
    } else if (widget.existingImageUrl != null && widget.existingImageUrl!.isNotEmpty) {
      _imageUrls = [widget.existingImageUrl!];
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      // 현재 선택된 총 이미지 수 확인
      final currentCount = _selectedImages.length + _imageUrls.length;
      if (currentCount >= maxImages) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('최대 ${maxImages}장까지 선택 가능합니다'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // 남은 선택 가능한 이미지 수 계산
      final remainingSlots = maxImages - currentCount;

      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFiles.isNotEmpty) {
        // 최대 개수만큼만 추가
        final filesToAdd = pickedFiles.take(remainingSlots).map((xFile) => File(xFile.path)).toList();
        
        setState(() {
          _selectedImages.addAll(filesToAdd);
        });

        if (pickedFiles.length > remainingSlots) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${filesToAdd.length}장의 사진이 추가되었습니다 (최대 ${maxImages}장 제한)'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ 이미지 선택 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.imagePickFailed ?? "")),
        );
      }
    }
  }

  void _removeImage(int index, {bool isUrl = false}) {
    setState(() {
      if (isUrl) {
        _imageUrls.removeAt(index);
      } else {
        _selectedImages.removeAt(index);
      }
    });
  }

  Future<List<String>?> _uploadImages() async {
    setState(() {
      _isUploading = true;
    });

    try {
      final List<String> uploadedUrls = [..._imageUrls]; // 기존 URL 유지

      // 새로 선택한 이미지들 업로드
      for (int i = 0; i < _selectedImages.length; i++) {
        final file = _selectedImages[i];
        final fileName = 'review_${widget.meetup.id}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('meetup_reviews')
            .child(fileName);

        await storageRef.putFile(file);
        final downloadUrl = await storageRef.getDownloadURL();
        uploadedUrls.add(downloadUrl);
      }

      setState(() {
        _isUploading = false;
      });

      return uploadedUrls;
    } catch (e) {
      print('❌ 이미지 업로드 오류: $e');
      setState(() {
        _isUploading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.imageUploadFailed ?? "")),
        );
      }
      return null;
    }
  }

  Future<void> _submitReview() async {
    if (_selectedImages.isEmpty && _imageUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('최소 1장의 사진을 선택해주세요')),
      );
      return;
    }

    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.pleaseEnterReviewContent ?? "")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 이미지 업로드
      final imageUrls = await _uploadImages();
      if (imageUrls == null || imageUrls.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // 후기 생성 또는 수정
      if (widget.existingReviewId != null) {
        // 수정 모드 - 모든 이미지 URL 전달
        final success = await _meetupService.updateMeetupReview(
          reviewId: widget.existingReviewId!,
          imageUrls: imageUrls,
          content: _contentController.text.trim(),
        );

        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.reviewUpdated ?? "")),
          );
          Navigator.of(context).pop(true);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.reviewUpdateFailed ?? "")),
          );
        }
      } else {
        // 생성 모드 - 모든 이미지 URL 전달
        final reviewId = await _meetupService.createMeetupReview(
          meetupId: widget.meetup.id,
          imageUrls: imageUrls,
          content: _contentController.text.trim(),
        );

        if (reviewId == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context)!.reviewCreateFailed ?? "")),
            );
          }
          setState(() {
            _isLoading = false;
          });
          return;
        }

        // 참여자 목록 가져오기
        final participants = await _meetupService.getMeetupParticipantsByStatus(
          widget.meetup.id,
          'approved',
        );
        final participantIds = participants
            .map((p) => p.userId)
            .where((id) => id != widget.meetup.userId) // 모임장 제외
            .toList();

        // 후기 수락 요청 전송
        final requestSent = await _meetupService.sendReviewApprovalRequests(
          reviewId: reviewId,
          participantIds: participantIds,
        );

        if (mounted) {
          if (requestSent) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.reviewCreatedAndRequestsSent(participantIds.length) ?? ""),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.reviewCreatedButNotificationFailed ?? ""),
                backgroundColor: Colors.orange,
              ),
            );
          }
          
          // 후기 작성 완료 후 My Page 탭으로 이동
          Navigator.of(context).popUntil((route) => route.isFirst);
          
          // MainScreen의 탭을 My Page로 변경
          final mainScreenContext = Navigator.of(context).context;
          if (mainScreenContext.mounted) {
            // MainScreen에 접근하여 탭 변경
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => MainScreen(initialTabIndex: 2), // My Page 탭
              ),
            );
          }
        }
      }
    } catch (e) {
      print('❌ 후기 제출 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.error ?? "")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildImageTile({File? imageFile, String? imageUrl, required VoidCallback onRemove}) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: DesignTokens.radiusM,
            border: Border.all(color: BrandColors.neutral300),
            boxShadow: DesignTokens.shadowLight,
          ),
          child: ClipRRect(
            borderRadius: DesignTokens.radiusM,
            child: imageFile != null
                ? Image.file(
                    imageFile,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  )
                : imageUrl != null
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: BrandColors.neutral200,
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: BrandColors.textTertiary,
                            ),
                          );
                        },
                      )
                    : const SizedBox.shrink(),
          ),
        ),
        // 삭제 버튼
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
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
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.existingReviewId != null;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditMode ? (AppLocalizations.of(context)!.reviewEditTitle ?? "") : AppLocalizations.of(context)!.reviewWriteTitle,
          style: TypographyStyles.headlineMedium.copyWith(
            color: const Color(0xFF111827),
          ),
        ),
      ),
      body: Column(
        children: [
          // 스크롤 가능한 콘텐츠
          Expanded(
            child: SingleChildScrollView(
              padding: DesignTokens.paddingM,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 모임 정보
                  Container(
                    padding: DesignTokens.paddingS,
                    decoration: BoxDecoration(
                      color: BrandColors.primarySubtle,
                      borderRadius: DesignTokens.radiusM,
                      border: Border.all(
                        color: BrandColors.primary.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_outlined,
                          color: BrandColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.meetup.title,
                            style: TypographyStyles.titleMedium.copyWith(
                              color: BrandColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 사진 선택 (최대 5장)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.reviewPhoto,
                        style: TypographyStyles.titleMedium,
                      ),
                      Text(
                        '${_selectedImages.length + _imageUrls.length}/$maxImages',
                        style: TypographyStyles.bodyMedium.copyWith(
                          color: BrandColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // 이미지 그리드
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _selectedImages.length + _imageUrls.length + 1,
                    itemBuilder: (context, index) {
                      // 기존 URL 이미지 표시
                      if (index < _imageUrls.length) {
                        return _buildImageTile(
                          imageUrl: _imageUrls[index],
                          onRemove: () => _removeImage(index, isUrl: true),
                        );
                      }
                      
                      // 새로 선택한 이미지 표시
                      final fileIndex = index - _imageUrls.length;
                      if (fileIndex < _selectedImages.length) {
                        return _buildImageTile(
                          imageFile: _selectedImages[fileIndex],
                          onRemove: () => _removeImage(fileIndex, isUrl: false),
                        );
                      }
                      
                      // 추가 버튼
                      if (index < maxImages) {
                        return GestureDetector(
                          onTap: _isLoading ? null : _pickImages,
                          child: Container(
                            decoration: BoxDecoration(
                              color: BrandColors.neutral100,
                              borderRadius: DesignTokens.radiusM,
                              border: Border.all(
                                color: BrandColors.neutral300,
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 32,
                                  color: BrandColors.textTertiary,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '사진 추가',
                                  style: TypographyStyles.labelSmall.copyWith(
                                    color: BrandColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      
                      return const SizedBox.shrink();
                    },
                  ),
                  const SizedBox(height: 24),

                  // 후기 내용
                  Text(
                    AppLocalizations.of(context)!.reviewContent,
                    style: TypographyStyles.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _contentController,
                    enabled: !_isLoading,
                    maxLines: 8,
                    maxLength: 500,
                    style: TypographyStyles.bodyLarge,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context)!.reviewWriteHint,
                      hintStyle: TypographyStyles.bodyLarge.copyWith(
                        color: BrandColors.textHint,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: DesignTokens.radiusM,
                        borderSide: BorderSide(color: BrandColors.neutral300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: DesignTokens.radiusM,
                        borderSide: BorderSide(color: BrandColors.neutral300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: DesignTokens.radiusM,
                        borderSide: BorderSide(color: BrandColors.primary, width: 2),
                      ),
                      filled: true,
                      fillColor: BrandColors.neutral50,
                      contentPadding: DesignTokens.paddingS,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 안내 문구
                  if (!isEditMode)
                    Container(
                      padding: DesignTokens.paddingS,
                      decoration: BoxDecoration(
                        color: BrandColors.warning.withOpacity(0.1),
                        borderRadius: DesignTokens.radiusM,
                        border: Border.all(
                          color: BrandColors.warning.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: BrandColors.warning,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)!.reviewRequestInfo,
                              style: TypographyStyles.bodySmall.copyWith(
                                color: BrandColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  // 하단 여백 (버튼 높이 + 여백)
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
          
          // 고정된 하단 버튼 영역
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16, // 시스템 네비게이션 바 고려
            ),
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
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading || _isUploading ? null : _submitReview,
                style: ComponentStyles.primaryButton.copyWith(
                  backgroundColor: WidgetStateProperty.resolveWith<Color>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.disabled)) {
                        return BrandColors.neutral300;
                      }
                      return BrandColors.primary;
                    },
                  ),
                ),
                child: _isLoading || _isUploading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        isEditMode ? (AppLocalizations.of(context)!.reviewEditTitle ?? "") : AppLocalizations.of(context)!.requestReviewAcceptance,
                        style: TypographyStyles.buttonText.copyWith(
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

