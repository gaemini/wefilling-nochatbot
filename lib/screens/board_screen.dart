// lib/screens/board_screen.dart
//게시판 메인 화면
//광고 배터 및 게시글 목록 표시
//게시글 작성 기능 제공

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/post.dart';
import '../services/post_service.dart';
import '../widgets/country_flag_circle.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class BoardScreen extends StatefulWidget {
  const BoardScreen({Key? key}) : super(key: key);

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  final PostService _postService = PostService();
  final PageController _bannerController = PageController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // 배너 인디케이터 상태를 위한 ValueNotifier 추가
  final ValueNotifier<int> _currentBannerIndex = ValueNotifier<int>(0);

  // 배너 데이터 - 제목과 URL을 포함합니다.
  final List<Map<String, dynamic>> _banners = [
    {
      'title': 'MCPC',
      'url': 'https://swift-graphs-363644.framer.app/',
      'color': Colors.blue,
      'icon': Icons.computer,
      'domain': 'MCPC.app',
    },
    {
      'title': 'Office of International Affairs',
      'url': 'https://global.hanyang.ac.kr/?intro_non', 
      'color': Colors.blue,
      'icon': Icons.language,
      'domain': 'hanyang.ac.kr',
    },
  ];

  @override
  void initState() {
    super.initState();
    // 배너 자동 슬라이드 설정
    _startAutoSlide();
    
    // 메모리 최적화를 위한 GC 힌트
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // 화면이 그려진 후 약간의 딜레이를 두고 초기화
        Future.delayed(const Duration(milliseconds: 200), () {});
      }
    });
  }

  @override
  void dispose() {
    // ValueNotifier 해제 추가
    _currentBannerIndex.dispose();
    _bannerController.dispose();
    _searchController.dispose();
    // 메모리 힌트 추가
    WidgetsBinding.instance.addPostFrameCallback((_) {});
    super.dispose();
  }

  // 배너 자동 슬라이드 기능 수정
  void _startAutoSlide() {
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        final nextPage = (_currentBannerIndex.value + 1) % _banners.length;
        _bannerController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        ).then((_) {
          // 애니메이션 완료 후 다음 슬라이드 예약
          if (mounted) {
            _startAutoSlide();
          }
        });
      }
    });
  }

  // URL 열기 기능
  Future<void> _launchURL(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      // 기존 코드를 수정하여 직접 launchUrl 호출
      await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,  
      ).then((value) {
        if (!value) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('링크를 열 수 없습니다')),
            );
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류가 발생했습니다: ${e.toString()}')),
        );
      }
    }
  }

  // 아바타 색상 생성 헬퍼 메서드
  Color _getAvatarColor(String text) {
    if (text.isEmpty) return Colors.grey;
    final colors = [
      Colors.blue.shade500,
      Colors.blue.shade600,
      Colors.blue.shade700,
      Colors.blue.shade800,
      Colors.indigo.shade500,
      Colors.indigo.shade600,
    ];
    
    // 이름의 첫 글자 아스키 코드를 기준으로 색상 결정
    final index = text.codeUnitAt(0) % colors.length;
    return colors[index];
  }
  
  // 카운트 배지 위젯
  Widget _buildCountBadge(IconData icon, int count, Color iconColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: iconColor,
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: iconColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFCFF), // 배경색 설정
      body: Column(
        children: [
          // 검색창 추가
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                hintText: '게시글 검색',
                hintStyle: TextStyle(color: Colors.grey[400]),
                filled: true,
                fillColor: Colors.grey[200], 
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.blue.shade300),
                ),
                // 검색어 지우기 버튼 추가
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          
          // 광고 배너 (슬라이드 박스)
          SizedBox(
            height: 180,
            child: PageView.builder(
              controller: _bannerController,
              itemCount: _banners.length,
              onPageChanged: (index) {
                // setState 대신 ValueNotifier 값 변경
                _currentBannerIndex.value = index;
              },
              // 캐싱 설정
              allowImplicitScrolling: false,
              physics: const PageScrollPhysics(),
              padEnds: false,
              pageSnapping: true,
              itemBuilder: (context, index) {
                final banner = _banners[index];
                // WebPreviewBanner 대신 일반 배너로 변경
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
                        onTap: () => _launchURL(banner['url']),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                banner['color'].withOpacity(0.1),
                                banner['color'].withOpacity(0.2),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  banner['icon'],
                                  size: 56,
                                  color: banner['color'],
                                ),
                                const SizedBox(height: 20),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  child: Text(
                                    banner['title'],
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 배너 인디케이터 ValueListenableBuilder로 변경
          ValueListenableBuilder<int>(
            valueListenable: _currentBannerIndex,
            builder: (context, currentIndex, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _banners.length,
                  (index) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: currentIndex == index
                          ? Colors.blue.shade600
                          : Colors.grey.shade300,
                    ),
                  ),
                ),
              );
            }
          ),
          
          // 게시글 목록 헤더
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      height: 24,
                      width: 4,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '게시글',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 게시글 목록
          Expanded(
            child: StreamBuilder<List<Post>>(
              stream: _postService.getAllPosts(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('오류가 발생했습니다: ${snapshot.error}'),
                  );
                }

                final allPosts = snapshot.data ?? [];
                
                // 검색 필터링
                final posts = _searchQuery.isEmpty
                    ? allPosts
                    : allPosts
                        .where((post) =>
                            post.title.toLowerCase().contains(_searchQuery) ||
                            post.content.toLowerCase().contains(_searchQuery))
                        .toList();

                if (posts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _searchQuery.isEmpty 
                              ? Icons.article_outlined
                              : Icons.search_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? '게시글이 없습니다'
                              : '검색 결과가 없습니다',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.isEmpty
                              ? '첫 번째 게시글을 작성해보세요!'
                              : '다른 검색어를 시도해보세요!',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {}); // 새로고침 효과
                  },
                  child: ListView.builder(
                    itemCount: posts.length,
                    itemBuilder: (context, index) {
                      final post = posts[index];
                      return Card(
                        elevation: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        color: const Color(0xFFF5F8FF), 
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.blue.shade50, width: 0.5),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {

                            // 게시글 상세 화면으로 이동
                            final result = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PostDetailScreen(post: post),
                              ),
                            );

                            // 게시글이 삭제되었으면 목록 새로고침
                            if (result == true) {
                              setState(() {}); // Stream이므로 자동으로 갱신됨
                            }
                          },

                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [

                                // 제목 - 이 부분을 수정
                                Consumer<SettingsProvider>(
                                  builder: (context, settings, child) {
                                    return FutureBuilder<String>(
                                      future: post.getTranslatedTitle(settings),
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState == ConnectionState.waiting) {
                                          return Text(
                                            post.title,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: -0.2,
                                              color: Color(0xFF2C3E50),
                                            ),
                                          );
                                        }
                                        return Text(
                                          snapshot.data ?? post.title,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: -0.2,
                                            color: Color(0xFF2C3E50),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),

                                // 이미지 섹션
                                if (post.content.isNotEmpty)
                                  Consumer<SettingsProvider>(
                                    builder: (context, settings, child) {
                                      return FutureBuilder<String>(
                                        future: post.getTranslatedPreviewContent(settings),
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState == ConnectionState.waiting) {
                                            return Text(
                                              post.getPreviewContent(),
                                              style: const TextStyle(
                                                fontSize: 14,
                                                height: 1.3,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            );
                                          }
                                          return Text(
                                            snapshot.data ?? post.getPreviewContent(),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              height: 1.3,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          );
                                        },
                                      );
                                    },
                                  ),
                                
                                const SizedBox(height: 8),
                                
                                // 구분선
                                Divider(color: Colors.blue.shade100),
                                
                                // 하단 메타 정보 영역
                                Row(
                                  children: [
                                    // 작성자 아바타 (첫 글자로 표현)
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: _getAvatarColor(post.author),
                                      child: Text(
                                        post.author.isNotEmpty ? post.author[0].toUpperCase() : '?',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    
                                    // 작성자
                                    Text(
                                      post.author,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14,
                                        color: Color(0xFF3A5270), 
                                      ),
                                    ),
                                    
                                    // 시간 구분점
                                    Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 8),
                                      width: 3,
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[400],
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    
                                    // 작성 시간
                                    Text(
                                      post.getFormattedTime(),
                                      style: TextStyle(
                                        color: Colors.blue.shade700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    
                                    const Spacer(),
                                    
                                    // 좋아요 개수 표시
                                    if (post.likes > 0)
                                      _buildCountBadge(
                                        Icons.favorite,
                                        post.likes,
                                        Colors.red,
                                        Colors.red.shade50,
                                      ),
                                      
                                    // 댓글 개수 표시
                                    if (post.commentCount > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: _buildCountBadge(
                                          Icons.chat_bubble_outline,
                                          post.commentCount,
                                          Colors.blue.shade700,
                                          Colors.blue.shade50,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      // 게시글 작성 버튼
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreatePostScreen(
                onPostCreated: () {
                  // 게시글이 작성되면 화면 새로고침 (스트림이므로 자동으로 업데이트됨)
                  setState(() {});
                },
              ),
            ),
          );
        },
        backgroundColor: Colors.blue.shade700,
        icon: const Icon(Icons.edit, color: Colors.white),
        label: const Text(
          '글쓰기',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}