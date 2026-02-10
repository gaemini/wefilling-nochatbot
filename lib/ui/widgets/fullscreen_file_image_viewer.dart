// lib/ui/widgets/fullscreen_file_image_viewer.dart
// 게시글 이미지 뷰어 UX(스와이프/줌/인디케이터)를 로컬 파일(File)에도 적용

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FullscreenFileImageViewer extends StatefulWidget {
  final List<File> imageFiles;
  final int initialIndex;
  final String? heroTag;
  final bool showConfirmButton;
  final String? confirmLabel;

  const FullscreenFileImageViewer({
    super.key,
    required this.imageFiles,
    this.initialIndex = 0,
    this.heroTag,
    this.showConfirmButton = false,
    this.confirmLabel,
  });

  @override
  State<FullscreenFileImageViewer> createState() => _FullscreenFileImageViewerState();
}

class _FullscreenFileImageViewerState extends State<FullscreenFileImageViewer>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  final Map<int, TransformationController> _transformationControllers = {};
  final Map<int, Offset> _doubleTapDownPositions = {};
  bool _isZoomed = false;
  late final AnimationController _animationController;
  Animation<Matrix4>? _animation;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    // 상태바 숨기기 (기존 게시글 전체화면 이미지 뷰어와 동일)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  void _syncZoomStateForIndex(int index) {
    if (index != _currentIndex) return;
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
    final scenePoint = controller.toScene(tapPosition);
    final dx = -scenePoint.dx * (scale - 1);
    final dy = -scenePoint.dy * (scale - 1);
    return Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
  }

  Future<void> _onDoubleTap(int index) async {
    if (index != _currentIndex) return;
    final controller = _transformationControllers[index];
    if (controller == null) return;

    final current = controller.value;
    final currentScale = current.getMaxScaleOnAxis();
    final isCurrentlyZoomed = currentScale > 1.01;

    final tapPos = _doubleTapDownPositions[index] ??
        Offset(MediaQuery.of(context).size.width / 2, MediaQuery.of(context).size.height / 2);

    final endMatrix = isCurrentlyZoomed
        ? Matrix4.identity()
        : _doubleTapZoomMatrix(controller: controller, tapPosition: tapPos);

    _animationController.stop();
    _animationController.reset();

    _animation = Matrix4Tween(begin: current, end: endMatrix).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    )..addListener(() {
        controller.value = _animation!.value;
        _syncZoomStateForIndex(index);
      });

    try {
      await _animationController.forward();
    } finally {
      controller.value = endMatrix;
      _syncZoomStateForIndex(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirmLabel = widget.confirmLabel ??
        (Localizations.localeOf(context).languageCode == 'ko' ? '이 사진으로 업로드' : 'Continue');

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            physics: _isZoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
            itemCount: widget.imageFiles.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
                _isZoomed = false;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _syncZoomStateForIndex(index);
              });
            },
            itemBuilder: (context, index) {
              final file = widget.imageFiles[index];
              final transformationController = _transformationControllers.putIfAbsent(
                index,
                () => TransformationController(),
              );

              return InteractiveViewer(
                transformationController: transformationController,
                panEnabled: true,
                scaleEnabled: true,
                minScale: 0.8,
                maxScale: 3.0,
                onInteractionStart: (_) => _syncZoomStateForIndex(index),
                onInteractionUpdate: (_) => _syncZoomStateForIndex(index),
                onInteractionEnd: (_) => _syncZoomStateForIndex(index),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTapDown: (d) => _onDoubleTapDown(index, d),
                  onDoubleTap: () => _onDoubleTap(index),
                  child: Center(
                    child: Hero(
                      tag: (widget.heroTag != null && index == widget.initialIndex)
                          ? widget.heroTag!
                          : '${widget.heroTag ?? 'file_image'}_$index',
                      child: Image.file(
                        file,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(
                              Icons.broken_image_rounded,
                              color: Colors.white54,
                              size: 64,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // 닫기 버튼
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
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ),

          // 페이지 인디케이터
          if (widget.imageFiles.length > 1)
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.imageFiles.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

          // 확인(업로드 진행) 버튼
          if (widget.showConfirmButton)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: const BoxDecoration(
                    color: Color(0x8C000000), // black 55%
                    border: Border(top: BorderSide(color: Color(0x14FFFFFF))), // white 8%
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4A90E2),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            confirmLabel,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<bool> showFullscreenFileImageViewer(
  BuildContext context, {
  required List<File> imageFiles,
  int initialIndex = 0,
  String? heroTag,
  bool showConfirmButton = false,
  String? confirmLabel,
}) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (context) => FullscreenFileImageViewer(
        imageFiles: imageFiles,
        initialIndex: initialIndex,
        heroTag: heroTag,
        showConfirmButton: showConfirmButton,
        confirmLabel: confirmLabel,
      ),
    ),
  );
  return result ?? false;
}

