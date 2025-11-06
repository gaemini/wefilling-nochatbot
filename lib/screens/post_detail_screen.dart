// lib/screens/post_detail_screen.dart
// 게시글 상세 화면
// 게시글 내용, 좋아요, 댓글 표시
// 댓글 작성 및 게시글 삭제 기능

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../services/post_service.dart';
import '../services/comment_service.dart';
import '../services/storage_service.dart';
import '../services/dm_service.dart';
import 'dm_chat_screen.dart';
import 'dart:math' as math;
import '../providers/auth_provider.dart' as app_auth;
import '../widgets/country_flag_circle.dart';
import '../ui/widgets/enhanced_comment_widget.dart';
import '../l10n/app_localizations.dart';
import '../design/tokens.dart';
import '../design/color_system.dart';

class PostDetailScreen extends StatefulWidget {
  final Post post;

  const PostDetailScreen({Key? key, required this.post}) : super(key: key);

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final PostService _postService = PostService();
  final CommentService _commentService = CommentService();
  final DMService _dmService = DMService();
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _commentFocusNode = FocusNode();
  bool _isAuthor = false;
  bool _isDeleting = false;
  bool _isSubmittingComment = false;
  bool _isLiked = false;
  bool _isTogglingLike = false;
  bool _isSaved = false;
  bool _isTogglingSave = false;
  late Post _currentPost;
  final PageController _imagePageController = PageController();
  int _currentImageIndex = 0;
  
  // 이미지 페이지 인디케이터 표시 상태
  bool _showPageIndicator = false;
  Timer? _indicatorTimer;

  // 이미지 재시도 관련 상태
  Map<String, int> _imageRetryCount = {}; // URL별 재시도 횟수
  Map<String, bool> _imageRetrying = {}; // URL별 재시도 중 상태
  static const int _maxRetryCount = 3; // 최대 재시도 횟수
  
  // 익명 번호 매핑 (userId -> 익명번호)
  final Map<String, int> _anonymousUserMap = {};

  // 대댓글 모드 상태
  bool _isReplyMode = false;
  String? _replyParentTopLevelId; // 대댓글이 속할 최상위 댓글 ID
  String? _replyToUserId; // 직전 부모 댓글 작성자 ID
  String? _replyToUserName; // 직전 부모 댓글 작성자 닉네임
  String? _replyTargetCommentId; // 하이라이트할 댓글 ID (시각적 피드백용)

