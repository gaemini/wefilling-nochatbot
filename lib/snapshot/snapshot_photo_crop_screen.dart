// lib/snapshot/snapshot_photo_crop_screen.dart
// 스낵 편집의 사진 자르기: 비율(원본·1:1·4:5·9:16)을 고르고 사진을 끌거나
// 두 손가락으로 키워 틀 안을 맞춘 뒤 [완료]하면 자른 사진 파일을 돌려준다.
// 원본 파일은 바꾸지 않는다.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'snapshot_share_view.dart';
import 'snapshot_strings.dart';

/// 자를 비율. null이면 원본 비율.
enum SnapshotCropAspect {
  original(null),
  square(1),
  portrait(4 / 5),
  story(9 / 16);

  const SnapshotCropAspect(this.ratio);
  final double? ratio;
}

/// 틀(frame) 안에서 보이는 영역을 원본 픽셀 좌표로 바꾼다.
/// [baseScale]은 확대 1일 때 원본 1픽셀이 화면에서 차지하는 크기(cover 배율),
/// [translation]·[zoom]은 InteractiveViewer 변환 값이다.
@visibleForTesting
Rect snapshotCropSourceRect({
  required Size imageSize,
  required Size frameSize,
  required double baseScale,
  required Offset translation,
  required double zoom,
}) {
  final scale = baseScale * zoom;
  final left = (-translation.dx / scale).clamp(0.0, imageSize.width);
  final top = (-translation.dy / scale).clamp(0.0, imageSize.height);
  final width = math.min(frameSize.width / scale, imageSize.width - left);
  final height = math.min(frameSize.height / scale, imageSize.height - top);
  return Rect.fromLTWH(left, top, width, height);
}

class SnapshotPhotoCropScreen extends StatefulWidget {
  const SnapshotPhotoCropScreen({super.key, required this.file});

  final File file;

  @override
  State<SnapshotPhotoCropScreen> createState() =>
      _SnapshotPhotoCropScreenState();
}

class _SnapshotPhotoCropScreenState extends State<SnapshotPhotoCropScreen> {
  final TransformationController _transform = TransformationController();
  ui.Image? _image;
  bool _failed = false;
  bool _saving = false;
  SnapshotCropAspect _aspect = SnapshotCropAspect.original;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final bytes = await widget.file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    _image?.dispose();
    super.dispose();
  }

  Size _frameFor(Size available, Size image) {
    final ratio = _aspect.ratio ?? image.width / image.height;
    var width = available.width;
    var height = width / ratio;
    if (height > available.height) {
      height = available.height;
      width = height * ratio;
    }
    return Size(width, height);
  }

  void _setAspect(SnapshotCropAspect aspect) {
    if (aspect == _aspect) return;
    setState(() {
      _aspect = aspect;
      _transform.value = Matrix4.identity();
    });
  }

  Future<void> _done(Size frame, double baseScale) async {
    final image = _image;
    if (image == null || _saving) return;
    setState(() => _saving = true);
    try {
      final matrix = _transform.value;
      final zoom = matrix.getMaxScaleOnAxis();
      final translation = Offset(matrix.storage[12], matrix.storage[13]);
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final src = snapshotCropSourceRect(
        imageSize: imageSize,
        frameSize: frame,
        baseScale: baseScale,
        translation: translation,
        zoom: zoom,
      );
      // 결과는 긴 변 2400px 이하(기존 사진 선택과 같은 상한).
      final longest = math.max(src.width, src.height);
      final outScale = longest > 2400 ? 2400 / longest : 1.0;
      final outW = math.max(1, (src.width * outScale).round());
      final outH = math.max(1, (src.height * outScale).round());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        src,
        Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final cropped = await recorder.endRecording().toImage(outW, outH);
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      cropped.dispose();
      if (data == null) throw StateError('crop-encode-failed');
      final dir = await getTemporaryDirectory();
      final out = File(
        '${dir.path}/snack_crop_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (!mounted) return;
      Navigator.of(context).pop(out);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SnapshotStrings.of(context).photoFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    final image = _image;
    return Scaffold(
      backgroundColor: Colors.black,
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.25,
        child: Column(
          children: [
            SizedBox(height: padding.top),
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  TextButton(
                    key: const ValueKey('snapshot_crop_cancel'),
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      MaterialLocalizations.of(context).cancelButtonLabel,
                      style: shareTextStyle(context, ShareTextSpec.back),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      strings.cropTool,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: shareTextStyle(
                        context,
                        const ShareTextSpec(16, 22, FontWeight.w600, 1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 72),
                ],
              ),
            ),
            Expanded(
              child: image == null
                  ? Center(
                      child: _failed
                          ? Text(
                              strings.photoFailed,
                              style: shareTextStyle(context, ShareTextSpec.hint),
                            )
                          : const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final imageSize = Size(
                          image.width.toDouble(),
                          image.height.toDouble(),
                        );
                        final frame = _frameFor(
                          Size(
                            constraints.maxWidth - 32,
                            constraints.maxHeight - 32,
                          ),
                          imageSize,
                        );
                        final baseScale = math.max(
                          frame.width / imageSize.width,
                          frame.height / imageSize.height,
                        );
                        return Column(
                          children: [
                            Expanded(
                              child: Center(
                                child: Container(
                                  key: const ValueKey('snapshot_crop_frame'),
                                  width: frame.width,
                                  height: frame.height,
                                  foregroundDecoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: ClipRect(
                                    child: InteractiveViewer(
                                      key: ValueKey<SnapshotCropAspect>(_aspect),
                                      transformationController: _transform,
                                      constrained: false,
                                      minScale: 1,
                                      maxScale: 5,
                                      boundaryMargin: EdgeInsets.zero,
                                      child: SizedBox(
                                        width: imageSize.width * baseScale,
                                        height: imageSize.height * baseScale,
                                        child: RawImage(
                                          image: image,
                                          fit: BoxFit.fill,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _buildControls(strings, frame, baseScale),
                          ],
                        );
                      },
                    ),
            ),
            SizedBox(height: padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(
    SnapshotStrings strings,
    Size frame,
    double baseScale,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ShareChoiceGroup<SnapshotCropAspect>(
              keyPrefix: 'snapshot_crop_aspect',
              value: _aspect,
              options: [
                (SnapshotCropAspect.original, strings.cropOriginal),
                (SnapshotCropAspect.square, '1:1'),
                (SnapshotCropAspect.portrait, '4:5'),
                (SnapshotCropAspect.story, '9:16'),
              ],
              onChanged: _setAspect,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                key: const ValueKey('snapshot_crop_reset'),
                tooltip: strings.cropReset,
                onPressed: _saving
                    ? null
                    : () => setState(() => _transform.value = Matrix4.identity()),
                icon: const Icon(
                  CupertinoIcons.arrow_counterclockwise,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const Spacer(),
              GestureDetector(
                key: const ValueKey('snapshot_crop_done'),
                behavior: HitTestBehavior.opaque,
                onTap: _saving ? null : () => _done(frame, baseScale),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            strings.editDone,
                            style: shareTextStyle(
                              context,
                              ShareTextSpec.button,
                              color: Colors.black,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
