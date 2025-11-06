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
      print('❌ 사용자가 로그인되지 않았습니다.');
      return;
    }

    try {
      print('🔍 카테고리 조회 시작');
      print('👤 사용자 UID: ${user.uid}');
      print('📍 경로: friend_categories (where userId == ${user.uid})');
      
      // Firestore에서 사용자의 친구 카테고리 목록 가져오기
      // 실제로는 friend_categories 컬렉션에 저장되어 있음
      final categoriesSnapshot = await FirebaseFirestore.instance
          .collection('friend_categories')
          .where('userId', isEqualTo: user.uid)
          .get();

      print('📊 조회된 카테고리 개수: ${categoriesSnapshot.docs.length}');
      
      if (categoriesSnapshot.docs.isNotEmpty) {
        print('✅ 카테고리 목록:');
        for (var doc in categoriesSnapshot.docs) {
          print('  - ID: ${doc.id}, 데이터: ${doc.data()}');
        }
      }

      if (categoriesSnapshot.docs.isEmpty) {
        print('⚠️ 카테고리가 비어있습니다.');
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
      print('❌ 카테고리 로드 오류: $e');
      print('스택 트레이스: $stackTrace');
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
        print('게시글 작성 오류: $e');
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
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.newPostCreation ?? ""),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: (_canSubmit && !_isSubmitting) ? _submitPost : null,
              icon:
                  _isSubmitting
                      ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color:
                              _canSubmit
                                  ? Colors.blue.shade700
                                  : Colors.grey[400],
                        ),
                      )
                      : Icon(
                        Icons.check_circle,
                        color:
                            _canSubmit
                                ? Colors.blue.shade700
                                : Colors.grey[400],
                      ),
              label: Text(
                _isSubmitting ? (AppLocalizations.of(context)!.loading ?? "") : AppLocalizations.of(context)!.registration,
                style: TextStyle(
                  color: _canSubmit ? Colors.blue.shade700 : Colors.grey[400],
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
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
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[300],
                      ),
                      child: photoURL != null
                          ? ClipOval(
                              child: Image.network(
                                photoURL,
                                width: 36,
                                height: 36,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.person,
                                  size: 18,
                                  color: Colors.grey[600],
                                ),
                              ),
                            )
                          : Icon(
                              Icons.person,
                              size: 18,
                              color: Colors.grey[600],
                            ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      nickname,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.author,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
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
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.visibilityScope,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 전체 공개 / 카테고리별 공개 선택
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: Text(AppLocalizations.of(context)!.publicPost ?? ""),
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
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: Text(AppLocalizations.of(context)!.categorySpecific ?? ""),
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
                          ),
                        ),
                      ],
                    ),
                    
                    // 익명 체크박스 (전체 공개일 때만 표시)
                    if (_visibility == 'public') ...[
                      const SizedBox(height: 8),
                      // 안내 메시지
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _isAnonymous
                                    ? (AppLocalizations.of(context)!.postAnonymously ?? "") : AppLocalizations.of(context)!.authorAndCommenterInfo,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      CheckboxListTile(
                        title: Text(
                          AppLocalizations.of(context)!.postAnonymously,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          _isAnonymous 
                              ? '✓ ' + AppLocalizations.of(context)!.postAnonymously
                              : AppLocalizations.of(context)!.idWillBeShown,
                          style: TextStyle(
                            fontSize: 12,
                            color: _isAnonymous ? Colors.green.shade700 : Colors.grey.shade600,
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
                        activeColor: Colors.blue.shade700,
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
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, size: 16, color: Colors.green.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    AppLocalizations.of(context)!.selectedGroupOnly,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green.shade900,
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
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              backgroundColor: _selectedCategoryIds.isEmpty 
                                  ? Colors.orange.shade100 
                                  : null,
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.blue.shade400,
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
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 16),
              // 이미지 첨부 버튼
              ElevatedButton.icon(
                onPressed: _selectImages,
                icon: const Icon(Icons.image),
                label: Text(AppLocalizations.of(context)!.imageAttachment ?? ""),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.blue.shade700,
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
                    color:
                        _contentFocusNode.hasFocus
                            ? Colors.blue.shade400
                            : Colors.grey.shade300,
                    width: _contentFocusNode.hasFocus ? 2 : 1,
                  ),
                  color: Colors.white,
                ),
                child: TextField(
                  controller: _contentController,
                  focusNode: _contentFocusNode,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)!.enterContent,
                    border: InputBorder.none, // 테두리 없애기 (컨테이너가 이미 테두리를 가짐)
                    contentPadding: const EdgeInsets.all(16),
                    fillColor: Colors.transparent,
                    filled: true,
                  ),
                  maxLines: null, // 여러 줄 입력 가능
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 16, height: 1.5),
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
