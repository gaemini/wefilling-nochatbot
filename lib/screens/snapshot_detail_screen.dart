import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../models/snapshot.dart';
import '../services/dm_service.dart';
import '../services/report_service.dart';
import '../services/snapshot_service.dart';
import '../snapshot/snapshot_storage_image.dart';
import '../snapshot/snapshot_strings.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../utils/responsive_helper.dart';
import 'dm_chat_screen.dart';

/// 상세 화면에서도 작성 화면에서 합성한 전체 프레임을 보존한다.
const BoxFit snapshotDetailImageFit = BoxFit.contain;

class SnapshotDetailScreen extends StatefulWidget {
  const SnapshotDetailScreen({
    super.key,
    required this.snapshots,
    required this.initialIndex,
  });

  final List<SnapshotItem> snapshots;
  final int initialIndex;

  @override
  State<SnapshotDetailScreen> createState() => _SnapshotDetailScreenState();
}

class _SnapshotDetailScreenState extends State<SnapshotDetailScreen>
    with WidgetsBindingObserver {
  static const Duration _switchDuration = Duration(milliseconds: 240);

  final SnapshotService _service = SnapshotService.instance;
  final DMService _dmService = DMService();
  late List<SnapshotItem> _items;
  late int _index;
  Timer? _ticker;
  Timer? _switchTimer;
  bool _isSwitching = false;

  SnapshotItem get _current => _items[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _items = widget.snapshots
        .where((item) => !item.isExpiredAt(_service.serverNow))
        .toList();
    final requestedId = widget.snapshots.isEmpty
        ? ''
        : widget
            .snapshots[
                widget.initialIndex.clamp(0, widget.snapshots.length - 1)]
            .id;
    _index = _items.indexWhere((item) => item.id == requestedId);
    if (_index < 0) _index = 0;
    _ticker =
        Timer.periodic(const Duration(seconds: 20), (_) => _recheckExpiry());
    WidgetsBinding.instance.addPostFrameCallback((_) => _recheckExpiry());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _switchTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_service.refreshServerClock().then((_) => _recheckExpiry()));
      unawaited(_service.syncMyFeed());
    }
  }

  void _recheckExpiry() {
    if (!mounted || _items.isEmpty) return;
    final currentId = _current.id;
    final filtered =
        _items.where((item) => !item.isExpiredAt(_service.serverNow)).toList();
    if (filtered.isEmpty) {
      final strings = SnapshotStrings.of(context);
      Navigator.of(context).pop();
      AppSnackBar.show(context, message: strings.expired);
      return;
    }
    final newIndex = filtered.indexWhere((item) => item.id == currentId);
    setState(() {
      _items = filtered;
      _index = newIndex >= 0 ? newIndex : 0;
    });
  }

  void _moveTo(int targetIndex) {
    if (_isSwitching || targetIndex < 0 || targetIndex >= _items.length) {
      return;
    }
    if (targetIndex == _index) return;

    _switchTimer?.cancel();
    HapticFeedback.selectionClick();
    setState(() {
      _index = targetIndex;
      _isSwitching = true;
    });
    _switchTimer = Timer(_switchDuration, () {
      if (!mounted) return;
      setState(() => _isSwitching = false);
    });
  }

  void _showPrevious() => _moveTo(_index - 1);

  void _showNext() => _moveTo(_index + 1);

  Future<void> _showActions() async {
    final strings = SnapshotStrings.of(context);
    final item = _current;
    final isOwner = FirebaseAuth.instance.currentUser?.uid == item.authorId;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOwner) ...[
              _ActionRow(
                icon: Icons.delete_outline_rounded,
                label: strings.delete,
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
            ] else ...[
              _ActionRow(
                icon: Icons.send_outlined,
                label: strings.message,
                onTap: () => Navigator.pop(sheetContext, 'message'),
              ),
              _ActionRow(
                icon: Icons.flag_outlined,
                label: strings.report,
                onTap: () => Navigator.pop(sheetContext, 'report'),
              ),
              _ActionRow(
                icon: Icons.block_outlined,
                label: strings.block,
                onTap: () => Navigator.pop(sheetContext, 'block'),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'delete':
        await _deleteCurrent();
      case 'message':
        await _openMessage();
      case 'report':
        await _report();
      case 'block':
        await _block();
    }
  }

  Future<void> _deleteCurrent() async {
    final strings = SnapshotStrings.of(context);
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          barrierColor: const Color(0x99000000),
          useSafeArea: true,
          builder: (dialogContext) => _SnapshotDeleteDialog(strings: strings),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await _service.deleteSnapshot(_current.id);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: strings.isKorean ? '삭제하지 못했어요.' : 'Could not delete it.',
          type: AppSnackBarType.error,
        );
      }
    }
  }

  Future<void> _openMessage() async {
    final strings = SnapshotStrings.of(context);
    try {
      final conversationId = await _dmService.getOrCreateConversation(
        _current.authorId,
        isFriend: _current.visibility != SnapshotVisibility.public,
      );
      if (!mounted) return;
      if (conversationId == null) throw StateError('conversation-unavailable');
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DMChatScreen(
            conversationId: conversationId,
            otherUserId: _current.authorId,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: strings.isKorean
              ? '메시지를 시작하지 못했어요.'
              : 'Could not start a message.',
          type: AppSnackBarType.error,
        );
      }
    }
  }

  Future<void> _report() async {
    final strings = SnapshotStrings.of(context);
    final ok = await ReportService.reportContent(
      reportedUserId: _current.authorId,
      targetType: 'snapshot',
      targetId: _current.id,
      reason: 'inappropriate_content',
      targetTitle: _current.overlay.text,
    );
    if (!mounted) return;
    if (ok) {
      _service.hideSnapshotLocally(_current.id);
      Navigator.of(context).pop();
      AppSnackBar.show(context,
          message: strings.reportDone, type: AppSnackBarType.success);
    }
  }

  Future<void> _block() async {
    final strings = SnapshotStrings.of(context);
    final ok = await ReportService.blockUser(_current.authorId);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      AppSnackBar.show(context,
          message: strings.blockDone, type: AppSnackBarType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const Scaffold(backgroundColor: Colors.black);
    }
    final strings = SnapshotStrings.of(context);
    final toolbarHeight = context.rh(56, min: 54, max: 60);
    final mediaPadding = MediaQuery.paddingOf(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final isOwner = FirebaseAuth.instance.currentUser?.uid == _current.authorId;
    final showsPosition = _items.length > 1;
    final reactionExclusionHeight =
        (isOwner ? 0 : context.rh(112, min: 104, max: 124)) +
            mediaPadding.bottom +
            keyboardInset;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: _switchDuration,
              reverseDuration: _switchDuration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                fit: StackFit.expand,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              transitionBuilder: (child, animation) {
                final fade = CurvedAnimation(
                  parent: animation,
                  curve: const Interval(.08, 1, curve: Curves.easeOutCubic),
                );
                final scale = Tween<double>(begin: .988, end: 1).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                );
                return FadeTransition(
                  opacity: fade,
                  child: ScaleTransition(scale: scale, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_current.id),
                child: _SnapshotDetailPage(
                  snapshot: _current,
                  service: _service,
                ),
              ),
            ),
            Positioned(
              top: mediaPadding.top + toolbarHeight,
              left: 0,
              right: 0,
              bottom: reactionExclusionHeight,
              child: _SnapshotTapNavigation(
                canGoPrevious: _index > 0,
                canGoNext: _index < _items.length - 1,
                previousLabel: strings.previousSnapshot,
                nextLabel: strings.nextSnapshot,
                onPrevious: _showPrevious,
                onNext: _showNext,
              ),
            ),
            if (showsPosition)
              Positioned(
                top: mediaPadding.top + toolbarHeight + 3,
                left: 12,
                right: 12,
                child: IgnorePointer(
                  child: _SnapshotPositionIndicator(
                    count: _items.length,
                    index: _index,
                  ),
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: toolbarHeight,
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 48,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            size: context.ri(22).clamp(21, 24).toDouble(),
                            color: Colors.white,
                            shadows: const [
                              Shadow(color: Colors.black54, blurRadius: 8),
                            ],
                          ),
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _SnapshotAuthorHeader(
                            snapshot: _current,
                            visibility: _visibilityLabel(
                              strings,
                              _current.visibility,
                            ),
                            remaining: _snapshotRemainingLabel(
                              _current,
                              _service,
                              strings,
                            ),
                          ),
                        ),
                      ),
                      SizedBox.square(
                        dimension: 48,
                        child: IconButton(
                          onPressed: FirebaseAuth.instance.currentUser?.uid ==
                                  _current.authorId
                              ? _deleteCurrent
                              : _showActions,
                          icon: Icon(
                            FirebaseAuth.instance.currentUser?.uid ==
                                    _current.authorId
                                ? Icons.delete_outline_rounded
                                : Icons.more_horiz_rounded,
                            size: context.ri(23).clamp(21, 25).toDouble(),
                            color: Colors.white,
                            shadows: const [
                              Shadow(color: Colors.black54, blurRadius: 8),
                            ],
                          ),
                          tooltip: FirebaseAuth.instance.currentUser?.uid ==
                                  _current.authorId
                              ? strings.delete
                              : MaterialLocalizations.of(context)
                                  .showMenuTooltip,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SnapshotDetailPage extends StatefulWidget {
  const _SnapshotDetailPage({
    required this.snapshot,
    required this.service,
  });
  final SnapshotItem snapshot;
  final SnapshotService service;

  @override
  State<_SnapshotDetailPage> createState() => _SnapshotDetailPageState();
}

class _SnapshotDetailPageState extends State<_SnapshotDetailPage>
    with SingleTickerProviderStateMixin {
  late Stream<SnapshotItem?> _accessStream;
  late Future<bool> _reactionStatus;
  late final AnimationController _heartBurstController;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  bool _submittingReaction = false;
  bool _reactedLocally = false;
  bool _sendingComment = false;

  @override
  void initState() {
    super.initState();
    _heartBurstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    );
    _accessStream = widget.service.watchSnapshot(
      widget.snapshot.id,
      initial: widget.snapshot,
    );
    _reactionStatus = widget.service.hasReacted(widget.snapshot.id);
  }

  @override
  void didUpdateWidget(covariant _SnapshotDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.id != widget.snapshot.id) {
      _accessStream = widget.service.watchSnapshot(
        widget.snapshot.id,
        initial: widget.snapshot,
      );
      _reactionStatus = widget.service.hasReacted(widget.snapshot.id);
      _commentController.clear();
      _commentFocusNode.unfocus();
      _submittingReaction = false;
      _reactedLocally = false;
      _sendingComment = false;
      _heartBurstController.reset();
    }
  }

  @override
  void dispose() {
    _heartBurstController.dispose();
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitReaction(String reaction) async {
    if (_submittingReaction || _reactedLocally) return;
    setState(() => _submittingReaction = true);
    try {
      await widget.service.reactOnce(widget.snapshot.id, reaction);
      if (!mounted) return;
      setState(() => _reactedLocally = true);
      if (reaction == '❤️') {
        unawaited(HapticFeedback.mediumImpact());
        unawaited(_heartBurstController.forward(from: 0));
      } else {
        unawaited(HapticFeedback.selectionClick());
      }
    } catch (_) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: SnapshotStrings.of(context).reactionFailed,
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _submittingReaction = false);
    }
  }

  Future<void> _sendComment() async {
    final message = _commentController.text.trim();
    if (_sendingComment || message.isEmpty) return;
    setState(() => _sendingComment = true);
    try {
      await widget.service.sendComment(widget.snapshot.id, message);
      if (!mounted) return;
      _commentController.clear();
      _commentFocusNode.unfocus();
      unawaited(HapticFeedback.lightImpact());
      AppSnackBar.show(
        context,
        message: SnapshotStrings.of(context).commentSent,
        type: AppSnackBarType.success,
      );
    } catch (_) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: SnapshotStrings.of(context).commentFailed,
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    return StreamBuilder<SnapshotItem?>(
      stream: _accessStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData &&
            !snapshot.hasError) {
          return const Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final inaccessible = snapshot.hasError ||
            (snapshot.connectionState != ConnectionState.waiting &&
                snapshot.data == null);
        if (inaccessible) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            Navigator.of(context).maybePop();
            AppSnackBar.show(context, message: strings.noAccess);
          });
          return const SizedBox.shrink();
        }
        final current = snapshot.data;
        if (current == null) return const SizedBox.shrink();
        final isOwner =
            FirebaseAuth.instance.currentUser?.uid == current.authorId;
        final mediaPadding = MediaQuery.paddingOf(context);
        final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
        final keyboardOpen = keyboardInset > 0;
        final horizontal = MediaQuery.sizeOf(context).width < 360
            ? 12.0
            : context.rs(16).clamp(14, 20).toDouble();
        return Stack(
          fit: StackFit.expand,
          children: [
            SnapshotStorageImage(
              snapshot: current,
              // 작성 화면에서 합성된 원본 비율을 그대로 보여준다. cover를 쓰면
              // 기기 화면비에 맞춰 좌우가 잘려 텍스트와 이미지가 확대되어 보인다.
              fit: snapshotDetailImageFit,
            ),
            const IgnorePointer(child: _SnapshotStoryScrim()),
            if (!isOwner)
              Positioned(
                left: horizontal - 4,
                right: horizontal - 4,
                bottom: mediaPadding.bottom + keyboardInset + 8,
                child: _SnapshotInteractionArea(
                  showReactions: !keyboardOpen,
                  reactionStatus: _reactionStatus,
                  reactedLocally: _reactedLocally,
                  submittingReaction: _submittingReaction,
                  reactionCounts: current.reactionCounts,
                  strings: strings,
                  onReact: _submitReaction,
                  commentController: _commentController,
                  commentFocusNode: _commentFocusNode,
                  sendingComment: _sendingComment,
                  onSendComment: _sendComment,
                ),
              ),
            if (!isOwner)
              Positioned(
                left: horizontal,
                right: horizontal,
                bottom: mediaPadding.bottom + keyboardInset + 54,
                height: 190,
                child: IgnorePointer(
                  child: _SnapshotHeartBurst(
                    animation: _heartBurstController,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SnapshotTapNavigation extends StatelessWidget {
  const _SnapshotTapNavigation({
    required this.canGoPrevious,
    required this.canGoNext,
    required this.previousLabel,
    required this.nextLabel,
    required this.onPrevious,
    required this.onNext,
  });

  final bool canGoPrevious;
  final bool canGoNext;
  final String previousLabel;
  final String nextLabel;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            enabled: canGoPrevious,
            label: previousLabel,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: canGoPrevious ? onPrevious : null,
              child: const SizedBox.expand(),
            ),
          ),
        ),
        Expanded(
          child: Semantics(
            button: true,
            enabled: canGoNext,
            label: nextLabel,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: canGoNext ? onNext : null,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }
}

class _SnapshotPositionIndicator extends StatelessWidget {
  const _SnapshotPositionIndicator({
    required this.count,
    required this.index,
  });

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2.5,
      child: Row(
        children: List.generate(count, (itemIndex) {
          return Expanded(
            child: AnimatedContainer(
              duration: _SnapshotDetailScreenState._switchDuration,
              curve: Curves.easeOutCubic,
              margin: EdgeInsets.only(right: itemIndex == count - 1 ? 0 : 3),
              decoration: BoxDecoration(
                color: itemIndex == index
                    ? Colors.white
                    : Colors.white.withValues(alpha: .34),
                borderRadius: BorderRadius.circular(99),
                boxShadow: itemIndex == index
                    ? const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 3,
                        ),
                      ]
                    : null,
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _SnapshotStoryScrim extends StatelessWidget {
  const _SnapshotStoryScrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, .24, .68, 1],
          colors: [
            Colors.black.withValues(alpha: .64),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: .62),
          ],
        ),
      ),
    );
  }
}

class _SnapshotAuthorHeader extends StatelessWidget {
  const _SnapshotAuthorHeader({
    required this.snapshot,
    required this.visibility,
    required this.remaining,
  });

  final SnapshotItem snapshot;
  final String visibility;
  final String remaining;

  @override
  Widget build(BuildContext context) {
    final avatarRadius = context.rs(18).clamp(17, 20).toDouble();
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(1.5),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: CircleAvatar(
              radius: avatarRadius,
              backgroundColor: const Color(0xFF475467),
              backgroundImage: snapshot.authorPhotoUrl.isNotEmpty
                  ? NetworkImage(snapshot.authorPhotoUrl)
                  : null,
              child: snapshot.authorPhotoUrl.isEmpty
                  ? Icon(
                      Icons.person_outline_rounded,
                      size: context.ri(19).clamp(18, 21).toDouble(),
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
          SizedBox(width: context.rs(10).clamp(8, 12).toDouble()),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: context.rf(15).clamp(14, 16).toDouble(),
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.18,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 6),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        visibility,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: context.rf(12).clamp(11.5, 13).toDouble(),
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: .9),
                          height: 1.2,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '·',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    Text(
                      remaining,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: context.rf(12).clamp(11.5, 13).toDouble(),
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: .9),
                        height: 1.2,
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 6),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SnapshotInteractionArea extends StatelessWidget {
  const _SnapshotInteractionArea({
    required this.showReactions,
    required this.reactionStatus,
    required this.reactedLocally,
    required this.submittingReaction,
    required this.reactionCounts,
    required this.strings,
    required this.onReact,
    required this.commentController,
    required this.commentFocusNode,
    required this.sendingComment,
    required this.onSendComment,
  });

  final bool showReactions;
  final Future<bool> reactionStatus;
  final bool reactedLocally;
  final bool submittingReaction;
  final Map<String, int> reactionCounts;
  final SnapshotStrings strings;
  final Future<void> Function(String) onReact;
  final TextEditingController commentController;
  final FocusNode commentFocusNode;
  final bool sendingComment;
  final Future<void> Function() onSendComment;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showReactions)
          FutureBuilder<bool>(
            future: reactionStatus,
            builder: (context, reactionState) {
              final hasReacted = reactedLocally || reactionState.data == true;
              final interactionDisabled = submittingReaction || hasReacted;

              return IgnorePointer(
                // 이미 반응한 스낵도 반응 종류와 집계는 계속 보여 주되,
                // 서버의 1회 반응 정책에 맞춰 중복 입력만 차단한다.
                ignoring: interactionDisabled,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: interactionDisabled ? .58 : 1,
                  child: _SnapshotReactionBar(
                    reactionCounts: reactionCounts,
                    strings: strings,
                    onReact: onReact,
                  ),
                ),
              );
            },
          ),
        if (showReactions) const SizedBox(height: 4),
        _SnapshotCommentComposer(
          controller: commentController,
          focusNode: commentFocusNode,
          hintText: strings.commentHint,
          sendLabel: strings.sendComment,
          sending: sendingComment,
          onSend: onSendComment,
        ),
      ],
    );
  }
}

