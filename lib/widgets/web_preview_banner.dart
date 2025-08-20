import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebPreviewBanner extends StatefulWidget {
  final String url;
  final String title;
  final String domain;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const WebPreviewBanner({
    Key? key,
    required this.url,
    required this.title,
    required this.domain,
    required this.color,
    required this.icon,
    required this.onTap,
  }) : super(key: key);

  @override
  State<WebPreviewBanner> createState() => _WebPreviewBannerState();
}

// 각 URL에 대한 WebViewController를 캐싱하기 위한 정적 맵
final Map<String, WebViewController> _cachedControllers = {};

class _WebPreviewBannerState extends State<WebPreviewBanner> with AutomaticKeepAliveClientMixin {
  late WebViewController _controller;
  bool _isLoading = true;
  bool _hasTimedOut = false;
  bool _isInitialized = false;

  @override
  bool get wantKeepAlive => true; // PageView에서 상태를 유지

  @override
  void initState() {
    super.initState();
    // 지연 웹뷰 로드를 위해 약간의 딜레이 추가
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _initializeController();
      }
    });
  }

  void _initializeController() {
    // 이미 캐시된 컨트롤러가 있는지 확인
    if (_cachedControllers.containsKey(widget.url)) {
      _controller = _cachedControllers[widget.url]!;
      // 이미 로드된 컨트롤러는 로딩 상태를 false로 설정
      setState(() {
        _isLoading = false;
        _isInitialized = true;
      });
      return;
    }

    // 새 컨트롤러 생성 및 캐시에 저장
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            // 페이지 로딩이 시작되면 초기 설정 적용
            _applyInitialSettings();
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _isInitialized = true;
              });

              // 웹뷰 내용을 적절하게 축소하여 전체 페이지가 보이도록 함
              _applyPageOptimizations();
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            // 페이지 내부 링크 클릭을 무시하고 현재 페이지만 표시
            return NavigationDecision.prevent;
          },
          onWebResourceError: (WebResourceError error) {
            // 웹 리소스 로딩 오류 발생 시
            if (mounted && _isLoading) {
              setState(() {
                _isLoading = false;
                _hasTimedOut = true;
              });
            }
          },
        ),
      )
      ..setBackgroundColor(Colors.white)
      ..loadRequest(Uri.parse(widget.url));

    _cachedControllers[widget.url] = _controller;

    // 4초 후에 로딩 상태를 종료하도록 타임아웃 설정
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
          _hasTimedOut = true;
        });
      }
    });
  }

  @override
  void didUpdateWidget(WebPreviewBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // URL이 변경된 경우 컨트롤러 재초기화
    if (oldWidget.url != widget.url) {
      _initializeController();
    }
  }

  // 페이지 로딩 시작 시 초기 설정 적용
  void _applyInitialSettings() {
    _controller.runJavaScript('''
      // 뷰포트 메타 태그 추가 및 크기 조절
      var meta = document.querySelector('meta[name="viewport"]');
      if (!meta) {
        meta = document.createElement('meta');
        meta.name = 'viewport';
        document.head.appendChild(meta);
      }
      meta.content = 'width=device-width, initial-scale=0.6, user-scalable=no';
      
      // 불필요한 애니메이션 및 미디어 해제
      document.querySelectorAll('video, audio').forEach(function(el) {
        el.pause();
        el.removeAttribute('autoplay');
      });
      
      // 스크롤 및 오버플로우 제어
      document.body.style.overflow = 'hidden';
      document.documentElement.style.overflow = 'hidden';
    ''');
  }
  
  // 페이지 로딩 완료 후 최적화 적용
  void _applyPageOptimizations() {
    _controller.runJavaScript('''
      // 여백 제거
      document.body.style.margin = '0';
      document.body.style.padding = '0';
      document.documentElement.style.margin = '0';
      document.documentElement.style.padding = '0';
      
      // 사이트 크기를 화면에 맞게 조정
      document.body.style.transform = 'scale(0.7)';
      document.body.style.transformOrigin = '0 0';
      
      // 쿠키 및 팝업 레이어 제거
      document.querySelectorAll('.cookie-notice, .popup, .modal').forEach(function(el) {
        if (el) el.style.display = 'none';
      });
      
      // 광고 및 불필요한 요소 제거
      document.querySelectorAll('[id*="ad"], [class*="ad"], [id*="banner"], [class*="banner"]').forEach(function(el) {
        if (el) el.style.display = 'none';
      });
    ''');
  }

  @override
  void dispose() {
    // 메모리 사용량을 줄이기 위해 필요하지 않은 경우 컨트롤러 해제
    if (!_isInitialized) {
      _cachedControllers.remove(widget.url);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 요구사항
    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 4.0,
            spreadRadius: 1.0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            child: Column(
              children: [
                // 웹사이트 제목 바
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.1),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.grey.shade200,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.icon,
                        size: 18,
                        color: widget.color,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.domain,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.open_in_new,
                        size: 16,
                        color: Colors.grey.shade400,
                      ),
                    ],
                  ),
                ),
                
                // 웹뷰 미리보기 부분
                Expanded(
                  child: Stack(
                    children: [
                      // 웹뷰
                      WebViewWidget(
                        controller: _controller,
                      ),
                      
                      // 로딩 표시
                      if (_isLoading)
                        Container(
                          color: Colors.white,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: widget.color,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      
                      // 타임아웃된 경우 대체 화면
                      if (_hasTimedOut)
                        Container(
                          color: Colors.white,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  widget.icon,
                                  size: 42,
                                  color: widget.color,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  widget.title,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    widget.domain,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                      // 오버레이 효과 (탭 가능한 느낌을 주기 위한)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withOpacity(0.0),
                                Colors.white.withOpacity(0.4),
                              ],
                              stops: const [0.7, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 웹사이트 제목
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: Colors.grey.shade200,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '웹페이지를 확인하려면 탭하세요',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}