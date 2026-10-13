import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../models/snapshot.dart';
import '../services/content_translation_service.dart';
import '../services/dm_service.dart';
import '../services/report_service.dart';
import '../services/snapshot_service.dart';
import '../services/notification_service.dart';
import '../services/active_content_registry.dart';
import '../snapshot/snapshot_storage_image.dart';
import '../snapshot/snapshot_storage_video.dart';
import '../snapshot/snapshot_author_profile_image.dart';
import '../snapshot/snapshot_seen_store.dart';
import '../snapshot/snapshot_strings.dart';
import '../snapshot/snack_feature_flags.dart';
import '../snapshot/snack_feel_icon.dart';
import '../snapshot/snapshot_viewer_chrome.dart';
import '../models/relationship_status.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/widgets/motion_press.dart';
import '../utils/responsive_helper.dart';
import 'dm_chat_screen.dart';
import 'friend_profile_screen.dart';
import 'snapshot_activity_sheet.dart';
import 'snapshot_comments_sheet.dart';
import '../l10n/ui_locale.dart';
import '../l10n/relationship_strings.dart';
import '../services/first_response_request_service.dart';
import '../snapshot/snack_response_policy.dart';
import '../ui/sheets/snack_reply_sheet.dart';
import '../providers/relationship_provider.dart';
import 'package:provider/provider.dart';
import '../services/relationship_state_watcher.dart';
import '../ui/widgets/user_avatar.dart';
import 'create_meetup_screen.dart';

/// 상세 화면에서도 작성 화면에서 합성한 전체 프레임을 보존한다.
const BoxFit snapshotDetailImageFit = BoxFit.contain;

class SnapshotDetailMotionRoute extends MaterialPageRoute<void> {
  SnapshotDetailMotionRoute({
    required List<SnapshotItem> snapshots,
    required int initialIndex,
  }) : super(
            builder: (_) => SnapshotDetailScreen(
                snapshots: snapshots, initialIndex: initialIndex));

  @override
  Duration get transitionDuration => MotionTokens.medium;

  @override
  Duration get reverseTransitionDuration => MotionTokens.state;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    // Keep the platform's interactive back transition, not just its recognizer.
    if (!MotionTokens.reduceMotion(context) &&
        (Theme.of(context).platform == TargetPlatform.iOS ||
            navigator?.userGestureInProgress == true)) {
      return super.buildTransitions(
          context, animation, secondaryAnimation, child);
    }
    final curved = animation.drive(CurveTween(curve: MotionTokens.decelerate));
    return FadeTransition(
      opacity: curved,
      child: MotionTokens.reduceMotion(context)
          ? child
          : SlideTransition(
              position: curved
                  .drive(Tween(begin: const Offset(0, .015), end: Offset.zero)),
              child: child,
            ),
    );
  }
}

