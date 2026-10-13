// lib/snapshot/snapshot_feel_bar.dart
// 스낵 보기 화면의 하단 바(스낵 v3). 필링 하나로 반응한다.
// 서비스 호출은 콜백으로 받아, 화면 밖에서도 테스트할 수 있다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/relationship_strings.dart';
import '../models/relationship_status.dart';
import '../models/snapshot.dart';
import '../providers/relationship_provider.dart';
import '../services/snapshot_service.dart';
import '../ui/widgets/motion_press.dart';
import 'snack_feel_icon.dart';
import 'snack_response_policy.dart';
import 'snapshot_strings.dart';
import 'snapshot_viewer_chrome.dart';

/// 필링 하나로 반응하는 하단 바.
/// - 작성자: `필링 n · 본 사람 m` 알약(활동 시트)
/// - 친구 + 친구 답장도: [DM 답장 입력] [사진·영상 답장] [필링]
/// - 그 밖: [필링] 알약 하나(보낸 뒤 비활성, 취소 없음)
class SnapshotFeelBar extends StatefulWidget {
  const SnapshotFeelBar({
    super.key,
    required this.snapshot,
    required this.service,
    required this.isOwner,
    required this.feelSent,
    required this.canFeel,
    required this.onFeel,
    required this.onDmReply,
    required this.onViewers,
    required this.onSnackReply,
    required this.onFocusChanged,
    this.viewersStream,
  });

  /// 테스트용. 없으면 `service.watchViewers`.
  final Stream<List<SnapshotViewer>>? viewersStream;

  final SnapshotItem snapshot;
  final SnapshotService? service;
  final bool isOwner;
  final bool feelSent;
  final bool canFeel;
  final VoidCallback onFeel;

  /// DM으로 보낼 글. 기존 DM 화면의 전송 경로를 쓴다.
  final Future<void> Function(String text) onDmReply;
  final VoidCallback onViewers;
  final VoidCallback onSnackReply;
  final ValueChanged<bool> onFocusChanged;

  @override
  State<SnapshotFeelBar> createState() => _SnapshotFeelBarState();
}

