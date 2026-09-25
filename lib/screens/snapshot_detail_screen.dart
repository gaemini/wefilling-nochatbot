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
import '../services/notification_service.dart';
import '../snapshot/snapshot_storage_image.dart';
import '../snapshot/snapshot_storage_video.dart';
import '../snapshot/snapshot_author_profile_image.dart';
import '../snapshot/snapshot_strings.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../utils/responsive_helper.dart';
import 'dm_chat_screen.dart';
import 'friend_profile_screen.dart';
import 'snapshot_viewers_screen.dart';
import 'snapshot_comments_sheet.dart';
import '../l10n/ui_locale.dart';

/// 상세 화면에서도 작성 화면에서 합성한 전체 프레임을 보존한다.
const BoxFit snapshotDetailImageFit = BoxFit.contain;

class SnapshotDetailScreen extends StatefulWidget {
  const SnapshotDetailScreen({
    super.key,
    required this.snapshots,
    required this.initialIndex,
    this.openCommentsInitially = false,
    this.focusCommentId,
  });

  final List<SnapshotItem> snapshots;
  final int initialIndex;
  final bool openCommentsInitially;
  final String? focusCommentId;

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
  bool _isHolding = false;
  bool _isAppInactive = false;
  bool _isComposingComment = false;
  bool _isModalPaused = false;
  String? _deletingSnapshotId;
  String? _mediaReadyId;
  String? _manualResumeSnapshotId;
  String? _unavailableSnapshotId;
  double _horizontalDragDistance = 0;
  int _displayedAgeMinutes = -1;

