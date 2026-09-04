import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../constants/app_constants.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../models/friend_category.dart';
import '../models/external_share_request.dart';
import '../models/post_category.dart';
import '../models/shared_link_preview.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../repositories/users_repository.dart';
import '../services/cache/app_image_cache_manager.dart';
import '../services/friend_category_service.dart';
import '../services/post_service.dart';
import '../services/shared_link_preview_service.dart';
import '../ui/widgets/fullscreen_file_image_viewer.dart';
import '../ui/widgets/group_audience_preview.dart';
import '../ui/widgets/instagram_embed_preview.dart';
import '../ui/widgets/post_category_selector.dart';
import '../ui/widgets/shared_link_preview_card.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';
import 'post_detail_screen.dart';

class CreatePostScreen extends StatefulWidget {
  final Function onPostCreated;
  final PostCategory? initialCategory;
  final FriendCategory? initialAudienceCategory;
  final ExternalShareRequest? initialSharedRequest;
  final VoidCallback? onSharedRequestReady;
  final Future<bool> Function(String postId)? onSharedPostCreated;
  final Future<bool> Function(ExternalShareDraft draft)? onSharedDraftSave;
  final bool stayInAppAfterSharedPost;

  const CreatePostScreen({
    super.key,
    required this.onPostCreated,
    this.initialCategory,
    this.initialAudienceCategory,
    this.initialSharedRequest,
    this.onSharedRequestReady,
    this.onSharedPostCreated,
    this.onSharedDraftSave,
    this.stayInAppAfterSharedPost = false,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const int _maxPostImages = 15;
  static const double _pickedImageMaxDimension = 2400;
  static const int _pickedImageQuality = 88;

  final _contentController = TextEditingController();
  final _contentFocusNode = FocusNode();
  final _composeScrollController = ScrollController();
  final _visibilityScrollController = ScrollController();
  final List<File> _selectedImages = [];
  final List<AssetEntity> _selectedAssets = [];
  final List<File> _standaloneImages = [];
  final ImagePicker _imagePicker = ImagePicker();
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
  bool _requiresHanyangVerification = false;
  bool _isAnonymous = false;
  List<String> _selectedCategoryIds = [];
  bool _showCategoryRequiredHint = false;
  final Set<PostCategory> _selectedPostTags = <PostCategory>{};
  bool _showPostTagRequiredHint = false;
  SharedLinkPreview? _sharedLinkPreview;
  bool _sharedLinkRemoved = false;
  int _previewResolveSequence = 0;
  Future<void>? _sharedLinkResolveFuture;
  String _sharedPayloadImagePath = '';

  String get _externalSocialShareProvider {
    final request = widget.initialSharedRequest;
    if (request == null) return '';

    final source = request.source.trim().toLowerCase();
    if (source == 'instagram' || source == 'youtube') return source;

    final previewProvider =
        request.preview?.provider.trim().toLowerCase() ?? '';
    if (previewProvider == 'instagram' || previewProvider == 'youtube') {
      return previewProvider;
    }

    final provider = SharedLinkPreviewService.instance.providerForUrl(
      request.normalizedUrl.trim(),
    );
    return provider == 'instagram' || provider == 'youtube' ? provider : '';
  }

  bool get _isExternalSocialShare => _externalSocialShareProvider.isNotEmpty;

  bool get _hasSharedPayloadImage {
    final path = _sharedPayloadImagePath.trim();
    return path.isNotEmpty && File(path).existsSync();
  }

  int get _expectedResolvedImageCount =>
      _selectedAssets.length + _standaloneImages.length;

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory case final initialCategory?) {
      _selectedPostTags.add(initialCategory);
    }
    final initialAudienceCategory = widget.initialAudienceCategory;
    if (initialAudienceCategory != null) {
      _visibility = 'category';
      _selectedCategoryIds = <String>[initialAudienceCategory.id];
    }
    _initializeSharedRequest();
    if (widget.initialSharedRequest != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onSharedRequestReady?.call();
      });
    }
    _contentController.addListener(_checkCanProceed);
    _loadFriendCategories();
    _checkCanProceed();
  }

  void _initializeSharedRequest() {
    final request = widget.initialSharedRequest;
    if (request == null) return;

    for (final key in request.categoryKeys) {
      if (PostCategory.isSupportedKey(key)) {
        _selectedPostTags.add(PostCategory.fromKey(key));
      }
    }
    if (request.visibility == 'category' &&
        request.visibleToCategoryIds.isNotEmpty) {
      _visibility = 'category';
      _isAnonymous = false;
      _selectedCategoryIds = request.visibleToCategoryIds.toSet().toList();
    } else {
      _visibility = 'public';
      _isAnonymous = request.isAnonymous;
    }

    final initialDraft = request.draftText.trim();
    if (initialDraft.isNotEmpty) {
      _contentController.text = initialDraft;
    } else if (!request.hasUrl && request.originalText.trim().isNotEmpty) {
      _contentController.text = request.originalText.trim();
    }
    final url = request.normalizedUrl.trim();
    final detectedProvider =
        SharedLinkPreviewService.instance.providerForUrl(url);
    final isYouTubeShare = request.source.trim().toLowerCase() == 'youtube' ||
        detectedProvider == 'youtube';

    final imagePath = request.imagePath.trim();
    // Old pending shares can still contain the YouTube app icon. A YouTube URL
    // is represented only by the video preview card, never as an attached image.
    if (!isYouTubeShare &&
        imagePath.isNotEmpty &&
        File(imagePath).existsSync()) {
      if (detectedProvider == 'instagram') {
        // Instagram 공유 이미지는 일반 첨부(최대 15장)와 분리한다. 게시
        // 직전에 linkPreview 전용 Storage 경로로 영구 저장된다.
        _sharedPayloadImagePath = imagePath;
      } else {
        final sharedImage = File(imagePath);
        _standaloneImages.add(sharedImage);
        _selectedImages.add(sharedImage);
      }
    }
    if (!request.hasUrl) return;

    final fallback = SharedLinkPreviewService.instance.fallback(
      url,
      provider: detectedProvider,
    );
    final nativePreview = request.preview;
    final sharedTitle = _firstNonUrlLine(request.originalText);
    _sharedLinkPreview = fallback.copyWith(
      originalUrl: request.originalUrl.trim().isEmpty
          ? fallback.originalUrl
          : request.originalUrl.trim(),
      canonicalUrl: nativePreview?.canonicalUrl.trim().isNotEmpty == true
          ? nativePreview!.canonicalUrl.trim()
          : fallback.canonicalUrl,
      title: nativePreview?.title.trim().isNotEmpty == true
          ? nativePreview!.title.trim()
          : (sharedTitle.isNotEmpty ? sharedTitle : fallback.title),
      authorName: nativePreview?.authorName ?? fallback.authorName,
      thumbnailUrl: nativePreview?.thumbnailUrl.trim().isNotEmpty == true
          ? nativePreview!.thumbnailUrl.trim()
          : fallback.thumbnailUrl,
      previewStatus: 'loading',
    );
    final resolveFuture = _resolveSharedLink(url);
    _sharedLinkResolveFuture = resolveFuture;
    unawaited(resolveFuture);
  }

  Future<void> _resolveSharedLink(String url) async {
    final sequence = ++_previewResolveSequence;
    final preview = await SharedLinkPreviewService.instance.resolve(url);
    if (!mounted || _sharedLinkRemoved || sequence != _previewResolveSequence) {
      return;
    }
    final localPreview = _sharedLinkPreview;
    final resolvedPreview =
        preview.previewStatus == 'ready' || localPreview == null
            ? preview
            : preview.copyWith(
                title: localPreview.title.trim().isNotEmpty
                    ? localPreview.title
                    : preview.title,
                authorName: localPreview.authorName.trim().isNotEmpty
                    ? localPreview.authorName
                    : preview.authorName,
                thumbnailUrl: localPreview.thumbnailUrl.trim().isNotEmpty
                    ? localPreview.thumbnailUrl
                    : preview.thumbnailUrl,
              );
    setState(() => _sharedLinkPreview = resolvedPreview);
    _checkCanProceed();
  }

  /// 공유 payload 이미지가 없더라도 작성 화면에서 이미 확인한 Instagram
  /// 썸네일은 서버 재조회보다 먼저 영구 저장에 사용한다. 실제 이미지 형식,
  /// 용량, 디코딩 가능 여부는 전용 persistence service에서 다시 검증한다.
  Future<File?> _resolveLocalInstagramPreviewFile() async {
    if (_sharedLinkRemoved || _hasSharedPayloadImage) {
      return _hasSharedPayloadImage ? File(_sharedPayloadImagePath) : null;
    }

    final preview = _sharedLinkPreview;
    if (preview == null ||
        preview.provider != 'instagram' ||
        preview.isPersistentThumbnail) {
      return null;
    }
    final thumbnailUrl = preview.thumbnailUrl.trim();
    final uri = Uri.tryParse(thumbnailUrl);
    if (uri == null || uri.scheme != 'https') return null;

    try {
      final cached = await AppImageCacheManager.instance.getSingleFile(
        thumbnailUrl,
        headers: const <String, String>{
          HttpHeaders.acceptHeader: 'image/avif,image/webp,image/*,*/*;q=0.8',
          HttpHeaders.refererHeader: 'https://www.instagram.com/',
        },
      ).timeout(const Duration(seconds: 15));
      if (!await cached.exists()) return null;
      final length = await cached.length();
      return length > 0 && length <= 20 * 1024 * 1024 ? cached : null;
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning(
        '[InstagramPreview][local-preview] unavailable=${error.runtimeType}',
      );
      return null;
    }
  }

  String _firstNonUrlLine(String text) {
    for (final rawLine in text.split(RegExp(r'[\r\n]+'))) {
      final line = rawLine.trim();
      if (line.isEmpty ||
          RegExp(r'https?://', caseSensitive: false).hasMatch(line)) {
        continue;
      }
      return line.length > 200 ? line.substring(0, 200) : line;
    }
    return '';
  }

  void _removeSharedLink() {
    _previewResolveSequence++;
    setState(() {
      _sharedLinkRemoved = true;
      _sharedLinkPreview = null;
    });
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
    final hasImages = !_isExternalSocialShare && _selectedImages.isNotEmpty;
    final hasSharedLink = _sharedLinkPreview != null && !_sharedLinkRemoved;
    final canProceed = _selectedPostTags.isNotEmpty &&
        (contentNotEmpty || hasImages || hasSharedLink);

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

  List<UserProfile> _membersForCategory(FriendCategory category) {
    final memberIds = category.friendIds.toSet();
    return _selectedAudienceUsers
        .where((user) => memberIds.contains(user.uid))
        .toList(growable: false);
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

    setState(() {
      _isResolvingSelectedImages = true;
    });

    final files = await _resolveSelectedAssetFiles();
    if (!mounted) return;

    setState(() {
      _selectedImages
        ..clear()
        ..addAll(files)
        ..addAll(_standaloneImages);
      _isResolvingSelectedImages = false;
    });
  }

  Future<void> _showImageSourceSheet() async {
    // Instagram/YouTube 공유 포스트는 링크 미리보기가 미디어 역할을 한다.
    // 외부 앱이 함께 전달한 이미지는 Instagram 썸네일 후보로만 사용하며,
    // 일반 포스트 첨부 이미지 목록에는 추가하지 않는다.
    if (_isExternalSocialShare || _selectedImages.length >= _maxPostImages) {
      return;
    }

    _dismissKeyboard();
    final l10n = AppLocalizations.of(context)!;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        final sheetWidth = MediaQuery.sizeOf(sheetContext).width;
        final horizontalPadding = sheetWidth < 360 ? 16.0 : 20.0;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.imageAttachment,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(16).clamp(15, 17).toDouble(),
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF111827),
                        ),
                      ),
                    ),
                    Text(
                      '${_selectedImages.length}/$_maxPostImages',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: context.rf(13).clamp(12, 14).toDouble(),
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildImageSourceOption(
                  icon: Icons.photo_library_outlined,
                  label: l10n.selectFromGallery,
                  onTap: () =>
                      Navigator.of(sheetContext).pop(ImageSource.gallery),
                ),
                _buildImageSourceOption(
                  icon: Icons.photo_camera_outlined,
                  label: l10n.takePhoto,
                  onTap: () =>
                      Navigator.of(sheetContext).pop(ImageSource.camera),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || source == null) return;
    if (source == ImageSource.camera) {
      await _takePhoto();
      return;
    }
    await _selectImagesFromGallery();
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 34,
                child: Icon(
                  icon,
                  size: context.ri(21).clamp(20, 23).toDouble(),
                  color: const Color(0xFF475467),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: context.rf(14).clamp(13, 15).toDouble(),
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectImagesFromGallery() async {
    if (_isExternalSocialShare) return;

    try {
      await _selectImagesFromGalleryInternal();
    } on PlatformException catch (error, stackTrace) {
      Logger.error('포스트 이미지 선택 실패', error, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.imageSelectError)),
      );
    } catch (error, stackTrace) {
      Logger.error('포스트 이미지 선택 실패', error, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.imageSelectError)),
      );
    }
  }

  Future<void> _selectImagesFromGalleryInternal() async {
    if (Platform.isAndroid) {
      final remaining = _maxPostImages - _selectedImages.length;
      if (remaining <= 0) return;
      final picked = remaining == 1
          ? <XFile>[
              if (await _imagePicker.pickImage(
                source: ImageSource.gallery,
                imageQuality: _pickedImageQuality,
                maxWidth: _pickedImageMaxDimension,
                maxHeight: _pickedImageMaxDimension,
                requestFullMetadata: false,
              )
                  case final image?)
                image,
            ]
          : await _imagePicker.pickMultiImage(
              limit: remaining,
              imageQuality: _pickedImageQuality,
              maxWidth: _pickedImageMaxDimension,
              maxHeight: _pickedImageMaxDimension,
              requestFullMetadata: false,
            );
      if (!mounted || picked.isEmpty) return;
      final files = picked
          .take(remaining)
          .map((image) => File(image.path))
          .toList(growable: false);
      setState(() {
        _standaloneImages.addAll(files);
        _selectedImages.addAll(files);
      });
      _checkCanProceed();
      return;
    }

    final maxAssets = _maxPostImages - _standaloneImages.length;
    if (maxAssets <= 0) return;
    final pickedAssets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        requestType: RequestType.image,
        selectedAssets: _selectedAssets,
        maxAssets: maxAssets,
        dragToSelect: false,
      ),
    );

    if (!mounted || pickedAssets == null) return;

    setState(() {
      _selectedAssets
        ..clear()
        ..addAll(pickedAssets.take(maxAssets));
    });

    await _syncSelectedImagesFromAssets();
    _checkCanProceed();
  }

  Future<void> _takePhoto() async {
    if (_selectedImages.length >= _maxPostImages) return;
    final l10n = AppLocalizations.of(context)!;
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: _pickedImageQuality,
        maxWidth: _pickedImageMaxDimension,
        maxHeight: _pickedImageMaxDimension,
        requestFullMetadata: false,
      );
      if (!mounted || picked == null) return;

      final file = File(picked.path);
      setState(() {
        _standaloneImages.add(file);
        _selectedImages.add(file);
      });
      _checkCanProceed();
    } on PlatformException catch (error, stackTrace) {
      Logger.error('포스트 사진 촬영 실패', error, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photoError)),
      );
    } catch (error, stackTrace) {
      Logger.error('포스트 사진 촬영 실패', error, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photoError)),
      );
    }
  }

  Future<void> _previewSelectedImages({int initialIndex = 0}) async {
    if (!mounted || _selectedImages.isEmpty) return;

    if (_selectedAssets.isNotEmpty &&
        _selectedImages.length != _expectedResolvedImageCount) {
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
    if (index < 0 || index >= _selectedImages.length) return;
    final assetCount = _selectedAssets.length;
    if (index < assetCount) {
      setState(() => _selectedAssets.removeAt(index));
      await _syncSelectedImagesFromAssets();
    } else {
      final standaloneIndex = index - assetCount;
      if (standaloneIndex < 0 || standaloneIndex >= _standaloneImages.length) {
        return;
      }
      setState(() {
        _standaloneImages.removeAt(standaloneIndex);
        _selectedImages.removeAt(index);
      });
    }
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
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
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
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
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
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
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

  String? _externalPostId() {
    if (!widget.stayInAppAfterSharedPost) return null;
    final requestId = widget.initialSharedRequest?.id ?? '';
    final normalized = requestId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (normalized.length < 20) return null;
    return normalized.substring(0, 20);
  }

  ExternalShareDraft _currentExternalShareDraft() {
    return ExternalShareDraft(
      draftText: _contentController.text.trim(),
      categoryKeys: _selectedPostTags.map((category) => category.key).toList(),
      visibility: _visibility,
      isAnonymous: _visibility == 'public' && _isAnonymous,
      visibleToCategoryIds:
          _visibility == 'category' ? _selectedCategoryIds : const <String>[],
    );
  }

  Future<void> _handleClose() async {
    if (_isSubmitting) return;
    if (widget.initialSharedRequest == null ||
        !widget.stayInAppAfterSharedPost) {
      Navigator.of(context).pop(
        widget.initialSharedRequest == null
            ? null
            : ExternalShareComposeOutcome.discarded,
      );
      return;
    }

    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final choice = await showDialog<ExternalShareComposeOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(isKo ? '작성을 종료할까요?' : 'Leave this post?'),
        content: Text(
          isKo
              ? '공유한 내용과 현재 입력을 다음 앱 실행에서 이어서 작성하거나, 공유 요청을 완전히 폐기할 수 있어요.'
              : 'Keep this draft for the next app launch or discard the shared request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(isKo ? '계속 작성' : 'Keep writing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(ExternalShareComposeOutcome.discarded),
            child: Text(
              isKo ? '공유 요청 폐기' : 'Discard',
              style: const TextStyle(color: Colors.red),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(ExternalShareComposeOutcome.saved),
            child: Text(isKo ? '초안 유지' : 'Keep draft'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;

    if (choice == ExternalShareComposeOutcome.saved) {
      final saved =
          await widget.onSharedDraftSave?.call(_currentExternalShareDraft()) ??
              false;
      if (!mounted) return;
      if (!saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isKo
                  ? '초안을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.'
                  : 'Could not save the draft. Please try again.',
            ),
          ),
        );
        return;
      }
    }

    Navigator.of(context).pop(choice);
  }

  Future<void> _openCreatedSharedPost(String postId) async {
    await widget.onSharedPostCreated?.call(postId);
    if (!mounted) return;

    var post = await _postService.getPostById(postId);
    for (var retry = 0; post == null && retry < 2; retry++) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      post = await _postService.getPostById(postId);
    }
    if (!mounted) return;

    if (post == null) {
      Navigator.of(context).pop(ExternalShareComposeOutcome.posted);
      return;
    }
    Navigator.of(context).pushReplacement<void, ExternalShareComposeOutcome>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/posts/$postId'),
        builder: (_) => PostDetailScreen(post: post!),
      ),
      result: ExternalShareComposeOutcome.posted,
    );
  }

  Future<void> _submitPost() async {
    final l10n = AppLocalizations.of(context)!;

    if (_selectedPostTags.isEmpty) {
      setState(() => _showPostTagRequiredHint = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localizations.localeOf(context).languageCode == 'ko'
                ? '태그를 한 개 이상 선택해 주세요.'
                : 'Choose at least one tag.',
          ),
        ),
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

    if (_requiresHanyangVerification &&
        !context.read<app_auth.AuthProvider>().isHanyangEmailVerified) {
      setState(() {
        _visibility = 'public';
        _isAnonymous = false;
        _requiresHanyangVerification = false;
        _selectedCategoryIds = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localizations.localeOf(context).languageCode == 'ko'
                ? '한양메일 인증 후 한양대학생 전용으로 게시할 수 있어요.'
                : 'Verify your Hanyang email to use Hanyang-only visibility.',
          ),
        ),
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
        _selectedImages.length != _expectedResolvedImageCount) {
      await _syncSelectedImagesFromAssets();
    }
    if (!mounted) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      // A user can submit immediately after arriving from the native share
      // sheet. Wait for the in-flight metadata request so the persisted post
      // contains the resolved thumbnail/title instead of racing the callback.
      if (!_sharedLinkRemoved) {
        await _sharedLinkResolveFuture;
      }
      if (!mounted) return;

      final sharedPreviewImage = await _resolveLocalInstagramPreviewFile();
      if (!mounted) return;

      if (!_isExternalSocialShare && _selectedImages.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.postImageUploading),
            duration: const Duration(seconds: 5),
          ),
        );
      }

      String? createdPostId;
      final success = await _postService.addPost(
        '',
        _contentController.text.trim(),
        categoryKeys:
            _selectedPostTags.map((category) => category.key).toList(),
        imageFiles: !_isExternalSocialShare && _selectedImages.isNotEmpty
            ? _selectedImages
            : null,
        visibility: _visibility,
        isAnonymous: _isAnonymous,
        requiresHanyangVerification: _requiresHanyangVerification,
        visibleToCategoryIds: _selectedCategoryIds,
        type: 'text',
        pollOptions: const [],
        linkPreview: _sharedLinkRemoved ? null : _sharedLinkPreview,
        linkPreviewImageFile: sharedPreviewImage,
        linkPreviewImageSource:
            _hasSharedPayloadImage ? 'share_payload' : 'local_preview',
        externalShareRequestId: widget.initialSharedRequest?.id ?? '',
        onLinkPreviewPersistenceFailed: () {
          if (!mounted) return;
          final isKo = Localizations.localeOf(context).languageCode == 'ko';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isKo
                    ? 'Instagram 미리보기를 저장하지 못했어요. 링크만 포함해서 게시합니다.'
                    : 'The Instagram preview could not be saved. The link will still be posted.',
              ),
            ),
          );
        },
        requestedPostId: _externalPostId(),
        onCreated: (postId) => createdPostId = postId,
      );

      if (!mounted) return;

      if (success) {
        widget.onPostCreated();
        if (widget.initialSharedRequest != null &&
            widget.stayInAppAfterSharedPost &&
            createdPostId != null) {
          await _openCreatedSharedPost(createdPostId!);
          return;
        }
        Navigator.of(context).pop(
          widget.initialSharedRequest == null
              ? null
              : ExternalShareComposeOutcome.posted,
        );
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
      toolbarHeight: _composerToolbarHeight,
      automaticallyImplyLeading: false,
      leadingWidth: 48,
      leading: IconButton(
        icon: Icon(
          Icons.close_rounded,
          color: const Color(0xFF111827),
          size: context.ri(22).clamp(21, 24).toDouble(),
        ),
        onPressed: _handleClose,
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
      ),
      flexibleSpace: _buildCenteredComposerTitle(l10n.writeStory),
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
    final useCompactShareAction = MediaQuery.sizeOf(context).width < 340 ||
        MediaQuery.textScalerOf(context).scale(14) > 24;

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.white,
      toolbarHeight: _composerToolbarHeight,
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
      flexibleSpace: _buildCenteredComposerTitle(l10n.writeStory),
      actions: [
        if (useCompactShareAction)
          SizedBox.square(
            dimension: 48,
            child: IconButton(
              onPressed: _isSubmitting ? null : _submitPost,
              tooltip: l10n.share,
              icon: _isSubmitting
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.check_rounded,
                      size: context.ri(21).clamp(20, 23).toDouble(),
                    ),
            ),
          )
        else
          TextButton.icon(
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
              l10n.share,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
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
        const SizedBox(width: 4),
      ],
    );
  }

  double get _composerToolbarHeight {
    final base = context.rh(56, min: 54, max: 60);
    final scaledTitle = MediaQuery.textScalerOf(context).scale(
      context.rf(18).clamp(16, 19).toDouble(),
    );
    final accessible = scaledTitle * 1.2 + DesignTokens.s24;
    return accessible > base ? accessible.clamp(base, 96).toDouble() : base;
  }

  Widget _buildCenteredComposerTitle(String title) {
    final horizontalClearance =
        MediaQuery.sizeOf(context).width < 360 ? 88.0 : 104.0;
    return SafeArea(
      bottom: false,
      child: IgnorePointer(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalClearance),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(18).clamp(16, 19).toDouble(),
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text, {String? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
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
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: context.rf(13).clamp(12, 14).toDouble(),
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6B7280),
            ),
          ),
      ],
    );
  }

  Widget _buildAddImageButton(AppLocalizations l10n) {
    final canAddImage = _selectedImages.length < _maxPostImages;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: canAddImage ? _showImageSourceSheet : null,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF475467),
          disabledForegroundColor: const Color(0xFF98A2B3),
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
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
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
        itemCount: _selectedImages.length,
        separatorBuilder: (_, __) => SizedBox(width: context.rs(8)),
        itemBuilder: (context, index) {
          final image = _selectedImages[index];
          return GestureDetector(
            onTap: () => _previewSelectedImages(initialIndex: index),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    image,
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
    final systemBottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final horizontalPadding = screenSize.width < 360
        ? 14.0
        : screenSize.width < 430
            ? 16.0
            : 20.0;
    final contentMinLines = screenSize.height < 700 ? 7 : 10;

    return SingleChildScrollView(
      controller: _composeScrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        context.rs(8).clamp(6, 10).toDouble(),
        horizontalPadding,
        DesignTokens.s24 + systemBottomInset,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PostCategorySelector(
                selected: _selectedPostTags,
                showError: _showPostTagRequiredHint,
                showHeader: false,
                onChanged: (tags) {
                  setState(() {
                    _selectedPostTags
                      ..clear()
                      ..addAll(tags);
                    _showPostTagRequiredHint = false;
                  });
                  _checkCanProceed();
                },
              ),
              SizedBox(height: context.rs(20).clamp(16, 22).toDouble()),
              if (!_isExternalSocialShare) ...[
                _buildSectionLabel(
                  imageLabel,
                  trailing: '${_selectedImages.length}/$_maxPostImages',
                ),
                _buildAddImageButton(l10n),
                if (_selectedImages.isNotEmpty) ...[
                  SizedBox(height: context.rs(4)),
                  _buildSelectedImagesStrip(),
                  SizedBox(height: context.rs(6)),
                ],
                Text(
                  l10n.postComposeImageHelper,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: context.rf(12).clamp(11, 13).toDouble(),
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF6B7280),
                  ),
                ),
                SizedBox(height: context.rs(22).clamp(18, 24).toDouble()),
              ] else
                SizedBox(height: context.rs(4).clamp(2, 6).toDouble()),
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
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: context.rf(15).clamp(14, 16).toDouble(),
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF9CA3AF),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
                ),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(15).clamp(14, 16).toDouble(),
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF111827),
                  height: 1.5,
                ),
              ),
              if (_sharedLinkPreview case final preview?) ...[
                SizedBox(height: context.rs(12).clamp(10, 16).toDouble()),
                if (preview.isInstagramEmbed ||
                    (preview.provider == 'instagram' &&
                        _sharedPayloadImagePath.isNotEmpty))
                  InstagramEmbedPreview(
                    preview: preview,
                    localImagePath: _sharedPayloadImagePath,
                    onRemove: _removeSharedLink,
                  )
                else
                  SharedLinkPreviewCard(
                    preview: preview,
                    onRemove: _removeSharedLink,
                  ),
                SizedBox(height: context.rs(8).clamp(6, 12).toDouble()),
              ],
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
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: context.rf(15).clamp(14, 16).toDouble(),
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            description,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
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

  Widget _buildGroupSelectionButton(FriendCategory category) {
    final isSelected = _selectedCategoryIds.contains(category.id);

    return Semantics(
      button: true,
      selected: isSelected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
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
                unawaited(_refreshSelectedAudienceUsers());
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
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
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
          if (isSelected)
            GroupAudiencePreview(
              members: _membersForCategory(category),
              loading: _isLoadingAudienceUsers && category.friendIds.isNotEmpty,
            ),
        ],
      ),
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
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
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
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB91C1C),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVisibilityBody() {
    final l10n = AppLocalizations.of(context)!;
    final isHanyangEmailVerified =
        context.watch<app_auth.AuthProvider>().isHanyangEmailVerified;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final systemBottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final horizontalPadding = screenWidth < 360
        ? 14.0
        : screenWidth < 430
            ? 16.0
            : 20.0;

    return SingleChildScrollView(
      controller: _visibilityScrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        context.rs(12).clamp(10, 16).toDouble(),
        horizontalPadding,
        DesignTokens.s24 + systemBottomInset,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.postComposeVisibilityPrompt,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
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
                selected: _visibility == 'public' &&
                    !_isAnonymous &&
                    !_requiresHanyangVerification,
                onTap: () {
                  setState(() {
                    _visibility = 'public';
                    _isAnonymous = false;
                    _requiresHanyangVerification = false;
                    _selectedCategoryIds = [];
                    _showCategoryRequiredHint = false;
                  });
                },
              ),
              const Divider(height: 1, indent: 40, color: Color(0xFFEAECF0)),
              _buildVisibilityOption(
                icon: Icons.visibility_off_outlined,
                title: l10n.postVisibilityAnonymousTitle,
                description: l10n.postVisibilityAnonymousDescription,
                selected: _visibility == 'public' &&
                    _isAnonymous &&
                    !_requiresHanyangVerification,
                onTap: () {
                  setState(() {
                    _visibility = 'public';
                    _isAnonymous = true;
                    _requiresHanyangVerification = false;
                    _selectedCategoryIds = [];
                    _showCategoryRequiredHint = false;
                  });
                },
              ),
              if (isHanyangEmailVerified) ...[
                const Divider(
                  height: 1,
                  indent: 40,
                  color: Color(0xFFEAECF0),
                ),
                _buildVisibilityOption(
                  icon: Icons.school_outlined,
                  title: Localizations.localeOf(context).languageCode == 'ko'
                      ? '한양대학생만'
                      : 'Hanyang students only',
                  description: Localizations.localeOf(context).languageCode ==
                          'ko'
                      ? '카드는 모두에게 보이고, 인증된 사용자만 내용을 볼 수 있어요.'
                      : 'Everyone sees the card, but only verified users can view its content.',
                  selected: _requiresHanyangVerification,
                  onTap: () {
                    setState(() {
                      _visibility = 'public';
                      _isAnonymous = false;
                      _requiresHanyangVerification = true;
                      _selectedCategoryIds = [];
                      _showCategoryRequiredHint = false;
                    });
                  },
                ),
              ],
              const Divider(height: 1, indent: 40, color: Color(0xFFEAECF0)),
              _buildVisibilityOption(
                icon: Icons.group_outlined,
                title: l10n.postVisibilityGroupTitle,
                description: l10n.postVisibilityGroupDescription,
                selected:
                    _visibility == 'category' && !_requiresHanyangVerification,
                onTap: () {
                  setState(() {
                    _visibility = 'category';
                    _requiresHanyangVerification = false;
                    // 그룹 공개는 작성자 정보가 보이는 공개 방식만 지원한다.
                    // 익명 공개를 선택한 상태에서 그룹으로 전환하면 즉시 해제한다.
                    _isAnonymous = false;
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
      canPop: (widget.initialSharedRequest == null ||
              !widget.stayInAppAfterSharedPost) &&
          _stepIndex == 0 &&
          !_isSubmitting,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isSubmitting) return;
        if (_stepIndex == 1) {
          await _goToStep(0);
        } else if (widget.initialSharedRequest != null &&
            widget.stayInAppAfterSharedPost) {
          await _handleClose();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true,
        appBar:
            _stepIndex == 0 ? _buildComposeAppBar() : _buildVisibilityAppBar(),
        // 키보드는 Scaffold의 resizeToAvoidBottomInset이 처리하고, 시스템
        // 내비게이션 여백은 각 스크롤 본문의 viewPadding으로 한 번만 반영한다.
        body: _buildAnimatedBody(),
      ),
    );
  }
}
