// lib/ui/widgets/fullscreen_image_viewer.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart' as permissions;

import '../../services/cache/app_image_cache_manager.dart';
import '../../services/snack_chat_media_cache_service.dart';

class FullscreenImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final List<String?>? storagePaths;
  final int initialIndex;
  final String? heroTag;

  const FullscreenImageViewer({
    Key? key,
    this.imageUrls = const <String>[],
    this.storagePaths,
    this.initialIndex = 0,
    this.heroTag,
  })  : assert(
          imageUrls.length > 0 ||
              (storagePaths != null && storagePaths.length > 0),
          'At least one image URL or storage path is required.',
        ),
        super(key: key);

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer>
    with SingleTickerProviderStateMixin {
  // Keep the save path aligned with the 15 MB Storage upload limit. Passing
  // larger typed data through a MethodChannel creates another full native
  // copy and can exhaust memory on low-end devices.
  static const int _maxImageBytes = 15 * 1024 * 1024;
  static const Duration _networkDownloadDeadline = Duration(seconds: 25);
  static const MethodChannel _mediaSaverChannel =
      MethodChannel('com.wefilling.app/media_saver');

  late final PageController _pageController;
  late final int _resolvedInitialIndex;
  late int _currentIndex;
  final Map<int, TransformationController> _transformationControllers = {};
  final Map<int, Offset> _doubleTapDownPositions = {};
  final Map<int, Future<Uint8List?>> _storageByteFutures = {};
  bool _isZoomed = false;
  bool _isSaving = false;
  late final AnimationController _animationController;
  late final CurvedAnimation _animationCurve;
  Animation<Matrix4>? _animation;
  TransformationController? _animatedTransformationController;
  int? _animatedIndex;
  int _animationGeneration = 0;

  int get _itemCount {
    final storageCount = widget.storagePaths?.length ?? 0;
    return widget.imageUrls.length > storageCount
        ? widget.imageUrls.length
        : storageCount;
  }

  @override
  void initState() {
    super.initState();
    _resolvedInitialIndex = _itemCount == 0
        ? 0
        : widget.initialIndex.clamp(0, _itemCount - 1).toInt();
    _currentIndex = _resolvedInitialIndex;
    _pageController = PageController(initialPage: _resolvedInitialIndex);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _animationCurve = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.addListener(_handleZoomAnimation);

    // 상태바 숨기기
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  String _imageUrlAt(int index) {
    if (index < 0 || index >= widget.imageUrls.length) return '';
    return widget.imageUrls[index].trim();
  }

  String _storagePathAt(int index) {
    final paths = widget.storagePaths;
    if (paths == null || index < 0 || index >= paths.length) return '';
    return (paths[index] ?? '').trim();
  }

  void _syncZoomStateForIndex(int index) {
    if (!mounted || index != _currentIndex) return;
    final controller = _transformationControllers[index];
    if (controller == null) return;
    final scale = controller.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.01;
    if (zoomed != _isZoomed) {
      setState(() {
        _isZoomed = zoomed;
      });
    }
  }

  @override
  void dispose() {
    _animationGeneration++;
    _animationController.removeListener(_handleZoomAnimation);
    _animationCurve.dispose();
    _pageController.dispose();
    _animationController.dispose();
    for (final c in _transformationControllers.values) {
      c.dispose();
    }

    // 상태바 복원
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onDoubleTapDown(int index, TapDownDetails details) {
    _doubleTapDownPositions[index] = details.localPosition;
  }

  Matrix4 _doubleTapZoomMatrix({
    required TransformationController controller,
    required Offset tapPosition,
    double scale = 2.0,
  }) {
    // tapPosition을 "장면 좌표(scene)"로 변환해서 그 지점을 중심으로 확대되도록 변환행렬 구성
    final scenePoint = controller.toScene(tapPosition);
    final dx = -scenePoint.dx * (scale - 1);
    final dy = -scenePoint.dy * (scale - 1);
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _handleZoomAnimation() {
    final animation = _animation;
    final controller = _animatedTransformationController;
    final index = _animatedIndex;
    if (animation == null || controller == null || index == null) return;
    controller.value = animation.value;
    _syncZoomStateForIndex(index);
  }

  Future<void> _onDoubleTap(int index) async {
    if (index != _currentIndex) return;
    final controller = _transformationControllers[index];
    if (controller == null) return;

    final current = controller.value;
    final currentScale = current.getMaxScaleOnAxis();
    final isCurrentlyZoomed = currentScale > 1.01;

    final tapPos = _doubleTapDownPositions[index] ??
        Offset(MediaQuery.of(context).size.width / 2,
            MediaQuery.of(context).size.height / 2);

    final endMatrix = isCurrentlyZoomed
        ? Matrix4.identity()
        : _doubleTapZoomMatrix(controller: controller, tapPosition: tapPos);

    final generation = ++_animationGeneration;
    _animationController.stop();
    _animationController.reset();
    _animatedTransformationController = controller;
    _animatedIndex = index;
    _animation = Matrix4Tween(begin: current, end: endMatrix).animate(
      _animationCurve,
    );

    try {
      await _animationController.forward().orCancel;
    } catch (_) {
      return;
    }
    if (!mounted || generation != _animationGeneration) return;
    controller.value = endMatrix;
    _syncZoomStateForIndex(index);
  }

  void _stopZoomAnimation() {
    if (!_animationController.isAnimating) return;
    _animationGeneration++;
    _animationController.stop();
    _animation = null;
    _animatedTransformationController = null;
    _animatedIndex = null;
  }

  String _extensionFromHint(String hint) {
    final uri = Uri.tryParse(hint);
    final path = uri?.path ?? hint;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    final extension = path.substring(dot + 1).toLowerCase();
    const supported = <String>{
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'heic',
      'heif',
      'tif',
      'tiff',
    };
    return supported.contains(extension) ? extension : 'jpg';
  }

  String _extensionFromBytes(Uint8List bytes, String hint) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'jpg';
    }
    if (bytes.length >= 6 &&
        String.fromCharCodes(bytes.sublist(0, 3)) == 'GIF') {
      return 'gif';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'webp';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
      final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
      if (const <String>{
        'heic',
        'heix',
        'hevc',
        'hevx',
        'heim',
        'heis',
        'mif1',
        'msf1',
      }.contains(brand)) {
        return 'heic';
      }
    }
    if (bytes.length >= 4 &&
        ((bytes[0] == 0x49 &&
                bytes[1] == 0x49 &&
                bytes[2] == 0x2a &&
                bytes[3] == 0x00) ||
            (bytes[0] == 0x4d &&
                bytes[1] == 0x4d &&
                bytes[2] == 0x00 &&
                bytes[3] == 0x2a))) {
      return 'tiff';
    }
    return _extensionFromHint(hint);
  }

  bool _hasSupportedImageSignature(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return true;
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return true;
    }
    if (bytes.length >= 6 &&
        String.fromCharCodes(bytes.sublist(0, 3)) == 'GIF') {
      return true;
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return true;
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
      final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
      if (const <String>{
        'heic',
        'heix',
        'hevc',
        'hevx',
        'heim',
        'heis',
        'mif1',
        'msf1',
      }.contains(brand)) {
        return true;
      }
    }
    return bytes.length >= 4 &&
        ((bytes[0] == 0x49 &&
                bytes[1] == 0x49 &&
                bytes[2] == 0x2a &&
                bytes[3] == 0x00) ||
            (bytes[0] == 0x4d &&
                bytes[1] == 0x4d &&
                bytes[2] == 0x00 &&
                bytes[3] == 0x2a));
  }

  Future<Uint8List?> _readStorageBytes(int index) async {
    final storagePath = _storagePathAt(index);
    if (storagePath.isEmpty) return null;
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    if (viewerId == null || viewerId.isEmpty) return null;
    try {
      final cached = await SnackChatMediaCacheService.instance.read(
        userId: viewerId,
        storagePath: storagePath,
      );
      if (cached != null && cached.isNotEmpty) return cached;
      final bytes = await FirebaseStorage.instance
          .ref(storagePath)
          .getData(_maxImageBytes)
          .timeout(const Duration(seconds: 15));
      if (bytes == null || bytes.isEmpty) return null;
      await SnackChatMediaCacheService.instance.write(
        userId: viewerId,
        storagePath: storagePath,
        bytes: bytes,
      );
      return bytes;
    } catch (_) {
      // path-only 신규 이미지가 아니라면 아래 URL 호환 경로로 복구한다.
      return null;
    }
  }

  Future<Uint8List?> _storageBytes(int index) {
    if (!_storageByteFutures.containsKey(index) &&
        _storageByteFutures.length >= 4) {
      _storageByteFutures.remove(_storageByteFutures.keys.first);
    }
    return _storageByteFutures.putIfAbsent(
      index,
      () async {
        final data = await _readStorageBytes(index);
        if (data == null || data.isEmpty) _storageByteFutures.remove(index);
        return data;
      },
    );
  }

  void _retryStorageImage(int index) {
    _storageByteFutures.remove(index);
    if (mounted) setState(() {});
  }

  Future<Uint8List> _bytesForSave(int index) async {
    final storagePath = _storagePathAt(index);
    if (storagePath.isNotEmpty) {
      var bytes = await _storageBytes(index);
      // 최초 표시 시 일시적으로 실패했더라도 저장 탭에서는 한 번 재시도한다.
      bytes ??= await _readStorageBytes(index);
      if (bytes != null && bytes.isNotEmpty) return bytes;
    }

    final imageUrl = _imageUrlAt(index);
    if (imageUrl.isEmpty) {
      throw StateError('No accessible image source.');
    }
    final cache = AppImageCacheManager.instance;
    final cached = await cache.getFileFromCache(imageUrl);
    if (cached != null && await cached.file.exists()) {
      final length = await cached.file.length();
      if (length <= 0 || length > _maxImageBytes) {
        throw StateError('Invalid cached image size.');
      }
      return cached.file.readAsBytes();
    }
    return _downloadNetworkBytes(imageUrl);
  }

  Future<Uint8List> _downloadNetworkBytes(String imageUrl) async {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw StateError('Unsupported image URL.');
    }
    final client = http.Client();
    final elapsed = Stopwatch()..start();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = true
        ..maxRedirects = 5;
      final response =
          await client.send(request).timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Image request failed (${response.statusCode}).');
      }
      final contentType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (contentType != null &&
          contentType.isNotEmpty &&
          !contentType.startsWith('image/')) {
        throw StateError('The response is not an image.');
      }
      final declaredLength = response.contentLength;
      if (declaredLength != null && declaredLength > _maxImageBytes) {
        throw StateError('Image is too large.');
      }

      Future<Uint8List> collectBody() async {
        final builder = BytesBuilder(copy: false);
        var received = 0;
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 8))) {
          received += chunk.length;
          if (received > _maxImageBytes) {
            throw StateError('Image is too large.');
          }
          builder.add(chunk);
        }
        return builder.takeBytes();
      }

      final remaining = _networkDownloadDeadline - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        throw StateError('Image download timed out.');
      }
      // Stream.timeout only bounds silence between chunks. This absolute
      // deadline also terminates slow-drip responses that never go idle.
      final bytes = await collectBody().timeout(remaining);
      if (bytes.isEmpty) throw StateError('Image is empty.');
      if (!_hasSupportedImageSignature(bytes)) {
        throw StateError('The downloaded file is not a supported image.');
      }
      await AppImageCacheManager.instance.putFile(
        imageUrl,
        bytes,
        key: imageUrl,
        maxAge: const Duration(days: 30),
        fileExtension: _extensionFromBytes(bytes, imageUrl),
      );
      return bytes;
    } finally {
      client.close();
    }
  }

  bool get _isKorean =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ko';

  void _showSaveMessage(String message, {bool showSettings = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: showSettings
              ? SnackBarAction(
                  label: _isKorean ? '설정' : 'Settings',
                  onPressed: () {
                    permissions.openAppSettings();
                  },
                )
              : null,
        ),
      );
  }

  Future<void> _saveCurrentImage() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    var permissionDenied = false;
    try {
      final index = _currentIndex;
      final bytes = await _bytesForSave(index);
      if (bytes.length > _maxImageBytes ||
          !_hasSupportedImageSignature(bytes)) {
        throw StateError('The selected file is not a supported image.');
      }
      final sourceHint = _storagePathAt(index).isNotEmpty
          ? _storagePathAt(index)
          : _imageUrlAt(index);
      final extension = _extensionFromBytes(bytes, sourceHint);
      final filename =
          'wefilling_${DateTime.now().millisecondsSinceEpoch}.$extension';
      if (Platform.isIOS || Platform.isAndroid) {
        // Native save paths use PHAssetCreationRequest on iOS and MediaStore on
        // modern Android without broad media read access. Android 9 and below
        // use the system Create Document flow instead of storage permission.
        await _mediaSaverChannel.invokeMethod<void>('saveImage', {
          'bytes': bytes,
          'filename': filename,
        }).timeout(const Duration(seconds: 30));
      } else {
        throw UnsupportedError('Image saving is supported on Android and iOS.');
      }
      _showSaveMessage(
        _isKorean ? '사진 앱에 이미지를 저장했습니다.' : 'Image saved to Photos.',
      );
    } on PlatformException catch (error) {
      permissionDenied = permissionDenied ||
          error.code == 'photo-permission-denied' ||
          error.code == 'permission-denied';
      _showSaveMessage(
        permissionDenied
            ? (_isKorean
                ? '사진 저장 권한이 필요합니다.'
                : 'Photo permission is required to save this image.')
            : (_isKorean
                ? '이미지를 저장하지 못했습니다. 잠시 후 다시 시도해 주세요.'
                : 'Could not save the image. Please try again.'),
        showSettings: permissionDenied,
      );
    } catch (_) {
      _showSaveMessage(
        _isKorean
            ? '이미지를 저장하지 못했습니다. 잠시 후 다시 시도해 주세요.'
            : 'Could not save the image. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _imageError() {
    return const Center(
      child: Icon(
        Icons.broken_image_rounded,
        color: Colors.white54,
        size: 64,
      ),
    );
  }

  Widget _networkImage(String imageUrl) {
    if (imageUrl.isEmpty) return _imageError();
    return CachedNetworkImage(
      imageUrl: imageUrl,
      cacheManager: AppImageCacheManager.instance,
      fit: BoxFit.contain,
      placeholder: (_, __) => const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2,
        ),
      ),
      errorWidget: (_, __, ___) => _imageError(),
    );
  }

  Widget _imageAt(int index) {
    final storagePath = _storagePathAt(index);
    final imageUrl = _imageUrlAt(index);
    if (storagePath.isEmpty) return _networkImage(imageUrl);
    return FutureBuilder<Uint8List?>(
      future: _storageBytes(index),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(
            bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _networkImage(imageUrl),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          );
        }
        if (imageUrl.isNotEmpty) return _networkImage(imageUrl);
        return Center(
          child: IconButton(
            onPressed: () => _retryStorageImage(index),
            tooltip: _isKorean ? '이미지 다시 불러오기' : 'Retry image',
            color: Colors.white70,
            iconSize: 32,
            icon: const Icon(Icons.refresh_rounded),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 이미지 PageView
          PageView.builder(
            controller: _pageController,
            physics: _isZoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: _itemCount,
            onPageChanged: (index) {
              _stopZoomAnimation();
              setState(() {
                _currentIndex = index;
                _isZoomed = false; // 페이지 전환 시 기본값으로 리셋
              });
              // 새 페이지가 이미 확대된 상태(예: 복원되지 않은 컨트롤러)라면 동기화
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _syncZoomStateForIndex(index);
              });
            },
            itemBuilder: (context, index) {
              final transformationController =
                  _transformationControllers.putIfAbsent(
                index,
                () => TransformationController(),
              );

              return InteractiveViewer(
                transformationController: transformationController,
                panEnabled: true,
                scaleEnabled: true,
                minScale: 0.8,
                maxScale: 3.0,
                onInteractionStart: (_) {
                  _stopZoomAnimation();
                  _syncZoomStateForIndex(index);
                },
                onInteractionUpdate: (_) => _syncZoomStateForIndex(index),
                onInteractionEnd: (_) => _syncZoomStateForIndex(index),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTapDown: (d) => _onDoubleTapDown(index, d),
                  onDoubleTap: () => _onDoubleTap(index),
                  child: Center(
                    child: Hero(
                      // heroTag가 주어졌다면 "처음 열린 이미지"에서만 그대로 사용해
                      // 기존 호출부(post/review 등)의 Hero 매칭을 유지한다.
                      // 나머지 페이지는 고유 태그를 사용해 중복 Hero 태그로 인한 크래시를 방지한다.
                      tag: (widget.heroTag != null &&
                              index == _resolvedInitialIndex)
                          ? widget.heroTag!
                          : '${widget.heroTag ?? 'image'}_$index',
                      child: _imageAt(index),
                    ),
                  ),
                ),
              );
            },
          ),

          // 닫기 버튼 (왼쪽 상단)
          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),

          // 페이지 인디케이터 (이미지가 2장 이상일 때만) - 오른쪽 상단
          if (_itemCount > 1)
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / $_itemCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

          // 시스템 내비게이션/홈 인디케이터 위 안전 영역에 저장 버튼 배치
          if (_itemCount > 0)
            Positioned(
              right: 16,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: Semantics(
                  button: true,
                  label: _isKorean ? '이미지 저장' : 'Save image',
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: IconButton(
                      onPressed: _isSaving ? null : _saveCurrentImage,
                      tooltip: _isKorean ? '이미지 저장' : 'Save image',
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.download_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// 전체화면 이미지 뷰어 표시 헬퍼 함수
Future<void> showFullscreenImageViewer(
  BuildContext context, {
  List<String> imageUrls = const <String>[],
  List<String?>? storagePaths,
  int initialIndex = 0,
  String? heroTag,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => FullscreenImageViewer(
        imageUrls: imageUrls,
        storagePaths: storagePaths,
        initialIndex: initialIndex,
        heroTag: heroTag,
      ),
    ),
  );
}