  SnapshotItem get _current => _items[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _items = List<SnapshotItem>.of(widget.snapshots);
    final requestedId = widget.snapshots.isEmpty
        ? ''
        : widget
              .snapshots[widget.initialIndex.clamp(
                0,
                widget.snapshots.length - 1,
              )]
              .id;
    _index = _items.indexWhere((item) => item.id == requestedId);
    if (_index < 0) _index = 0;
    if (_items.isNotEmpty) {
      _displayedAgeMinutes = _snapshotAgeMinutes(_current, _service.serverNow);
      if (_current.isExpiredAt(_service.serverNow)) {
        _unavailableSnapshotId = _current.id;
        _manualResumeSnapshotId = _current.id;
      }
    }
    _ticker = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _recheckExpiry(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recheckExpiry();
      if (_items.isNotEmpty && _unavailableSnapshotId != _current.id) {
        _recordCurrentView();
        _preloadCurrentAndNext();
      }
      if (widget.openCommentsInitially && _items.isNotEmpty) {
        unawaited(_openComments(focusCommentId: widget.focusCommentId));
      }
    });
  }

  @override
  void didUpdateWidget(covariant SnapshotDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_items.isEmpty || identical(oldWidget.snapshots, widget.snapshots)) {
      return;
    }
    final current = _current;
    final incoming = List<SnapshotItem>.of(widget.snapshots);
    var nextIndex = incoming.indexWhere((item) => item.id == current.id);
    if (nextIndex >= 0) {
      // 상세 실시간 구독에서 받은 하트·댓글 상태를 목록 재정렬이 되돌리지
      // 않도록 현재 항목은 유지한다.
      incoming[nextIndex] = current;
    } else {
      nextIndex = _index.clamp(0, incoming.length);
      incoming.insert(nextIndex, current);
    }
    final idsChanged =
        incoming.length != _items.length ||
        List<int>.generate(incoming.length, (index) => index).any(
          (index) =>
              index >= _items.length || incoming[index].id != _items[index].id,
        );
    if (!idsChanged) return;
    _items = incoming;
    _index = nextIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _unavailableSnapshotId == _current.id) return;
      _preloadCurrentAndNext();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_service.cancelVideoPreloads());
    _ticker?.cancel();
    _switchTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _isAppInactive = false);
      unawaited(_service.refreshServerClock().then((_) => _recheckExpiry()));
      unawaited(_service.syncMyFeed());
    } else {
      setState(() => _isAppInactive = true);
      unawaited(_service.cancelVideoPreloads());
    }
  }

  bool get _currentVideoCanPlay =>
      mounted &&
      _current.isVideo &&
      _mediaReadyId == _current.id &&
      !_isHolding &&
      !_isAppInactive &&
      !_isComposingComment &&
      !_isModalPaused &&
      _manualResumeSnapshotId != _current.id &&
      _unavailableSnapshotId != _current.id &&
      _deletingSnapshotId == null;

  void _setHolding(bool holding) {
    if (_isHolding == holding) return;
    setState(() => _isHolding = holding);
  }

  void _handleMediaReady(String snapshotId) {
    if (!mounted || _current.id != snapshotId) return;
    setState(() => _mediaReadyId = snapshotId);
    // 첫 프레임 기록이 네트워크 문제로 지연된 경우 이미지 준비 시점에 한 번
    // 더 합류한다. 서비스가 동일 요청을 단일 Future로 병합하므로 중복 쓰기는 없다.
    _recordCurrentView();
    if (!_current.isVideo) {
      _confirmCurrentNotification();
      _preloadNextVideo();
    }
  }

  void _handleSnapshotChanged(SnapshotItem latest) {
    if (!mounted) return;
    final itemIndex = _items.indexWhere((item) => item.id == latest.id);
    if (itemIndex < 0) {
      return;
    }
    final previous = _items[itemIndex];
    if (previous.commentCount == latest.commentCount &&
        _sameReactionCounts(previous.reactionCounts, latest.reactionCounts)) {
      return;
    }
    setState(() => _items[itemIndex] = latest);
  }

  void _handleVideoFirstFrame(String snapshotId) {
    if (!mounted || _current.id != snapshotId) return;
    _confirmCurrentNotification();
    _preloadNextVideo();
  }

  void _recordCurrentView() {
    if (!mounted || _items.isEmpty) return;
    if (FirebaseAuth.instance.currentUser?.uid == _current.authorId) return;
    unawaited(_service.recordView(_current.id));
  }

  void _confirmCurrentNotification() {
    if (!mounted || _items.isEmpty || _unavailableSnapshotId == _current.id ||
        _isAppInactive || _isModalPaused) return;
    final item = _current;
    unawaited(
      NotificationService().markRelatedNotificationsAsRead(
        types: const <String>{
          'snapshot_reaction',
        },
        targets: <String, String>{'snapshotId': item.id},
      ),
    );
  }

  Future<void> _openComments({String? focusCommentId}) async {
    if (!mounted ||
        _items.isEmpty ||
        _isComposingComment ||
        _unavailableSnapshotId == _current.id) {
      return;
    }
    final snapshotId = _current.id;
    final snapshot = _current;
    setState(() {
      _isComposingComment = true;
      if (snapshot.isVideo) _manualResumeSnapshotId = snapshotId;
    });
    unawaited(_service.cancelVideoPreloads());
    try {
      await SnapshotCommentsSheet.show(
        context,
        snapshot: snapshot,
        focusCommentId: focusCommentId,
      );
    } finally {
      if (mounted) {
        setState(() => _isComposingComment = false);
        if (_current.id == snapshotId && _mediaReadyId == snapshotId) {
          _preloadNextVideo();
        }
      }
    }
  }

  Future<void> _openLetterComposer() async {
    if (!mounted ||
        _items.isEmpty ||
        _isModalPaused ||
        _unavailableSnapshotId == _current.id ||
        FirebaseAuth.instance.currentUser?.uid == _current.authorId) {
      return;
    }
    final snapshotId = _current.id;
    setState(() => _isModalPaused = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _SnapshotLetterComposerSheet(
          snapshotId: snapshotId,
          service: _service,
        ),
      );
    } finally {
      if (mounted) setState(() => _isModalPaused = false);
    }
  }

  Future<void> _openViewers() async {
    if (_items.isEmpty ||
        FirebaseAuth.instance.currentUser?.uid != _current.authorId) {
      return;
    }
    final snapshotId = _current.id;
    setState(() => _isModalPaused = true);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SnapshotViewersScreen(snapshotId: snapshotId),
      ),
    );
    if (mounted) setState(() => _isModalPaused = false);
  }

  Future<void> _openAuthorProfile() async {
    if (_items.isEmpty) return;
    final item = _current;
    final userId = item.authorId.trim();
    if (userId.isEmpty || userId.toLowerCase() == 'deleted') return;

    setState(() => _isModalPaused = true);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          userId: userId,
          nickname: item.authorName,
          photoURL: item.authorPhotoUrl,
          university: item.university,
          allowNonFriendsPreview: true,
        ),
      ),
    );
    if (mounted) setState(() => _isModalPaused = false);
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
    final retainedVideoIds = <String>{};
    if (_current.isVideo) retainedVideoIds.add(_current.id);
    final nextIndex = _index + 1;
    if (nextIndex < _items.length && _items[nextIndex].isVideo) {
      retainedVideoIds.add(_items[nextIndex].id);
    }
    unawaited(
      _service.cancelVideoPreloads(exceptSnapshotIds: retainedVideoIds),
    );
    unawaited(_warmImage(_current));
    if (nextIndex < _items.length) {
      unawaited(_warmImage(_items[nextIndex]));
    }
  }

  void _preloadNextVideo() {
    if (!mounted || _items.isEmpty || _isAppInactive || _isComposingComment) {
      return;
    }
    final nextIndex = _index + 1;
    if (nextIndex >= _items.length) return;
    final next = _items[nextIndex];
    if (!next.isVideo) return;

    // 현재 미디어가 준비된 뒤 다음 영상 하나만 받아 초기 다운로드가
    // 경쟁하지 않게 한다. 실제 화면 진입 시에는 같은 Future/파일을 재사용한다.
    unawaited(
      _service
          .preloadVideoFile(next)
          .then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  void _recheckExpiry() {
    if (!mounted || _items.isEmpty) return;
    final now = _service.serverNow;
    final currentId = _current.id;
    if (_current.isExpiredAt(now)) {
      _markCurrentUnavailable(currentId);
      return;
    }
    final ageMinutes = _snapshotAgeMinutes(_current, now);
    if (ageMinutes != _displayedAgeMinutes) {
      setState(() => _displayedAgeMinutes = ageMinutes);
    }
  }

  void _moveTo(int targetIndex, {bool haptic = true}) {
    if (_isSwitching ||
        _isComposingComment ||
        _isModalPaused ||
        targetIndex < 0 ||
        targetIndex >= _items.length) {
      return;
    }
    if (targetIndex == _index) return;

    _switchTimer?.cancel();
    if (haptic) HapticFeedback.selectionClick();
    setState(() {
      _index = targetIndex;
      _isSwitching = true;
      _mediaReadyId = null;
      _manualResumeSnapshotId = null;
      _unavailableSnapshotId = _current.isExpiredAt(_service.serverNow)
          ? _current.id
          : null;
      _displayedAgeMinutes = _snapshotAgeMinutes(_current, _service.serverNow);
    });
    if (_unavailableSnapshotId == null) {
      _recordCurrentView();
      _preloadCurrentAndNext();
    }
    _switchTimer = Timer(_switchDuration, () {
      if (!mounted) return;
      setState(() => _isSwitching = false);
    });
  }

  void _showPrevious() => _moveTo(_index - 1);

  void _showNext() => _moveTo(_index + 1);

  void _handleHorizontalDragStart(DragStartDetails details) {
    _horizontalDragDistance = 0;
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
    }
  }

  void _markCurrentUnavailable(String snapshotId) {
    if (!mounted || _items.isEmpty || _current.id != snapshotId) return;
    if (_unavailableSnapshotId == snapshotId) return;
    setState(() {
      _unavailableSnapshotId = snapshotId;
      _manualResumeSnapshotId = snapshotId;
      _mediaReadyId = null;
    });
    unawaited(_service.cancelVideoLoad(snapshotId));
    unawaited(_service.cancelVideoPreloads());
  }

  void _handleVideoPlayRequested(String snapshotId) {
    if (!mounted || _items.isEmpty || _current.id != snapshotId) return;
    if (_manualResumeSnapshotId == snapshotId) {
      setState(() => _manualResumeSnapshotId = null);
    }
  }

  Future<void> _showActions() async {
    if (_unavailableSnapshotId == _current.id) return;
    setState(() => _isModalPaused = true);
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
      setState(() => _isModalPaused = false);
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
    if (mounted) setState(() => _isModalPaused = false);
  }

  Future<void> _deleteCurrent() async {
    if (_deletingSnapshotId != null || _items.isEmpty) return;
    final strings = SnapshotStrings.of(context);
    final deletingId = _current.id;
    HapticFeedback.mediumImpact();
    final confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          barrierColor: const Color(0x99000000),
          useSafeArea: true,
          builder: (dialogContext) => _SnapshotDeleteDialog(strings: strings),
        ) ??
        false;
    if (!confirmed ||
        !mounted ||
        _items.every((item) => item.id != deletingId)) {
      return;
    }
    setState(() => _deletingSnapshotId = deletingId);
    try {
      await _service.deleteSnapshot(deletingId);
      if (!mounted) return;
      setState(() {
        _deletingSnapshotId = null;
        _unavailableSnapshotId = deletingId;
        _manualResumeSnapshotId = deletingId;
        _mediaReadyId = null;
      });
      unawaited(_service.cancelVideoLoad(deletingId));
      unawaited(_service.cancelVideoPreloads());
    } catch (_) {
      if (mounted) {
        setState(() => _deletingSnapshotId = null);
        AppSnackBar.show(
          context,
          message: (isChineseUi(context)
              ? '删除失败。'
              : strings.isKorean
              ? '삭제하지 못했어요.'
              : 'Could not delete it.'),
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
          message: (isChineseUi(context)
              ? '无法发起私信。'
              : strings.isKorean
              ? '메시지를 시작하지 못했어요.'
              : 'Could not start a message.'),
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
      AppSnackBar.show(
        context,
        message: strings.reportDone,
        type: AppSnackBarType.success,
      );
    }
  }

  Future<void> _block() async {
    final strings = SnapshotStrings.of(context);
    final ok = await ReportService.blockUser(_current.authorId);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      AppSnackBar.show(
        context,
        message: strings.blockDone,
        type: AppSnackBarType.success,
      );
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
    final interactionsEnabled =
        _unavailableSnapshotId != _current.id && _deletingSnapshotId == null;
    final navigationEnabled =
        _deletingSnapshotId == null && !_isComposingComment && !_isModalPaused;
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
                createdLabel: _snapshotCreatedLabel(
                  _current,
                  _service,
                  strings,
                ),
                onBack: () => Navigator.of(context).maybePop(),
                onAuthorTap: interactionsEnabled ? _openAuthorProfile : null,
                onMore: interactionsEnabled ? _showActions : null,
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: navigationEnabled
                      ? (details) {
                          final width = MediaQuery.sizeOf(context).width;
                          if (details.localPosition.dx < width / 2) {
                            _showPrevious();
                          } else {
                            _showNext();
                          }
                        }
                      : null,
                  onHorizontalDragStart: navigationEnabled
                      ? _handleHorizontalDragStart
                      : null,
                  onHorizontalDragUpdate: navigationEnabled
                      ? _handleHorizontalDragUpdate
                      : null,
                  onHorizontalDragEnd: navigationEnabled
                      ? _handleHorizontalDragEnd
                      : null,
                  onLongPressStart: interactionsEnabled
                      ? (_) => _setHolding(true)
                      : null,
                  onLongPressEnd: interactionsEnabled
                      ? (_) => _setHolding(false)
                      : null,
                  onLongPressCancel: interactionsEnabled
                      ? () => _setHolding(false)
                      : null,
                  child: ColoredBox(
                    color: Colors.black,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey<String>('snapshot-page-${_current.id}'),
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: _switchDuration,
                      curve: Curves.easeOutCubic,
                      builder: (context, opacity, child) =>
                          Opacity(opacity: opacity, child: child),
                      child: _SnapshotDetailPage(
                        snapshot: _current,
                        service: _service,
                        deleting: _deletingSnapshotId == _current.id,
                        unavailable: _unavailableSnapshotId == _current.id,
                        manualResumeRequired:
                            _manualResumeSnapshotId == _current.id,
                        onMediaReady: _handleMediaReady,
                        onVideoFirstFrame: _handleVideoFirstFrame,
                        onSnapshotChanged: _handleSnapshotChanged,
                        onUnavailable: _markCurrentUnavailable,
                        onVideoPlayRequested: _handleVideoPlayRequested,
                        onComments: () => _openComments(),
                        onLetter: _openLetterComposer,
                        onViewers: _openViewers,
                        playing: _currentVideoCanPlay,
                      ),
                    ),
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
    required this.deleting,
    required this.unavailable,
    required this.manualResumeRequired,
    required this.onMediaReady,
    required this.onVideoFirstFrame,
    required this.onSnapshotChanged,
    required this.onUnavailable,
    required this.onVideoPlayRequested,
    required this.onComments,
    required this.onLetter,
    required this.onViewers,
    required this.playing,
  });
  final SnapshotItem snapshot;
  final SnapshotService service;
  final bool deleting;
  final bool unavailable;
  final bool manualResumeRequired;
  final ValueChanged<String> onMediaReady;
  final ValueChanged<String> onVideoFirstFrame;
  final ValueChanged<SnapshotItem> onSnapshotChanged;
  final ValueChanged<String> onUnavailable;
  final ValueChanged<String> onVideoPlayRequested;
  final VoidCallback onComments;
  final VoidCallback onLetter;
  final VoidCallback onViewers;
  final bool playing;

  @override
  State<_SnapshotDetailPage> createState() => _SnapshotDetailPageState();
}

