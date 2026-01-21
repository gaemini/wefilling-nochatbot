// 모임 생성 화면
// 모임 정보 입력 및 저장

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../services/post_service.dart';
import '../constants/app_constants.dart';
import '../models/friend_category.dart';
import '../services/friend_category_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../widgets/friend_category_selector.dart';

class CreatePostScreen extends StatefulWidget {
  final Function onPostCreated;

  const CreatePostScreen({super.key, required this.onPostCreated});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _contentFocusNode = FocusNode();
  final List<File> _selectedImages = [];
  final PostService _postService = PostService();
  final List<TextEditingController> _pollOptionControllers = [];
  
  // 친구 카테고리 관련
  final _friendCategoryService = FriendCategoryService();
  List<FriendCategory> _friendCategories = [];
  StreamSubscription<List<FriendCategory>>? _categoriesSubscription;

  bool _isSubmitting = false;
  bool _canSubmit = false;
  
  // 공개 범위 설정
  String _visibility = 'public'; // 'public' 또는 'category'
  bool _isAnonymous = false; // 익명 여부
  List<String> _selectedCategoryIds = []; // 선택된 카테고리 ID 목록
  
  // 게시글 타입 (일반/투표)
  String _postType = 'text'; // 'text' | 'poll'

  @override
  void initState() {
    super.initState();
    // 텍스트 컨트롤러에 리스너 추가
    _contentController.addListener(_checkCanSubmit);
    // 포커스 노드에 리스너 추가
    _contentFocusNode.addListener(() {
      setState(() {}); // 포커스 상태가 변경되면 화면 갱신
    });
    
    // 친구 카테고리 로드
    _loadFriendCategories();

    // 투표 선택지 기본 2개 생성
    _ensureMinimumPollOptions();
  }

  void _ensureMinimumPollOptions() {
    if (_pollOptionControllers.isNotEmpty) return;
    for (int i = 0; i < 2; i++) {
      final c = TextEditingController();
      c.addListener(_checkCanSubmit);
      _pollOptionControllers.add(c);
    }
    _checkCanSubmit();
  }

