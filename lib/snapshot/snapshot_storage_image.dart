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
  });

  final SnapshotItem snapshot;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  State<SnapshotStorageImage> createState() => _SnapshotStorageImageState();
}

class _SnapshotStorageImageState extends State<SnapshotStorageImage> {
  late Future<Uint8List> _future;
  Timer? _retryTimer;
  int _retryCount = 0;

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

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: const Color(0xFFF1F2F4),
      child: Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(
            strokeWidth: 1.8,
            color: Colors.grey.shade500,
          ),
        ),
      ),
    );

    Widget image = FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
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
              return const _ImageError();
            },
          );
        }
        if (snapshot.hasError) {
          _scheduleRetry(snapshot.error!);
          return const _ImageError();
        }
        return placeholder;
      },
    );

    if (widget.borderRadius != null) {
      image = ClipRRect(borderRadius: widget.borderRadius!, child: image);
    }
    return image;
  }
}

class _ImageError extends StatelessWidget {
  const _ImageError();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF1F2F4),
      child: Center(
        child:
            Icon(Icons.image_not_supported_outlined, color: Color(0xFF98A2B3)),
      ),
    );
  }
}