class _SnapshotCommentComposer extends StatelessWidget {
  const _SnapshotCommentComposer({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.sendLabel,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final String sendLabel;
  final bool sending;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Material(
        color: Colors.black.withValues(alpha: .48),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: context.rh(48, min: 46, max: 52),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            readOnly: sending,
            maxLength: 120,
            maxLines: 1,
            textInputAction: TextInputAction.send,
            keyboardAppearance: Brightness.dark,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: context.rf(15).clamp(14, 16).toDouble(),
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: hintText,
              hintStyle: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: context.rf(15).clamp(14, 16).toDouble(),
                color: Colors.white.withValues(alpha: .72),
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.only(left: 18, top: 13),
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 48, minHeight: 46),
              suffixIcon: Semantics(
                button: true,
                label: sendLabel,
                child: IconButton(
                  tooltip: sendLabel,
                  onPressed: sending ? null : onSend,
                  icon: sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                ),
              ),
            ),
            onSubmitted: (_) {
              if (!sending) onSend();
            },
          ),
        ),
      ),
    );
  }
}

class _HeartParticleSpec {
  const _HeartParticleSpec({
    required this.dx,
    required this.rise,
    required this.size,
    required this.delay,
    required this.rotation,
    required this.color,
  });

  final double dx;
  final double rise;
  final double size;
  final double delay;
  final double rotation;
  final Color color;
}

