// lib/ui/widgets/profile_image_viewer.dart
// 프로필 사진 확대 뷰어
// Hero 애니메이션과 제스처를 활용한 고품질 이미지 뷰어

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/profile_photo_policy.dart';

class ProfileImageViewer extends StatefulWidget {
  final String imageUrl;
  final String heroTag;

  const ProfileImageViewer({
    Key? key,
    required this.imageUrl,
    required this.heroTag,
  }) : super(key: key);

  @override
  State<ProfileImageViewer> createState() => _ProfileImageViewerState();
}

class _ProfileImageViewerState extends State<ProfileImageViewer>
    with SingleTickerProviderStateMixin {
  late TransformationController _transformationController;
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  
  // 드래그로 닫기 기능
  double _dragDistance = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    // 상태바 숨기기
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    
    // 상태바 복원
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _onDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    
    Matrix4 endMatrix;
    if (currentScale > 1.0) {
      // 줌 아웃
      endMatrix = Matrix4.identity();
    } else {
      // 줌 인 (2배)
      endMatrix = Matrix4.identity()..scale(2.0);
    }

    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: endMatrix,
    ).animate(
      CurveTween(curve: Curves.easeInOut).animate(_animationController),
    );

    _animationController.forward(from: 0).then((_) {
      _transformationController.value = endMatrix;
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    // 줌 상태가 아닐 때만 드래그로 닫기 가능
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale <= 1.0) {
      setState(() {
        _isDragging = true;
        _dragDistance += details.delta.dy;
      });
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    // 일정 거리 이상 드래그하면 닫기
    if (_dragDistance.abs() > 100) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isDragging = false;
        _dragDistance = 0;
      });
    }
  }

  void _onVerticalDragCancel() {
    if (!_isDragging && _dragDistance == 0) return;
    setState(() {
      _isDragging = false;
      _dragDistance = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final safeUrl = ProfilePhotoPolicy.isAllowedProfilePhotoUrl(widget.imageUrl)
        ? widget.imageUrl
        : '';
    
    final scale = _isDragging
        ? (1.0 - (_dragDistance.abs() / 1000)).clamp(0.85, 1.0)
        : 1.0;

    return Scaffold(
      // 릴리즈(실기기)에서 발생하던 반투명 합성 이슈를 피하기 위해
      // 배경은 항상 완전 불투명으로 유지한다.
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        onVerticalDragCancel: _onVerticalDragCancel,
        child: Stack(
          children: [
            // 이미지 뷰어
            Center(
              child: Transform.translate(
                offset: Offset(0, _dragDistance),
                child: Transform.scale(
                  scale: scale,
                  child: AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      if (_animation != null) {
                        _transformationController.value = _animation!.value;
                      }
                      return InteractiveViewer(
                        transformationController: _transformationController,
                        minScale: 0.5,
                        maxScale: 4.0,
                        onInteractionEnd: (details) {
                          // 줌 아웃 상태에서 손을 떼면 원래 크기로
                          final scale = _transformationController.value.getMaxScaleOnAxis();
                          if (scale < 1.0) {
                            _transformationController.value = Matrix4.identity();
                          }
                        },
                        child: GestureDetector(
                          onDoubleTap: _onDoubleTap,
                          child: Hero(
                            tag: widget.heroTag,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(0),
                              child: safeUrl.isEmpty
                                  ? Container(
                                      width: 200,
                                      height: 200,
                                      color: Colors.grey[900],
                                      child: const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 64,
                                      ),
                                    )
                                  : Image.network(
                                      safeUrl,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                      gaplessPlayback: true,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return Container(
                                          width: 200,
                                          height: 200,
                                          color: Colors.grey[900],
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              value: loadingProgress.expectedTotalBytes != null
                                                  ? loadingProgress.cumulativeBytesLoaded /
                                                      loadingProgress.expectedTotalBytes!
                                                  : null,
                                              color: Colors.white,
                                            ),
                                          ),
                                        );
                                      },
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          width: 200,
                                          height: 200,
                                          color: Colors.grey[900],
                                          child: const Icon(
                                            Icons.error_outline,
                                            color: Colors.white,
                                            size: 48,
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
                ),
              ),
            ),
            
            // 상단 닫기 버튼
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // 하단 안내 텍스트 (처음에만 표시)
            if (!_isDragging && _transformationController.value.getMaxScaleOnAxis() <= 1.0)
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '더블탭으로 확대 • 드래그로 닫기',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
