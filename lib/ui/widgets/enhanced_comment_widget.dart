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
import '../../l10n/app_localizations.dart';
import '../../services/dm_service.dart';
import '../../screens/dm_chat_screen.dart';

class EnhancedCommentWidget extends StatefulWidget {
  final Comment comment;
  final List<Comment> replies;
  final String postId;
  final VoidCallback? onReplyTap;
  final Function(String)? onDeleteComment;
  final Function(String, String, String)? onReplySubmit;
  final bool isAnonymousPost; // 익명 게시글 여부
  final String Function(Comment)? getDisplayName; // 댓글 작성자 표시명 함수
  final bool isReplyTarget; // 현재 하이라이트 대상인지
  final String? parentTopLevelCommentId; // 최상위 댓글 ID (대댓글 작성용)

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
    this.isReplyTarget = false,
    this.parentTopLevelCommentId,
  });

  @override
  State<EnhancedCommentWidget> createState() => _EnhancedCommentWidgetState();
}

class _EnhancedCommentWidgetState extends State<EnhancedCommentWidget> {
  final CommentService _commentService = CommentService();
  final DMService _dmService = DMService();
  bool _showReplies = true;
  String? _currentNickname; // 캐시된 현재 닉네임

  @override
  void dispose() {
    super.dispose();
  }