class _SnapshotHeartBurst extends StatelessWidget {
  const _SnapshotHeartBurst({required this.animation});

  final Animation<double> animation;

  static const List<_HeartParticleSpec> _particles = [
    _HeartParticleSpec(
      dx: -72,
      rise: 132,
      size: 22,
      delay: .02,
      rotation: -.24,
      color: AppColors.pointColor,
    ),
    _HeartParticleSpec(
      dx: -42,
      rise: 164,
      size: 17,
      delay: .10,
      rotation: .18,
      color: Color(0xFF8CC4FF),
    ),
    _HeartParticleSpec(
      dx: -15,
      rise: 112,
      size: 19,
      delay: .04,
      rotation: -.08,
      color: AppColors.pointColor,
    ),
    _HeartParticleSpec(
      dx: 18,
      rise: 174,
      size: 21,
      delay: .12,
      rotation: .16,
      color: Color(0xFF8CC4FF),
    ),
    _HeartParticleSpec(
      dx: 48,
      rise: 122,
      size: 16,
      delay: .06,
      rotation: -.18,
      color: AppColors.pointColor,
    ),
    _HeartParticleSpec(
      dx: 74,
      rise: 152,
      size: 23,
      delay: .14,
      rotation: .24,
      color: Color(0xFF8CC4FF),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final progress = animation.value;
        if (progress <= 0 || progress >= 1) {
          return const SizedBox.shrink();
        }

        final centerProgress = Curves.easeOutBack.transform(
          (progress / .42).clamp(0.0, 1.0),
        );
        final centerOpacity = progress < .58
            ? 1.0
            : (1 - ((progress - .58) / .42)).clamp(0.0, 1.0);

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Transform.scale(
              scale: centerProgress,
              child: Opacity(
                opacity: centerOpacity,
                child: const Icon(
                  Icons.favorite_rounded,
                  size: 52,
                  color: AppColors.pointColor,
                  shadows: [
                    Shadow(color: Colors.white70, blurRadius: 10),
                    Shadow(color: Colors.black45, blurRadius: 14),
                  ],
                ),
              ),
            ),
            for (final particle in _particles)
              _buildParticle(particle, progress),
          ],
        );
      },
    );
  }

  Widget _buildParticle(_HeartParticleSpec particle, double progress) {
    final local =
        ((progress - particle.delay) / (1 - particle.delay)).clamp(0.0, 1.0);
    if (local <= 0) return const SizedBox.shrink();

    final travel = Curves.easeOutCubic.transform(local);
    final opacity = local < .58
        ? (local / .18).clamp(0.0, 1.0)
        : (1 - ((local - .58) / .42)).clamp(0.0, 1.0);
    final horizontalDrift =
        particle.dx * travel + math.sin(local * math.pi) * particle.dx.sign * 8;

    return Transform.translate(
      offset: Offset(horizontalDrift, -particle.rise * travel),
      child: Transform.rotate(
        angle: particle.rotation * travel,
        child: Opacity(
          opacity: opacity,
          child: Icon(
            Icons.favorite_rounded,
            size: particle.size * (.72 + (.28 * travel)),
            color: particle.color,
            shadows: const [
              Shadow(color: Colors.black54, blurRadius: 7),
            ],
          ),
        ),
      ),
    );
  }
}