class _SnapshotDetailPageState extends State<_SnapshotDetailPage>
    with SingleTickerProviderStateMixin {
  late Stream<SnapshotItem?> _accessStream;
  StreamSubscription<bool>? _reactionSubscription;
  late final AnimationController _heartBurstController;
  bool _submittingReaction = false;
  bool _reactedLocally = false;
  bool _reactionStatusResolved = false;
  bool _hasReacted = true;
  int? _lastReportedCommentCount;
  late Map<String, int> _lastReportedReactionCounts;
  int _reactionStatusGeneration = 0;
  String? _confirmingReactionSnapshotId;

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
    _lastReportedCommentCount = widget.snapshot.commentCount;
    _lastReportedReactionCounts = Map<String, int>.of(
      widget.snapshot.reactionCounts,
    );
    final cachedReaction = widget.service.cachedMyReaction(widget.snapshot.id);
    _reactionStatusResolved = cachedReaction != null;
    _hasReacted = cachedReaction ?? true;
    if (!widget.deleting) _watchReactionStatus();
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
      _lastReportedCommentCount = widget.snapshot.commentCount;
      _lastReportedReactionCounts = Map<String, int>.of(
        widget.snapshot.reactionCounts,
      );
      if (!widget.deleting) _watchReactionStatus();
      _heartBurstController.reset();
    } else if (oldWidget.deleting != widget.deleting) {
      if (widget.deleting) {
        unawaited(_reactionSubscription?.cancel());
        _reactionSubscription = null;
        _reactionStatusResolved = false;
        _hasReacted = true;
      } else {
        _watchReactionStatus();
      }
    }
  }

  void _watchReactionStatus() {
    final snapshotId = widget.snapshot.id;
    final generation = ++_reactionStatusGeneration;
    unawaited(_reactionSubscription?.cancel());
    final cachedReaction = widget.service.cachedMyReaction(snapshotId);
    _reactionStatusResolved = cachedReaction != null;
    _hasReacted = cachedReaction ?? true;
    _reactionSubscription = widget.service
        .watchMyReaction(snapshotId)
        .listen(
          (hasReacted) {
            if (!mounted ||
                generation != _reactionStatusGeneration ||
                widget.snapshot.id != snapshotId) {
              return;
            }
            setState(() {
              _reactionStatusResolved = true;
              _hasReacted = hasReacted;
            });
          },
          onError: (_) {
            if (!mounted ||
                generation != _reactionStatusGeneration ||
                widget.snapshot.id != snapshotId) {
              return;
            }
            final cachedReaction = widget.service.cachedMyReaction(snapshotId);
            setState(() {
              _reactionStatusResolved = cachedReaction != null;
              _hasReacted = cachedReaction ?? true;
            });
            unawaited(_confirmReactionStatus(snapshotId, generation));
          },
        );
    unawaited(_confirmReactionStatus(snapshotId, generation));
  }

  Future<void> _confirmReactionStatus(String snapshotId, int generation) async {
    if (_confirmingReactionSnapshotId == snapshotId) return;
    _confirmingReactionSnapshotId = snapshotId;
    try {
      final hasReacted = await widget.service.hasReacted(snapshotId);
      if (!mounted ||
          generation != _reactionStatusGeneration ||
          widget.snapshot.id != snapshotId) {
        return;
      }
      setState(() {
        _reactionStatusResolved = true;
        _hasReacted = hasReacted;
      });
    } catch (_) {
      // 실시간 문서 구독이 살아 있으면 그 결과를 유지한다. 두 경로가 모두
      // 실패한 경우에도 미확인 상태를 미반응으로 단정하지 않는다.
    } finally {
      if (_confirmingReactionSnapshotId == snapshotId) {
        _confirmingReactionSnapshotId = null;
      }
    }
  }

  @override
  void dispose() {
    _reactionStatusGeneration++;
    unawaited(_reactionSubscription?.cancel());
    _heartBurstController.dispose();
    super.dispose();
  }

  Future<void> _submitReaction(String reaction) async {
    if (widget.deleting ||
        _submittingReaction ||
        _reactedLocally ||
        _hasReacted) {
      return;
    }
    final snapshotId = widget.snapshot.id;
    setState(() {
      _submittingReaction = true;
      _reactedLocally = true;
    });
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
      });
      _watchReactionStatus();
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
      initialData: widget.snapshot,
      builder: (context, snapshot) {
        if (widget.unavailable) {
          return _SnapshotUnavailableView(message: strings.noAccess);
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData &&
            !snapshot.hasError) {
          return const ColoredBox(color: Colors.black);
        }
        final inaccessible =
            snapshot.hasError ||
            (snapshot.connectionState != ConnectionState.waiting &&
                snapshot.data == null);
        if (inaccessible && !widget.deleting) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || widget.snapshot.id.isEmpty) return;
            widget.onUnavailable(widget.snapshot.id);
          });
          return _SnapshotUnavailableView(message: strings.noAccess);
        }
        // 삭제 Callable이 canonical 문서를 먼저 제거해도 완료 응답을
        // 받기 전까지는 기존 미디어 프레임을 유지해 검은 화면을 막는다.
        final current = snapshot.data ?? widget.snapshot;
        if (_lastReportedCommentCount != current.commentCount ||
            !_sameReactionCounts(
              _lastReportedReactionCounts,
              current.reactionCounts,
            ) ||
            widget.snapshot.authorName != current.authorName ||
            widget.snapshot.authorPhotoUrl != current.authorPhotoUrl ||
            widget.snapshot.authorPhotoVersion != current.authorPhotoVersion) {
          _lastReportedCommentCount = current.commentCount;
          _lastReportedReactionCounts = Map<String, int>.of(
            current.reactionCounts,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || widget.snapshot.id != current.id) return;
            widget.onSnapshotChanged(current);
          });
        }
        final isOwner =
            FirebaseAuth.instance.currentUser?.uid == current.authorId;
        final reactionCount = current.reactionCounts.values.fold<int>(
          0,
          (total, count) => total + count.clamp(0, 1 << 30),
        );
        return Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _SnapshotMediaCanvas(
                    snapshot: current,
                    playing: widget.playing,
                    manualResumeRequired: widget.manualResumeRequired,
                    onReady: () => widget.onMediaReady(current.id),
                    onVideoFirstFrame: () =>
                        widget.onVideoFirstFrame(current.id),
                    onVideoPlayRequested: () =>
                        widget.onVideoPlayRequested(current.id),
                  ),
                  if (!isOwner && !widget.deleting)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 18,
                      height: 190,
                      child: IgnorePointer(
                        child: _SnapshotHeartBurst(
                          animation: _heartBurstController,
                        ),
                      ),
                    ),
                  if (widget.deleting)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: .18),
                          child: const Center(
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!widget.deleting)
              _SnapshotBottomControls(
                snapshotId: current.id,
                service: widget.service,
                strings: strings,
                isOwner: isOwner,
                reactionCount: reactionCount,
                commentCount: current.commentCount,
                reactionStatusResolved: _reactionStatusResolved,
                hasReacted: _hasReacted,
                reactedLocally: _reactedLocally,
                submittingReaction: _submittingReaction,
                onReact: _submitReaction,
                onComments: widget.onComments,
                onLetter: widget.onLetter,
                onViewers: widget.onViewers,
              ),
          ],
        );
      },
    );
  }
}

