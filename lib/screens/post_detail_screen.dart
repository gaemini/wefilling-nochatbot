// lib/screens/post_detail_screen.dart
// 게시글 상세 화면
// 게시글 내용, 좋아요, 댓글 표시
// 댓글 작성 및 게시글 삭제 기능

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../services/post_service.dart';
import '../services/comment_service.dart';
import '../services/storage_service.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../widgets/country_flag_circle.dart';
import '../ui/widgets/enhanced_comment_widget.dart';

class PostDetailScreen extends StatefulWidget {
  final Post post;

  const PostDetailScreen({Key? key, required this.post}) : super(key: key);

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final PostService _postService = PostService();
  final CommentService _commentService = CommentService();
  final TextEditingController _commentController = TextEditingController();
  bool _isAuthor = false;
  bool _isDeleting = false;
  bool _isSubmittingComment = false;
  bool _isLiked = false;
  bool _isTogglingLike = false;
  late Post _currentPost;

  // 이미지 재시도 관련 상태
  Map<String, int> _imageRetryCount = {}; // URL별 재시도 횟수
  Map<String, bool> _imageRetrying = {}; // URL별 재시도 중 상태
  static const int _maxRetryCount = 3; // 최대 재시도 횟수

  @override
  void initState() {
    super.initState();
    _currentPost = widget.post;
    _checkIfUserIsAuthor();
    _checkIfUserLikedPost();
    // 디버그용: 이미지 URL 확인
    _logImageUrls();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _checkIfUserIsAuthor() async {
    final isAuthor = await _postService.isCurrentUserAuthor(widget.post.id);
    if (mounted) {
      setState(() {
        _isAuthor = isAuthor;
      });
    }
  }

  Future<void> _checkIfUserLikedPost() async {
    final hasLiked = await _postService.hasUserLikedPost(widget.post.id);
    if (mounted) {
      setState(() {
        _isLiked = hasLiked;
      });
    }
  }

  // 게시글 새로고침
  Future<void> _refreshPost() async {
    try {
      final updatedPost = await _postService.getPostById(widget.post.id);
      if (updatedPost != null && mounted) {
        setState(() {
          _currentPost = updatedPost;
        });
      }
    } catch (e) {
      print('게시글 새로고침 오류: $e');
    }
  }

  // post_detail_screen.dart 파일의 _toggleLike 메서드 개선
  Future<void> _toggleLike() async {
    if (_isTogglingLike) return;

    // 로그인 상태 확인
    final authProvider = Provider.of<app_auth.AuthProvider>(
      context,
      listen: false,
    );
    final isLoggedIn = authProvider.isLoggedIn;
    final user = authProvider.user;

    if (!isLoggedIn || user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('좋아요를 누르려면 로그인이 필요합니다.')));
      return;
    }

    // 즉시 UI 업데이트 (낙관적 업데이트 방식)
    setState(() {
      _isTogglingLike = true;
      _isLiked = !_isLiked; // 즉시 좋아요 상태 토글

      // 좋아요 수와 목록 업데이트 - copyWith 사용하여 모든 필드 보존
      if (_isLiked) {
        // 좋아요 추가
        _currentPost = _currentPost.copyWith(
          likes: _currentPost.likes + 1,
          likedBy: [..._currentPost.likedBy, user.uid],
        );
      } else {
        // 좋아요 제거
        _currentPost = _currentPost.copyWith(
          likes: _currentPost.likes - 1,
          likedBy: _currentPost.likedBy.where((id) => id != user.uid).toList(),
        );
      }
    });