  List<String> _getCleanedPollOptions() {
    return _pollOptionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  // 친구 카테고리 로드
  void _loadFriendCategories() {
    _categoriesSubscription?.cancel();
    _categoriesSubscription = _friendCategoryService.getCategoriesStream().listen((categories) {
      if (mounted) {
        setState(() {
          _friendCategories = categories;
        });
      }
    });
  }

  // 제목과 본문이 모두 입력되었는지 확인
  void _checkCanSubmit() {
    final contentNotEmpty = _contentController.text.trim().isNotEmpty;
    final pollOptions = _getCleanedPollOptions();

    setState(() {
      if (_postType == 'poll') {
        // 투표: 질문(본문) + 선택지 2개(고정) 필수, 이미지 첨부는 선택
        _canSubmit = contentNotEmpty && pollOptions.length == 2;
      } else {
        // 일반글: 텍스트가 있거나 이미지가 있으면 등록 가능
        _canSubmit = contentNotEmpty || _selectedImages.isNotEmpty;
      }
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    _contentFocusNode.dispose();
    for (final c in _pollOptionControllers) {
      c.dispose();
    }
    _categoriesSubscription?.cancel();
    _friendCategoryService.dispose();
    super.dispose();
  }

  Future<void> _selectImages() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _selectedImages.clear(); // 기존 이미지 삭제
        for (final xFile in pickedFiles) {
          _selectedImages.add(File(xFile.path));
        }
      });

      // 이미지 선택 후 용량 확인 및 경고
      _checkImagesSize();

      // 이미지 선택만으로도 등록 가능 상태가 바뀔 수 있음
      _checkCanSubmit();
    }
  }

  // 이미지 용량 체크
  Future<void> _checkImagesSize() async {
    int totalSize = 0;
    for (final image in _selectedImages) {
      totalSize += await image.length();
    }

    // 총 용량이 10MB를 초과하면 경고
    final sizeInMB = totalSize / (1024 * 1024);
    if (sizeInMB > 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.totalImageSizeWarning(sizeInMB.toStringAsFixed(1)),
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _submitPost() async {
    // 카테고리별 공개인 경우 카테고리 선택 여부 확인
    if (_visibility == 'category' && _selectedCategoryIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.categorySelectAtLeastOne),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isSubmitting = true;
      });

      try {
        // Firebase에 게시글 저장
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final user = authProvider.user;
        final userData = authProvider.userData;
        final nickname = userData?['nickname'] ?? '익명';

        // 이미지가 있는 경우 프로그레스 다이얼로그 표시
        if (_selectedImages.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.postImageUploading),
                duration: Duration(seconds: 5),
              ),
            );
          }
        }

        // PostService를 사용하여 게시글 저장
        final success = await _postService.addPost(
          '', // 제목 입력 제거
          _contentController.text.trim(),
          imageFiles: _selectedImages.isNotEmpty ? _selectedImages : null,
          visibility: _visibility,
          isAnonymous: _isAnonymous,
          visibleToCategoryIds: _selectedCategoryIds,
          type: _postType,
          pollOptions: _postType == 'poll' ? _getCleanedPollOptions() : const [],
        );

        if (success) {
          // 게시글 추가 완료 후 콜백 호출
          widget.onPostCreated();

          // 화면 닫기
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.postCreated ?? "")));
          }
        } else {
          throw Exception("게시글 등록 실패");
        }
      } catch (e) {
        Logger.error('게시글 작성 오류: $e');
        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.postCreateFailed ?? ""),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Color _getAvatarColor(String text) {
    if (text.isEmpty) return Colors.grey;
    final colors = [
      Colors.blue.shade700,
      Colors.purple.shade700,
      Colors.green.shade700,
      Colors.orange.shade700,
      Colors.pink.shade700,
      Colors.teal.shade700,
    ];

    // 이름의 첫 글자 아스키 코드를 기준으로 색상 결정
    final index = text.codeUnitAt(0) % colors.length;
    return colors[index];
  }

  // 선택한 이미지 삭제
  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
    _checkCanSubmit();
  }

  @override
  Widget build(BuildContext context) {
    // AuthProvider는 익명/공개범위 등 동작에 사용되므로 유지 (상단 Author UI는 제거)
    Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)!.newPostCreation ?? "",
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: (_canSubmit && !_isSubmitting) ? _submitPost : null,
              icon:
                  _isSubmitting
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.pointColor,
                        ),
                      )
                      : Icon(
                        Icons.check_circle,
                        color: _canSubmit 
                            ? AppColors.pointColor
                            : const Color(0xFF9CA3AF),
                      ),
              label: Text(
                _isSubmitting ? (AppLocalizations.of(context)!.loading ?? "") : AppLocalizations.of(context)!.registration,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  color: _canSubmit 
                      ? AppColors.pointColor
                      : const Color(0xFF9CA3AF),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 16.0,
            right: 16.0,
            top: 16.0,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 작성 타입 선택 (일반/투표)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16.0),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.postTypeSectionTitle,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: Text(
                              AppLocalizations.of(context)!.postTypeTextLabel,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF374151),
                              ),
                            ),
                            value: 'text',
                            groupValue: _postType,
                            onChanged: (value) {
                              setState(() {
                                _postType = value!;
                              });
                              _checkCanSubmit();
                            },
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            activeColor: AppColors.pointColor,
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: Text(
                              AppLocalizations.of(context)!.postTypePollLabel,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF374151),
                              ),
                            ),
                            value: 'poll',
                            groupValue: _postType,
                            onChanged: (value) {
                              setState(() {
                                _postType = value!;
                                _ensureMinimumPollOptions();
                              });
                              _checkCanSubmit();
                            },
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            activeColor: AppColors.pointColor,
                          ),
                        ),
                      ],
                    ),
                    if (_postType == 'poll') ...[
                      const SizedBox(height: 10),
                      Text(
                        AppLocalizations.of(context)!.postTypePollHelper,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 상단 Author 정보 영역 제거 (요구사항: 작성 화면 UI 단순화)
              // 공개 범위 선택
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16.0),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.visibilityScope,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 전체 공개 / 카테고리별 공개 선택
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: Text(
                              AppLocalizations.of(context)!.publicPost ?? "",
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF374151),
                              ),
                            ),
                            value: 'public',
                            groupValue: _visibility,
                            onChanged: (value) {
                              setState(() {
                                _visibility = value!;
                                if (_visibility == 'category') {
                                  _isAnonymous = false; // 카테고리 공개 시 익명 해제
                                }
                              });
                            },
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            activeColor: AppColors.pointColor,
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: Text(
                              AppLocalizations.of(context)!.categorySpecific ?? "",
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF374151),
                              ),
                            ),
                            value: 'category',
                            groupValue: _visibility,
                            onChanged: (value) {
                              setState(() {
                                _visibility = value!;
                                if (_visibility == 'category') {
                                  _isAnonymous = false; // 카테고리 공개 시 익명 해제
                                }
                              });
                            },
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            activeColor: AppColors.pointColor,
                          ),
                        ),
                      ],
                    ),
                    
                    // 익명 체크박스 (전체 공개일 때만 표시)
                    if (_visibility == 'public') ...[
                      const SizedBox(height: 8),
                      // 안내 메시지
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFD1D5DB)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: AppColors.pointColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _isAnonymous
                                    ? (AppLocalizations.of(context)!.postAnonymously ?? "") : AppLocalizations.of(context)!.authorAndCommenterInfo,
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF374151),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      CheckboxListTile(
                        title: Text(
                          AppLocalizations.of(context)!.postAnonymously,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827),
                          ),
                        ),
                        subtitle: Text(
                          _isAnonymous 
                              ? '✓ ' + AppLocalizations.of(context)!.postAnonymously
                              : AppLocalizations.of(context)!.idWillBeShown,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _isAnonymous 
                                ? const Color(0xFF10B981) 
                                : const Color(0xFF6B7280),
                          ),
                        ),
                        value: _isAnonymous,
                        onChanged: (value) {
                          setState(() {
                            _isAnonymous = value ?? false;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeColor: AppColors.pointColor,
                      ),
                    ],
                    
                    // 카테고리 선택 (카테고리별 공개일 때만 표시)
                    if (_visibility == 'category')
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          // 안내 메시지
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFD1D5DB)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info_outline, size: 16, color: Color(0xFF10B981)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    AppLocalizations.of(context)!.selectedGroupOnly,
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF374151),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          
                          FriendCategorySelector(
                            categories: _friendCategories,
                            selectedCategoryIds: _selectedCategoryIds,
                            onSelectionChanged: (newSelection) {
                              setState(() {
                                _selectedCategoryIds = newSelection;
                              });
                            },
                          ),

                          if (_selectedCategoryIds.isEmpty && _friendCategories.isNotEmpty)
                             Padding(
                               padding: const EdgeInsets.only(top: 8.0),
                               child: Text(
                                 AppLocalizations.of(context)!.selectCategoryRequired ?? "카테고리를 선택해주세요.",
                                 style: const TextStyle(
                                   color: Colors.red,
                                   fontSize: 12,
                                   fontWeight: FontWeight.w500,
                                   fontFamily: 'Pretendard',
                                 ),
                               ),
                             ),
                        ],
                      ),
                  ],
                ),
              ),
              
              // 제목 입력 필드 제거 (요구사항: 제목 없이 작성)
              const SizedBox(height: 8),
              // 이미지 첨부 버튼
              ElevatedButton.icon(
                onPressed: _selectImages,
                icon: const Icon(Icons.image, size: 20),
                label: Text(
                  AppLocalizations.of(context)!.imageAttachment ?? "",
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: AppColors.pointColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 첨부된 이미지 표시
              if (_selectedImages.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedImages.length,
                    itemBuilder: (context, index) {
                      return Container(
                        margin: const EdgeInsets.only(right: 8.0),
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                _selectedImages[index],
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () => _removeImage(index),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
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
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),

              // 투표 선택지 입력 (투표 모드일 때만)
              if (_postType == 'poll') ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.pollOptionsTitle,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...List.generate(_pollOptionControllers.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _pollOptionControllers[index],
                                  decoration: InputDecoration(
                                    hintText: AppLocalizations.of(context)!.pollOptionHint(index + 1),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],

              // 내용 입력 필드 - 고정 높이로 시작하고 내용에 따라 스크롤
              Container(
                height: 200, // 고정 높이 설정
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _contentFocusNode.hasFocus
                        ? AppColors.pointColor
                        : const Color(0xFFE5E7EB),
                    width: _contentFocusNode.hasFocus ? 2 : 1,
                  ),
                  color: Colors.white,
                ),
                child: TextField(
                  controller: _contentController,
                  focusNode: _contentFocusNode,
                  decoration: InputDecoration(
                    hintText: _postType == 'poll'
                        ? AppLocalizations.of(context)!.pollQuestionHint
                        : AppLocalizations.of(context)!.enterContent,
                    hintStyle: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF9CA3AF),
                    ),
                    border: InputBorder.none, // 테두리 없애기 (컨테이너가 이미 테두리를 가짐)
                    contentPadding: const EdgeInsets.all(16),
                    fillColor: Colors.transparent,
                    filled: true,
                  ),
                  maxLines: null, // 여러 줄 입력 가능
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16, 
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF111827),
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 로딩 표시
              if (_isSubmitting)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
