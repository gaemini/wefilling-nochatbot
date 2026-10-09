// lib/ui/widgets/feed_video_player.dart
// 피드·상세·채팅 공용 인라인 영상 플레이어.
//
// - 카드가 화면의 60% 이상 보이면 자동 재생, 30% 아래로 내려가면 일시정지.
// - 처음에는 무음이며, 탭하거나 스피커 아이콘을 누르면 소리가 켜진다.
//   한 번 켠 소리는 같은 세션의 다른 영상에도 이어진다(Instagram과 동일).
// - 동시에 하나의 영상만 재생한다(다른 카드가 재생을 시작하면 이전 카드는 멈춤).
// - 영상 파일은 AppVideoCacheManager로 기기당 한 번만 내려받는다. 내려받는
//   동안은 썸네일을 보여준다.
// - 무음 자동 재생이 사용자의 음악을 멈추지 않도록 mixWithOthers로 연다
//   (iOS 오디오 세션 MixWithOthers, Android 오디오 포커스 미요청).
// - 화면에서 완전히 사라지면 컨트롤러를 해제한다. Android 하드웨어 디코더와
//   iOS AVPlayer는 동시에 열 수 있는 수가 적어, 스크롤로 지나간 카드가 붙잡고
//   있으면 저사양 기기에서 다음 영상 초기화가 실패한다. 파일은 캐시에 남는다.
import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../services/cache/app_image_cache_manager.dart';
import '../../services/cache/app_video_cache_manager.dart';
import '../../utils/logger.dart';

/// 세션 전체의 무음 상태. 기본 무음.
class FeedVideoAudio {
  FeedVideoAudio._();
  static final ValueNotifier<bool> muted = ValueNotifier<bool>(true);
}

/// 동시에 하나의 인라인 영상만 재생되게 조정한다.
class _FeedVideoCoordinator {
  _FeedVideoCoordinator._();
  static final _FeedVideoCoordinator instance = _FeedVideoCoordinator._();

  _FeedVideoPlayerState? _active;

  void requestPlay(_FeedVideoPlayerState player) {
    final previous = _active;
    if (previous != null && previous != player && previous.mounted) {
      previous._pause();
    }
    _active = player;
  }

  void release(_FeedVideoPlayerState player) {
    if (_active == player) _active = null;
  }
}

class FeedVideoPlayer extends StatefulWidget {
  const FeedVideoPlayer({
    super.key,
    required this.videoKey,
    this.videoUrl,
    this.reference,
    this.thumbnailUrl,
    this.thumbnailFile,
    this.aspectRatio = 1.0,
    this.autoplay = true,
    this.loop = true,
    this.borderRadius,
    this.onOpen,
  }) : assert(videoUrl != null || reference != null);

  /// 캐시/조정에 쓰는 안정적인 키(포스트 영상 id 등).
  final String videoKey;

  /// 공개 다운로드 URL(포스트).
  final String? videoUrl;

  /// 규칙으로 보호된 Storage 객체(스낵챗·DM). SDK 인증 다운로드.
  final Reference? reference;
  final String? thumbnailUrl;
  final File? thumbnailFile;
  final double aspectRatio;
  final bool autoplay;
  final bool loop;
  final BorderRadius? borderRadius;

  /// 확대 보기 등 외부 동작. null이면 탭이 음소거 토글만 한다.
  final VoidCallback? onOpen;

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer>
    with WidgetsBindingObserver {
  static const double _playThreshold = 0.6;
  static const double _pauseThreshold = 0.3;
  static const Duration _playDebounce = Duration(milliseconds: 500);

  VideoPlayerController? _controller;
  File? _retainedFile;
  bool _loading = false;
  bool _wantsPlay = false;
  bool _appActive = true;
  bool _firstFrame = false;
  Object? _error;
  Timer? _playTimer;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FeedVideoAudio.muted.addListener(_applyVolume);
  }

