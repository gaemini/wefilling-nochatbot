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
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../models/friend_category.dart';
import '../models/snapshot.dart';
import '../models/user_profile.dart';
import '../repositories/users_repository.dart';
import '../services/friend_category_service.dart';
import '../services/snapshot_service.dart';
import '../snapshot/snapshot_strings.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/widgets/group_audience_preview.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';

class CreateSnapshotScreen extends StatefulWidget {
  const CreateSnapshotScreen({super.key, this.onCreated});

  final VoidCallback? onCreated;

  @override
  State<CreateSnapshotScreen> createState() => _CreateSnapshotScreenState();
}

class _CreateSnapshotScreenState extends State<CreateSnapshotScreen>
    with WidgetsBindingObserver {
  static const int _galleryPageSize = 100;
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
  final TextEditingController _overlayController = TextEditingController();
  final FocusNode _overlayFocusNode = FocusNode();

  StreamSubscription<List<FriendCategory>>? _categoriesSubscription;

  File? _sourceFile;
  File? _composedFile;
  int _sourceWidth = 0;
  int _sourceHeight = 0;
  String _overlayText = '';
  Offset _overlayPosition = const Offset(.5, .5);
  double _overlayFontScale = 1;
  double _gestureStartFontScale = 1;
  bool _editingOverlay = false;
  Completer<void>? _overlayCommitCompleter;
  bool _lightText = true;
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
    _overlayFocusNode.addListener(_syncOverlayFocus);
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
    _overlayController.dispose();
    _overlayFocusNode
      ..removeListener(_syncOverlayFocus)
      ..dispose();
    _deleteTemporaryComposition();
    super.dispose();
  }

  void _syncOverlayFocus() {
    if (!mounted) return;
    if (_overlayFocusNode.hasFocus) {
      if (!_editingOverlay) setState(() => _editingOverlay = true);
      return;
    }
    unawaited(_scheduleOverlayCommit());
  }

  Future<void> _scheduleOverlayCommit() {
    final pending = _overlayCommitCompleter;
    if (pending != null) return pending.future;
    final completer = Completer<void>();
    _overlayCommitCompleter = completer;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!identical(_overlayCommitCompleter, completer)) return;
      try {
        if (!mounted || _overlayFocusNode.hasFocus) return;
        final text = _overlayController.text;
        var nextScale = _overlayFontScale;
        var nextPosition = _overlayPosition;
        final renderObject = _compositionKey.currentContext?.findRenderObject();
        if (text.isNotEmpty &&
            renderObject is RenderBox &&
            renderObject.attached &&
            renderObject.hasSize) {
          nextScale = _fitOverlayFontScale(
            nextScale,
            renderObject.size.width,
            renderObject.size.height,
          );
          nextPosition = _boundedOverlayPosition(
            nextPosition,
            renderObject.size.width,
            renderObject.size.height,
            fontScale: nextScale,
          );
        }
        if (_editingOverlay ||
            _overlayText != text ||
            _overlayFontScale != nextScale ||
            _overlayPosition != nextPosition) {
          setState(() {
            _overlayText = text;
            _overlayFontScale = nextScale;
            _overlayPosition = nextPosition;
            _editingOverlay = false;
          });
        }
      } catch (error, stackTrace) {
        // A layout/measurement failure must not leave the next button waiting
        // forever. Preserve the user's exact controller text as the fallback;
        // capture can still proceed with the last safe transform values.
        Logger.error('스낵 텍스트 오버레이 확정 실패', error, stackTrace);
        if (mounted && !_overlayFocusNode.hasFocus) {
          final text = _overlayController.text;
          if (_editingOverlay || _overlayText != text) {
            setState(() {
              _overlayText = text;
              _editingOverlay = false;
            });
          }
        }
      } finally {
        if (identical(_overlayCommitCompleter, completer)) {
          _overlayCommitCompleter = null;
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
    if (!mounted) return;
    setState(() {
      _sourceFile = file;
      _sourceWidth = width;
      _sourceHeight = height;
      _step = 0;
    });
  }

  void _focusOverlayText() {
    if (!_editingOverlay) setState(() => _editingOverlay = true);
    if (!_overlayFocusNode.hasFocus) _overlayFocusNode.requestFocus();
  }

  Future<void> _finishOverlayEditing() {
    if (_overlayFocusNode.hasFocus) _overlayFocusNode.unfocus();
    return _scheduleOverlayCommit();
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
    double imageWidth, {
    double? fontScale,
  }) {
    return TextStyle(
      fontFamily: 'Pretendard',
      fontSize: (imageWidth * .066).clamp(19, 34).toDouble() *
          (fontScale ?? _overlayFontScale),
      fontWeight: FontWeight.w800,
      height: 1.18,
      color: _lightText ? Colors.white : const Color(0xFF111111),
      shadows: _lightText
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
    double imageWidth, {
    required double fontScale,
  }) {
    final text = _overlayController.text;
    if (text.isEmpty || imageWidth <= 0) return Size.zero;
    final maxTextWidth = imageWidth * .82;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: _overlayTextStyle(imageWidth, fontScale: fontScale),
      ),
      textAlign: TextAlign.center,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      textWidthBasis: TextWidthBasis.longestLine,
      maxLines: 3,
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
    double requested,
    double imageWidth,
    double imageHeight,
  ) {
    var candidate = requested.clamp(.35, 1.75).toDouble();
    if (_overlayController.text.isEmpty ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      return candidate;
    }
    for (var iteration = 0; iteration < 5; iteration++) {
      final bounds = _overlayPaintBounds(
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
      final fitted = (candidate * fitRatio * .98).clamp(.35, candidate);
      if ((candidate - fitted).abs() < .001) break;
      candidate = fitted.toDouble();
    }
    return candidate;
  }

  Offset _boundedOverlayPosition(
    Offset requested,
    double imageWidth,
    double imageHeight, {
    required double fontScale,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0) return const Offset(.5, .5);
    if (_overlayController.text.isEmpty) {
      return Offset(
        requested.dx.clamp(0.0, 1.0).toDouble(),
        requested.dy.clamp(0.0, 1.0).toDouble(),
      );
    }
    final bounds = _overlayPaintBounds(
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

  void _startOverlayTransform(ScaleStartDetails _) {
    _gestureStartFontScale = _overlayFontScale;
  }

  void _setOverlayFontScale(double requested) {
    var nextScale = requested.clamp(.35, 1.75).toDouble();
    var nextPosition = _overlayPosition;
    final renderObject = _compositionKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize) {
      nextScale = _fitOverlayFontScale(
        nextScale,
        renderObject.size.width,
        renderObject.size.height,
      );
      nextPosition = _boundedOverlayPosition(
        nextPosition,
        renderObject.size.width,
        renderObject.size.height,
        fontScale: nextScale,
      );
    }
    setState(() {
      _overlayFontScale = nextScale;
      _overlayPosition = nextPosition;
    });
  }

  void _updateOverlayTransform(
    ScaleUpdateDetails details,
    double imageWidth,
    double imageHeight,
  ) {
    if (_overlayText.isEmpty || imageWidth <= 0 || imageHeight <= 0) return;
    final nextScale = _fitOverlayFontScale(
      _gestureStartFontScale * details.scale,
      imageWidth,
      imageHeight,
    );
    final nextPosition = _boundedOverlayPosition(
      Offset(
        _overlayPosition.dx + details.focalPointDelta.dx / imageWidth,
        _overlayPosition.dy + details.focalPointDelta.dy / imageHeight,
      ),
      imageWidth,
      imageHeight,
      fontScale: nextScale,
    );
    setState(() {
      _overlayPosition = nextPosition;
      _overlayFontScale = nextScale;
    });
  }

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
    } catch (_) {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: strings.photoFailed,
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
    try {
      await _service.createSnapshot(
        composedImage: file,
        visibility: _visibility,
        visibleToCategoryIds: _visibility == SnapshotVisibility.category
            ? _selectedCategoryIds
            : const <String>[],
        overlay: SnapshotOverlay(
          text: _overlayText,
          x: _overlayPosition.dx,
          y: _overlayPosition.dy,
          lightText: _lightText,
          fontScale: _overlayFontScale,
        ),
        aspectRatio: _aspectRatio,
        sourceWidth: _sourceWidth,
        sourceHeight: _sourceHeight,
        onProgress: (progress) {
          if (mounted) setState(() => _uploadProgress = progress);
        },
      );
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
    _composedFile = null;
    if (file != null && await file.exists()) {
      try {
        await file.delete();
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
                    fontFamily: 'Pretendard',
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
        if (_step == 1) {
          setState(() => _step = 0);
          return;
        }
        final shouldExit = await _confirmExit();
        if (shouldExit && mounted) Navigator.of(this.context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          toolbarHeight: context.rh(56, min: 54, max: 60),
          automaticallyImplyLeading: false,
          leadingWidth: 48,
          leading: IconButton(
            onPressed: _uploading
                ? null
                : () async {
                    if (_step == 1) {
                      setState(() => _step = 0);
                    } else if (await _confirmExit() && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
            icon: Icon(
              _step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded,
              color: const Color(0xFF111827),
              size: context.ri(22).clamp(21, 24).toDouble(),
            ),
            tooltip: _step == 0
                ? MaterialLocalizations.of(context).closeButtonTooltip
                : MaterialLocalizations.of(context).backButtonTooltip,
          ),
          title: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: Text(
              strings.createSnapshot,
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
            if (_step == 0)
              SizedBox.square(
                dimension: 48,
                child: IconButton(
                  onPressed: _sourceFile == null || _composing
                      ? null
                      : _composeAndContinue,
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

  Widget _buildEditor(SnapshotStrings strings) {
    return LayoutBuilder(
      key: const ValueKey('snapshot_editor'),
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 360 ? 6.0 : 10.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(horizontal, 4, horizontal, 6),
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
                        addPhotosLabel: strings.addPhotos,
                        settingsLabel: strings.settings,
                        permissionMessage: strings.galleryPermissionRequired,
                        loadFailedMessage: strings.photoFailed,
                        retryLabel: strings.retry,
                        onCamera: () => _pickImage(ImageSource.camera),
                        onGallery: () => _pickImage(ImageSource.gallery),
                        onAddPhotos: _selectMorePhotos,
                        onRetry: _loadRecentPhotos,
                        onOpenSettings: PhotoManager.openSetting,
                        onLoadMore: _loadMoreRecentPhotos,
                        onPhotoTap: _selectRecentPhoto,
                      )
                    : Center(
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
                                    final textStyle = _overlayTextStyle(width);
                                    return Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: _editingOverlay
                                              ? () => unawaited(
                                                    _finishOverlayEditing(),
                                                  )
                                              : _focusOverlayText,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              Image.file(
                                                _sourceFile!,
                                                fit: BoxFit.cover,
                                              ),
                                              if (_overlayText.isEmpty &&
                                                  !_editingOverlay &&
                                                  !_composing)
                                                Center(
                                                  child: Text(
                                                    strings.tapPhotoToType,
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontFamily: 'Pretendard',
                                                      fontSize: (width * .043)
                                                          .clamp(13, 17)
                                                          .toDouble(),
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Colors.white,
                                                      shadows: const [
                                                        Shadow(
                                                          color:
                                                              Color(0xB3000000),
                                                          blurRadius: 8,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Positioned(
                                          left: _overlayPosition.dx * width,
                                          top: _overlayPosition.dy * height,
                                          child: FractionalTranslation(
                                            translation: const Offset(-.5, -.5),
                                            child: GestureDetector(
                                              behavior:
                                                  HitTestBehavior.translucent,
                                              onTap: _editingOverlay
                                                  ? null
                                                  : _focusOverlayText,
                                              onScaleStart: _editingOverlay
                                                  ? null
                                                  : _startOverlayTransform,
                                              onScaleUpdate: _editingOverlay
                                                  ? null
                                                  : (details) =>
                                                      _updateOverlayTransform(
                                                        details,
                                                        width,
                                                        height,
                                                      ),
                                              child: IgnorePointer(
                                                ignoring: !_editingOverlay,
                                                child: SizedBox(
                                                  width: width * .82,
                                                  child: TextField(
                                                    key: const ValueKey(
                                                      'snapshot_overlay_text_field',
                                                    ),
                                                    controller:
                                                        _overlayController,
                                                    focusNode:
                                                        _overlayFocusNode,
                                                    readOnly: false,
                                                    showCursor: true,
                                                    minLines: 1,
                                                    maxLines: 3,
                                                    maxLength: 60,
                                                    maxLengthEnforcement:
                                                        MaxLengthEnforcement
                                                            .truncateAfterCompositionEnds,
                                                    keyboardType:
                                                        TextInputType.multiline,
                                                    textInputAction:
                                                        TextInputAction.newline,
                                                    enableInteractiveSelection:
                                                        true,
                                                    scrollPhysics:
                                                        const NeverScrollableScrollPhysics(),
                                                    onTapOutside: (_) =>
                                                        unawaited(
                                                      _finishOverlayEditing(),
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    cursorColor: _lightText
                                                        ? Colors.white
                                                        : const Color(
                                                            0xFF111111),
                                                    decoration: InputDecoration(
                                                      hintText: _editingOverlay
                                                          ? strings.textHint
                                                          : null,
                                                      hintStyle:
                                                          textStyle.copyWith(
                                                        color: Colors.white70,
                                                      ),
                                                      border: InputBorder.none,
                                                      enabledBorder:
                                                          InputBorder.none,
                                                      focusedBorder:
                                                          InputBorder.none,
                                                      isDense: true,
                                                      counterText: '',
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                    ),
                                                    style: textStyle,
                                                  ),
                                                ),
                                              ),
                                            ),
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
              if (_sourceFile != null) ...[
                const SizedBox(height: 4),
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          await _finishOverlayEditing();
                          await _deleteTemporaryComposition();
                          if (!mounted) return;
                          setState(() {
                            _sourceFile = null;
                            _sourceWidth = 0;
                            _sourceHeight = 0;
                          });
                          unawaited(
                            _loadRecentPhotos(requestPermission: false),
                          );
                        },
                        icon: const Icon(Icons.image_outlined, size: 19),
                        label: Text(strings.choosePhoto),
                      ),
                      if (_overlayText.isNotEmpty)
                        IconButton(
                          tooltip: _lightText ? 'Dark text' : 'Light text',
                          onPressed: () =>
                              setState(() => _lightText = !_lightText),
                          icon: Icon(
                            _lightText
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                            size: 20,
                          ),
                        ),
                      if (_overlayText.isNotEmpty)
                        IconButton(
                          tooltip: strings.deleteText,
                          onPressed: () {
                            _overlayController.clear();
                            unawaited(_finishOverlayEditing());
                          },
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 20),
                        ),
                    ],
                  ),
                ),
                if (_overlayText.isNotEmpty)
                  SizedBox(
                    height: 42,
                    child: Row(
                      children: [
                        Icon(
                          Icons.text_decrease_rounded,
                          size: context.ri(19).clamp(18, 21).toDouble(),
                          color: const Color(0xFF667085),
                        ),
                        Expanded(
                          child: Slider(
                            value: _overlayFontScale,
                            min: .35,
                            max: 1.75,
                            divisions: 14,
                            onChanged: _setOverlayFontScale,
                          ),
                        ),
                        Icon(
                          Icons.text_increase_rounded,
                          size: context.ri(22).clamp(21, 24).toDouble(),
                          color: const Color(0xFF344054),
                        ),
                      ],
                    ),
                  ),
              ],
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
                      child: Image.file(file, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            SizedBox(height: context.rs(22).clamp(18, 24).toDouble()),
            Text(
              strings.visibilityPrompt,
              style: TextStyle(
                fontFamily: 'Pretendard',
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
            fontFamily: 'Pretendard',
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
            fontFamily: 'Pretendard',
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
                fontFamily: 'Pretendard',
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
    required this.addPhotosLabel,
    required this.settingsLabel,
    required this.permissionMessage,
    required this.loadFailedMessage,
    required this.retryLabel,
    required this.onCamera,
    required this.onGallery,
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
  final String addPhotosLabel;
  final String settingsLabel;
  final String permissionMessage;
  final String loadFailedMessage;
  final String retryLabel;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
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
              const SizedBox(height: 20),
              Text(
                permissionMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
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
              const SizedBox(height: 20),
              Text(
                loadFailedMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
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

    final leadingItemCount = permissionLimited ? 2 : 1;
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
              if (permissionLimited && index == 1) {
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
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
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
                          fontFamily: 'Pretendard',
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
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
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
                        fontFamily: 'Pretendard',
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
