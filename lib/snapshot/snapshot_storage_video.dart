import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/snapshot.dart';
import '../services/snapshot_service.dart';
import '../utils/logger.dart';
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
  File? _file;
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
    final previous = _controller;
    final previousFile = _file;
    _controller = null;
    _file = null;
    await previous?.dispose();
    if (previousFile != null && await previousFile.exists()) {
      await previousFile.delete().catchError((_) => previousFile);
    }
    if (mounted) setState(() => _error = null);
    File? loadedFile;
    try {
      final File file = await SnapshotService.instance.loadVideoFile(
        widget.snapshot,
      );
      loadedFile = file;
      if (!mounted || generation != _generation) {
        if (await file.exists()) await file.delete().catchError((_) => file);
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
      _file = file;
      setState(() {});
      widget.onReady();
      _syncPlayback();
    } catch (error, stackTrace) {
      if (loadedFile != null && await loadedFile.exists()) {
        await loadedFile.delete().catchError((_) => loadedFile!);
      }
      Logger.error(
        '스낵 영상 재생 준비 실패 (snapshotId=${widget.snapshot.id})',
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
    final file = _file;
    unawaited(() async {
      await controller?.dispose();
      if (file != null && await file.exists()) {
        await file.delete().catchError((_) => file);
      }
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return Center(
        child: TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          label: Text(
            SnapshotStrings.of(context).videoPlaybackFailed,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
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
