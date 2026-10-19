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

import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/ui_locale.dart';
import '../../models/post.dart';
import '../../design/tokens.dart';
import '../../models/content_translation.dart';
import '../../services/comment_invite_nudge_gate.dart';
import '../../services/comment_service.dart';
import '../../services/content_filter_service.dart';
import '../../services/post_service.dart';
import '../../services/user_info_cache_service.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_language_guess.dart';
import 'motion_press.dart';
import 'post_translation_feed.dart';
import 'translatable_content.dart';
import 'user_avatar.dart';

class PostCardCommentInvite extends StatefulWidget {
  const PostCardCommentInvite({
    super.key,
    required this.post,
    required this.commentCount,
    required this.onOpenComments,
    @visibleForTesting this.debugViewerId,
    @visibleForTesting this.debugBlockedIds,
  });

  /// 테스트에서 로그인 사용자 대신 쓰는 uid. 앱에서는 항상 null이다.
  final String? debugViewerId;

  /// 테스트에서 차단 목록 대신. 앱에서는 null(ContentFilterService 캐시).
  final Set<String>? debugBlockedIds;
  final Post post;
  final int commentCount;

  /// 방금 남긴 댓글을 누르면 전체 댓글(상세 화면)로 이동한다.
  final VoidCallback onOpenComments;

  /// 테스트에서 CommentService 대신(댓글 수 캐시 조정도 건너뛴다). 앱에서는 null.
  @visibleForTesting
  static Future<bool> Function(String postId, String text)? debugAddComment;

  @override
  State<PostCardCommentInvite> createState() => _PostCardCommentInviteState();
}

