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

class CreateMeetupReviewScreen extends StatefulWidget {
  final Meetup meetup;
  final String? existingReviewId; // 수정 모드일 경우
  final String? existingImageUrl;
  final String? existingContent;

  const CreateMeetupReviewScreen({
    Key? key,
    required this.meetup,
    this.existingReviewId,
    this.existingImageUrl,
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
    if (widget.existingImageUrl != null && widget.existingImageUrl!.isNotEmpty) {
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
          SnackBar(content: Text(AppLocalizations.of(context)?.imagePickFailed)),
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
          SnackBar(content: Text(AppLocalizations.of(context)?.imageUploadFailed)),
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
        SnackBar(content: Text(AppLocalizations.of(context)?.pleaseEnterReviewContent)),
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
        // 수정 모드 - MeetupService의 updateMeetupReview가 imageUrls를 지원해야 함
        // 현재는 단일 imageUrl만 지원하므로 첫 번째 이미지만 전달
        final success = await _meetupService.updateMeetupReview(
          reviewId: widget.existingReviewId!,
          imageUrl: imageUrls.first,
          content: _contentController.text.trim(),
        );

        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)?.reviewUpdated)),
          );
          Navigator.of(context).pop(true);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)?.reviewUpdateFailed)),
          );
        }
      } else {
        // 생성 모드 - MeetupService의 createMeetupReview가 imageUrls를 지원해야 함
        // 현재는 단일 imageUrl만 지원하므로 첫 번째 이미지만 전달
        final reviewId = await _meetupService.createMeetupReview(
          meetupId: widget.meetup.id,
          imageUrl: imageUrls.first,
          content: _contentController.text.trim(),
        );

        if (reviewId == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context)?.reviewCreateFailed)),
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
                content: Text(AppLocalizations.of(context)?.reviewCreatedAndRequestsSent(participantIds.length)),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)?.reviewCreatedButNotificationFailed),
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
          SnackBar(content: Text(AppLocalizations.of(context)?.error)),
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
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
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
                            color: Colors.grey[300],
                            child: Icon(Icons.broken_image, color: Colors.grey[600]),
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
      appBar: AppBar(
        title: Text(isEditMode ? AppLocalizations.of(context)?.reviewEditTitle : AppLocalizations.of(context)?.reviewWriteTitle),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 모임 정보
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.event, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.meetup.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[900],
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
                  AppLocalizations.of(context)?.reviewPhoto,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_selectedImages.length + _imageUrls.length}/$maxImages',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
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
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate, size: 32, color: Colors.grey[400]),
                          const SizedBox(height: 4),
                          Text(
                            '사진 추가',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
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
              AppLocalizations.of(context)?.reviewContent,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              enabled: !_isLoading,
              maxLines: 8,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)?.reviewWriteHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
            const SizedBox(height: 24),

            // 제출 버튼
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading || _isUploading ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
                        isEditMode ? AppLocalizations.of(context)?.reviewEditTitle : AppLocalizations.of(context)?.requestReviewAcceptance,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // 안내 문구
            if (!isEditMode)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber[200]!),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber[800], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)?.reviewRequestInfo,
                        style: TextStyle(
                          color: Colors.amber[900],
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

