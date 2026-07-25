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
import '../utils/responsive_helper.dart';

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
      toolbarHeight: context.rh(56, min: 54, max: 60),
      automaticallyImplyLeading: false,
      leadingWidth: 48,
      leading: IconButton(
        icon: Icon(
          Icons.close_rounded,
          color: const Color(0xFF111827),
          size: context.ri(22).clamp(21, 24).toDouble(),
        ),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
      ),
      title: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: Text(
          l10n.newPostCreation,
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
            onPressed:
                (_canProceed && !_isSubmitting) ? _goToVisibilityStep : null,
            icon: Icon(
              Icons.arrow_forward_rounded,
              size: context.ri(23).clamp(21, 25).toDouble(),
            ),
            color: const Color(0xFF111827),
            disabledColor: const Color(0xFFD1D5DB),
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
          ),
        ),
        const SizedBox(width: 2),
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
      toolbarHeight: context.rh(56, min: 54, max: 60),
      automaticallyImplyLeading: false,
      leadingWidth: 48,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_rounded,
          color: const Color(0xFF111827),
          size: context.ri(22).clamp(21, 24).toDouble(),
        ),
        onPressed: _isSubmitting ? null : () => _goToStep(0),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      ),
      title: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: Text(
          l10n.newPostCreation,
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
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.15,
          child: TextButton.icon(
            onPressed: _isSubmitting ? null : _submitPost,
            icon: _isSubmitting
                ? const SizedBox.square(
                    dimension: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.check_rounded,
                    size: context.ri(18).clamp(17, 20).toDouble(),
                  ),
            label: Text(
              l10n.registration,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: context.rf(14).clamp(13, 15).toDouble(),
                fontWeight: FontWeight.w700,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF111827),
              disabledForegroundColor: const Color(0xFF9CA3AF),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(44, 44),
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildSectionLabel(String text, {String? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: context.rf(15).clamp(14, 16).toDouble(),
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: context.rf(13).clamp(12, 14).toDouble(),
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6B7280),
            ),
          ),
      ],
    );
  }

  Widget _buildAddImageButton(AppLocalizations l10n) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _selectImages,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF475467),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        icon: Icon(
          Icons.add_photo_alternate_outlined,
          size: context.ri(21).clamp(20, 23).toDouble(),
        ),
        label: Text(
          l10n.addImage,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: context.rf(13).clamp(12, 14).toDouble(),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedImagesStrip() {
    final thumbnailExtent = context.rh(76, min: 68, max: 82);
    return SizedBox(
      height: thumbnailExtent,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedAssets.length,
        separatorBuilder: (_, __) => SizedBox(width: context.rs(8)),
        itemBuilder: (context, index) {
          final asset = _selectedAssets[index];
          return GestureDetector(
            onTap: () => _previewSelectedImages(initialIndex: index),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image(
                    image: AssetEntityImageProvider(
                      asset,
                      isOriginal: false,
                      thumbnailSize: const ThumbnailSize.square(256),
                    ),
                    width: thumbnailExtent,
                    height: thumbnailExtent,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => _removeImage(index),
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
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildComposeBody() {
    final l10n = AppLocalizations.of(context)!;
    final imageLabel = l10n.imageAttachment;
    final screenSize = MediaQuery.sizeOf(context);
    final horizontalPadding = screenSize.width < 360 ? 12.0 : 16.0;
    final contentMinLines = screenSize.height < 700 ? 7 : 10;

    return SingleChildScrollView(
      controller: _composeScrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        context.rs(8).clamp(6, 10).toDouble(),
        horizontalPadding,
        24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
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
              SizedBox(height: context.rs(20).clamp(16, 22).toDouble()),
              _buildSectionLabel(
                imageLabel,
                trailing: '${_selectedAssets.length}/15',
              ),
              _buildAddImageButton(l10n),
              if (_selectedAssets.isNotEmpty) ...[
                SizedBox(height: context.rs(4)),
                _buildSelectedImagesStrip(),
                SizedBox(height: context.rs(6)),
              ],
              Text(
                l10n.postComposeImageHelper,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: context.rf(12).clamp(11, 13).toDouble(),
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF6B7280),
                ),
              ),
              SizedBox(height: context.rs(22).clamp(18, 24).toDouble()),
              _buildSectionLabel(l10n.content),
              const Divider(height: 18, color: Color(0xFFE5E7EB)),
              TextField(
                controller: _contentController,
                focusNode: _contentFocusNode,
                minLines: contentMinLines,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: l10n.enterContent,
                  hintStyle: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: context.rf(15).clamp(14, 16).toDouble(),
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF9CA3AF),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
                ),
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: context.rf(15).clamp(14, 16).toDouble(),
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF111827),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisibilityOption({
    required IconData icon,
    required String title,
    required String description,
    required bool selected,
    required VoidCallback onTap,
    Widget? child,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: context.rs(11).clamp(9, 13).toDouble(),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 30,
                      child: Icon(
                        icon,
                        color: const Color(0xFF667085),
                        size: context.ri(20).clamp(19, 22).toDouble(),
                      ),
                    ),
                    SizedBox(width: context.rs(10)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: context.rf(15).clamp(14, 16).toDouble(),
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            description,
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: context.rf(12).clamp(11, 13).toDouble(),
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF6B7280),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: context.ri(23).clamp(22, 25).toDouble(),
                      color: selected
                          ? const Color(0xFF344054)
                          : const Color(0xFFD0D5DD),
                    ),
                  ],
                ),
                if (child != null) ...[
                  SizedBox(height: context.rs(10)),
                  Padding(
                    padding: EdgeInsets.only(left: context.rs(40)),
                    child: child,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnonymousToggle() {
    final l10n = AppLocalizations.of(context)!;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.postAnonymously,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: context.rf(14).clamp(13, 15).toDouble(),
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.idWillBeShown,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: context.rf(12).clamp(11, 13).toDouble(),
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            height: 40,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Switch(
                value: _isAnonymous,
                onChanged: (value) {
                  setState(() {
                    _isAnonymous = value;
                  });
                },
                activeThumbColor: Colors.white,
                activeTrackColor: const Color(0xFF475467),
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFD0D5DD),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSelectionButton(FriendCategory category) {
    final isSelected = _selectedCategoryIds.contains(category.id);

    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: context.rf(14).clamp(13, 15).toDouble(),
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: const Color(0xFF111827),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: context.ri(21).clamp(20, 23).toDouble(),
                    color: isSelected
                        ? const Color(0xFF475467)
                        : const Color(0xFFD0D5DD),
                  ),
                ],
              ),
            ),
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
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: context.rf(13).clamp(12, 14).toDouble(),
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        if (_isLoadingAudienceUsers)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_selectedAudienceUsers.isEmpty)
          Text(
            l10n.postSelectedPeopleEmpty,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: context.rf(12.5).clamp(12, 13.5).toDouble(),
              fontWeight: FontWeight.w500,
              color: const Color(0xFF98A2B3),
            ),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: _selectedAudienceUsers
                .map(
                  (user) => Text(
                    user.displayNameOrNickname,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: context.rf(13).clamp(12, 14).toDouble(),
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF344054),
                    ),
                  ),
                )
                .toList(growable: false),
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
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _selectedCategoryIds.isEmpty
                  ? l10n.postVisibilityNoGroupsSelected
                  : l10n.postVisibilityGroupsSelected(
                      _selectedCategoryIds.length),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF667085),
              ),
            ),
          ),
        Column(
          children: [
            for (var index = 0; index < _friendCategories.length; index++) ...[
              _buildGroupSelectionButton(_friendCategories[index]),
              if (index != _friendCategories.length - 1)
                const Divider(height: 1, color: Color(0xFFEAECF0)),
            ],
          ],
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
        SizedBox(height: context.rs(16)),
        const Divider(height: 1, color: Color(0xFFEAECF0)),
        SizedBox(height: context.rs(14)),
        _buildSelectedAudienceNames(l10n),
      ],
    );
  }

  Widget _buildVisibilityBody() {
    final l10n = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth < 360 ? 12.0 : 16.0;

    return SingleChildScrollView(
      controller: _visibilityScrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        context.rs(12).clamp(10, 16).toDouble(),
        horizontalPadding,
        24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.postComposeVisibilityPrompt,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: context.rf(17).clamp(15.5, 18).toDouble(),
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827),
                ),
              ),
              SizedBox(height: context.rs(14)),
              _buildVisibilityOption(
                icon: Icons.public_outlined,
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
              const Divider(height: 1, indent: 40, color: Color(0xFFEAECF0)),
              Padding(
                padding: EdgeInsets.only(
                  left: context.rs(40),
                  top: context.rs(5),
                  bottom: context.rs(5),
                ),
                child: _buildAnonymousToggle(),
              ),
              const Divider(height: 1, indent: 40, color: Color(0xFFEAECF0)),
              _buildVisibilityOption(
                icon: Icons.group_outlined,
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
        ),
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
        resizeToAvoidBottomInset: true,
        appBar:
            _stepIndex == 0 ? _buildComposeAppBar() : _buildVisibilityAppBar(),
        body: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 8),
          child: _buildAnimatedBody(),
        ),
      ),
    );
  }
}
