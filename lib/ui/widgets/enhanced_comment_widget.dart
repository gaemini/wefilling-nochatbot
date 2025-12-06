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
import '../../services/report_service.dart';
import '../../design/tokens.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../services/dm_service.dart';
import '../../screens/dm_chat_screen.dart';
import '../../utils/logger.dart';

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
    final TextEditingController reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          elevation: 8,
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          title: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.report_gmailerrorred_outlined, 
                  color: Color(0xFFEF4444), 
                  size: 18
                ),
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)!.report,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.reportConfirm,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  color: Color(0xFF111827),
                ),
                decoration: InputDecoration(
                  labelText: Localizations.localeOf(context).languageCode == 'ko' ? '신고 사유' : 'Reason',
                  hintText: Localizations.localeOf(context).languageCode == 'ko' 
                      ? '신고 사유를 입력해주세요 (예: 욕설, 비방)' 
                      : 'Please enter the reason (e.g., abuse, spam)',
                  labelStyle: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                  hintStyle: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    color: Color(0xFF9CA3AF),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300, width: 1),
                      ),
                      backgroundColor: Colors.white,
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.cancel,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.report,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      final reason = reasonController.text.trim();
      if (reason.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('신고 사유를 입력해주세요.')),
        );
        return;
      }

      await _submitReport(reason);
    }
  }

  /// 신고 제출 (Firestore 저장)
  Future<void> _submitReport(String reason) async {
    final success = await ReportService.reportContent(
      reportedUserId: widget.comment.userId,
      targetType: 'comment',
      targetId: widget.comment.id,
      reason: reason,
      description: widget.comment.content, // 댓글 내용을 상세 설명으로 저장
      targetTitle: '댓글 신고',
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.reportSubmitted)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.reportError)),
        );
      }
    }
  }

  /// 댓글 삭제 확인 다이얼로그
  Future<void> _showDeleteConfirmDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          elevation: 8,
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          title: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.delete_outline, 
                  color: Color(0xFFEF4444), 
                  size: 18
                ),
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)!.delete,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16), // 하단 여백 추가
            child: Text(
              _getDeleteConfirmMessage(context),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300, width: 1),
                      ),
                      backgroundColor: Colors.white,
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.cancel,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w700, // w600 → w700 (bold)
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.delete,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w700, // w600 → w700 (bold)
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      widget.onDeleteComment?.call(widget.comment.id);
    }
  }

  /// 언어별 삭제 확인 메시지 반환
  String _getDeleteConfirmMessage(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    if (locale == 'ko') {
      return '댓글을 삭제하시겠습니까?\n삭제된 댓글은 복구할 수 없습니다.';
    } else {
      return 'Are you sure you want to delete this comment?\nDeleted comments cannot be recovered.';
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
      Logger.log('🔍 DM 대상 확인 (댓글):');
      Logger.log('  - comment.userId: ${widget.comment.userId}');
      Logger.log('  - comment.author: ${widget.comment.authorNickname}');
      
      // Firebase Auth UID 형식 검증 (28자 영숫자)
      final uidPattern = RegExp(r'^[a-zA-Z0-9]{28}$');
      if (!uidPattern.hasMatch(widget.comment.userId)) {
        Logger.log('❌ 잘못된 userId 형식: ${widget.comment.userId}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.reportError),
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
      
      Logger.log('✅ DM conversation ID 생성됨: $conversationId');

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
      Logger.error('❌ DM 열기 오류: $e');
      Logger.error('오류 타입: ${e.runtimeType}');
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
      Logger.error('닉네임 조회 오류: $e');
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
      Logger.error('댓글 좋아요 토글 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')),
        );
      }
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
        left: (widget.comment.depth * 20.0) + (widget.comment.depth == 0 ? 16.0 : 0.0),
        right: widget.comment.depth == 0 ? 16.0 : 0.0,
        bottom: 16, // 댓글 간 간격
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 프로필 이미지
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[200],
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
                        size: 18,
                        color: Colors.grey[500],
                      ),
                    ),
                  )
                : Icon(
                    Icons.person,
                    size: 18,
                    color: Colors.grey[500],
                  ),
          ),
          const SizedBox(width: 10),
          
          // 댓글 내용 영역
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더: 작성자 이름, 시간, 메뉴
                Row(
                  children: [
                    // 작성자 이름
                    FutureBuilder<String>(
                      future: widget.isAnonymousPost
                          ? Future.value(widget.getDisplayName?.call(widget.comment) ?? AppLocalizations.of(context)!.anonymous)
                          : _getCurrentNickname(widget.comment.userId),
                      builder: (context, snapshot) {
                        final displayName = snapshot.data ?? 
                            (widget.getDisplayName?.call(widget.comment) ?? widget.comment.authorNickname);
                        return Text(
                          displayName,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                    
                    // 시간
                    Text(
                      widget.comment.getFormattedTime(context),
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF9CA3AF), // textHint/Tertiary color
                      ),
                    ),
                    
                    const Spacer(),
                    
                    // 삭제 아이콘 (내 댓글인 경우)
                    if (isMyComment)
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey[500]),
                          onPressed: () {
                            _showDeleteConfirmDialog();
                          },
                          tooltip: '댓글 삭제',
                        ),
                      )
                    else
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.more_horiz, size: 18, color: Colors.grey[500]),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 4,
                          color: Colors.white,
                          surfaceTintColor: Colors.white,
                          offset: const Offset(0, 8),
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
                                height: 48,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6366F1).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.chat_bubble_outline,
                                        size: 16,
                                        color: Color(0xFF6366F1),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      AppLocalizations.of(context)!.directMessage,
                                      style: const TextStyle(
                                        fontFamily: 'Pretendard',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(height: 1),
                              PopupMenuItem<String>(
                                value: 'report',
                                height: 48,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.report_gmailerrorred_outlined,
                                        size: 16,
                                        color: Color(0xFFEF4444),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      AppLocalizations.of(context)!.report,
                                      style: const TextStyle(
                                        fontFamily: 'Pretendard',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFEF4444),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ];
                          },
                        ),
                      ),
                  ],
                ),
                
                const SizedBox(height: 2),
                
                // 답글 대상 표시 (대댓글인 경우)
                if (widget.comment.replyToUserNickname != null && 
                    widget.comment.replyToUserId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '@${widget.comment.replyToUserNickname} ',
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6366F1), // BrandColors.primary
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 댓글 내용
                Linkify(
                  onOpen: (link) async {
                    final uri = Uri.parse(link.url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  text: widget.comment.content,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF1F2937), // textSecondary
                    height: 1.5,
                  ),
                  linkStyle: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF6366F1), // BrandColors.primary
                    decoration: TextDecoration.underline,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // 액션 버튼 (좋아요, 답글 달기)
                Row(
                  children: [
                    // 좋아요 버튼
                    InkWell(
                      onTap: _toggleLike,
                      borderRadius: BorderRadius.circular(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            size: 14,
                            color: isLiked ? Colors.red : const Color(0xFF9CA3AF),
                          ),
                          const SizedBox(width: 4),
                          if (widget.comment.likeCount > 0)
                            Text(
                              '${widget.comment.likeCount}',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isLiked ? Colors.red : const Color(0xFF9CA3AF),
                              ),
                            )
                          else
                            Text(
                              '좋아요', // 텍스트로 '좋아요' 표시 (디자인 시안에 따라 조정 가능)
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(width: 16),
                    
                    // 답글 버튼 (원댓글에만 표시)
                    if (widget.comment.depth == 0)
                      InkWell(
                        onTap: widget.onReplyTap,
                        borderRadius: BorderRadius.circular(4),
                        child: Text(
                          '답글 달기',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                  ],
                ),

                // 답글 더보기/숨기기 (답글이 있는 경우)
                if (widget.replies.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => setState(() => _showReplies = !_showReplies),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 24,
                          height: 1,
                          color: const Color(0xFFD1D5DB), // 구분선
                          margin: const EdgeInsets.only(right: 8),
                        ),
                        Text(
                          _showReplies 
                              ? '답글 숨기기' 
                              : '답글 ${widget.replies.length}개 보기',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // 답글 목록
                  if (_showReplies) ...[
                    const SizedBox(height: 12),
                    ...widget.replies.map((reply) => EnhancedCommentWidget(
                      comment: reply,
                      replies: const [], // 대댓글의 대댓글은 지원하지 않음
                      postId: widget.postId,
                      onDeleteComment: widget.onDeleteComment,
                      isAnonymousPost: widget.isAnonymousPost,
                      getDisplayName: widget.getDisplayName,
                      isReplyTarget: widget.parentTopLevelCommentId != null,
                      parentTopLevelCommentId: widget.comment.id,
                      onReplyTap: widget.onReplyTap, // 대댓글에는 답글 버튼 미표시
                    )).toList(),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
