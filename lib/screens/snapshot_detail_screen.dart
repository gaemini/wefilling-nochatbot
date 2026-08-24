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
import 'snapshot_viewers_screen.dart';

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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const Duration _switchDuration = Duration(milliseconds: 240);
  static const Duration _playbackDuration = Duration(seconds: 7);
  static const Duration _positionVisibilityDuration =
      Duration(milliseconds: 1400);

  final SnapshotService _service = SnapshotService.instance;
  final DMService _dmService = DMService();
  late List<SnapshotItem> _items;
  late int _index;
  Timer? _ticker;
  Timer? _switchTimer;
  Timer? _positionTimer;
  late final AnimationController _playbackController;
  bool _isSwitching = false;
  bool _isHolding = false;
  bool _isAppInactive = false;
  bool _isComposingComment = false;
  bool _reactionSlotAvailable = true;
  bool _showFeedPosition = false;
  String? _mediaReadyId;
  double _horizontalDragDistance = 0;

  SnapshotItem get _current => _items[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playbackController = AnimationController(
      vsync: this,
      duration: _playbackDuration,
    )..addStatusListener(_handlePlaybackStatus);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recheckExpiry();
      _recordCurrentView();
      _restartPlayback();
      _preloadCurrentAndNext();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _switchTimer?.cancel();
    _positionTimer?.cancel();
    _playbackController
      ..removeStatusListener(_handlePlaybackStatus)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppInactive = false;
      _resumePlaybackIfAllowed();
      unawaited(_service.refreshServerClock().then((_) => _recheckExpiry()));
      unawaited(_service.syncMyFeed());
    } else {
      _isAppInactive = true;
      _playbackController.stop();
    }
  }

  void _handlePlaybackStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted || _items.isEmpty) {
      return;
    }
    if (_index < _items.length - 1) {
      _moveTo(_index + 1, haptic: false);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  bool get _playbackCanRun =>
      mounted &&
      _mediaReadyId == _current.id &&
      !_isHolding &&
      !_isAppInactive &&
      !_isComposingComment;

  void _restartPlayback() {
    if (!mounted || _items.isEmpty) return;
    _playbackController.value = 0;
    if (_playbackCanRun) _playbackController.forward();
  }

  void _resumePlaybackIfAllowed() {
    if (!_playbackCanRun || _playbackController.isAnimating) return;
    if (_playbackController.value >= 1) {
      _restartPlayback();
    } else {
      _playbackController.forward();
    }
  }

  void _setHolding(bool holding) {
    if (_isHolding == holding) return;
    _isHolding = holding;
    if (holding) {
      _playbackController.stop();
    } else {
      _resumePlaybackIfAllowed();
    }
  }

  void _setCommentComposerFocused(bool focused) {
    if (_isComposingComment == focused) return;
    _isComposingComment = focused;
    if (focused) {
      _playbackController.stop();
    } else {
      _resumePlaybackIfAllowed();
    }
  }

  void _handleMediaReady(String snapshotId) {
    if (!mounted || _current.id != snapshotId) return;
    _mediaReadyId = snapshotId;
    // 첫 프레임 기록이 네트워크 문제로 지연된 경우 이미지 준비 시점에 한 번
    // 더 합류한다. 서비스가 동일 요청을 단일 Future로 병합하므로 중복 쓰기는 없다.
    _recordCurrentView();
    _resumePlaybackIfAllowed();
  }

  void _handleReactionAvailabilityChanged(
    String snapshotId,
    bool isAvailable,
  ) {
    if (!mounted || _current.id != snapshotId) return;
    if (_reactionSlotAvailable == isAvailable) return;
    setState(() => _reactionSlotAvailable = isAvailable);
  }

  void _recordCurrentView() {
    if (!mounted || _items.isEmpty) return;
    final item = _current;
    if (FirebaseAuth.instance.currentUser?.uid == item.authorId) return;
    unawaited(_service.recordView(item.id));
  }

  Future<void> _openViewers() async {
    if (_items.isEmpty ||
        FirebaseAuth.instance.currentUser?.uid != _current.authorId) {
      return;
    }
    final snapshotId = _current.id;
    _playbackController.stop();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SnapshotViewersScreen(snapshotId: snapshotId),
      ),
    );
    if (mounted) _resumePlaybackIfAllowed();
  }

  Future<void> _warmImage(SnapshotItem item) async {
    try {
      await _service.loadImageBytes(item);
    } catch (_) {
      // 실제 이미지 위젯의 오류/재시도 처리가 사용자에게 상태를 표시한다.
    }
  }

  void _preloadCurrentAndNext() {
    if (!mounted || _items.isEmpty) return;
    unawaited(_warmImage(_current));
    final nextIndex = _index + 1;
    if (nextIndex < _items.length) {
      unawaited(_warmImage(_items[nextIndex]));
    }
  }

  void _showTransientFeedPosition() {
    _positionTimer?.cancel();
    if (!_showFeedPosition) {
      setState(() => _showFeedPosition = true);
    }
    _positionTimer = Timer(_positionVisibilityDuration, () {
      if (!mounted) return;
      setState(() => _showFeedPosition = false);
    });
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
    final resolvedIndex = newIndex >= 0 ? newIndex : 0;
    final contentsChanged = filtered.length != _items.length ||
        !List<bool>.generate(
          filtered.length,
          (index) => filtered[index].id == _items[index].id,
        ).every((same) => same);
    if (!contentsChanged && resolvedIndex == _index) return;
    final currentChanged = filtered[resolvedIndex].id != currentId;
    setState(() {
      _items = filtered;
      _index = resolvedIndex;
      if (currentChanged) _reactionSlotAvailable = true;
    });
    _recordCurrentView();
    _restartPlayback();
    _preloadCurrentAndNext();
  }

  void _moveTo(int targetIndex, {bool haptic = true}) {
    if (_isSwitching || targetIndex < 0 || targetIndex >= _items.length) {
      return;
    }
    if (targetIndex == _index) return;

    _switchTimer?.cancel();
    if (haptic) HapticFeedback.selectionClick();
    setState(() {
      _index = targetIndex;
      _isSwitching = true;
      // 새 스낵의 반응 여부를 확인하는 동안에는 하트 자리를 유지해
      // 비동기 결과로 입력창이 겹치지 않도록 한다.
      _reactionSlotAvailable = true;
    });
    _recordCurrentView();
    _restartPlayback();
    _preloadCurrentAndNext();
    _showTransientFeedPosition();
    _switchTimer = Timer(_switchDuration, () {
      if (!mounted) return;
      setState(() => _isSwitching = false);
    });
  }

  void _showPrevious() => _moveTo(_index - 1);

  void _showNext() => _moveTo(_index + 1);

  void _handleHorizontalDragStart(DragStartDetails details) {
    _horizontalDragDistance = 0;
    _playbackController.stop();
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    _horizontalDragDistance += details.primaryDelta ?? 0;
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldGoNext = _horizontalDragDistance < -48 || velocity < -320;
    final shouldGoPrevious = _horizontalDragDistance > 48 || velocity > 320;
    _horizontalDragDistance = 0;
    if (shouldGoNext) {
      _showNext();
    } else if (shouldGoPrevious) {
      _showPrevious();
    } else {
      _resumePlaybackIfAllowed();
    }
  }

  Future<void> _showActions() async {
    _playbackController.stop();
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
    if (!mounted) return;
    if (action == null) {
      _resumePlaybackIfAllowed();
      return;
    }
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
    if (mounted) _resumePlaybackIfAllowed();
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
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final isOwner = FirebaseAuth.instance.currentUser?.uid == _current.authorId;
    final horizontalInset = MediaQuery.sizeOf(context).width < 360
        ? 12.0
        : context.rs(16).clamp(14, 20).toDouble();
    final reactionSlotWidth = context.rs(48).clamp(46, 52).toDouble();
    final reserveReactionSlot = _reactionSlotAvailable && keyboardInset <= 0;
    final ownerViewerEntryHeight = context.rh(66, min: 62, max: 72);
    final reactionExclusionHeight = (isOwner
            ? ownerViewerEntryHeight
            : context.rh(112, min: 104, max: 124)) +
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
        body: SafeArea(
          child: Column(
            children: [
              _SnapshotTopRegion(
                snapshot: _current,
                visibility: _visibilityLabel(strings, _current.visibility),
                remaining: _snapshotRemainingLabel(
                  _current,
                  _service,
                  strings,
                ),
                playback: _playbackController,
                onBack: () => Navigator.of(context).maybePop(),
                onMore: _showActions,
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: _handleHorizontalDragStart,
                  onHorizontalDragUpdate: _handleHorizontalDragUpdate,
                  onHorizontalDragEnd: _handleHorizontalDragEnd,
                  onHorizontalDragCancel: _resumePlaybackIfAllowed,
                  onLongPressStart: (_) => _setHolding(true),
                  onLongPressEnd: (_) => _setHolding(false),
                  onLongPressCancel: () => _setHolding(false),
                  child: Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.hardEdge,
                    children: [
                      AnimatedSwitcher(
                        duration: _switchDuration,
                        reverseDuration: _switchDuration,
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        layoutBuilder: (currentChild, previousChildren) =>
                            Stack(
                          fit: StackFit.expand,
                          children: [
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        ),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: CurvedAnimation(
                            parent: animation,
                            curve: const Interval(
                              .08,
                              1,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                          child: child,
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(_current.id),
                          child: _SnapshotDetailPage(
                            snapshot: _current,
                            service: _service,
                            onMediaReady: _handleMediaReady,
                            onReactionAvailabilityChanged:
                                _handleReactionAvailabilityChanged,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
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
                      if (!isOwner)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          left: horizontalInset +
                              (reserveReactionSlot ? reactionSlotWidth + 6 : 0),
                          right: horizontalInset,
                          bottom: keyboardInset + 8,
                          child: _SnapshotCommentLayer(
                            key: ValueKey<String>(
                              'snapshot-comment-${_current.id}',
                            ),
                            snapshotId: _current.id,
                            service: _service,
                            strings: strings,
                            onFocusChanged: _setCommentComposerFocused,
                          ),
                        ),
                      if (isOwner)
                        Positioned(
                          left: MediaQuery.sizeOf(context).width < 360
                              ? 10
                              : context.rs(14).clamp(12, 18).toDouble(),
                          right: MediaQuery.sizeOf(context).width < 360
                              ? 10
                              : context.rs(14).clamp(12, 18).toDouble(),
                          bottom: 4,
                          child: _SnapshotViewerEntry(
                            key: ValueKey<String>(
                              'snapshot-viewers-${_current.id}',
                            ),
                            snapshotId: _current.id,
                            service: _service,
                            strings: strings,
                            onTap: _openViewers,
                          ),
                        ),
                      if (_items.length > 1)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: keyboardInset +
                              (isOwner ? ownerViewerEntryHeight + 6 : 112),
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              opacity: _showFeedPosition ? 1 : 0,
                              child: _SnapshotFeedPositionToast(
                                label: strings.feedPosition(
                                  _index + 1,
                                  _items.length,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SnapshotDetailPage extends StatefulWidget {
  const _SnapshotDetailPage({
    required this.snapshot,
    required this.service,
    required this.onMediaReady,
    required this.onReactionAvailabilityChanged,
  });
  final SnapshotItem snapshot;
  final SnapshotService service;
  final ValueChanged<String> onMediaReady;
  final void Function(String snapshotId, bool isAvailable)
      onReactionAvailabilityChanged;

  @override
  State<_SnapshotDetailPage> createState() => _SnapshotDetailPageState();
}

class _SnapshotDetailPageState extends State<_SnapshotDetailPage>
    with SingleTickerProviderStateMixin {
  late Stream<SnapshotItem?> _accessStream;
  late Future<bool> _reactionStatus;
  late final AnimationController _heartBurstController;
  bool _submittingReaction = false;
  bool _reactedLocally = false;

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
    _refreshReactionStatus();
  }

  @override
  void didUpdateWidget(covariant _SnapshotDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.id != widget.snapshot.id) {
      _accessStream = widget.service.watchSnapshot(
        widget.snapshot.id,
        initial: widget.snapshot,
      );
      _submittingReaction = false;
      _reactedLocally = false;
      _refreshReactionStatus();
      _heartBurstController.reset();
    }
  }

  void _reportReactionAvailability(String snapshotId, bool isAvailable) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.snapshot.id != snapshotId) return;
      widget.onReactionAvailabilityChanged(snapshotId, isAvailable);
    });
  }

  void _refreshReactionStatus() {
    final snapshotId = widget.snapshot.id;
    final status = widget.service.hasReacted(snapshotId);
    _reactionStatus = status;
    unawaited(
      status.then(
        (hasReacted) {
          if (!mounted || widget.snapshot.id != snapshotId) return;
          _reportReactionAvailability(
            snapshotId,
            !hasReacted && !_reactedLocally,
          );
        },
        onError: (_) {
          // 상태를 확인하지 못하면 하트 입력도 열지 않는다. 코멘트 입력창은
          // 불필요한 빈 슬롯 없이 사용할 수 있게 한다.
          _reportReactionAvailability(snapshotId, false);
        },
      ),
    );
  }

  @override
  void dispose() {
    _heartBurstController.dispose();
    super.dispose();
  }

  Future<void> _submitReaction(String reaction) async {
    if (_submittingReaction || _reactedLocally) return;
    final snapshotId = widget.snapshot.id;
    setState(() {
      _submittingReaction = true;
      _reactedLocally = true;
    });
    _reportReactionAvailability(snapshotId, false);
    if (reaction == '❤️') {
      unawaited(HapticFeedback.mediumImpact());
      unawaited(_heartBurstController.forward(from: 0));
    } else {
      unawaited(HapticFeedback.selectionClick());
    }
    try {
      await widget.service.reactOnce(snapshotId, reaction);
    } catch (_) {
      if (!mounted || widget.snapshot.id != snapshotId) return;
      setState(() {
        _reactedLocally = false;
        _refreshReactionStatus();
      });
      _heartBurstController.reset();
      AppSnackBar.show(
        context,
        message: SnapshotStrings.of(context).reactionFailed,
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted && widget.snapshot.id == snapshotId) {
        setState(() => _submittingReaction = false);
      }
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
          return const ColoredBox(color: Colors.black);
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
        final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
        final keyboardOpen = keyboardInset > 0;
        final horizontal = MediaQuery.sizeOf(context).width < 360
            ? 12.0
            : context.rs(16).clamp(14, 20).toDouble();
        return Stack(
          fit: StackFit.expand,
          children: [
            _SnapshotMediaCanvas(
              snapshot: current,
              onReady: () => widget.onMediaReady(current.id),
            ),
            const IgnorePointer(child: _SnapshotStoryScrim()),
            if (!isOwner)
              Positioned(
                left: horizontal,
                width: context.rs(48).clamp(46, 52).toDouble(),
                bottom: keyboardInset + 8,
                child: _SnapshotInteractionArea(
                  showReactions: !keyboardOpen,
                  reactionStatus: _reactionStatus,
                  reactedLocally: _reactedLocally,
                  submittingReaction: _submittingReaction,
                  strings: strings,
                  onReact: _submitReaction,
                ),
              ),
            if (!isOwner)
              Positioned(
                left: horizontal,
                right: horizontal,
                bottom: keyboardInset + 54,
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

/// 상단 UI를 제외한 실제 미디어 영역 안에서 합성 캔버스 전체를 정중앙에 둔다.
///
/// 현재 저장 이미지는 작성 화면에서 사진과 텍스트 오버레이를 하나의 프레임으로
/// 합성한 결과다. 따라서 이 SizedBox가 사진·텍스트·향후 합성 오버레이가 공유하는
/// 단일 좌표계가 되며, 화면 비율이 달라져도 함께 같은 비율로 이동·축소된다.
class _SnapshotMediaCanvas extends StatelessWidget {
  const _SnapshotMediaCanvas({
    required this.snapshot,
    required this.onReady,
  });

  final SnapshotItem snapshot;
  final VoidCallback onReady;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final source = Size(snapshot.aspectRatio, 1);
          final canvasSize = applyBoxFit(
            snapshotDetailImageFit,
            source,
            viewport,
          ).destination;
          return Center(
            child: SizedBox.fromSize(
              size: canvasSize,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SnapshotStorageImage(
                    snapshot: snapshot,
                    fit: snapshotDetailImageFit,
                    placeholderColor: Colors.black,
                    errorBackgroundColor: Colors.black,
                    showLoadingIndicator: false,
                    fadeInDuration: const Duration(milliseconds: 180),
                    onImageReady: onReady,
                  ),
                ],
              ),
            ),
          );
        },
      ),
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

class _SnapshotTopRegion extends StatelessWidget {
  const _SnapshotTopRegion({
    required this.snapshot,
    required this.visibility,
    required this.remaining,
    required this.playback,
    required this.onBack,
    required this.onMore,
  });

  final SnapshotItem snapshot;
  final String visibility;
  final String remaining;
  final Animation<double> playback;
  final VoidCallback onBack;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: context.rh(56, min: 54, max: 60),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 48,
                  child: IconButton(
                    onPressed: onBack,
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      size: context.ri(22).clamp(21, 24).toDouble(),
                      color: Colors.white,
                    ),
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _SnapshotAuthorHeader(
                      snapshot: snapshot,
                      visibility: visibility,
                      remaining: remaining,
                    ),
                  ),
                ),
                SizedBox.square(
                  dimension: 48,
                  child: IconButton(
                    onPressed: onMore,
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      size: context.ri(23).clamp(21, 25).toDouble(),
                      color: Colors.white,
                    ),
                    tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 12, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 3,
                child: AnimatedBuilder(
                  animation: playback,
                  builder: (context, child) => LinearProgressIndicator(
                    value: playback.value,
                    backgroundColor: Colors.white.withValues(alpha: .26),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SnapshotViewerEntry extends StatefulWidget {
  const _SnapshotViewerEntry({
    super.key,
    required this.snapshotId,
    required this.service,
    required this.strings,
    required this.onTap,
  });

  final String snapshotId;
  final SnapshotService service;
  final SnapshotStrings strings;
  final VoidCallback onTap;

  @override
  State<_SnapshotViewerEntry> createState() => _SnapshotViewerEntryState();
}

class _SnapshotViewerEntryState extends State<_SnapshotViewerEntry> {
  late Stream<List<SnapshotViewer>> _viewersStream;

  @override
  void initState() {
    super.initState();
    _viewersStream = widget.service.watchViewers(widget.snapshotId);
  }

  @override
  void didUpdateWidget(covariant _SnapshotViewerEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshotId != widget.snapshotId) {
      _viewersStream = widget.service.watchViewers(widget.snapshotId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SnapshotViewer>>(
      stream: _viewersStream,
      builder: (context, snapshot) {
        final count = snapshot.data?.length;
        final supportingText = snapshot.hasError
            ? widget.strings.viewersLoadFailed
            : count == null
                ? widget.strings.viewersLoading
                : count == 0
                    ? widget.strings.noViewers
                    : widget.strings.viewersCount(count);
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Semantics(
            button: true,
            label: supportingText,
            excludeSemantics: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: context.rh(58, min: 54, max: 64),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 40,
                          child: Icon(
                            Icons.visibility_outlined,
                            size: context.ri(23).clamp(21, 25).toDouble(),
                            color: Colors.white,
                            shadows: const [
                              Shadow(color: Colors.black54, blurRadius: 6),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: context.rs(8).clamp(6, 10).toDouble(),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.strings.viewers,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize:
                                      context.rf(14).clamp(13, 15).toDouble(),
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  height: 1.15,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                supportingText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize: context
                                      .rf(11.5)
                                      .clamp(11, 12.5)
                                      .toDouble(),
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: .78),
                                  height: 1.15,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox.square(
                          dimension: 40,
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: context.ri(22).clamp(21, 24).toDouble(),
                            color: Colors.white.withValues(alpha: .86),
                            shadows: const [
                              Shadow(color: Colors.black54, blurRadius: 6),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SnapshotFeedPositionToast extends StatelessWidget {
  const _SnapshotFeedPositionToast({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Center(
        child: Semantics(
          label: label,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .48),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(11).clamp(10.5, 12).toDouble(),
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: .72),
                  height: 1.1,
                ),
              ),
            ),
          ),
        ),
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
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
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
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
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
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
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
    required this.strings,
    required this.onReact,
  });

  final bool showReactions;
  final Future<bool> reactionStatus;
  final bool reactedLocally;
  final bool submittingReaction;
  final SnapshotStrings strings;
  final Future<void> Function(String) onReact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: const ValueKey<String>('snapshot-reaction-area'),
          child: showReactions
              ? FutureBuilder<bool>(
                  future: reactionStatus,
                  builder: (context, reactionState) {
                    // 반응 여부가 확정되기 전에는 입력을 열지 않는다.
                    // 이전에는 FutureBuilder의 초기 data(null)를 false처럼 처리해
                    // 이미 반응한 스낵에도 하트가 한 프레임 노출될 수 있었다.
                    final isStatusResolved =
                        reactionState.connectionState == ConnectionState.done &&
                            !reactionState.hasError;
                    final hasReacted =
                        reactedLocally || reactionState.data == true;
                    if (!isStatusResolved || hasReacted) {
                      return const SizedBox.shrink();
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: IgnorePointer(
                        ignoring: submittingReaction,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 120),
                          opacity: submittingReaction ? 0 : 1,
                          child: _SnapshotReactionBar(
                            strings: strings,
                            onReact: onReact,
                          ),
                        ),
                      ),
                    );
                  },
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// 코멘트 입력 수명주기를 이미지/반응 스트림과 분리한다.
///
/// 키보드가 열릴 때 MediaQuery와 스낵 접근 스트림이 다시 빌드되어도 이 State는
/// 현재 스낵 ID가 바뀌기 전까지 유지되므로 TextField의 포커스와 조합 중인 문자가
/// 취소되지 않는다.
class _SnapshotCommentLayer extends StatefulWidget {
  const _SnapshotCommentLayer({
    super.key,
    required this.snapshotId,
    required this.service,
    required this.strings,
    required this.onFocusChanged,
  });

  final String snapshotId;
  final SnapshotService service;
  final SnapshotStrings strings;
  final ValueChanged<bool> onFocusChanged;

  @override
  State<_SnapshotCommentLayer> createState() => _SnapshotCommentLayerState();
}

class _SnapshotCommentLayerState extends State<_SnapshotCommentLayer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'snapshot-comment');
  bool _checkingStatus = true;
  bool _hasCommented = true;
  bool _sending = false;
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
    _focusNode.addListener(_handleFocusChanged);
    unawaited(_loadStatus());
  }

  @override
  void didUpdateWidget(covariant _SnapshotCommentLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshotId == widget.snapshotId) return;
    _controller.clear();
    _focusNode.unfocus();
    _checkingStatus = true;
    _hasCommented = true;
    _sending = false;
    unawaited(_loadStatus());
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    widget.onFocusChanged(_focusNode.hasFocus);
  }

  void _handleTextChanged() {
    final canSend = _controller.text.trim().isNotEmpty;
    if (canSend == _canSend || !mounted) return;
    setState(() => _canSend = canSend);
  }

  Future<void> _loadStatus() async {
    final requestedSnapshotId = widget.snapshotId;
    final hasCommented = await widget.service.hasCommented(requestedSnapshotId);
    if (!mounted || widget.snapshotId != requestedSnapshotId) return;
    setState(() {
      _hasCommented = hasCommented;
      _checkingStatus = false;
    });
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (_sending || _hasCommented || message.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.service.sendComment(widget.snapshotId, message);
      if (!mounted) return;
      setState(() {
        _hasCommented = true;
        _sending = false;
        _canSend = false;
      });
      _controller.clear();
      _focusNode.unfocus();
      unawaited(HapticFeedback.lightImpact());
      AppSnackBar.show(
        context,
        message: widget.strings.commentSent,
        type: AppSnackBarType.success,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      // 실패 시 본문과 포커스를 그대로 유지해 바로 다시 보낼 수 있게 한다.
      if (!_focusNode.hasFocus) _focusNode.requestFocus();
      AppSnackBar.show(
        context,
        message: widget.strings.commentFailed,
        type: AppSnackBarType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingStatus || _hasCommented) return const SizedBox.shrink();
    return _SnapshotCommentComposer(
      controller: _controller,
      focusNode: _focusNode,
      hintText: widget.strings.commentHint,
      sendLabel: widget.strings.sendComment,
      sending: _sending,
      canSend: _canSend,
      onSend: _send,
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
    required this.canSend,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final String sendLabel;
  final bool sending;
  final bool canSend;
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
            maxLength: 120,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            keyboardAppearance: Brightness.dark,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: context.rf(15).clamp(14, 16).toDouble(),
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: hintText,
              hintStyle: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
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
                  onPressed: sending || !canSend ? null : onSend,
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
    required this.strings,
    required this.onReact,
  });

  final SnapshotStrings strings;
  final Future<void> Function(String) onReact;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: SizedBox(
        width: double.infinity,
        child: Align(
          alignment: Alignment.centerLeft,
          child: _SnapshotReactionButton(
            icon: Icons.favorite_rounded,
            iconColor: AppColors.pointColor,
            label: strings.likeReaction,
            onTap: () => onReact('❤️'),
          ),
        ),
      ),
    );
  }
}

class _SnapshotReactionButton extends StatelessWidget {
  const _SnapshotReactionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              icon,
              size: context.ri(21).clamp(20, 23).toDouble(),
              color: iconColor,
              shadows: iconColor == Colors.black
                  ? const [Shadow(color: Colors.white, blurRadius: 5)]
                  : const [Shadow(color: Colors.black54, blurRadius: 6)],
            ),
          ),
        ),
      ),
    );
  }
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
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
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
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
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
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
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
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
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
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
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
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
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
    return strings.isKorean
        ? '${duration.inHours}시간 ${strings.remaining}'
        : '${duration.inHours}h ${strings.remaining}';
  }
  final minutes = duration.inMinutes.clamp(1, 59);
  return strings.isKorean
      ? '$minutes분 ${strings.remaining}'
      : '${minutes}m ${strings.remaining}';
}
