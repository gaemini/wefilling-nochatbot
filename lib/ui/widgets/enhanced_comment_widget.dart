// lib/ui/widgets/enhanced_comment_widget.dart
// 확장된 댓글 위젯 - 대댓글과 좋아요 기능 지원
// 계층적 댓글 표시 및 인터랙션 제공

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/comment.dart';
import '../../services/comment_service.dart';
import '../../design/tokens.dart';
import '../../design/theme.dart';

class EnhancedCommentWidget extends StatefulWidget {
  final Comment comment;
  final List<Comment> replies;
  final String postId;
  final VoidCallback? onReplyTap;
  final Function(String)? onDeleteComment;
  final Function(String, String, String)? onReplySubmit;
  final bool isAnonymousPost; // 익명 게시글 여부
  final String Function(Comment)? getDisplayName; // 댓글 작성자 표시명 함수

  const EnhancedCommentWidget({
    super.key,
    required this.comment,
    required this.replies,
    required this.postId,
    this.onReplyTap,
    this.onDeleteComment,
    this.onReplySubmit,
    this.isAnonymousPost = false,
    this.getDisplayName,
  });

  @override
  State<EnhancedCommentWidget> createState() => _EnhancedCommentWidgetState();
}

class _EnhancedCommentWidgetState extends State<EnhancedCommentWidget> {
  final CommentService _commentService = CommentService();
  final TextEditingController _replyController = TextEditingController();
  bool _isReplying = false;
  bool _isSubmittingReply = false;
  bool _showReplies = true;
  String? _currentNickname; // 캐시된 현재 닉네임

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  // 사용자의 현재 닉네임을 실시간으로 조회
  Future<String> _getCurrentNickname(String userId) async {
    // 이미 캐시된 닉네임이 있으면 반환
    if (_currentNickname != null) {
      return _currentNickname!;
    }
    
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
      if (userDoc.exists) {
        final data = userDoc.data();
        final nickname = data?['nickname'] ?? widget.comment.authorNickname;
        // 캐시에 저장
        if (mounted) {
          setState(() {
            _currentNickname = nickname;
          });
        }
        return nickname;
      }
    } catch (e) {
      print('닉네임 조회 오류: $e');
    }
    // 조회 실패 시 댓글에 저장된 닉네임 반환
    return widget.comment.authorNickname;
  }

  // 좋아요 토글
  Future<void> _toggleLike() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인이 필요합니다.')),
        );
      }
      return;
    }

    try {
      // 댓글 좋아요 토글 실행
      final success = await _commentService.toggleCommentLike(widget.comment.id, user.uid);
      
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('좋아요 업데이트에 실패했습니다.')),
        );
      }
    } catch (e) {
      print('댓글 좋아요 토글 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류가 발생했습니다: $e')),
        );
      }
    }
  }

  // 답글 제출
  Future<void> _submitReply() async {
    final content = _replyController.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _isSubmittingReply = true;
    });

    try {
      // 최신 닉네임 사용
      final currentNickname = _currentNickname ?? await _getCurrentNickname(widget.comment.userId);
      
      final success = await _commentService.addComment(
        widget.postId,
        content,
        parentCommentId: widget.comment.id,
        replyToUserId: widget.comment.userId,
        replyToUserNickname: currentNickname,
      );

      if (success && mounted) {
        _replyController.clear();
        setState(() {
          _isReplying = false;
        });
      }
    } catch (e) {
      print('답글 작성 오류: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingReply = false;
        });
      }
    }
  }

  /// 댓글 깊이에 따른 배경색 반환
  Color _getCommentBackgroundColor(ThemeData theme) {
    if (widget.comment.depth == 0) {
      // 최상위 댓글: 기본 카드 색상
      return theme.cardColor;
    } else {
      // 대댓글: 지정된 노란색 100% 적용
      return const Color(0xFFF9F871);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = FirebaseAuth.instance.currentUser;
    final isMyComment = currentUser?.uid == widget.comment.userId;
    final isLiked = currentUser != null && widget.comment.isLikedBy(currentUser.uid);

    return Container(
      margin: EdgeInsets.only(
        left: widget.comment.depth * 24.0, // 들여쓰기
        bottom: 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 대댓글용 세로선
          if (widget.comment.depth > 0) ...[
            Container(
              width: 3,
              height: 60, // 카드 높이에 맞춤
              margin: const EdgeInsets.only(right: 8, top: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
          
          // 댓글 내용
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 댓글 카드
                Card(
            elevation: 1,
            color: _getCommentBackgroundColor(theme),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: widget.comment.depth > 0 
                    ? theme.colorScheme.primary.withOpacity(0.15)
                    : Colors.transparent,
                width: widget.comment.depth > 0 ? 0.5 : 0,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 작성자 정보
                  Row(
                    children: [
                      // 프로필 이미지
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[300],
                        ),
                        child: (!widget.isAnonymousPost && widget.comment.authorPhotoUrl.isNotEmpty)
                            ? ClipOval(
                                child: Image.network(
                                  widget.comment.authorPhotoUrl,
                                  width: 32,
                                  height: 32,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.person,
                                    size: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.person,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                      ),
                      const SizedBox(width: 8),
                      
                      // 작성자 이름과 시간
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // 실시간 닉네임 표시
                                FutureBuilder<String>(
                                  future: widget.isAnonymousPost
                                      ? Future.value(widget.getDisplayName?.call(widget.comment) ?? '익명')
                                      : _getCurrentNickname(widget.comment.userId),
                                  builder: (context, snapshot) {
                                    final displayName = snapshot.data ?? 
                                        (widget.getDisplayName?.call(widget.comment) ?? widget.comment.authorNickname);
                                    return Text(
                                      displayName,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                  },
                                ),
                                if (widget.comment.replyToUserNickname != null && 
                                    widget.comment.replyToUserId != null) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.reply, size: 12, color: Colors.grey),
                                  const SizedBox(width: 2),
                                  // 답글 대상도 익명 처리
                                  Builder(
                                    builder: (context) {
                                      if (widget.isAnonymousPost && widget.getDisplayName != null) {
                                        // 익명 게시글인 경우: replyToUserId로 Comment 객체를 만들어서 getDisplayName 호출
                                        final replyTargetComment = Comment(
                                          id: '',
                                          postId: widget.postId,
                                          userId: widget.comment.replyToUserId!,
                                          authorNickname: widget.comment.replyToUserNickname!,
                                          authorPhotoUrl: '',
                                          content: '',
                                          createdAt: DateTime.now(),
                                        );
                                        final displayName = widget.getDisplayName!(replyTargetComment);
                                        return Text(
                                          displayName,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        );
                                      } else {
                                        // 일반 게시글인 경우: 실제 닉네임 표시
                                        return Text(
                                          widget.comment.replyToUserNickname!,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              widget.comment.getFormattedTime(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // 삭제 버튼 (본인 댓글만)
                      if (isMyComment)
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18),
                          onPressed: () => widget.onDeleteComment?.call(widget.comment.id),
                          color: Colors.grey[600],
                        ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // 댓글 내용 (URL 클릭 가능)
                  Linkify(
                    onOpen: (link) async {
                      final uri = Uri.parse(link.url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('링크를 열 수 없습니다: ${link.url}')),
                          );
                        }
                      }
                    },
                    text: widget.comment.content,
                    style: theme.textTheme.bodyMedium,
                    linkStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // 액션 버튼들
                  Row(
                    children: [
                      // 좋아요 버튼
                      InkWell(
                        onTap: _toggleLike,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isLiked ? Icons.favorite : Icons.favorite_border,
                                size: 16,
                                color: isLiked ? Colors.red : Colors.grey[600],
                              ),
                              if (widget.comment.likeCount > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '${widget.comment.likeCount}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 8),
                      
                      // 답글 버튼 (원댓글에만 표시)
                      if (widget.comment.depth == 0)
                        InkWell(
                          onTap: () => setState(() => _isReplying = !_isReplying),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.reply, size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text(
                                  '답글',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      
                      // 답글 수 표시
                      if (widget.replies.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => setState(() => _showReplies = !_showReplies),
                          child: Text(
                            '답글 ${widget.replies.length}개 ${_showReplies ? '숨기기' : '보기'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // 답글 입력창
          if (_isReplying) ...[
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.only(left: 24),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _replyController,
                    decoration: InputDecoration(
                      hintText: '${_currentNickname ?? widget.comment.authorNickname}님에게 답글...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    maxLines: 3,
                    minLines: 1,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _isReplying = false),
                        child: Text('취소'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isSubmittingReply ? null : _submitReply,
                        child: _isSubmittingReply
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text('답글 작성'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          
                // 답글 목록
                if (_showReplies && widget.replies.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...widget.replies.map((reply) => EnhancedCommentWidget(
                    comment: reply,
                    replies: const [], // 대댓글의 대댓글은 지원하지 않음
                    postId: widget.postId,
                    onDeleteComment: widget.onDeleteComment,
                    isAnonymousPost: widget.isAnonymousPost,
                    getDisplayName: widget.getDisplayName,
                  )).toList(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