class _SnapshotReactionBar extends StatelessWidget {
  const _SnapshotReactionBar({
    required this.reactionCounts,
    required this.strings,
    required this.onReact,
  });

  final Map<String, int> reactionCounts;
  final SnapshotStrings strings;
  final Future<void> Function(String) onReact;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: context.rs(6).clamp(2, 8).toDouble(),
          runSpacing: 0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _SnapshotReactionButton(
              icon: Icons.favorite_rounded,
              iconColor: AppColors.pointColor,
              label: strings.likeReaction,
              count: reactionCounts['❤️'] ?? 0,
              onTap: () => onReact('❤️'),
            ),
            _SnapshotReactionButton(
              icon: Icons.waving_hand_outlined,
              label: strings.applauseReaction,
              count: reactionCounts['👏'] ?? 0,
              onTap: () => onReact('👏'),
            ),
            _SnapshotReactionButton(
              icon: Icons.sentiment_satisfied_alt_outlined,
              label: strings.smileReaction,
              count: reactionCounts['😊'] ?? 0,
              onTap: () => onReact('😊'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SnapshotReactionButton extends StatelessWidget {
  const _SnapshotReactionButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = count > 0 ? '$label $count' : label;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: context.ri(21).clamp(20, 23).toDouble(),
                  color: iconColor,
                  shadows: iconColor == Colors.black
                      ? const [Shadow(color: Colors.white, blurRadius: 5)]
                      : const [Shadow(color: Colors.black54, blurRadius: 6)],
                ),
                if (count > 0) ...[
                  const SizedBox(width: 5),
                  Text(
                    _compactReactionCount(count),
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: context.rf(13).clamp(12, 14).toDouble(),
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.15,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 6),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _compactReactionCount(int count) {
  if (count < 1000) return '$count';
  if (count < 1000000) {
    final value = count / 1000;
    return '${value >= 10 ? value.round() : value.toStringAsFixed(1)}K';
  }
  final value = count / 1000000;
  return '${value >= 10 ? value.round() : value.toStringAsFixed(1)}M';
}

class _SnapshotDeleteDialog extends StatelessWidget {
  const _SnapshotDeleteDialog({required this.strings});

  final SnapshotStrings strings;

  @override
  Widget build(BuildContext context) {
    const dangerColor = Color(0xFFD92D20);
    const primaryText = Color(0xFF111827);
    const secondaryText = Color(0xFF667085);
    final horizontalInset = context.rs(28).clamp(20, 36).toDouble();
    final contentPadding = context.rs(22).clamp(20, 24).toDouble();
    final verticalInset = context.rs(24).clamp(16, 32).toDouble();

    return Dialog(
      backgroundColor: Colors.white,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              contentPadding,
              contentPadding,
              context.rs(16).clamp(12, 18).toDouble(),
              context.rs(12).clamp(10, 14).toDouble(),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.delete,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: context.rf(17).clamp(16, 18).toDouble(),
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: primaryText,
                  ),
                ),
                SizedBox(height: context.rs(8).clamp(6, 10).toDouble()),
                Text(
                  strings.deleteConfirm,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: context.rf(14.5).clamp(13.5, 15.5).toDouble(),
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: primaryText,
                  ),
                ),
                SizedBox(height: context.rs(4).clamp(3, 6).toDouble()),
                Text(
                  strings.isKorean
                      ? '삭제한 스낵은 다시 복구할 수 없어요.'
                      : 'This snack cannot be restored after deletion.',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: context.rf(13).clamp(12.5, 14).toDouble(),
                    fontWeight: FontWeight.w400,
                    height: 1.5,
                    color: secondaryText,
                  ),
                ),
                SizedBox(height: context.rs(14).clamp(12, 18).toDouble()),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: _snapshotDeleteActionStyle(secondaryText),
                        child: Text(
                          strings.cancel,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          Navigator.pop(context, true);
                        },
                        style: _snapshotDeleteActionStyle(dangerColor),
                        child: Text(
                          strings.delete,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

ButtonStyle _snapshotDeleteActionStyle(Color foregroundColor) =>
    TextButton.styleFrom(
      foregroundColor: foregroundColor,
      minimumSize: const Size(64, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Icon(icon, size: 21, color: const Color(0xFF475467)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _visibilityLabel(
  SnapshotStrings strings,
  SnapshotVisibility visibility,
) {
  return switch (visibility) {
    SnapshotVisibility.public => strings.public,
    SnapshotVisibility.friends => strings.friends,
    SnapshotVisibility.category => strings.selectedGroups,
  };
}

String _snapshotRemainingLabel(
  SnapshotItem snapshot,
  SnapshotService service,
  SnapshotStrings strings,
) {
  final duration = snapshot.remainingAt(service.serverNow);
  if (duration.inHours >= 1) {
    return '${duration.inHours}h ${strings.remaining}';
  }
  return '${duration.inMinutes.clamp(1, 59)}m ${strings.remaining}';
}