class _SnapshotBottomControls extends StatelessWidget {
  const _SnapshotBottomControls({
    required this.snapshotId,
    required this.service,
    required this.strings,
    required this.isOwner,
    required this.reactionCount,
    required this.commentCount,
    required this.reactionStatusResolved,
    required this.hasReacted,
    required this.reactedLocally,
    required this.submittingReaction,
    required this.onReact,
    required this.onComments,
    required this.onLetter,
    required this.onViewers,
  });

  final String snapshotId;
  final SnapshotService service;
  final SnapshotStrings strings;
  final bool isOwner;
  final int reactionCount;
  final int commentCount;
  final bool reactionStatusResolved;
  final bool hasReacted;
  final bool reactedLocally;
  final bool submittingReaction;
  final Future<void> Function(String) onReact;
  final VoidCallback onComments;
  final VoidCallback onLetter;
  final VoidCallback onViewers;

  @override
  Widget build(BuildContext context) {
    final selected = reactedLocally || (reactionStatusResolved && hasReacted);
    final canReact =
        !isOwner && reactionStatusResolved && !selected && !submittingReaction;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: SizedBox(
        height: context.rh(62, min: 58, max: 68),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SnapshotBottomAction(
              icon: selected
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              iconColor: selected ? AppColors.pointColor : Colors.white,
              label: strings.likeReaction,
              count: reactionCount,
              selected: selected,
              onTap: canReact ? () => onReact('❤️') : null,
            ),
            _SnapshotBottomAction(
              icon: Icons.chat_bubble_outline_rounded,
              label: strings.comments,
              count: commentCount,
              onTap: onComments,
            ),
            if (isOwner)
              _SnapshotViewerCountAction(
                key: ValueKey<String>('snapshot-viewers-$snapshotId'),
                snapshotId: snapshotId,
                service: service,
                strings: strings,
                onTap: onViewers,
              )
            else
              _SnapshotBottomAction(
                icon: Icons.mail_outline_rounded,
                label: strings.snackLetter,
                onTap: onLetter,
              ),
          ],
        ),
      ),
    );
  }
}

