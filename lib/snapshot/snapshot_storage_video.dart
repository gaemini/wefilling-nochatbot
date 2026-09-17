import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
  });

  final SnapshotItem snapshot;
  final bool playing;
  final VoidCallback onReady;

  @override
  State<SnapshotStorageVideo> createState() => _SnapshotStorageVideoState();
}

class _SnapshotStorageVideoState extends State<SnapshotStorageVideo>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  Object? _error;
  bool _appActive = true;
  int _generation = 0;

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
      unawaited(_load());
    } else if (oldWidget.playing != widget.playing) {
      _syncPlayback();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncPlayback();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final snapshot = widget.snapshot;
    final previous = _controller;
    _controller = null;
    await previous?.dispose();
    if (!mounted || generation != _generation) return;
    setState(() => _error = null);
    try {
      final File file = await SnapshotService.instance.loadVideoFile(
        snapshot,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      final controller = VideoPlayerController.file(file);
      await controller.initialize().timeout(const Duration(seconds: 30));
      if (!mounted || generation != _generation) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(false);
      _controller = controller;
      setState(() {});
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

  void _syncPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.playing && _appActive) {
      if (controller.value.position >= controller.value.duration) {
        unawaited(
            controller.seekTo(Duration.zero).then((_) => controller.play()));
      } else {
        unawaited(controller.play());
      }
    } else {
      unawaited(controller.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    final controller = _controller;
    unawaited(controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final thumbnail = SnapshotStorageImage(
      snapshot: widget.snapshot,
      fit: BoxFit.cover,
      placeholderColor: Colors.black,
      errorBackgroundColor: Colors.black,
      showLoadingIndicator: false,
      fadeInDuration: const Duration(milliseconds: 120),
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
    return VideoPlayer(controller);
  }
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
