// lib/screens/review_comments_screen.dart
// 후기 댓글 화면

import 'package:flutter/material.dart';
import '../models/review_post.dart';
import '../services/comment_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/comment.dart';
import '../l10n/app_localizations.dart';
import '../services/user_info_cache_service.dart';
import '../utils/responsive_helper.dart';

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
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          scrolledUnderElevation: 0,
          centerTitle: true,
          toolbarHeight: context.rh(56, min: 54, max: 60),
          leadingWidth: 48,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_rounded,
              size: context.ri(22).clamp(21, 24).toDouble(),
              color: const Color(0xFF111827),
            ),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          title: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: Text(
              l10n?.comments ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                color: const Color(0xFF111827),
                fontSize: context.rf(18).clamp(16, 19).toDouble(),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder(
                  stream:
                      _commentService.getCommentsWithReplies(widget.review.id),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            l10n?.loadingComments ?? '',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: ['NotoSansKR'],
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF667085),
                            ),
                          ),
                        ),
                      );
                    }

                    final comments = (snapshot.data ?? []) as List<Comment>;
                    if (comments.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.mode_comment_outlined,
                              size: 40,
                              color: Color(0xFF98A2B3),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              l10n?.noCommentsYet ?? '',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: ['NotoSansKR'],
                                fontSize: 15,
                                color: Color(0xFF475467),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              l10n?.beFirstToComment ?? '',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: ['NotoSansKR'],
                                fontSize: 13,
                                color: Color(0xFF98A2B3),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        _horizontalPadding,
                        10,
                        _horizontalPadding,
                        18,
                      ),
                      itemCount: comments.length,
                      separatorBuilder: (_, __) => const Padding(
                        padding: EdgeInsets.only(left: 42),
                        child: Divider(height: 1, color: Color(0xFFF1F3F5)),
                      ),
                      itemBuilder: (context, index) {
                        final c = comments[index];
                        if (c.userId.isEmpty || c.userId == 'deleted') {
                          return _buildCommentRow(
                            context,
                            c,
                            displayName:
                                l10n?.deletedAccount ?? 'Deleted Account',
                            photoURL: '',
                          );
                        }
                        final cache = UserInfoCacheService();
                        return StreamBuilder<DMUserInfo?>(
                          stream: cache.watchUserInfo(c.userId),
                          initialData: cache.getCachedUserInfo(c.userId),
                          builder: (context, snapshot) {
                            final latest = snapshot.data;
                            final isDeleted = latest?.isDeletedAccount == true;
                            return _buildCommentRow(
                              context,
                              c,
                              displayName: isDeleted
                                  ? (l10n?.deletedAccount ?? 'Deleted Account')
                                  : ((latest?.nickname ?? '').trim().isNotEmpty
                                      ? latest!.nickname
                                      : c.authorNickname),
                              photoURL: isDeleted
                                  ? ''
                                  : ((latest?.photoURL ?? '').trim().isNotEmpty
                                      ? latest!.photoURL
                                      : c.authorPhotoUrl),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              _buildCommentInput(l10n),
            ],
          ),
        ),
      ),
    );
  }

  double get _horizontalPadding {
    final width = MediaQuery.sizeOf(context).width;
    return width < 360 ? 14 : (width < 430 ? 16 : 20);
  }

  Widget _buildCommentRow(
    BuildContext context,
    Comment comment, {
    required String displayName,
    required String photoURL,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: context.rs(12).clamp(10, 14).toDouble(),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: context.rs(17).clamp(16, 19).toDouble(),
            backgroundColor: const Color(0xFFF2F4F7),
            backgroundImage:
                photoURL.isNotEmpty ? NetworkImage(photoURL) : null,
            child: photoURL.isEmpty
                ? Icon(
                    Icons.person_outline_rounded,
                    color: const Color(0xFF667085),
                    size: context.ri(17).clamp(16, 19).toDouble(),
                  )
                : null,
          ),
          SizedBox(width: context.rs(10).clamp(8, 12).toDouble()),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(13).clamp(12.5, 14).toDouble(),
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      comment.getFormattedTime(context),
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(11).clamp(10.5, 12).toDouble(),
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF98A2B3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  comment.content,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: context.rf(14).clamp(13, 15).toDouble(),
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF344054),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentInput(AppLocalizations? l10n) {
    final canSubmit =
        !_isSubmitting && _commentController.text.trim().isNotEmpty;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF1F3F5))),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: _horizontalPadding,
          vertical: context.rs(8).clamp(7, 10).toDouble(),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 42,
                      maxHeight: 120,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: TextField(
                        controller: _commentController,
                        focusNode: _commentFocusNode,
                        maxLines: null,
                        minLines: 1,
                        textInputAction: TextInputAction.newline,
                        keyboardType: TextInputType.multiline,
                        decoration: InputDecoration(
                          hintText: l10n?.writeComment ?? '',
                          hintStyle: TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            color: const Color(0xFF98A2B3),
                            fontSize: context.rf(14).clamp(13, 15).toDouble(),
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(14).clamp(13, 15).toDouble(),
                          color: const Color(0xFF111827),
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox.square(
                  dimension: 42,
                  child: IconButton.filled(
                    onPressed: canSubmit ? _handleSubmitComment : null,
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF2E90FA),
                      disabledBackgroundColor: const Color(0xFFE4E7EC),
                      disabledForegroundColor: const Color(0xFF98A2B3),
                    ),
                    tooltip: l10n?.writeComment ?? '',
                    icon: _isSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.arrow_upward_rounded,
                            color: Colors.white,
                            size: 21,
                          ),
                  ),
                ),
              ],
            ),
          ),
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
            SnackBar(
                content:
                    Text(AppLocalizations.of(context)!.loginRequired ?? ""),
                backgroundColor: Colors.red),
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
            SnackBar(
                content: Text(
                    AppLocalizations.of(context)!.commentSubmitFailed ?? ""),
                backgroundColor: Colors.red),
          );
        } else {
          _commentController.clear();
          _commentFocusNode.unfocus();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.commentSubmitFailed ?? ""),
              backgroundColor: Colors.red),
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
