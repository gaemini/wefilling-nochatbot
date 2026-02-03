// 모임 생성 화면
// 모임 정보 입력 및 저장

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../services/post_service.dart';
import '../constants/app_constants.dart';
import '../models/friend_category.dart';
import '../services/friend_category_service.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../widgets/friend_category_selector.dart';

class CreatePostScreen extends StatefulWidget {
  final Function onPostCreated;

  const CreatePostScreen({super.key, required this.onPostCreated});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen>
    with SingleTickerProviderStateMixin {
  final _contentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _contentFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _step1ScrollController = ScrollController();
  final List<File> _selectedImages = [];
  final PostService _postService = PostService();
  final List<TextEditingController> _pollOptionControllers = [];
  final GlobalKey _categorySectionKey = GlobalKey();
  final GlobalKey _contentSectionKey = GlobalKey();
  final GlobalKey _imagesSectionKey = GlobalKey();
  final GlobalKey _pollOptionsSectionKey = GlobalKey();
  late final TabController _tabController;
  
  // 친구 카테고리 관련
  final _friendCategoryService = FriendCategoryService();
  List<FriendCategory> _friendCategories = [];
  StreamSubscription<List<FriendCategory>>? _categoriesSubscription;

  bool _isSubmitting = false;
  bool _canSubmit = false;
  bool _canProceed = false;
  int _stepIndex = 0; // 0: Content, 1: Visibility (UI/PopScope 상태용)
  bool _didDismissKeyboardOnTabDrag = false; // 가로 스와이프 시작 시 1회만 키보드 내림
  
  // 공개 범위 설정
  String _visibility = 'category'; // 'public' 또는 'category' (기본: 카테고리별 공개)
  bool _isAnonymous = false; // 익명 여부
  List<String> _selectedCategoryIds = []; // 선택된 카테고리 ID 목록
  bool _showCategoryRequiredHint = false; // 카테고리 선택 필수 강조 표시
  
  // 게시글 타입 (일반/투표)
  String _postType = 'text'; // 'text' | 'poll'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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

    // 탭 전환: 순서 없이 자유롭게 이동 가능 (요청사항)
    _tabController.addListener(() {
      if (!mounted) return;
      final idx = _tabController.index;
      if (_stepIndex != idx) {
        // Content ↔ Visibility 전환 시 키보드가 남아 UX가 깨지는 문제 방지
        _dismissKeyboard();
        setState(() {
          _stepIndex = idx;
        });
      }
    });
  }

  void _dismissKeyboard() {
    // 일부 상황에서 FocusScope.unfocus()만으로 포커스가 남는 경우가 있어 보강
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
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
      final categoryOk = _visibility != 'category' || _selectedCategoryIds.isNotEmpty;
      if (_postType == 'poll') {
        // 투표: 질문(본문) + 선택지 2개(고정) 필수, 이미지 첨부는 선택
        _canProceed = contentNotEmpty && pollOptions.length == 2;
        _canSubmit = _canProceed && categoryOk;
      } else {
        // 일반글: 텍스트가 있거나 이미지가 있으면 등록 가능
        _canProceed = (contentNotEmpty || _selectedImages.isNotEmpty);
        _canSubmit = _canProceed && categoryOk;
      }
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    _contentFocusNode.dispose();
    _scrollController.dispose();
    _step1ScrollController.dispose();
    _tabController.dispose();
    for (final c in _pollOptionControllers) {
      c.dispose();
    }
    _categoriesSubscription?.cancel();
    _friendCategoryService.dispose();
    super.dispose();
  }

  void _setPostType(String value) {
    if (_postType == value) return;
    setState(() {
      _postType = value;
      if (value == 'poll') {
        _ensureMinimumPollOptions();
      }
    });
    _checkCanSubmit();
  }

  void _setVisibility(String value) {
    if (_visibility == value) return;
    setState(() {
      _visibility = value;
      _showCategoryRequiredHint = false;
      // 카테고리 공개에서는 익명 옵션을 허용하지 않음(기존 동작 유지)
      if (value == 'category') {
        _isAnonymous = false;
      }
    });
    _checkCanSubmit();
  }