class _PostCardCommentInviteState extends State<PostCardCommentInvite>
    with SingleTickerProviderStateMixin {
  static const _brand = Color(0xFF2E6CC2);
  static const _iconIdle = Color(0xFF98A2B3);

  /// 화면에 들어올 때 한 번: 고리(1.6s) · 아바타(0.9s) · 번역 아이콘(0.8s)을 Interval로.
  late final AnimationController _nudge = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  /// 60% 이상 보인 채 800ms 머물면 게이트에 요청.
  Timer? _dwell;

  /// 안내 문구 회전(2.6초 간격, 두 바퀴 뒤 문구 1).
  Timer? _rotate;
  int _phraseIndex = 0;
  int _rotations = 0;
  List<String> _phrases = const [];
  bool _nudged = false;
  final GlobalKey _rowKey = GlobalKey();

  /// 이 카드에서 방금 남긴 댓글. 카드 안에서 바로 대화에 참여했음을 보여 준다.
  String? _myRecentComment;

  /// 보낸 직후 2.2초 동안 '✓ 댓글을 남겼어요'.
  bool _showSent = false;
  Timer? _sentTimer;

  @override
  void didUpdateWidget(covariant PostCardCommentInvite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      _myRecentComment = null;
      _showSent = false;
      _sentTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _sentTimer?.cancel();
    _dwell?.cancel();
    _rotate?.cancel();
    CommentInviteNudgeGate.instance.cancel(widget.post.id);
    _nudge.dispose();
    super.dispose();
  }

  bool get _eligible {
    final viewer = _viewerId;
    return viewer != null &&
        viewer != widget.post.userId &&
        !_nudged &&
        !CommentInviteNudgeGate.instance.doneToday(widget.post.id);
  }

  void _onVisibility(VisibilityInfo info) {
    if (!mounted) return;
    final fraction = info.visibleFraction;
    if (fraction < .1) _stopRotation();
    if (fraction >= .6) {
      if (_eligible && _dwell == null) {
        _dwell = Timer(const Duration(milliseconds: 800), _requestNudge);
      }
    } else {
      _dwell?.cancel();
      _dwell = null;
      CommentInviteNudgeGate.instance.cancel(widget.post.id);
    }
  }

  void _requestNudge() {
    _dwell = null;
    if (!mounted || !_eligible) return;
    final box = _rowKey.currentContext?.findRenderObject() as RenderBox?;
    final top = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero).dy
        : double.infinity;
    CommentInviteNudgeGate.instance.request(widget.post.id, top, _startNudge);
  }

  void _startNudge() {
    if (!mounted || _nudged) return;
    _nudged = true;
    if (MotionTokens.reduceMotion(context)) return;
    _nudge.forward(from: 0);
    _phrases = _buildPhrases();
    if (_phrases.length < 2) return;
    _rotations = 0;
    _rotate?.cancel();
    _rotate = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (!mounted) return;
      setState(() {
        _phraseIndex = (_phraseIndex + 1) % _phrases.length;
        _rotations++;
      });
      if (_rotations >= _phrases.length * 2) _stopRotation();
    });
  }

  void _stopRotation() {
    _rotate?.cancel();
    _rotate = null;
    if (_phraseIndex != 0 && mounted) setState(() => _phraseIndex = 0);
  }

  /// 문구 1 '어떻게 생각하세요?', 2 '{작성자}에게 한마디', 3 '{내 언어}로 써도 {작성자 언어}로'
  /// (글의 원문 언어가 내 언어와 다를 때만).
  List<String> _buildPhrases() {
    final strings = _InviteStrings.of(context);
    final mine = Localizations.localeOf(context).languageCode;
    final theirs = postSourceLanguage(widget.post);
    final author = widget.post.isAnonymous ? '' : widget.post.author.trim();
    final myName = strings.languageName(mine);
    final theirName = strings.languageName(theirs);
    return [
      strings.prompt,
      strings.sayToAuthor(author),
      if (theirs.isNotEmpty &&
          theirs != mine &&
          myName != null &&
          theirName != null)
        strings.writeInYours(myName, theirName),
    ];
  }

  String? get _viewerId =>
      widget.debugViewerId ?? FirebaseAuth.instance.currentUser?.uid;

  Future<void> _openComposer() async {
    if (_viewerId == null) return;
    // 누르면 회전을 멈추고, 이 카드는 오늘 다시 반응하지 않는다.
    _stopRotation();
    _dwell?.cancel();
    _dwell = null;
    _nudged = true;
    CommentInviteNudgeGate.instance.markDone(widget.post.id);
    final sent = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _CardCommentComposerSheet(post: widget.post),
    );
    if (!mounted || sent == null || sent.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _myRecentComment = sent.trim();
      _showSent = true;
    });
    _sentTimer?.cancel();
    _sentTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _showSent = false);
    });
  }

  /// 최근 댓글 한 줄에 보일 댓글. 없거나 차단 관계면 null.
  PostLatestComment? get _visibleLatest {
    final latest = widget.post.latestComment;
    if (latest == null || widget.commentCount < 1) return null;
    if (latest.text.isEmpty && !latest.hasMedia) return null;
    if (widget.debugBlockedIds != null) {
      if (widget.debugBlockedIds!.contains(latest.authorId)) return null;
    } else if (ContentFilterService.getBlockedUserIdsCached()
            .contains(latest.authorId) ||
        ContentFilterService.getBlockedByUserIdsCached()
            .contains(latest.authorId)) {
      return null;
    }
    return latest;
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
        : (cached?.photoURL ??
                FirebaseAuth.instance.currentUser?.photoURL ??
                '')
            .trim();
    final photoVersion = cached?.photoVersion ?? 0;
    // 모든 카드에서 같은 한 문장으로 의견을 묻는다.
    final prompt = strings.prompt;
    final recent = _myRecentComment;
    final latest = recent == null ? _visibleLatest : null;
    final showViewAll =
        widget.commentCount >= 1 && (recent != null || latest != null);

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (recent != null)
            // 내 댓글로 바뀌며 8px 아래에서 올라온다. 이름 '나'는 brand 색.
            _RiseIn(
              key: ValueKey('post-card-my-comment:${widget.post.id}'),
              child: _RecentCommentLine(
                uid: viewerId,
                photoUrl: photoUrl,
                photoVersion: photoVersion,
                label: strings.me,
                labelColor: const Color(0xFF2E6CC2),
                timeLabel: strings.justNow,
                text: recent,
                onTap: widget.onOpenComments,
              ),
            )
          else if (latest != null)
            _LatestCommentLine(
              key: ValueKey('post-card-latest-comment:${widget.post.id}'),
              post: widget.post,
              latest: latest,
              anonymousLabel:
                  AppLocalizations.of(context)?.anonymous ?? strings.anonymous,
              mediaLabel: strings.media,
              onTap: widget.onOpenComments,
            ),
          if (showViewAll)
            InkWell(
              key: ValueKey('post-card-view-all:${widget.post.id}'),
              onTap: widget.onOpenComments,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  strings.viewAll(widget.commentCount),
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ),
          VisibilityDetector(
            key: ValueKey('comment-invite-vis:${widget.post.id}'),
            onVisibilityChanged: _onVisibility,
            child: Row(
              key: _rowKey,
              children: [
                // 아바타: 위로 3px · -6° → +4° → 제자리(900ms, 살짝 넘침).
                AnimatedBuilder(
                  animation: _nudge,
                  builder: (context, child) {
                    final t = (_nudge.value * 1600 / 900).clamp(0.0, 1.0);
                    if (!_nudge.isAnimating || t >= 1) return child!;
                    final lift = math.sin(t * math.pi);
                    final degrees = t < .3
                        ? -6 * (t / .3)
                        : t < .65
                            ? -6 + 10 * ((t - .3) / .35)
                            : 4 * (1 - (t - .65) / .35);
                    return Transform.translate(
                      offset: Offset(0, -3 * lift),
                      child: Transform.rotate(
                          angle: degrees * math.pi / 180, child: child),
                    );
                  },
                  child: UserAvatar(
                    uid: viewerId,
                    photoUrl: photoUrl,
                    photoVersion: photoVersion,
                    isAnonymous: false,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomPaint(
                    // 입력칸 고리: brand .28, 0 → 3px → 0(1.6s). 레이아웃은 흔들지 않는다.
                    foregroundPainter: _RingPainter(_nudge, color: _brand),
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
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 13),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _PhraseSwitcher(
                                        text: _phrases.isEmpty
                                            ? prompt
                                            : _phrases[_phraseIndex.clamp(
                                                0, _phrases.length - 1)],
                                        style: TextStyle(
                                          fontFamily:
                                              uiFontFamily(context, 'Inter'),
                                          fontFamilyFallback: const [
                                            'NotoSansKR'
                                          ],
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
                                    const SizedBox(width: 6),
                                    // 어떤 언어로 써도 번역돼 전달된다는 신호.
                                    // 반응할 때 Y축으로 한 바퀴, 회색 → brand → 회색(800ms).
                                    AnimatedBuilder(
                                      animation: _nudge,
                                      builder: (context, _) {
                                        final t = (_nudge.value * 1600 / 800)
                                            .clamp(0.0, 1.0);
                                        final spinning =
                                            _nudge.isAnimating && t < 1;
                                        final icon = Icon(
                                          Icons.translate_rounded,
                                          size: 15,
                                          color: spinning
                                              ? Color.lerp(_iconIdle, _brand,
                                                  math.sin(t * math.pi))
                                              : _iconIdle,
                                        );
                                        if (!spinning) return icon;
                                        return Transform(
                                          alignment: Alignment.center,
                                          transform: Matrix4.rotationY(
                                              Curves.easeInOut.transform(t) *
                                                  2 *
                                                  math.pi),
                                          child: icon,
                                        );
                                      },
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
                ),
              ],
            ),
          ),
          // 보낸 직후: '✓ 댓글을 남겼어요'(300ms 나타남, 2.2초 뒤 사라짐).
          AnimatedSize(
            duration: MotionTokens.of(context, MotionTokens.page),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: _showSent
                ? Padding(
                    padding: const EdgeInsets.only(top: 6, left: 34),
                    child: _SentPill(
                      key: ValueKey('post-card-comment-sent:${widget.post.id}'),
                      label: strings.sent,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// 입력칸 바깥 고리: 0 → 3px → 0, brand 투명도 .28(easeOutCubic).
class _RingPainter extends CustomPainter {
  _RingPainter(this.animation, {required this.color})
      : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final v = animation.value;
    if (v <= 0 || v >= 1) return;
    final t = Curves.easeOutCubic.transform(v);
    final spread = 3 * math.sin(t * math.pi);
    if (spread <= .05) return;
    final rect = (Offset.zero & size).inflate(spread / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(18 + spread / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = spread
        ..color = color.withValues(alpha: .28),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}

/// 안내 문구: 새 문구가 아래에서 올라오고 이전 문구는 위로 사라진다(450ms).
class _PhraseSwitcher extends StatelessWidget {
  const _PhraseSwitcher({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSwitcher(
        duration: MotionTokens.of(context, const Duration(milliseconds: 450)),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (child, animation) {
          final incoming = child.key == ValueKey(text);
          final slide = Tween<Offset>(
            begin: Offset(0, incoming ? 1 : -1),
            end: Offset.zero,
          ).animate(animation);
          return SlideTransition(
            position: slide,
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: Text(
          text,
          key: ValueKey(text),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}

/// 8px 아래에서 올라오며 나타난다(medium). 동작 줄이기면 바로.
class _RiseIn extends StatelessWidget {
  const _RiseIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MotionTokens.of(context, MotionTokens.medium),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
    );
  }
}

class _SentPill extends StatelessWidget {
  const _SentPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MotionTokens.of(context, const Duration(milliseconds: 300)),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF7EF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded, size: 14, color: Color(0xFF15803D)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF15803D),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 최근 댓글 한 줄(posts.latestComment): 이름 15/w800 + 본문 14 한 줄.
/// 본문은 카드 본문과 같은 번역 상태를 따른다(같은 scope). 내 언어로 보이는 댓글이나
/// 120자로 잘린 댓글은 번역을 요청하지 않는다(원문 확인이 맞지 않음).
class _LatestCommentLine extends StatelessWidget {
  const _LatestCommentLine({
    super.key,
    required this.post,
    required this.latest,
    required this.anonymousLabel,
    required this.mediaLabel,
    required this.onTap,
  });

  final Post post;
  final PostLatestComment latest;
  final String anonymousLabel;
  final String mediaLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = latest.isAnonymous || latest.authorName.isEmpty
        ? anonymousLabel
        : latest.authorName;
    final language = Localizations.localeOf(context).languageCode;
    final text = latest.text.isEmpty ? mediaLabel : latest.text;
    Widget line(String body) => Text.rich(
          TextSpan(children: [
            TextSpan(
              text: '$name  ',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            TextSpan(text: body),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: 14,
            color: const Color(0xFF374151),
            height: 1.35,
          ),
        );
    final guessed = guessTextLanguage(latest.text);
    final translatable = latest.text.isNotEmpty &&
        latest.text.characters.length < 120 &&
        guessed != language;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 4),
        child: translatable
            ? TranslatableContent(
                request: ContentTranslationRequest(
                  contentType: 'comment',
                  contentId: latest.commentId,
                  parentId: post.id,
                  sourceFields: {'content': latest.text},
                ),
                scope: PostTranslationFeed.scopeOf(context, post.id),
                showToggle: false,
                builder: (context, fields) => line(fields['content'] ?? text),
              )
            : line(text),
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
    this.labelColor,
  });

  final String uid;
  final String photoUrl;
  final int photoVersion;
  final String label;
  final Color? labelColor;
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
                      style: baseStyle.copyWith(
                          fontWeight: FontWeight.w700, color: labelColor),
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
    final debugAdd = PostCardCommentInvite.debugAddComment;
    try {
      success = debugAdd != null
          ? await debugAdd(widget.post.id, text)
          : await CommentService().addComment(widget.post.id, text);
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    if (success) {
      // 카드/상세가 공유하는 댓글 수를 즉시 올린다(서버 집계가 뒤이어 확정).
      if (debugAdd == null) {
        PostService().adjustCachedCommentCount(widget.post.id, 1);
      }
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
                    Icon(
                      _failed
                          ? Icons.error_outline_rounded
                          : Icons.translate_rounded,
                      size: 14,
                      color: _failed
                          ? const Color(0xFFD92D20)
                          : const Color(0xFF98A2B3),
                    ),
                    const SizedBox(width: 6),
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
  String get failed =>
      _t('댓글을 남기지 못했어요.', 'Could not post the comment.', '评论发送失败。');
  String get me => _t('나', 'You', '我');
  String get justNow => _t('방금', 'now', '刚刚');
  String get anonymous => _t('익명', 'Anonymous', '匿名');
  String get media => _t('사진', 'Photo', '图片');
  String get sent => _t('댓글을 남겼어요', 'Comment posted', '评论已发送');
  String viewAll(int n) =>
      _t('댓글 $n개 모두 보기', 'View all $n comments', '查看全部 $n 条评论');

  /// 문구 2: 익명 글은 '작성자'.
  String sayToAuthor(String author) => author.isEmpty
      ? _t('작성자에게 한마디 남겨 볼까요?', 'Say something to the author?', '给作者留句话吧？')
      : _t('$author에게 한마디 남겨 볼까요?', 'Say something to $author?',
          '给$author留句话吧？');

  /// 문구 3: 내 언어로 써도 작성자 언어로 번역된다.
  String writeInYours(String mine, String theirs) => _t(
        '$mine로 써도 $theirs로 번역돼요',
        "Write in $mine, they'll read it in $theirs",
        '用$mine写，对方会看到$theirs',
      );

  /// 화면 언어로 쓴 언어 이름. 모르는 언어는 null(문구 3을 넣지 않는다).
  String? languageName(String code) {
    const names = <String, (String, String, String)>{
      'ko': ('한국어', 'Korean', '韩语'),
      'en': ('영어', 'English', '英语'),
      'zh': ('중국어', 'Chinese', '中文'),
      'ja': ('일본어', 'Japanese', '日语'),
    };
    final name = names[code];
    return name == null ? null : _t(name.$1, name.$2, name.$3);
  }
}
