// lib/ui/widgets/post_card_comment_invite.dart
// 포스트 카드 아래에 붙는 '댓글 참여 줄'.
//
// 위필링의 포스트 카드는 읽고 지나가는 콘텐츠가 아니라 대화가 시작되는
// 자리다. 모든 카드 끝에 내 아바타와 입력 줄을 두어, 상세 화면에 들어가지
// 않고도 바로 한 줄을 남길 수 있게 한다. 어떤 언어로 써도 읽는 사람에게는
// 기존 댓글 번역으로 그 사람의 언어로 보인다.
//
// 댓글 작성은 상세 화면과 같은 CommentService.addComment를 그대로 쓰고,
// 댓글 수도 상세 화면과 같은 방식(adjustCachedCommentCount)으로 반영한다.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/ui_locale.dart';
import '../../models/post.dart';
import '../../services/comment_service.dart';
import '../../services/post_service.dart';
import '../../services/user_info_cache_service.dart';
import '../../utils/responsive_helper.dart';
import 'motion_press.dart';
import 'user_avatar.dart';

class PostCardCommentInvite extends StatefulWidget {
  const PostCardCommentInvite({
    super.key,
    required this.post,
    required this.commentCount,
    required this.onOpenComments,
    @visibleForTesting this.debugViewerId,
  });

  /// 테스트에서 로그인 사용자 대신 쓰는 uid. 앱에서는 항상 null이다.
  final String? debugViewerId;
  final Post post;
  final int commentCount;

  /// 방금 남긴 댓글을 누르면 전체 댓글(상세 화면)로 이동한다.
  final VoidCallback onOpenComments;

  @override
  State<PostCardCommentInvite> createState() => _PostCardCommentInviteState();
}

class _PostCardCommentInviteState extends State<PostCardCommentInvite> {
  /// 이 카드에서 방금 남긴 댓글. 카드 안에서 바로 대화에 참여했음을 보여 준다.
  String? _myRecentComment;

