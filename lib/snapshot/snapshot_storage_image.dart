import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/snapshot.dart';
import '../services/snapshot_service.dart';
import '../utils/logger.dart';

class SnapshotStorageImage extends StatefulWidget {
  const SnapshotStorageImage({
    super.key,
    required this.snapshot,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderColor = const Color(0xFFF1F2F4),
    this.errorBackgroundColor = const Color(0xFFF1F2F4),
    this.showLoadingIndicator = true,
    this.fadeInDuration = Duration.zero,
    this.onImageReady,
  });

  final SnapshotItem snapshot;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Color placeholderColor;
  final Color errorBackgroundColor;
  final bool showLoadingIndicator;
  final Duration fadeInDuration;
  final VoidCallback? onImageReady;

  @override
  State<SnapshotStorageImage> createState() => _SnapshotStorageImageState();
}

class _SnapshotStorageImageState extends State<SnapshotStorageImage> {
  late Future<Uint8List> _future;
  Timer? _retryTimer;
  int _retryCount = 0;
  String? _readyNotificationId;

  @override
  void initState() {
    super.initState();
    _future = SnapshotService.instance.loadImageBytes(widget.snapshot);
  }

  @override
  void didUpdateWidget(covariant SnapshotStorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.id != widget.snapshot.id ||
        oldWidget.snapshot.storagePath != widget.snapshot.storagePath) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryCount = 0;
      _readyNotificationId = null;
      _future = SnapshotService.instance.loadImageBytes(widget.snapshot);
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _scheduleRetry(Object error) {
    if (_retryTimer != null || _retryCount >= 1) return;
    final snapshotId = widget.snapshot.id;
    final delays = <Duration>[const Duration(seconds: 2)];
    final delay = delays[_retryCount];
    _retryCount += 1;
    Logger.error('스낵 이미지 조회 제한 재시도 ($_retryCount/1): $snapshotId', error);
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!mounted || widget.snapshot.id != snapshotId) return;
      setState(() {
        _future = SnapshotService.instance.loadImageBytes(widget.snapshot);
      });
    });
  }

  void _notifyImageReady() {
    final callback = widget.onImageReady;
    final snapshotId = widget.snapshot.id;
    if (callback == null || _readyNotificationId == snapshotId) return;
    _readyNotificationId = snapshotId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.snapshot.id != snapshotId) return;
      callback();
    });
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      key: ValueKey<String>('snapshot-image-loading-${widget.snapshot.id}'),
      color: widget.placeholderColor,
      child: Center(
        child: widget.showLoadingIndicator
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: Colors.grey.shade500,
                ),
              )
            : null,
      ),
    );

    Widget image = FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        late final Widget content;
        if (snapshot.hasData) {
          _notifyImageReady();
          content = Image.memory(
            snapshot.data!,
            key: ValueKey<String>('snapshot-image-ready-${widget.snapshot.id}'),
            fit: widget.fit,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, error, stackTrace) {
              Logger.error(
                '스낵 이미지 렌더링 실패 '
                '(contentId=${widget.snapshot.id}, '
                'currentUserId=${FirebaseAuth.instance.currentUser?.uid})',
                error,
                stackTrace,
              );
              return _ImageError(
                key: ValueKey<String>(
                  'snapshot-image-render-error-${widget.snapshot.id}',
                ),
                backgroundColor: widget.errorBackgroundColor,
              );
            },
          );
        } else if (snapshot.hasError) {
          _scheduleRetry(snapshot.error!);
          content = _ImageError(
            key: ValueKey<String>(
              'snapshot-image-load-error-${widget.snapshot.id}',
            ),
            backgroundColor: widget.errorBackgroundColor,
          );
        } else {
          content = placeholder;
        }

        if (widget.fadeInDuration == Duration.zero) return content;
        return AnimatedSwitcher(
          duration: widget.fadeInDuration,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
          child: content,
        );
      },
    );

    if (widget.borderRadius != null) {
      image = ClipRRect(borderRadius: widget.borderRadius!, child: image);
    }
    return image;
  }
}

class _ImageError extends StatelessWidget {
  const _ImageError({super.key, required this.backgroundColor});

  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Color(0xFF98A2B3),
        ),
      ),
    );
  }
}
