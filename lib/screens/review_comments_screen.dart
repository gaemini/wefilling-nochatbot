// lib/screens/review_comments_screen.dart
// 후기 댓글 화면

import 'package:flutter/material.dart';
import '../models/review_post.dart';
import '../services/comment_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/comment.dart';
import '../l10n/app_localizations.dart';

class ReviewCommentsScreen extends StatefulWidget {
  final ReviewPost review;

  const ReviewCommentsScreen({
    Key? key,
    required this.review,
  }) : super(key: key);

  @override
  State<ReviewCommentsScreen> createState() => _ReviewCommentsScreenState();
}

class _ReviewCommentsScreenState extends State<ReviewCommentsScreen> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  final CommentService _commentService = CommentService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // 텍스트 변경 시 버튼 상태 업데이트
    _commentController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return GestureDetector(
      onTap: () {
        // 키보드 밖을 탭하면 키보드 닫기
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true, // 키보드가 나타날 때 화면 크기 조정
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
          ),
          title: Text(
            l10n?.comments ?? "",
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder(
                stream: _commentService.getCommentsWithReplies(widget.review.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('${l10n?.loadingComments ?? ""}: ${snapshot.error}'),
                    );
                  }

                  final comments = (snapshot.data ?? []) as List<Comment>;
                  if (comments.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mode_comment_outlined, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(l10n?.noCommentsYet ?? "", style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                          const SizedBox(height: 8),
                          Text(l10n?.beFirstToComment ?? "", style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                        ],
                      ),
                    );
                  }

                  // 간단 목록 렌더 (상세 위젯은 차후 확장)
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: comments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final c = comments[index];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 작성자 아바타
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.grey[300],
                            backgroundImage: c.authorPhotoUrl.isNotEmpty
                                ? NetworkImage(c.authorPhotoUrl)
                                : null,
                            child: c.authorPhotoUrl.isEmpty
                                ? Icon(Icons.person, color: Colors.grey[600], size: 16)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          // 본문 카드
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c.authorNickname,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        c.getFormattedTime(context),
                                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    c.content,
                                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            
            // 댓글 입력창
            _buildCommentInput(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentInput(AppLocalizations? l10n) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        bottom: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 40,
                  maxHeight: 120,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _commentController,
                    focusNode: _commentFocusNode,
                    maxLines: null,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: l10n?.writeComment ?? "",
                      hintStyle: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isSubmitting ? null : _handleSubmitComment,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _isSubmitting || _commentController.text.trim().isEmpty
                      ? Colors.grey[300]
                      : Colors.blue,
                  shape: BoxShape.circle,
                ),
                child: _isSubmitting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(
                        Icons.arrow_upward_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSubmitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.loginRequired ?? ""), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final ok = await _commentService.addComment(
        widget.review.id,
        text,
        reviewOwnerUserId: widget.review.authorId,
        reviewTitle: widget.review.meetupTitle,
      );

      if (mounted) {
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.commentSubmitFailed ?? ""), backgroundColor: Colors.red),
          );
        } else {
          _commentController.clear();
          _commentFocusNode.unfocus();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.commentSubmitFailed ?? ""), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
}