  @override
  void didUpdateWidget(covariant PostCardCommentInvite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) _myRecentComment = null;
  }

  String? get _viewerId =>
      widget.debugViewerId ?? FirebaseAuth.instance.currentUser?.uid;

  Future<void> _openComposer() async {
    if (_viewerId == null) return;
    final sent = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _CardCommentComposerSheet(post: widget.post),
    );
    if (!mounted || sent == null || sent.trim().isEmpty) return;
    setState(() => _myRecentComment = sent.trim());
  }

  @override
  Widget build(BuildContext context) {
    final viewerId = _viewerId;
    if (viewerId == null) return const SizedBox.shrink();
    final strings = _InviteStrings.of(context);
    final cached = widget.debugViewerId != null
        ? null
        : UserInfoCacheService().getCachedUserInfo(viewerId);
    final photoUrl = widget.debugViewerId != null
        ? ''
        : (cached?.photoURL ?? FirebaseAuth.instance.currentUser?.photoURL ?? '')
            .trim();
    final photoVersion = cached?.photoVersion ?? 0;
    // 모든 카드에서 같은 한 문장으로 의견을 묻는다.
    final prompt = strings.prompt;
    final recent = _myRecentComment;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (recent != null)
            _RecentCommentLine(
              uid: viewerId,
              photoUrl: photoUrl,
              photoVersion: photoVersion,
              label: strings.me,
              timeLabel: strings.justNow,
              text: recent,
              onTap: widget.onOpenComments,
            ),
          Row(
            children: [
              UserAvatar(
                uid: viewerId,
                photoUrl: photoUrl,
                photoVersion: photoVersion,
                isAnonymous: false,
                size: 26,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  button: true,
                  label: prompt,
                  excludeSemantics: true,
                  child: MotionPress(
                    pressedScale: .985,
                    child: Material(
                      color: const Color(0xFFF2F4F7),
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey<String>(
                          'post-card-comment-invite:${widget.post.id}',
                        ),
                        onTap: _openComposer,
                        child: SizedBox(
                          height: 36,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 13),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    prompt,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: uiFontFamily(context, 'Inter'),
                                      fontFamilyFallback: const ['NotoSansKR'],
                                      fontSize: context
                                          .rf(13.5)
                                          .clamp(13, 14.5)
                                          .toDouble(),
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFF667085),
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentCommentLine extends StatelessWidget {
  const _RecentCommentLine({
    required this.uid,
    required this.photoUrl,
    required this.photoVersion,
    required this.label,
    required this.timeLabel,
    required this.text,
    required this.onTap,
  });

  final String uid;
  final String photoUrl;
  final int photoVersion;
  final String label;
  final String timeLabel;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: context.rf(13.5).clamp(13, 14.5).toDouble(),
      color: const Color(0xFF111827),
      height: isChineseUi(context) ? 1.35 : 1.3,
      letterSpacing: -0.2,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 3, right: 3, top: 1),
              child: UserAvatar(
                uid: uid,
                photoUrl: photoUrl,
                photoVersion: photoVersion,
                isAnonymous: false,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$label  ',
                      style: baseStyle.copyWith(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: text),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: baseStyle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              timeLabel,
              style: baseStyle.copyWith(
                fontSize: context.rf(12).clamp(11.5, 13).toDouble(),
                color: const Color(0xFF98A2B3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 카드에서 여는 댓글 입력 시트. 키보드 바로 위에 붙어 피드 위치를 지킨다.
class _CardCommentComposerSheet extends StatefulWidget {
  const _CardCommentComposerSheet({required this.post});

  final Post post;

  @override
  State<_CardCommentComposerSheet> createState() =>
      _CardCommentComposerSheetState();
}

class _CardCommentComposerSheetState extends State<_CardCommentComposerSheet> {
  static const int _maxLength = 500;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'post-card-comment');
  bool _sending = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (mounted) setState(() => _failed = false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (_sending || text.isEmpty) return;
    setState(() {
      _sending = true;
      _failed = false;
    });
    bool success;
    try {
      success = await CommentService().addComment(widget.post.id, text);
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    if (success) {
      // 카드/상세가 공유하는 댓글 수를 즉시 올린다(서버 집계가 뒤이어 확정).
      PostService().adjustCachedCommentCount(widget.post.id, 1);
      Navigator.of(context).pop(text);
      return;
    }
    setState(() {
      _sending = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = _InviteStrings.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final hasText = _controller.text.trim().isNotEmpty;
    final excerpt = widget.post.displayText.replaceAll('\n', ' ').trim();
    final author = widget.post.isAnonymous
        ? (AppLocalizations.of(context)?.anonymous ?? '')
        : widget.post.author.trim();
    final small = TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: context.rf(12.5).clamp(12, 13.5).toDouble(),
      color: const Color(0xFF667085),
      height: 1.3,
    );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD0D5DD),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 어떤 글에 다는 댓글인지 한 줄로 보여 준다.
                Container(
                  padding: const EdgeInsets.only(left: 10),
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Color(0xFFD0D5DD), width: 2.5),
                    ),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (author.isNotEmpty)
                          TextSpan(
                            text: '$author  ',
                            style: small.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF344054),
                            ),
                          ),
                        TextSpan(text: excerpt.isEmpty ? '…' : excerpt),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: _maxLength,
                        textInputAction: TextInputAction.newline,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(15).clamp(14, 16).toDouble(),
                          color: const Color(0xFF101828),
                        ),
                        decoration: InputDecoration(
                          hintText: strings.composerHint,
                          hintStyle: const TextStyle(color: Color(0xFF98A2B3)),
                          counterText: '',
                          filled: true,
                          fillColor: const Color(0xFFF2F4F7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox.square(
                      dimension: 44,
                      child: Center(
                        child: _sending
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Semantics(
                                button: true,
                                enabled: hasText,
                                label: strings.send,
                                excludeSemantics: true,
                                child: Material(
                                  color: hasText
                                      ? const Color(0xFF4990E2)
                                      : const Color(0xFFD0D5DD),
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    key: const ValueKey<String>(
                                      'post-card-comment-send',
                                    ),
                                    customBorder: const CircleBorder(),
                                    onTap: hasText ? _send : null,
                                    child: const SizedBox.square(
                                      dimension: 36,
                                      child: Icon(
                                        Icons.arrow_upward_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // 번역 아이콘은 누를 수 있는 곳에만 쓴다(장식용 아이콘 제거).
                    if (_failed) ...[
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 14,
                        color: Color(0xFFD92D20),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        _failed
                            ? (AppLocalizations.of(context)
                                    ?.commentSubmitFailed ??
                                strings.failed)
                            : strings.translationHint,
                        style: small.copyWith(
                          color: _failed ? const Color(0xFFD92D20) : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InviteStrings {
  const _InviteStrings._(this.isKorean, this.isChinese);

  final bool isKorean;
  final bool isChinese;

  static _InviteStrings of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return _InviteStrings._(code == 'ko', code == 'zh');
  }

  String _t(String ko, String en, String zh) =>
      isChinese ? zh : (isKorean ? ko : en);

  String get prompt => _t('어떻게 생각하세요?', 'What do you think?', '你怎么看？');
  String get composerHint => _t('댓글 달기…', 'Add a comment…', '添加评论…');
  String get translationHint => _t(
        '어떤 언어로 써도 읽는 사람에게는 그 사람의 언어로 번역돼요.',
        'Write in any language. Readers see it in theirs.',
        '用任何语言书写，读者都会看到自己语言的译文。',
      );
  String get send => _t('보내기', 'Send', '发送');
  String get failed => _t('댓글을 남기지 못했어요.', 'Could not post the comment.', '评论发送失败。');
  String get me => _t('나', 'You', '我');
  String get justNow => _t('방금', 'now', '刚刚');
}
