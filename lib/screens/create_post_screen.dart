import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/friend_category.dart';
import '../models/post_category.dart';
import '../models/user_profile.dart';
import '../repositories/users_repository.dart';
import '../services/friend_category_service.dart';
import '../services/post_service.dart';
import '../ui/widgets/fullscreen_file_image_viewer.dart';
import '../ui/widgets/post_category_selector.dart';
import '../utils/logger.dart';

class CreatePostScreen extends StatefulWidget {
  final Function onPostCreated;
  final PostCategory? initialCategory;
  final FriendCategory? initialAudienceCategory;

  const CreatePostScreen({
    super.key,
    required this.onPostCreated,
    this.initialCategory,
    this.initialAudienceCategory,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentController = TextEditingController();
  final _contentFocusNode = FocusNode();
  final _composeScrollController = ScrollController();
  final _visibilityScrollController = ScrollController();
  final List<File> _selectedImages = [];
  final List<AssetEntity> _selectedAssets = [];
  final PostService _postService = PostService();
  final _friendCategoryService = FriendCategoryService();
  final _usersRepository = UsersRepository();

  StreamSubscription<List<FriendCategory>>? _categoriesSubscription;
  List<FriendCategory> _friendCategories = [];
  List<UserProfile> _selectedAudienceUsers = [];
  bool _isLoadingAudienceUsers = false;
  int _audienceLoadSeq = 0;

  bool _isSubmitting = false;
  bool _isForwardTransition = true;
  bool _canProceed = false;
  bool _isResolvingSelectedImages = false;
  int _stepIndex = 0;

  String _visibility = 'public';
  bool _isAnonymous = false;
  List<String> _selectedCategoryIds = [];
  bool _showCategoryRequiredHint = false;
  PostCategory? _selectedPostCategory;
  bool _showPostCategoryRequiredHint = false;

  @override
  void initState() {
    super.initState();
    _selectedPostCategory = widget.initialCategory;
    final initialAudienceCategory = widget.initialAudienceCategory;
    if (initialAudienceCategory != null) {
      _visibility = 'category';
      _selectedCategoryIds = <String>[initialAudienceCategory.id];
    }
    _contentController.addListener(_checkCanProceed);
    _contentFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _loadFriendCategories();
    _checkCanProceed();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _contentFocusNode.dispose();
    _composeScrollController.dispose();
    _visibilityScrollController.dispose();
    _categoriesSubscription?.cancel();
    _friendCategoryService.dispose();
    super.dispose();
  }

  void _loadFriendCategories() {
    _categoriesSubscription?.cancel();
    _categoriesSubscription =
        _friendCategoryService.getCategoriesStream().listen((categories) {
      if (!mounted) return;
      setState(() {
        _friendCategories = categories;
      });
      if (_selectedCategoryIds.isNotEmpty) {
        _refreshSelectedAudienceUsers();
      }
    });
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
  }

  void _checkCanProceed() {
    final contentNotEmpty = _contentController.text.trim().isNotEmpty;
    final hasImages = _selectedAssets.isNotEmpty;
    final canProceed =
        _selectedPostCategory != null && (contentNotEmpty || hasImages);

    if (!mounted) return;
    setState(() {
      _canProceed = canProceed;
    });
  }

  Set<String> _selectedAudienceIds() {
    final selectedSet = _selectedCategoryIds.toSet();
    final ids = <String>{};
    for (final category in _friendCategories) {
      if (!selectedSet.contains(category.id)) continue;
      ids.addAll(category.friendIds);
    }
    return ids;
  }

  Future<void> _refreshSelectedAudienceUsers() async {
    final currentSeq = ++_audienceLoadSeq;
    final audienceIds = _selectedAudienceIds().toList();

    if (audienceIds.isEmpty) {
      if (!mounted) return;
      setState(() {
        _selectedAudienceUsers = [];
        _isLoadingAudienceUsers = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoadingAudienceUsers = true;
    });

    final profiles = await _usersRepository.getUserProfilesBatch(audienceIds);
    profiles.sort(
      (left, right) =>
          left.displayNameOrNickname.compareTo(right.displayNameOrNickname),
    );

    if (!mounted || currentSeq != _audienceLoadSeq) return;
    setState(() {
      _selectedAudienceUsers = profiles;
      _isLoadingAudienceUsers = false;
    });
  }

  Future<List<File>> _resolveSelectedAssetFiles() async {
    if (_selectedAssets.isEmpty) return const <File>[];
    final resolved = await Future.wait(
      _selectedAssets.map((asset) async {
        try {
          final origin = await asset.originFile;
          return origin ?? await asset.file;
        } catch (_) {
          return null;
        }
      }),
    );
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

    setState(() {
      _isResolvingSelectedImages = true;
    });

    final files = await _resolveSelectedAssetFiles();
    if (!mounted) return;

    setState(() {
      _selectedImages
        ..clear()
        ..addAll(files);
      _isResolvingSelectedImages = false;
    });
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
    _checkCanProceed();
  }

  Future<void> _checkImagesSize() async {
    if (_selectedImages.isEmpty) return;

    var totalSize = 0;
    for (final image in _selectedImages) {
      totalSize += await image.length();
    }

    final sizeInMB = totalSize / (1024 * 1024);
    if (!mounted || sizeInMB <= 10) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!
              .totalImageSizeWarning(sizeInMB.toStringAsFixed(1)),
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _previewSelectedImages({int initialIndex = 0}) async {
    if (!mounted || _selectedAssets.isEmpty) return;

    if (_selectedImages.length != _selectedAssets.length) {
      await _syncSelectedImagesFromAssets();
    }
    if (!mounted || _selectedImages.isEmpty) return;

    await showFullscreenFileImageViewer(
      context,
      imageFiles: List<File>.unmodifiable(_selectedImages),
      initialIndex: initialIndex.clamp(0, _selectedImages.length - 1),
      heroTag: 'create_post_selected_images',
      showConfirmButton: false,
    );
  }

  Future<void> _removeImage(int index) async {
    setState(() {
      if (index >= 0 && index < _selectedAssets.length) {
        _selectedAssets.removeAt(index);
      }
    });
    await _syncSelectedImagesFromAssets();
    _checkCanProceed();
  }

  Future<void> _goToStep(int index) async {
    _dismissKeyboard();
    if (!mounted) return;
    setState(() {
      _isForwardTransition = index > _stepIndex;
      _stepIndex = index;
    });
  }

  Future<void> _goToVisibilityStep() async {
    final l10n = AppLocalizations.of(context)!;

    if (!_canProceed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.postDraftIncompleteMessage)),
      );
      return;
    }

    await _goToStep(1);
  }

  Future<bool> _confirmSubmitPost() async {
    if (!mounted) return false;

    HapticFeedback.mediumImpact();
    final l10n = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final bodyText = isKo ? '포스트를 등록할까요?' : 'Do you want to post this?';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          elevation: 8,
          contentPadding: const EdgeInsets.fromLTRB(24, 26, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          content: Text(
            bodyText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
              height: 1.35,
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      foregroundColor: const Color(0xFF6B7280),
                    ),
                    child: Text(
                      l10n.cancel,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: AppColors.pointColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      l10n.registration,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<void> _submitPost() async {
    final l10n = AppLocalizations.of(context)!;

    if (_selectedPostCategory == null) {
      setState(() => _showPostCategoryRequiredHint = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.postCategoryRequired)),
      );
      await _goToStep(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_composeScrollController.hasClients) return;
        _composeScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
      return;
    }

    if (_visibility == 'category' && _selectedCategoryIds.isEmpty) {
      setState(() {
        _showCategoryRequiredHint = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.groupSelectAtLeastOne)),
      );
      await _visibilityScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }

    if (_isResolvingSelectedImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.postPreparingImages)),
      );
      return;
    }

    final confirmed = await _confirmSubmitPost();
    if (!mounted || !confirmed) return;

    if (_selectedAssets.isNotEmpty &&
        _selectedImages.length != _selectedAssets.length) {
      await _syncSelectedImagesFromAssets();
    }
    if (!mounted) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      if (_selectedAssets.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.postImageUploading),
            duration: const Duration(seconds: 5),
          ),
        );
      }

      final success = await _postService.addPost(
        '',
        _contentController.text.trim(),
        categoryKey: _selectedPostCategory!.key,
        imageFiles: _selectedImages.isNotEmpty ? _selectedImages : null,
        visibility: _visibility,
        isAnonymous: _isAnonymous,
        visibleToCategoryIds: _selectedCategoryIds,
        type: 'text',
        pollOptions: const [],
      );

      if (!mounted) return;

      if (success) {
        widget.onPostCreated();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.postCreated)),
        );
        return;
      }

      throw Exception('포스트 등록 실패');
    } catch (error) {
      Logger.error('포스트 작성 오류: $error');
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.postCreateFailed),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  PreferredSizeWidget _buildComposeAppBar() {
    final l10n = AppLocalizations.of(context)!;

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.white,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Color(0xFF111827), size: 30),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        l10n.newPostCreation,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF111827),
        ),
      ),
      actions: [
        IconButton(
          onPressed:
              (_canProceed && !_isSubmitting) ? _goToVisibilityStep : null,
          icon: Icon(
            Icons.arrow_forward_rounded,
            size: 32,
            color: (_canProceed && !_isSubmitting)
                ? const Color(0xFF111827)
                : const Color(0xFFD1D5DB),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  PreferredSizeWidget _buildVisibilityAppBar() {
    final l10n = AppLocalizations.of(context)!;

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.white,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xFF111827), size: 30),
        onPressed: _isSubmitting ? null : () => _goToStep(0),
      ),
      title: Text(
        l10n.newPostCreation,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF111827),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _isSubmitting ? null : _submitPost,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(
            l10n.registration,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.pointColor,
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSectionLabel(String text, {String? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
      ],
    );
  }

  Widget _buildAddImageTile(AppLocalizations l10n) {
    return GestureDetector(
      onTap: _selectImages,
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFD1D5DB),
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined,
                color: Color(0xFF6B7280), size: 30),
            const SizedBox(height: 8),
            Text(
              l10n.addImage,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholderStrip() {
    return Expanded(
      child: Container(
        height: 110,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            for (var index = 0; index < 3; index++) ...[
              if (index > 0) const SizedBox(width: 10),
              Expanded(
                child: Align(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedImagesStrip() {
    return Expanded(
      child: SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _selectedAssets.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final asset = _selectedAssets[index];
            return GestureDetector(
              onTap: () => _previewSelectedImages(initialIndex: index),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image(
                      image: AssetEntityImageProvider(
                        asset,
                        isOriginal: false,
                        thumbnailSize: const ThumbnailSize.square(256),
                      ),
                      width: 110,
                      height: 110,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => _removeImage(index),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: Color(0xCC111827),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
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
    );
  }

  Widget _buildComposeBody() {
    final l10n = AppLocalizations.of(context)!;
    final imageLabel = l10n.imageAttachment;

    return SingleChildScrollView(
      controller: _composeScrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PostCategorySelector(
            selected: _selectedPostCategory,
            showError: _showPostCategoryRequiredHint,
            onChanged: (category) {
              setState(() {
                _selectedPostCategory = category;
                _showPostCategoryRequiredHint = false;
              });
              _checkCanProceed();
            },
          ),
          const SizedBox(height: 24),
          _buildSectionLabel(
            imageLabel,
            trailing: '${_selectedAssets.length}/15',
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAddImageTile(l10n),
              const SizedBox(width: 14),
              _selectedAssets.isEmpty
                  ? _buildImagePlaceholderStrip()
                  : _buildSelectedImagesStrip(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.postComposeImageHelper,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 28),
          _buildSectionLabel(l10n.content),
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(minHeight: 360),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _contentFocusNode.hasFocus
                    ? AppColors.pointColor
                    : const Color(0xFFD1D5DB),
                width: _contentFocusNode.hasFocus ? 1.5 : 1,
              ),
            ),
            child: TextField(
              controller: _contentController,
              focusNode: _contentFocusNode,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: l10n.enterContent,
                hintStyle: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF9CA3AF),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF111827),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisibilityOption({
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
    required String title,
    required String description,
    required bool selected,
    required VoidCallback onTap,
    Widget? child,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFF3F4F6)),
          ),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6B7280),
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? AppColors.pointColor
                          : const Color(0xFFD1D5DB),
                      width: 2.5,
                    ),
                  ),
                  child: selected
                      ? const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.pointColor,
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
            if (child != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 46),
                child: child,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnonymousToggle() {
    final l10n = AppLocalizations.of(context)!;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.postAnonymously,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.idWillBeShown,
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
        Switch(
          value: _isAnonymous,
          onChanged: (value) {
            setState(() {
              _isAnonymous = value;
            });
          },
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.pointColor,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: const Color(0xFF9CA3AF),
        ),
      ],
    );
  }

  Widget _buildGroupSelectionButton(FriendCategory category) {
    final isSelected = _selectedCategoryIds.contains(category.id);

    return GestureDetector(
      onTap: () {
        final nextSelection = List<String>.from(_selectedCategoryIds);
        if (isSelected) {
          nextSelection.remove(category.id);
        } else {
          nextSelection.add(category.id);
        }

        setState(() {
          _selectedCategoryIds = nextSelection;
          if (nextSelection.isNotEmpty) {
            _showCategoryRequiredHint = false;
          }
        });
        _refreshSelectedAudienceUsers();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 58,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F8EDB) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF111827) : const Color(0xFF111827),
            width: 1.6,
          ),
        ),
        child: Text(
          category.name,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : const Color(0xFF111827),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedAudienceNames(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.postSelectedPeopleTitle,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD1D5DB)),
          ),
          child: _isLoadingAudienceUsers
              ? const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _selectedAudienceUsers.isEmpty
                  ? Text(
                      l10n.postSelectedPeopleEmpty,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF9CA3AF),
                      ),
                    )
                  : Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: _selectedAudienceUsers
                          .map(
                            (user) => Text(
                              user.displayNameOrNickname,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
        ),
      ],
    );
  }

  Widget _buildGroupSelectionSection() {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_friendCategories.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _selectedCategoryIds.isEmpty
                  ? const Color(0xFFF3F4F6)
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _selectedCategoryIds.isEmpty
                  ? l10n.postVisibilityNoGroupsSelected
                  : l10n.postVisibilityGroupsSelected(
                      _selectedCategoryIds.length),
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _selectedCategoryIds.isEmpty
                    ? const Color(0xFF6B7280)
                    : AppColors.pointColor,
              ),
            ),
          ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: (_showCategoryRequiredHint && _selectedCategoryIds.isEmpty)
                ? const Color(0xFFFFF1F2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: (_showCategoryRequiredHint && _selectedCategoryIds.isEmpty)
                ? Border.all(color: const Color(0xFFFCA5A5), width: 1.2)
                : null,
          ),
          child: Column(
            children: [
              for (var index = 0;
                  index < _friendCategories.length;
                  index++) ...[
                _buildGroupSelectionButton(_friendCategories[index]),
                if (index != _friendCategories.length - 1)
                  const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        if (_showCategoryRequiredHint && _selectedCategoryIds.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.groupSelectAtLeastOne,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB91C1C),
              ),
            ),
          ),
        const SizedBox(height: 18),
        _buildSelectedAudienceNames(l10n),
      ],
    );
  }

  Widget _buildVisibilityBody() {
    final l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      controller: _visibilityScrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.postComposeVisibilityPrompt,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 22),
          _buildVisibilityOption(
            icon: Icons.public,
            iconColor: AppColors.pointColor,
            iconBackground: const Color(0xFFEFF6FF),
            title: l10n.postVisibilityPublicTitle,
            description: l10n.postVisibilityPublicDescription,
            selected: _visibility == 'public',
            onTap: () {
              setState(() {
                _visibility = 'public';
                _showCategoryRequiredHint = false;
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.only(left: 46, top: 10, bottom: 14),
            child: _buildAnonymousToggle(),
          ),
          _buildVisibilityOption(
            icon: Icons.change_history_rounded,
            iconColor: const Color(0xFFEF4444),
            iconBackground: const Color(0xFFFFF1F2),
            title: l10n.postVisibilityGroupTitle,
            description: l10n.postVisibilityGroupDescription,
            selected: _visibility == 'category',
            onTap: () {
              setState(() {
                _visibility = 'category';
              });
            },
            child: _visibility == 'category'
                ? _buildGroupSelectionSection()
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBody() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) {
        final beginOffset = Offset(_isForwardTransition ? 0.12 : -0.12, 0);
        return SlideTransition(
          position: Tween<Offset>(
            begin: beginOffset,
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(_stepIndex),
        child: _stepIndex == 0 ? _buildComposeBody() : _buildVisibilityBody(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stepIndex == 0 && !_isSubmitting,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isSubmitting) return;
        if (_stepIndex == 1) {
          await _goToStep(0);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar:
            _stepIndex == 0 ? _buildComposeAppBar() : _buildVisibilityAppBar(),
        body: _buildAnimatedBody(),
      ),
    );
  }
}
