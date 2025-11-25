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

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    
    // 상태바 숨기기
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    _pageController.dispose();
    
    // 상태바 복원
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
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
            itemCount: widget.imageUrls.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final imageUrl = widget.imageUrls[index];
              
              return InteractiveViewer(
                panEnabled: true,
                scaleEnabled: true,
                minScale: 0.8,
                maxScale: 3.0,
                child: Center(
                  child: Hero(
                    tag: widget.heroTag ?? 'image_$index',
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
              );
            },
          ),

          // 닫기 버튼
          SafeArea(
            child: Positioned(
              top: 16,
              right: 16,
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
          
          // 페이지 인디케이터 (이미지가 2장 이상일 때만)
          if (widget.imageUrls.length > 1)
            SafeArea(
              child: Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Center(
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