/// Paint-only page motion. It does not create or control the media player.
class SnapshotPageTransition extends StatelessWidget {
  const SnapshotPageTransition(
      {super.key,
      required this.progress,
      required this.direction,
      required this.child});
  final double progress;
  final int direction;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(
              MotionTokens.reduceMotion(context)
                  ? 0
                  : direction * 12 * (1 - progress),
              0),
          child: child,
        ),
      );
}

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
  Duration get _switchDuration => MotionTokens.reduceMotion(context)
      ? MotionTokens.instant
      : MotionTokens.state;

  final SnapshotService _service = SnapshotService.instance;
  final DMService _dmService = DMService();
  late List<SnapshotItem> _items;
  late int _index;
  Timer? _ticker;
  Timer? _switchTimer;
  bool _isSwitching = false;
  int _pageTransitionDirection = 0;
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
  // 번역 칩 상태. 기존 기본값(번역문 표시)을 유지한다.
  bool _captionTranslated = true;
  String _targetLanguageLabel = '';
  bool _isReplyFocused = false;
  final ValueNotifier<int> _heartTrigger = ValueNotifier<int>(0);
  Timer? _tapTimer;
  DateTime? _lastTapAt;

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
    FirstResponseRequestService.instance.ensureStarted();
    _ticker = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _recheckExpiry(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadTargetLanguageLabel());
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
    final idsChanged = incoming.length != _items.length ||
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
    ActiveContentRegistry.unregister(this);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_service.cancelVideoPreloads());
    _ticker?.cancel();
    _switchTimer?.cancel();
    _tapTimer?.cancel();
    _heartTrigger.dispose();
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid == _current.authorId) return;
    final viewedId = _current.id;
    unawaited(
      _service.recordView(viewedId).then<void>(
        (_) => SnapshotSeenStore.instance.markSeen(viewedId),
        onError: (Object _, StackTrace __) {},
      ),
    );
  }

  /// 스낵 답장. 친구에게는 3~5초 영상/사진을 DM으로 바로 보내고,
  /// 비친구에게는 친구 요청을 안내한다.
  Future<void> _openSnackReplyComposer() async {
    if (!mounted || _items.isEmpty || _isModalPaused) return;
    final item = _current;
    if (!item.responseMode.allowsSnackReply) return;
    setState(() => _isModalPaused = true);
    SnackReplyAction? action;
    try {
      final watcher = RelationshipStateWatcher.instance;
      final relationship = await watcher.resolve(item.authorId);
      if (!mounted) return;
      action = await showSnackReplySheet(
        context,
        relationship: relationship,
        friendRequestPending: watcher.friendRequestPendingTo(item.authorId),
      );
      if (!mounted || action == null) return;
      switch (action) {
        case SnackReplyAction.friendRequest:
          await _sendFriendRequestTo(item.authorId);
        case SnackReplyAction.recordVideo:
        case SnackReplyAction.takePhoto:
        case SnackReplyAction.pickFromGallery:
          final media = await pickSnackReplyMedia(context, action);
          if (!mounted || media == null) return;
          await _sendSnackReplyMedia(item, media);
      }
    } finally {
      if (mounted) setState(() => _isModalPaused = false);
    }
  }

  /// 친구 스낵의 글 답장. 새 전송 경로를 만들지 않고 DM 화면의 전송 흐름에
  /// 출처 한 줄(`snackReplyQuote`)과 함께 넘긴다.
  Future<void> _sendDmTextReply(String text) async {
    if (!mounted || _items.isEmpty) return;
    final item = _current;
    final relationshipStrings = RelationshipStrings.of(context);
    String? room;
    try {
      room = await _dmService.prepareConversationForOpen(item.authorId);
    } catch (_) {
      room = null;
    }
    if (!mounted) return;
    if (room == null) {
      AppSnackBar.show(
        context,
        message: relationshipStrings.openConversationFailed,
        type: AppSnackBarType.error,
      );
      return;
    }
    setState(() => _isModalPaused = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DMChatScreen(
            conversationId: room!,
            otherUserId: item.authorId,
            initialReplyText: text,
            initialReplyContext:
                relationshipStrings.snackReplyQuote(item.displayCaption),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isModalPaused = false);
    }
  }

  Future<void> _sendFriendRequestTo(String userId) async {
    final relationshipProvider = context.read<RelationshipProvider>();
    final success = await relationshipProvider.sendFriendRequest(userId);
    if (!mounted) return;
    if (success) RelationshipStateWatcher.instance.markRequestSent(userId);
    final strings = RelationshipStrings.of(context);
    AppSnackBar.show(
      context,
      message: success
          ? strings.friendRequestSentLocalized
          : strings.friendRequestError(relationshipProvider.actionErrorMessage),
      type: success ? AppSnackBarType.success : AppSnackBarType.error,
    );
  }

  /// 친구 DM 대화방을 열고, 기존 사진 미리보기/영상 확인 단계를 거쳐 보낸다.
  Future<void> _sendSnackReplyMedia(
    SnapshotItem item,
    SnackReplyMedia media,
  ) async {
    final relationshipStrings = RelationshipStrings.of(context);
    String? room;
    try {
      // 방은 사진·영상을 실제로 보낼 때 만들어진다(빈 방 방지).
      room = await _dmService.prepareConversationForOpen(item.authorId);
    } catch (_) {
      room = null;
    }
    if (!mounted) return;
    if (room == null) {
      AppSnackBar.show(
        context,
        message: relationshipStrings.openConversationFailed,
        type: AppSnackBarType.error,
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DMChatScreen(
          conversationId: room!,
          otherUserId: item.authorId,
          initialReplyMedia: media.file,
          initialReplyIsVideo: media.isVideo,
          initialReplyContext:
              relationshipStrings.snackReplyQuote(item.displayCaption),
        ),
      ),
    );
  }

  /// 조건부 밋업 초안. 제목만 미리 채워 기존 밋업 생성 화면을 재사용한다.
  Future<void> _openMeetupDraft() async {
    if (!mounted || _items.isEmpty) return;
    final item = _current;
    setState(() => _isModalPaused = true);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CreateMeetupScreen(
          initialDayIndex: 0,
          initialDate: DateTime.now(),
          onCreateMeetup: (_, __) {},
          initialTitle: item.displayCaption,
        ),
      ),
    );
    if (mounted) setState(() => _isModalPaused = false);
  }

  void _hideCurrent() {
    if (_items.isEmpty) return;
    _service.hideSnapshotLocally(_current.id);
    Navigator.of(context).pop();
    AppSnackBar.show(
      context,
      message: RelationshipStrings.of(context).hidden,
      type: AppSnackBarType.info,
    );
  }

  void _confirmCurrentNotification() {
    if (!mounted ||
        _items.isEmpty ||
        _unavailableSnapshotId == _current.id ||
        _isAppInactive ||
        _isModalPaused) return;
    final item = _current;
    // Capture owner/session now, like the other destination screens, so a
    // sign-out during the request can never confirm a read for a new account.
    unawaited(
      NotificationService().markRelatedNotificationsAsRead(
        types: const <String>{
          'snapshot_reaction',
        },
        targets: <String, String>{'snapshotId': item.id},
        readContext: NotificationService.captureReadContext(),
      ),
    );
    ActiveContentRegistry.register(this,
        types: const <String>{'snapshot_reaction'},
        targets: <String, String>{'snapshotId': item.id});
  }

  Future<void> _openComments({String? focusCommentId, bool focusInput = false}) async {
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
        focusInput: focusInput,
        // 스낵에는 필링만 남긴다. 플래그가 꺼져 있으면 기존 댓글만 읽는다.
        readOnly: !SnackFeatureFlags.publicComments,
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
    final item = _current;
    setState(() => _isModalPaused = true);
    try {
      await SnapshotActivitySheet.show(context, snapshot: item);
    } finally {
      if (mounted) setState(() => _isModalPaused = false);
    }
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
      _pageTransitionDirection = targetIndex > _index ? 1 : -1;
      _index = targetIndex;
      _isSwitching = true;
      _mediaReadyId = null;
      _manualResumeSnapshotId = null;
      _unavailableSnapshotId =
          _current.isExpiredAt(_service.serverNow) ? _current.id : null;
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
    final relationshipStrings = RelationshipStrings.of(context);
    final audienceLabel = switch (item.visibility) {
      SnapshotVisibility.public => relationshipStrings.audiencePublic,
      SnapshotVisibility.friends => relationshipStrings.audienceFriends,
      SnapshotVisibility.category => relationshipStrings.audienceGroups,
    };
    final responseLabel = switch (item.responseMode) {
      SnapshotResponseMode.viewOnly => relationshipStrings.viewOnly,
      SnapshotResponseMode.reactions => relationshipStrings.reactionsMode,
      SnapshotResponseMode.replies => relationshipStrings.repliesMode,
    };
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
            // 공개 범위와 반응 문은 아이콘만으로 숨기지 않고 텍스트로 확인한다.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined,
                      size: 20, color: Color(0xFF667085)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${relationshipStrings.audienceLabel} · $audienceLabel\n'
                      '${relationshipStrings.responseModeTitle} · $responseLabel',
                      style: TextStyle(
                        fontFamily: uiFontFamily(sheetContext, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF475467),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
              if (SnackFeatureFlags.letters)
                _ActionRow(
                  icon: Icons.mail_outline_rounded,
                  label: strings.snackLetter,
                  onTap: () => Navigator.pop(sheetContext, 'letter'),
                ),
              if (item.responseMode.allowsSnackReply)
                _ActionRow(
                  icon: Icons.videocam_outlined,
                  label: relationshipStrings.snackReply,
                  onTap: () => Navigator.pop(sheetContext, 'snackReply'),
                ),
              _ActionRow(
                icon: Icons.visibility_off_outlined,
                label: relationshipStrings.hide,
                onTap: () => Navigator.pop(sheetContext, 'hide'),
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
      case 'letter':
        if (mounted) setState(() => _isModalPaused = false);
        await _openLetterComposer();
        return;
      case 'snackReply':
        if (mounted) setState(() => _isModalPaused = false);
        await _openSnackReplyComposer();
        return;
      case 'hide':
        _hideCurrent();
        return;
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
    final confirmed = await showDialog<bool>(
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
      // 방은 첫 메시지를 보낼 때 만들어진다(빈 방 방지).
      final conversationId =
          await _dmService.prepareConversationForOpen(_current.authorId);
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

  Future<void> _loadTargetLanguageLabel() async {
    if (!mounted) return;
    try {
      final code = await ContentTranslationService.instance.targetLanguage(
        uiLanguageCode: Localizations.localeOf(context).languageCode,
      );
      final label = ContentTranslationService.supportedLanguages[code] ?? '';
      if (!mounted || label == _targetLanguageLabel) return;
      setState(() => _targetLanguageLabel = label);
    } catch (_) {
      // 라벨이 비면 칩은 `번역`만 보인다.
    }
  }

  /// 좌우 한 번 탭은 두 번 탭(하트)을 기다리는 250ms 뒤에 실행한다.
  void _handleMediaTap(TapUpDetails details, double width) {
    if (_isReplyFocused) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    final isOwner =
        FirebaseAuth.instance.currentUser?.uid == _current.authorId;
    final now = DateTime.now();
    final previous = _lastTapAt;
    if (!isOwner &&
        previous != null &&
        now.difference(previous) <= const Duration(milliseconds: 250) &&
        (_tapTimer?.isActive ?? false)) {
      _tapTimer?.cancel();
      _lastTapAt = null;
      HapticFeedback.selectionClick();
      _heartTrigger.value++;
      return;
    }
    _lastTapAt = now;
    final goPrevious = details.localPosition.dx < width / 2;
    _tapTimer?.cancel();
    if (isOwner) {
      goPrevious ? _showPrevious() : _showNext();
      return;
    }
    _tapTimer = Timer(const Duration(milliseconds: 250), () {
      _lastTapAt = null;
      if (!mounted) return;
      goPrevious ? _showPrevious() : _showNext();
    });
  }

  String _headerSubtitle(SnapshotStrings strings) {
    final created = _snapshotCreatedLabel(_current, _service, strings);
    final remaining = snapshotRemainingLabel(
      strings,
      _current.remainingAt(_service.serverNow),
    );
    return remaining == null ? created : '$created · $remaining';
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
    final navigationEnabled = _deletingSnapshotId == null &&
        !_isComposingComment &&
        !_isModalPaused;
    final showTranslateChip = interactionsEnabled &&
        _current.hasTranslatedCaption &&
        _current.translatedCaption.trim() != _current.displayCaption.trim();
    final profile = SnapshotAuthorProfile.resolve(_current);
    final authorIsFriend = context.select<RelationshipProvider, bool>(
      (provider) =>
          provider.feedRelationshipStatus(_current.authorId) ==
          RelationshipStatus.friends,
    );
    final decodeWidth =
        (32 * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(64, 256);
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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: navigationEnabled || _isReplyFocused
                  ? (details) => _handleMediaTap(
                        details,
                        MediaQuery.sizeOf(context).width,
                      )
                  : null,
              onHorizontalDragStart:
                  navigationEnabled ? _handleHorizontalDragStart : null,
              onHorizontalDragUpdate:
                  navigationEnabled ? _handleHorizontalDragUpdate : null,
              onHorizontalDragEnd:
                  navigationEnabled ? _handleHorizontalDragEnd : null,
              onLongPressStart:
                  interactionsEnabled ? (_) => _setHolding(true) : null,
              onLongPressEnd: interactionsEnabled && !_isReplyFocused
                  ? (_) => _setHolding(false)
                  : null,
              onLongPressCancel: interactionsEnabled && !_isReplyFocused
                  ? () => _setHolding(false)
                  : null,
              child: TweenAnimationBuilder<double>(
                key: ValueKey<String>('snapshot-page-${_current.id}'),
                tween: Tween<double>(begin: 0, end: 1),
                duration: _switchDuration,
                curve: MotionTokens.curve,
                builder: (context, opacity, child) => SnapshotPageTransition(
                  progress: opacity,
                  direction: _pageTransitionDirection,
                  child: child!,
                ),
                child: _SnapshotDetailPage(
                  snapshot: _current,
                  service: _service,
                  deleting: _deletingSnapshotId == _current.id,
                  unavailable: _unavailableSnapshotId == _current.id,
                  manualResumeRequired: _manualResumeSnapshotId == _current.id,
                  onMediaReady: _handleMediaReady,
                  onVideoFirstFrame: _handleVideoFirstFrame,
                  onSnapshotChanged: _handleSnapshotChanged,
                  onUnavailable: _markCurrentUnavailable,
                  onVideoPlayRequested: _handleVideoPlayRequested,
                  onComments: () => _openComments(focusInput: true),
                  onLetter: _openLetterComposer,
                  onViewers: _openViewers,
                  onSnackReply: _openSnackReplyComposer,
                  onThread: () => _openComments(),
                  onMeetupDraft: _openMeetupDraft,
                  playing: _currentVideoCanPlay,
                  captionTranslated: _captionTranslated,
                  onDmReply: _sendDmTextReply,
                  heartTrigger: _heartTrigger,
                  onReplyFocusChanged: (focused) {
                    if (!mounted || _isReplyFocused == focused) return;
                    setState(() => _isReplyFocused = focused);
                    _setHolding(focused);
                  },
                ),
              ),
            ),
            // 진행 막대 + 헤더. 사진 위에 얹고 상태바 안전 영역만 비킨다.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SnapshotProgressSegments(
                          count: _items.length,
                          index: _index,
                        ),
                      ),
                      SnapshotViewerHeader(
                        avatar: SnapshotAuthorProfileImage(
                          profile: profile,
                          size: 32,
                          borderRadius: BorderRadius.circular(16),
                          decodeWidth: decodeWidth,
                          placeholderColor: const Color(0xFF475467),
                          placeholderIconColor: Colors.white,
                          placeholderIconSize: 18,
                        ),
                        name: _current.authorName,
                        subtitle: _headerSubtitle(strings),
                        onAuthorTap:
                            interactionsEnabled ? _openAuthorProfile : null,
                        onMore: interactionsEnabled ? _showActions : null,
                        onClose: () => Navigator.of(context).maybePop(),
                        badgeLabel: authorIsFriend ? strings.friendBadge : null,
                        translateChip: showTranslateChip
                            ? SnapshotTranslateChip(
                                on: _captionTranslated,
                                languageLabel: _targetLanguageLabel,
                                onTap: () => setState(
                                  () => _captionTranslated = !_captionTranslated,
                                ),
                              )
                            : null,
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
    required this.onSnackReply,
    required this.onThread,
    required this.onMeetupDraft,
    required this.playing,
    required this.captionTranslated,
    required this.onDmReply,
    required this.onReplyFocusChanged,
    required this.heartTrigger,
  });
  final bool captionTranslated;
  final Future<void> Function(String text) onDmReply;
  final ValueChanged<bool> onReplyFocusChanged;
  final ValueListenable<int> heartTrigger;
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
  final VoidCallback onSnackReply;
  final VoidCallback onThread;
  final VoidCallback onMeetupDraft;
  final bool playing;

  @override
  State<_SnapshotDetailPage> createState() => _SnapshotDetailPageState();
}

class _SnapshotDetailPageState extends State<_SnapshotDetailPage> {
  late Stream<SnapshotItem?> _accessStream;
  StreamSubscription<bool>? _reactionSubscription;
  bool _submittingReaction = false;
  bool _reactedLocally = false;
  bool _reactionStatusResolved = false;
  bool _hasReacted = true;
  int? _lastReportedCommentCount;
  late Map<String, int> _lastReportedReactionCounts;
  int _reactionStatusGeneration = 0;
  String? _confirmingReactionSnapshotId;
  bool _replyFocused = false;
  bool _burstActive = false;
  int _burstSerial = 0;
  Timer? _burstTimer;

  @override
  void initState() {
    super.initState();
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
    widget.heartTrigger.addListener(_handleHeartTrigger);
  }

  bool get _isOwner =>
      FirebaseAuth.instance.currentUser?.uid == widget.snapshot.authorId;

  bool get _canReactNow =>
      reactionAllowed(
        deleting: widget.deleting,
        unavailable: widget.unavailable,
        resolved: _reactionStatusResolved,
        hasReacted: _hasReacted,
        reactedLocally: _reactedLocally,
        submitting: _submittingReaction,
      );

  void _handleHeartTrigger() {
    if (!mounted || _isOwner || !_canReactNow) return;
    _showBurst();
    unawaited(_submitReaction('❤️'));
  }

  void _showBurst() {
    _burstTimer?.cancel();
    setState(() {
      _burstActive = true;
      _burstSerial++;
    });
    _burstTimer = Timer(const Duration(milliseconds: 620), () {
      if (mounted) setState(() => _burstActive = false);
    });
  }

  /// 알약/버튼 탭: 효과와 함께 기존 `_submitReaction('❤️')`(서버 값은 그대로).
  void _handleFeelTap() {
    if (!_canReactNow) return;
    _showBurst();
    unawaited(_submitReaction('❤️'));
  }

  @override
  void didUpdateWidget(covariant _SnapshotDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heartTrigger != widget.heartTrigger) {
      oldWidget.heartTrigger.removeListener(_handleHeartTrigger);
      widget.heartTrigger.addListener(_handleHeartTrigger);
    }
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
    _reactionSubscription = widget.service.watchMyReaction(snapshotId).listen(
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
    widget.heartTrigger.removeListener(_handleHeartTrigger);
    _burstTimer?.cancel();
    _reactionStatusGeneration++;
    unawaited(_reactionSubscription?.cancel());
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
      unawaited(HapticFeedback.selectionClick());
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
        final inaccessible = snapshot.hasError ||
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
        final barHeight = _snapshotBottomBarHeight(context);
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final selected =
            _reactedLocally || (_reactionStatusResolved && _hasReacted);
        final showCaption = current.hasTranslatedCaption;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: barHeight,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(16)),
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
                    if (!widget.deleting) ...[
                      const Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: 140,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x99000000), Colors.transparent],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: _replyFocused ? 220 : 120,
                        child: const IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Color(0xB3000000)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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
            ),
            if (!widget.deleting)
              Positioned(
                left: 16,
                right: 16,
                bottom: barHeight + 16,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.2,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showCaption)
                        _SnapshotCaptionBar(
                          snapshot: current,
                          showTranslated: widget.captionTranslated,
                        ),
                      if (!_replyFocused &&
                          !isOwner &&
                          SnackFeatureFlags.publicComments) ...[
                        if (showCaption) const SizedBox(height: 8),
                        _SnapshotInfoRow(
                          snapshot: current,
                          service: widget.service,
                          onComments: widget.onComments,
                          onThread: widget.onThread,
                        ),
                      ],
                      if (!isOwner &&
                          canOfferMeetupDraft(
                            responseMode: current.responseMode,
                            replyCount: current.commentCount,
                            // 시간·장소 맥락은 2단계(context 필드)에서 켠다.
                            hasTimeOrPlaceContext: false,
                            canCreateMeetup: true,
                          ))
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            onPressed: widget.onMeetupDraft,
                            tooltip:
                                RelationshipStrings.of(context).meetupDraft,
                            icon: const Icon(
                              Icons.event_available_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (_burstActive)
              Positioned.fill(
                child: SnapshotReactionBurst(
                  key: ValueKey<int>(_burstSerial),
                ),
              ),
            if (!widget.deleting)
              Positioned(
                left: 12,
                right: 12,
                bottom: keyboard > 0 ? keyboard + 8 : 0,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: 12,
                    bottom: keyboard > 0
                        ? 0
                        : math.max(MediaQuery.paddingOf(context).bottom, 12.0),
                  ),
                  child: _SnapshotBottomBar(
                    snapshot: current,
                    service: widget.service,
                    isOwner: isOwner,
                    feelSent: selected,
                    canFeel: _canReactNow,
                    onFeel: _handleFeelTap,
                    onDmReply: widget.onDmReply,
                    onViewers: widget.onViewers,
                    onSnackReply: widget.onSnackReply,
                    onFocusChanged: (focused) {
                      if (_replyFocused != focused && mounted) {
                        setState(() => _replyFocused = focused);
                      }
                      widget.onReplyFocusChanged(focused);
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 하단 바 높이(안전 영역 제외 56 = 위 12 + 입력 44).
double _snapshotBottomBarHeight(BuildContext context) =>
    12 + 44 + math.max(MediaQuery.paddingOf(context).bottom, 12.0);

/// 필링 하나로 반응하는 하단 바.
/// - 작성자: `필링 n · 본 사람 m` 알약(활동 시트)
/// - 친구 + 친구 답장도: [DM 답장 입력] [사진·영상 답장] [필링]
/// - 그 밖: [필링] 알약 하나(보낸 뒤 비활성, 취소 없음)
class _SnapshotBottomBar extends StatefulWidget {
  const _SnapshotBottomBar({
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
  });

  final SnapshotItem snapshot;
  final SnapshotService service;
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
  State<_SnapshotBottomBar> createState() => _SnapshotBottomBarState();
}

class _SnapshotBottomBarState extends State<_SnapshotBottomBar> {
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
  void didUpdateWidget(covariant _SnapshotBottomBar oldWidget) {
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
        ? widget.service.watchViewers(widget.snapshot.id)
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

/// 하단 바 위 정보 줄: 왼쪽 한마디를 남긴 사람 아바타(최대 3), 오른쪽 `한마디 n` 칩.
class _SnapshotInfoRow extends StatelessWidget {
  const _SnapshotInfoRow({
    required this.snapshot,
    required this.service,
    required this.onComments,
    required this.onThread,
  });

  final SnapshotItem snapshot;
  final SnapshotService service;
  final VoidCallback onComments;
  final VoidCallback onThread;

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final showPeople =
        snapshot.responseMode.allowsSnackReply && snapshot.commentCount > 0;
    final showChip = snapshot.responseMode != SnapshotResponseMode.viewOnly;
    if (!showPeople && !showChip) return const SizedBox.shrink();
    Widget people = const SizedBox.shrink();
    if (showPeople) {
      people = StreamBuilder<List<SnapshotComment>>(
        stream: service.watchFeedComments(snapshot.id),
        builder: (context, result) {
          final seen = <String>{};
          final authors = <SnapshotComment>[];
          for (final comment in result.data ?? const <SnapshotComment>[]) {
            if (comment.isDeleted || comment.userId.isEmpty) continue;
            if (seen.add(comment.userId)) authors.add(comment);
          }
          if (authors.isEmpty) return const SizedBox.shrink();
          final shown = authors.take(3).toList(growable: false);
          const avatar = 24.0;
          const step = avatar - 6;
          final first = shown.first.authorNickname.trim();
          final label = authors.length > 1
              ? strings.talkedNames(first, authors.length - 1)
              : strings.talkedName(first);
          return GestureDetector(
            key: const ValueKey('snapshot_info_people'),
            behavior: HitTestBehavior.opaque,
            onTap: onThread,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: avatar + (shown.length - 1) * step,
                  height: avatar,
                  child: Stack(
                    children: [
                      for (var i = 0; i < shown.length; i++)
                        Positioned(
                          left: i * step,
                          child: Container(
                            padding: const EdgeInsets.all(1),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: UserAvatar(
                              uid: shown[i].userId,
                              photoUrl: shown[i].authorPhotoUrl,
                              photoVersion: 0,
                              isAnonymous: false,
                              size: avatar - 2,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    first.isEmpty ? '' : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: snapshotChromeStyle(
                      context,
                      size: 12.5,
                      weight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    return Row(
      children: [
        Expanded(child: Align(alignment: Alignment.centerLeft, child: people)),
        if (showChip)
          SnapshotGlassChip(
            key: const ValueKey('snapshot_comment_count_chip'),
            onTap: onThread,
            semanticsLabel: strings.everyoneOneLiner,
            child: Text(
              snapshot.commentCount > 0
                  ? '${strings.oneLinerChip} ${_compactCount(snapshot.commentCount)}'
                  : strings.oneLinerChip,
              maxLines: 1,
              style: snapshotChromeStyle(context, size: 13),
            ),
          ),
      ],
    );
  }
}

/// 캡션. 번역 칩이 켜지면 번역문, 꺼지면 원문을 제자리에서 크로스페이드한다.
class _SnapshotCaptionBar extends StatelessWidget {
  const _SnapshotCaptionBar({
    required this.snapshot,
    required this.showTranslated,
  });

  final SnapshotItem snapshot;
  final bool showTranslated;

  @override
  Widget build(BuildContext context) {
    final original = snapshot.displayCaption;
    final translated = snapshot.translatedCaption.trim();
    final text = showTranslated && translated.isNotEmpty ? translated : original;
    if (text.isEmpty) return const SizedBox.shrink();
    final style = snapshotChromeStyle(
      context,
      size: context.rf(15).clamp(14, 16).toDouble(),
    ).copyWith(height: 1.3);
    return AnimatedSwitcher(
      duration: snapshotReduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      child: Text(
        text,
        key: ValueKey<String>(text),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: style,
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
            color: const Color(0xFFD0D5DD),
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
                      decodeWidth: (canvasSize.width *
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

/// 반응을 지금 보낼 수 있는지(이미 반응했거나 확인 전·삭제 중이면 false).
@visibleForTesting
bool reactionAllowed({
  required bool deleting,
  required bool unavailable,
  required bool resolved,
  required bool hasReacted,
  required bool reactedLocally,
  required bool submitting,
}) =>
    !deleting &&
    !unavailable &&
    resolved &&
    !hasReacted &&
    !reactedLocally &&
    !submitting;

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