  @override
  void initState() {
    super.initState();
    _currentPost = widget.post;
    _checkIfUserIsAuthor();
    _checkIfUserLikedPost();
    _checkIfUserSavedPost();
    // 디버그용: 이미지 URL 확인
    _logImageUrls();
    
    // 이미지가 여러 개일 때 첫 진입 시 인디케이터 표시
    if (_currentPost.imageUrls.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPageIndicatorTemporarily();
      });
    }
  }
  
  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    _commentFocusNode.dispose();
    _imagePageController.dispose();
    _indicatorTimer?.cancel(); // Timer 정리
    super.dispose();
  }
  
  // 페이지 인디케이터를 표시하고 1초 후 자동으로 숨김
  void _showPageIndicatorTemporarily() {
    setState(() {
      _showPageIndicator = true;
    });
    
    // 기존 타이머가 있으면 취소
    _indicatorTimer?.cancel();
    
    // 1초 후 숨김
    _indicatorTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showPageIndicator = false;
        });
      }
    });
  }

  /// 게시글 상세에서 DM 열기
  Future<void> _openDMFromDetail() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.loginRequired),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      // post.userId가 올바른 Firebase UID인지 확인
      print('🔍 DM 대상 확인 (상세페이지):');
      print('  - post.id: ${_currentPost.id}');
      print('  - post.userId: ${_currentPost.userId}');
      print('  - post.isAnonymous: ${_currentPost.isAnonymous}');
      print('  - currentUser.uid: ${currentUser.uid}');
      
      // 본인에게 DM 전송 체크 (익명 포함)
      if (_currentPost.userId == currentUser.uid) {
        print('❌ 본인 게시글에는 DM 불가');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('본인에게는 메시지를 보낼 수 없습니다'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // Firebase Auth UID 형식 검증 (20~30자 영숫자, 언더스코어 포함 가능)
      final uidPattern = RegExp(r'^[a-zA-Z0-9_-]{20,30}$');
      if (!uidPattern.hasMatch(_currentPost.userId)) {
        print('❌ 잘못된 userId 형식: ${_currentPost.userId} (길이: ${_currentPost.userId.length}자)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('이 게시글 작성자에게는 메시지를 보낼 수 없습니다'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // userId가 'deleted' 또는 빈 문자열인 경우 체크
      if (_currentPost.userId == 'deleted' || _currentPost.userId.isEmpty) {
        print('❌ 탈퇴했거나 삭제된 사용자');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('탈퇴한 사용자에게는 메시지를 보낼 수 없습니다'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // 대화방 ID 생성 (실제 생성은 메시지 전송 시)
      final conversationId = _dmService.generateConversationId(
        _currentPost.userId,
        postId: _currentPost.id,
        isOtherUserAnonymous: _currentPost.isAnonymous,
      );
      
      print('✅ DM conversation ID 생성: $conversationId');

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DMChatScreen(
              conversationId: conversationId,
              otherUserId: _currentPost.userId,
            ),
          ),
        );
      }
    } catch (e) {
      print('❌ DM 열기 오류: $e');
      print('오류 타입: ${e.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.cannotSendDM),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Future<void> _checkIfUserIsAuthor() async {
    // Post 객체에 이미 userId가 있으므로 직접 비교
    final user = FirebaseAuth.instance.currentUser;
    if (mounted && user != null) {
      setState(() {
        _isAuthor = widget.post.userId == user.uid;
      });
    }
  }

  Future<void> _checkIfUserLikedPost() async {
    // Post 객체에 이미 likedBy 리스트가 있으므로 직접 확인
    final user = FirebaseAuth.instance.currentUser;
    if (mounted && user != null) {
      setState(() {
        _isLiked = widget.post.likedBy.contains(user.uid);
      });
    }
  }

  Future<void> _checkIfUserSavedPost() async {
    final isSaved = await _postService.isPostSaved(widget.post.id);
    if (mounted) {
      setState(() {
        _isSaved = isSaved;
      });
    }
  }

  Future<void> _toggleSave() async {
    if (_isTogglingSave) return;

    // 로그인 상태 확인
    final authProvider = Provider.of<app_auth.AuthProvider>(
      context,
      listen: false,
    );
    final isLoggedIn = authProvider.isLoggedIn;

    if (!isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('로그인이 필요한 기능입니다'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isTogglingSave = true;
    });

    try {
      final newSavedStatus = await _postService.toggleSavePost(widget.post.id);
      
      if (mounted) {
        setState(() {
          _isSaved = newSavedStatus;
          _isTogglingSave = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newSavedStatus ? AppLocalizations.of(context)!.postSaved : AppLocalizations.of(context)!.postUnsaved
            ),
            backgroundColor: newSavedStatus ? Colors.green : Colors.grey,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTogglingSave = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.error),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
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
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.loginToComment)));
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
          ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.commentLikeFailed)));
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
        ).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')));
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
                title: Text(AppLocalizations.of(context)!.deletePost),
                content: Text(AppLocalizations.of(context)!.deletePostConfirm),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(AppLocalizations.of(context)!.cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: Text(AppLocalizations.of(context)!.delete),
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
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.postDeleted)));
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.postDeleteFailed)));
        setState(() {
          _isDeleting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')));
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  // 대댓글 모드 진입
  void _enterReplyMode({
    required String parentTopId,
    required String replyToUserId,
    required String replyToUserName,
    required String targetCommentId,
  }) {
    setState(() {
      _isReplyMode = true;
      _replyParentTopLevelId = parentTopId;
      _replyToUserId = replyToUserId;
      _replyToUserName = replyToUserName;
      _replyTargetCommentId = targetCommentId;
    });
    
    // 입력창으로 포커스 및 스크롤 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToInputAndFocus();
    });
  }

  // 대댓글 모드 종료
  void _exitReplyMode() {
    setState(() {
      _isReplyMode = false;
      _replyParentTopLevelId = null;
      _replyToUserId = null;
      _replyToUserName = null;
      _replyTargetCommentId = null;
    });
    _commentController.clear();
    FocusScope.of(context).unfocus();
  }

  // 입력창으로 스크롤 및 포커스
  void _scrollToInputAndFocus() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    _commentFocusNode.requestFocus();
  }

  // 댓글 등록 (일반 댓글 + 대댓글 모드 지원)
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
    print('💬 대댓글 모드: $_isReplyMode');

    setState(() {
      _isSubmittingComment = true;
    });

    try {
      final bool success;
      
      if (_isReplyMode) {
        // 대댓글 작성
        success = await _commentService.addComment(
          widget.post.id,
          content,
          parentCommentId: _replyParentTopLevelId,
          replyToUserId: _replyToUserId,
          replyToUserNickname: _replyToUserName,
        );
        print('💬 대댓글 작성 완료 (parent: $_replyParentTopLevelId, replyTo: $_replyToUserId)');
      } else {
        // 일반 댓글 작성
        success = await _commentService.addComment(widget.post.id, content);
        print('💬 일반 댓글 작성 완료');
      }

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
        
        // 대댓글 모드 종료
        if (_isReplyMode) {
          _exitReplyMode();
        } else {
          // 일반 댓글인 경우에만 키보드 닫기
          FocusScope.of(context).unfocus();
        }

        // 게시글 정보 새로고침 (댓글 수 업데이트)
        print('💬 게시글 새로고침 시작');
        await _refreshPost();
        print('💬 게시글 새로고침 완료');
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.commentSubmitFailed)));
      }
    } catch (e) {
      print('❌ 댓글 작성 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')));
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
        SnackBar(content: Text(AppLocalizations.of(context)!.commentDeleted)),
      );
      await _refreshPost();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.commentDeleteFailed)),
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
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.commentDeleted)));

        // 게시글 정보 새로고침 (댓글 수 업데이트)
        await _refreshPost();
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.commentDeleteFailed)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')));
      }
    }
  }


  // 알림 시간 포맷팅
  String _formatNotificationTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    final locale = Localizations.localeOf(context).languageCode;

    if (difference.inDays > 0) {
      if (locale == 'ko') {
        return '${difference.inDays}${AppLocalizations.of(context)!.daysAgo}';
      } else {
        return '${difference.inDays}${difference.inDays == 1 ? ' day ago' : ' days ago'}';
      }
    } else if (difference.inHours > 0) {
      if (locale == 'ko') {
        return '${difference.inHours}${AppLocalizations.of(context)!.hoursAgo}';
      } else {
        return '${difference.inHours}${difference.inHours == 1 ? ' hour ago' : AppLocalizations.of(context)!.hoursAgo}';
      }
    } else if (difference.inMinutes > 0) {
      if (locale == 'ko') {
        return '${difference.inMinutes}${AppLocalizations.of(context)!.minutesAgo}';
      } else {
        return '${difference.inMinutes}${difference.inMinutes == 1 ? ' minute ago' : AppLocalizations.of(context)!.minutesAgo}';
      }
    } else {
      return AppLocalizations.of(context)!.justNow;
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
  
  /// 익명 게시글의 댓글 작성자 표시명 생성
  /// - 글쓴이: "글쓴이"
  /// - 다른 사람: "익명1", "익명2", ... (같은 사람은 같은 번호)
  String getCommentAuthorName(Comment comment, String? currentUserId) {
    // 익명이 아닌 게시글인 경우 실명 표시
    if (!_currentPost.isAnonymous) {
      return comment.authorNickname;
    }
    
    // 익명 게시글인 경우
    // 글쓴이인 경우
    if (comment.userId == _currentPost.userId) {
      return AppLocalizations.of(context)!.author;
    }
    
    // 다른 사람인 경우 익명 번호 할당
    if (!_anonymousUserMap.containsKey(comment.userId)) {
      _anonymousUserMap[comment.userId] = _anonymousUserMap.length + 1;
    }
    
    return '익명${_anonymousUserMap[comment.userId]}';
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
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white, // 상세 화면은 흰색 배경 유지
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)?.post ?? '게시글'),
        actions: [
          // 게시글 저장 버튼
          _isTogglingSave
              ? Container(
                margin: const EdgeInsets.all(10.0),
                width: 20,
                height: 20,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
              : IconButton(
                icon: Icon(
                  _isSaved ? Icons.bookmark : Icons.bookmark_border,
                  color: Colors.black87, // 검은색으로 통일
                ),
                tooltip: _isSaved ? (AppLocalizations.of(context)?.unsave ?? '저장 취소') : (AppLocalizations.of(context)?.savePost ?? '게시글 저장'),
                onPressed: _toggleSave,
              ),
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
                  tooltip: AppLocalizations.of(context)?.deletePost ?? '게시글 삭제',
                  onPressed: _deletePost,
                ),
        ],
      ),
      body: Column(
        children: [
          // 게시글 내용
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 작성자 정보 헤더 (인스타그램 스타일)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.s16,
                      vertical: DesignTokens.s8,
                    ),
                    child: Row(
                      children: [
                        // 프로필 사진 (인스타그램 크기)
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[200],
                          ),
                          child: (!_currentPost.isAnonymous && _currentPost.authorPhotoURL.isNotEmpty)
                              ? ClipOval(
                                  child: Image.network(
                                    _currentPost.authorPhotoURL,
                                    width: 32,
                                    height: 32,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Icon(
                                      Icons.person,
                                      color: Colors.grey[600],
                                      size: 18,
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.person,
                                  color: Colors.grey[600],
                                  size: 18,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 작성자 이름
                              Row(
                                children: [
                                  Text(
                                    _currentPost.isAnonymous ? '익명' : _currentPost.author,
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: WefillingColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  if (_currentPost.authorNationality.isNotEmpty)
                                    CountryFlagCircle(
                                      nationality: _currentPost.authorNationality,
                                      size: 16,
                                    ),
                                ],
                              ),
                              // 시간
                              Text(
                                _currentPost.getFormattedTime(context),
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 제목 (Pretendard Bold - 모바일 UI 원칙 준수)
                  if (_currentPost.title.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DesignTokens.s16,
                        DesignTokens.s8,
                        DesignTokens.s16,
                        8, // 제목 하단 간격 축소 (이미지 없을 때 본문과 가까이)
                      ),
                      child: Text(
                        _currentPost.title,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 22,
                          fontWeight: FontWeight.w700, // Bold
                          color: WefillingColors.textPrimary,
                          height: 1.3,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],

                  // 이미지 유무에 따라 레이아웃 분기
                  if (_currentPost.imageUrls.isNotEmpty) ...[
                    // === 이미지가 있는 경우: 제목 → 이미지 → 좋아요 → 본문 ===
                    // 게시글 이미지 (인스타그램 스타일 - 전체 너비, 좌우 여백 없음)
                    AspectRatio(
                      aspectRatio: 1.0, // 정사각형 비율 (인스타그램 스타일)
                      child: Stack(
                        children: [
                          PageView.builder(
                            controller: _imagePageController,
                            onPageChanged: (i) {
                              setState(() => _currentImageIndex = i);
                              _showPageIndicatorTemporarily(); // 페이지 변경 시 인디케이터 표시
                            },
                            itemCount: _currentPost.imageUrls.length,
                            itemBuilder: (context, index) {
                              final imageUrl = _currentPost.imageUrls[index];
                              return GestureDetector(
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    barrierColor: Colors.black87,
                                    builder: (context) => Dialog(
                                      backgroundColor: Colors.black,
                                      insetPadding: EdgeInsets.zero,
                                      child: Stack(
                                        children: [
                                          Center(
                                            child: InteractiveViewer(
                                              panEnabled: true,
                                              boundaryMargin: const EdgeInsets.all(20),
                                              minScale: 0.5,
                                              maxScale: 3.0,
                                              child: _buildRetryableImage(
                                                imageUrl,
                                                fit: BoxFit.contain,
                                                isFullScreen: true,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 50,
                                            right: 20,
                                            child: IconButton(
                                              onPressed: () => Navigator.pop(context),
                                              icon: const Icon(Icons.close, color: Colors.white, size: 28),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  width: double.infinity,
                                  height: double.infinity,
                                  color: Colors.black,
                                  child: _buildRetryableImage(
                                    imageUrl,
                                    fit: BoxFit.cover, // 이미지가 컨테이너를 완전히 채움
                                    isFullScreen: false,
                                  ),
                                ),
                              );
                            },
                          ),
                          // 이미지 인디케이터 (점 형식으로 하단 중앙에 표시)
                          if (_currentPost.imageUrls.length > 1 && _showPageIndicator)
                            Positioned(
                              bottom: 12,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: AnimatedOpacity(
                                  opacity: _showPageIndicator ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 300),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.55),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 점 인디케이터
                                    Row(
                                      children: List.generate(
                                        _currentPost.imageUrls.length,
                                        (i) => Container(
                                          width: 6,
                                          height: 6,
                                          margin: const EdgeInsets.symmetric(horizontal: 3),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: i == _currentImageIndex 
                                                ? Colors.white 
                                                : Colors.white.withOpacity(0.47),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // 숫자 표시
                                    Text(
                                      '${_currentImageIndex + 1}/${_currentPost.imageUrls.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    // 액션 버튼들 (이미지 바로 아래)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          // 좋아요 버튼
                          IconButton(
                            icon: Icon(
                              _isLiked ? Icons.favorite : Icons.favorite_border,
                              color: _isLiked ? Colors.red : Colors.black,
                              size: 24,
                            ),
                            onPressed: _isTogglingLike ? null : _toggleLike,
                            splashRadius: 20,
                          ),
                          
                          // DM 버튼 (본인 글이 아닌 경우만)
                          if (FirebaseAuth.instance.currentUser != null &&
                              _currentPost.userId != FirebaseAuth.instance.currentUser!.uid)
                            IconButton(
                              icon: Transform.rotate(
                                angle: -math.pi / 4, // 45도 기울임
                                child: const Icon(
                                  Icons.send_rounded,
                                  color: Colors.black,
                                  size: 24,
                                ),
                              ),
                              onPressed: _openDMFromDetail,
                              splashRadius: 20,
                            ),
                        ],
                      ),
                    ),

                    // 좋아요 수 표시
                    if (_currentPost.likes > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.s16,
                        ),
                        child: Text(
                          '좋아요 ${_currentPost.likes}개',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: WefillingColors.textPrimary,
                          ),
                        ),
                      ),

                    // 본문 영역 (이미지가 있을 때)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.s16,
                        vertical: DesignTokens.s12,
                      ),
                      child: Text(
                        _currentPost.content,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 16, // 15 → 16 (가독성 개선)
                          height: 1.6,
                          color: WefillingColors.textPrimary, // 검은색으로 변경 ✨
                          fontWeight: FontWeight.w500, // w400 → w500 (조금 더 굵게) ✨
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ] else ...[
                    // === 이미지가 없는 경우: 제목 → 본문 → 좋아요 ===
                    // 본문 영역 (제목 바로 아래 배치)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.s16,
                        vertical: 8, // 이미지 없을 때 간격 축소
                      ),
                      child: Text(
                        _currentPost.content,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 16, // 15 → 16 (가독성 개선)
                          height: 1.6,
                          color: WefillingColors.textPrimary, // 검은색으로 변경 ✨
                          fontWeight: FontWeight.w500, // w400 → w500 (조금 더 굵게) ✨
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 12), // 본문과 좋아요 사이 간격
                    
                    // 액션 버튼들 (본문 바로 아래)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          // 좋아요 버튼
                          IconButton(
                            icon: Icon(
                              _isLiked ? Icons.favorite : Icons.favorite_border,
                              color: _isLiked ? Colors.red : Colors.black,
                              size: 24,
                            ),
                            onPressed: _isTogglingLike ? null : _toggleLike,
                            splashRadius: 20,
                          ),
                          
                          // DM 버튼 (본인 글이 아닌 경우만)
                          if (FirebaseAuth.instance.currentUser != null &&
                              _currentPost.userId != FirebaseAuth.instance.currentUser!.uid)
                            IconButton(
                              icon: Transform.rotate(
                                angle: -math.pi / 4, // 45도 기울임
                                child: const Icon(
                                  Icons.send_rounded,
                                  color: Colors.black,
                                  size: 24,
                                ),
                              ),
                              onPressed: _openDMFromDetail,
                              splashRadius: 20,
                            ),
                        ],
                      ),
                    ),

                    // 좋아요 수 표시
                    if (_currentPost.likes > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.s16,
                        ),
                        child: Text(
                          '좋아요 ${_currentPost.likes}개',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: WefillingColors.textPrimary,
                          ),
                        ),
                      ),
                  ],

                  // 댓글 섹션 타이틀 (간격 조정)
                  SizedBox(height: _currentPost.imageUrls.isEmpty ? 16 : 24),
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
                        Text(
                          AppLocalizations.of(context)!.comments,
                          style: const TextStyle(
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
                            '${AppLocalizations.of(context)!.loadingComments}: ${snapshot.error}',
                          ),
                        );
                      }

                      final allComments = snapshot.data ?? [];
                      final currentUser = FirebaseAuth.instance.currentUser;

                      if (allComments.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Center(child: Text(AppLocalizations.of(context)!.firstCommentPrompt)),
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
                            isAnonymousPost: _currentPost.isAnonymous,
                            getDisplayName: (comment) => getCommentAuthorName(comment, currentUser?.uid),
                            isReplyTarget: _replyTargetCommentId == comment.id,
                            onReplyTap: () {
                              // 최상위 댓글에 답글 달기
                              _enterReplyMode(
                                parentTopId: comment.id,
                                replyToUserId: comment.userId,
                                replyToUserName: getCommentAuthorName(comment, currentUser?.uid),
                                targetCommentId: comment.id,
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 댓글 입력 영역 (하단 고정, overflow 방지)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 대댓글 모드 상단 바 (미니멀 디자인)
                  if (_isReplyMode)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 10.0,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[50], // 매우 연한 회색 배경
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey[300]!, // 연한 회색 테두리
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.subdirectory_arrow_right, // 더 명확한 대댓글 아이콘
                            size: 18,
                            color: Colors.grey[700], // 검은색 계열
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)!.replyingTo(_replyToUserName ?? ''),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800], // 검은색 계열
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: _exitReplyMode,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  // 입력창
                  Padding(
                    padding: EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      top: 8.0,
                      bottom: MediaQuery.of(context).viewInsets.bottom > 0 
                          ? 8.0  // 키보드가 올라온 경우
                          : MediaQuery.of(context).padding.bottom + 8.0,  // 하단 safe area 고려
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentController,
                            focusNode: _commentFocusNode,
                            enabled: isLoggedIn,
                            decoration: InputDecoration(
                              hintText: isLoggedIn 
                                  ? (_isReplyMode 
                                      ? AppLocalizations.of(context)!.writeReplyHint 
                                      : AppLocalizations.of(context)!.enterComment)
                                  : AppLocalizations.of(context)!.loginToComment,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: _isReplyMode 
                                    ? BorderSide(color: Colors.grey[400]!, width: 1.5) // 대댓글 모드일 때 테두리 표시
                                    : BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: _isReplyMode 
                                    ? BorderSide(color: Colors.grey[300]!, width: 1.5)
                                    : BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: _isReplyMode 
                                    ? BorderSide(color: Colors.blue[600]!, width: 2) // 포커스 시 파란색
                                    : BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.grey[50], // 더 밝은 회색 배경으로 통일
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              isDense: true, // 높이 최소화
                            ),
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.send,
                            onSubmitted: isLoggedIn ? (_) => _submitComment() : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                      // 입력 전송 버튼 - DM 아이콘과 구분되는 상향 화살표 버튼
                      (isLoggedIn)
                          ? (_isSubmittingComment
                              ? const SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : InkWell(
                                  onTap: _submitComment,
                                  customBorder: const CircleBorder(),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.blue[600],
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.arrow_upward_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ))
                          : const SizedBox.shrink(),
                      ],
                    ),
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
