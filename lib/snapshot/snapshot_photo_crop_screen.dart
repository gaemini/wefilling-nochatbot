// lib/snapshot/snapshot_photo_crop_screen.dart
// 스낵 편집의 사진 자르기: 사진 위 자르기 틀의 모서리·변을 끌어 크기를 바꾸고,
// 틀 안을 끌어 옮긴다. 비율은 자유·원본·1:1·4:5·9:16. [완료]하면 틀 안만 담은
// 새 사진 파일을 돌려준다(원본 파일은 바꾸지 않는다).

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'snapshot_share_view.dart';
import 'snapshot_strings.dart';

/// 자를 비율. [free]는 비율 제한 없음, [original]은 사진 원래 비율.
enum SnapshotCropAspect {
  free,
  original,
  square,
  portrait,
  story;

  double? ratioFor(Size image) => switch (this) {
        SnapshotCropAspect.free => null,
        SnapshotCropAspect.original => image.width / image.height,
        SnapshotCropAspect.square => 1,
        SnapshotCropAspect.portrait => 4 / 5,
        SnapshotCropAspect.story => 9 / 16,
      };
}

/// 끌고 있는 부분.
enum SnapshotCropHandle {
  move,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  left,
  right,
  top,
  bottom,
}

/// 사진 안에서 가장 큰, [ratio] 비율의 가운데 틀(사진 픽셀 좌표).
@visibleForTesting
Rect snapshotCenteredCropRect(Size image, double? ratio) {
  if (ratio == null) return Offset.zero & image;
  var width = image.width;
  var height = width / ratio;
  if (height > image.height) {
    height = image.height;
    width = height * ratio;
  }
  return Rect.fromLTWH(
    (image.width - width) / 2,
    (image.height - height) / 2,
    width,
    height,
  );
}

/// 틀을 [delta](사진 픽셀)만큼 끈 결과. 사진 밖으로 나가지 않고, 한 변이
/// [minSide]보다 작아지지 않으며, [ratio]가 있으면 비율을 지킨다.
@visibleForTesting
Rect snapshotDragCropRect({
  required Rect rect,
  required SnapshotCropHandle handle,
  required Offset delta,
  required Size image,
  required double? ratio,
  required double minSide,
}) {
  final bounds = Offset.zero & image;
  if (handle == SnapshotCropHandle.move) {
    final dx = delta.dx.clamp(-rect.left, bounds.right - rect.right);
    final dy = delta.dy.clamp(-rect.top, bounds.bottom - rect.bottom);
    return rect.shift(Offset(dx.toDouble(), dy.toDouble()));
  }

  var left = rect.left;
  var top = rect.top;
  var right = rect.right;
  var bottom = rect.bottom;
  final movesLeft = handle == SnapshotCropHandle.left ||
      handle == SnapshotCropHandle.topLeft ||
      handle == SnapshotCropHandle.bottomLeft;
  final movesRight = handle == SnapshotCropHandle.right ||
      handle == SnapshotCropHandle.topRight ||
      handle == SnapshotCropHandle.bottomRight;
  final movesTop = handle == SnapshotCropHandle.top ||
      handle == SnapshotCropHandle.topLeft ||
      handle == SnapshotCropHandle.topRight;
  final movesBottom = handle == SnapshotCropHandle.bottom ||
      handle == SnapshotCropHandle.bottomLeft ||
      handle == SnapshotCropHandle.bottomRight;

  if (movesLeft) left = (left + delta.dx).clamp(0.0, right - minSide);
  if (movesRight) right = (right + delta.dx).clamp(left + minSide, image.width);
  if (movesTop) top = (top + delta.dy).clamp(0.0, bottom - minSide);
  if (movesBottom) {
    bottom = (bottom + delta.dy).clamp(top + minSide, image.height);
  }

  if (ratio != null) {
    var width = right - left;
    var height = bottom - top;
    final horizontalOnly = (movesLeft || movesRight) && !movesTop && !movesBottom;
    final verticalOnly = (movesTop || movesBottom) && !movesLeft && !movesRight;
    if (horizontalOnly) {
      height = width / ratio;
    } else if (verticalOnly) {
      width = height * ratio;
    } else if (width / height > ratio) {
      width = height * ratio;
    } else {
      height = width / ratio;
    }
    // 사진 안에 들어오도록 줄인다(비율 유지).
    final maxWidth = movesLeft ? right : image.width - left;
    final maxHeight = movesTop ? bottom : image.height - top;
    final shrink = math.min(
      1.0,
      math.min(maxWidth / width, maxHeight / height),
    );
    width *= shrink;
    height *= shrink;
    if (verticalOnly) {
      // 가로는 가운데를 기준으로 맞춘다.
      final center = (rect.left + rect.right) / 2;
      left = (center - width / 2).clamp(0.0, image.width - width);
      right = left + width;
    } else if (movesLeft) {
      left = right - width;
    } else {
      right = left + width;
    }
    if (horizontalOnly) {
      final center = (rect.top + rect.bottom) / 2;
      top = (center - height / 2).clamp(0.0, image.height - height);
      bottom = top + height;
    } else if (movesTop) {
      top = bottom - height;
    } else {
      bottom = top + height;
    }
  }
  return Rect.fromLTRB(left, top, right, bottom).intersect(bounds);
}

