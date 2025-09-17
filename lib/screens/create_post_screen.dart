// 모임 생성 화면
// 모임 정보 입력 및 저장

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../services/post_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  Future<void> _submitPost() async {
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
        );

        if (success) {
          // 게시글 추가 완료 후 콜백 호출
          widget.onPostCreated();

          // 화면 닫기
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('게시글이 등록되었습니다.')));
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
            const SnackBar(
              content: Text('게시글 등록에 실패했습니다. 다시 시도해주세요.'),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('새 게시글 작성'),
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
                _isSubmitting ? '등록 중...' : '등록',
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
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
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
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: _getAvatarColor(nickname),
                      child: Text(
                        nickname.isNotEmpty ? nickname[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
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
                        '작성자',
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
              // 제목 입력 필드
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: '제목을 입력하세요',
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
                label: const Text('이미지 첨부'),
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
                    hintText: '내용을 입력하세요',
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