  @override
  void didUpdateWidget(covariant FeedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoKey != widget.videoKey ||
        oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.reference?.fullPath != widget.reference?.fullPath) {
      _resetPlayback();
      if (_wantsPlay) _schedulePlay();
    }
  }

  /// 진행 중인 로드를 무효화하고 컨트롤러를 해제한다. 진행 중이던 다운로드는
  /// 캐시 관리자에서 계속되어 다음 로드가 그 파일을 쓴다.
  void _resetPlayback() {
    _generation++;
    _loading = false;
    _firstFrame = false;
    _error = null;
    _FeedVideoCoordinator.instance.release(this);
    unawaited(_disposeController());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncPlayback();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FeedVideoAudio.muted.removeListener(_applyVolume);
    _playTimer?.cancel();
    _FeedVideoCoordinator.instance.release(this);
    _generation++;
    unawaited(_disposeController());
    super.dispose();
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    final file = _retainedFile;
    _controller = null;
    _retainedFile = null;
    controller?.removeListener(_handleValue);
    await controller?.dispose();
    if (file != null) AppVideoCacheManager.instance.release(file);
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (!mounted) return;
    final fraction = info.visibleFraction;
    if (fraction >= _playThreshold) {
      if (!_wantsPlay) {
        _wantsPlay = true;
        _schedulePlay();
      }
    } else if (fraction <= _pauseThreshold && _wantsPlay) {
      _wantsPlay = false;
      _playTimer?.cancel();
      _pause();
    }
    if (fraction <= 0 && (_controller != null || _loading)) {
      setState(_resetPlayback);
    }
  }

  void _schedulePlay() {
    if (!widget.autoplay) return;
    _playTimer?.cancel();
    // 빠른 스크롤로 스쳐 지나가는 카드는 다운로드하지 않는다.
    _playTimer = Timer(_playDebounce, () {
      if (!mounted || !_wantsPlay) return;
      if (_controller == null) {
        unawaited(_load());
      } else {
        _syncPlayback();
      }
    });
  }

  Future<void> _load() async {
    if (_loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final File file;
      final url = widget.videoUrl;
      if (url != null) {
        file = await AppVideoCacheManager.instance.fetchUrl(url);
      } else {
        file = await AppVideoCacheManager.instance.fetchReference(
          widget.reference!,
        );
      }
      if (!mounted || generation != _generation) return;
      AppVideoCacheManager.instance.retain(file);
      final controller = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      try {
        await controller.initialize().timeout(const Duration(seconds: 20));
      } catch (error) {
        await controller.dispose();
        AppVideoCacheManager.instance.release(file);
        rethrow;
      }
      if (!mounted || generation != _generation) {
        await controller.dispose();
        AppVideoCacheManager.instance.release(file);
        return;
      }
      await controller.setLooping(widget.loop);
      await controller.setVolume(FeedVideoAudio.muted.value ? 0 : 1);
      controller.addListener(_handleValue);
      _controller = controller;
      _retainedFile = file;
      setState(() => _loading = false);
      _syncPlayback();
    } catch (error, stackTrace) {
      Logger.error('인라인 영상 준비 실패 (${widget.videoKey})', error, stackTrace);
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  void _handleValue() {
    final controller = _controller;
    if (controller == null || !mounted || _firstFrame) return;
    final value = controller.value;
    if (value.isInitialized && !value.isBuffering && value.position > Duration.zero) {
      setState(() => _firstFrame = true);
    }
  }

  void _syncPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_wantsPlay && _appActive && widget.autoplay) {
      _FeedVideoCoordinator.instance.requestPlay(this);
      unawaited(controller.play());
    } else {
      unawaited(controller.pause());
    }
  }

  void _pause() {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      unawaited(controller.pause());
    }
  }

  void _applyVolume() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    unawaited(controller.setVolume(FeedVideoAudio.muted.value ? 0 : 1));
  }

  void _toggleMute() {
    FeedVideoAudio.muted.value = !FeedVideoAudio.muted.value;
    final controller = _controller;
    if (controller != null && controller.value.isInitialized && !controller.value.isPlaying && _wantsPlay) {
      unawaited(controller.play());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final showVideo = controller != null && controller.value.isInitialized && _firstFrame;
    final radius = widget.borderRadius ?? BorderRadius.zero;

    Widget thumbnail;
    if (widget.thumbnailFile != null) {
      thumbnail = Image.file(widget.thumbnailFile!, fit: BoxFit.cover);
    } else if ((widget.thumbnailUrl ?? '').isNotEmpty) {
      thumbnail = CachedNetworkImage(
        imageUrl: widget.thumbnailUrl!,
        cacheManager: AppImageCacheManager.instance,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 120),
        errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF111827)),
      );
    } else {
      thumbnail = const ColoredBox(color: Color(0xFF111827));
    }

    return VisibilityDetector(
      key: Key('feed-video-${widget.videoKey}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: ClipRRect(
        borderRadius: radius,
        child: AspectRatio(
          aspectRatio: widget.aspectRatio <= 0 ? 1.0 : widget.aspectRatio,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpen ?? _toggleMute,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (showVideo)
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  )
                else
                  thumbnail,
                if (_loading)
                  const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (_error != null && !_loading)
                  Center(
                    child: IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                      onPressed: () {
                        _error = null;
                        _wantsPlay = true;
                        unawaited(_load());
                      },
                    ),
                  ),
                if (!showVideo && !_loading && _error == null)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: FeedVideoAudio.muted,
                    builder: (context, muted, _) {
                      return Semantics(
                        button: true,
                        label: muted ? 'unmute' : 'mute',
                        child: GestureDetector(
                          onTap: _toggleMute,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              color: Color(0x99000000),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      );
                    },
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
