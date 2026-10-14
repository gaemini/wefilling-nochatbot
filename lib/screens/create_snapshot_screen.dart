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

import '../design/tokens.dart';
import '../models/friend_category.dart';
import '../models/snapshot.dart';
import '../models/user_profile.dart';
import '../services/friend_category_service.dart';
import '../services/snapshot_archive_service.dart';
import '../services/snapshot_service.dart';
import '../snapshot/snapshot_storage_video.dart';
import '../snapshot/snapshot_create_widgets.dart';
import '../snapshot/snapshot_share_view.dart';
import '../providers/relationship_provider.dart';
import 'package:provider/provider.dart';
import '../snapshot/snapshot_strings.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/widgets/motion_press.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';
import '../l10n/ui_locale.dart';

// Short AVC/AAC clips can be uploaded as muxed. Keep the existing encoder for
// HEVC, large clips, and other formats, but run it only after Publish is tapped.
bool shouldCompressAndroidSnapshotVideo({
  required String? videoMime,
  required String? audioMime,
  required int fileSizeBytes,
}) {
  const directUploadLimitBytes = 32 * 1024 * 1024;
  return fileSizeBytes > directUploadLimitBytes ||
      videoMime != 'video/avc' ||
      (audioMime != null && audioMime != 'audio/mp4a-latm');
}

/// Do not retain an outgoing editor canvas or media player during a fade.
Widget snapshotEditorMotionLayout(Widget? current, List<Widget> previous) =>
    current ?? const SizedBox.shrink();

class CreateSnapshotScreen extends StatefulWidget {
  const CreateSnapshotScreen({
    super.key,
    this.onCreated,
    this.initialAudienceCategory,
  });

  final VoidCallback? onCreated;

  /// 그룹 화면에서 `스낵`으로 들어온 경우: 공개 범위를 그룹, 이 카테고리 선택으로
  /// 미리 채운다. 없으면(null) 기존 동작이다.
  final FriendCategory? initialAudienceCategory;

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

  StreamSubscription<List<FriendCategory>>? _categoriesSubscription;

  File? _sourceFile;
  File? _composedFile;
  File? _videoThumbnail;
  File? _optimizedVideoForUpload;
  bool _videoNeedsCompression = false;
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
  // 반응 문. 공개 범위와 분리된 설정이며 기존 동작과 같은 '답장 받기'가 기본이다.
  SnapshotResponseMode _responseMode = SnapshotResponseMode.replies;
  List<FriendCategory> _friendCategories = const <FriendCategory>[];
  List<String> _selectedCategoryIds = const <String>[];
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

  /// 고르기 그리드에서 고른 사진(미리보기). 없으면 가장 최근 항목을 보여 준다.
  AssetEntity? _pickedAsset;

  /// 편집 단계 영상 자르기 편집기 펼침 여부.
  bool _trimOpen = false;

