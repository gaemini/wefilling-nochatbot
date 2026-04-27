// 피드 게시글 작성 화면
// 1단계: 이미지/내용 작성 -> 2단계: 공개 범위 설정

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/friend_category.dart';
import '../models/user_profile.dart';
import '../repositories/users_repository.dart';
import '../services/friend_category_service.dart';
import '../services/post_service.dart';
import '../ui/widgets/fullscreen_file_image_viewer.dart';
import '../utils/logger.dart';

class CreatePostScreen extends StatefulWidget {
  final Function onPostCreated;

  const CreatePostScreen({super.key, required this.onPostCreated});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _contentFocusNode = FocusNode();
  final FriendCategoryService _categoryService = FriendCategoryService();
  final UsersRepository _usersRepository = UsersRepository();
  final PostService _postService = PostService();

  late final TabController _tabController;
  StreamSubscription<List<FriendCategory>>? _categoriesSub;

  final List<AssetEntity> _selectedAssets = [];
  final List<File> _selectedImages = [];
  final List<FriendCategory> _categories = [];
  final Set<String> _selectedCategoryIds = {};
  List<UserProfile> _selectedPeople = const [];

  bool _isSubmitting = false;
  bool _isResolvingSelectedImages = false;
  bool _isAnonymous = false;
  int _stepIndex = 0;
  String _visibility = 'public'; // public | group

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!mounted) return;
      if (_stepIndex != _tabController.index) {
        setState(() => _stepIndex = _tabController.index);
      }
    });
    _categoriesSub = _categoryService.getCategoriesStream().listen((items) {
      if (!mounted) return;
      setState(() {
        _categories
          ..clear()
          ..addAll(items);
      });
      _syncSelectedPeople();
    });
  }

  @override
  void dispose() {
    _categoriesSub?.cancel();
    _categoryService.dispose();
    _tabController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _goToStep(int index) async {
    FocusManager.instance.primaryFocus?.unfocus();
    _tabController.animateTo(index.clamp(0, 1));
  }

  Future<void> _selectImages() async {
    final pickedAssets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        requestType: RequestType.image,
        selectedAssets: _selectedAssets,
        maxAssets: 15,
        dragToSelect: false,
      ),
    );

    if (!mounted || pickedAssets == null) return;
    setState(() {
      _selectedAssets
        ..clear()
        ..addAll(pickedAssets.take(15));
    });
    await _syncSelectedImagesFromAssets();
    await _checkImagesSize();
  }

  Future<List<File>> _resolveSelectedAssetFiles() async {
    final futures = _selectedAssets.map((asset) async {
      try {
        return await asset.originFile ?? await asset.file;
      } catch (_) {
        return null;
      }
    }).toList(growable: false);
    final resolved = await Future.wait(futures);
    return resolved.whereType<File>().toList(growable: false);
  }

  Future<void> _syncSelectedImagesFromAssets() async {
    if (!mounted) return;
    if (_selectedAssets.isEmpty) {
      setState(() {
        _selectedImages.clear();
        _isResolvingSelectedImages = false;
      });
      return;
    }

    setState(() => _isResolvingSelectedImages = true);
    final files = await _resolveSelectedAssetFiles();
    if (!mounted) return;
    setState(() {
      _selectedImages
        ..clear()
        ..addAll(files);
      _isResolvingSelectedImages = false;
    });
  }

  Future<void> _checkImagesSize() async {
    if (_selectedImages.isEmpty) return;
    var totalSize = 0;
    for (final image in _selectedImages) {
      totalSize += await image.length();
    }
    final sizeInMb = totalSize / (1024 * 1024);
    if (sizeInMb <= 10 || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!
              .totalImageSizeWarning(sizeInMb.toStringAsFixed(1)),
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _removeImage(int index) async {
    setState(() {
      if (index >= 0 && index < _selectedAssets.length) {
        _selectedAssets.removeAt(index);
      }
    });
    await _syncSelectedImagesFromAssets();
  }

  Future<void> _previewSelectedImages({int initialIndex = 0}) async {
    if (_selectedAssets.isEmpty) return;
    if (_selectedImages.length != _selectedAssets.length) {
      await _syncSelectedImagesFromAssets();
    }
    if (!mounted || _selectedImages.isEmpty) return;
    await showFullscreenFileImageViewer(
      context,
      imageFiles: List<File>.unmodifiable(_selectedImages),
      initialIndex: initialIndex.clamp(0, _selectedImages.length - 1),
      heroTag: 'create_feed_selected_images',
      showConfirmButton: false,
    );
  }

  void _setVisibility(String visibility) {
    setState(() {
      _visibility = visibility;
      if (visibility == 'public') {
        _selectedCategoryIds.clear();
      } else {
        _isAnonymous = false;
      }
    });
    _syncSelectedPeople();
  }

  void _toggleCategory(FriendCategory category) {
    setState(() {
      if (_selectedCategoryIds.contains(category.id)) {
        _selectedCategoryIds.remove(category.id);
      } else {
        _selectedCategoryIds.add(category.id);
      }
      _visibility = 'group';
      _isAnonymous = false;
    });
    _syncSelectedPeople();
  }

  Future<void> _syncSelectedPeople() async {
    final ids = _categories
        .where((category) => _selectedCategoryIds.contains(category.id))
        .expand((category) => category.friendIds)
        .toSet()
        .toList();
    if (ids.isEmpty) {
      if (mounted) setState(() => _selectedPeople = const []);
      return;
    }
    final profiles = await _usersRepository.getUserProfilesBatch(ids);
    if (!mounted) return;
    profiles.sort(
        (a, b) => a.displayNameOrNickname.compareTo(b.displayNameOrNickname));
    setState(() => _selectedPeople = profiles);
  }

  Future<void> _submitPost() async {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    if (_selectedAssets.isEmpty) {
      HapticFeedback.selectionClick();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo
                ? '사진을 1장 이상 첨부해주세요.'
                : 'Please attach at least one photo.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      await _goToStep(0);
      return;
    }
    if (_visibility == 'group' && _selectedCategoryIds.isEmpty) {
      HapticFeedback.selectionClick();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo ? '공개할 그룹을 선택해주세요.' : 'Please select a group to share with.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_isResolvingSelectedImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo
                ? '선택한 사진을 준비 중이에요. 잠시만 기다려주세요.'
                : 'Preparing selected photos. Please wait a moment.',
          ),
        ),
      );
      return;
    }
    if (_selectedImages.length != _selectedAssets.length) {
      await _syncSelectedImagesFromAssets();
    }
    if (!mounted) return;

    setState(() => _isSubmitting = true);
    try {
      final success = await _postService.addPost(
        '',
        _contentController.text.trim(),
        imageFiles: _selectedImages,
        visibility: _visibility == 'group' ? 'category' : 'public',
        isAnonymous: _visibility == 'public' && _isAnonymous,
        visibleToCategoryIds:
            _visibility == 'group' ? _selectedCategoryIds.toList() : const [],
        type: 'text',
        pollOptions: const [],
        category: '일반',
      );
      if (!mounted) return;
      if (!success) throw Exception('post create failed');
      widget.onPostCreated();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.postCreated)),
      );
    } catch (e) {
      Logger.error('피드 작성 오류: $e');
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.postCreateFailed),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stepIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goToStep(0);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(),
        body: TabBarView(
          controller: _tabController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildContentStep(),
            _buildVisibilityStep(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final isFirstStep = _stepIndex == 0;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: Icon(
          isFirstStep ? Icons.close_rounded : Icons.arrow_back_rounded,
          color: Colors.black,
          size: 30,
        ),
        onPressed: () {
          if (isFirstStep) {
            Navigator.of(context).pop();
          } else {
            _goToStep(0);
          }
        },
      ),
      title: Text(
        isKo ? '새 피드 작성' : 'New Feed Post',
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Colors.black,
        ),
      ),
      actions: [
        if (isFirstStep)
          IconButton(
            icon: const Icon(Icons.arrow_forward_rounded,
                color: Colors.black, size: 30),
            onPressed: () => _goToStep(1),
          )
        else
          TextButton.icon(
            onPressed: _isSubmitting ? null : _submitPost,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded, size: 22),
            label: Text(isKo ? '등록' : 'Post'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF2F6FDB),
              textStyle: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildContentStep() {
    final media = MediaQuery.of(context);
    final bottomSafePadding = media.padding.bottom;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        20,
        22,
        20,
        media.viewInsets.bottom + bottomSafePadding + 32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isKo
                      ? '이미지 첨부(1장 이상 필수)'
                      : 'Attach images (at least 1 required)',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
              Text(
                '${_selectedAssets.length}/15',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildImagePickerRow(),
          const SizedBox(height: 24),
          Text(
            isKo ? '내용' : 'Content',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 445,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD1D5DB)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: TextField(
              controller: _contentController,
              focusNode: _contentFocusNode,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(14),
              ),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                height: 1.45,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePickerRow() {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Row(
      children: [
        GestureDetector(
          onTap: _selectImages,
          child: CustomPaint(
            painter: const _DashedBorderPainter(
              color: Color(0xFFBDBDBD),
              radius: 12,
            ),
            child: Container(
              width: 92,
              height: 92,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add_a_photo,
                    color: Color(0xFF6B7280),
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isKo ? '추가하기' : 'Add',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      color: Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            height: 92,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(top: 8, bottom: 8, right: 8),
              itemCount: _selectedAssets.isEmpty ? 4 : _selectedAssets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                if (_selectedAssets.isEmpty) return _buildImagePlaceholder();
                final asset = _selectedAssets[index];
                return SizedBox(
                  width: 78,
                  height: 76,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned(
                        left: 4,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: () =>
                              _previewSelectedImages(initialIndex: index),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image(
                              image: AssetEntityImageProvider(
                                asset,
                                isOriginal: false,
                                thumbnailSize: const ThumbnailSize.square(256),
                              ),
                              width: 70,
                              height: 70,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () => _removeImage(index),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Color(0xCC111827),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 14,
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
        ),
      ],
    );
  }

  Widget _buildImagePlaceholder() {
    return Center(
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildVisibilityStep() {
    final media = MediaQuery.of(context);
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        32,
        22,
        32,
        media.viewInsets.bottom + media.padding.bottom + 36,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isKo ? '공개 대상을 선택해주세요.' : 'Choose who can see this post.',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 28),
          _buildVisibilityOption(
            value: 'public',
            icon: Icons.public_rounded,
            iconBg: const Color(0xFFEAF5FF),
            iconColor: AppColors.pointColor,
            title: isKo ? '모두에게 공개' : 'Public',
            subtitle: isKo
                ? '모든 사용자가 게시글을 볼 수 있습니다'
                : 'Everyone can see this post',
          ),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: _buildAnonymousRow(enabled: _visibility == 'public'),
          ),
          const SizedBox(height: 18),
          _buildVisibilityOption(
            value: 'group',
            customIcon: const Icon(
              Icons.change_history,
              size: 32,
              color: Color(0xFFFF4B1F),
            ),
            title: isKo ? '그룹 선택' : 'Select Group',
          ),
          if (_visibility == 'group') ...[
            const SizedBox(height: 20),
            _buildGroupSelector(),
            const SizedBox(height: 18),
            Text(
              isKo ? '선택된 사람들' : 'Selected People',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            _buildSelectedPeopleBox(),
          ],
        ],
      ),
    );
  }

  Widget _buildVisibilityOption({
    required String value,
    IconData? icon,
    Widget? customIcon,
    Color iconBg = Colors.transparent,
    Color iconColor = Colors.black,
    required String title,
    String? subtitle,
  }) {
    final selected = _visibility == value;
    return InkWell(
      onTap: () => _setVisibility(value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: customIcon ??
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: iconBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor, size: 24),
                  ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _RadioCircle(selected: selected),
          ],
        ),
      ),
    );
  }

  Widget _buildAnonymousRow({required bool enabled}) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(left: 14),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_off_outlined, size: 22, color: Colors.black),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isKo ? '익명으로 게시' : 'Post Anonymously',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isKo ? '아이디가 공개되지 않습니다' : 'Your ID will not be shown',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled && _isAnonymous,
            onChanged: enabled
                ? (value) => setState(() => _isAnonymous = value)
                : null,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF2F6FDB),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFBDBDBD),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSelector() {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    if (_categories.isEmpty) {
      return Text(
        isKo ? '생성된 그룹이 없습니다.' : 'No groups have been created.',
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 14,
          color: Color(0xFF6B7280),
        ),
      );
    }
    return Column(
      children: _categories.map((category) {
        final selected = _selectedCategoryIds.contains(category.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: InkWell(
            onTap: () => _toggleCategory(category),
            borderRadius: BorderRadius.circular(5),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: double.infinity,
              height: 60,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 36),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF4A90E2) : Colors.white,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.black, width: 1.5),
              ),
              child: Text(
                category.name,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : Colors.black,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSelectedPeopleBox() {
    final text = _selectedPeople
        .map((user) => user.displayNameOrNickname)
        .where((name) => name.trim().isNotEmpty)
        .join('   ');
    return Container(
      width: double.infinity,
      height: 126,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD1D5DB)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Colors.black,
          height: 1.5,
        ),
      ),
    );
  }
}

class _RadioCircle extends StatelessWidget {
  final bool selected;

  const _RadioCircle({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFF2F6FDB) : const Color(0xFFBDBDBD),
          width: 3,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF2F6FDB),
                ),
              ),
            )
          : null,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({
    required this.color,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 6.0;
      const gap = 4.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