  Widget _buildPostTypeOption({
    required String value,
    required String label,
  }) {
    final selected = _postType == value;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          // 다른 선택 컴포넌트(카테고리 선택 등)와 톤 통일: pointColor + 투명도
          color: selected ? AppColors.pointColor.withOpacity(0.10) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.pointColor : const Color(0xFFE5E7EB),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _setPostType(value),
            borderRadius: BorderRadius.circular(12),
            // 크기/톤 통일: 아이콘 제거 + 컴팩트한 높이
            child: SizedBox(
              height: 44,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVisibilityOption({
    required String value,
    required String label,
  }) {
    final selected = _visibility == value;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? AppColors.pointColor.withOpacity(0.10) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.pointColor : const Color(0xFFE5E7EB),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _setVisibility(value),
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 44,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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

  Future<void> _goToStep(int index) async {
    final next = index.clamp(0, 1);
    if (!mounted) return;
    _dismissKeyboard();
    _tabController.animateTo(next);
  }

  // 슬라이드/탭 기반 전환이라 별도 Next 버튼은 사용하지 않음

  Future<void> _submitPost() async {
    // 카테고리별 공개인 경우 카테고리 선택 여부 확인
    if (_visibility == 'category' && _selectedCategoryIds.isEmpty) {
      setState(() {
        _showCategoryRequiredHint = true;
      });
      HapticFeedback.selectionClick();
      // 해당 섹션으로 자동 스크롤 (사용자 인지 강화)
      final ctx = _categorySectionKey.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
      } else if (_scrollController.hasClients) {
        // 키가 아직 attach되지 않은 경우: 상단(공개범위 영역)으로 최대한 이동
        await _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.categorySelectAtLeastOne),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
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

    return PopScope(
      canPop: _stepIndex == 0,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_stepIndex == 1) {
          await _goToStep(0);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () async {
            if (_stepIndex == 1) {
              await _goToStep(0);
              return;
            }
            Navigator.pop(context);
          },
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: false,
              labelStyle: const TextStyle(
                fontFamily: 'Pretendard',
                fontWeight: FontWeight.w800,
              ),
              unselectedLabelStyle: const TextStyle(
                fontFamily: 'Pretendard',
                fontWeight: FontWeight.w700,
              ),
              dividerColor: Colors.transparent,
              indicator: const UnderlineTabIndicator(
                borderSide: BorderSide(color: AppColors.pointColor, width: 3),
                insets: EdgeInsets.symmetric(horizontal: 28),
              ),
              labelColor: const Color(0xFF111827),
              unselectedLabelColor: const Color(0xFF9CA3AF),
              onTap: (_) => _dismissKeyboard(),
              tabs: [
                Tab(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Text(Localizations.localeOf(context).languageCode == 'ko' ? '내용' : 'Content'),
                  ),
                ),
                Tab(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Text(Localizations.localeOf(context).languageCode == 'ko' ? '공개' : 'Visibility'),
                  ),
                ),
              ],
            ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: (_canSubmit && !_isSubmitting) ? _submitPost : null,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(
              AppLocalizations.of(context)!.registration,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontWeight: FontWeight.w700,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.pointColor,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      resizeToAvoidBottomInset: true,
        bottomNavigationBar: null,
        body: Form(
          key: _formKey,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // TabBarView(PageView) 가로 스와이프 시작 시점에 키보드를 즉시 내린다.
              if (notification.metrics.axis == Axis.horizontal) {
                final isUserDragStart = notification is ScrollStartNotification ||
                    (notification is ScrollUpdateNotification && notification.dragDetails != null);
                if (isUserDragStart && !_didDismissKeyboardOnTabDrag) {
                  _didDismissKeyboardOnTabDrag = true;
                  _dismissKeyboard();
                } else if (notification is ScrollEndNotification) {
                  _didDismissKeyboardOnTabDrag = false;
                }
              }
              return false; // 다른 리스너/스크롤 동작에 영향 없음
            },
            child: TabBarView(
              controller: _tabController,
              physics: const BouncingScrollPhysics(),
              children: [
            SingleChildScrollView(
              controller: _step1ScrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 16.0,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),

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
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.center,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildPostTypeOption(
                                    value: 'text',
                                    label: AppLocalizations.of(context)!.postTypeTextLabel,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildPostTypeOption(
                                    value: 'poll',
                                    label: AppLocalizations.of(context)!.postTypePollLabel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 이미지
                  Container(
                    key: _imagesSectionKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (_postType == 'poll') ...[
                    Container(
                      key: _pollOptionsSectionKey,
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
                          const SizedBox(height: 2),
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
                      ),
                    ),
                  ],

                  Container(
                    key: _contentSectionKey,
                    height: 200,
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
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(16),
                        fillColor: Colors.transparent,
                        filled: true,
                      ),
                      maxLines: null,
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
                ],
              ),
            ),

            SingleChildScrollView(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 16.0,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),

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
                        // 탭에 이미 Visibility가 있으므로, 섹션 내부 타이틀은 제거
                        Row(
                          children: [
                            Expanded(
                              child: _buildVisibilityOption(
                                value: 'public',
                                label: AppLocalizations.of(context)!.publicPost ?? "",
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildVisibilityOption(
                                value: 'category',
                                label: AppLocalizations.of(context)!.category,
                              ),
                            ),
                          ],
                        ),

                        if (_visibility == 'public') ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              // 카테고리 안내 박스와 톤/규격 통일 (amber)
                              color: const Color(0xFFFFFBEB), // amber-50
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFDE68A)), // amber-200
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: Color(0xFFB45309), // amber-700
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _isAnonymous
                                        ? (AppLocalizations.of(context)!.postAnonymously ?? "")
                                        : AppLocalizations.of(context)!.authorAndCommenterInfo,
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF92400E), // amber-800
                                      height: 1.25,
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
                                  ? '✓ ${AppLocalizations.of(context)!.postAnonymously}'
                                  : AppLocalizations.of(context)!.idWillBeShown,
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _isAnonymous ? const Color(0xFF10B981) : const Color(0xFF6B7280),
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

                        if (_visibility == 'category')
                          Container(
                            key: _categorySectionKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text(
                                      AppLocalizations.of(context)!.selectCategoryRequired,
                                      style: TextStyle(
                                        fontFamily: 'Pretendard',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: (_showCategoryRequiredHint && _selectedCategoryIds.isEmpty)
                                            ? const Color(0xFFB91C1C)
                                            : const Color(0xFF111827),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: (_selectedCategoryIds.isEmpty)
                                            ? const Color(0xFFFEE2E2)
                                            : const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        '${_selectedCategoryIds.length}개 선택',
                                        style: TextStyle(
                                          fontFamily: 'Pretendard',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: (_selectedCategoryIds.isEmpty)
                                              ? const Color(0xFF991B1B)
                                              : const Color(0xFF166534),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFFDE68A)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.info_outline,
                                        size: 18,
                                        color: Color(0xFFB45309),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          AppLocalizations.of(context)!.selectedGroupOnlyPost,
                                          style: const TextStyle(
                                            fontFamily: 'Pretendard',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF92400E),
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: (_showCategoryRequiredHint && _selectedCategoryIds.isEmpty)
                                        ? const Color(0xFFFFF1F2)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: (_showCategoryRequiredHint && _selectedCategoryIds.isEmpty)
                                          ? const Color(0xFFFCA5A5)
                                          : const Color(0xFFE5E7EB),
                                      width: (_showCategoryRequiredHint && _selectedCategoryIds.isEmpty) ? 1.5 : 1,
                                    ),
                                  ),
                                  child: FriendCategorySelector(
                                    categories: _friendCategories,
                                    selectedCategoryIds: _selectedCategoryIds,
                                    selectedColor: AppColors.pointColor,
                                    style: FriendCategorySelectorStyle.list,
                                    onSelectionChanged: (newSelection) {
                                      setState(() {
                                        _selectedCategoryIds = newSelection;
                                        if (newSelection.isNotEmpty) {
                                          _showCategoryRequiredHint = false;
                                        }
                                      });
                                      _checkCanSubmit();
                                    },
                                  ),
                                ),
                                if (_selectedCategoryIds.isEmpty && _friendCategories.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      AppLocalizations.of(context)!.categorySelectAtLeastOne,
                                      style: const TextStyle(
                                        color: Color(0xFFB91C1C),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Pretendard',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

// Draft 요약 UI는 Visibility 탭에서 제거함
