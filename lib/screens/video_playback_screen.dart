// lib/screens/video_playback_screen.dart
// 채팅(스낵챗·DM) 영상과 포스트 영상의 전체 화면 재생.
// 파일은 AppVideoCacheManager로 기기당 한 번만 내려받고, 소리는 사용자가
// 직접 연 화면이므로 켠 상태로 시작한다.
import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/cache/app_video_cache_manager.dart';
import '../utils/logger.dart';

class VideoPlaybackScreen extends StatefulWidget {
  const VideoPlaybackScreen({
    super.key,
    this.localFile,
    this.reference,
    this.url,
    this.title,
  }) : assert(localFile != null || reference != null || url != null);

  final File? localFile;
  final Reference? reference;
  final String? url;
  final String? title;

  static Future<void> open(
    BuildContext context, {
    File? localFile,
    Reference? reference,
    String? url,
    String? title,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => VideoPlaybackScreen(
          localFile: localFile,
          reference: reference,
          url: url,
          title: title,
        ),
      ),
    );
  }

  @override
  State<VideoPlaybackScreen> createState() => _VideoPlaybackScreenState();
}

class _VideoPlaybackScreenState extends State<VideoPlaybackScreen> {
  VideoPlayerController? _controller;
  File? _retained;
  Object? _error;
  bool _muted = false;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      File file;
      final local = widget.localFile;
      if (local != null && await local.exists()) {
        file = local;
      } else if (widget.reference != null) {
        file = await AppVideoCacheManager.instance
            .fetchReference(widget.reference!);
        AppVideoCacheManager.instance.retain(file);
        _retained = file;
      } else {
        file = await AppVideoCacheManager.instance.fetchUrl(widget.url!);
        AppVideoCacheManager.instance.retain(file);
        _retained = file;
      }
      final controller = VideoPlayerController.file(file);
      await controller.initialize().timeout(const Duration(seconds: 30));
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(false);
      await controller.setVolume(_muted ? 0 : 1);
      controller.addListener(_onValue);
      setState(() => _controller = controller);
      await controller.play();
      _scheduleHide();
    } catch (error, stackTrace) {
      Logger.error('영상 재생 준비 실패', error, stackTrace);
      if (mounted) setState(() => _error = error);
    }
  }

  void _onValue() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      if (controller.value.position >= controller.value.duration) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
    }
    if (!mounted) return;
    setState(() => _showControls = true);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    final controller = _controller;
    controller?.removeListener(_onValue);
    unawaited(controller?.dispose());
    final retained = _retained;
    if (retained != null) AppVideoCacheManager.instance.release(retained);
    super.dispose();
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: _error != null
                  ? const Icon(Icons.error_outline_rounded,
                      color: Colors.white70, size: 40)
                  : ready
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() => _showControls = !_showControls);
                            if (_showControls) _scheduleHide();
                          },
                          child: AspectRatio(
                            aspectRatio: controller.value.aspectRatio <= 0
                                ? 1
                                : controller.value.aspectRatio,
                            child: VideoPlayer(controller),
                          ),
                        )
                      : const CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
            ),
            if (_showControls || !ready)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip:
                          MaterialLocalizations.of(context).closeButtonTooltip,
                    ),
                    Expanded(
                      child: Text(
                        widget.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ),
                    if (ready)
                      IconButton(
                        icon: Icon(
                          _muted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          setState(() => _muted = !_muted);
                          unawaited(controller.setVolume(_muted ? 0 : 1));
                        },
                      ),
                  ],
                ),
              ),
            if (ready && _showControls)
              Center(
                child: IconButton(
                  iconSize: 64,
                  icon: Icon(
                    controller.value.isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  onPressed: _togglePlay,
                ),
              ),
            if (ready && _showControls)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Colors.white,
                        bufferedColor: Colors.white38,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_format(controller.value.position),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        Text(_format(controller.value.duration),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