  /// 신고 다이얼로그
  Future<void> _showReportDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.report_gmailerrorred_outlined, color: Colors.red, size: 22),
              SizedBox(width: 8),
              Text('신고'),
            ],
          ),
          content: const Text('해당 댓글을 신고하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('신고'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      // 실제 신고 로직 연동 전까지 안내만 표시
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('신고가 접수되었습니다')),
      );
    }
  }

  /// 댓글 작성자에게 DM 열기
  Future<void> _openDMToCommentAuthor() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.loginRequired ?? "")),
        );
      }
      return;
    }

    // 본인에게는 DM 불가
    if (widget.comment.userId == currentUser.uid) {
      return;
    }

    try {
      // comment.userId가 올바른 Firebase UID인지 확인
      print('🔍 DM 대상 확인 (댓글):');
      print('  - comment.userId: ${widget.comment.userId}');
      print('  - comment.author: ${widget.comment.authorNickname}');
      
      // Firebase Auth UID 형식 검증 (28자 영숫자)
      final uidPattern = RegExp(r'^[a-zA-Z0-9]{28}$');
      if (!uidPattern.hasMatch(widget.comment.userId)) {
        print('❌ 잘못된 userId 형식: ${widget.comment.userId}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('댓글 작성자 정보가 올바르지 않습니다'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      final conversationId = await _dmService.prepareConversationId(
        widget.comment.userId,
        isOtherUserAnonymous: false,
        postId: widget.postId,
      );
      
      print('✅ DM conversation ID 생성됨: $conversationId');

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DMChatScreen(
              conversationId: conversationId,
              otherUserId: widget.comment.userId,
            ),
          ),
        );
      }
    } catch (e) {
      print('❌ DM 열기 오류: $e');
      print('오류 타입: ${e.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.cannotSendDM ?? "")),
        );
      }
    }
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
      } else {
        // 사용자 문서가 없으면 탈퇴한 계정으로 표시
        final deletedText = AppLocalizations.of(context)!.deletedAccount ?? "";
        if (mounted) {
          setState(() {
            _currentNickname = deletedText;
          });
        }
        return deletedText;
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
          SnackBar(content: Text(AppLocalizations.of(context)!.loginRequired ?? "")),
        );
      }
      return;
    }

    try {
      // 댓글 좋아요 토글 실행
      final success = await _commentService.toggleCommentLike(widget.comment.id, user.uid);
      
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.commentLikeFailed ?? "")),
        );
      }
    } catch (e) {
      print('댓글 좋아요 토글 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')),
        );
      }
    }
  }

  /// 댓글 배경색 반환 (깊이 고려)
  Color _getCommentBackgroundColor(ThemeData theme) {
    if (widget.comment.depth == 0) {
      // 최상위 댓글: 기본 카드 색상 (흰색)
      return theme.cardColor;
    } else {
      // 대댓글: 약간 더 진한 회색 배경으로 구분 강화
      return Colors.grey[100]!; // grey[50] → grey[100]
    }
  }
  
  /// 하이라이트용 BoxDecoration 반환
  BoxDecoration _getCardDecoration(ThemeData theme) {
    if (widget.isReplyTarget) {
      // 하이라이트 대상: 파란색 테두리 (전체 UI와 조화)
      return BoxDecoration(
        color: _getCommentBackgroundColor(theme),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blue[400]!, // 파란색 테두리
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue[100]!.withOpacity(0.3), // 연한 파란색 그림자
            blurRadius: 8,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      );
    } else {
      // 일반 상태
      return BoxDecoration(
        color: _getCommentBackgroundColor(theme),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.comment.depth > 0 
              ? Colors.grey[400]! // 더 진한 회색 테두리 (300 → 400)
              : Colors.transparent,
          width: widget.comment.depth > 0 ? 1.5 : 0, // 테두리 두께 증가 (1 → 1.5)
        ),
        // 대댓글에 미세한 그림자 추가
        boxShadow: widget.comment.depth > 0 
            ? [
                BoxShadow(
                  color: Colors.grey[300]!.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      );
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
        left: widget.comment.depth * 28.0, // 들여쓰기 증가 (24 → 28)
        bottom: 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 대댓글용 세로선 (더 굵고 진하게)
          if (widget.comment.depth > 0) ...[
            Container(
              width: 4, // 두께 증가 (3 → 4)
              height: 60,
              margin: const EdgeInsets.only(right: 10, top: 8), // 간격 증가 (8 → 10)
              decoration: BoxDecoration(
                color: Colors.blue[300]!, // 더 진한 파란색
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
                Container(
            decoration: _getCardDecoration(theme),
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
                                Flexible(
                                  child: FutureBuilder<String>(
                                    future: widget.isAnonymousPost
                                        ? Future.value(widget.getDisplayName?.call(widget.comment) ?? '익명')
                                        : _getCurrentNickname(widget.comment.userId),
                                    builder: (context, snapshot) {
                                      final displayName = snapshot.data ?? 
                                          (widget.getDisplayName?.call(widget.comment) ?? widget.comment.authorNickname);
                                      return Text(
                                        displayName,
                                        style: const TextStyle(
                                          fontFamily: 'Pretendard',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF111827),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      );
                                    },
                                  ),
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
                                          style: const TextStyle(
                                            fontFamily: 'Pretendard',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF5865F2),
                                          ),
                                        );
                                      } else {
                                        // 일반 게시글인 경우: 실제 닉네임 표시
                                        return Text(
                                          widget.comment.replyToUserNickname!,
                                          style: const TextStyle(
                                            fontFamily: 'Pretendard',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF5865F2),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              widget.comment.getFormattedTime(context),
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // 케밥 메뉴 (댓글별 액션) - 내가 쓴 댓글일 때만 삭제 버튼 표시
                      if (isMyComment)
                        // 내가 쓴 댓글: 삭제 버튼만
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey[700]),
                          onPressed: () {
                            widget.onDeleteComment?.call(widget.comment.id);
                          },
                          tooltip: '댓글 삭제',
                        )
                      else
                        // 다른 사람 댓글: DM과 신고 버튼
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, size: 18, color: Colors.grey[700]),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          onSelected: (value) {
                            switch (value) {
                              case 'dm':
                                _openDMToCommentAuthor();
                                break;
                              case 'report':
                                _showReportDialog();
                                break;
                            }
                          },
                          itemBuilder: (context) {
                            return [
                              PopupMenuItem<String>(
                                value: 'dm',
                                child: Row(
                                  children: [
                                    const Icon(Icons.chat_bubble_outline, size: 18),
                                    const SizedBox(width: 12),
                                    Text('Direct message'),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem<String>(
                                value: 'report',
                                child: Row(
                                  children: [
                                    const Icon(Icons.report_gmailerrorred_outlined, size: 18),
                                    const SizedBox(width: 12),
                                    const Text('신고'),
                                  ],
                                ),
                              ),
                            ];
                          },
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
                            SnackBar(content: Text('${AppLocalizations.of(context)!.error}: ${link.url}')),
                          );
                        }
                      }
                    },
                    text: widget.comment.content,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF111827),
                      height: 1.5,
                    ),
                    linkStyle: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF5865F2),
                      decoration: TextDecoration.underline,
                      height: 1.5,
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
                                color: isLiked ? Colors.red : const Color(0xFF6B7280),
                              ),
                              if (widget.comment.likeCount > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '${widget.comment.likeCount}',
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF6B7280),
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
                          onTap: widget.onReplyTap,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.reply, size: 16, color: Color(0xFF6B7280)),
                                const SizedBox(width: 4),
                                Text(
                                  AppLocalizations.of(context)!.reply,
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF6B7280),
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
                            '${AppLocalizations.of(context)!.repliesCount(widget.replies.length)} ${_showReplies ? (AppLocalizations.of(context)!.hideReplies ?? "") : AppLocalizations.of(context)!.showReplies}',
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF5865F2),
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
                    isReplyTarget: widget.parentTopLevelCommentId != null, // 대댓글도 하이라이트 가능하도록 유지 (상위 전달)
                    parentTopLevelCommentId: widget.comment.id, // 최상위 댓글 ID 전달
                    onReplyTap: widget.onReplyTap, // 대댓글에는 답글 버튼을 표시하지 않으므로 사용되지 않음
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