class _SnapshotBottomAction extends StatelessWidget {
  const _SnapshotBottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = Colors.white,
    this.count,
    this.selected = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final safeCount = count?.clamp(0, 1 << 30);
    final semanticsLabel = safeCount == null ? label : '$label $safeCount';
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      selected: selected,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: onTap,
          radius: 26,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 52, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: iconColor,
                    size: context.ri(25).clamp(23, 27).toDouble(),
                  ),
                  if (safeCount != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      _compactCount(safeCount),
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        color: Colors.white,
                        fontSize: context.rf(12).clamp(11.5, 13).toDouble(),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SnapshotViewerCountAction extends StatefulWidget {
  const _SnapshotViewerCountAction({
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
  State<_SnapshotViewerCountAction> createState() =>
      _SnapshotViewerCountActionState();
}

class _SnapshotViewerCountActionState
    extends State<_SnapshotViewerCountAction> {
  late Stream<List<SnapshotViewer>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.service.watchViewers(widget.snapshotId);
  }

  @override
  void didUpdateWidget(covariant _SnapshotViewerCountAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshotId != widget.snapshotId) {
      _stream = widget.service.watchViewers(widget.snapshotId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SnapshotViewer>>(
      stream: _stream,
      builder: (context, snapshot) => _SnapshotBottomAction(
        icon: Icons.visibility_outlined,
        label: widget.strings.viewers,
        count: snapshot.data?.length ?? 0,
        onTap: widget.onTap,
      ),
    );
  }
}

class _SnapshotUnavailableView extends StatelessWidget {
  const _SnapshotUnavailableView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
            color: const Color(0xFFB8C0CC),
            fontSize: context.rf(14).clamp(13.5, 15).toDouble(),
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _SnapshotLetterComposerSheet extends StatefulWidget {
  const _SnapshotLetterComposerSheet({
    required this.snapshotId,
    required this.service,
  });

  final String snapshotId;
  final SnapshotService service;

  @override
  State<_SnapshotLetterComposerSheet> createState() =>
      _SnapshotLetterComposerSheetState();
}

class _SnapshotLetterComposerSheetState
    extends State<_SnapshotLetterComposerSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'snapshot-letter');
  bool _checking = true;
  bool _hasSent = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStatus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final snapshotId = widget.snapshotId;
    final hasSent = await widget.service.hasCommented(snapshotId);
    if (!mounted || widget.snapshotId != snapshotId) return;
    setState(() {
      _hasSent = hasSent;
      _checking = false;
    });
    if (!hasSent) _focusNode.requestFocus();
  }

  Future<void> _send() async {
    if (_sending || _hasSent) return;
    _focusNode.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final message = _controller.text.trim();
    if (message.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.service.sendComment(widget.snapshotId, message);
      if (!mounted) return;
      setState(() {
        _hasSent = true;
        _sending = false;
      });
      _controller.clear();
      AppSnackBar.show(
        context,
        message: SnapshotStrings.of(context).commentSent,
        type: AppSnackBarType.success,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      AppSnackBar.show(
        context,
        message: SnapshotStrings.of(context).commentFailed,
        type: AppSnackBarType.error,
      );
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.snackLetter,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(17).clamp(16, 18).toDouble(),
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF101828),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (_checking)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_hasSent)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      strings.commentSent,
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(14).clamp(13.5, 15).toDouble(),
                        color: const Color(0xFF667085),
                      ),
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: context.rf(15).clamp(14, 16).toDouble(),
                            color: const Color(0xFF101828),
                          ),
                          decoration: InputDecoration(
                            hintText: strings.commentHint,
                            hintStyle: const TextStyle(
                              color: Color(0xFF98A2B3),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF2F4F7),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 11,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox.square(
                        dimension: 48,
                        child: IconButton(
                          onPressed: _sending ? null : _send,
                          tooltip: strings.sendComment,
                          icon: _sending
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
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

/// 상단 UI를 제외한 실제 미디어 영역 안에서 합성 캔버스 전체를 정중앙에 둔다.
///
/// 현재 저장 이미지는 작성 화면에서 사진과 텍스트 오버레이를 하나의 프레임으로
/// 합성한 결과다. 따라서 이 SizedBox가 사진·텍스트·향후 합성 오버레이가 공유하는
/// 단일 좌표계가 되며, 화면 비율이 달라져도 함께 같은 비율로 이동·축소된다.
class _SnapshotMediaCanvas extends StatelessWidget {
  const _SnapshotMediaCanvas({
    required this.snapshot,
    required this.playing,
    required this.manualResumeRequired,
    required this.onReady,
    required this.onVideoFirstFrame,
    required this.onVideoPlayRequested,
  });

  final SnapshotItem snapshot;
  final bool playing;
  final bool manualResumeRequired;
  final VoidCallback onReady;
  final VoidCallback onVideoFirstFrame;
  final VoidCallback onVideoPlayRequested;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
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
                  if (snapshot.isVideo) ...[
                    SnapshotStorageVideo(
                      snapshot: snapshot,
                      playing: playing,
                      onReady: onReady,
                      onFirstFrame: onVideoFirstFrame,
                      onPlaybackStable: onVideoFirstFrame,
                      showPlayButton: manualResumeRequired,
                      onPlayRequested: onVideoPlayRequested,
                    ),
                    IgnorePointer(
                      child: SnapshotOverlayLayer(overlays: snapshot.overlays),
                    ),
                  ] else
                    SnapshotStorageImage(
                      snapshot: snapshot,
                      fit: snapshotDetailImageFit,
                      placeholderColor: Colors.black,
                      errorBackgroundColor: Colors.black,
                      showLoadingIndicator: false,
                      fadeInDuration: Duration.zero,
                      decodeWidth:
                          (canvasSize.width *
                                  MediaQuery.devicePixelRatioOf(context))
                              .ceil()
                              .clamp(320, 2160),
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

class _SnapshotTopRegion extends StatelessWidget {
  const _SnapshotTopRegion({
    required this.snapshot,
    required this.createdLabel,
    required this.onBack,
    required this.onAuthorTap,
    required this.onMore,
  });

  final SnapshotItem snapshot;
  final String createdLabel;
  final VoidCallback onBack;
  final VoidCallback? onAuthorTap;
  final VoidCallback? onMore;

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
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                  ),
                ),
                Expanded(
                  child: Semantics(
                    button: true,
                    enabled: onAuthorTap != null,
                    label: snapshot.authorName,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onAuthorTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _SnapshotAuthorHeader(
                          snapshot: snapshot,
                          createdLabel: createdLabel,
                        ),
                      ),
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
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _SnapshotAuthorHeader extends StatelessWidget {
  const _SnapshotAuthorHeader({
    required this.snapshot,
    required this.createdLabel,
  });

  final SnapshotItem snapshot;
  final String createdLabel;

  @override
  Widget build(BuildContext context) {
    final avatarRadius = context.rs(18).clamp(17, 20).toDouble();
    final avatarSize = avatarRadius * 2;
    final decodeWidth = (avatarSize * MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(64, 256);
    final profile = SnapshotAuthorProfile.resolve(snapshot);
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
            child: SnapshotAuthorProfileImage(
              profile: profile,
              size: avatarSize,
              borderRadius: BorderRadius.circular(avatarSize / 2),
              decodeWidth: decodeWidth,
              placeholderColor: const Color(0xFF475467),
              placeholderIconColor: Colors.white,
              placeholderIconSize: context.ri(19).clamp(18, 21).toDouble(),
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
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: context.rf(15).clamp(14, 16).toDouble(),
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: isChineseUi(context) ? 1.3 : 1.18,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 6),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  createdLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: context.rf(12).clamp(11.5, 13).toDouble(),
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: .78),
                    height: isChineseUi(context) ? 1.3 : 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
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
    final local = ((progress - particle.delay) / (1 - particle.delay)).clamp(
      0.0,
      1.0,
    );
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
            shadows: const [Shadow(color: Colors.black54, blurRadius: 7)],
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
                    fontFamily: uiFontFamily(context, 'Inter'),
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
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: context.rf(14.5).clamp(13.5, 15.5).toDouble(),
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: primaryText,
                  ),
                ),
                SizedBox(height: context.rs(4).clamp(3, 6).toDouble()),
                Text(
                  (isChineseUi(context)
                      ? '删除后，此限时动态将无法恢复。'
                      : strings.isKorean
                      ? '삭제한 스낵은 다시 복구할 수 없어요.'
                      : 'This snack cannot be restored after deletion.'),
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
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
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
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
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
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
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
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

int _snapshotAgeMinutes(SnapshotItem snapshot, DateTime serverNow) {
  final age = serverNow.difference(snapshot.createdAt);
  if (age.isNegative) return 0;
  return age.inMinutes;
}

String _snapshotCreatedLabel(
  SnapshotItem snapshot,
  SnapshotService service,
  SnapshotStrings strings,
) {
  final minutes = _snapshotAgeMinutes(snapshot, service.serverNow);
  if (minutes < 1) return strings.viewedJustNow;
  if (minutes < 60) return strings.viewedMinutesAgo(minutes);
  return strings.viewedHoursAgo((minutes ~/ 60).clamp(1, 23));
}

bool _sameReactionCounts(Map<String, int> left, Map<String, int> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}

String _compactCount(int count) {
  if (count < 1000) return '$count';
  if (count < 1000000) {
    final value = count / 1000;
    return value >= 10
        ? '${value.floor()}K'
        : '${value.toStringAsFixed(1).replaceFirst('.0', '')}K';
  }
  final value = count / 1000000;
  return value >= 10
      ? '${value.floor()}M'
      : '${value.toStringAsFixed(1).replaceFirst('.0', '')}M';
}