    try {
      // Firebase에 변경사항 저장
      final success = await _postService.toggleLike(_currentPost.id);

      if (!success && mounted) {
        // 실패 시 UI 롤백
        setState(() {
          _isLiked = !_isLiked;
        // 좋아요 수와 목록 롤백 - copyWith 사용하여 모든 필드 보존
        if (_isLiked) {
          _currentPost = _currentPost.copyWith(
            likes: _currentPost.likes + 1,
            likedBy: [..._currentPost.likedBy, user.uid],
          );
        } else {
          _currentPost = _currentPost.copyWith(
            likes: _currentPost.likes - 1,
            likedBy: _currentPost.likedBy.where((id) => id != user.uid).toList(),
          );
        }

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('좋아요 업데이트에 실패했습니다.')));
        });
      }

      // 최신 데이터로 백그라운드 갱신 (필요한 경우)
      if (success) {
        _refreshPost();
      }
    } catch (e) {
      print('좋아요 토글 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류가 발생했습니다: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingLike = false;
        });
      }
    }
  }

  Future<void> _deletePost() async {
    // 삭제 확인 다이얼로그 표시
    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('게시글 삭제'),
                content: const Text('정말 이 게시글을 삭제하시겠습니까?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('취소'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('삭제'),
                  ),
                ],
              ),
        ) ??
        false;

    if (!shouldDelete || !mounted) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      final success = await _postService.deletePost(widget.post.id);

      if (success && mounted) {
        // 삭제 성공 시 화면 닫기
        Navigator.of(context).pop(true); // true를 반환하여 삭제되었음을 알림
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('게시글이 삭제되었습니다.')));
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('게시글 삭제에 실패했습니다.')));
        setState(() {
          _isDeleting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류가 발생했습니다: $e')));
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  // 댓글 등록
  Future<void> _submitComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    // 댓글 작성 전 상태 로깅
    final authUser = FirebaseAuth.instance.currentUser;
    print('💬 댓글 작성 시작');
    print(
      '💬 Auth 상태 (작성 전): ${authUser != null ? "Authenticated (${authUser.uid})" : "Not Authenticated"}',
    );
    print('💬 Timestamp (작성 전): ${DateTime.now()}');

    setState(() {
      _isSubmittingComment = true;
    });

    try {
      final success = await _commentService.addComment(widget.post.id, content);

      // 댓글 작성 후 상태 로깅
      final authUserAfter = FirebaseAuth.instance.currentUser;
      print('💬 댓글 작성 완료');
      print(
        '💬 Auth 상태 (작성 후): ${authUserAfter != null ? "Authenticated (${authUserAfter.uid})" : "Not Authenticated"}',
      );
      print('💬 Timestamp (작성 후): ${DateTime.now()}');
      print('💬 댓글 작성 성공: $success');

      if (success && mounted) {
        _commentController.clear();
        // 키보드 닫기
        FocusScope.of(context).unfocus();

        // 게시글 정보 새로고침 (댓글 수 업데이트)
        print('💬 게시글 새로고침 시작');
        await _refreshPost();
        print('💬 게시글 새로고침 완료');
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('댓글 등록에 실패했습니다.')));
      }
    } catch (e) {
      print('❌ 댓글 작성 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류가 발생했습니다: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingComment = false;
        });
      }
    }
  }

  // 댓글 삭제 (대댓글 포함)
  Future<void> _deleteCommentWithReplies(String commentId) async {
    final success = await _commentService.deleteCommentWithReplies(commentId, _currentPost.id);
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글이 삭제되었습니다.')),
      );
      await _refreshPost();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글 삭제에 실패했습니다.')),
      );
    }
  }

  // 기존 댓글 삭제 (호환성 유지)
  Future<void> _deleteComment(String commentId) async {
    try {
      final success = await _commentService.deleteComment(
        commentId,
        widget.post.id,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('댓글이 삭제되었습니다.')));

        // 게시글 정보 새로고침 (댓글 수 업데이트)
        await _refreshPost();
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('댓글 삭제에 실패했습니다.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류가 발생했습니다: $e')));
      }
    }
  }

  // 댓글 위젯 빌드
  Widget _buildCommentItem(Comment comment) {
    final authProvider = Provider.of<app_auth.AuthProvider>(
      context,
      listen: false,
    );
    final isCommentAuthor = authProvider.user?.uid == comment.userId;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 프로필 이미지
          CircleAvatar(
            radius: 18,
            backgroundColor:
                comment.authorPhotoUrl.isEmpty
                    ? _getAvatarColor(comment.authorNickname)
                    : Colors.grey[200],
            backgroundImage:
                comment.authorPhotoUrl.isNotEmpty
                    ? NetworkImage(comment.authorPhotoUrl)
                    : null,
            child:
                comment.authorPhotoUrl.isEmpty
                    ? Text(
                      comment.authorNickname.isNotEmpty
                          ? comment.authorNickname[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    )
                    : null,
          ),
          const SizedBox(width: 12),

          // 댓글 내용
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더 (닉네임 + 시간)
                Row(
                  children: [
                    // 닉네임
                    Text(
                      comment.authorNickname,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 작성 시간
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _formatNotificationTime(comment.createdAt),
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // 댓글 내용 - 간격과 스타일 개선
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    comment.content,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: Color(0xFF444444),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 삭제 버튼 (댓글 작성자만 볼 수 있음)
          if (isCommentAuthor)
            Container(
              margin: const EdgeInsets.only(left: 4),
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  padding: const EdgeInsets.all(8),
                ),
                color: Colors.red[400],
                onPressed: () => _deleteComment(comment.id),
                tooltip: '댓글 삭제',
              ),
            ),
        ],
      ),
    );
  }

  // 알림 시간 포맷팅
  String _formatNotificationTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }

  // 디버그용: 이미지 URL 로깅
  void _logImageUrls() {
    print('📋 게시글 ID: ${_currentPost.id}');
    print('📋 이미지 URL 개수: ${_currentPost.imageUrls.length}');
    for (int i = 0; i < _currentPost.imageUrls.length; i++) {
      print('📋 원본 이미지 URL $i: ${_currentPost.imageUrls[i]}');
    }
    print('✅ URL 변환 없이 원본 그대로 사용');
  }

  // 이미지 로딩 재시도 로직
  void _retryImageLoad(String imageUrl) {
    if (_imageRetrying[imageUrl] == true) {
      print('🔄 이미 재시도 중인 이미지: $imageUrl');
      return;
    }

    final currentRetryCount = _imageRetryCount[imageUrl] ?? 0;
    if (currentRetryCount >= _maxRetryCount) {
      print('❌ 최대 재시도 횟수 초과: $imageUrl (${currentRetryCount}회)');
      return;
    }

    setState(() {
      _imageRetrying[imageUrl] = true;
      _imageRetryCount[imageUrl] = currentRetryCount + 1;
    });

    print(
      '🔄 이미지 재시도 시작: $imageUrl (${currentRetryCount + 1}/${_maxRetryCount}회)',
    );

    // 재시도 지연 시간 (점진적으로 증가)
    final delaySeconds = (currentRetryCount + 1) * 2; // 2초, 4초, 6초

    Future.delayed(Duration(seconds: delaySeconds), () {
      if (mounted) {
        setState(() {
          _imageRetrying[imageUrl] = false;
        });
        print('🔄 이미지 재시도 실행: $imageUrl');
      }
    });
  }

  // 이미지 로딩 성공 처리
  void _onImageLoadSuccess(String imageUrl) {
    if (_imageRetryCount.containsKey(imageUrl)) {
      print('✅ 이미지 로딩 성공: $imageUrl (${_imageRetryCount[imageUrl]}회 재시도 후)');
      setState(() {
        _imageRetryCount.remove(imageUrl);
        _imageRetrying.remove(imageUrl);
      });
    }
  }

  // 재시도 가능한 이미지 위젯 빌더
  Widget _buildRetryableImage(
    String imageUrl, {
    required BoxFit fit,
    required bool isFullScreen,
  }) {
    final isRetrying = _imageRetrying[imageUrl] ?? false;
    final retryCount = _imageRetryCount[imageUrl] ?? 0;

    // 재시도 중이면 로딩 인디케이터 표시
    if (isRetrying) {
      return Container(
        color: Colors.grey.shade100,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              '재시도 중... (${retryCount}/${_maxRetryCount})',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Image.network(
      imageUrl,
      fit: fit,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36',
        'Accept': 'image/*',
      },
      loadingBuilder: (context, child, loadingProgress) {
        final authUser = FirebaseAuth.instance.currentUser;
        print('📸 이미지 로딩 시도: $imageUrl');
        print(
          '📸 Auth 상태: ${authUser != null ? "Authenticated (${authUser.uid})" : "Not Authenticated"}',
        );
        print('📸 Timestamp: ${DateTime.now()}');

        if (loadingProgress != null) {
          print(
            '📸 로딩 진행률: ${loadingProgress.cumulativeBytesLoaded} / ${loadingProgress.expectedTotalBytes ?? 'unknown'}',
          );
        }

        if (loadingProgress == null) {
          // 이미지 로딩 성공
          _onImageLoadSuccess(imageUrl);
          return child;
        }

        return Center(
          child: CircularProgressIndicator(
            value:
                loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
            strokeWidth: isFullScreen ? 3 : 2,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        final authUser = FirebaseAuth.instance.currentUser;
        print('❌ 이미지 로드 오류: $imageUrl');
        print('❌ Error: $error');
        print(
          '❌ Auth 상태: ${authUser != null ? "Authenticated (${authUser.uid})" : "Not Authenticated"}',
        );
        print('❌ Timestamp: ${DateTime.now()}');

        // 403 오류이고 재시도 가능한 경우 자동 재시도
        if (error.toString().contains('403') && retryCount < _maxRetryCount) {
          print('🔄 403 오류 감지, 자동 재시도 시작: $imageUrl');
          // 비동기적으로 재시도 실행
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _retryImageLoad(imageUrl);
          });

          return Container(
            color: Colors.grey.shade100,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.refresh,
                  color: Colors.blue.shade600,
                  size: isFullScreen ? 32 : 24,
                ),
                const SizedBox(height: 8),
                Text(
                  '곧 재시도됩니다...',
                  style: TextStyle(
                    fontSize: isFullScreen ? 14 : 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        // 최대 재시도 횟수 초과하거나 403이 아닌 오류
        return Container(
          color: Colors.grey.shade200,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                retryCount >= _maxRetryCount
                    ? Icons.error_outline
                    : Icons.broken_image,
                color: Colors.grey[600],
                size: isFullScreen ? 32 : 24,
              ),
              const SizedBox(height: 8),
              Text(
                retryCount >= _maxRetryCount ? '이미지를 불러올 수 없습니다' : '이미지 오류',
                style: TextStyle(
                  fontSize: isFullScreen ? 14 : 12,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              if (retryCount >= _maxRetryCount) ...[
                const SizedBox(height: 4),
                Text(
                  '${_maxRetryCount}회 재시도 실패',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
                const SizedBox(height: 8),
                // 수동 재시도 버튼 (최대 재시도 후에만 표시)
                ElevatedButton.icon(
                  onPressed: () {
                    // 재시도 카운트 리셋 후 다시 시도
                    setState(() {
                      _imageRetryCount[imageUrl] = 0;
                      _imageRetrying[imageUrl] = false;
                    });
                    print('🔄 수동 재시도: $imageUrl');
                  },
                  icon: Icon(Icons.refresh, size: 16),
                  label: Text('다시 시도', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size(0, 0),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<app_auth.AuthProvider>(context);
    final isLoggedIn = authProvider.isLoggedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('게시글'),
        actions: [
          // 게시글 삭제 버튼 (작성자인 경우에만)
          if (_isAuthor)
            _isDeleting
                ? Container(
                  margin: const EdgeInsets.all(10.0),
                  width: 20,
                  height: 20,
                  child: const CircularProgressIndicator(
                    color: Colors.red,
                    strokeWidth: 2,
                  ),
                )
                : IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red,
                  tooltip: '게시글 삭제',
                  onPressed: _deletePost,
                ),
        ],
      ),
      body: Column(
        children: [
          // 게시글 내용
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 게시글 제목
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      _currentPost.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),

                  // 작성자 정보 영역
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        // 작성자 아바타
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: _getAvatarColor(_currentPost.author),
                          child: Text(
                            _currentPost.author.isNotEmpty
                                ? _currentPost.author[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 작성자 정보
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _currentPost.author,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // 국적 정보 표시
                                CountryFlagCircle(
                                  nationality: _currentPost.authorNationality,
                                  size: 22,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _currentPost.getFormattedTime(),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 게시글 이미지
                  if (_currentPost.imageUrls.isNotEmpty)
                    Container(
                      height: 200,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _currentPost.imageUrls.length,
                        itemBuilder: (context, index) {
                          final imageUrl = _currentPost.imageUrls[index];
                          print('이미지 표시 시도: $imageUrl');
                          print('이미지 번호: $index, URL 길이: ${imageUrl.length}');

                          return GestureDetector(
                            onTap: () {
                              // 이미지 전체 화면으로 보기
                              showDialog(
                                context: context,
                                builder:
                                    (context) => Dialog(
                                      insetPadding: const EdgeInsets.all(8),
                                      child: InteractiveViewer(
                                        panEnabled: true,
                                        boundaryMargin: const EdgeInsets.all(
                                          20,
                                        ),
                                        minScale: 0.5,
                                        maxScale: 3.0,
                                        child: _buildRetryableImage(
                                          imageUrl,
                                          fit: BoxFit.contain,
                                          isFullScreen: true,
                                        ),
                                      ),
                                    ),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 200,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _buildRetryableImage(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  isFullScreen: false,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),

                  // 게시글 본문
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _currentPost.content,
                      style: const TextStyle(
                        fontSize: 19,
                        height: 1.6,
                        color: Color(0xFF333333),
                      ),
                    ),
                  ),

                  // 좋아요 섹션
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      // 좋아요 버튼
                      IconButton(
                        icon: Icon(
                          _isLiked ? Icons.favorite : Icons.favorite_border,
                          color: _isLiked ? Colors.red : Colors.grey,
                          size: 28, // 버튼 크기 증가
                        ),
                        onPressed:
                            _isTogglingLike
                                ? null
                                : () {
                                  // 버튼 클릭 시 좋아요 토글 함수 호출
                                  _toggleLike();
                                },
                        splashColor: Colors.red.withAlpha(76), // 눌렀을 때 효과 추가
                        splashRadius: 24,
                      ),
                      // 좋아요 수
                      Text(
                        '${_currentPost.likes}',
                        style: TextStyle(
                          fontSize: 16,
                          color: _isLiked ? Colors.red : Colors.grey[700],
                          fontWeight:
                              _isLiked ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      const Spacer(),
                      // 댓글 아이콘 및 수
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 20,
                        color: Colors.grey[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_currentPost.commentCount}',
                        style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                      ),
                    ],
                  ),

                  // 댓글 섹션 타이틀
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          height: 18,
                          width: 3,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade700,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '댓글',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: StreamBuilder<List<Comment>>(
                            stream: _commentService.getCommentsByPostId(
                              _currentPost.id,
                            ),
                            builder: (context, snapshot) {
                              final count = snapshot.data?.length ?? 0;
                              return Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 확장된 댓글 목록 (대댓글 + 좋아요 지원)
                  StreamBuilder<List<Comment>>(
                    stream: _commentService.getCommentsWithReplies(_currentPost.id),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            '댓글을 불러오는 중 오류가 발생했습니다: ${snapshot.error}',
                          ),
                        );
                      }

                      final allComments = snapshot.data ?? [];

                      if (allComments.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: Text('첫 번째 댓글을 남겨보세요!')),
                        );
                      }

                      // 댓글을 계층적으로 구조화
                      final topLevelComments = allComments.where((c) => c.isTopLevel).toList();
                      
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: topLevelComments.length,
                        itemBuilder: (context, index) {
                          final comment = topLevelComments[index];
                          final replies = allComments
                              .where((c) => c.parentCommentId == comment.id)
                              .toList();
                          
                          return EnhancedCommentWidget(
                            comment: comment,
                            replies: replies,
                            postId: _currentPost.id,
                            onDeleteComment: _deleteCommentWithReplies,
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 댓글 입력 영역
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withAlpha(51),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                // 현재 사용자 프로필 이미지 (로그인 상태인 경우에만)
                if (isLoggedIn) ...[
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.grey[200],
                    backgroundImage:
                        authProvider.user?.photoURL != null
                            ? NetworkImage(authProvider.user!.photoURL!)
                            : null,
                    child:
                        authProvider.user?.photoURL == null
                            ? Text(
                              authProvider.userData?['nickname'] != null
                                  ? (authProvider.userData!['nickname']
                                          as String)[0]
                                      .toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                            : null,
                  ),
                  const SizedBox(width: 8),
                ],

                // 댓글 입력 필드
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText:
                          isLoggedIn ? '댓글을 입력하세요...' : '로그인 후 댓글을 작성할 수 있습니다',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      enabled: isLoggedIn,
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: isLoggedIn ? (_) => _submitComment() : null,
                  ),
                ),

                // 댓글 전송 버튼
                const SizedBox(width: 8),
                IconButton(
                  icon:
                      _isSubmittingComment
                          ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.send),
                  onPressed:
                      (isLoggedIn && !_isSubmittingComment)
                          ? _submitComment
                          : null,
                  color: Colors.blue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 아바타 색상 생성 헬퍼 메서드
  Color _getAvatarColor(String text) {
    if (text.isEmpty) return Colors.grey;
    final colors = [
      Colors.blue.shade700,
      Colors.purple.shade700,
      Colors.green.shade700,
      Colors.orange.shade700,
      Colors.pink.shade700,
      Colors.teal.shade700,
    ];

    // 이름의 첫 글자 아스키 코드를 기준으로 색상 결정
    final index = text.codeUnitAt(0) % colors.length;
    return colors[index];
  }
}
