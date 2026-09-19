import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/snapshot.dart';
import '../services/snapshot_service.dart';
import '../utils/logger.dart';
import 'snapshot_storage_image.dart';
import 'snapshot_strings.dart';

class SnapshotStorageVideo extends StatefulWidget {
  const SnapshotStorageVideo({
    super.key,
    required this.snapshot,
    required this.playing,
    required this.onReady,
    required this.onFirstFrame,
    required this.onPlaybackStable,
    required this.showPlayButton,
    required this.onPlayRequested,
  });

  final SnapshotItem snapshot;
  final bool playing;
  final VoidCallback onReady;
  final VoidCallback onFirstFrame;
  final VoidCallback onPlaybackStable;
  final bool showPlayButton;
  final VoidCallback onPlayRequested;

  @override
  State<SnapshotStorageVideo> createState() => _SnapshotStorageVideoState();
}

class _SnapshotStorageVideoState extends State<SnapshotStorageVideo>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  File? _retainedFile;
  Object? _error;
  bool _appActive = true;
  bool _firstFrameVisible = false;
  bool _wasBuffering = false;
  bool _cacheHit = false;
  bool _playActionPending = false;
  int _generation = 0;
  Stopwatch? _loadStopwatch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant SnapshotStorageVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.id != widget.snapshot.id) {
      unawaited(
        SnapshotService.instance.cancelVideoLoad(oldWidget.snapshot.id),
      );
      unawaited(_load());
    } else if (oldWidget.playing != widget.playing) {
      _syncPlayback();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive) {
      unawaited(SnapshotService.instance.cancelVideoPreloads());
    }
    _syncPlayback();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final snapshot = widget.snapshot;
    final previous = _controller;
    final previousFile = _retainedFile;
    _controller = null;
    _retainedFile = null;
    previous?.removeListener(_handleControllerValue);
    await previous?.dispose();
    if (previousFile != null) {
      await SnapshotService.instance.releaseVideoFile(previousFile);
    }
    if (!mounted || generation != _generation) return;
    _loadStopwatch = Stopwatch()..start();
    setState(() {
      _error = null;
      _firstFrameVisible = false;
      _wasBuffering = false;
      _cacheHit = false;
      _playActionPending = false;
    });
    try {
      if (Logger.isVerboseEnabled) {
        Logger.log('스낵 영상 재생 요청 시작 (snapshotId=${snapshot.id})');
      }
      final source =
          await SnapshotService.instance.prepareVideoPlayback(snapshot);
      if (!mounted || generation != _generation) {
        return;
      }
      _cacheHit = source.cacheHit;
      var retainedFile = source.file;
      var controller = _controllerForSource(source);
      if (retainedFile != null) {
        SnapshotService.instance.retainVideoFile(retainedFile);
      }
      final initializationStopwatch = Stopwatch()..start();
      try {
        await controller.initialize().timeout(const Duration(seconds: 20));
      } catch (initializationError) {
        final category = _initializationFailureCategory(initializationError);
        final shouldUseFileFallback = source.networkUri != null &&
            category == _VideoInitializationFailure.compatibility;
        final shouldRefreshPlaybackCache = source.file != null &&
            !source.cacheKey.startsWith('archive::') &&
            category == _VideoInitializationFailure.compatibility;
        if (Logger.isVerboseEnabled) {
          Logger.warning(
            '스낵 영상 초기화 실패 '
            '(snapshotId=${snapshot.id}, category=${category.name}, '
            'source=${source.networkUri != null ? 'network' : 'file'}, '
            'errorType=${initializationError.runtimeType}, '
            'platformCode=${initializationError is PlatformException ? initializationError.code : 'none'}, '
            'fallback=${shouldUseFileFallback || shouldRefreshPlaybackCache}, '
            'elapsedMs=${initializationStopwatch.elapsedMilliseconds})',
          );
        }
        await controller.dispose();
        if (retainedFile != null) {
          await SnapshotService.instance.releaseVideoFile(retainedFile);
          retainedFile = null;
        }
        if ((!shouldUseFileFallback && !shouldRefreshPlaybackCache) ||
            !mounted ||
            generation != _generation) {
          rethrow;
        }
        if (shouldRefreshPlaybackCache) {
          await SnapshotService.instance.evictVideoPlaybackCache(snapshot.id);
          if (!mounted || generation != _generation) return;
        }
        // 일부 기기/코덱이 인증 헤더 기반 Range 재생을 지원하지 못할 때만
        // 또는 일반 시청 캐시가 손상됐을 때만 Firebase Storage SDK 전체
        // 파일 경로를 한 번 사용한다. 작성자 영구 보관 파일은 지우지 않는다.
        final file = await SnapshotService.instance.loadVideoFile(snapshot);
        if (!mounted || generation != _generation) return;
        retainedFile = file;
        SnapshotService.instance.retainVideoFile(file);
        controller = VideoPlayerController.file(file);
        final fallbackStopwatch = Stopwatch()..start();
        try {
          await controller.initialize().timeout(const Duration(seconds: 30));
        } catch (fallbackError, fallbackStackTrace) {
          final fallbackCategory =
              _initializationFailureCategory(fallbackError);
          Logger.error(
            '스낵 영상 파일 대체 경로 초기화 실패 '
            '(snapshotId=${snapshot.id}, category=${fallbackCategory.name}, '
            'errorType=${fallbackError.runtimeType}, '
            'platformCode=${fallbackError is PlatformException ? fallbackError.code : 'none'}, '
            'elapsedMs=${fallbackStopwatch.elapsedMilliseconds})',
            fallbackError,
            fallbackStackTrace,
          );
          await controller.dispose();
          await SnapshotService.instance.releaseVideoFile(file);
          rethrow;
        }
        if (Logger.isVerboseEnabled) {
          Logger.log(
            '스낵 영상 파일 대체 경로 준비 '
            '(snapshotId=${snapshot.id}, '
            'elapsedMs=${fallbackStopwatch.elapsedMilliseconds})',
          );
        }
        _cacheHit = true;
      }
      if (!mounted || generation != _generation) {
        await controller.dispose();
        if (retainedFile != null) {
          await SnapshotService.instance.releaseVideoFile(retainedFile);
        }
        return;
      }
      await controller.setLooping(true);
      controller.addListener(_handleControllerValue);
      _controller = controller;
      _retainedFile = retainedFile;
      setState(() {});
      if (Logger.isVerboseEnabled) {
        Logger.log(
          '스낵 영상 플레이어 준비 '
          '(snapshotId=${snapshot.id}, '
          'elapsedMs=${_loadStopwatch?.elapsedMilliseconds ?? 0}, '
          'initializeMs=${initializationStopwatch.elapsedMilliseconds}, '
          'cacheHit=$_cacheHit)',
        );
      }
      widget.onReady();
      _syncPlayback();
    } catch (error, stackTrace) {
      Logger.error(
        '스낵 영상 재생 준비 실패 (snapshotId=${snapshot.id})',
        error,
        stackTrace,
      );
      if (mounted && generation == _generation) {
        setState(() => _error = error);
      }
    }
  }

  VideoPlayerController _controllerForSource(
    SnapshotVideoPlaybackSource source,
  ) {
    final file = source.file;
    if (file != null) return VideoPlayerController.file(file);
    final uri = source.networkUri;
    if (uri == null) throw StateError('snapshot-video-playback-source-missing');
    return VideoPlayerController.networkUrl(
      uri,
      httpHeaders: source.httpHeaders,
    );
  }

  void _handleControllerValue() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;
    if (value.isBuffering != _wasBuffering) {
      final wasBuffering = _wasBuffering;
      _wasBuffering = value.isBuffering;
      if (_wasBuffering) {
        unawaited(SnapshotService.instance.cancelVideoPreloads());
      } else if (wasBuffering && value.isInitialized) {
        if (Logger.isVerboseEnabled) {
          Logger.log(
            '스낵 영상 버퍼링 회복 '
            '(snapshotId=${widget.snapshot.id}, positionMs=${value.position.inMilliseconds})',
          );
        }
        widget.onPlaybackStable();
      }
    }
    if (_firstFrameVisible ||
        !value.isInitialized ||
        value.isBuffering ||
        value.position <= Duration.zero) {
      return;
    }
    _firstFrameVisible = true;
    if (Logger.isVerboseEnabled) {
      Logger.log(
        '스낵 영상 첫 프레임 '
        '(snapshotId=${widget.snapshot.id}, '
        'elapsedMs=${_loadStopwatch?.elapsedMilliseconds ?? 0}, '
        'cacheHit=$_cacheHit, signal=position-estimate)',
      );
    }
    setState(() {});
    widget.onFirstFrame();
  }

  void _syncPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.playing && _appActive) {
      unawaited(controller.play());
    } else {
      unawaited(controller.pause());
    }
  }

  Future<void> _handlePlayRequested() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _playActionPending) {
      return;
    }
    _playActionPending = true;
    widget.onPlayRequested();
    try {
      await controller.play();
    } catch (error, stackTrace) {
      Logger.error(
        '스낵 영상 재생 재개 실패 (snapshotId=${widget.snapshot.id})',
        error,
        stackTrace,
      );
      if (mounted) setState(() => _error = error);
    } finally {
      _playActionPending = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    final controller = _controller;
    final retainedFile = _retainedFile;
    controller?.removeListener(_handleControllerValue);
    unawaited(controller?.dispose());
    if (retainedFile != null) {
      unawaited(SnapshotService.instance.releaseVideoFile(retainedFile));
    }
    unawaited(
      SnapshotService.instance.cancelVideoLoad(widget.snapshot.id),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final thumbnailDecodeWidth = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(320, 2160);
    final thumbnail = SnapshotStorageImage(
      snapshot: widget.snapshot,
      fit: BoxFit.cover,
      placeholderColor: Colors.black,
      errorBackgroundColor: Colors.black,
      showLoadingIndicator: false,
      fadeInDuration: const Duration(milliseconds: 120),
      decodeWidth: thumbnailDecodeWidth,
    );
    if (_error != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          thumbnail,
          ColoredBox(color: Colors.black.withValues(alpha: .28)),
          Center(
            child: TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              label: Text(
                SnapshotStrings.of(context).videoPlaybackFailed,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          thumbnail,
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .34),
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        thumbnail,
        AnimatedOpacity(
          opacity: _firstFrameVisible ? 1 : 0,
          duration: const Duration(milliseconds: 100),
          child: VideoPlayer(controller),
        ),
        if (!_firstFrameVisible)
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .34),
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        if (widget.showPlayButton)
          Center(
            child: Semantics(
              button: true,
              label: SnapshotStrings.of(context).playVideo,
              child: Material(
                color: Colors.black.withValues(alpha: .52),
                shape: const CircleBorder(),
                child: InkResponse(
                  onTap: _handlePlayRequested,
                  radius: 32,
                  child: const SizedBox.square(
                    dimension: 56,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum _VideoInitializationFailure {
  access,
  expiredOrCancelled,
  timeout,
  network,
  compatibility,
}

_VideoInitializationFailure _initializationFailureCategory(Object error) {
  if (error is TimeoutException) {
    return _VideoInitializationFailure.timeout;
  }
  final message = error is PlatformException
      ? '${error.code} ${error.message ?? ''}'.toLowerCase()
      : error.toString().toLowerCase();
  if (message.contains('401') ||
      message.contains('403') ||
      message.contains('unauthorized') ||
      message.contains('permission') ||
      message.contains('forbidden') ||
      message.contains('app check')) {
    return _VideoInitializationFailure.access;
  }
  if (message.contains('expired') ||
      message.contains('cancel') ||
      message.contains('404') ||
      message.contains('410') ||
      message.contains('not found') ||
      message.contains('account-changed')) {
    return _VideoInitializationFailure.expiredOrCancelled;
  }
  if (message.contains('network') ||
      message.contains('unknownhost') ||
      message.contains('connection') ||
      message.contains('socket') ||
      message.contains('offline') ||
      message.contains('internet')) {
    return _VideoInitializationFailure.network;
  }
  return _VideoInitializationFailure.compatibility;
}

class SnapshotOverlayLayer extends StatelessWidget {
  const SnapshotOverlayLayer({
    super.key,
    required this.overlays,
  });

  final List<SnapshotOverlay> overlays;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final overlay in overlays.take(5))
              Positioned(
                left: overlay.x * width,
                top: overlay.y * height,
                child: FractionalTranslation(
                  translation: const Offset(-.5, -.5),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width * .82),
                    child: Text(
                      overlay.text,
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const <String>['NotoSansKR'],
                        fontSize:
                            (width * .066).clamp(19, 34) * overlay.fontScale,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        color: overlay.lightText
                            ? Colors.white
                            : const Color(0xFF111111),
                        shadows: overlay.lightText
                            ? const <Shadow>[
                                Shadow(
                                  color: Color(0x99000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 1),
                                ),
                              ]
                            : const <Shadow>[
                                Shadow(
                                  color: Color(0x77FFFFFF),
                                  blurRadius: 8,
                                  offset: Offset(0, 1),
                                ),
                              ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
