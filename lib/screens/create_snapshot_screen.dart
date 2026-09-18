import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../models/friend_category.dart';
import '../models/snapshot.dart';
import '../models/user_profile.dart';
import '../repositories/users_repository.dart';
import '../services/friend_category_service.dart';
import '../services/snapshot_archive_service.dart';
import '../services/snapshot_service.dart';
import '../snapshot/snapshot_storage_video.dart';
import '../snapshot/snapshot_strings.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/widgets/group_audience_preview.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';
import '../l10n/ui_locale.dart';

class CreateSnapshotScreen extends StatefulWidget {
  const CreateSnapshotScreen({super.key, this.onCreated});

  final VoidCallback? onCreated;

  @override
  State<CreateSnapshotScreen> createState() => _CreateSnapshotScreenState();
}

class _SnapshotTextLayer {
  _SnapshotTextLayer({
    required this.id,
    required this.position,
  })  : controller = TextEditingController(),
        focusNode = FocusNode();

  final String id;
  final TextEditingController controller;
  final FocusNode focusNode;
  late final VoidCallback focusListener;
  String text = '';
  Offset position;
  double fontScale = 1;
  bool lightText = true;
  int layoutRevision = 0;

  void dispose() {
    focusNode
      ..removeListener(focusListener)
      ..dispose();
    controller.dispose();
  }
}

enum _SnapshotTrimDragTarget { start, end, range }

