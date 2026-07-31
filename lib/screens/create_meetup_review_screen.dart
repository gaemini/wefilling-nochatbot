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
import 'main_screen.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';
import '../ui/snackbar/app_snackbar.dart';

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
  State<CreateMeetupReviewScreen> createState() =>
      _CreateMeetupReviewScreenState();
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
    if (widget.existingImageUrls != null &&
        widget.existingImageUrls!.isNotEmpty) {
      _imageUrls = List<String>.from(widget.existingImageUrls!);
    } else if (widget.existingImageUrl != null &&
        widget.existingImageUrl!.isNotEmpty) {
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
        final isKo = Localizations.localeOf(context).languageCode == 'ko';
        AppSnackBar.show(
          context,
          message: isKo
              ? '최대 ${maxImages}장까지 선택 가능합니다'
              : 'You can select up to $maxImages images',
          type: AppSnackBarType.warning,
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
        final filesToAdd = pickedFiles
            .take(remainingSlots)
            .map((xFile) => File(xFile.path))
            .toList();

        setState(() {
          _selectedImages.addAll(filesToAdd);
        });

        if (pickedFiles.length > remainingSlots) {
          final isKo = Localizations.localeOf(context).languageCode == 'ko';
          AppSnackBar.show(
            context,
            message: isKo
                ? '${filesToAdd.length}장의 사진이 추가되었습니다 (최대 ${maxImages}장 제한)'
                : '${filesToAdd.length} images added (max $maxImages)',
            type: AppSnackBarType.info,
          );
        }
      }
    } catch (e) {
      Logger.error('❌ 이미지 선택 오류: $e');
      if (mounted) {
        AppSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.imagePickFailed ?? "",
          type: AppSnackBarType.error,
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
        final fileName =
            'review_${widget.meetup.id}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
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
      Logger.error('❌ 이미지 업로드 오류: $e');
      setState(() {
        _isUploading = false;
      });
      if (mounted) {
        AppSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.imageUploadFailed ?? "",
          type: AppSnackBarType.error,
        );
      }
      return null;
    }
  }

  Future<void> _submitReview() async {
    if (_selectedImages.isEmpty && _imageUrls.isEmpty) {
      final isKo = Localizations.localeOf(context).languageCode == 'ko';
      AppSnackBar.show(
        context,
        message: isKo ? '최소 1장의 사진을 선택해주세요' : 'Please select at least 1 photo',
        type: AppSnackBarType.warning,
      );
      return;
    }

    if (_contentController.text.trim().isEmpty) {
      AppSnackBar.show(
        context,
        message: AppLocalizations.of(context)!.pleaseEnterReviewContent ?? "",
        type: AppSnackBarType.warning,
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
          AppSnackBar.show(
            context,
            message: AppLocalizations.of(context)!.reviewUpdated ?? "",
            type: AppSnackBarType.success,
          );
          Navigator.of(context).pop(true);
        } else if (mounted) {
          AppSnackBar.show(
            context,
            message: AppLocalizations.of(context)!.reviewUpdateFailed ?? "",
            type: AppSnackBarType.error,
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
            AppSnackBar.show(
              context,
              message: AppLocalizations.of(context)!.reviewCreateFailed ?? "",
              type: AppSnackBarType.error,
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
            AppSnackBar.show(
              context,
              message: AppLocalizations.of(context)!
                      .reviewCreatedAndRequestsSent(participantIds.length) ??
                  "",
              type: AppSnackBarType.success,
            );
          } else {
            AppSnackBar.show(
              context,
              message: AppLocalizations.of(context)!
                      .reviewCreatedButNotificationFailed ??
                  "",
              type: AppSnackBarType.warning,
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
                builder: (context) =>
                    MainScreen(initialTabIndex: 2), // My Page 탭
              ),
            );
          }
        }
      }
    } catch (e) {
      Logger.error('❌ 후기 제출 오류: $e');
      if (mounted) {
        AppSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.error ?? "",
          type: AppSnackBarType.error,
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

  Widget _buildImageTile({
    File? imageFile,
    String? imageUrl,
    required VoidCallback onRemove,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
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
                        return const ColoredBox(
                          color: Color(0xFFF4F4F5),
                          child: Center(
                            child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const ColoredBox(
                          color: Color(0xFFF4F4F5),
                          child: Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        );
                      },
                    )
                  : const SizedBox.shrink(),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Semantics(
            button: true,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xCC111827),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 15,
                ),
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
    final l10n = AppLocalizations.of(context)!;
    final horizontal = MediaQuery.sizeOf(context).width < 360 ? 12.0 : 16.0;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final thumbnailExtent = context.rh(82, min: 74, max: 88);
    final selectedCount = _selectedImages.length + _imageUrls.length;
    final isBusy = _isLoading || _isUploading;

    return PopScope(
      canPop: !isBusy,
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.white,
          centerTitle: true,
          toolbarHeight: context.rh(56, min: 54, max: 60),
          automaticallyImplyLeading: false,
          leadingWidth: 48,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: const Color(0xFF111827),
              size: context.ri(22).clamp(21, 24).toDouble(),
            ),
            onPressed: isBusy ? null : () => Navigator.pop(context),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          title: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: Text(
              isEditMode ? l10n.reviewEditTitle : l10n.reviewWriteTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: context.rf(18).clamp(16, 19).toDouble(),
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827),
              ),
            ),
          ),
          actions: [
            SizedBox.square(
              dimension: 48,
              child: IconButton(
                onPressed: isBusy ? null : _submitReview,
                icon: isBusy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.check_rounded,
                        size: context.ri(23).clamp(21, 25).toDouble(),
                      ),
                color: const Color(0xFF111827),
                disabledColor: const Color(0xFFD1D5DB),
                tooltip: isEditMode
                    ? l10n.reviewEditTitle
                    : l10n.requestReviewAcceptance,
              ),
            ),
            const SizedBox(width: 2),
          ],
        ),
        body: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 8),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              horizontal,
              context.rs(8).clamp(6, 10).toDouble(),
              horizontal,
              context.rs(24).clamp(20, 28).toDouble(),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: context.rs(10).clamp(8, 12).toDouble(),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.event_outlined,
                            color: const Color(0xFF667085),
                            size: context.ri(20).clamp(19, 22).toDouble(),
                          ),
                          SizedBox(width: context.rs(10)),
                          Expanded(
                            child: Text(
                              widget.meetup.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize:
                                    context.rf(15).clamp(14, 16).toDouble(),
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF344054),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 20, color: Color(0xFFE5E7EB)),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.reviewPhoto,
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: context.rf(15).clamp(14, 16).toDouble(),
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF111827),
                            ),
                          ),
                        ),
                        Text(
                          '$selectedCount/$maxImages',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: context.rf(13).clamp(12, 14).toDouble(),
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: isBusy || selectedCount >= maxImages
                            ? null
                            : _pickImages,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF475467),
                          disabledForegroundColor: const Color(0xFFB8BDC7),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 8,
                          ),
                          minimumSize: const Size(44, 44),
                        ),
                        icon: Icon(
                          Icons.add_photo_alternate_outlined,
                          size: context.ri(21).clamp(20, 23).toDouble(),
                        ),
                        label: Text(
                          l10n.pickPhoto,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: context.rf(13).clamp(12, 14).toDouble(),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (selectedCount > 0) ...[
                      SizedBox(
                        height: thumbnailExtent,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: selectedCount,
                          separatorBuilder: (_, __) =>
                              SizedBox(width: context.rs(8)),
                          itemBuilder: (context, index) {
                            if (index < _imageUrls.length) {
                              return SizedBox.square(
                                dimension: thumbnailExtent,
                                child: _buildImageTile(
                                  imageUrl: _imageUrls[index],
                                  onRemove: () =>
                                      _removeImage(index, isUrl: true),
                                ),
                              );
                            }
                            final fileIndex = index - _imageUrls.length;
                            return SizedBox.square(
                              dimension: thumbnailExtent,
                              child: _buildImageTile(
                                imageFile: _selectedImages[fileIndex],
                                onRemove: () =>
                                    _removeImage(fileIndex, isUrl: false),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: context.rs(8)),
                    ],
                    Text(
                      isKo
                          ? '최대 $maxImages장까지 선택할 수 있어요.'
                          : 'Select up to $maxImages photos.',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: context.rf(12).clamp(11, 13).toDouble(),
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                    SizedBox(height: context.rs(22).clamp(18, 24).toDouble()),
                    Text(
                      l10n.reviewContent,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: context.rf(15).clamp(14, 16).toDouble(),
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    const Divider(height: 18, color: Color(0xFFE5E7EB)),
                    TextField(
                      controller: _contentController,
                      enabled: !isBusy,
                      minLines:
                          MediaQuery.sizeOf(context).height < 700 ? 7 : 10,
                      maxLines: null,
                      maxLength: 500,
                      textAlignVertical: TextAlignVertical.top,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: context.rf(15).clamp(14, 16).toDouble(),
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF111827),
                        height: 1.5,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.reviewWriteHint,
                        hintStyle: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: context.rf(15).clamp(14, 16).toDouble(),
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF9CA3AF),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(0, 2, 0, 4),
                        counterStyle: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: context.rf(12).clamp(11, 13).toDouble(),
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                    if (!isEditMode) ...[
                      SizedBox(height: context.rs(18)),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: const Color(0xFF667085),
                            size: context.ri(19).clamp(18, 21).toDouble(),
                          ),
                          SizedBox(width: context.rs(8)),
                          Expanded(
                            child: Text(
                              l10n.reviewRequestInfo,
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize:
                                    context.rf(12).clamp(11, 13).toDouble(),
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF667085),
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
