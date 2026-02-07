// lib/ui/widgets/fullscreen_image_viewer.dart
// 간단한 전체화면 이미지 뷰어

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FullscreenImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final String? heroTag;

  const FullscreenImageViewer({
    Key? key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.heroTag,
  }) : super(key: key);

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer>
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
    
    // 상태바 숨기기
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
    // tapPosition을 "장면 좌표(scene)"로 변환해서 그 지점을 중심으로 확대되도록 변환행렬 구성
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
        Offset(MediaQuery.of(context).size.width / 2,
            MediaQuery.of(context).size.height / 2);

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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 이미지 PageView
          PageView.builder(
            controller: _pageController,
            physics: _isZoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: widget.imageUrls.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
                _isZoomed = false; // 페이지 전환 시 기본값으로 리셋
              });
              // 새 페이지가 이미 확대된 상태(예: 복원되지 않은 컨트롤러)라면 동기화
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _syncZoomStateForIndex(index);
              });
            },
            itemBuilder: (context, index) {
              final imageUrl = widget.imageUrls[index];
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
                      // heroTag가 주어졌다면 "처음 열린 이미지"에서만 그대로 사용해
                      // 기존 호출부(post/review 등)의 Hero 매칭을 유지한다.
                      // 나머지 페이지는 고유 태그를 사용해 중복 Hero 태그로 인한 크래시를 방지한다.
                      tag: (widget.heroTag != null && index == widget.initialIndex)
                          ? widget.heroTag!
                          : '${widget.heroTag ?? 'image'}_$index',
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          );
                        },
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

          // 닫기 버튼 (왼쪽 상단)
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
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          
          // 페이지 인디케이터 (이미지가 2장 이상일 때만) - 오른쪽 상단
          if (widget.imageUrls.length > 1)
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
                    '${_currentIndex + 1} / ${widget.imageUrls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// 전체화면 이미지 뷰어 표시 헬퍼 함수
Future<void> showFullscreenImageViewer(
  BuildContext context, {
  required List<String> imageUrls,
  int initialIndex = 0,
  String? heroTag,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => FullscreenImageViewer(
        imageUrls: imageUrls,
        initialIndex: initialIndex,
        heroTag: heroTag,
      ),
    ),
  );
}