class _SnapshotFeelBarState extends State<SnapshotFeelBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'snapshot-dm-reply');
  Stream<List<SnapshotViewer>>? _viewers;
  bool _sending = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_handleFocus);
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText && mounted) setState(() => _hasText = has);
    });
    _bind();
  }

  @override
  void didUpdateWidget(covariant SnapshotFeelBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.id != widget.snapshot.id ||
        oldWidget.isOwner != widget.isOwner) {
      _controller.clear();
      _sending = false;
      _bind();
    }
  }

  void _bind() {
    _viewers = widget.isOwner
        ? (widget.viewersStream ??
            widget.service!.watchViewers(widget.snapshot.id))
        : null;
  }

  void _handleFocus() {
    widget.onFocusChanged(_focus.hasFocus);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_handleFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (_sending || message.isEmpty) return;
    setState(() => _sending = true);
    _focus.unfocus();
    try {
      await widget.onDmReply(message);
      if (mounted) _controller.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  TextStyle _text(double size, FontWeight weight, {double alpha = 1}) =>
      snapshotChromeStyle(context, size: size, weight: weight)
          .copyWith(color: Colors.white.withValues(alpha: alpha));

  /// 필링 알약. 보내기 전은 유리 알약, 보낸 뒤는 #2C6BC0 채움.
  Widget _feelPill(SnapshotStrings strings) {
    final sent = widget.feelSent;
    return Semantics(
      button: true,
      enabled: widget.canFeel,
      selected: sent,
      label: sent ? strings.feelSent : strings.feel,
      excludeSemantics: true,
      child: MotionPress(
        enabled: widget.canFeel,
        pressedScale: .97,
        child: GestureDetector(
          key: const ValueKey('snapshot_feel_pill'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.canFeel ? widget.onFeel : null,
          child: AnimatedContainer(
            duration: snapshotReduceMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sent ? snapshotAccent : const Color(0x1FFFFFFF),
              borderRadius: BorderRadius.circular(22),
              border: sent
                  ? null
                  : Border.all(color: const Color(0x73FFFFFF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FeelPop(
                  sent: sent,
                  child: SnackFeelIcon(size: 20, filled: sent),
                ),
                const SizedBox(width: 8),
                Text(
                  sent ? strings.feelSent : strings.feel,
                  style: _text(14, FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 친구 화면의 필링 아이콘 버튼(26). 보낸 뒤 #2C6BC0 채움.
  Widget _feelButton(SnapshotStrings strings) {
    final sent = widget.feelSent;
    return Semantics(
      button: true,
      enabled: widget.canFeel,
      selected: sent,
      label: sent ? strings.feelSent : strings.feel,
      excludeSemantics: true,
      child: MotionPress(
        enabled: widget.canFeel,
        pressedScale: .9,
        child: GestureDetector(
          key: const ValueKey('snapshot_feel_button'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.canFeel ? widget.onFeel : null,
          child: SizedBox.square(
            dimension: 44,
            child: Center(
              child: _FeelPop(
                sent: sent,
                child: SnackFeelIcon(
                  size: 26,
                  filled: sent,
                  color: sent ? snapshotAccent : Colors.white,
                  lensColor: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final relation = RelationshipStrings.of(context);
    final snapshot = widget.snapshot;
    Widget row;
    var typing = false;
    if (widget.isOwner) {
      final feels =
          snapshot.reactionCounts.values.fold<int>(0, (sum, v) => sum + v);
      row = StreamBuilder<List<SnapshotViewer>>(
        stream: _viewers,
        builder: (context, result) => GestureDetector(
          key: const ValueKey('snapshot_owner_activity_pill'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onViewers,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x1FFFFFFF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x73FFFFFF)),
            ),
            child: Text(
              strings.feelAndViewers(feels, result.data?.length ?? 0),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(14, FontWeight.w600),
            ),
          ),
        ),
      );
    } else {
      return Selector<RelationshipProvider, RelationshipStatus?>(
        selector: (_, provider) =>
            provider.feedRelationshipStatus(snapshot.authorId),
        builder: (context, status, _) {
          final friendReply = status == RelationshipStatus.friends &&
              allowsFriendReply(snapshot.responseMode);
          return _viewerBar(context, strings, relation, friendReply);
        },
      );
    }
    return _frame(typing, strings, row);
  }

  Widget _viewerBar(
    BuildContext context,
    SnapshotStrings strings,
    RelationshipStrings relation,
    bool friendReply,
  ) {
    final snapshot = widget.snapshot;
    if (!friendReply) {
      return _frame(false, strings, _feelPill(strings));
    }
    final name = snapshot.authorName.trim().isEmpty
        ? strings.snapshot
        : snapshot.authorName.trim();
    final typing = _focus.hasFocus;
    final input = Container(
      height: typing ? 40 : 44,
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: BoxDecoration(
        color: typing ? const Color(0xFF2C2C2E) : const Color(0x33000000),
        borderRadius: BorderRadius.circular(typing ? 20 : 22),
        border: typing ? null : Border.all(color: const Color(0x59FFFFFF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('snapshot_dm_reply_input'),
              controller: _controller,
              focusNode: _focus,
              enabled: !_sending,
              maxLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => unawaited(_send()),
              cursorColor: Colors.white,
              style: _text(14, FontWeight.w400),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: strings.replyByDm(name),
                hintStyle: _text(14, FontWeight.w400, alpha: .7),
              ),
            ),
          ),
          if (_hasText)
            GestureDetector(
              key: const ValueKey('snapshot_dm_reply_send'),
              behavior: HitTestBehavior.opaque,
              onTap: _sending ? null : () => unawaited(_send()),
              child: Container(
                width: 32,
                height: 32,
                margin: EdgeInsets.only(right: typing ? 0 : 2),
                decoration: const BoxDecoration(
                  color: snapshotAccent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_upward_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
    final row = Row(
      children: [
        Expanded(child: input),
        if (!typing) ...[
          Semantics(
            button: true,
            label: relation.snackReply,
            hint: relation.snackReplyHint,
            excludeSemantics: true,
            child: MotionPress(
              pressedScale: .9,
              child: GestureDetector(
                key: const ValueKey('snapshot_video_reply_button'),
                behavior: HitTestBehavior.opaque,
                // 탭 한 번으로 연다(이전: 탭은 안내, 길게 눌러야 열림).
                onTap: widget.onSnackReply,
                onLongPress: widget.onSnackReply,
                child: const SizedBox.square(
                  dimension: 44,
                  child: Center(
                    child: Icon(
                      Icons.videocam_outlined,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
          ),
          _feelButton(strings),
        ],
      ],
    );
    return _frame(
      typing,
      strings,
      row,
      hint: typing ? strings.replyDmHint(name) : null,
    );
  }

  Widget _frame(
    bool typing,
    SnapshotStrings strings,
    Widget row, {
    String? hint,
  }) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: Container(
        color: hint != null ? const Color(0xFF1C1C1E) : Colors.transparent,
        padding: hint != null
            ? const EdgeInsets.fromLTRB(4, 8, 4, 4)
            : EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 8),
                child: Text(
                  hint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _text(12, FontWeight.w400, alpha: .6),
                ),
              ),
            row,
          ],
        ),
      ),
    );
  }
}

/// 보낸 순간 1.2배로 튀는 효과(250ms).
class _FeelPop extends StatelessWidget {
  const _FeelPop({required this.sent, required this.child});

  final bool sent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!sent || snapshotReduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      key: const ValueKey('feel-pop'),
      tween: Tween<double>(begin: 1.2, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}