class _CreateSnapshotScreenState extends State<CreateSnapshotScreen>
    with WidgetsBindingObserver {
  static const int _galleryPageSize = 100;
  static const MethodChannel _snapshotVideoEditorChannel = MethodChannel(
    'com.wefilling.app/snapshot_video_editor',
  );
  static const PermissionRequestOption _galleryPermissionRequestOption =
      PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.image,
      mediaLocation: false,
    ),
  );

  final ImagePicker _picker = ImagePicker();
  final GlobalKey _compositionKey = GlobalKey();
  final SnapshotService _service = SnapshotService.instance;
  final FriendCategoryService _friendCategoryService = FriendCategoryService();
  final UsersRepository _usersRepository = UsersRepository();

  StreamSubscription<List<FriendCategory>>? _categoriesSubscription;

  File? _sourceFile;
  File? _composedFile;
  File? _videoThumbnail;
  SnapshotMediaType _mediaType = SnapshotMediaType.photo;
  VideoPlayerController? _sourceVideoController;
  VideoPlayerController? _previewVideoController;
  Duration _videoDuration = Duration.zero;
  RangeValues _videoTrimSeconds = const RangeValues(0, 12);
  int _sourceWidth = 0;
  int _sourceHeight = 0;
  final List<_SnapshotTextLayer> _textLayers = <_SnapshotTextLayer>[];
  String? _selectedTextLayerId;
  String? _editingTextLayerId;
  String? _transformingTextLayerId;
  int _nextTextLayerId = 0;
  double _gestureStartFontScale = 1;
  Offset _gestureStartPosition = Offset.zero;
  Offset _gestureStartFocalPoint = Offset.zero;
  double _trimDragGrabOffset = 0;
  _SnapshotTrimDragTarget? _trimDragTarget;
  Completer<void>? _overlayCommitCompleter;
  String? _overlayCommitLayerId;
  SnapshotVisibility _visibility = SnapshotVisibility.public;
  List<FriendCategory> _friendCategories = const <FriendCategory>[];
  List<String> _selectedCategoryIds = const <String>[];
  List<UserProfile> _selectedAudienceUsers = const <UserProfile>[];
  bool _isLoadingAudienceUsers = false;
  int _audienceLoadSeq = 0;
  bool _showCategoryRequired = false;
  bool _loadingPhoto = false;
  bool _composing = false;
  bool _uploading = false;
  String? _pendingUploadSnapshotId;
  double _uploadProgress = 0;
  int _step = 0;
  List<AssetEntity> _recentPhotos = const <AssetEntity>[];
  AssetPathEntity? _recentPhotoAlbum;
  int _galleryTotalCount = 0;
  int _galleryNextPage = 0;
  bool _loadingGallery = true;
  bool _loadingMoreGallery = false;
  bool _galleryPermissionDenied = false;
  bool _galleryPermissionLimited = false;
  bool _galleryLoadFailed = false;
  int _galleryLoadSequence = 0;

  double get _aspectRatio {
    if (_sourceWidth <= 0 || _sourceHeight <= 0) return .8;
    return (_sourceWidth / _sourceHeight).clamp(.55, 1.8);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _categoriesSubscription =
        _friendCategoryService.getCategoriesStream().listen((categories) {
      if (!mounted) return;
      setState(() {
        _friendCategories = categories;
        final validIds = categories.map((category) => category.id).toSet();
        _selectedCategoryIds = _selectedCategoryIds
            .where(validIds.contains)
            .toList(growable: false);
      });
      unawaited(_refreshSelectedAudienceUsers());
    });
    unawaited(_loadRecentPhotos());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshRecentPhotosAfterResume());
    }
  }

  Future<void> _refreshRecentPhotosAfterResume() async {
    if (_loadingGallery || _loadingPhoto || _uploading || _sourceFile != null) {
      return;
    }
    final refreshSequence = ++_galleryLoadSequence;
    try {
      final permission = await PhotoManager.getPermissionState(
        requestOption: _galleryPermissionRequestOption,
      );
      if (!mounted || refreshSequence != _galleryLoadSequence) return;
      if (permission.hasAccess) {
        await _loadRecentPhotos(requestPermission: false);
        return;
      }
      setState(() {
        _recentPhotos = const <AssetEntity>[];
        _recentPhotoAlbum = null;
        _galleryTotalCount = 0;
        _galleryNextPage = 0;
        _galleryPermissionDenied = true;
        _galleryPermissionLimited = false;
        _galleryLoadFailed = false;
      });
    } on PlatformException {
      // Keep the current gallery state. The visible retry action still lets
      // the user request access again if this platform check was interrupted.
    }
  }

  Set<String> _selectedAudienceIds() {
    final selectedIds = _selectedCategoryIds.toSet();
    final audienceIds = <String>{};
    for (final category in _friendCategories) {
      if (selectedIds.contains(category.id)) {
        audienceIds.addAll(category.friendIds);
      }
    }
    return audienceIds;
  }

  List<UserProfile> _membersForCategory(FriendCategory category) {
    final memberIds = category.friendIds.toSet();
    return _selectedAudienceUsers
        .where((user) => memberIds.contains(user.uid))
        .toList(growable: false);
  }

  Future<void> _refreshSelectedAudienceUsers() async {
    final currentSeq = ++_audienceLoadSeq;
    final audienceIds = _selectedAudienceIds().toList(growable: false);

    if (audienceIds.isEmpty) {
      if (!mounted) return;
      setState(() {
        _selectedAudienceUsers = const <UserProfile>[];
        _isLoadingAudienceUsers = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _isLoadingAudienceUsers = true);

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

  Future<void> _loadRecentPhotos({bool requestPermission = true}) async {
    final loadSequence = ++_galleryLoadSequence;
    if (mounted) {
      setState(() {
        _loadingGallery = true;
        _loadingMoreGallery = false;
        _galleryPermissionDenied = false;
        _galleryPermissionLimited = false;
        _galleryLoadFailed = false;
        _recentPhotoAlbum = null;
        _galleryTotalCount = 0;
        _galleryNextPage = 0;
      });
    }
    try {
      final permission = requestPermission
          ? await PhotoManager.requestPermissionExtend(
              requestOption: _galleryPermissionRequestOption,
            )
          : await PhotoManager.getPermissionState(
              requestOption: _galleryPermissionRequestOption,
            );
      if (!mounted || loadSequence != _galleryLoadSequence) return;
      if (!permission.hasAccess) {
        if (!mounted) return;
        setState(() {
          _recentPhotos = const <AssetEntity>[];
          _galleryPermissionDenied = true;
          _galleryPermissionLimited = false;
          _galleryLoadFailed = false;
        });
        return;
      }
      if (mounted) {
        setState(() => _galleryPermissionLimited = permission.isLimited);
      }
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
        filterOption: FilterOptionGroup(
          orders: const <OrderOption>[
            OrderOption(type: OrderOptionType.createDate, asc: false),
          ],
        ),
      );
      if (!mounted || loadSequence != _galleryLoadSequence) return;
      if (albums.isEmpty) {
        if (!mounted) return;
        setState(() => _recentPhotos = const <AssetEntity>[]);
        return;
      }

      final album = albums.first;
      final results = await Future.wait<dynamic>([
        album.assetCountAsync,
        album.getAssetListPaged(page: 0, size: _galleryPageSize),
      ]);
      final totalCount = results[0] as int;
      final photos = results[1] as List<AssetEntity>;
      if (!mounted || loadSequence != _galleryLoadSequence) return;
      setState(() {
        _recentPhotoAlbum = album;
        _galleryTotalCount = totalCount;
        _galleryNextPage = 1;
        _recentPhotos = List<AssetEntity>.unmodifiable(photos);
      });
    } on PlatformException catch (error, stackTrace) {
      if (!mounted || loadSequence != _galleryLoadSequence) return;
      Logger.error('최근 사진 불러오기 실패', error, stackTrace);
      setState(() {
        _recentPhotos = const <AssetEntity>[];
        _galleryLoadFailed = true;
      });
    } catch (error, stackTrace) {
      if (!mounted || loadSequence != _galleryLoadSequence) return;
      Logger.error('최근 사진 불러오기 실패', error, stackTrace);
      setState(() {
        _recentPhotos = const <AssetEntity>[];
        _galleryLoadFailed = true;
      });
    } finally {
      if (mounted && loadSequence == _galleryLoadSequence) {
        setState(() => _loadingGallery = false);
      }
    }
  }

  Future<void> _selectMorePhotos() async {
    if (_loadingGallery || _loadingPhoto || _uploading) return;
    final strings = SnapshotStrings.of(context);
    setState(() => _loadingGallery = true);
    try {
      await PhotoManager.presentLimited(type: RequestType.image);
      if (!mounted) return;
      await _loadRecentPhotos(requestPermission: false);
    } catch (error, stackTrace) {
      if (!mounted) return;
      Logger.error('사진 선택 범위 변경 실패', error, stackTrace);
      setState(() => _loadingGallery = false);
      AppSnackBar.show(
        context,
        message: strings.permissionFailed,
        type: AppSnackBarType.warning,
      );
    }
  }

  Future<void> _loadMoreRecentPhotos() async {
    final album = _recentPhotoAlbum;
    if (album == null ||
        _loadingGallery ||
        _loadingMoreGallery ||
        _recentPhotos.length >= _galleryTotalCount) {
      return;
    }

    final requestedPage = _galleryNextPage;
    setState(() => _loadingMoreGallery = true);
    try {
      final photos = await album.getAssetListPaged(
        page: requestedPage,
        size: _galleryPageSize,
      );
      if (!mounted || !identical(album, _recentPhotoAlbum)) return;

      final knownIds = _recentPhotos.map((photo) => photo.id).toSet();
      final nextPhotos = photos
          .where((photo) => knownIds.add(photo.id))
          .toList(growable: false);
      setState(() {
        _galleryNextPage = requestedPage + 1;
        _recentPhotos = List<AssetEntity>.unmodifiable(
          <AssetEntity>[..._recentPhotos, ...nextPhotos],
        );
      });
    } on PlatformException {
      // Keep the already loaded photos usable. A later scroll can retry this
      // exact page because the cursor advances only after a successful read.
    } catch (_) {
      // Asset providers can be temporarily unavailable while the device is
      // syncing cloud photos. Preserve the current page and allow a retry.
    } finally {
      if (mounted && identical(album, _recentPhotoAlbum)) {
        setState(() => _loadingMoreGallery = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _categoriesSubscription?.cancel();
    _friendCategoryService.dispose();
    final pendingCommit = _overlayCommitCompleter;
    _overlayCommitCompleter = null;
    if (pendingCommit != null && !pendingCommit.isCompleted) {
      pendingCommit.complete();
    }
    for (final layer in _textLayers) {
      layer.dispose();
    }
    unawaited(_disposeVideoControllers());
    unawaited(
      VideoCompress.cancelCompression()
          .then((_) => VideoCompress.deleteAllCache()),
    );
    _deleteTemporaryComposition();
    super.dispose();
  }

  _SnapshotTextLayer? _textLayerById(String? id) {
    if (id == null) return null;
    for (final layer in _textLayers) {
      if (layer.id == id) return layer;
    }
    return null;
  }

  _SnapshotTextLayer? get _selectedTextLayer =>
      _textLayerById(_selectedTextLayerId);

  void _syncOverlayFocus(String layerId) {
    if (!mounted) return;
    final layer = _textLayerById(layerId);
    if (layer == null) return;
    if (layer.focusNode.hasFocus) {
      if (_selectedTextLayerId != layerId || _editingTextLayerId != layerId) {
        setState(() {
          _selectedTextLayerId = layerId;
          _editingTextLayerId = layerId;
        });
      }
      return;
    }
    if (_editingTextLayerId == layerId) {
      unawaited(_scheduleOverlayCommit(layerId));
    }
  }

  Future<void> _addTextLayer() async {
    if (_sourceFile == null || _composing || _uploading) return;
    if (_textLayers.length >= 5) {
      AppSnackBar.show(
        context,
        message: SnapshotStrings.of(context).textLimit,
        type: AppSnackBarType.warning,
      );
      return;
    }
    await _finishOverlayEditing();
    if (!mounted) return;

    final layerNumber = _nextTextLayerId++;
    final offsetStep = (layerNumber % 5) * .035;
    final layer = _SnapshotTextLayer(
      id: 'snapshot_text_${DateTime.now().microsecondsSinceEpoch}_$layerNumber',
      position: Offset(.5, (.42 + offsetStep).clamp(.2, .8)),
    );
    layer.focusListener = () => _syncOverlayFocus(layer.id);
    layer.focusNode.addListener(layer.focusListener);
    setState(() {
      _textLayers.add(layer);
      _selectedTextLayerId = layer.id;
      _editingTextLayerId = layer.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editingTextLayerId != layer.id) return;
      layer.focusNode.requestFocus();
    });
  }

  Future<void> _selectTextLayer(String layerId) async {
    if (_composing || _uploading) return;
    if (_editingTextLayerId != null && _editingTextLayerId != layerId) {
      await _finishOverlayEditing();
    }
    if (!mounted || _textLayerById(layerId) == null) return;
    setState(() {
      _selectedTextLayerId = layerId;
      if (_editingTextLayerId != layerId) _editingTextLayerId = null;
    });
  }

  Future<void> _beginTextLayerEditing(String layerId) async {
    if (_composing || _uploading) return;
    if (_editingTextLayerId != null && _editingTextLayerId != layerId) {
      await _finishOverlayEditing();
    }
    if (!mounted) return;
    final layer = _textLayerById(layerId);
    if (layer == null) return;
    setState(() {
      _selectedTextLayerId = layerId;
      _editingTextLayerId = layerId;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editingTextLayerId != layerId) return;
      layer.focusNode.requestFocus();
      layer.controller.selection = TextSelection.collapsed(
        offset: layer.controller.text.length,
      );
    });
  }

  Future<void> _scheduleOverlayCommit(String layerId) async {
    final pending = _overlayCommitCompleter;
    if (pending != null) {
      if (_overlayCommitLayerId == layerId) return pending.future;
      await pending.future;
      if (!mounted) return;
    }

    final completer = Completer<void>();
    _overlayCommitCompleter = completer;
    _overlayCommitLayerId = layerId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!identical(_overlayCommitCompleter, completer) ||
          _overlayCommitLayerId != layerId) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      try {
        final layer = _textLayerById(layerId);
        if (!mounted || layer == null || layer.focusNode.hasFocus) return;
        final text = layer.controller.text;
        var nextScale = layer.fontScale;
        var nextPosition = layer.position;
        final renderObject = _compositionKey.currentContext?.findRenderObject();
        if (text.isNotEmpty &&
            renderObject is RenderBox &&
            renderObject.attached &&
            renderObject.hasSize) {
          nextScale = _fitOverlayFontScale(
            layer,
            nextScale,
            renderObject.size.width,
            renderObject.size.height,
          );
          nextPosition = _boundedOverlayPosition(
            layer,
            nextPosition,
            renderObject.size.width,
            renderObject.size.height,
            fontScale: nextScale,
          );
        }
        setState(() {
          layer
            ..text = text
            ..fontScale = nextScale
            ..position = nextPosition;
          if (_editingTextLayerId == layerId) _editingTextLayerId = null;
        });
      } catch (error, stackTrace) {
        Logger.error('스낵 텍스트 오버레이 확정 실패', error, stackTrace);
        final layer = _textLayerById(layerId);
        if (mounted && layer != null && !layer.focusNode.hasFocus) {
          setState(() {
            layer.text = layer.controller.text;
            if (_editingTextLayerId == layerId) _editingTextLayerId = null;
          });
        }
      } finally {
        if (identical(_overlayCommitCompleter, completer)) {
          _overlayCommitCompleter = null;
          _overlayCommitLayerId = null;
        }
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  Future<void> _pickImage(ImageSource source) async {
    final strings = SnapshotStrings.of(context);
    setState(() => _loadingPhoto = true);
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 96,
        maxWidth: 2400,
        maxHeight: 2400,
        requestFullMetadata: false,
      );
      if (picked == null) return;
      await _useImageFile(File(picked.path));
    } on PlatformException {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: strings.permissionFailed,
          type: AppSnackBarType.warning,
        );
      }
    } catch (_) {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: strings.photoFailed,
          type: AppSnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPhoto = false);
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    if (_loadingPhoto || _uploading) return;
    final strings = SnapshotStrings.of(context);
    setState(() => _loadingPhoto = true);
    try {
      final picked = await _picker.pickVideo(
        source: source,
        maxDuration:
            source == ImageSource.camera ? const Duration(seconds: 12) : null,
      );
      if (picked == null) return;
      await _useVideoFile(File(picked.path));
    } on PlatformException {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: strings.permissionFailed,
          type: AppSnackBarType.warning,
        );
      }
    } catch (error, stackTrace) {
      Logger.error('스낵 영상 선택 실패', error, stackTrace);
      if (mounted) {
        AppSnackBar.show(
          context,
          message: strings.videoUnsupported,
          type: AppSnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPhoto = false);
    }
  }

  Future<void> _chooseCameraMedia() async {
    if (_loadingPhoto || _uploading) return;
    final strings = SnapshotStrings.of(context);
    final type = await showModalBottomSheet<SnapshotMediaType>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(strings.takePhoto),
              onTap: () => Navigator.pop(
                sheetContext,
                SnapshotMediaType.photo,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(strings.recordVideo),
              subtitle: Text(strings.videoMaxDuration),
              onTap: () => Navigator.pop(
                sheetContext,
                SnapshotMediaType.video,
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || type == null) return;
    if (type == SnapshotMediaType.video) {
      await _pickVideo(ImageSource.camera);
    } else {
      await _pickImage(ImageSource.camera);
    }
  }

  Future<void> _selectRecentPhoto(AssetEntity asset) async {
    if (_loadingPhoto || _uploading) return;
    final strings = SnapshotStrings.of(context);
    setState(() => _loadingPhoto = true);
    try {
      final file = await asset.file;
      if (file == null) throw StateError('asset-file-unavailable');
      await _useImageFile(file);
    } catch (_) {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: strings.photoFailed,
          type: AppSnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPhoto = false);
    }
  }

  Future<void> _useImageFile(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final width = frame.image.width;
    final height = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    if (!mounted) return;
    await _deleteTemporaryComposition();
    await _disposeVideoControllers();
    if (!mounted) return;
    setState(() {
      _sourceFile = file;
      _mediaType = SnapshotMediaType.photo;
      _sourceWidth = width;
      _sourceHeight = height;
      _step = 0;
    });
  }

  Future<void> _useVideoFile(File file) async {
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize().timeout(const Duration(seconds: 30));
      final duration = controller.value.duration;
      final size = controller.value.size;
      if (duration <= Duration.zero || size.isEmpty) {
        throw StateError('snapshot-video-metadata-invalid');
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _deleteTemporaryComposition();
      await _disposeVideoControllers();
      final durationSeconds = duration.inMilliseconds / 1000.0;
      final trimEnd = durationSeconds.clamp(.1, 12.0).toDouble();
      setState(() {
        _sourceFile = file;
        _mediaType = SnapshotMediaType.video;
        _sourceVideoController = controller;
        _videoDuration = duration;
        _videoTrimSeconds = RangeValues(0, trimEnd);
        _sourceWidth = size.width.round();
        _sourceHeight = size.height.round();
        _step = 0;
      });
      controller.addListener(_keepSourceVideoInsideTrim);
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  }

  Future<File> _trimSnapshotVideo(
    File source, {
    required int startMs,
    required int endMs,
  }) async {
    final trimmedPath = await _snapshotVideoEditorChannel.invokeMethod<String>(
      'trimVideo',
      <String, Object>{
        'path': source.path,
        'startMs': startMs,
        'endMs': endMs,
      },
    ).timeout(const Duration(minutes: 2));
    if (trimmedPath == null || trimmedPath.trim().isEmpty) {
      throw StateError('snapshot-video-trim-empty');
    }
    final trimmed = File(trimmedPath);
    if (!await trimmed.exists() || await trimmed.length() <= 0) {
      throw StateError('snapshot-video-trim-missing');
    }
    return trimmed;
  }

  Future<File?> _compressAndroidSnapshotVideo(File source) async {
    if (!Platform.isAndroid) return null;
    try {
      await VideoCompress.deleteAllCache();
      final info = await VideoCompress.compressVideo(
        source.path,
        quality: VideoQuality.Res1280x720Quality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: 30,
        // 구간 선택은 네이티브 muxer에서 이미 끝났다. 플러그인에
        // trim 값을 다시 넘기지 않아 음수 구간 계산을 원천 차단한다.
      ).timeout(
        const Duration(minutes: 3),
        onTimeout: () async {
          await VideoCompress.cancelCompression();
          throw TimeoutException('snapshot-video-optimization-timeout');
        },
      );
      final optimized = info?.file;
      if (optimized == null ||
          optimized.path == source.path ||
          !await optimized.exists() ||
          await optimized.length() <= 0) {
        return null;
      }
      return optimized;
    } catch (error) {
      // 기기 코덱이 재인코딩을 지원하지 않아도 이미 검증된
      // 네이티브 trim 결과로 게시할 수 있게 최적화만 생략한다.
      Logger.warning('Android 스낵 영상 최적화 생략: $error');
      return null;
    }
  }

  Future<void> _disposeVideoControllers() async {
    final source = _sourceVideoController;
    final preview = _previewVideoController;
    _sourceVideoController = null;
    _previewVideoController = null;
    await source?.dispose();
    if (!identical(source, preview)) await preview?.dispose();
  }

  void _keepSourceVideoInsideTrim() {
    final controller = _sourceVideoController;
    if (controller == null || !controller.value.isPlaying) return;
    final end = Duration(
      milliseconds: (_videoTrimSeconds.end * 1000).round(),
    );
    if (controller.value.position >= end) {
      unawaited(controller.pause());
      unawaited(controller.seekTo(Duration(
        milliseconds: (_videoTrimSeconds.start * 1000).round(),
      )));
      if (mounted) setState(() {});
    }
  }

  void _toggleSourceVideoPreview() {
    final controller = _sourceVideoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      unawaited(controller.pause());
      return;
    }
    unawaited(
      controller
          .seekTo(Duration(
            milliseconds: (_videoTrimSeconds.start * 1000).round(),
          ))
          .then((_) => controller.play()),
    );
  }

  void _seekSourceVideoForTrim(double seconds) {
    final controller = _sourceVideoController;
    if (controller?.value.isPlaying == true) {
      unawaited(controller!.pause());
    }
    unawaited(controller?.seekTo(Duration(
      milliseconds: (seconds * 1000).round(),
    )));
  }

  void _moveVideoTrimWindow(double requestedStart) {
    final totalSeconds = _videoDuration.inMilliseconds / 1000.0;
    if (totalSeconds <= 0) return;
    final selectedDuration = (_videoTrimSeconds.end - _videoTrimSeconds.start)
        .clamp(.1, 12.0)
        .toDouble();
    final maxStart = (totalSeconds - selectedDuration).clamp(0.0, totalSeconds);
    final start = requestedStart.clamp(0.0, maxStart).toDouble();
    final end =
        (start + selectedDuration).clamp(start, totalSeconds).toDouble();
    setState(() => _videoTrimSeconds = RangeValues(start, end));
    _seekSourceVideoForTrim(start);
  }

  void _updateVideoTrimStartHandle(double requestedStart) {
    final end = _videoTrimSeconds.end;
    final minimumStart = (end - 12).clamp(0.0, end).toDouble();
    final maximumStart = (end - .1).clamp(minimumStart, end).toDouble();
    final start = requestedStart.clamp(minimumStart, maximumStart).toDouble();
    setState(() => _videoTrimSeconds = RangeValues(start, end));
    _seekSourceVideoForTrim(start);
  }

  void _updateVideoTrimEndHandle(double requestedEnd) {
    final totalSeconds = _videoDuration.inMilliseconds / 1000.0;
    if (totalSeconds <= 0) return;
    final start = _videoTrimSeconds.start;
    final minimumEnd = (start + .1).clamp(start, totalSeconds).toDouble();
    final maximumEnd = (start + 12).clamp(minimumEnd, totalSeconds).toDouble();
    final end = requestedEnd.clamp(minimumEnd, maximumEnd).toDouble();
    setState(() => _videoTrimSeconds = RangeValues(start, end));
    _seekSourceVideoForTrim(end);
  }

  void _handleOverlayTextChanged(String layerId, String text) {
    final layer = _textLayerById(layerId);
    if (layer == null) return;
    final revision = ++layer.layoutRevision;
    if (layer.text != text) setState(() => layer.text = text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = _textLayerById(layerId);
      if (!mounted || current == null || revision != current.layoutRevision) {
        return;
      }
      final renderObject = _compositionKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize) {
        return;
      }
      final nextScale = _fitOverlayFontScale(
        current,
        current.fontScale,
        renderObject.size.width,
        renderObject.size.height,
      );
      final nextPosition = _boundedOverlayPosition(
        current,
        current.position,
        renderObject.size.width,
        renderObject.size.height,
        fontScale: nextScale,
      );
      if (nextScale == current.fontScale && nextPosition == current.position) {
        return;
      }
      setState(() {
        current
          ..fontScale = nextScale
          ..position = nextPosition;
      });
    });
  }

  Future<void> _finishOverlayEditing() {
    final layerId = _editingTextLayerId;
    if (layerId == null) {
      return _overlayCommitCompleter?.future ?? Future<void>.value();
    }
    final layer = _textLayerById(layerId);
    if (layer == null) {
      _editingTextLayerId = null;
      return Future<void>.value();
    }
    if (layer.focusNode.hasFocus) layer.focusNode.unfocus();
    return _scheduleOverlayCommit(layerId);
  }

  Future<bool> _waitForNextPaintedFrame() {
    final completer = Completer<bool>();
    final watchdog = Timer(const Duration(seconds: 2), () {
      if (!completer.isCompleted) completer.complete(false);
    });
    // This callback is registered only after the focus-loss post-frame commit
    // has completed. It therefore runs after the *following* frame's paint,
    // which is the first frame containing the finalized non-editing overlay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      watchdog.cancel();
      if (!completer.isCompleted) completer.complete(mounted);
    });
    WidgetsBinding.instance.scheduleFrame();
    return completer.future;
  }

  TextStyle _overlayTextStyle(
    _SnapshotTextLayer layer,
    double imageWidth, {
    double? fontScale,
  }) {
    return TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: (imageWidth * .066).clamp(19, 34).toDouble() *
          (fontScale ?? layer.fontScale),
      fontWeight: FontWeight.w800,
      height: isChineseUi(context) ? 1.3 : 1.18,
      color: layer.lightText ? Colors.white : const Color(0xFF111111),
      shadows: layer.lightText
          ? const [
              Shadow(
                color: Color(0x99000000),
                blurRadius: 8,
                offset: Offset(0, 1),
              ),
            ]
          : const [
              Shadow(
                color: Color(0x77FFFFFF),
                blurRadius: 8,
                offset: Offset(0, 1),
              ),
            ],
    );
  }

  Size _overlayPaintBounds(
    _SnapshotTextLayer layer,
    double imageWidth, {
    required double fontScale,
  }) {
    final text = layer.controller.text;
    if (text.isEmpty || imageWidth <= 0) return Size.zero;
    final maxTextWidth = imageWidth * .82;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: _overlayTextStyle(
          layer,
          imageWidth,
          fontScale: fontScale,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout(maxWidth: maxTextWidth);
    // TextPainter does not include the blur extent of TextStyle.shadows.
    const shadowSafety = 10.0;
    final size = Size(
      painter.width + shadowSafety * 2,
      painter.height + shadowSafety * 2,
    );
    painter.dispose();
    return size;
  }

  double _fitOverlayFontScale(
    _SnapshotTextLayer layer,
    double requested,
    double imageWidth,
    double imageHeight,
  ) {
    var candidate = requested.clamp(.25, 1.75).toDouble();
    if (layer.controller.text.isEmpty || imageWidth <= 0 || imageHeight <= 0) {
      return candidate;
    }
    for (var iteration = 0; iteration < 5; iteration++) {
      final bounds = _overlayPaintBounds(
        layer,
        imageWidth,
        fontScale: candidate,
      );
      if (bounds.width <= imageWidth && bounds.height <= imageHeight) {
        break;
      }
      final widthRatio = imageWidth / bounds.width;
      final heightRatio = imageHeight / bounds.height;
      final fitRatio = widthRatio < heightRatio ? widthRatio : heightRatio;
      if (fitRatio >= 1) break;
      final fitted = (candidate * fitRatio * .98).clamp(.25, candidate);
      if ((candidate - fitted).abs() < .001) break;
      candidate = fitted.toDouble();
    }
    return candidate;
  }

  Offset _boundedOverlayPosition(
    _SnapshotTextLayer layer,
    Offset requested,
    double imageWidth,
    double imageHeight, {
    required double fontScale,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0) return const Offset(.5, .5);
    if (layer.controller.text.isEmpty) {
      return Offset(
        requested.dx.clamp(0.0, 1.0).toDouble(),
        requested.dy.clamp(0.0, 1.0).toDouble(),
      );
    }
    final bounds = _overlayPaintBounds(
      layer,
      imageWidth,
      fontScale: fontScale,
    );
    final halfWidth = (bounds.width / imageWidth / 2).clamp(0.0, .5).toDouble();
    final halfHeight =
        (bounds.height / imageHeight / 2).clamp(0.0, .5).toDouble();
    final x = halfWidth >= .5
        ? .5
        : requested.dx.clamp(halfWidth, 1 - halfWidth).toDouble();
    final y = halfHeight >= .5
        ? .5
        : requested.dy.clamp(halfHeight, 1 - halfHeight).toDouble();
    return Offset(x, y);
  }

  void _startOverlayTransform(
    String layerId,
    ScaleStartDetails details,
  ) {
    if (_composing || _uploading) return;
    final layer = _textLayerById(layerId);
    if (layer == null) return;
    _transformingTextLayerId = layerId;
    _gestureStartFontScale = layer.fontScale;
    _gestureStartPosition = layer.position;
    _gestureStartFocalPoint = details.focalPoint;
    if (_selectedTextLayerId != layerId || _editingTextLayerId != null) {
      setState(() {
        _selectedTextLayerId = layerId;
        _editingTextLayerId = null;
      });
    }
  }

  void _updateOverlayTransform(
    String layerId,
    ScaleUpdateDetails details,
    double imageWidth,
    double imageHeight,
  ) {
    if (_composing || _uploading) return;
    if (_transformingTextLayerId != layerId ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      return;
    }
    final layer = _textLayerById(layerId);
    if (layer == null || layer.text.isEmpty) return;
    final nextScale = _fitOverlayFontScale(
      layer,
      _gestureStartFontScale * details.scale,
      imageWidth,
      imageHeight,
    );
    final nextPosition = _boundedOverlayPosition(
      layer,
      Offset(
        _gestureStartPosition.dx +
            (details.focalPoint.dx - _gestureStartFocalPoint.dx) / imageWidth,
        _gestureStartPosition.dy +
            (details.focalPoint.dy - _gestureStartFocalPoint.dy) / imageHeight,
      ),
      imageWidth,
      imageHeight,
      fontScale: nextScale,
    );
    setState(() {
      layer
        ..position = nextPosition
        ..fontScale = nextScale;
    });
  }

  void _endOverlayTransform(String layerId) {
    if (_transformingTextLayerId == layerId) {
      _transformingTextLayerId = null;
    }
  }

  Future<void> _deleteTextLayer(String layerId) async {
    if (_composing || _uploading) return;
    if (_editingTextLayerId == layerId) await _finishOverlayEditing();
    if (!mounted) return;
    final layer = _textLayerById(layerId);
    if (layer == null) return;
    setState(() {
      _textLayers.remove(layer);
      _selectedTextLayerId = _textLayers.isEmpty ? null : _textLayers.last.id;
      if (_editingTextLayerId == layerId) _editingTextLayerId = null;
      if (_transformingTextLayerId == layerId) {
        _transformingTextLayerId = null;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => layer.dispose());
  }

  void _bringSelectedTextLayerForward() {
    if (_composing || _uploading) return;
    final layer = _selectedTextLayer;
    if (layer == null || identical(layer, _textLayers.last)) return;
    setState(() {
      _textLayers
        ..remove(layer)
        ..add(layer);
    });
  }

  void _handlePhotoTap() {
    if (_composing || _uploading) return;
    if (_editingTextLayerId != null) {
      unawaited(_finishOverlayEditing());
    } else if (_selectedTextLayerId != null) {
      setState(() => _selectedTextLayerId = null);
    }
  }

  Future<void> _returnToMediaSelection() async {
    if (_sourceFile == null || _uploading) return;
    await _finishOverlayEditing();
    await _deleteTemporaryComposition();
    if (!mounted) return;
    setState(() {
      _sourceFile = null;
      _mediaType = SnapshotMediaType.photo;
      _sourceWidth = 0;
      _sourceHeight = 0;
      _selectedTextLayerId = null;
      _editingTextLayerId = null;
      _transformingTextLayerId = null;
    });
    await _disposeVideoControllers();
    unawaited(_loadRecentPhotos(requestPermission: false));
  }

  Future<void> _continueFromEditor() async {
    if (_sourceFile == null || _composing || _uploading) return;
    await _composeAndContinue();
  }

  SnapshotOverlay _legacyOverlay() {
    _SnapshotTextLayer? layer;
    for (final candidate in _textLayers.reversed) {
      if (candidate.text.trim().isNotEmpty) {
        layer = candidate;
        break;
      }
    }
    if (layer == null) {
      return const SnapshotOverlay(
        text: '',
        x: .5,
        y: .5,
        lightText: true,
      );
    }
    final firstThreeLines = layer.text.trim().split('\n').take(3).join('\n');
    final legacyText =
        String.fromCharCodes(firstThreeLines.runes.take(60)).trim();
    return SnapshotOverlay(
      text: legacyText,
      x: layer.position.dx,
      y: layer.position.dy,
      lightText: layer.lightText,
      fontScale: layer.fontScale,
    );
  }

  List<SnapshotOverlay> _snapshotOverlays() => _textLayers
      .asMap()
      .entries
      .where((entry) => entry.value.text.trim().isNotEmpty)
      .map((entry) => SnapshotOverlay(
            id: entry.value.id,
            text: entry.value.text,
            x: entry.value.position.dx,
            y: entry.value.position.dy,
            lightText: entry.value.lightText,
            fontScale: entry.value.fontScale,
            order: entry.key,
          ))
      .take(5)
      .toList(growable: false);

  Future<void> _composeAndContinue() async {
    final strings = SnapshotStrings.of(context);
    if (_sourceFile == null) {
      AppSnackBar.show(context, message: strings.photoRequired);
      return;
    }
    if (_composing) return;
    setState(() => _composing = true);
    try {
      await _finishOverlayEditing();
      if (!mounted) return;
      if (_mediaType == SnapshotMediaType.video) {
        await _sourceVideoController?.pause();
        final source = _sourceFile!;
        final sourceDurationMs = _videoDuration.inMilliseconds;
        final minimumDurationMs =
            sourceDurationMs < 100 ? sourceDurationMs : 100;
        final maximumStartMs = sourceDurationMs - minimumDurationMs;
        final startMs = (_videoTrimSeconds.start * 1000)
            .round()
            .clamp(0, maximumStartMs)
            .toInt();
        final maximumEndMs = (startMs + 12000).clamp(0, sourceDurationMs);
        final endMs = (_videoTrimSeconds.end * 1000)
            .round()
            .clamp(startMs + minimumDurationMs, maximumEndMs)
            .toInt();
        final durationMs = endMs - startMs;
        if (durationMs <= 0 || durationMs > 12000) {
          throw StateError('snapshot-video-duration-invalid');
        }
        final usesWholeSource = startMs <= 50 &&
            (sourceDurationMs - endMs).abs() <= 50 &&
            sourceDurationMs <= 12000;
        File? temporaryTrim;
        File? pendingOutput;
        File? pendingThumbnail;
        late File output;
        try {
          if (Platform.isAndroid || Platform.isIOS) {
            // Android streams selected tracks into a normalized MP4 without
            // re-opening the AAC decoder. iOS exports the exact millisecond
            // time range with AVFoundation, avoiding the plugin's end-of-file
            // duration calculation. Neither path loads the source into memory.
            output = await _trimSnapshotVideo(
              source,
              startMs: startMs,
              endMs: endMs,
            );
            temporaryTrim = output;
            if (Platform.isAndroid) {
              final optimized = await _compressAndroidSnapshotVideo(output);
              if (optimized != null) output = optimized;
            }
          } else {
            await VideoCompress.deleteAllCache();
            final trimWithPlugin = !usesWholeSource;
            final info = await VideoCompress.compressVideo(
              source.path,
              quality: VideoQuality.MediumQuality,
              deleteOrigin: false,
              includeAudio: true,
              frameRate: 30,
              startTime: trimWithPlugin ? startMs ~/ 1000 : null,
              duration: trimWithPlugin
                  ? (durationMs / 1000).ceil().clamp(1, 12).toInt()
                  : null,
            ).timeout(
              const Duration(minutes: 5),
              onTimeout: () async {
                await VideoCompress.cancelCompression();
                throw TimeoutException('snapshot-video-compression-timeout');
              },
            );
            final compressed = info?.file;
            if (compressed == null || !await compressed.exists()) {
              throw StateError('snapshot-video-compression-failed');
            }
            output = compressed;
          }
          if (!await output.exists() || await output.length() <= 0) {
            throw StateError('snapshot-video-output-empty');
          }
          pendingOutput = output;
          final thumbnail = await VideoCompress.getFileThumbnail(
            output.path,
            quality: 82,
            position: 0,
          ).timeout(const Duration(minutes: 1));
          if (!await thumbnail.exists()) {
            throw StateError('snapshot-video-thumbnail-failed');
          }
          pendingThumbnail = thumbnail;
          await _deleteTemporaryComposition();
          final previewController = VideoPlayerController.file(output);
          await previewController
              .initialize()
              .timeout(const Duration(seconds: 30));
          await previewController.setLooping(true);
          if (!mounted) {
            await previewController.dispose();
            return;
          }
          final obsoleteTrim = temporaryTrim;
          if (obsoleteTrim != null && obsoleteTrim.path != output.path) {
            await obsoleteTrim.delete().catchError((_) => obsoleteTrim);
            temporaryTrim = null;
          }
          await _previewVideoController?.dispose();
          setState(() {
            _composedFile = output;
            _videoThumbnail = thumbnail;
            _previewVideoController = previewController;
            _sourceWidth = previewController.value.size.width.round();
            _sourceHeight = previewController.value.size.height.round();
            _step = 1;
          });
          pendingOutput = null;
          pendingThumbnail = null;
          temporaryTrim = null;
          unawaited(previewController.play());
          return;
        } finally {
          final staleOutputs = <String, File>{
            if (pendingOutput != null) pendingOutput.path: pendingOutput,
            if (temporaryTrim != null) temporaryTrim.path: temporaryTrim,
          };
          for (final staleOutput in staleOutputs.values) {
            if (await staleOutput.exists()) {
              await staleOutput.delete().catchError((_) => staleOutput);
            }
          }
          final staleThumbnail = pendingThumbnail;
          if (staleThumbnail != null && await staleThumbnail.exists()) {
            await staleThumbnail.delete().catchError((_) => staleThumbnail);
          }
        }
      }
      final didPaintFinalOverlay = await _waitForNextPaintedFrame();
      if (!mounted) return;
      if (!didPaintFinalOverlay) {
        throw StateError('composition-frame-not-painted');
      }
      final boundary = _compositionKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('composition-not-ready');
      final logicalWidth = boundary.size.width;
      final ratio = (1440 / logicalWidth).clamp(1.5, 3.2).toDouble();
      final image = await boundary.toImage(pixelRatio: ratio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) throw StateError('composition-empty');

      final directory = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final png = File(path.join(directory.path, 'snapshot_$stamp.png'));
      await png.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      final jpgPath = path.join(directory.path, 'snapshot_$stamp.jpg');
      final compressed = await FlutterImageCompress.compressAndGetFile(
        png.path,
        jpgPath,
        format: CompressFormat.jpeg,
        quality: 88,
        keepExif: false,
      );
      await png.delete().catchError((_) => png);
      if (compressed == null) throw StateError('compression-failed');
      await _deleteTemporaryComposition();
      if (!mounted) return;
      setState(() {
        _composedFile = File(compressed.path);
        _step = 1;
      });
    } catch (error, stackTrace) {
      Logger.error('스낵 미디어 처리 실패', error, stackTrace);
      if (mounted) {
        AppSnackBar.show(
          context,
          message: _mediaType == SnapshotMediaType.video
              ? strings.videoProcessingFailed
              : strings.photoFailed,
          type: AppSnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _composing = false);
    }
  }

  Future<void> _upload() async {
    if (_uploading) return;
    final strings = SnapshotStrings.of(context);
    final file = _composedFile;
    if (file == null) return;
    if (_visibility == SnapshotVisibility.category &&
        _selectedCategoryIds.isEmpty) {
      setState(() => _showCategoryRequired = true);
      AppSnackBar.show(
        context,
        message: strings.groupRequired,
        type: AppSnackBarType.warning,
      );
      return;
    }
    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });
    final cleanupExistingUpload = _pendingUploadSnapshotId != null;
    final snapshotId = _pendingUploadSnapshotId ??= _service.createSnapshotId();
    try {
      await _previewVideoController?.pause();
      final created = await _service.createSnapshot(
        snapshotId: snapshotId,
        composedImage: file,
        mediaType: _mediaType,
        videoThumbnail: _videoThumbnail,
        overlays: _snapshotOverlays(),
        visibility: _visibility,
        visibleToCategoryIds: _visibility == SnapshotVisibility.category
            ? _selectedCategoryIds
            : const <String>[],
        overlay: _legacyOverlay(),
        aspectRatio: _aspectRatio,
        sourceWidth: _sourceWidth,
        sourceHeight: _sourceHeight,
        durationMs: _mediaType == SnapshotMediaType.video
            ? (_previewVideoController?.value.duration.inMilliseconds ??
                    ((_videoTrimSeconds.end - _videoTrimSeconds.start) * 1000)
                        .round())
                .clamp(0, 12000)
                .toInt()
            : 0,
        cleanupExistingUpload: cleanupExistingUpload,
        onProgress: (progress) {
          if (mounted) setState(() => _uploadProgress = progress);
        },
      );
      try {
        await SnapshotArchiveService.instance.savePublished(
          snapshot: created,
          media: file,
          thumbnail: _videoThumbnail,
        );
      } catch (archiveError, archiveStackTrace) {
        Logger.error(
          '게시된 스낵의 로컬 보관 실패 (snapshotId=${created.id})',
          archiveError,
          archiveStackTrace,
        );
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(strings.archiveFailedTitle),
              content: Text(strings.archiveFailedBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(strings.confirm),
                ),
              ],
            ),
          );
        }
      }
      widget.onCreated?.call();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      if (!mounted) return;
      Logger.error('스낵 업로드 실패', error, stackTrace);
      setState(() => _uploading = false);
      final serviceUnavailable =
          error is FirebaseFunctionsException && error.code == 'not-found';
      AppSnackBar.show(
        context,
        message: serviceUnavailable
            ? strings.uploadServiceUnavailable
            : strings.uploadFailed,
        type: AppSnackBarType.error,
      );
    }
  }

  Future<void> _deleteTemporaryComposition() async {
    final file = _composedFile;
    final thumbnail = _videoThumbnail;
    _composedFile = null;
    _videoThumbnail = null;
    _pendingUploadSnapshotId = null;
    if (file != null && await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    if (thumbnail != null && await thumbnail.exists()) {
      try {
        await thumbnail.delete();
      } catch (_) {}
    }
  }

  Future<bool> _confirmExit() async {
    if (_sourceFile == null || _uploading) return !_uploading;
    final strings = SnapshotStrings.of(context);
    return await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.white,
          barrierColor: Colors.black.withValues(alpha: .36),
          showDragHandle: false,
          useSafeArea: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (sheetContext) => SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(20, 22, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.deleteConfirm,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: sheetContext.rf(16).clamp(15, 17).toDouble(),
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        child: Text(strings.cancel),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFB42318),
                        ),
                        child: Text(strings.delete),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final compactUploadAction = MediaQuery.sizeOf(context).width < 340 ||
        MediaQuery.textScalerOf(context).scale(14) > 24;
    return PopScope(
      canPop: _sourceFile == null && !_uploading,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _uploading) return;
        if (_step == 1) {
          setState(() => _step = 0);
          return;
        }
        if (_sourceFile != null) {
          await _returnToMediaSelection();
          return;
        }
        final shouldExit = await _confirmExit();
        if (shouldExit && mounted) Navigator.of(this.context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        // Keep the media canvas at a stable size while the keyboard overlays it.
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          toolbarHeight: _snapshotToolbarHeight,
          automaticallyImplyLeading: false,
          leadingWidth: 48,
          leading: IconButton(
            onPressed: _uploading
                ? null
                : () async {
                    if (_step == 1) {
                      setState(() => _step = 0);
                    } else if (_sourceFile != null) {
                      await _returnToMediaSelection();
                    } else if (await _confirmExit() && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
            icon: Icon(
              _step == 0 && _sourceFile == null
                  ? Icons.close_rounded
                  : Icons.arrow_back_rounded,
              color: const Color(0xFF111827),
              size: context.ri(22).clamp(21, 24).toDouble(),
            ),
            tooltip: _step == 0 && _sourceFile == null
                ? MaterialLocalizations.of(context).closeButtonTooltip
                : MaterialLocalizations.of(context).backButtonTooltip,
          ),
          flexibleSpace: _buildCenteredSnapshotTitle(strings.createSnapshot),
          actions: [
            if (_step == 0)
              SizedBox.square(
                dimension: 48,
                child: IconButton(
                  onPressed: _sourceFile == null || _composing
                      ? null
                      : _continueFromEditor,
                  icon: _composing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.arrow_forward_rounded,
                          size: context.ri(23).clamp(21, 25).toDouble(),
                        ),
                  color: const Color(0xFF111827),
                  disabledColor: const Color(0xFFD1D5DB),
                  tooltip: MaterialLocalizations.of(context).nextPageTooltip,
                ),
              )
            else if (compactUploadAction)
              SizedBox.square(
                dimension: 48,
                child: IconButton(
                  onPressed: _uploading ? null : _upload,
                  tooltip: strings.upload,
                  icon: _uploading
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
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.15,
                child: TextButton.icon(
                  onPressed: _uploading ? null : _upload,
                  icon: _uploading
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.check_rounded,
                          size: context.ri(18).clamp(17, 20).toDouble(),
                        ),
                  label: Text(
                    strings.upload,
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
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
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 8),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _step == 0 ? _buildEditor(strings) : _buildPreview(strings),
          ),
        ),
      ),
    );
  }

  double get _snapshotToolbarHeight {
    final base = context.rh(56, min: 54, max: 60);
    final scaledTitle = MediaQuery.textScalerOf(context).scale(
      context.rf(18).clamp(16, 19).toDouble(),
    );
    final accessible = scaledTitle * 1.2 + 24;
    return accessible > base ? accessible.clamp(base, 96).toDouble() : base;
  }

  Widget _buildCenteredSnapshotTitle(String title) {
    final clearance = MediaQuery.sizeOf(context).width < 360 ? 88.0 : 104.0;
    return SafeArea(
      bottom: false,
      child: IgnorePointer(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: clearance),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(18).clamp(16, 19).toDouble(),
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _textLayerLabel(_SnapshotTextLayer layer, int index) {
    final normalized = layer.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final preview = normalized.isEmpty
        ? SnapshotStrings.of(context).textHint
        : String.fromCharCodes(normalized.runes.take(18));
    return '${index + 1}. $preview';
  }

  Widget _buildTextLayer(
    _SnapshotTextLayer layer,
    double imageWidth,
    double imageHeight,
    SnapshotStrings strings,
  ) {
    final editing = _editingTextLayerId == layer.id;
    final selected = _selectedTextLayerId == layer.id;
    if (_composing && layer.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final textStyle = _overlayTextStyle(layer, imageWidth);
    final textContent = editing
        ? SizedBox(
            width: imageWidth * .82,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: TextField(
                key: ValueKey('snapshot_overlay_text_field_${layer.id}'),
                controller: layer.controller,
                focusNode: layer.focusNode,
                showCursor: true,
                minLines: 1,
                maxLines: null,
                maxLength: 240,
                maxLengthEnforcement:
                    MaxLengthEnforcement.truncateAfterCompositionEnds,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                enableInteractiveSelection: true,
                onChanged: (text) => _handleOverlayTextChanged(layer.id, text),
                scrollPhysics: const NeverScrollableScrollPhysics(),
                onTapOutside: (_) => unawaited(_finishOverlayEditing()),
                textAlign: TextAlign.center,
                cursorColor:
                    layer.lightText ? Colors.white : const Color(0xFF111111),
                decoration: InputDecoration(
                  hintText: strings.textHint,
                  hintStyle: textStyle.copyWith(color: Colors.white70),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                ),
                style: textStyle,
              ),
            ),
          )
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: imageWidth * .82),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(
                layer.text.isEmpty ? strings.textHint : layer.text,
                textAlign: TextAlign.center,
                softWrap: true,
                style: layer.text.isEmpty
                    ? textStyle.copyWith(color: Colors.white70)
                    : textStyle,
              ),
            ),
          );
    final showSelectionChrome = selected && !_composing;
    final selectedTextContent = Stack(
      children: [
        textContent,
        if (showSelectionChrome)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .9),
                    width: 1.2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
      ],
    );

    return Positioned(
      left: layer.position.dx * imageWidth,
      top: layer.position.dy * imageHeight,
      child: FractionalTranslation(
        translation: const Offset(-.5, -.5),
        child: Semantics(
          selected: selected,
          label: layer.text.trim().isEmpty ? strings.textHint : layer.text,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: editing ? null : () => unawaited(_selectTextLayer(layer.id)),
            onDoubleTap: editing
                ? null
                : () => unawaited(_beginTextLayerEditing(layer.id)),
            onScaleStart: editing
                ? null
                : (details) => _startOverlayTransform(layer.id, details),
            onScaleUpdate: editing
                ? null
                : (details) => _updateOverlayTransform(
                      layer.id,
                      details,
                      imageWidth,
                      imageHeight,
                    ),
            onScaleEnd: editing ? null : (_) => _endOverlayTransform(layer.id),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Padding(
                  // Keep the close button's centre on the selected box corner
                  // while retaining its full touch target inside this widget.
                  padding: showSelectionChrome
                      ? const EdgeInsets.all(16)
                      : EdgeInsets.zero,
                  child: selectedTextContent,
                ),
                if (showSelectionChrome && !_uploading)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Semantics(
                      button: true,
                      label: strings.deleteText,
                      child: SizedBox.square(
                        dimension: 32,
                        child: IconButton(
                          tooltip: strings.deleteText,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => unawaited(
                            _deleteTextLayer(layer.id),
                          ),
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 19,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoTrimEditor(SnapshotStrings strings) {
    final controller = _sourceVideoController;
    final maximumSeconds = (_videoDuration.inMilliseconds / 1000.0)
        .clamp(.1, double.infinity)
        .toDouble();
    final rangeLabel = strings.videoTrimRange(
      _videoTrimSeconds.start,
      _videoTrimSeconds.end,
    );

    return SizedBox(
      height: 64,
      child: Row(
        children: [
          SizedBox.square(
            dimension: 44,
            child: IconButton(
              onPressed: controller == null ? null : _toggleSourceVideoPreview,
              padding: const EdgeInsets.all(9),
              color: const Color(0xFF111827),
              disabledColor: const Color(0xFF98A2B3),
              tooltip: strings.videoPreview,
              icon: controller == null
                  ? const Icon(Icons.play_arrow_rounded, size: 24)
                  : ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: controller,
                      builder: (context, value, _) => Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 24,
                      ),
                    ),
            ),
          ),
          Expanded(
            child: controller == null
                ? _buildVideoTrimWindow(
                    maximumSeconds: maximumSeconds,
                    rangeLabel: rangeLabel,
                    positionSeconds: _videoTrimSeconds.start,
                  )
                : ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => _buildVideoTrimWindow(
                      maximumSeconds: maximumSeconds,
                      rangeLabel: rangeLabel,
                      positionSeconds: value.position.inMilliseconds / 1000.0,
                    ),
                  ),
          ),
          SizedBox(
            width: 76,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.15,
              child: Text(
                rangeLabel,
                maxLines: 1,
                textAlign: TextAlign.end,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(11).clamp(10.5, 12).toDouble(),
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF475467),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoTrimWindow({
    required double maximumSeconds,
    required String rangeLabel,
    required double positionSeconds,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        if (trackWidth <= 0) return const SizedBox.shrink();
        const handleDiameter = 18.0;
        const handleRadius = handleDiameter / 2;
        final usableWidth =
            (trackWidth - handleDiameter).clamp(1.0, trackWidth).toDouble();
        const trackStart = handleRadius;
        final startSeconds =
            _videoTrimSeconds.start.clamp(0.0, maximumSeconds).toDouble();
        final endSeconds = _videoTrimSeconds.end
            .clamp(startSeconds, maximumSeconds)
            .toDouble();
        final startX = trackStart + usableWidth * startSeconds / maximumSeconds;
        final endX = trackStart + usableWidth * endSeconds / maximumSeconds;
        final selectedWidth =
            (endX - startX).clamp(0.0, usableWidth).toDouble();
        final selectedDuration =
            _videoTrimSeconds.end - _videoTrimSeconds.start;
        final playheadInSelection = selectedDuration > 0 &&
            positionSeconds >= _videoTrimSeconds.start &&
            positionSeconds <= _videoTrimSeconds.end;
        final playheadProgress = selectedDuration <= 0
            ? 0.0
            : ((positionSeconds - _videoTrimSeconds.start) / selectedDuration)
                .clamp(0.0, 1.0)
                .toDouble();
        final playheadLeft = (startX + selectedWidth * playheadProgress - 1)
            .clamp(0.0, (trackWidth - 2).clamp(0.0, trackWidth))
            .toDouble();

        double secondsForX(double pointerX) {
          return (maximumSeconds * (pointerX - trackStart) / usableWidth)
              .clamp(0.0, maximumSeconds)
              .toDouble();
        }

        void moveRangeFromPointer(double pointerX) {
          final duration = selectedDuration.clamp(.1, 12.0).toDouble();
          final maximumStart =
              (maximumSeconds - duration).clamp(0.0, maximumSeconds);
          final maximumLeft =
              trackStart + usableWidth * maximumStart / maximumSeconds;
          final nextLeft = (pointerX - _trimDragGrabOffset)
              .clamp(trackStart, maximumLeft)
              .toDouble();
          _moveVideoTrimWindow(
            maximumSeconds * (nextLeft - trackStart) / usableWidth,
          );
        }

        void updateActiveTarget(double pointerX) {
          switch (_trimDragTarget) {
            case _SnapshotTrimDragTarget.start:
              _updateVideoTrimStartHandle(secondsForX(pointerX));
              break;
            case _SnapshotTrimDragTarget.end:
              _updateVideoTrimEndHandle(secondsForX(pointerX));
              break;
            case _SnapshotTrimDragTarget.range:
              moveRangeFromPointer(pointerX);
              break;
            case null:
              break;
          }
        }

        void beginDrag(double pointerX) {
          final distanceFromStart = (pointerX - startX).abs();
          final distanceFromEnd = (pointerX - endX).abs();
          const handleHitRadius = 22.0;
          if (distanceFromStart <= handleHitRadius ||
              distanceFromEnd <= handleHitRadius) {
            _trimDragTarget = distanceFromStart <= distanceFromEnd
                ? _SnapshotTrimDragTarget.start
                : _SnapshotTrimDragTarget.end;
            updateActiveTarget(pointerX);
            return;
          }
          if (pointerX > startX && pointerX < endX) {
            _trimDragTarget = _SnapshotTrimDragTarget.range;
            _trimDragGrabOffset = pointerX - startX;
            return;
          }
          _trimDragTarget = distanceFromStart <= distanceFromEnd
              ? _SnapshotTrimDragTarget.start
              : _SnapshotTrimDragTarget.end;
          updateActiveTarget(pointerX);
        }

        return Semantics(
          slider: true,
          value: rangeLabel,
          onIncrease: () => _moveVideoTrimWindow(
            _videoTrimSeconds.start + .5,
          ),
          onDecrease: () => _moveVideoTrimWindow(
            _videoTrimSeconds.start - .5,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final pointerX = details.localPosition.dx;
              if (pointerX >= startX && pointerX <= endX) return;
              if ((pointerX - startX).abs() <= (pointerX - endX).abs()) {
                _updateVideoTrimStartHandle(secondsForX(pointerX));
              } else {
                _updateVideoTrimEndHandle(secondsForX(pointerX));
              }
            },
            onHorizontalDragStart: (details) => beginDrag(
              details.localPosition.dx,
            ),
            onHorizontalDragUpdate: (details) => updateActiveTarget(
              details.localPosition.dx,
            ),
            onHorizontalDragEnd: (_) => _trimDragTarget = null,
            onHorizontalDragCancel: () => _trimDragTarget = null,
            child: SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(
                    left: trackStart,
                    width: usableWidth,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD0D5DD),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Positioned(
                    left: startX,
                    width: selectedWidth < 2 ? 2 : selectedWidth,
                    child: Container(
                      height: 9,
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Positioned(
                    left: startX - handleRadius,
                    child: const _TrimHandle(diameter: handleDiameter),
                  ),
                  Positioned(
                    left: endX - handleRadius,
                    child: const _TrimHandle(diameter: handleDiameter),
                  ),
                  if (playheadInSelection)
                    Positioned(
                      left: playheadLeft,
                      child: IgnorePointer(
                        child: Container(
                          width: 2,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(99),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMediaTextActions(SnapshotStrings strings) {
    final iconSize = context.ri(22).clamp(21, 24).toDouble();
    final selectedLayer = _selectedTextLayer;
    final selectedIsFront = selectedLayer != null &&
        _textLayers.isNotEmpty &&
        identical(selectedLayer, _textLayers.last);
    const iconColor = Colors.white;
    const iconShadows = <Shadow>[
      Shadow(color: Colors.black87, blurRadius: 8),
    ];
    Widget action({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) {
      return SizedBox.square(
        dimension: 44,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          icon: Icon(
            icon,
            size: iconSize,
            color: onPressed == null ? Colors.white54 : iconColor,
            shadows: iconShadows,
          ),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      runAlignment: WrapAlignment.end,
      children: [
        if (selectedLayer != null)
          action(
            icon: Icons.edit_outlined,
            tooltip: strings.editText,
            onPressed: () => unawaited(
              _beginTextLayerEditing(selectedLayer.id),
            ),
          ),
        if (selectedLayer != null && !selectedIsFront)
          action(
            icon: Icons.flip_to_front_outlined,
            tooltip: strings.bringForward,
            onPressed: _bringSelectedTextLayerForward,
          ),
        if (selectedLayer != null)
          action(
            icon: selectedLayer.lightText
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            tooltip:
                selectedLayer.lightText ? strings.darkText : strings.lightText,
            onPressed: () => setState(() {
              final layer = _selectedTextLayer;
              if (layer != null) layer.lightText = !layer.lightText;
            }),
          ),
        if (_textLayers.length > 1)
          SizedBox.square(
            dimension: 44,
            child: PopupMenuButton<String>(
              tooltip: strings.selectText,
              color: Colors.white,
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.layers_outlined,
                size: iconSize,
                color: iconColor,
                shadows: iconShadows,
              ),
              onSelected: (layerId) => unawaited(_selectTextLayer(layerId)),
              itemBuilder: (context) => _textLayers
                  .asMap()
                  .entries
                  .toList(growable: false)
                  .reversed
                  .map(
                    (entry) => CheckedPopupMenuItem<String>(
                      value: entry.value.id,
                      checked: entry.value.id == _selectedTextLayerId,
                      child: Text(
                        _textLayerLabel(entry.value, entry.key),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        action(
          icon: Icons.text_fields_rounded,
          tooltip: '${strings.addText} (${_textLayers.length}/5)',
          onPressed: _addTextLayer,
        ),
      ],
    );
  }

  Widget _buildEditorControls(
    SnapshotStrings strings,
  ) {
    return SizedBox(
      height: 72,
      child: _videoDuration > Duration.zero
          ? _buildVideoTrimEditor(strings)
          : const SizedBox.shrink(),
    );
  }

  Widget _buildEditor(SnapshotStrings strings) {
    return LayoutBuilder(
      key: const ValueKey('snapshot_editor'),
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 360 ? 12.0 : 16.0;
        final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
        final keyboardOpen = keyboardInset > 0;
        return Padding(
          padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 8),
          child: Column(
            children: [
              Expanded(
                child: _sourceFile == null
                    ? _RecentPhotoGallery(
                        loading: _loadingGallery,
                        selecting: _loadingPhoto,
                        permissionDenied: _galleryPermissionDenied,
                        permissionLimited: _galleryPermissionLimited,
                        loadFailed: _galleryLoadFailed,
                        photos: _recentPhotos,
                        hasMore: _recentPhotos.length < _galleryTotalCount,
                        loadingMore: _loadingMoreGallery,
                        cameraLabel: strings.camera,
                        galleryLabel: strings.choosePhoto,
                        videoLabel: strings.chooseVideo,
                        addPhotosLabel: strings.addPhotos,
                        settingsLabel: strings.settings,
                        permissionMessage: strings.galleryPermissionRequired,
                        loadFailedMessage: strings.photoFailed,
                        retryLabel: strings.retry,
                        onCamera: _chooseCameraMedia,
                        onGallery: () => _pickImage(ImageSource.gallery),
                        onVideo: () => _pickVideo(ImageSource.gallery),
                        onAddPhotos: _selectMorePhotos,
                        onRetry: _loadRecentPhotos,
                        onOpenSettings: PhotoManager.openSetting,
                        onLoadMore: _loadMoreRecentPhotos,
                        onPhotoTap: _selectRecentPhoto,
                      )
                    : Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: AspectRatio(
                            aspectRatio: _aspectRatio,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: RepaintBoundary(
                                key: _compositionKey,
                                child: LayoutBuilder(
                                  builder: (context, imageConstraints) {
                                    final width = imageConstraints.maxWidth;
                                    final height = imageConstraints.maxHeight;
                                    return Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: _handlePhotoTap,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              if (_mediaType ==
                                                  SnapshotMediaType.photo)
                                                Image.file(
                                                  _sourceFile!,
                                                  fit: BoxFit.contain,
                                                )
                                              else if (_sourceVideoController !=
                                                      null &&
                                                  _sourceVideoController!
                                                      .value.isInitialized)
                                                FittedBox(
                                                  fit: BoxFit.contain,
                                                  child: SizedBox(
                                                    width:
                                                        _sourceVideoController!
                                                            .value.size.width,
                                                    height:
                                                        _sourceVideoController!
                                                            .value.size.height,
                                                    child: VideoPlayer(
                                                      _sourceVideoController!,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        for (final layer in _textLayers)
                                          _buildTextLayer(
                                            layer,
                                            width,
                                            height,
                                            strings,
                                          ),
                                        if (!_composing)
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: _buildMediaTextActions(
                                              strings,
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              if (_sourceFile != null && _mediaType == SnapshotMediaType.video)
                Visibility(
                  visible: !keyboardOpen,
                  maintainAnimation: true,
                  maintainSize: true,
                  maintainState: true,
                  child: _buildEditorControls(strings),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPreview(SnapshotStrings strings) {
    final file = _composedFile;
    return LayoutBuilder(
      key: const ValueKey('snapshot_preview'),
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 360 ? 12.0 : 16.0;
        return ListView(
          padding: EdgeInsets.fromLTRB(horizontal, 10, horizontal, 24),
          children: [
            if (_uploading) ...[
              LinearProgressIndicator(
                value: _uploadProgress > 0 ? _uploadProgress : null,
                minHeight: 2,
              ),
              const SizedBox(height: 10),
            ],
            if (file != null)
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 520,
                    maxHeight: constraints.maxHeight * .5,
                  ),
                  child: AspectRatio(
                    aspectRatio: _aspectRatio,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ColoredBox(
                        color: Colors.black,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_mediaType == SnapshotMediaType.photo)
                              Image.file(file, fit: BoxFit.contain)
                            else if (_previewVideoController != null &&
                                _previewVideoController!.value.isInitialized)
                              VideoPlayer(_previewVideoController!),
                            if (_mediaType == SnapshotMediaType.video)
                              IgnorePointer(
                                child: SnapshotOverlayLayer(
                                  overlays: _snapshotOverlays(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            SizedBox(height: context.rs(22).clamp(18, 24).toDouble()),
            Text(
              strings.visibilityPrompt,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(17).clamp(15.5, 18).toDouble(),
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
              ),
            ),
            SizedBox(height: context.rs(12).clamp(10, 14).toDouble()),
            _VisibilityRow(
              icon: Icons.public_outlined,
              title: strings.public,
              description: strings.publicDescription,
              selected: _visibility == SnapshotVisibility.public,
              onTap: () => setState(() {
                _visibility = SnapshotVisibility.public;
                _showCategoryRequired = false;
              }),
            ),
            const Divider(height: 1, indent: 40, color: Color(0xFFEAECF0)),
            _VisibilityRow(
              icon: Icons.group_outlined,
              title: strings.friends,
              description: strings.friendsDescription,
              selected: _visibility == SnapshotVisibility.friends,
              onTap: () => setState(() {
                _visibility = SnapshotVisibility.friends;
                _showCategoryRequired = false;
              }),
            ),
            const Divider(height: 1, indent: 40, color: Color(0xFFEAECF0)),
            _VisibilityRow(
              icon: Icons.groups_2_outlined,
              title: strings.groups,
              description: strings.groupsDescription,
              selected: _visibility == SnapshotVisibility.category,
              onTap: () => setState(
                () => _visibility = SnapshotVisibility.category,
              ),
              child: _visibility == SnapshotVisibility.category
                  ? _buildGroupSelection(strings)
                  : null,
            ),
          ],
        );
      },
    );
  }

  Widget _buildGroupSelection(SnapshotStrings strings) {
    if (_friendCategories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          strings.noGroups,
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(12).clamp(11, 13).toDouble(),
            fontWeight: FontWeight.w500,
            color: const Color(0xFF667085),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.groupsSelected(_selectedCategoryIds.length),
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(12).clamp(11, 13).toDouble(),
            fontWeight: FontWeight.w700,
            color: const Color(0xFF667085),
          ),
        ),
        const SizedBox(height: 4),
        for (final category in _friendCategories)
          _CategoryRow(
            category: category,
            selected: _selectedCategoryIds.contains(category.id),
            child: _selectedCategoryIds.contains(category.id)
                ? GroupAudiencePreview(
                    members: _membersForCategory(category),
                    loading: _isLoadingAudienceUsers &&
                        category.friendIds.isNotEmpty,
                  )
                : null,
            onTap: () {
              final next = List<String>.from(_selectedCategoryIds);
              if (next.contains(category.id)) {
                next.remove(category.id);
              } else {
                next.add(category.id);
              }
              setState(() {
                _selectedCategoryIds = next;
                if (next.isNotEmpty) _showCategoryRequired = false;
              });
              unawaited(_refreshSelectedAudienceUsers());
            },
          ),
        if (_showCategoryRequired && _selectedCategoryIds.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              strings.groupRequired,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(12).clamp(11, 13).toDouble(),
                fontWeight: FontWeight.w700,
                color: const Color(0xFFB42318),
              ),
            ),
          ),
      ],
    );
  }
}

class _TrimHandle extends StatelessWidget {
  const _TrimHandle({required this.diameter});

  final double diameter;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: diameter,
      child: const DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFF111827),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _RecentPhotoGallery extends StatelessWidget {
  const _RecentPhotoGallery({
    required this.loading,
    required this.selecting,
    required this.permissionDenied,
    required this.permissionLimited,
    required this.loadFailed,
    required this.photos,
    required this.hasMore,
    required this.loadingMore,
    required this.cameraLabel,
    required this.galleryLabel,
    required this.videoLabel,
    required this.addPhotosLabel,
    required this.settingsLabel,
    required this.permissionMessage,
    required this.loadFailedMessage,
    required this.retryLabel,
    required this.onCamera,
    required this.onGallery,
    required this.onVideo,
    required this.onAddPhotos,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onLoadMore,
    required this.onPhotoTap,
  });

  final bool loading;
  final bool selecting;
  final bool permissionDenied;
  final bool permissionLimited;
  final bool loadFailed;
  final List<AssetEntity> photos;
  final bool hasMore;
  final bool loadingMore;
  final String cameraLabel;
  final String galleryLabel;
  final String videoLabel;
  final String addPhotosLabel;
  final String settingsLabel;
  final String permissionMessage;
  final String loadFailedMessage;
  final String retryLabel;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onVideo;
  final VoidCallback onAddPhotos;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback onLoadMore;
  final ValueChanged<AssetEntity> onPhotoTap;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (permissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CameraButton(
                label: cameraLabel,
                enabled: !selecting,
                onPressed: onCamera,
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: selecting ? null : onGallery,
                icon: const Icon(Icons.photo_library_outlined, size: 19),
                label: Text(galleryLabel),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: selecting ? null : onVideo,
                icon: const Icon(Icons.video_library_outlined, size: 19),
                label: Text(videoLabel),
              ),
              const SizedBox(height: 20),
              Text(
                permissionMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF667085),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(onPressed: onRetry, child: Text(retryLabel)),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: onOpenSettings,
                    child: Text(settingsLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (loadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CameraButton(
                label: cameraLabel,
                enabled: !selecting,
                onPressed: onCamera,
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: selecting ? null : onGallery,
                icon: const Icon(Icons.photo_library_outlined, size: 19),
                label: Text(galleryLabel),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: selecting ? null : onVideo,
                icon: const Icon(Icons.video_library_outlined, size: 19),
                label: Text(videoLabel),
              ),
              const SizedBox(height: 20),
              Text(
                loadFailedMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF667085),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ),
        ),
      );
    }

    final leadingItemCount = permissionLimited ? 3 : 2;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (hasMore &&
                !loadingMore &&
                notification.metrics.extentAfter < 600) {
              onLoadMore();
            }
            return false;
          },
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(0, 2, 0, 8),
            physics: const BouncingScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
            ),
            itemCount: photos.length + leadingItemCount + (loadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _CameraButton(
                  label: cameraLabel,
                  enabled: !selecting,
                  onPressed: onCamera,
                  fillCell: true,
                );
              }
              if (index == 1) {
                return _PhotoActionCell(
                  label: videoLabel,
                  icon: Icons.video_library_outlined,
                  enabled: !selecting,
                  onPressed: onVideo,
                );
              }
              if (permissionLimited && index == 2) {
                return _PhotoActionCell(
                  label: addPhotosLabel,
                  icon: Icons.add_photo_alternate_outlined,
                  enabled: !selecting,
                  onPressed: onAddPhotos,
                );
              }
              final photoIndex = index - leadingItemCount;
              if (photoIndex >= photos.length) {
                return const Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final photo = photos[photoIndex];
              return Semantics(
                button: true,
                label: '${photoIndex + 1}',
                child: Material(
                  color: const Color(0xFFF2F4F7),
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: selecting ? null : () => onPhotoTap(photo),
                    child: Image(
                      image: AssetEntityImageProvider(
                        photo,
                        isOriginal: false,
                        thumbnailSize: const ThumbnailSize.square(420),
                      ),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (selecting)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.white.withValues(alpha: .6),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _PhotoActionCell extends StatelessWidget {
  const _PhotoActionCell({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 27, color: const Color(0xFF111827)),
                const SizedBox(height: 7),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: ['NotoSansKR'],
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF344054),
                    ),
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

class _CameraButton extends StatelessWidget {
  const _CameraButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.fillCell = false,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final bool fillCell;

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      label: label,
      child: Material(
        color: const Color(0xFF111827),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: context.rs(50).clamp(46, 56).toDouble(),
            child: const Icon(
              Icons.photo_camera_outlined,
              size: 24,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );

    if (!fillCell) return button;
    return Material(
      color: const Color(0xFFF2F4F7),
      borderRadius: BorderRadius.circular(10),
      child: Center(child: button),
    );
  }
}

class _VisibilityRow extends StatelessWidget {
  const _VisibilityRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.child,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 70),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 21, color: const Color(0xFF667085)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 15,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w700,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: ['NotoSansKR'],
                          fontSize: 12.5,
                          height: 1.3,
                          color: Color(0xFF667085),
                        ),
                      ),
                    ],
                  ),
                ),
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
            if (child != null)
              Padding(
                padding: EdgeInsets.only(
                  left: context.rs(35),
                  top: context.rs(8),
                ),
                child: child,
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.selected,
    required this.onTap,
    this.child,
  });

  final FriendCategory category;
  final bool selected;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 46),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(14).clamp(13, 15).toDouble(),
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: const Color(0xFF111827),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: context.ri(21).clamp(20, 23).toDouble(),
                    color: selected
                        ? const Color(0xFF475467)
                        : const Color(0xFFD0D5DD),
                  ),
                ],
              ),
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}
