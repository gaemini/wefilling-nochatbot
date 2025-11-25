// 모임 생성 화면
// 모임 정보 입력 및 저장

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../services/post_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';

class CreatePostScreen extends StatefulWidget {
  final Function onPostCreated;

  const CreatePostScreen({super.key, required this.onPostCreated});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _contentFocusNode = FocusNode();
  final List<File> _selectedImages = [];
  final PostService _postService = PostService();

  bool _isSubmitting = false;
  bool _canSubmit = false;
  
  // 공개 범위 설정
  String _visibility = 'public'; // 'public' 또는 'category'
  bool _isAnonymous = false; // 익명 여부
  List<String> _selectedCategoryIds = []; // 선택된 카테고리 ID 목록

  @override
  void initState() {
    super.initState();
    // 텍스트 컨트롤러에 리스너 추가
    _titleController.addListener(_checkCanSubmit);
    _contentController.addListener(_checkCanSubmit);
    // 포커스 노드에 리스너 추가
    _contentFocusNode.addListener(() {
      setState(() {}); // 포커스 상태가 변경되면 화면 갱신
    });
  }

  // 제목과 본문이 모두 입력되었는지 확인
  void _checkCanSubmit() {
    final titleNotEmpty = _titleController.text.trim().isNotEmpty;
    final contentNotEmpty = _contentController.text.trim().isNotEmpty;

    setState(() {
      _canSubmit = titleNotEmpty && contentNotEmpty;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
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
              '경고: 총 이미지 크기가 ${sizeInMB.toStringAsFixed(1)}MB입니다. 게시글 등록에 시간이 걸릴 수 있습니다.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // 카테고리 선택 다이얼로그
  Future<void> _selectCategories() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    
    if (user == null) {
      Logger.log('❌ 사용자가 로그인되지 않았습니다.');
      return;
    }

    try {
      Logger.log('🔍 카테고리 조회 시작');
      Logger.log('👤 사용자 UID: ${user.uid}');
      Logger.log('📍 경로: friend_categories (where userId == ${user.uid})');
      
      // Firestore에서 사용자의 친구 카테고리 목록 가져오기
      // 실제로는 friend_categories 컬렉션에 저장되어 있음
      final categoriesSnapshot = await FirebaseFirestore.instance
          .collection('friend_categories')
          .where('userId', isEqualTo: user.uid)
          .get();

      Logger.log('📊 조회된 카테고리 개수: ${categoriesSnapshot.docs.length}');
      
      if (categoriesSnapshot.docs.isNotEmpty) {
        Logger.log('✅ 카테고리 목록:');
        for (var doc in categoriesSnapshot.docs) {
          Logger.log('  - ID: ${doc.id}, 데이터: ${doc.data()}');
        }
      }

      if (categoriesSnapshot.docs.isEmpty) {
        Logger.log('⚠️ 카테고리가 비어있습니다.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('생성된 친구 카테고리가 없습니다. 먼저 카테고리를 생성해주세요.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      final categories = categoriesSnapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'name': doc.data()['name'] ?? '이름 없음',
        };
      }).toList();

      // 다중 선택 다이얼로그 표시
      final selected = await showDialog<List<String>>(
        context: context,
        builder: (context) {
          // 임시로 선택된 카테고리 저장
          List<String> tempSelected = List.from(_selectedCategoryIds);

          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(AppLocalizations.of(context)!.selectCategoriesToShare ?? ""),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: categories.map((category) {
                      final isSelected = tempSelected.contains(category['id']);
                      return CheckboxListTile(
                        title: Text(category['name']!),
                        value: isSelected,
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              tempSelected.add(category['id']!);
                            } else {
                              tempSelected.remove(category['id']);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppLocalizations.of(context)!.cancel ?? ""),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, tempSelected),
                    child: Text(AppLocalizations.of(context)!.confirm ?? ""),
                  ),
                ],
              );
            },
          );
        },
      );

      if (selected != null) {
        setState(() {
          _selectedCategoryIds = selected;
        });
      }
    } catch (e, stackTrace) {
      Logger.error('❌ 카테고리 로드 오류: $e');
      Logger.log('스택 트레이스: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('카테고리를 불러오는 중 오류가 발생했습니다: $e'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: '확인',
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }

  Future<void> _submitPost() async {
    // 카테고리별 공개인 경우 카테고리 선택 여부 확인
    if (_visibility == 'category' && _selectedCategoryIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('카테고리를 최소 1개 이상 선택해주세요.'),
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
              const SnackBar(
                content: Text('이미지를 업로드 중입니다. 잠시만 기다려주세요...'),
                duration: Duration(seconds: 5),
              ),
            );
          }
        }

        // PostService를 사용하여 게시글 저장
        final success = await _postService.addPost(
          _titleController.text.trim(),
          _contentController.text.trim(),
          imageFiles: _selectedImages.isNotEmpty ? _selectedImages : null,
          visibility: _visibility,
          isAnonymous: _isAnonymous,
          visibleToCategoryIds: _selectedCategoryIds,
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
  }

  @override
  Widget build(BuildContext context) {
    // 현재 유저의 닉네임 가져오기
    final authProvider = Provider.of<AuthProvider>(context);
    final nickname = authProvider.userData?['nickname'] ?? '익명';
    final photoURL = authProvider.user?.photoURL;

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
                          color: Color(0xFF5865F2),
                        ),
                      )
                      : Icon(
                        Icons.check_circle,
                        color: _canSubmit 
                            ? const Color(0xFF5865F2)
                            : const Color(0xFF9CA3AF),
                      ),
              label: Text(
                _isSubmitting ? (AppLocalizations.of(context)!.loading ?? "") : AppLocalizations.of(context)!.registration,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  color: _canSubmit 
                      ? const Color(0xFF5865F2)
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
              // 작성자 정보 표시
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                margin: const EdgeInsets.only(bottom: 16.0),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFE5E7EB),
                      ),
                      child: photoURL != null
                          ? ClipOval(
                              child: Image.network(
                                photoURL,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person,
                                  size: 20,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.person,
                              size: 20,
                              color: Color(0xFF6B7280),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      nickname,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.author,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 12,
                          color: Color(0xFF5865F2),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
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
                            activeColor: const Color(0xFF5865F2),
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
                            activeColor: const Color(0xFF5865F2),
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
                            const Icon(Icons.info_outline, size: 16, color: Color(0xFF5865F2)),
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
                        activeColor: const Color(0xFF5865F2),
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
                          ElevatedButton.icon(
                            onPressed: _selectCategories,
                            icon: const Icon(Icons.category, size: 18),
                            label: Text(
                              _selectedCategoryIds.isEmpty
                                  ? (AppLocalizations.of(context)!.selectCategoryRequired ?? "") : '${_selectedCategoryIds.length}${AppLocalizations.of(context)!.selectedCount}',
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              backgroundColor: _selectedCategoryIds.isEmpty 
                                  ? const Color(0xFFFFF3E0)
                                  : const Color(0xFF5865F2),
                              foregroundColor: _selectedCategoryIds.isEmpty
                                  ? const Color(0xFFFF8A65)
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              
              // 제목 입력 필드
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.enterTitle,
                  hintStyle: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF9CA3AF),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF5865F2),
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  fillColor: Colors.white,
                  filled: true,
                ),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 16),
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
                  backgroundColor: const Color(0xFF5865F2),
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
              // 내용 입력 필드 - 고정 높이로 시작하고 내용에 따라 스크롤
              Container(
                height: 200, // 고정 높이 설정
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _contentFocusNode.hasFocus
                        ? const Color(0xFF5865F2)
                        : const Color(0xFFE5E7EB),
                    width: _contentFocusNode.hasFocus ? 2 : 1,
                  ),
                  color: Colors.white,
                ),
                child: TextField(
                  controller: _contentController,
                  focusNode: _contentFocusNode,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)!.enterContent,
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