  double get _aspectRatio {
    if (_sourceWidth <= 0 || _sourceHeight <= 0) return .8;
    return (_sourceWidth / _sourceHeight).clamp(.55, 1.8);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initialAudience = widget.initialAudienceCategory;
    if (initialAudience != null) {
      _visibility = SnapshotVisibility.category;
      _selectedCategoryIds = <String>[initialAudience.id];
    }
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
    });
    unawaited(_loadRecentPhotos());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        unawaited(
          context
              .read<RelationshipProvider>()
              .ensureInitialized()
              .catchError((Object _) {}),
        );
      } catch (_) {}
    });
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
    unawaited(VideoCompress.cancelCompression());
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
      final selection = layer.controller.selection;
      if (!selection.isValid || selection.end > layer.controller.text.length) {
        layer.controller.selection = TextSelection.collapsed(
          offset: layer.controller.text.length,
        );
      }
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
        if (text.trim().isEmpty) {
          setState(() {
            _textLayers.remove(layer);
            if (_selectedTextLayerId == layerId) {
              _selectedTextLayerId = null;
            }
            if (_editingTextLayerId == layerId) _editingTextLayerId = null;
            if (_transformingTextLayerId == layerId) {
              _transformingTextLayerId = null;
            }
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => layer.dispose());
          return;
        }
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

  Future<({File file, String? videoMime, String? audioMime})>
      _trimSnapshotVideo(
    File source, {
    required int startMs,
    required int endMs,
  }) async {
    final result = await _snapshotVideoEditorChannel.invokeMethod<Object?>(
      'trimVideo',
      <String, Object>{
        'path': source.path,
        'startMs': startMs,
        'endMs': endMs,
      },
    ).timeout(const Duration(minutes: 2));
    // iOS and older Android builds return a path; current Android also
    // returns the track MIME so only a compatible clip can bypass encoding.
    final trimmedPath = result is String
        ? result
        : result is Map
            ? result['path'] as String?
            : null;
    final videoMime = result is Map ? result['videoMime'] as String? : null;
    final audioMime = result is Map ? result['audioMime'] as String? : null;
    if (trimmedPath == null || trimmedPath.trim().isEmpty) {
      throw StateError('snapshot-video-trim-empty');
    }
    final trimmed = File(trimmedPath);
    if (!await trimmed.exists() || await trimmed.length() <= 0) {
      throw StateError('snapshot-video-trim-missing');
    }
    return (file: trimmed, videoMime: videoMime, audioMime: audioMime);
  }

  Future<File?> _compressAndroidSnapshotVideo(File source) async {
    if (!Platform.isAndroid) return null;
    try {
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

  void _setTextLayerFontScale(String layerId, double requestedScale) {
    final layer = _textLayerById(layerId);
    if (layer == null || _composing || _uploading) return;
    final renderObject = _compositionKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return;
    }
    final scale = _fitOverlayFontScale(
      layer,
      requestedScale,
      renderObject.size.width,
      renderObject.size.height,
    );
    final position = _boundedOverlayPosition(
      layer,
      layer.position,
      renderObject.size.width,
      renderObject.size.height,
      fontScale: scale,
    );
    setState(() {
      layer
        ..fontScale = scale
        ..position = position;
    });
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
      _trimOpen = false;
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
        var needsCompression = false;
        late File output;
        try {
          if (Platform.isAndroid || Platform.isIOS) {
            // Android streams selected tracks into a normalized MP4 without
            // re-opening the AAC decoder. iOS exports the exact millisecond
            // time range with AVFoundation, avoiding the plugin's end-of-file
            // duration calculation. Neither path loads the source into memory.
            final trimmed = await _trimSnapshotVideo(
              source,
              startMs: startMs,
              endMs: endMs,
            );
            output = trimmed.file;
            temporaryTrim = output;
            needsCompression = Platform.isAndroid &&
                shouldCompressAndroidSnapshotVideo(
                  videoMime: trimmed.videoMime,
                  audioMime: trimmed.audioMime,
                  fileSizeBytes: await output.length(),
                );
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
            _videoNeedsCompression = needsCompression;
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
    final composedFile = _composedFile;
    if (composedFile == null) return;
    if (_visibility == SnapshotVisibility.category &&
        _selectedCategoryIds.isEmpty) {
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
      var uploadFile = composedFile;
      if (_mediaType == SnapshotMediaType.video && _videoNeedsCompression) {
        final cached = _optimizedVideoForUpload;
        if (cached != null &&
            await cached.exists() &&
            await cached.length() > 0) {
          uploadFile = cached;
        } else {
          final optimized = await _compressAndroidSnapshotVideo(composedFile);
          if (!mounted) {
            if (optimized != null) {
              await optimized.delete().catchError((_) => optimized);
            }
            return;
          }
          if (optimized != null) {
            _optimizedVideoForUpload = optimized;
            uploadFile = optimized;
          }
        }
      }
      if (!mounted) return;
      final created = await _service.createSnapshot(
        snapshotId: snapshotId,
        composedImage: uploadFile,
        mediaType: _mediaType,
        videoThumbnail: _videoThumbnail,
        overlays: _snapshotOverlays(),
        visibility: _visibility,
        responseMode: _responseMode,
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
          media: uploadFile,
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
    final optimized = _optimizedVideoForUpload;
    _composedFile = null;
    _videoThumbnail = null;
    _optimizedVideoForUpload = null;
    _videoNeedsCompression = false;
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
    if (optimized != null &&
        optimized.path != file?.path &&
        await optimized.exists()) {
      try {
        await optimized.delete();
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
    return PopScope(
      canPop: _sourceFile == null && !_uploading,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _uploading) return;
        if (_step == 0 && _editingTextLayerId != null) {
          await _finishOverlayEditing();
          return;
        }
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
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // 고르기·편집·공유 세 단계 모두 검정 바탕(상태바 아이콘 흰색)이다.
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
        backgroundColor: Colors.black,
        // Keep the media canvas at a stable size while the keyboard overlays it.
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          top: false,
          bottom: false,
          child: AnimatedSwitcher(
            // One canvas/player owns its GlobalKey at a time, including a
            // rapid preview -> editor reversal before the fade completes.
            layoutBuilder: snapshotEditorMotionLayout,
            duration: MotionTokens.reduceMotion(context)
                ? MotionTokens.instant
                : MotionTokens.state,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, child) => Transform.translate(
                  offset: Offset(
                      0,
                      MotionTokens.reduceMotion(context)
                          ? 0
                          : 6 * (1 - animation.value)),
                  child: child,
                ),
              ),
            ),
            child: _step == 0 ? _buildEditor(strings) : _buildPreview(strings),
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
    final showSelectionChrome = (selected || editing) && !_composing;
    final selectedTextContent = Stack(
      clipBehavior: Clip.none,
      children: [
        textContent,
        // 편집·선택 중인 레이어: 1.5pt 흰 70% 점선, 4pt 띄움(합성에는 그리지 않음).
        if (showSelectionChrome)
          const Positioned(
            left: -4,
            top: -4,
            right: -4,
            bottom: -4,
            child: SnapshotDashedFrame(),
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
            onTap: editing
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
                            color: Color(0xFF111827),
                            shadows: [
                              Shadow(color: Colors.white, blurRadius: 6),
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
              color: Colors.white,
              disabledColor: Colors.white.withValues(alpha: .4),
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
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: .7),
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
              height: 48,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // 프레임 줄(높이 48, 모서리 10). 위치 계산은 기존과 같다.
                  Positioned(
                    left: trackStart,
                    width: usableWidth,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  // 선택 창: 2.5pt 흰 테두리.
                  Positioned(
                    left: startX,
                    width: selectedWidth < 2 ? 2 : selectedWidth,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2.5),
                        borderRadius: BorderRadius.circular(10),
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
    const iconColor = Color(0xFF111827);
    Widget iconSurface(Widget child) => SizedBox.square(
          dimension: 48,
          child: Material(
            color: Colors.white.withValues(alpha: .94),
            shape: const CircleBorder(),
            child: child,
          ),
        );
    Widget action({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) {
      return MotionPress(
        enabled: onPressed != null,
        pressedScale: .9,
        child: iconSurface(
          IconButton(
            tooltip: tooltip,
            padding: EdgeInsets.zero,
            onPressed: onPressed,
            icon: Icon(
              icon,
              size: iconSize,
              color: onPressed == null ? const Color(0xFF98A2B3) : iconColor,
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selectedLayer != null)
          action(
            icon: Icons.edit_outlined,
            tooltip: strings.editText,
            onPressed: () => unawaited(
              _beginTextLayerEditing(selectedLayer.id),
            ),
          ),
        if (_textLayers.length > 1)
          iconSurface(
            PopupMenuButton<String>(
              tooltip: strings.selectText,
              color: Colors.white,
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.layers_outlined,
                size: iconSize,
                color: iconColor,
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
        if (selectedLayer != null)
          iconSurface(
            PopupMenuButton<String>(
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              color: Colors.white,
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.more_horiz_rounded,
                size: iconSize,
                color: iconColor,
              ),
              onSelected: (value) {
                if (value == 'front') {
                  _bringSelectedTextLayerForward();
                } else if (value == 'color') {
                  setState(() {
                    final layer = _selectedTextLayer;
                    if (layer != null) layer.lightText = !layer.lightText;
                  });
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'color',
                  child: Text(selectedLayer.lightText
                      ? strings.darkText
                      : strings.lightText),
                ),
                if (!selectedIsFront)
                  PopupMenuItem<String>(
                    value: 'front',
                    child: Text(strings.bringForward),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// 글자 편집 패널: 밝게/어둡게 ↔ lightText, 작게/보통/크게 ↔ fontScale(세 값으로
  /// 설정만 하고 핀치 조절은 그대로 둔다).
  Widget _buildTextEditPanel(
    SnapshotStrings strings,
    _SnapshotTextLayer layer, {
    required double bottomPadding,
  }) {
    return TextFieldTapRegion(
      child: SnapshotTextEditPanel(
        strings: strings,
        lightText: layer.lightText,
        fontScale: layer.fontScale,
        showBringForward: _textLayers.length > 1,
        bottomPadding: bottomPadding,
        onLightChanged: (light) => setState(() => layer.lightText = light),
        onScaleChanged: (scale) => _setTextLayerFontScale(layer.id, scale),
        onBringForward: _bringSelectedTextLayerForward,
        onDone: () => unawaited(_finishOverlayEditing()),
      ),
    );
  }

  Widget _buildEditor(SnapshotStrings strings) {
    return LayoutBuilder(
      key: const ValueKey('snapshot_editor'),
      builder: (context, constraints) => _sourceFile == null
          ? _buildPicker(strings, constraints)
          : _buildMediaEditor(strings, constraints),
    );
  }

  /// 고르기: 위쪽 미리보기 + 탭 줄 + 4열 그리드 + [카메라][다음].
  Widget _buildPicker(SnapshotStrings strings, BoxConstraints constraints) {
    final padding = MediaQuery.paddingOf(context);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final previewHeight =
        (constraints.maxHeight * .5).clamp(0.0, 420.0).toDouble();
    final picked = _pickedAsset != null &&
            _recentPhotos.any((photo) => photo.id == _pickedAsset!.id)
        ? _pickedAsset
        : (_recentPhotos.isNotEmpty ? _recentPhotos.first : null);
    final busy = _loadingPhoto || _uploading;

    return ColoredBox(
      color: Colors.black,
      child: Column(
        children: [
          SizedBox(
            height: previewHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedSwitcher(
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
                  child: picked == null
                      ? const ColoredBox(
                          key: ValueKey('snapshot_picker_preview_empty'),
                          color: Colors.black,
                        )
                      : Image(
                          key: ValueKey('snapshot_picker_preview_${picked.id}'),
                          image: AssetEntityImageProvider(
                            picked,
                            isOriginal: false,
                            thumbnailSize: const ThumbnailSize.square(1080),
                          ),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) =>
                              const ColoredBox(color: Colors.black),
                        ),
                ),
                const _SnapshotEdgeFades(top: 110, bottom: 120),
                Positioned(
                  top: padding.top + 6,
                  left: 0,
                  right: 0,
                  child: SnapshotCreateTopBar(
                    icon: Icons.close_rounded,
                    label: null,
                    semanticLabel:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    lifetime: strings.shareLifetimeNote,
                    onBack: _uploading
                        ? null
                        : () async {
                            if (await _confirmExit() && mounted) {
                              Navigator.of(this.context).pop();
                            }
                          },
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SnapshotPickerTabRow(
                    strings: strings,
                    onPhotos:
                        busy ? null : () => _pickImage(ImageSource.gallery),
                    onVideos:
                        busy ? null : () => _pickVideo(ImageSource.gallery),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _RecentPhotoGallery(
              loading: _loadingGallery,
              selecting: _loadingPhoto,
              permissionDenied: _galleryPermissionDenied,
              permissionLimited: _galleryPermissionLimited,
              loadFailed: _galleryLoadFailed,
              photos: _recentPhotos,
              picked: picked,
              hasMore: _recentPhotos.length < _galleryTotalCount,
              loadingMore: _loadingMoreGallery,
              addPhotosLabel: strings.addPhotos,
              settingsLabel: strings.openSettings,
              permissionMessage: strings.galleryPermissionRequired,
              loadFailedMessage: strings.photoFailed,
              retryLabel: strings.retry,
              onAddPhotos: _selectMorePhotos,
              onRetry: _loadRecentPhotos,
              onOpenSettings: PhotoManager.openSetting,
              onLoadMore: _loadMoreRecentPhotos,
              onPhotoTap: (photo) => setState(() => _pickedAsset = photo),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, padding.bottom + 20),
            child: Row(
              children: [
                SnapshotCameraCircle(
                  label: strings.camera,
                  onTap: busy ? null : _chooseCameraMedia,
                  onLongPress:
                      busy ? null : () => _pickVideo(ImageSource.camera),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SnapshotPillButton(
                    key: const ValueKey('snapshot_picker_next'),
                    label: strings.next,
                    busy: _loadingPhoto,
                    onPressed: picked == null || _uploading
                        ? null
                        : () => _selectRecentPhoto(picked),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 편집: 미디어(위는 상태바 뒤까지, 아래는 하단 바 위 104에서 끝남) + 도구 줄.
  /// 합성 캔버스(_compositionKey 아래 AspectRatio)는 그대로 두고 둘레만 바꾼다.
  Widget _buildMediaEditor(
    SnapshotStrings strings,
    BoxConstraints constraints,
  ) {
    final padding = MediaQuery.paddingOf(context);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final editingLayer = _textLayerById(_editingTextLayerId);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final mediaBottom = 104 + padding.bottom;
    final isVideo = _mediaType == SnapshotMediaType.video &&
        _videoDuration > Duration.zero;
    final showTrim = isVideo && _trimOpen && editingLayer == null;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: mediaBottom,
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(16)),
            child: ColoredBox(
              color: const Color(0xFF111111),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: AspectRatio(
                        aspectRatio: _aspectRatio,
                        child: RepaintBoundary(
                          key: _compositionKey,
                          child: LayoutBuilder(
                            builder: (context, mediaConstraints) {
                              final width = mediaConstraints.maxWidth;
                              final height = mediaConstraints.maxHeight;
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _handlePhotoTap,
                                    child: _buildSourceMedia(),
                                  ),
                                  for (final layer in _textLayers)
                                    _buildTextLayer(
                                      layer,
                                      width,
                                      height,
                                      strings,
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  const _SnapshotEdgeFades(top: 110, bottom: 0),
                  if (_textLayers.isNotEmpty &&
                      _editingTextLayerId == null &&
                      !_composing)
                    Positioned(
                      top: padding.top + 56,
                      right: 12,
                      bottom: 12,
                      child: SingleChildScrollView(
                        child: _buildMediaTextActions(strings),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: padding.top + 6,
          left: 0,
          right: 0,
          child: SnapshotCreateTopBar(
            icon: Icons.chevron_left_rounded,
            label: strings.repick,
            lifetime: strings.shareLifetimeNote,
            onBack: _uploading || _composing
                ? null
                : () => unawaited(_returnToMediaSelection()),
          ),
        ),
        if (showTrim)
          Positioned(
            key: const ValueKey('snapshot_trim_panel'),
            left: 0,
            right: 0,
            bottom: mediaBottom,
            child: Container(
              color: Colors.black.withValues(alpha: .55),
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
              child: _buildVideoTrimEditor(strings),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedSwitcher(
            duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .25),
                end: Offset.zero,
              ).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: editingLayer != null
                ? Padding(
                    key: const ValueKey('snapshot_text_panel_slot'),
                    padding: EdgeInsets.only(bottom: keyboardInset),
                    child: _buildTextEditPanel(
                      strings,
                      editingLayer,
                      bottomPadding: keyboardInset > 0 ? 0 : padding.bottom,
                    ),
                  )
                : Padding(
                    key: const ValueKey('snapshot_tool_row_slot'),
                    padding:
                        EdgeInsets.fromLTRB(16, 12, 20, padding.bottom + 20),
                    child: SnapshotEditorToolRow(
                      strings: strings,
                      isVideo: isVideo,
                      trimOpen: _trimOpen,
                      busy: _composing,
                      onAddText: _textLayers.length < 5 && !_composing
                          ? _addTextLayer
                          : null,
                      onToggleTrim: () =>
                          setState(() => _trimOpen = !_trimOpen),
                      onNext: _composing
                          ? null
                          : () {
                              if (_trimOpen) setState(() => _trimOpen = false);
                              unawaited(_continueFromEditor());
                            },
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceMedia() {
    if (_mediaType == SnapshotMediaType.photo) {
      return Image.file(_sourceFile!, fit: BoxFit.contain);
    }
    final controller = _sourceVideoController;
    if (controller != null && controller.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      );
    }
    return const SizedBox.expand();
  }

  Widget _buildPreview(SnapshotStrings strings) {
    final file = _composedFile;
    Widget media = const ColoredBox(color: Colors.black);
    if (file != null) {
      // 합성 프레임 비율을 유지한 채 cover로 채운다. 영상 텍스트도 같은 틀 안에 둔다.
      media = FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: _aspectRatio * 1000,
          height: 1000,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_mediaType == SnapshotMediaType.photo)
                Image.file(file, fit: BoxFit.fill)
              else if (_previewVideoController != null &&
                  _previewVideoController!.value.isInitialized)
                VideoPlayer(_previewVideoController!),
              if (_mediaType == SnapshotMediaType.video)
                IgnorePointer(
                  child: SnapshotOverlayLayer(overlays: _snapshotOverlays()),
                ),
            ],
          ),
        ),
      );
    }
    // 그룹 멤버 표시는 이미 구독 중인 친구 목록만 쓴다(그룹마다 서버 조회 없음).
    final streamsReady = context.select<RelationshipProvider, bool>(
      (provider) => provider.relationshipStreamsReady,
    );
    final friendProfiles = context.select<RelationshipProvider, List<UserProfile>>(
      (provider) => provider.friends,
    );
    final List<ShareAudienceMember>? audienceFriends = streamsReady
        ? [
            for (final friend in friendProfiles)
              ShareAudienceMember(
                uid: friend.uid,
                name: friend.displayNameOrNickname,
                photoUrl: friend.photoURL ?? '',
              ),
          ]
        : null;
    return SnapshotShareView(
      key: const ValueKey('snapshot_preview'),
      friends: audienceFriends,
      media: media,
      visibility: _visibility,
      responseMode: _responseMode,
      categories: _friendCategories,
      selectedCategoryIds: _selectedCategoryIds,
      uploading: _uploading,
      uploadProgress: _uploadProgress,
      onBack: _uploading ? null : () => setState(() => _step = 0),
      onVisibilityChanged: (value) => setState(() => _visibility = value),
      onResponseModeChanged: (value) => setState(() => _responseMode = value),
      onToggleCategory: (id) {
        final next = List<String>.from(_selectedCategoryIds);
        if (next.contains(id)) {
          next.remove(id);
        } else {
          next.add(id);
        }
        setState(() => _selectedCategoryIds = next);
      },
      onShare: _upload,
    );
  }
}

class _SnapshotEdgeFades extends StatelessWidget {
  const _SnapshotEdgeFades({required this.top, required this.bottom});

  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (top > 0)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: top,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x8C000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          if (bottom > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: bottom,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xFF000000)],
                  ),
                ),
              ),
            ),
        ],
      ),
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
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 3)],
        ),
      ),
    );
  }
}

/// 고르기 그리드: 4열·간격 2·정사각, 한 장만 고른다. 페이징·권한 거부·
/// 불러오기 실패·제한 접근(사진 더 보기) 경로는 기존과 같다.
class _RecentPhotoGallery extends StatelessWidget {
  const _RecentPhotoGallery({
    required this.loading,
    required this.selecting,
    required this.permissionDenied,
    required this.permissionLimited,
    required this.loadFailed,
    required this.photos,
    required this.picked,
    required this.hasMore,
    required this.loadingMore,
    required this.addPhotosLabel,
    required this.settingsLabel,
    required this.permissionMessage,
    required this.loadFailedMessage,
    required this.retryLabel,
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
  final AssetEntity? picked;
  final bool hasMore;
  final bool loadingMore;
  final String addPhotosLabel;
  final String settingsLabel;
  final String permissionMessage;
  final String loadFailedMessage;
  final String retryLabel;
  final VoidCallback onAddPhotos;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback onLoadMore;
  final ValueChanged<AssetEntity> onPhotoTap;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }

    if (permissionDenied) {
      return SnapshotPickerNotice(
        message: permissionMessage,
        primaryLabel: settingsLabel,
        onPrimary: onOpenSettings,
        secondaryLabel: retryLabel,
        onSecondary: onRetry,
      );
    }

    if (loadFailed) {
      return SnapshotPickerNotice(
        message: loadFailedMessage,
        primaryLabel: retryLabel,
        onPrimary: onRetry,
      );
    }

    final leadingItemCount = permissionLimited ? 1 : 0;
    final cacheWidth =
        (MediaQuery.sizeOf(context).width / 4 * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(120, 360);
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
            key: const ValueKey('snapshot_picker_grid'),
            padding: const EdgeInsets.only(top: 2),
            physics: const BouncingScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: photos.length + leadingItemCount + (loadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (permissionLimited && index == 0) {
                return Semantics(
                  button: true,
                  label: addPhotosLabel,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: selecting ? null : onAddPhotos,
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: .08),
                      child: const Center(
                        child: Icon(
                          Icons.add_rounded,
                          size: 24,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              }
              final photoIndex = index - leadingItemCount;
              if (photoIndex >= photos.length) {
                return const Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                );
              }
              final photo = photos[photoIndex];
              final selected = picked?.id == photo.id;
              return Semantics(
                button: true,
                selected: selected,
                label: '${photoIndex + 1}',
                excludeSemantics: true,
                child: GestureDetector(
                  key: ValueKey<String>('snapshot_picker_cell_${photo.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: selecting ? null : () => onPhotoTap(photo),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: const Color(0xFF1A1A1A),
                        child: Image(
                          image: ResizeImage(
                            AssetEntityImageProvider(
                              photo,
                              isOriginal: false,
                              thumbnailSize: const ThumbnailSize.square(360),
                            ),
                            width: cacheWidth,
                          ),
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink(),
                        ),
                      ),
                      SnapshotGridSelection(selected: selected),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (selecting)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: .5),
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