class SnapshotPhotoCropScreen extends StatefulWidget {
  const SnapshotPhotoCropScreen({super.key, required this.file});

  final File file;

  @override
  State<SnapshotPhotoCropScreen> createState() =>
      _SnapshotPhotoCropScreenState();
}

class _SnapshotPhotoCropScreenState extends State<SnapshotPhotoCropScreen> {
  static const double _handleTouch = 28;

  ui.Image? _image;
  bool _failed = false;
  bool _saving = false;
  SnapshotCropAspect _aspect = SnapshotCropAspect.free;

  /// 사진 픽셀 좌표의 자르기 틀.
  Rect? _crop;
  SnapshotCropHandle? _dragging;

  Size get _imageSize => Size(
        _image!.width.toDouble(),
        _image!.height.toDouble(),
      );

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
      setState(() {
        _image = frame.image;
        _crop = Offset.zero & _imageSize;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _setAspect(SnapshotCropAspect aspect) {
    if (_image == null) return;
    setState(() {
      _aspect = aspect;
      _crop = snapshotCenteredCropRect(_imageSize, aspect.ratioFor(_imageSize));
    });
  }

  void _reset() {
    if (_image == null) return;
    setState(() {
      _aspect = SnapshotCropAspect.free;
      _crop = Offset.zero & _imageSize;
    });
  }

  /// 화면의 누른 위치(틀 기준)에서 어느 부분을 끄는지 정한다.
  SnapshotCropHandle _hitHandle(Offset point, Rect screenCrop) {
    final nearLeft = (point.dx - screenCrop.left).abs() <= _handleTouch;
    final nearRight = (point.dx - screenCrop.right).abs() <= _handleTouch;
    final nearTop = (point.dy - screenCrop.top).abs() <= _handleTouch;
    final nearBottom = (point.dy - screenCrop.bottom).abs() <= _handleTouch;
    if (nearTop && nearLeft) return SnapshotCropHandle.topLeft;
    if (nearTop && nearRight) return SnapshotCropHandle.topRight;
    if (nearBottom && nearLeft) return SnapshotCropHandle.bottomLeft;
    if (nearBottom && nearRight) return SnapshotCropHandle.bottomRight;
    final insideX =
        point.dx > screenCrop.left && point.dx < screenCrop.right;
    final insideY =
        point.dy > screenCrop.top && point.dy < screenCrop.bottom;
    if (nearLeft && insideY) return SnapshotCropHandle.left;
    if (nearRight && insideY) return SnapshotCropHandle.right;
    if (nearTop && insideX) return SnapshotCropHandle.top;
    if (nearBottom && insideX) return SnapshotCropHandle.bottom;
    return SnapshotCropHandle.move;
  }

  Future<void> _done() async {
    final image = _image;
    final crop = _crop;
    if (image == null || crop == null || _saving) return;
    setState(() => _saving = true);
    try {
      // 결과는 긴 변 2400px 이하(기존 사진 선택과 같은 상한).
      final longest = math.max(crop.width, crop.height);
      final outScale = longest > 2400 ? 2400 / longest : 1.0;
      final outW = math.max(1, (crop.width * outScale).round());
      final outH = math.max(1, (crop.height * outScale).round());
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        image,
        crop,
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
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
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
                              style:
                                  shareTextStyle(context, ShareTextSpec.hint),
                            )
                          : const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            _buildCropArea(image, constraints),
                      ),
                    ),
            ),
            _buildControls(strings),
            SizedBox(height: padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildCropArea(ui.Image image, BoxConstraints constraints) {
    final imageSize = _imageSize;
    // 사진 전체가 보이도록 넣는다(contain).
    final scale = math.min(
      constraints.maxWidth / imageSize.width,
      constraints.maxHeight / imageSize.height,
    );
    final shown = Size(imageSize.width * scale, imageSize.height * scale);
    final crop = _crop ?? Offset.zero & imageSize;
    final screenCrop = Rect.fromLTRB(
      crop.left * scale,
      crop.top * scale,
      crop.right * scale,
      crop.bottom * scale,
    );
    // 한 변 최소 화면 64pt.
    final minSide = 64 / scale;

    return Center(
      child: SizedBox(
        width: shown.width,
        height: shown.height,
        child: GestureDetector(
          key: const ValueKey('snapshot_crop_area'),
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _dragging =
              _hitHandle(details.localPosition, screenCrop),
          onPanUpdate: (details) {
            final handle = _dragging;
            if (handle == null) return;
            setState(() {
              _crop = snapshotDragCropRect(
                rect: _crop ?? Offset.zero & imageSize,
                handle: handle,
                delta: details.delta / scale,
                image: imageSize,
                ratio: _aspect.ratioFor(imageSize),
                minSide: minSide,
              );
            });
          },
          onPanEnd: (_) => _dragging = null,
          onPanCancel: () => _dragging = null,
          child: Stack(
            children: [
              Positioned.fill(
                child: RawImage(image: image, fit: BoxFit.fill),
              ),
              Positioned.fill(
                child: CustomPaint(
                  key: const ValueKey('snapshot_crop_frame'),
                  painter: _CropOverlayPainter(screenCrop),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(SnapshotStrings strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ShareChoiceGroup<SnapshotCropAspect>(
              keyPrefix: 'snapshot_crop_aspect',
              value: _aspect,
              options: [
                (SnapshotCropAspect.free, strings.cropFree),
                (SnapshotCropAspect.original, strings.cropOriginal),
                (SnapshotCropAspect.square, '1:1'),
                (SnapshotCropAspect.portrait, '4:5'),
                (SnapshotCropAspect.story, '9:16'),
              ],
              onChanged: _setAspect,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                key: const ValueKey('snapshot_crop_reset'),
                tooltip: strings.cropReset,
                onPressed: _saving ? null : _reset,
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
                onTap: _saving ? null : _done,
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

/// 틀 밖은 어둡게, 틀에는 흰 선·3분할 안내선·모서리 손잡이.
class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter(this.crop);

  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final dim = Paint()..color = Colors.black.withValues(alpha: .55);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(full),
        Path()..addRect(crop),
      ),
      dim,
    );
    final guide = Paint()
      ..color = Colors.white.withValues(alpha: .45)
      ..strokeWidth = .8;
    for (var i = 1; i < 3; i++) {
      final x = crop.left + crop.width * i / 3;
      final y = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), guide);
      canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), guide);
    }
    canvas.drawRect(
      crop,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final corner = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 18.0;
    void l(Offset a, Offset b) => canvas.drawLine(a, b, corner);
    l(crop.topLeft, crop.topLeft + const Offset(len, 0));
    l(crop.topLeft, crop.topLeft + const Offset(0, len));
    l(crop.topRight, crop.topRight + const Offset(-len, 0));
    l(crop.topRight, crop.topRight + const Offset(0, len));
    l(crop.bottomLeft, crop.bottomLeft + const Offset(len, 0));
    l(crop.bottomLeft, crop.bottomLeft + const Offset(0, -len));
    l(crop.bottomRight, crop.bottomRight + const Offset(-len, 0));
    l(crop.bottomRight, crop.bottomRight + const Offset(0, -len));
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.crop != crop;
}
