import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../models/snack_chat.dart';
import '../models/snack_chat_message.dart';
import '../config/snack_chat_file_policy.dart';
import '../l10n/app_localizations.dart';
import '../services/cache/app_image_cache_manager.dart';
import '../services/snack_chat_active_conversation.dart';
import '../services/snack_chat_document_import_service.dart';
import '../services/snack_chat_local_cache_service.dart';
import '../services/snack_chat_file_transfer_service.dart';
import '../services/snack_chat_service.dart';
import '../services/storage_service.dart';
import '../services/user_info_cache_service.dart';
import '../ui/widgets/fullscreen_image_viewer.dart';
import '../ui/widgets/snack_chat_message_extras.dart';
import '../ui/widgets/snack_chat_chrome.dart';
import '../ui/widgets/user_avatar.dart';
import '../ui/dialogs/block_dialog.dart';
import '../ui/dialogs/report_dialog.dart';
import '../ui/dialogs/snack_chat_poll_dialog.dart';
import '../ui/sheets/snack_chat_attachment_sheet.dart';
import '../ui/sheets/snack_chat_file_confirmation_sheet.dart';
import '../utils/responsive_helper.dart';
import '../utils/logger.dart';
import '../utils/snack_chat_message_grouping.dart';
import 'friend_categories_screen.dart';
import 'main_screen.dart';
import 'snack_chat_info_screen.dart';

class SnackChatScreen extends StatefulWidget {
  final String snackChatId;
  final bool fromPush;

  const SnackChatScreen({
    super.key,
    required this.snackChatId,
    this.fromPush = false,
  });

  @override
  State<SnackChatScreen> createState() => _SnackChatScreenState();
}

class _ReadReceiptData {
  const _ReadReceiptData({required this.read, required this.unread});

  final List<String> read;
  final List<String> unread;

  int get total => read.length + unread.length;
}

enum _MessageActionType {
  reaction,
  reply,
  retry,
  removeFailed,
  report,
  block,
}

class _MessageAction {
  const _MessageAction(this.type, {this.emoji});

  final _MessageActionType type;
  final String? emoji;
}

class _ScrollAnchor {
  const _ScrollAnchor({required this.messageId, required this.globalDy});

  final String messageId;
  final double globalDy;
}

class _SnackChatScreenState extends State<SnackChatScreen>
    with WidgetsBindingObserver {
  static const Color _chatBackground = SnackChatBackdrop.backgroundColor;
  static const Color _outgoingBubble = Color(0xFF344054);
  static const Color _incomingBubble = Color(0xFFFFFFFF);
  static const Color _secondaryText = Color(0xFF667085);
  static const Color _tertiaryText = Color(0xFF98A2B3);
  static const Color _composerBackground = Color(0xFF252629);
  static const Color _composerAction = Color(0xFF4B4E55);
  static const Color _composerActionDisabled = Color(0xFF36383D);
  static const Duration _peopleLookupDeadline = Duration(seconds: 8);

  final SnackChatService _snackChatService = SnackChatService();
  final StorageService _storageService = StorageService();
  final UserInfoCacheService _userInfoCache = UserInfoCacheService();
  final SnackChatLocalCacheService _localCache = SnackChatLocalCacheService();
  final SnackChatDocumentImportService _documentImporter =
      SnackChatDocumentImportService.instance;
  final SnackChatFileTransferService _fileTransfer =
      SnackChatFileTransferService.instance;
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isUploadingImage = false;
  bool _isCreatingPoll = false;
  bool _isAttachmentFlowOpen = false;
  bool _isLeavingRoom = false;
  bool _roomAccessTerminated = false;
  bool _roomWasLeft = false;
  bool _roomAccessTerminationScheduled = false;
  bool _roomAvailabilityCheckInFlight = false;
  Timer? _roomRetryTimer;
  int _roomRetryAttempt = 0;
  Timer? _autoMarkReadDebounce;
  bool _autoMarkReadInFlight = false;
  bool _readFlushQueued = false;
  int _readRetryAttempt = 0;
  Future<void>? _markAsReadOperation;
  final Map<String, String> _senderNameCache = {};
  final Map<String, Future<String>> _senderNameFutures = {};
  final Set<String> _senderProfileRefreshStarted = <String>{};
  final Map<String, GlobalKey> _messageKeys = {};
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  late Stream<SnackChat?> _roomStream;
  Future<void>? _membershipReady;
  AppLifecycleState _appLifecycleState = AppLifecycleState.detached;
  bool _routeActive = true;
  int _highestVisibleSequence = 0;
  int _lastReadSequenceSent = 0;
  int? _initialLastReadSequence;
  bool _legacyReadResetPending = false;
  bool _legacyReadResetSent = false;
  SnackChatMessage? _replyingTo;
  String? _replyingToSenderName;
  Object? _messageStreamError;
  Object? _loadMoreError;
  final Map<String, String> _myReactions = <String, String>{};
  final Map<String, Set<String>> _myVotes = <String, Set<String>>{};
  final Map<String, String?> _confirmedReactions = <String, String?>{};
  final Map<String, Set<String>> _confirmedVotes = <String, Set<String>>{};
  final Map<String, String?> _pendingReactionTargets = <String, String?>{};
  final Map<String, Set<String>> _pendingVoteTargets = <String, Set<String>>{};
  final Set<String> _reactionMutationsInFlight = <String>{};
  final Set<String> _voteMutationsInFlight = <String>{};
  final Set<String> _retryingMessageIds = <String>{};
  final Set<String> _sendingTextMessageIds = <String>{};
  final Map<String, Future<void>> _outboundQueues = <String, Future<void>>{};
  final Set<String> _removingFailedMessageIds = <String>{};
  final Set<String> _blockedUserIds = <String>{};

  // ─── 페이지네이션 상태 ───────────────────────────────────────────
  StreamSubscription<List<SnackChatMessage>>? _msgSub;
  StreamSubscription<List<SnackChatMember>>? _memberSub;
  StreamSubscription<List<SnackChatReaction>>? _reactionSub;
  StreamSubscription<List<SnackChatVote>>? _voteSub;
  StreamSubscription<Set<String>>? _blockSub;
  StreamSubscription<SnackChatFileTransferEvent>? _fileTransferSub;
  Timer? _messageRetryTimer;
  Timer? _fileExpiryTimer;
  int _messageRetryAttempt = 0;
  Timer? _auxiliaryRetryTimer;
  int _auxiliaryRetryAttempt = 0;
  int _auxiliarySubscriptionGeneration = 0;
  int _messageSubscriptionGeneration = 0;
  final List<SnackChatMessage> _messages = [];
  final Set<String> _messageIds = {};
  final Map<String, SnackChatMember> _members = <String, SnackChatMember>{};
  SnackChatMessage? _oldestMessage;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isInitialLoading = true; // 초기 로딩 상태 추가
  SnackChat? _lastRoom;
  Timer? _draftSaveDebounce;
  Timer? _messageCacheDebounce;
  Timer? _outboxRetryTimer;
  int _outboxRetryAttempt = 0;
  bool _restoringDraft = false;
  bool _draftTouched = false;
  bool _isNearLatest = true;
  bool _hasReceivedFirstLiveBatch = false;
  int _newMessageCount = 0;
  int _cacheHydrationGeneration = 0;
  String? _cachedRoomWriteToken;
  DateTime? _lastOptimisticCreatedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appLifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.detached;
    SnackChatActiveConversation.setActive(widget.snackChatId);
    _roomStream = _snackChatService.watchSnackChat(widget.snackChatId);
    _scrollController.addListener(_onScroll);
    _messageController.addListener(_onDraftChanged);
    unawaited(_hydrateLocalState());
    unawaited(_ensureMyMembershipReady().catchError((_) {}));
    _subscribeToMessages();
    _subscribeToAuxiliaryState();
    _subscribeToFileTransfers();
    unawaited(_restoreFileTransfers());
  }

  @override
  void didUpdateWidget(covariant SnackChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snackChatId == widget.snackChatId) return;
    unawaited(
      _localCache.saveDraft(oldWidget.snackChatId, _messageController.text),
    );
    if (_messages.isNotEmpty) {
      unawaited(
        _localCache.upsertMessages(oldWidget.snackChatId, List.of(_messages)),
      );
    }
    if (SnackChatActiveConversation.isActive(oldWidget.snackChatId)) {
      SnackChatActiveConversation.setActive(null);
    }
    _messageSubscriptionGeneration++;
    _auxiliarySubscriptionGeneration++;
    unawaited(_msgSub?.cancel() ?? Future<void>.value());
    unawaited(_memberSub?.cancel() ?? Future<void>.value());
    unawaited(_reactionSub?.cancel() ?? Future<void>.value());
    unawaited(_voteSub?.cancel() ?? Future<void>.value());
    unawaited(_fileTransferSub?.cancel() ?? Future<void>.value());
    _msgSub = null;
    _fileTransferSub = null;
    _memberSub = null;
    _reactionSub = null;
    _voteSub = null;
    _draftSaveDebounce?.cancel();
    _messageCacheDebounce?.cancel();
    _outboxRetryTimer?.cancel();
    _messageRetryTimer?.cancel();
    _fileExpiryTimer?.cancel();
    _roomRetryTimer?.cancel();
    _restoringDraft = true;
    _messageController.clear();
    _restoringDraft = false;
    _draftTouched = false;
    _messages.clear();
    _messageIds.clear();
    _messageKeys.clear();
    _members.clear();
    _senderNameCache.clear();
    _senderNameFutures.clear();
    _senderProfileRefreshStarted.clear();
    _myReactions.clear();
    _myVotes.clear();
    _confirmedReactions.clear();
    _confirmedVotes.clear();
    _pendingReactionTargets.clear();
    _pendingVoteTargets.clear();
    _retryingMessageIds.clear();
    _removingFailedMessageIds.clear();
    _clearReplyState();
    _oldestMessage = null;
    _lastRoom = null;
    _membershipReady = null;
    _messageStreamError = null;
    _messageRetryAttempt = 0;
    _roomRetryAttempt = 0;
    _loadMoreError = null;
    _isInitialLoading = true;
    _hasMore = true;
    _isLoadingMore = false;
    _isUploadingImage = false;
    _isCreatingPoll = false;
    _isAttachmentFlowOpen = false;
    _roomAccessTerminated = false;
    _roomWasLeft = false;
    _roomAccessTerminationScheduled = false;
    _roomAvailabilityCheckInFlight = false;
    _highestVisibleSequence = 0;
    _lastReadSequenceSent = 0;
    _initialLastReadSequence = null;
    _legacyReadResetPending = false;
    _legacyReadResetSent = false;
    _isNearLatest = true;
    _outboxRetryAttempt = 0;
    _newMessageCount = 0;
    _hasReceivedFirstLiveBatch = false;
    _cachedRoomWriteToken = null;
    _lastOptimisticCreatedAt = null;
    _roomStream = _snackChatService.watchSnackChat(widget.snackChatId);
    SnackChatActiveConversation.setActive(widget.snackChatId);
    unawaited(_hydrateLocalState());
    unawaited(_ensureMyMembershipReady().catchError((_) {}));
    _subscribeToMessages();
    _subscribeToAuxiliaryState();
    _subscribeToFileTransfers();
    unawaited(_restoreFileTransfers());
  }

  void _subscribeToFileTransfers() {
    unawaited(_fileTransferSub?.cancel() ?? Future<void>.value());
    final roomId = widget.snackChatId;
    _fileTransferSub = _fileTransfer.watchRoom(roomId).listen((event) {
      if (!mounted || roomId != widget.snackChatId) return;
      setState(() {
        final index = _messages.indexWhere(
          (message) => message.id == event.message.id,
        );
        if (event.removed) {
          if (index >= 0) _messages.removeAt(index);
          _messageIds.remove(event.message.id);
          _messageKeys.remove(event.message.id);
        } else if (index >= 0) {
          final current = _messages[index];
          if (!(current.sendStatus == MessageSendStatus.sent &&
              event.message.sendStatus != MessageSendStatus.sent)) {
            _messages[index] =
                event.message.sendStatus == MessageSendStatus.sent
                    ? event.message
                    : event.message.copyWith(
                        sequence: current.sequence,
                        recipientIds: current.recipientIds,
                        deliveryRecipientIds: current.deliveryRecipientIds,
                        readBy: current.readBy,
                      );
          }
        } else {
          _insertLocalMessage(event.message);
        }
        _sortMessages();
      });
      _scheduleMessageCacheWrite();
      _scheduleFileExpiryRefresh();
      if (_isNearLatest) _scrollToLatest(animated: true);
    });
  }

  Future<void> _restoreFileTransfers() async {
    final roomId = widget.snackChatId;
    final restored = await _fileTransfer.restoreRoom(roomId);
    if (!mounted || roomId != widget.snackChatId || restored.isEmpty) return;
    setState(() {
      for (final pending in restored) {
        final index =
            _messages.indexWhere((message) => message.id == pending.id);
        if (index < 0) {
          _insertLocalMessage(pending);
        } else if (_messages[index].sendStatus != MessageSendStatus.sent) {
          _messages[index] = pending;
        }
      }
      _sortMessages();
      _isInitialLoading = false;
    });
    _scheduleMessageCacheWrite();
    _scheduleFileExpiryRefresh();
    if (_appLifecycleState == AppLifecycleState.resumed) {
      unawaited(_fileTransfer.retryRoom(roomId));
    }
  }

  void _scheduleFileExpiryRefresh() {
    _fileExpiryTimer?.cancel();
    _fileExpiryTimer = null;
    final now = DateTime.now();
    DateTime? nearest;
    for (final message in _messages) {
      final deadline = message.expiresAt;
      if (message.type != SnackChatMessageType.file ||
          deadline == null ||
          !deadline.isAfter(now)) {
        continue;
      }
      if (nearest == null || deadline.isBefore(nearest)) nearest = deadline;
    }
    if (nearest == null) return;
    _fileExpiryTimer =
        Timer(nearest.difference(now) + const Duration(milliseconds: 120), () {
      _fileExpiryTimer = null;
      if (!mounted) return;
      setState(() {});
      unawaited(_fileTransfer.purgeExpiredCache());
      _scheduleFileExpiryRefresh();
    });
  }

  Future<void> _hydrateLocalState() async {
    final roomId = widget.snackChatId;
    final ownerUid = _uid;
    final generation = ++_cacheHydrationGeneration;
    if (ownerUid == null) return;
    final messagesFuture = _localCache.getMessages(roomId);
    final roomFuture = _localCache.getRoom(roomId);
    final draftFuture = _localCache.getDraft(roomId);
    final cachedMessages = await messagesFuture;
    final cachedRoom = await roomFuture;
    final draft = await draftFuture;
    final profiles = await _userInfoCache.hydrateUsers(
      cachedMessages.map((message) => message.senderId),
    );
    if (!mounted ||
        generation != _cacheHydrationGeneration ||
        roomId != widget.snackChatId ||
        ownerUid != _uid) {
      return;
    }
    for (final entry in profiles.entries) {
      final nickname = entry.value?.nickname.trim() ?? '';
      if (nickname.isNotEmpty && !_looksLikeInternalIdentifier(nickname)) {
        _senderNameCache[entry.key] = nickname;
      }
    }
    setState(() {
      _lastRoom ??= cachedRoom;
      for (final cached in cachedMessages) {
        if (_messageIds.add(cached.id)) {
          _messages.add(
            cached.isPending
                ? cached.copyWith(
                    sendStatus: MessageSendStatus.failed,
                    errorMessage: '전송 상태를 확인해 주세요. 눌러서 다시 시도할 수 있습니다.',
                  )
                : cached,
          );
        }
      }
      if (_messages.isNotEmpty) {
        _sortMessages();
        _isInitialLoading = false;
      } else if (cachedRoom != null &&
          cachedRoom.lastMessageId.isEmpty &&
          cachedRoom.lastMessage.isEmpty) {
        _isInitialLoading = false;
      }
      if (!_draftTouched &&
          _messageController.text.isEmpty &&
          draft.isNotEmpty) {
        _restoringDraft = true;
        _messageController.value = TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: draft.length),
        );
        _restoringDraft = false;
      }
    });
    _scheduleOutboxRecovery();
  }

  void _onDraftChanged() {
    if (_restoringDraft || _isLeavingRoom) return;
    _draftTouched = true;
    _draftSaveDebounce?.cancel();
    final roomId = widget.snackChatId;
    final value = _messageController.text;
    _draftSaveDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!_isLeavingRoom && roomId == widget.snackChatId) {
        unawaited(_localCache.saveDraft(roomId, value));
      }
    });
  }

  void _scheduleMessageCacheWrite() {
    _messageCacheDebounce?.cancel();
    final roomId = widget.snackChatId;
    _messageCacheDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!_isLeavingRoom && roomId == widget.snackChatId) {
        unawaited(_localCache.upsertMessages(roomId, List.of(_messages)));
      }
    });
  }

  void _cacheRoomIfChanged(SnackChat room) {
    final token = '${room.id}:${room.updatedAt.millisecondsSinceEpoch}:'
        '${room.title}:${room.participantCount}:${room.lastMessageId}';
    if (_cachedRoomWriteToken == token) return;
    _cachedRoomWriteToken = token;
    unawaited(_localCache.saveRoom(widget.snackChatId, room));
  }

  DateTime _nextOptimisticCreatedAt() {
    final now = DateTime.now();
    final previous = _lastOptimisticCreatedAt;
    final next = previous != null && !now.isAfter(previous)
        ? previous.add(const Duration(microseconds: 1))
        : now;
    _lastOptimisticCreatedAt = next;
    return next;
  }

  void _retryRoomStream() {
    if (!mounted || _isLeavingRoom || _roomAccessTerminated) return;
    _roomRetryTimer?.cancel();
    _roomRetryTimer = null;
    setState(() {
      _roomStream = _snackChatService.watchSnackChat(widget.snackChatId);
    });
  }

  void _scheduleRoomRetry() {
    if (_roomRetryTimer != null || _isLeavingRoom || _roomAccessTerminated) {
      return;
    }
    _roomRetryAttempt = (_roomRetryAttempt + 1).clamp(1, 5).toInt();
    final seconds = (1 << _roomRetryAttempt).clamp(2, 30).toInt();
    _roomRetryTimer = Timer(Duration(seconds: seconds), () {
      _roomRetryTimer = null;
      _retryRoomStream();
    });
  }

  bool get _canTrackVisibility {
    if (!mounted || _isLeavingRoom || _roomAccessTerminated || !_routeActive) {
      return false;
    }
    if (_appLifecycleState != AppLifecycleState.resumed) return false;
    return ModalRoute.of(context)?.isCurrent ?? false;
  }

  bool get _canMarkRead =>
      _canTrackVisibility && _initialLastReadSequence != null;

  Future<void> _ensureMyMembershipReady({bool force = false}) {
    final existing = _membershipReady;
    if (!force && existing != null) return existing;
    final operation = _snackChatService.ensureMyMembership(widget.snackChatId);
    _membershipReady = operation;
    unawaited(operation.catchError((Object _) {
      if (identical(_membershipReady, operation)) _membershipReady = null;
    }));
    return operation;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _scheduleMarkAsRead();
      if (_messageStreamError != null && _messageRetryTimer == null) {
        _subscribeToMessages();
      }
      if (_outboxRetryAttempt >= 5) _outboxRetryAttempt = 0;
      _scheduleOutboxRecovery();
      unawaited(_fileTransfer.retryRoom(widget.snackChatId));
      unawaited(_fileTransfer.purgeExpiredCache());
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(
        _localCache.saveDraft(widget.snackChatId, _messageController.text),
      );
      if (_messages.isNotEmpty) {
        unawaited(
          _localCache.upsertMessages(widget.snackChatId, List.of(_messages)),
        );
      }
    }
  }

  @override
  void didChangeMetrics() {
    if (!_isNearLatest) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isNearLatest) _scrollToLatest(animated: false);
    });
  }

  void _onMessageVisibilityChanged(
    SnackChatMessage message,
    VisibilityInfo info,
  ) {
    final sequence = message.sequence;
    // Visibility can arrive before the server-maintained membership document.
    // Keep the observed high-water mark immediately, then gate only the
    // Firestore write until the initial read cursor is known. Otherwise the
    // first visible page may stay unread until the user scrolls again.
    if (info.visibleFraction < 0.6 || !_canTrackVisibility) {
      return;
    }
    if (sequence == null) {
      // Pre-sequence rooms used only the room-level unread badge. A visible
      // legacy message must still clear that badge once, but never clear a
      // mixed/new room whose latest sequenced messages may be off-screen.
      if (!_legacyReadResetSent && (_lastRoom?.lastMessageSequence ?? 0) == 0) {
        _legacyReadResetPending = true;
        _scheduleMarkAsRead();
      }
      return;
    }
    if (sequence > _highestVisibleSequence) {
      _highestVisibleSequence = sequence;
      _scheduleMarkAsRead();
    }
  }

  /// Only the highest sequence that was actually visible is persisted. A
  /// second target arriving during a write is queued instead of being lost.
  void _scheduleMarkAsRead() {
    final needsLegacyReset = _legacyReadResetPending && !_legacyReadResetSent;
    if (!_canMarkRead ||
        (!needsLegacyReset &&
            _highestVisibleSequence <= _lastReadSequenceSent)) {
      return;
    }
    if (_autoMarkReadInFlight) {
      _readFlushQueued = true;
      return;
    }
    _autoMarkReadDebounce?.cancel();
    unawaited(_performMarkAsRead());
  }

  Future<void> _performMarkAsRead() async {
    final needsLegacyReset = _legacyReadResetPending && !_legacyReadResetSent;
    if (!_canMarkRead ||
        (!needsLegacyReset &&
            _highestVisibleSequence <= _lastReadSequenceSent)) {
      return;
    }
    if (_autoMarkReadInFlight) {
      _readFlushQueued = true;
      return;
    }
    final target = _highestVisibleSequence;
    _autoMarkReadInFlight = true;
    final operation = () async {
      await _ensureMyMembershipReady();
      await _snackChatService.markAsRead(
        widget.snackChatId,
        lastReadSequence: target,
      );
    }();
    _markAsReadOperation = operation;
    var didSucceed = false;
    try {
      await operation;
      didSucceed = true;
      _readRetryAttempt = 0;
      if (needsLegacyReset) {
        _legacyReadResetPending = false;
        _legacyReadResetSent = true;
      }
      _lastReadSequenceSent =
          target > _lastReadSequenceSent ? target : _lastReadSequenceSent;
    } catch (_) {
      // 화면이 유지되는 동안 아래 bounded retry로 복구한다.
    } finally {
      if (identical(_markAsReadOperation, operation)) {
        _markAsReadOperation = null;
      }
      _autoMarkReadInFlight = false;
      if (_readFlushQueued ||
          (didSucceed && _highestVisibleSequence > _lastReadSequenceSent)) {
        _readFlushQueued = false;
        _scheduleMarkAsRead();
      } else if (!didSucceed &&
          _canMarkRead &&
          (_highestVisibleSequence > _lastReadSequenceSent ||
              (_legacyReadResetPending && !_legacyReadResetSent))) {
        // Firestore transactions are not queued while offline. Keep one
        // bounded retry alive while this route remains visible so the read
        // cursor converges after connectivity returns without requiring an
        // extra scroll gesture.
        _readRetryAttempt = (_readRetryAttempt + 1).clamp(1, 5).toInt();
        final retrySeconds = (1 << _readRetryAttempt).clamp(2, 30).toInt();
        _autoMarkReadDebounce?.cancel();
        _autoMarkReadDebounce = Timer(
          Duration(seconds: retrySeconds),
          _scheduleMarkAsRead,
        );
      }
    }
  }

  void _flushReadOnDispose() {
    final target = _highestVisibleSequence;
    final needsLegacyReset = _legacyReadResetPending && !_legacyReadResetSent;
    if (_roomWasLeft ||
        _roomAccessTerminated ||
        (target <= 0 && !needsLegacyReset)) {
      return;
    }
    unawaited(
      (() async {
        await _ensureMyMembershipReady();
        await _snackChatService.markAsRead(
          widget.snackChatId,
          lastReadSequence: target,
        );
      })()
          .catchError((Object error) {
        Logger.error('Snack Chat 화면 종료 읽음 동기화 실패', error);
      }),
    );
  }

  void _subscribeToMessages() {
    if (_roomAccessTerminated || _isLeavingRoom) return;
    _messageRetryTimer?.cancel();
    _fileExpiryTimer?.cancel();
    _messageRetryTimer = null;
    final generation = ++_messageSubscriptionGeneration;
    final previous = _msgSub;
    _msgSub = null;
    if (previous != null) unawaited(previous.cancel());
    final liveWindowOldest = _oldestMessage;
    _msgSub = _snackChatService
        .watchMessages(
      widget.snackChatId,
      throughMessage: liveWindowOldest,
    )
        .listen(
      (incoming) {
        if (!mounted ||
            _isLeavingRoom ||
            generation != _messageSubscriptionGeneration) {
          return;
        }
        var shouldPinInitialLiveWindow = false;
        var addedRemoteMessages = 0;
        final wasNearLatest = _isNearLatest;
        final hadLiveBatch = _hasReceivedFirstLiveBatch;
        setState(() {
          _isInitialLoading = false;
          _messageStreamError = null;
          _messageRetryAttempt = 0;
          if (_oldestMessage == null && incoming.isNotEmpty) {
            // Only contiguous query batches advance the pagination cursor.
            // A separately fetched reply target must never move this cursor.
            _oldestMessage = incoming.last;
            shouldPinInitialLiveWindow = true;
          }
          for (final serverMessage in incoming) {
            final index = _messages
                .indexWhere((message) => message.id == serverMessage.id);
            if (index < 0) {
              _messageIds.add(serverMessage.id);
              _messages.add(serverMessage);
              if (hadLiveBatch && serverMessage.senderId != _uid) {
                addedRemoteMessages++;
              }
            } else {
              final local = _messages[index];
              final keepOptimisticReaction =
                  _reactionMutationsInFlight.contains(serverMessage.id) ||
                      _pendingReactionTargets.containsKey(serverMessage.id);
              final keepOptimisticPoll =
                  _voteMutationsInFlight.contains(serverMessage.id) ||
                      _pendingVoteTargets.containsKey(serverMessage.id);
              _messages[index] = serverMessage.copyWith(
                localImagePath: local.localImagePath,
                localFilePath: local.localFilePath,
                fileTransferStatus:
                    serverMessage.type == SnackChatMessageType.file
                        ? SnackChatFileTransferStatus.ready
                        : local.fileTransferStatus,
                transferProgress:
                    serverMessage.type == SnackChatMessageType.file
                        ? 1
                        : local.transferProgress,
                reactionCounts: keepOptimisticReaction
                    ? local.reactionCounts
                    : serverMessage.reactionCounts,
                poll: keepOptimisticPoll ? local.poll : serverMessage.poll,
                clearErrorMessage: true,
              );
            }
          }
          _sortMessages();
          _hasReceivedFirstLiveBatch = true;
          if (addedRemoteMessages > 0 && !wasNearLatest) {
            _newMessageCount += addedRemoteMessages;
          }
        });
        _scheduleMessageCacheWrite();
        _scheduleFileExpiryRefresh();
        _scheduleOutboxRecovery();
        if (wasNearLatest && (incoming.isNotEmpty || !hadLiveBatch)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _isNearLatest) _scrollToLatest(animated: true);
          });
        }
        if (shouldPinInitialLiveWindow) {
          scheduleMicrotask(() {
            if (mounted &&
                !_isLeavingRoom &&
                !_roomAccessTerminated &&
                generation == _messageSubscriptionGeneration) {
              _subscribeToMessages();
            }
          });
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted ||
            _isLeavingRoom ||
            generation != _messageSubscriptionGeneration) {
          return;
        }
        setState(() {
          _isInitialLoading = false;
          _messageStreamError = error;
        });
        if (_isTerminalRoomError(error)) {
          _scheduleRoomAccessTermination();
        } else if (_messageRetryTimer == null) {
          _messageRetryAttempt = (_messageRetryAttempt + 1).clamp(1, 5).toInt();
          final seconds = (1 << _messageRetryAttempt).clamp(2, 30).toInt();
          _messageRetryTimer = Timer(Duration(seconds: seconds), () {
            _messageRetryTimer = null;
            if (mounted && !_isLeavingRoom && !_roomAccessTerminated) {
              _subscribeToMessages();
            }
          });
        }
      },
    );
  }

  void _subscribeToAuxiliaryState() {
    if (_roomAccessTerminated || _isLeavingRoom) return;
    final generation = ++_auxiliarySubscriptionGeneration;
    _auxiliaryRetryTimer?.cancel();
    _auxiliaryRetryTimer = null;
    final previousSubscriptions = <StreamSubscription<dynamic>?>[
      _memberSub,
      _reactionSub,
      _voteSub,
      _blockSub,
    ];
    _memberSub = null;
    _reactionSub = null;
    _voteSub = null;
    _blockSub = null;
    for (final subscription in previousSubscriptions) {
      if (subscription != null) unawaited(subscription.cancel());
    }

    final readyStreams = <String>{};
    void markReady(String name) {
      readyStreams.add(name);
      if (readyStreams.length == 4) _auxiliaryRetryAttempt = 0;
    }

    void handleError(Object error, StackTrace _) {
      if (!mounted ||
          _isLeavingRoom ||
          _roomAccessTerminated ||
          generation != _auxiliarySubscriptionGeneration ||
          _auxiliaryRetryTimer != null) {
        return;
      }
      if (_isTerminalRoomError(error)) {
        _scheduleRoomAccessTermination();
        return;
      }
      _auxiliaryRetryAttempt = (_auxiliaryRetryAttempt + 1).clamp(1, 5).toInt();
      final retrySeconds = (1 << _auxiliaryRetryAttempt).clamp(2, 30).toInt();
      _auxiliaryRetryTimer = Timer(Duration(seconds: retrySeconds), () {
        _auxiliaryRetryTimer = null;
        if (mounted &&
            !_isLeavingRoom &&
            !_roomAccessTerminated &&
            generation == _auxiliarySubscriptionGeneration) {
          _subscribeToAuxiliaryState();
        }
      });
    }

    _memberSub = _snackChatService.watchMembers(widget.snackChatId).listen(
      (members) {
        if (!mounted || generation != _auxiliarySubscriptionGeneration) {
          return;
        }
        final nextMembers = <String, SnackChatMember>{};
        for (final member in members) {
          final previous = _members[member.userId];
          nextMembers[member.userId] = previous != null &&
                  previous.lastReadSequence > member.lastReadSequence
              ? SnackChatMember(
                  userId: member.userId,
                  status: member.status,
                  lastReadSequence: previous.lastReadSequence,
                  lastReadAt: previous.lastReadAt ?? member.lastReadAt,
                  periods: member.periods,
                )
              : member;
        }
        markReady('members');
        final currentUserId = _uid;
        final mine = currentUserId == null ? null : nextMembers[currentUserId];
        setState(() {
          _members
            ..clear()
            ..addAll(nextMembers);
          if (mine != null) {
            final current = _initialLastReadSequence;
            if (current == null || mine.lastReadSequence > current) {
              _initialLastReadSequence = mine.lastReadSequence;
            }
          }
          if (mine != null && mine.lastReadSequence > _lastReadSequenceSent) {
            _lastReadSequenceSent = mine.lastReadSequence;
          }
        });
        if (mine == null) {
          unawaited(_ensureMyMembershipReady().catchError((_) {}));
        } else if (mine.status != 'active') {
          unawaited(
            _ensureMyMembershipReady(force: true).catchError((_) {}),
          );
        } else {
          _scheduleMarkAsRead();
        }
      },
      onError: handleError,
    );
    _reactionSub =
        _snackChatService.watchMyReactions(widget.snackChatId).listen(
      (reactions) {
        if (!mounted || generation != _auxiliarySubscriptionGeneration) {
          return;
        }
        final next = <String, String>{
          for (final reaction in reactions) reaction.messageId: reaction.emoji,
        };
        markReady('reactions');
        setState(() {
          final ids = <String>{
            ..._myReactions.keys,
            ..._confirmedReactions.keys,
            ...next.keys,
          };
          for (final messageId in ids) {
            if (_reactionMutationsInFlight.contains(messageId) ||
                _pendingReactionTargets.containsKey(messageId)) {
              continue;
            }
            final value = next[messageId];
            value == null
                ? _myReactions.remove(messageId)
                : _myReactions[messageId] = value;
            _confirmedReactions[messageId] = value;
          }
        });
      },
      onError: handleError,
    );
    _voteSub = _snackChatService.watchMyVotes(widget.snackChatId).listen(
      (votes) {
        if (!mounted || generation != _auxiliarySubscriptionGeneration) {
          return;
        }
        final next = <String, Set<String>>{
          for (final vote in votes) vote.messageId: vote.optionIds.toSet(),
        };
        markReady('votes');
        setState(() {
          final ids = <String>{
            ..._myVotes.keys,
            ..._confirmedVotes.keys,
            ...next.keys,
          };
          for (final messageId in ids) {
            if (_voteMutationsInFlight.contains(messageId) ||
                _pendingVoteTargets.containsKey(messageId)) {
              continue;
            }
            final value = next[messageId];
            if (value == null) {
              _myVotes.remove(messageId);
              _confirmedVotes[messageId] = const <String>{};
            } else {
              _myVotes[messageId] = Set<String>.from(value);
              _confirmedVotes[messageId] = Set<String>.from(value);
            }
          }
        });
      },
      onError: handleError,
    );
    _blockSub = _snackChatService.watchBlockedUserIds().listen(
      (ids) {
        if (!mounted || generation != _auxiliarySubscriptionGeneration) {
          return;
        }
        markReady('blocks');
        if (_blockedUserIds.length == ids.length &&
            _blockedUserIds.containsAll(ids)) {
          return;
        }
        final anchor = _captureScrollAnchor();
        setState(() {
          _blockedUserIds
            ..clear()
            ..addAll(ids);
        });
        _restoreScrollAnchor(anchor);
      },
      onError: handleError,
    );
  }

  _ScrollAnchor? _captureScrollAnchor() {
    if (!_scrollController.hasClients) return null;
    final screenHeight = MediaQuery.sizeOf(context).height;
    _ScrollAnchor? best;
    var bestDistance = double.infinity;
    for (final message in _messages) {
      final renderObject =
          _messageKeys[message.id]?.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final dy = renderObject.localToGlobal(Offset.zero).dy;
      final bottom = dy + renderObject.size.height;
      if (bottom <= 0 || dy >= screenHeight) continue;
      final distance = (dy - screenHeight * .45).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = _ScrollAnchor(messageId: message.id, globalDy: dy);
      }
    }
    return best;
  }

  void _restoreScrollAnchor(_ScrollAnchor? anchor) {
    if (anchor == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final renderObject =
          _messageKeys[anchor.messageId]?.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) return;
      final newDy = renderObject.localToGlobal(Offset.zero).dy;
      final globalDelta = newDy - anchor.globalDy;
      if (globalDelta.abs() < .5) return;
      final position = _scrollController.position;
      final offsetDelta = position.axisDirection == AxisDirection.up
          ? -globalDelta
          : globalDelta;
      final target = (position.pixels + offsetDelta)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((target - position.pixels).abs() >= .5) position.jumpTo(target);
    });
  }

  void _sortMessages() {
    _messages.sort((a, b) {
      final aSequence = a.sequence;
      final bSequence = b.sequence;
      if (aSequence != null && bSequence != null && aSequence != bSequence) {
        return bSequence.compareTo(aSequence);
      }
      final byTime = b.createdAt.compareTo(a.createdAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
  }

  void _onScroll() {
    final nearLatest = _scrollController.position.pixels <= 72;
    if (nearLatest != _isNearLatest || (nearLatest && _newMessageCount > 0)) {
      setState(() {
        _isNearLatest = nearLatest;
        if (nearLatest) _newMessageCount = 0;
      });
    }
    // 리스트가 끝(오래된 메시지 방향)에 다가오면 추가 로드
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final older = await _snackChatService.fetchMessagesPage(
        widget.snackChatId,
        beforeMessage: _oldestMessage,
      );
      if (!mounted) return;
      setState(() {
        _loadMoreError = null;
        for (final m in older) {
          if (!_messageIds.contains(m.id)) {
            _messageIds.add(m.id);
            _messages.add(m);
          }
        }
        if (older.isNotEmpty) _oldestMessage = older.last;
        if (older.isEmpty || older.length < 30) _hasMore = false;
        if (_messages.isNotEmpty) {
          _sortMessages();
        }
      });
      if (older.isNotEmpty) _subscribeToMessages();
      _scheduleMessageCacheWrite();
    } catch (error) {
      if (mounted) setState(() => _loadMoreError = error);
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _scrollToLatest({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    if (_newMessageCount != 0 || !_isNearLatest) {
      setState(() {
        _newMessageCount = 0;
        _isNearLatest = true;
      });
    }
    final target = _scrollController.position.minScrollExtent;
    if (animated && (_scrollController.position.pixels - target).abs() > 1) {
      unawaited(_scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ));
    } else if ((_scrollController.position.pixels - target).abs() > .5) {
      _scrollController.jumpTo(target);
    }
  }

  Future<String> _getSenderName(String senderId, String? senderName) async {
    final fallbackLabel = _genericUserLabel;
    if (senderName != null && senderName.trim().isNotEmpty) {
      return _safeUserLabel(senderName);
    }
    if (_senderNameCache.containsKey(senderId)) {
      return _senderNameCache[senderId]!;
    }
    final userInfo = await _userInfoCache.getUserInfo(senderId);
    final name = userInfo?.nickname.trim() ?? '';
    if (name.isNotEmpty && !_looksLikeInternalIdentifier(name)) {
      _senderNameCache[senderId] = name;
      return name;
    }
    return fallbackLabel;
  }

  String get _genericUserLabel =>
      Localizations.localeOf(context).languageCode == 'ko' ? '사용자' : 'User';

  bool _looksLikeInternalIdentifier(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(value.trim());

  String _safeUserLabel(String? value) {
    final candidate = value?.trim() ?? '';
    if (candidate.isEmpty || _looksLikeInternalIdentifier(candidate)) {
      return _genericUserLabel;
    }
    return candidate;
  }

  Future<String> _senderNameFuture(
    String senderId,
    String? senderName,
  ) {
    if (senderName?.trim().isNotEmpty == true) {
      return Future<String>.value(_safeUserLabel(senderName));
    }
    final cached = _senderNameCache[senderId];
    if (cached != null) {
      if (_senderProfileRefreshStarted.add(senderId)) {
        unawaited(_refreshSenderName(senderId));
      }
      return Future<String>.value(cached);
    }
    return _senderNameFutures.putIfAbsent(
      senderId,
      () => _getSenderName(senderId, senderName),
    );
  }

  Future<void> _refreshSenderName(String senderId) async {
    try {
      final info = await _userInfoCache.getUserInfo(
        senderId,
        forceRefresh: true,
      );
      final name = info?.nickname.trim() ?? '';
      if (!mounted ||
          name.isEmpty ||
          _looksLikeInternalIdentifier(name) ||
          _senderNameCache[senderId] == name) {
        return;
      }
      setState(() => _senderNameCache[senderId] = name);
    } finally {
      _senderProfileRefreshStarted.remove(senderId);
    }
  }

  @override
  void dispose() {
    // 빠르게 뒤로 가더라도 이미 화면에 노출된 마지막 sequence를 서버에
    // 먼저 전달한다. 커서는 단조 증가하므로 진행 중 작업과 중복되어도 안전하다.
    _flushReadOnDispose();
    _isLeavingRoom = true;
    _cacheHydrationGeneration++;
    _auxiliarySubscriptionGeneration++;
    _auxiliaryRetryTimer?.cancel();
    _draftSaveDebounce?.cancel();
    _messageCacheDebounce?.cancel();
    _outboxRetryTimer?.cancel();
    _messageRetryTimer?.cancel();
    _fileExpiryTimer?.cancel();
    _roomRetryTimer?.cancel();
    _messageController.removeListener(_onDraftChanged);
    if (!_roomWasLeft) {
      unawaited(
        _localCache.saveDraft(widget.snackChatId, _messageController.text),
      );
      if (_messages.isNotEmpty) {
        unawaited(
          _localCache.upsertMessages(widget.snackChatId, List.of(_messages)),
        );
      }
    }
    WidgetsBinding.instance.removeObserver(this);
    _autoMarkReadDebounce?.cancel();
    if (SnackChatActiveConversation.isActive(widget.snackChatId)) {
      SnackChatActiveConversation.setActive(null);
    }
    _msgSub?.cancel();
    _memberSub?.cancel();
    _reactionSub?.cancel();
    _voteSub?.cancel();
    _blockSub?.cancel();
    _fileTransferSub?.cancel();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _isTerminalRoomError(Object? error) {
    if (error is! FirebaseException) return false;
    return error.code == 'permission-denied' ||
        error.code == 'not-found' ||
        error.code == 'unauthenticated';
  }

  void _scheduleRoomAccessTermination() {
    if (_roomAccessTerminated || _roomAccessTerminationScheduled) return;
    _roomAccessTerminationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _roomAccessTerminationScheduled = false;
      if (!mounted || _roomAccessTerminated) return;
      setState(() {
        _roomAccessTerminated = true;
        _roomWasLeft = true;
        _lastRoom = null;
      });
      _draftSaveDebounce?.cancel();
      _messageCacheDebounce?.cancel();
      _outboxRetryTimer?.cancel();
      _messageRetryTimer?.cancel();
      _roomRetryTimer?.cancel();
      unawaited(_localCache.clearRoom(widget.snackChatId));
      _messageSubscriptionGeneration++;
      _auxiliarySubscriptionGeneration++;
      _autoMarkReadDebounce?.cancel();
      _autoMarkReadDebounce = null;
      _auxiliaryRetryTimer?.cancel();
      _auxiliaryRetryTimer = null;
      final subscriptions = <StreamSubscription<dynamic>?>[
        _msgSub,
        _memberSub,
        _reactionSub,
        _voteSub,
        _blockSub,
      ];
      _msgSub = null;
      _memberSub = null;
      _reactionSub = null;
      _voteSub = null;
      _blockSub = null;
      for (final subscription in subscriptions) {
        if (subscription != null) unawaited(subscription.cancel());
      }
      if (SnackChatActiveConversation.isActive(widget.snackChatId)) {
        SnackChatActiveConversation.setActive(null);
      }
    });
  }

  Future<void> _confirmRoomUnavailable() async {
    if (_roomAccessTerminated ||
        _roomAvailabilityCheckInFlight ||
        _isLeavingRoom) {
      return;
    }
    final roomId = widget.snackChatId;
    _roomAvailabilityCheckInFlight = true;
    try {
      final confirmed = await _snackChatService.getSnackChatFromServer(
        roomId,
      );
      if (!mounted || _isLeavingRoom || roomId != widget.snackChatId) return;
      if (confirmed == null) {
        setState(() => _lastRoom = null);
        _scheduleRoomAccessTermination();
      } else {
        setState(() => _lastRoom = confirmed);
      }
    } catch (error) {
      if (_isTerminalRoomError(error)) _scheduleRoomAccessTermination();
      // A network timeout is not proof that access was revoked. Firestore's
      // room stream remains attached and can recover on its own.
    } finally {
      _roomAvailabilityCheckInFlight = false;
    }
  }

  Future<void> _send() async {
    final roomId = widget.snackChatId;
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLeavingRoom) return;
    final uid = _uid;
    if (uid == null) return;
    final messageId = _snackChatService.createMessageId(roomId);
    if (!_sendingTextMessageIds.add(messageId)) return;
    final reply = _replyPreviewForCurrentTarget();
    final localMessage = SnackChatMessage(
      id: messageId,
      senderId: uid,
      senderName: FirebaseAuth.instance.currentUser?.displayName,
      text: text,
      createdAt: _nextOptimisticCreatedAt(),
      replyToMessageId: reply?.messageId,
      replyPreview: reply,
      sendStatus: MessageSendStatus.sending,
    );
    final keepFocus = _messageFocusNode.hasFocus;
    _messageController.clear();
    unawaited(_localCache.saveDraft(roomId, ''));
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _clearReplyState();
      _insertLocalMessage(localMessage);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && keepFocus && !_messageFocusNode.hasFocus) {
        _messageFocusNode.requestFocus();
      }
      if (mounted && _isNearLatest) _scrollToLatest(animated: true);
    });
    try {
      await _enqueueOutbound(roomId, () async {
        final ok = await _snackChatService.sendMessage(
          roomId,
          text,
          messageId: messageId,
          replyPreview: reply,
        );
        await _resolveSendOutcome(messageId, ok, roomId: roomId);
      });
    } finally {
      _sendingTextMessageIds.remove(messageId);
    }
  }

  Future<void> _enqueueOutbound(
    String roomId,
    Future<void> Function() operation,
  ) async {
    final previous = _outboundQueues[roomId] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) => operation());
    _outboundQueues[roomId] = next;
    try {
      await next;
    } finally {
      if (identical(_outboundQueues[roomId], next)) {
        _outboundQueues.remove(roomId);
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_isUploadingImage || _isLeavingRoom) return;
    final roomId = widget.snackChatId;
    final uid = _uid;
    if (uid == null) return;

    String? pendingMessageId;
    setState(() => _isUploadingImage = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 88,
      );
      if (picked == null) return;
      if (!mounted || roomId != widget.snackChatId) return;

      final messageId = _snackChatService.createMessageId(roomId);
      pendingMessageId = messageId;
      final reply = _replyPreviewForCurrentTarget();
      setState(() {
        _clearReplyState();
        _insertLocalMessage(SnackChatMessage(
          id: messageId,
          senderId: uid,
          senderName: FirebaseAuth.instance.currentUser?.displayName,
          type: SnackChatMessageType.image,
          text: '',
          createdAt: _nextOptimisticCreatedAt(),
          replyToMessageId: reply?.messageId,
          replyPreview: reply,
          sendStatus: MessageSendStatus.sending,
          localImagePath: picked.path,
        ));
      });
      await _enqueueOutbound(roomId, () async {
        final upload = await _storageService.uploadPrivateSnackChatImage(
          File(picked.path),
          userId: uid,
          snackChatId: roomId,
        );
        if (upload == null || upload.storagePath.isEmpty) {
          if (mounted && roomId == widget.snackChatId) {
            _markMessageFailed(messageId, '이미지 업로드에 실패했습니다.');
          }
          return;
        }

        final imageUrl = upload.imageUrl;
        final imagePath = upload.storagePath;
        if (mounted && roomId == widget.snackChatId) {
          _updateLocalMessage(
            messageId,
            (message) => message.copyWith(
              imageUrl: imageUrl,
              imagePath: imagePath,
            ),
          );
        }

        final ok = await _snackChatService.sendImageMessage(
          roomId,
          imageUrl: imageUrl,
          imagePath: imagePath,
          messageId: messageId,
          replyPreview: reply,
        );
        // Do not delete the upload when the client response is uncertain: the
        // transaction may already have committed and retry uses the same ID.
        await _resolveSendOutcome(messageId, ok, roomId: roomId);
      });
    } catch (_) {
      if (pendingMessageId != null) {
        if (mounted && roomId == widget.snackChatId) {
          _markMessageFailed(
            pendingMessageId,
            '이미지를 전송하지 못했습니다. 눌러서 다시 시도하세요.',
          );
        }
      } else if (mounted && roomId == widget.snackChatId) {
        _showNotice('이미지를 불러오지 못했습니다.');
      }
    } finally {
      if (mounted && roomId == widget.snackChatId) {
        setState(() => _isUploadingImage = false);
      }
    }
  }

  ReplyMessagePreview? _replyPreviewForCurrentTarget({
    bool forDisplay = false,
  }) {
    final target = _replyingTo;
    if (target == null) return null;
    final preview = ReplyMessagePreview.fromMessage(target);
    final resolvedName = _replyingToSenderName?.trim() ?? '';
    return forDisplay && resolvedName.isNotEmpty
        ? preview.copyWith(senderName: resolvedName)
        : preview;
  }

  void _clearReplyState() {
    _replyingTo = null;
    _replyingToSenderName = null;
  }

  void _insertLocalMessage(SnackChatMessage message) {
    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index < 0) {
      _messageIds.add(message.id);
      _messages.add(message);
    } else {
      _messages[index] = message;
    }
    _sortMessages();
    _scheduleMessageCacheWrite();
  }

  void _updateLocalMessage(
    String messageId,
    SnackChatMessage Function(SnackChatMessage message) update,
  ) {
    if (!mounted) return;
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    setState(() => _messages[index] = update(_messages[index]));
    _scheduleMessageCacheWrite();
  }

  void _markMessageFailed(String messageId, String reason) {
    _updateLocalMessage(
      messageId,
      (message) => message.copyWith(
        sendStatus: MessageSendStatus.failed,
        errorMessage: reason,
      ),
    );
    _scheduleOutboxRecovery();
  }

  void _scheduleOutboxRecovery() {
    if (_outboxRetryTimer != null ||
        _isLeavingRoom ||
        _roomAccessTerminated ||
        _outboxRetryAttempt >= 5) {
      return;
    }
    final uid = _uid;
    if (uid == null ||
        !_messages.any(
          (message) => message.senderId == uid && message.hasFailed,
        )) {
      _outboxRetryAttempt = 0;
      return;
    }
    final seconds = (1 << _outboxRetryAttempt).clamp(2, 30).toInt();
    _outboxRetryAttempt++;
    _outboxRetryTimer = Timer(Duration(seconds: seconds), () async {
      _outboxRetryTimer = null;
      if (!mounted ||
          _isLeavingRoom ||
          _roomAccessTerminated ||
          _appLifecycleState != AppLifecycleState.resumed) {
        return;
      }
      final pending = _messages
          .where(
            (message) => message.senderId == _uid && message.hasFailed,
          )
          .toList(growable: false)
          .reversed
          .toList(growable: false);
      await Future.wait(pending.map(_retryMessage));
      if (!mounted) return;
      if (_messages.any(
        (message) => message.senderId == _uid && message.hasFailed,
      )) {
        _scheduleOutboxRecovery();
      } else {
        _outboxRetryAttempt = 0;
      }
    });
  }

  Future<void> _resolveSendOutcome(
    String messageId,
    bool reportedSuccess, {
    String? roomId,
  }) async {
    final targetRoomId = roomId ?? widget.snackChatId;
    if (!mounted || targetRoomId != widget.snackChatId) return;
    if (reportedSuccess) {
      _updateLocalMessage(
        messageId,
        (message) => message.copyWith(
          sendStatus: MessageSendStatus.sent,
          clearErrorMessage: true,
        ),
      );
      return;
    }
    try {
      final serverMessage = await _snackChatService
          .getMessage(targetRoomId, messageId)
          .timeout(const Duration(seconds: 4));
      if (serverMessage != null &&
          mounted &&
          targetRoomId == widget.snackChatId) {
        setState(() {
          final index =
              _messages.indexWhere((message) => message.id == messageId);
          if (index >= 0) {
            _messages[index] = serverMessage.copyWith(
              localImagePath: _messages[index].localImagePath,
              localFilePath: _messages[index].localFilePath,
              fileTransferStatus: _messages[index].fileTransferStatus,
              transferProgress: _messages[index].transferProgress,
            );
            _sortMessages();
          }
        });
        return;
      }
    } catch (_) {
      // The stable document ID makes a later retry safe even when this lookup
      // cannot disambiguate an offline timeout.
    }
    if (!mounted || targetRoomId != widget.snackChatId) return;
    _markMessageFailed(messageId, '전송하지 못했습니다. 눌러서 다시 시도하세요.');
  }

  Future<void> _retryMessage(SnackChatMessage message) async {
    final roomId = widget.snackChatId;
    if (!message.hasFailed ||
        _isLeavingRoom ||
        !_retryingMessageIds.add(message.id)) {
      return;
    }
    try {
      if (message.type == SnackChatMessageType.file) {
        await _fileTransfer.retry(message.id);
        return;
      }
      _updateLocalMessage(
        message.id,
        (value) => value.copyWith(
          sendStatus: MessageSendStatus.sending,
          clearErrorMessage: true,
        ),
      );
      await _enqueueOutbound(roomId, () async {
        bool ok = false;
        if (message.type == SnackChatMessageType.image) {
          var imageUrl = message.imageUrl;
          var imagePath = message.imagePath;
          if ((imageUrl == null || imageUrl.isEmpty) &&
              (imagePath == null || imagePath.isEmpty) &&
              message.localImagePath?.isNotEmpty == true) {
            final uid = _uid;
            if (uid != null) {
              final upload = await _storageService.uploadPrivateSnackChatImage(
                File(message.localImagePath!),
                userId: uid,
                snackChatId: roomId,
              );
              if (upload != null && mounted && roomId == widget.snackChatId) {
                imageUrl = upload.imageUrl;
                imagePath = upload.storagePath;
                _updateLocalMessage(
                  message.id,
                  (value) => value.copyWith(
                    imageUrl: imageUrl,
                    imagePath: imagePath,
                  ),
                );
              }
            }
          }
          if ((imageUrl?.isNotEmpty ?? false) ||
              (imagePath?.isNotEmpty ?? false)) {
            ok = await _snackChatService.sendImageMessage(
              roomId,
              messageId: message.id,
              imageUrl: imageUrl,
              imagePath: imagePath,
              text: message.text,
              replyPreview: message.replyPreview,
            );
          }
        } else if (message.type == SnackChatMessageType.poll &&
            message.poll != null) {
          ok = await _snackChatService.sendPollMessage(
            roomId,
            poll: message.poll!,
            messageId: message.id,
          );
        } else {
          ok = await _snackChatService.sendMessage(
            roomId,
            message.text,
            messageId: message.id,
            replyPreview: message.replyPreview,
          );
        }
        await _resolveSendOutcome(message.id, ok, roomId: roomId);
      });
    } catch (_) {
      _markMessageFailed(message.id, '재전송하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      _retryingMessageIds.remove(message.id);
    }
  }

  Future<void> _removeFailedMessage(SnackChatMessage message) async {
    final uid = _uid;
    if (!message.hasFailed ||
        uid == null ||
        !_removingFailedMessageIds.add(message.id)) {
      return;
    }
    try {
      if (message.type == SnackChatMessageType.file) {
        SnackChatMessage? confirmed;
        try {
          confirmed = await _snackChatService.getMessageFromServer(
            widget.snackChatId,
            message.id,
          );
        } catch (_) {
          _showNotice('서버 전송 여부를 확인한 뒤 삭제할 수 있습니다.');
          return;
        }
        if (confirmed != null) {
          if (!mounted) return;
          _updateLocalMessage(
            message.id,
            (current) => confirmed!.copyWith(
              localFilePath: current.localFilePath,
              fileTransferStatus: SnackChatFileTransferStatus.ready,
              transferProgress: 1,
              clearErrorMessage: true,
            ),
          );
          _showNotice('이미 서버에 전송된 메시지입니다.');
          return;
        }
        await _fileTransfer.cancelAndRemove(message.id);
        if (!mounted) return;
        setState(() {
          _messages.removeWhere((item) => item.id == message.id);
          _messageIds.remove(message.id);
          _messageKeys.remove(message.id);
          _sortMessages();
        });
        unawaited(_localCache.removeMessage(widget.snackChatId, message.id));
        return;
      }
      late final SnackChatMessage? serverMessage;
      try {
        serverMessage = await _snackChatService.getMessageFromServer(
          widget.snackChatId,
          message.id,
        );
      } catch (_) {
        _showNotice('서버 전송 여부를 확인한 뒤 삭제할 수 있습니다.');
        return;
      }
      if (!mounted) return;
      final confirmedMessage = serverMessage;
      if (confirmedMessage != null) {
        setState(() {
          final index = _messages.indexWhere((item) => item.id == message.id);
          if (index >= 0) {
            _messages[index] = confirmedMessage.copyWith(
              localImagePath: _messages[index].localImagePath,
              clearErrorMessage: true,
            );
            _sortMessages();
          }
        });
        _showNotice('이미 서버에 전송된 메시지입니다.');
        return;
      }

      final storagePath = message.imagePath?.trim() ?? '';
      if (storagePath.isNotEmpty) {
        try {
          await _storageService.deletePrivateSnackChatImage(
            storagePath,
            userId: uid,
            snackChatId: widget.snackChatId,
          );
        } catch (_) {
          _showNotice('업로드된 이미지를 정리하지 못했습니다. 다시 시도해 주세요.');
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((item) => item.id == message.id);
        _messageIds.remove(message.id);
        _messageKeys.remove(message.id);
        _sortMessages();
      });
      unawaited(
        _localCache.removeMessage(widget.snackChatId, message.id),
      );
    } finally {
      _removingFailedMessageIds.remove(message.id);
    }
  }

  Future<void> _createPoll() async {
    if (_isCreatingPoll) return;
    final roomId = widget.snackChatId;
    setState(() => _isCreatingPoll = true);
    try {
      SnackChatPoll? poll;
      _routeActive = false;
      try {
        poll = await showSnackChatPollDialog(context);
      } finally {
        _routeActive = true;
        _scheduleMarkAsRead();
      }
      if (!mounted ||
          poll == null ||
          _uid == null ||
          roomId != widget.snackChatId) {
        return;
      }
      final messageId = _snackChatService.createMessageId(roomId);
      final local = SnackChatMessage(
        id: messageId,
        senderId: _uid!,
        senderName: FirebaseAuth.instance.currentUser?.displayName,
        type: SnackChatMessageType.poll,
        text: poll.question,
        createdAt: _nextOptimisticCreatedAt(),
        poll: poll,
        sendStatus: MessageSendStatus.sending,
      );
      setState(() => _insertLocalMessage(local));
      await _enqueueOutbound(roomId, () async {
        final ok = await _snackChatService.sendPollMessage(
          roomId,
          poll: poll!,
          messageId: messageId,
        );
        await _resolveSendOutcome(messageId, ok, roomId: roomId);
      });
    } finally {
      if (mounted && roomId == widget.snackChatId) {
        setState(() => _isCreatingPoll = false);
      } else {
        _isCreatingPoll = false;
      }
    }
  }

  Future<void> _showAttachmentOptions() async {
    if (_isAttachmentFlowOpen) return;
    setState(() => _isAttachmentFlowOpen = true);
    try {
      _routeActive = false;
      SnackChatAttachmentAction? action;
      try {
        action = await showSnackChatAttachmentSheet(context);
      } finally {
        _routeActive = true;
        _scheduleMarkAsRead();
      }
      if (!mounted) return;
      if (action == SnackChatAttachmentAction.image) {
        await _pickAndSendImage();
      } else if (action == SnackChatAttachmentAction.file) {
        await _pickAndQueueFiles();
      } else if (action == SnackChatAttachmentAction.poll) {
        await _createPoll();
      }
    } finally {
      if (mounted) {
        setState(() => _isAttachmentFlowOpen = false);
      } else {
        _isAttachmentFlowOpen = false;
      }
    }
  }

  Future<void> _pickAndQueueFiles() async {
    final roomId = widget.snackChatId;
    final room = _lastRoom;
    if (room == null || _uid == null) {
      _showNotice('채팅방 정보를 확인한 뒤 다시 시도해 주세요.');
      return;
    }
    FilePickerResult? picked;
    _routeActive = false;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowMultiple: true,
        withData: false,
        withReadStream: false,
        allowedExtensions:
            SnackChatFilePolicy.allowedMimeByExtension.keys.toList(),
      );
    } finally {
      _routeActive = true;
      _scheduleMarkAsRead();
    }
    if (!mounted || picked == null || roomId != widget.snackChatId) return;
    if (picked.files.length > SnackChatFilePolicy.maxSelectionCount) {
      _showNotice('파일은 한 번에 최대 5개까지 선택할 수 있습니다.');
      return;
    }
    final validated = <SnackChatSelectedFile>[];
    for (final selected in picked.files) {
      if (selected.size > SnackChatFilePolicy.maxFileBytes) {
        _showNotice('${selected.name}: 파일은 20MB 이하만 전송할 수 있습니다.');
        continue;
      }
      try {
        final path = await _documentImporter.resolveReadablePath(
          fileName: selected.name,
          pickerPath: selected.path,
          identifier: selected.identifier,
        );
        if (path == null) {
          _showNotice('${selected.name}: 파일을 읽을 수 없습니다.');
          continue;
        }
        SnackChatSelectedFile? checked;
        Object? lastError;
        StackTrace? lastStackTrace;
        for (var attempt = 0; attempt < 4 && checked == null; attempt++) {
          try {
            checked = await SnackChatFilePolicy.validatePath(
              path,
              displayName: selected.name,
            );
          } on FileSystemException catch (error, stackTrace) {
            lastError = error;
            lastStackTrace = stackTrace;
            await Future<void>.delayed(
              Duration(milliseconds: 80 * (attempt + 1)),
            );
          }
        }
        if (checked == null) {
          Error.throwWithStackTrace(
            lastError ?? StateError('document-import-not-ready'),
            lastStackTrace ?? StackTrace.current,
          );
        }
        validated.add(checked);
      } on SnackChatFileValidationException catch (error) {
        if (mounted) _showNotice('${selected.name}: ${error.message}');
      } catch (error, stackTrace) {
        Logger.error(
          'Snack Chat 첨부 파일 검사 실패: ${selected.name}',
          error,
          stackTrace,
        );
        if (mounted) _showNotice('${selected.name}: 파일을 확인할 수 없습니다.');
      }
    }
    if (!mounted || validated.isEmpty || roomId != widget.snackChatId) return;
    _routeActive = false;
    List<SnackChatSelectedFile>? confirmed;
    try {
      confirmed = await showSnackChatFileConfirmationSheet(
        context,
        files: validated,
        temporary24h: room.activeDurationHours != 0,
      );
    } finally {
      _routeActive = true;
      _scheduleMarkAsRead();
    }
    if (!mounted ||
        confirmed == null ||
        confirmed.isEmpty ||
        roomId != widget.snackChatId) {
      return;
    }
    final reply = _replyPreviewForCurrentTarget();
    late final List<SnackChatMessage> pending;
    try {
      pending = await _fileTransfer.enqueueFiles(
        room: room,
        files: confirmed,
        replyPreview: reply,
      );
    } catch (_) {
      if (mounted) _showNotice('파일 전송을 시작하지 못했습니다.');
      return;
    }
    if (!mounted || roomId != widget.snackChatId) return;
    setState(() {
      for (final message in pending) {
        _insertLocalMessage(message);
      }
      _clearReplyState();
    });
    if (_isNearLatest) _scrollToLatest(animated: true);
  }

  Future<void> _beginReply(SnackChatMessage message) async {
    if (message.type == SnackChatMessageType.system ||
        message.hasFailed ||
        message.isPending ||
        message.isDeleted) {
      return;
    }
    setState(() {
      _replyingTo = message;
      _replyingToSenderName = _safeUserLabel(message.senderName);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _messageFocusNode.requestFocus();
    });
    final embeddedName = message.senderName?.trim() ?? '';
    if (embeddedName.isNotEmpty &&
        !_looksLikeInternalIdentifier(embeddedName)) {
      return;
    }
    final resolvedName = await _senderNameFuture(
      message.senderId,
      message.senderName,
    );
    if (!mounted || _replyingTo?.id != message.id) return;
    setState(() => _replyingToSenderName = resolvedName);
  }

  Future<void> _jumpToMessage(
    String messageId, {
    String? replyingMessageId,
  }) async {
    var index = _messages.indexWhere((message) => message.id == messageId);
    SnackChatMessage? target = index >= 0 ? _messages[index] : null;
    var missingWasConfirmed = false;
    if (index < 0) {
      try {
        target = await _snackChatService.getMessageFromServer(
          widget.snackChatId,
          messageId,
        );
        missingWasConfirmed = target == null;
        if (target != null && mounted) {
          // Load the contiguous pages leading to the reply target first. A
          // sparse one-off insertion makes its visual position ambiguous and
          // fixed-height scroll estimates fail for images/long text/polls.
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          var advancedLiveWindow = false;
          while (mounted &&
              _hasMore &&
              _messages.every((message) => message.id != messageId) &&
              _isOlderThanCursor(target, _oldestMessage) &&
              DateTime.now().isBefore(deadline)) {
            if (_isLoadingMore) {
              await Future<void>.delayed(const Duration(milliseconds: 80));
              continue;
            }
            setState(() => _isLoadingMore = true);
            try {
              final remaining = deadline.difference(DateTime.now());
              if (remaining <= Duration.zero) break;
              final older = await _snackChatService
                  .fetchMessagesPage(
                    widget.snackChatId,
                    beforeMessage: _oldestMessage,
                  )
                  .timeout(remaining);
              if (!mounted) return;
              setState(() {
                _loadMoreError = null;
                for (final message in older) {
                  if (_messageIds.add(message.id)) _messages.add(message);
                }
                if (older.isNotEmpty) {
                  _oldestMessage = older.last;
                  advancedLiveWindow = true;
                }
                if (older.isEmpty || older.length < 30) _hasMore = false;
                _sortMessages();
              });
              if (older.isEmpty) break;
            } catch (error) {
              if (mounted) setState(() => _loadMoreError = error);
              break;
            } finally {
              if (mounted) setState(() => _isLoadingMore = false);
            }
          }
          if (advancedLiveWindow) _subscribeToMessages();
          index = _messages.indexWhere((message) => message.id == messageId);
          if (index < 0) {
            // Bounded fallback for exceptionally deep histories or a
            // temporarily unavailable intermediate page. It still provides
            // the immutable reply snapshot target without an endless wait.
            setState(() => _insertLocalMessage(target!));
            index = _messages.indexWhere((message) => message.id == messageId);
          }
        }
      } catch (_) {}
    }
    if (!mounted || index < 0) {
      if (missingWasConfirmed && replyingMessageId != null) {
        _markReplyTargetDeleted(replyingMessageId, messageId);
      }
      _showNotice('원본 메시지를 불러올 수 없습니다.');
      return;
    }
    final revealed = await _revealMessage(messageId, index);
    if (!revealed) _showNotice('원본 메시지 위치를 표시하지 못했습니다.');
  }

  ReplyMessagePreview _effectiveReplyPreview(ReplyMessagePreview preview) {
    var effective = preview;
    if (effective.senderName.trim().isEmpty ||
        _looksLikeInternalIdentifier(effective.senderName)) {
      effective = effective.copyWith(
        senderName: _senderNameCache[effective.senderId] ?? _genericUserLabel,
      );
    }
    if (effective.isDeleted) return effective;
    final index =
        _messages.indexWhere((message) => message.id == effective.messageId);
    if (index < 0 || !_messages[index].isDeleted) return effective;
    return effective.copyWith(
      isDeleted: true,
      textPreview: '',
      clearImageUrl: true,
      clearImagePath: true,
    );
  }

  void _markReplyTargetDeleted(String replyingMessageId, String targetId) {
    _updateLocalMessage(replyingMessageId, (message) {
      final preview = message.replyPreview;
      if (preview == null || preview.messageId != targetId) return message;
      return message.copyWith(
        replyPreview: preview.copyWith(
          isDeleted: true,
          textPreview: '',
          clearImageUrl: true,
          clearImagePath: true,
        ),
      );
    });
  }

  bool _isOlderThanCursor(
    SnackChatMessage target,
    SnackChatMessage? cursor,
  ) {
    if (cursor == null) return false;
    if (target.sequence != null && cursor.sequence != null) {
      return target.sequence! < cursor.sequence!;
    }
    final byTime = target.createdAt.compareTo(cursor.createdAt);
    if (byTime != 0) return byTime < 0;
    return target.id.compareTo(cursor.id) < 0;
  }

  Future<bool> _revealMessage(String messageId, int initialIndex) async {
    var targetIndex = initialIndex;
    for (var attempt = 0; attempt < 10; attempt++) {
      if (!mounted) return false;
      final targetContext = _messageKeys[messageId]?.currentContext;
      if (targetContext != null) {
        if (!targetContext.mounted) continue;
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        return true;
      }
      if (!_scrollController.hasClients || _messages.isEmpty) return false;
      targetIndex = _messages.indexWhere((message) => message.id == messageId);
      if (targetIndex < 0) return false;

      final position = _scrollController.position;
      final maxExtent = position.maxScrollExtent;
      final builtIndices = <int>[];
      for (var index = 0; index < _messages.length; index++) {
        if (_messageKeys[_messages[index].id]?.currentContext != null) {
          builtIndices.add(index);
        }
      }
      final averageExtent = maxExtent <= 0
          ? 76.0
          : maxExtent / (_messages.length - 1).clamp(1, 1 << 20);
      double estimate;
      if (builtIndices.isEmpty) {
        estimate = averageExtent * targetIndex;
      } else {
        builtIndices.sort((a, b) =>
            (a - targetIndex).abs().compareTo((b - targetIndex).abs()));
        final nearest = builtIndices.first;
        estimate = position.pixels + (targetIndex - nearest) * averageExtent;
      }
      final bounded = estimate.clamp(0.0, maxExtent).toDouble();
      if ((bounded - position.pixels).abs() < 1 && maxExtent > 0) {
        final direction =
            targetIndex > (builtIndices.isEmpty ? 0 : builtIndices.first)
                ? 1.0
                : -1.0;
        position.jumpTo(
          (position.pixels + direction * position.viewportDimension * 0.8)
              .clamp(0.0, maxExtent)
              .toDouble(),
        );
      } else {
        position.jumpTo(bounded);
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    return _messageKeys[messageId]?.currentContext != null;
  }

  Future<void> _toggleReaction(
    SnackChatMessage message,
    String emoji,
  ) async {
    if (message.isDeleted || message.isPending || message.hasFailed) return;
    final oldEmoji = _myReactions[message.id];
    final nextEmoji = oldEmoji == emoji ? null : emoji;
    if (!_reactionMutationsInFlight.contains(message.id) &&
        !_pendingReactionTargets.containsKey(message.id)) {
      _confirmedReactions[message.id] = oldEmoji;
    }
    setState(() {
      _applyReactionTargetInState(message.id, nextEmoji);
    });
    _pendingReactionTargets[message.id] = nextEmoji;
    await _flushReactionMutations(message.id);
  }

  void _applyReactionTargetInState(String messageId, String? target) {
    final current = _myReactions[messageId];
    if (current == target) return;
    target == null
        ? _myReactions.remove(messageId)
        : _myReactions[messageId] = target;
    final index = _messages.indexWhere((item) => item.id == messageId);
    if (index < 0) return;
    final counts = Map<String, int>.from(_messages[index].reactionCounts);
    if (current != null) {
      final remaining = (counts[current] ?? 1) - 1;
      remaining <= 0 ? counts.remove(current) : counts[current] = remaining;
    }
    if (target != null) counts[target] = (counts[target] ?? 0) + 1;
    _messages[index] = _messages[index].copyWith(reactionCounts: counts);
  }

  Future<void> _flushReactionMutations(String messageId) async {
    if (!_reactionMutationsInFlight.add(messageId)) return;
    try {
      while (_pendingReactionTargets.containsKey(messageId)) {
        final target = _pendingReactionTargets.remove(messageId);
        try {
          await _snackChatService
              .setReaction(
                snackChatId: widget.snackChatId,
                messageId: messageId,
                emoji: target,
              )
              .timeout(const Duration(seconds: 10));
          _confirmedReactions[messageId] = target;
        } on TimeoutException {
          // Firestore timeouts do not cancel the queued local write. Keep the
          // latest explicit target instead of rolling back to a state that a
          // delayed acknowledgement may immediately invalidate.
          _confirmedReactions[messageId] = target;
          if (!_pendingReactionTargets.containsKey(messageId)) {
            _showNotice('네트워크 연결 후 반응이 동기화됩니다.');
          }
        } catch (_) {
          if (!_pendingReactionTargets.containsKey(messageId) && mounted) {
            setState(() => _applyReactionTargetInState(
                  messageId,
                  _confirmedReactions[messageId],
                ));
            _showNotice('반응을 저장하지 못했습니다.');
          }
        }
      }
    } finally {
      _reactionMutationsInFlight.remove(messageId);
      // A tap can arrive between the loop condition and the in-flight cleanup.
      if (_pendingReactionTargets.containsKey(messageId)) {
        unawaited(_flushReactionMutations(messageId));
      }
    }
  }

  Future<void> _showReactionUsers(
    SnackChatMessage message,
    String emoji,
  ) async {
    _routeActive = false;
    try {
      final reactions = await _snackChatService.fetchMessageReactions(
        snackChatId: widget.snackChatId,
        messageId: message.id,
      );
      final ids = reactions
          .where((reaction) => reaction.emoji == emoji)
          .map((reaction) => reaction.userId)
          .toList(growable: false);
      if (!mounted) return;
      await _showPeopleSheet(title: '$emoji ${ids.length}명', userIds: ids);
    } catch (_) {
      if (mounted) _showNotice('반응한 사용자를 불러오지 못했습니다.');
    } finally {
      _routeActive = true;
      _scheduleMarkAsRead();
    }
  }

  Future<void> _castVote(
    SnackChatMessage message,
    List<String> optionIds,
  ) async {
    if (message.isPending ||
        message.hasFailed ||
        message.isDeleted ||
        message.poll == null ||
        message.poll!.isClosed()) {
      return;
    }
    final target = optionIds.toSet();
    if (!_voteMutationsInFlight.contains(message.id) &&
        !_pendingVoteTargets.containsKey(message.id)) {
      _confirmedVotes[message.id] =
          Set<String>.from(_myVotes[message.id] ?? const <String>{});
    }
    setState(() => _myVotes[message.id] = target);
    _pendingVoteTargets[message.id] = target;
    await _flushVoteMutations(message.id);
  }

  Future<void> _flushVoteMutations(String messageId) async {
    if (!_voteMutationsInFlight.add(messageId)) return;
    try {
      while (_pendingVoteTargets.containsKey(messageId)) {
        final target = Set<String>.from(
          _pendingVoteTargets.remove(messageId) ?? const <String>{},
        );
        try {
          await _snackChatService
              .castVote(
                snackChatId: widget.snackChatId,
                messageId: messageId,
                optionIds: target.toList(growable: false),
              )
              .timeout(const Duration(seconds: 10));
          _confirmedVotes[messageId] = Set<String>.from(target);
        } on TimeoutException {
          _confirmedVotes[messageId] = Set<String>.from(target);
          if (!_pendingVoteTargets.containsKey(messageId)) {
            _showNotice('네트워크 연결 후 투표가 동기화됩니다.');
          }
        } catch (_) {
          if (!_pendingVoteTargets.containsKey(messageId) && mounted) {
            setState(() {
              _myVotes[messageId] = Set<String>.from(
                _confirmedVotes[messageId] ?? const <String>{},
              );
            });
            _showNotice('투표를 저장하지 못했습니다.');
          }
        }
      }
    } finally {
      _voteMutationsInFlight.remove(messageId);
      if (_pendingVoteTargets.containsKey(messageId)) {
        unawaited(_flushVoteMutations(messageId));
      }
    }
  }

  _ReadReceiptData _readReceiptFor(SnackChatMessage message) {
    final sequence = message.sequence;
    if (sequence == null ||
        message.senderId != _uid ||
        (message.type != SnackChatMessageType.text &&
            message.type != SnackChatMessageType.image &&
            message.type != SnackChatMessageType.file) ||
        message.isPending ||
        message.hasFailed) {
      return const _ReadReceiptData(read: <String>[], unread: <String>[]);
    }
    final targets = <String>{};
    final deliveredAtSend = message.deliveryRecipientIds;
    if (deliveredAtSend != null) {
      targets.addAll(deliveredAtSend);
    } else {
      for (final member in _members.values) {
        if (member.wasRecipientFor(sequence, message.senderId)) {
          targets.add(member.userId);
        }
      }
      // recipientIds is the immutable client send-time fallback while the
      // server delivery marker is propagating or for a legacy message.
      targets.addAll(message.recipientIds);
      // Only the fallback uses current blocks. Server-materialized delivery
      // remains historical even if either user later blocks or unblocks.
      targets.removeAll(_blockedUserIds);
    }
    targets.remove(message.senderId);
    final read = <String>[];
    final unread = <String>[];
    for (final userId in targets) {
      final member = _members[userId];
      if ((member?.lastReadSequence ?? 0) >= sequence ||
          message.readBy.contains(userId)) {
        read.add(userId);
      } else {
        unread.add(userId);
      }
    }
    return _ReadReceiptData(read: read, unread: unread);
  }

  Map<String, DMUserInfo?> _cachedPeople(Iterable<String> userIds) =>
      <String, DMUserInfo?>{
        for (final id in userIds) id: _userInfoCache.getCachedUserInfo(id),
      };

  Future<Map<String, DMUserInfo?>> _loadPeople(
    List<String> userIds,
  ) =>
      _userInfoCache.getUserInfoBatch(userIds).timeout(_peopleLookupDeadline);

  Widget _peopleLoadRetry({
    required bool isKo,
    required VoidCallback onRetry,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isKo
                  ? '일부 프로필을 불러오지 못해 저장된 정보를 표시합니다.'
                  : 'Some profiles could not be loaded. Showing saved information.',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12.5,
                height: 1.35,
                color: _secondaryText,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: Text(isKo ? '다시 시도' : 'Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _showReadReceiptDetails(SnackChatMessage message) async {
    final receipt = _readReceiptFor(message);
    if (receipt.total == 0) return;
    _routeActive = false;
    final ids = <String>[...receipt.read, ...receipt.unread];
    final initialCached = _cachedPeople(ids);
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    var peopleFuture = _loadPeople(ids);
    try {
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => FractionallySizedBox(
          heightFactor: 0.72,
          child: StatefulBuilder(
            builder: (context, setSheetState) =>
                FutureBuilder<Map<String, DMUserInfo?>>(
              future: peopleFuture,
              initialData: initialCached,
              builder: (context, snapshot) {
                final users = _cachedPeople(ids);
                final loaded = snapshot.data;
                if (loaded != null) users.addAll(loaded);
                final loading =
                    snapshot.connectionState != ConnectionState.done;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    if (snapshot.hasError)
                      _peopleLoadRetry(
                        isKo: isKo,
                        onRetry: () => setSheetState(
                          () => peopleFuture = _loadPeople(ids),
                        ),
                      ),
                    _peopleSectionTitle(
                      isKo
                          ? '확인 ${receipt.read.length}명'
                          : 'Seen ${receipt.read.length}',
                    ),
                    ...receipt.read.map(
                      (id) => _personTile(id, users[id], loading: loading),
                    ),
                    const SizedBox(height: 16),
                    _peopleSectionTitle(
                      isKo
                          ? '미확인 ${receipt.unread.length}명'
                          : 'Not seen ${receipt.unread.length}',
                    ),
                    ...receipt.unread.map(
                      (id) => _personTile(id, users[id], loading: loading),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    } finally {
      _routeActive = true;
      _scheduleMarkAsRead();
    }
  }

  Future<void> _showPeopleSheet({
    required String title,
    required List<String> userIds,
  }) async {
    final initialCached = _cachedPeople(userIds);
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    var peopleFuture = _loadPeople(userIds);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) =>
            FutureBuilder<Map<String, DMUserInfo?>>(
          future: peopleFuture,
          initialData: initialCached,
          builder: (context, snapshot) {
            final users = _cachedPeople(userIds);
            final loaded = snapshot.data;
            if (loaded != null) users.addAll(loaded);
            final loading = snapshot.connectionState != ConnectionState.done;
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                if (snapshot.hasError)
                  _peopleLoadRetry(
                    isKo: isKo,
                    onRetry: () => setSheetState(
                      () => peopleFuture = _loadPeople(userIds),
                    ),
                  ),
                _peopleSectionTitle(title),
                ...userIds.map(
                  (id) => _personTile(id, users[id], loading: loading),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _peopleSectionTitle(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _personTile(
    String userId,
    DMUserInfo? info, {
    bool loading = false,
  }) {
    final isBlocked = _blockedUserIds.contains(userId);
    final name = isBlocked
        ? '차단한 사용자'
        : info == null
            ? loading
                ? '불러오는 중…'
                : '탈퇴한 사용자'
            : _safeUserLabel(info.nickname);
    final photoUrl = isBlocked ? '' : (info?.photoURL ?? '');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 40,
      leading: info != null && !isBlocked
          ? UserAvatar(
              uid: userId,
              photoUrl: photoUrl,
              photoVersion: info.photoVersion,
              isAnonymous: false,
              size: 36,
              placeholderIcon: Icons.person_outline_rounded,
              placeholderIconSize: 19,
            )
          : CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFE4E7EC),
              child: loading && !isBlocked
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  : const Icon(Icons.person_outline_rounded, size: 19),
            ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _showMessageActions(SnackChatMessage message) async {
    _routeActive = false;
    final isMe = message.senderId == _uid;
    try {
      final action = await showModalBottomSheet<_MessageAction>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!message.hasFailed &&
                  !message.isPending &&
                  !message.isDeleted) ...[
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final extent = (constraints.maxWidth / 6)
                          .clamp(40.0, 48.0)
                          .toDouble();
                      return Wrap(
                        alignment: WrapAlignment.spaceEvenly,
                        children: const ['👍', '❤️', '😂', '😮', '😢', '🙏']
                            .map((emoji) => SizedBox.square(
                                  dimension: extent,
                                  child: IconButton(
                                    onPressed: () => Navigator.pop(
                                      sheetContext,
                                      _MessageAction(
                                        _MessageActionType.reaction,
                                        emoji: emoji,
                                      ),
                                    ),
                                    padding: EdgeInsets.zero,
                                    tooltip: emoji,
                                    icon: Text(
                                      emoji,
                                      style: const TextStyle(fontSize: 22),
                                    ),
                                  ),
                                ))
                            .toList(growable: false),
                      );
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.reply_rounded),
                  title: const Text('답장'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    const _MessageAction(_MessageActionType.reply),
                  ),
                ),
              ],
              if (message.hasFailed && isMe) ...[
                ListTile(
                  leading: const Icon(Icons.refresh_rounded),
                  title: const Text('다시 시도'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    const _MessageAction(_MessageActionType.retry),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('실패 메시지 삭제'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    const _MessageAction(_MessageActionType.removeFailed),
                  ),
                ),
              ],
              if (!isMe && !message.hasFailed && !message.isPending) ...[
                ListTile(
                  leading: const Icon(Icons.report_gmailerrorred_outlined),
                  title: const Text('메시지 신고'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    const _MessageAction(_MessageActionType.report),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.block_outlined),
                  title: const Text('사용자 차단'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    const _MessageAction(_MessageActionType.block),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      if (!mounted || action == null) return;
      switch (action.type) {
        case _MessageActionType.reaction:
          final emoji = action.emoji;
          if (emoji != null) await _toggleReaction(message, emoji);
          break;
        case _MessageActionType.reply:
          await _beginReply(message);
          break;
        case _MessageActionType.retry:
          await _retryMessage(message);
          break;
        case _MessageActionType.removeFailed:
          await _removeFailedMessage(message);
          break;
        case _MessageActionType.report:
          await showReportDialog(
            context,
            reportedUserId: message.senderId,
            targetType: 'snack_chat_message',
            targetId: '${widget.snackChatId}/${message.id}',
            targetTitle: message.type == SnackChatMessageType.file
                ? message.originalFileName ?? '파일 메시지'
                : message.text.trim().isEmpty
                    ? '이미지 메시지'
                    : message.text.trim(),
          );
          break;
        case _MessageActionType.block:
          await showBlockUserDialog(
            context,
            userId: message.senderId,
            userName: _safeUserLabel(message.senderName),
          );
          break;
      }
    } finally {
      _routeActive = true;
      _scheduleMarkAsRead();
    }
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) _showNotice('링크를 열 수 없습니다.');
    } catch (_) {
      if (mounted) _showNotice('링크를 열 수 없습니다.');
    }
  }

  void _showNotice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// 방을 나가기 전에 읽음 타이머와 Firestore 구독을 먼저 중단한다.
  /// 나가기 트랜잭션과 markAsRead/stream callback이 경합해 이미 제거된
  /// 참여자의 필드를 다시 쓰는 상황을 방지한다.
  Future<void> _leaveRoomFromInfo() async {
    if (_isLeavingRoom) return;
    if (!mounted) {
      throw StateError('채팅 화면이 이미 닫혔습니다.');
    }
    setState(() => _isLeavingRoom = true);
    _draftSaveDebounce?.cancel();
    _messageCacheDebounce?.cancel();
    _outboxRetryTimer?.cancel();
    _messageRetryTimer?.cancel();
    _roomRetryTimer?.cancel();
    _autoMarkReadDebounce?.cancel();
    _autoMarkReadDebounce = null;
    _auxiliarySubscriptionGeneration++;
    _auxiliaryRetryTimer?.cancel();
    _auxiliaryRetryTimer = null;

    // 아래 StreamBuilder까지 null stream으로 교체되는 프레임을 기다려
    // 방 문서 접근 권한이 제거된 뒤 기존 listener가 재조회하지 않게 한다.
    await WidgetsBinding.instance.endOfFrame;

    final messageSubscription = _msgSub;
    final memberSubscription = _memberSub;
    final reactionSubscription = _reactionSub;
    final voteSubscription = _voteSub;
    final blockSubscription = _blockSub;
    _msgSub = null;
    _memberSub = null;
    _reactionSub = null;
    _voteSub = null;
    _blockSub = null;

    try {
      await Future.wait<void>([
        if (messageSubscription != null) messageSubscription.cancel(),
        if (memberSubscription != null) memberSubscription.cancel(),
        if (reactionSubscription != null) reactionSubscription.cancel(),
        if (voteSubscription != null) voteSubscription.cancel(),
        if (blockSubscription != null) blockSubscription.cancel(),
      ]);
      final pendingRead = _markAsReadOperation;
      if (pendingRead != null) {
        try {
          await pendingRead.timeout(const Duration(seconds: 2));
        } catch (_) {
          // 읽음 반영은 best-effort다. 네트워크가 느리거나 실패해도 방
          // 나가기 자체를 막거나 무한 대기시키지 않는다.
        }
      }
      await _snackChatService.leaveRoom(widget.snackChatId);
      await _localCache.clearRoom(widget.snackChatId);
      _roomWasLeft = true;
    } catch (_) {
      // 나가기에 실패했다면 현재 채팅 화면을 계속 사용할 수 있도록
      // 중단했던 구독과 읽음 처리를 복구한다.
      if (mounted) {
        setState(() => _isLeavingRoom = false);
        _subscribeToMessages();
        _subscribeToAuxiliaryState();
      } else {
        _isLeavingRoom = false;
      }
      rethrow;
    }
  }

  Future<void> _openRoomInfo(SnackChat room) async {
    if (_isLeavingRoom) return;
    _routeActive = false;
    final infoRoute = MaterialPageRoute<bool>(
      builder: (_) => SnackChatInfoScreen(
        snackChatId: room.id,
        onLeave: _leaveRoomFromInfo,
      ),
    );
    try {
      final didLeave = await Navigator.of(context).push<bool>(infoRoute);
      if (!mounted || didLeave != true) return;

      // push()의 Future는 reverse transition이 끝나기 전에 완료될 수 있다.
      // 정보 화면의 overlay가 완전히 제거된 뒤 채팅 화면을 닫아 연속 pop으로
      // 인한 framework dependency assertion을 방지한다.
      await infoRoute.completed;
      if (!mounted) return;

      if (SnackChatActiveConversation.isActive(widget.snackChatId)) {
        SnackChatActiveConversation.setActive(null);
      }

      if (widget.fromPush) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const MainScreen(
              initialGroupTabIndex: snackChatTabIndex,
            ),
          ),
          (_) => false,
        );
        return;
      }
      Navigator.of(context).pop(true);
    } finally {
      _routeActive = true;
      if (mounted && !_isLeavingRoom && !_roomAccessTerminated) {
        _scheduleMarkAsRead();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final l10n = AppLocalizations.of(context)!;
    return StreamBuilder<SnackChat?>(
      stream: _isLeavingRoom ? null : _roomStream,
      builder: (context, roomSnap) {
        final incomingRoom = roomSnap.data;
        if (incomingRoom != null) {
          _roomRetryTimer?.cancel();
          _roomRetryTimer = null;
          _roomRetryAttempt = 0;
          _lastRoom = incomingRoom;
          _cacheRoomIfChanged(incomingRoom);
        } else if (!_isLeavingRoom &&
            !roomSnap.hasError &&
            roomSnap.connectionState == ConnectionState.active) {
          // An active null snapshot is a definitive deleted/missing room, not
          // an initial loading frame. Confirm against the server before
          // stopping child listeners because an empty local cache can also
          // briefly produce a null document snapshot during startup.
          unawaited(_confirmRoomUnavailable());
        } else if (roomSnap.hasError && _isTerminalRoomError(roomSnap.error)) {
          _lastRoom = null;
          _scheduleRoomAccessTermination();
        } else if (roomSnap.hasError) {
          _scheduleRoomRetry();
        }
        final terminalRoomError =
            roomSnap.hasError && _isTerminalRoomError(roomSnap.error);
        final room = _roomAccessTerminated || terminalRoomError
            ? null
            : incomingRoom ?? _lastRoom;
        if (room == null &&
            roomSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (room == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    roomSnap.hasError ? '대화방을 불러오지 못했습니다.' : '대화방을 찾을 수 없습니다.',
                  ),
                  if (roomSnap.hasError) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _retryRoomStream,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(isKo ? '다시 시도' : 'Retry'),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return PopScope(
          canPop: !widget.fromPush,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && widget.fromPush) {
              _handlePushBackNavigation(room);
            }
          },
          child: Scaffold(
            backgroundColor: _chatBackground,
            appBar: AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              toolbarHeight: context.rh(58, min: 56, max: 62),
              leadingWidth: 48,
              centerTitle: true,
              titleSpacing: 4,
              iconTheme: IconThemeData(
                color: const Color(0xFF111827),
                size: context.ri(22).clamp(21, 24).toDouble(),
              ),
              title: SnackChatHeaderTitle(
                roomTitle: room.title.trim().isEmpty ||
                        _looksLikeInternalIdentifier(room.title)
                    ? l10n.snackChat
                    : room.title.trim(),
                contextLabel: l10n.snackChat,
                participantLabel:
                    l10n.snackChatParticipantCount(room.participantCount),
              ),
              actions: [
                IconButton(
                  onPressed: _isLeavingRoom ? null : () => _openRoomInfo(room),
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: Color(0xFF344054),
                  ),
                  iconSize: context.ri(22).clamp(21, 24).toDouble(),
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: isKo ? '더보기' : 'More',
                ),
                SizedBox(width: context.rs(2).clamp(0, 4).toDouble()),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: SnackChatBackdrop(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _buildMessageContent(isKo: isKo),
                      ),
                    ),
                  ),
                ),
                _buildMessageComposer(isKo: isKo),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageContent({required bool isKo}) {
    if (_isInitialLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _secondaryText),
      );
    }
    if (_messages.isEmpty && _messageStreamError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined,
                  color: _tertiaryText, size: 40),
              const SizedBox(height: 10),
              Text(
                isKo ? '메시지를 불러오지 못했습니다.' : 'Messages could not be loaded.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  color: _secondaryText,
                ),
              ),
              TextButton.icon(
                onPressed: _subscribeToMessages,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(isKo ? '다시 시도' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: context.ri(42).clamp(38, 46).toDouble(),
                color: _tertiaryText,
              ),
              SizedBox(height: context.rs(10)),
              Text(
                isKo
                    ? '스낵챗의 첫 메시지를 보내보세요.'
                    : 'Send the first message in this Snack Chat.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: context.rf(14).clamp(13, 15).toDouble(),
                  color: _secondaryText,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final messageList = ListView.builder(
      controller: _scrollController,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      scrollCacheExtent: ScrollCacheExtent.pixels(
        MediaQuery.sizeOf(context).height * 1.25,
      ),
      padding: EdgeInsets.fromLTRB(
        context.rs(10).clamp(8, 14).toDouble(),
        context.rs(10).clamp(8, 14).toDouble(),
        context.rs(10).clamp(8, 14).toDouble(),
        context.rs(6).clamp(4, 8).toDouble(),
      ),
      itemCount: _messages.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _isLoadingMore
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _secondaryText,
                      ),
                    )
                  : _loadMoreError != null
                      ? TextButton.icon(
                          onPressed: _loadMoreMessages,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                              isKo ? '이전 메시지 다시 불러오기' : 'Retry older messages'),
                        )
                      : const SizedBox.shrink(),
            ),
          );
        }
        final message = _messages[index];
        final isMe = message.senderId == _uid;
        final showDateDivider = _shouldShowDateDivider(index);
        final groupedWithNewer = index > 0 &&
            shouldGroupSnackChatMessages(message, _messages[index - 1]);
        final groupedWithOlder = index < _messages.length - 1 &&
            shouldGroupSnackChatMessages(message, _messages[index + 1]);
        final row = Column(
          children: [
            if (showDateDivider) _buildDateDivider(message.createdAt),
            _buildMessageBubble(
              message: message,
              isMe: isMe,
              timeText: _formatTime(message.createdAt),
              showTimeText: !groupedWithNewer,
              showSenderName: !isMe && !groupedWithOlder,
              groupedWithNewer: groupedWithNewer,
              groupedWithOlder: groupedWithOlder,
            ),
          ],
        );
        return VisibilityDetector(
          key: ValueKey<String>('snack-chat-visible-${message.id}'),
          onVisibilityChanged: (info) =>
              _onMessageVisibilityChanged(message, info),
          child: KeyedSubtree(
            key: _messageKeys.putIfAbsent(
              message.id,
              () => GlobalKey(debugLabel: 'snack-chat-${message.id}'),
            ),
            child: row,
          ),
        );
      },
    );
    return Stack(
      children: [
        Positioned.fill(child: messageList),
        if (_messageStreamError != null)
          Positioned(
            top: 4,
            left: 12,
            right: 12,
            child: Center(
              child: Material(
                color: const Color(0xFFF2F4F7),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: _subscribeToMessages,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.sync_problem_rounded,
                          size: 16,
                          color: _secondaryText,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            isKo
                                ? '연결이 잠시 멈췄습니다. 다시 연결'
                                : 'Live updates paused. Reconnect',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _secondaryText,
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
        if (_newMessageCount > 0)
          Positioned(
            right: context.rs(14).clamp(12, 18).toDouble(),
            bottom: context.rs(10).clamp(8, 14).toDouble(),
            child: Semantics(
              button: true,
              label: isKo
                  ? '새 메시지 $_newMessageCount개로 이동'
                  : 'Jump to $_newMessageCount new messages',
              child: Material(
                color: const Color(0xFF344054),
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  onTap: _scrollToLatest,
                  borderRadius: BorderRadius.circular(22),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_newMessageCount',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageComposer({required bool isKo}) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 360;
    final horizontalPadding = (screenWidth * 0.032).clamp(10.0, 18.0);
    final composerPadding = isNarrow ? 5.0 : 6.0;
    final actionExtent = isNarrow ? 40.0 : 44.0;
    final sendWidth = actionExtent;
    final itemGap = isNarrow ? 6.0 : 8.0;
    final composerRadius = isNarrow ? 26.0 : 30.0;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 4),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                7,
                horizontalPadding,
                6,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyingTo != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 4, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: SnackChatReplyPreviewView(
                              preview: _replyPreviewForCurrentTarget(
                                forDisplay: true,
                              )!,
                              isOutgoing: false,
                              onTap: () => _jumpToMessage(_replyingTo!.id),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(_clearReplyState),
                            tooltip: isKo ? '답장 취소' : 'Cancel reply',
                            icon: const Icon(Icons.close_rounded, size: 19),
                          ),
                        ],
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: _composerBackground,
                      borderRadius: BorderRadius.circular(composerRadius),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(composerPadding),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _buildComposerButton(
                            width: actionExtent,
                            height: actionExtent,
                            radius: actionExtent / 2,
                            tooltip: isKo ? '첨부' : 'Attach',
                            onPressed: _isAttachmentFlowOpen
                                ? null
                                : _showAttachmentOptions,
                            enabledColor: _composerAction,
                            disabledColor: _composerActionDisabled,
                            child: Icon(
                              Icons.add_rounded,
                              size: context.ri(24).clamp(22, 25).toDouble(),
                              color: _isAttachmentFlowOpen
                                  ? Colors.white54
                                  : Colors.white,
                            ),
                          ),
                          SizedBox(width: itemGap),
                          Expanded(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: actionExtent,
                                maxHeight: 108,
                              ),
                              child: MediaQuery.withClampedTextScaling(
                                maxScaleFactor: 1.3,
                                child: TextField(
                                  controller: _messageController,
                                  focusNode: _messageFocusNode,
                                  maxLines: 4,
                                  minLines: 1,
                                  maxLength: 500,
                                  buildCounter: (
                                    _, {
                                    required currentLength,
                                    required isFocused,
                                    required maxLength,
                                  }) =>
                                      null,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _send(),
                                  cursorColor: const Color(0xFFD1D5DB),
                                  style: TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize:
                                        context.rf(15).clamp(14, 16).toDouble(),
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                    height: 1.35,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: isKo
                                        ? '메시지를 입력하세요...'
                                        : 'Type a message...',
                                    hintStyle: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF9CA3AF),
                                    ),
                                    isDense: true,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: isNarrow ? 2 : 4,
                                      vertical: isNarrow ? 10 : 11,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: itemGap),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _messageController,
                            builder: (context, value, _) {
                              final canSend = value.text.trim().isNotEmpty;
                              return AnimatedOpacity(
                                opacity: canSend ? 1 : 0.45,
                                duration: const Duration(milliseconds: 150),
                                child: _buildComposerButton(
                                  width: sendWidth,
                                  height: actionExtent,
                                  radius: actionExtent / 2,
                                  tooltip: isKo ? '전송' : 'Send',
                                  onPressed: canSend ? _send : null,
                                  enabledColor: _composerAction,
                                  disabledColor: _composerActionDisabled,
                                  child: Icon(
                                    Icons.arrow_upward_rounded,
                                    size:
                                        context.ri(21).clamp(19, 22).toDouble(),
                                    color: Colors.white,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposerButton({
    required double width,
    required double height,
    required double radius,
    required String tooltip,
    required VoidCallback? onPressed,
    required Color enabledColor,
    required Color disabledColor,
    required Widget child,
  }) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: enabled ? enabledColor : disabledColor,
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: width,
              height: height,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble({
    required SnackChatMessage message,
    required bool isMe,
    required String timeText,
    required bool showTimeText,
    required bool showSenderName,
    required bool groupedWithNewer,
    required bool groupedWithOlder,
  }) {
    if (message.type == SnackChatMessageType.system) {
      return _buildSystemMessage(message);
    }
    if (_blockedUserIds.contains(message.senderId) && !isMe) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: null,
            icon: const Icon(Icons.visibility_off_outlined, size: 16),
            label: const Text('차단한 사용자의 메시지'),
            style: TextButton.styleFrom(foregroundColor: _tertiaryText),
          ),
        ),
      );
    }
    final hasImage = message.imageUrl?.isNotEmpty == true ||
        message.imagePath?.isNotEmpty == true ||
        message.localImagePath?.isNotEmpty == true;
    final hasFile = message.type == SnackChatMessageType.file;
    final hasText = message.text.trim().isNotEmpty &&
        message.type != SnackChatMessageType.poll &&
        !hasFile;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = (screenWidth * (hasImage || hasFile ? 0.76 : 0.70))
        .clamp(160.0, 420.0)
        .toDouble();
    final horizontalPadding = context.rs(2).clamp(0, 4).toDouble();
    final bottomSpacing = groupedWithNewer ? 3.0 : 10.0;
    final bubblePadding = EdgeInsets.fromLTRB(
      hasImage
          ? 6
          : hasFile
              ? 10
              : 12,
      hasImage
          ? 6
          : hasFile
              ? 10
              : 9,
      hasImage
          ? 6
          : hasFile
              ? 10
              : 12,
      hasImage
          ? 6
          : hasFile
              ? 10
              : 9,
    );
    final textStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: context.rf(14).clamp(13.5, 15).toDouble(),
      fontWeight: FontWeight.w500,
      height: 1.35,
      color: isMe ? Colors.white : const Color(0xFF111827),
    );
    final bubbleRadius = BorderRadius.only(
      topLeft: Radius.circular(!isMe && groupedWithOlder ? 6 : 16),
      topRight: Radius.circular(isMe && groupedWithOlder ? 6 : 16),
      bottomLeft: Radius.circular(!isMe && groupedWithNewer ? 6 : 16),
      bottomRight: Radius.circular(isMe && groupedWithNewer ? 6 : 16),
    );
    final replyPreview = message.replyPreview == null
        ? null
        : _effectiveReplyPreview(message.replyPreview!);
    final bubble = GestureDetector(
      onTap: hasFile ? () => _handleFileTap(message) : null,
      onLongPress:
          message.isPending ? null : () => _showMessageActions(message),
      child: Container(
        padding: bubblePadding,
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        decoration: BoxDecoration(
          color: isMe ? _outgoingBubble : _incomingBubble,
          borderRadius: bubbleRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (replyPreview != null)
              SnackChatReplyPreviewView(
                preview: replyPreview,
                isOutgoing: isMe,
                onTap: replyPreview.isDeleted
                    ? null
                    : () => _jumpToMessage(
                          replyPreview.messageId,
                          replyingMessageId: message.id,
                        ),
              ),
            if (message.isDeleted)
              Text(
                '삭제된 메시지',
                style: textStyle.copyWith(fontStyle: FontStyle.italic),
              )
            else ...[
              if (hasImage) _buildImageBubble(message: message, isMe: isMe),
              if (hasFile) _buildFileBubble(message: message, isMe: isMe),
              if (hasImage && (hasText || message.poll != null))
                const SizedBox(height: 8),
              if (message.poll != null)
                SnackChatPollCard(
                  poll: message.poll!,
                  myOptionIds: _myVotes[message.id] ?? const <String>{},
                  isOutgoing: isMe,
                  enabled: !message.isPending &&
                      !message.hasFailed &&
                      !message.isDeleted,
                  onVote: (ids) => _castVote(message, ids),
                )
              else if (hasText)
                Linkify(
                  text: message.text,
                  onOpen: (link) => _openExternalUrl(link.url),
                  style: textStyle,
                  linkStyle: textStyle.copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: textStyle.color,
                  ),
                )
              else if (!hasImage && !hasFile)
                Text(
                  message.type == SnackChatMessageType.unknown
                      ? '지원하지 않는 메시지입니다.'
                      : '메시지',
                  style: textStyle,
                ),
              if (message.linkPreview != null && !message.linkPreviewRemoved)
                SnackChatLinkPreviewCard(
                  preview: message.linkPreview!,
                  isOutgoing: isMe,
                  onOpen: () => _openExternalUrl(message.linkPreview!.url),
                  onRemove: isMe
                      ? () async {
                          final previousPreview = message.linkPreview;
                          final previousRemoved = message.linkPreviewRemoved;
                          _updateLocalMessage(
                            message.id,
                            (value) => value.copyWith(
                              clearLinkPreview: true,
                              linkPreviewRemoved: true,
                            ),
                          );
                          try {
                            await _snackChatService.removeLinkPreview(
                              widget.snackChatId,
                              message.id,
                            );
                          } on TimeoutException {
                            // Firestore keeps the queued write after the
                            // Future timeout, so retaining the explicit local
                            // target avoids flicker and late state reversal.
                            _showNotice('네트워크 연결 후 미리보기가 제거됩니다.');
                          } catch (_) {
                            if (previousPreview != null) {
                              _updateLocalMessage(
                                message.id,
                                (value) => value.copyWith(
                                  linkPreview: previousPreview,
                                  linkPreviewRemoved: previousRemoved,
                                ),
                              );
                            }
                            _showNotice('미리보기를 제거하지 못했습니다.');
                          }
                        }
                      : null,
                ),
            ],
            SnackChatReactionBar(
              counts: message.reactionCounts,
              myReaction: _myReactions[message.id],
              isOutgoing: isMe,
              onToggle: (emoji) => _toggleReaction(message, emoji),
              onShowUsers: (emoji) => _showReactionUsers(message, emoji),
            ),
          ],
        ),
      ),
    );
    final row = Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (isMe) _buildOutgoingMessageMeta(message, timeText, showTimeText),
        Flexible(child: bubble),
        if (!isMe && showTimeText)
          Padding(
            padding: const EdgeInsets.only(left: 5, bottom: 2),
            child: _messageTimeText(timeText),
          ),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(
        bottom: bottomSpacing,
        left: horizontalPadding,
        right: horizontalPadding,
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe && showSenderName)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 4),
              child: FutureBuilder<String>(
                future: _senderNameFuture(message.senderId, message.senderName),
                initialData: message.senderName?.trim().isNotEmpty == true
                    ? _safeUserLabel(message.senderName)
                    : _senderNameCache[message.senderId] ?? _genericUserLabel,
                builder: (context, snapshot) => Text(
                  snapshot.data ?? '사용자',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: context.rf(13).clamp(12, 14).toDouble(),
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
            ),
          row,
        ],
      ),
    );
  }

  Future<void> _handleFileTap(SnackChatMessage message) async {
    if (message.hasFailed) {
      await _retryMessage(message);
      return;
    }
    if (message.isPending) return;
    try {
      await _fileTransfer.openFile(message, roomId: widget.snackChatId);
    } catch (error) {
      if (!mounted) return;
      final text = error.toString().replaceFirst('Bad state: ', '');
      _showNotice(text.isEmpty ? '파일을 열 수 없습니다.' : text);
    }
  }

  Widget _buildFileBubble({
    required SnackChatMessage message,
    required bool isMe,
  }) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final expired = message.isFileExpired;
    final status = message.fileTransferStatus;
    final progress = (message.transferProgress ?? 0).clamp(0.0, 1.0).toDouble();
    String statusText;
    if (expired) {
      statusText = isKo ? '만료됨' : 'Expired';
    } else {
      statusText = switch (status) {
        SnackChatFileTransferStatus.queued => isKo ? '업로드 대기' : 'Waiting',
        SnackChatFileTransferStatus.uploading => isKo
            ? '업로드 ${(progress * 100).round()}%'
            : 'Uploading ${(progress * 100).round()}%',
        SnackChatFileTransferStatus.finalizing => isKo ? '전송 처리 중' : 'Sending',
        SnackChatFileTransferStatus.downloading => isKo
            ? '다운로드 ${(progress * 100).round()}%'
            : 'Downloading ${(progress * 100).round()}%',
        SnackChatFileTransferStatus.downloaded =>
          isKo ? '다운로드 완료' : 'Downloaded',
        SnackChatFileTransferStatus.failed =>
          isKo ? '실패 · 다시 시도' : 'Failed · Retry',
        SnackChatFileTransferStatus.canceled => isKo ? '전송 취소' : 'Canceled',
        SnackChatFileTransferStatus.expired => isKo ? '만료됨' : 'Expired',
        _ => message.isPending
            ? (isKo ? '전송 준비 중' : 'Preparing')
            : (isKo ? '눌러서 열기' : 'Tap to open'),
      };
    }
    final foreground = isMe ? Colors.white : const Color(0xFF111827);
    final secondary =
        isMe ? Colors.white.withValues(alpha: 0.72) : const Color(0xFF667085);
    final extension = (message.fileExtension ?? '').toUpperCase();
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 190),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 38,
                child: Center(
                  child: Icon(
                    _fileIcon(message.fileExtension),
                    size: 24,
                    color: expired ? _tertiaryText : foreground,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expired
                          ? (isKo ? '만료된 파일입니다' : 'This file expired')
                          : message.originalFileName ??
                              (isKo ? '문서 파일' : 'Document'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: context.rf(14).clamp(13.5, 15).toDouble(),
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: expired ? _tertiaryText : foreground,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      <String>[
                        if (extension.isNotEmpty) extension,
                        if (message.fileSize != null)
                          SnackChatFilePolicy.formatBytes(message.fileSize!),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(
                  statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: message.hasFailed
                        ? (isMe
                            ? const Color(0xFFFFD5D2)
                            : const Color(0xFFB42318))
                        : secondary,
                  ),
                ),
              ),
              if (!expired && message.expiresAt != null)
                Text(
                  message.retentionMode == 'temporary24h'
                      ? (isKo ? '24시간' : '24h')
                      : (isKo ? '30일' : '30d'),
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: secondary,
                  ),
                ),
            ],
          ),
          if (!expired &&
              (status == SnackChatFileTransferStatus.uploading ||
                  status == SnackChatFileTransferStatus.downloading)) ...[
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 2,
                value: progress,
                color: isMe ? Colors.white : const Color(0xFF475467),
                backgroundColor: isMe
                    ? Colors.white.withValues(alpha: 0.22)
                    : const Color(0xFFE4E7EC),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _fileIcon(String? extension) {
    final value = extension?.toLowerCase();
    if (value == 'pdf') return Icons.picture_as_pdf_outlined;
    if (<String>{'xls', 'xlsx', 'csv'}.contains(value)) {
      return Icons.table_chart_outlined;
    }
    if (<String>{'ppt', 'pptx'}.contains(value)) {
      return Icons.slideshow_outlined;
    }
    return Icons.description_outlined;
  }

  Widget _buildSystemMessage(SnackChatMessage message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      child: Center(
        child: Text(
          _localizedSystemMessage(message),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: context.rf(11.5).clamp(10.5, 12.5).toDouble(),
            fontWeight: FontWeight.w600,
            color: _secondaryText,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  String _localizedSystemMessage(SnackChatMessage message) {
    final fallback = message.text.trim();
    final metadata = message.metadata ?? const <String, dynamic>{};
    final systemType = (metadata['systemType'] ?? '').toString();
    final isKorean = Localizations.localeOf(context).languageCode == 'ko';
    final rawUserName = (metadata['userName'] ?? '').toString().trim();
    final userName = _redactInternalIdentifiers(rawUserName);
    final rawNewTitle = (metadata['newTitle'] ?? '').toString().trim();
    final newTitle =
        _looksLikeInternalIdentifier(rawNewTitle) ? '' : rawNewTitle;
    final question = (metadata['question'] ?? '').toString().trim();
    final announcement =
        (metadata['announcement'] ?? message.text).toString().trim();

    switch (systemType) {
      case 'member_joined':
        if (userName.isNotEmpty) {
          return isKorean
              ? '$userName님이 스낵챗에 참여했어요.'
              : '$userName joined the Snack Chat.';
        }
        break;
      case 'member_left':
        if (userName.isNotEmpty) {
          return isKorean
              ? '$userName님이 스낵챗에서 나갔어요.'
              : '$userName left the Snack Chat.';
        }
        break;
      case 'title_changed':
        if (newTitle.isNotEmpty) {
          return isKorean
              ? '스낵챗 이름이 "$newTitle"로 변경됐어요.'
              : 'The Snack Chat name changed to "$newTitle".';
        }
        break;
      case 'poll_created':
        if (userName.isNotEmpty && question.isNotEmpty) {
          return isKorean
              ? '$userName님이 투표를 만들었어요: $question'
              : '$userName created a poll: $question';
        }
        break;
      case 'poll_closed':
        if (question.isNotEmpty) {
          return isKorean ? '투표가 종료됐어요: $question' : 'Poll ended: $question';
        }
        break;
      case 'announcement':
        if (announcement.isNotEmpty) {
          return isKorean
              ? '📢 공지 · $announcement'
              : '📢 Announcement · $announcement';
        }
        break;
    }
    final localizedLegacy = _localizedLegacySystemMessage(
      fallback,
      isKorean: isKorean,
    );
    if (localizedLegacy != null) return localizedLegacy;
    if (fallback.isNotEmpty) return _redactInternalIdentifiers(fallback);
    return isKorean
        ? '채팅방 정보가 변경되었습니다.'
        : 'Snack Chat information was updated.';
  }

  String? _localizedLegacySystemMessage(
    String fallback, {
    required bool isKorean,
  }) {
    if (fallback.isEmpty) return null;

    RegExpMatch? match =
        RegExp(r'^(.+) joined the Snack Chat\.$').firstMatch(fallback);
    match ??= RegExp(r'^(.+)님이 스낵챗에 참여했어요\.$').firstMatch(fallback);
    if (match != null) {
      final name = _redactInternalIdentifiers(match.group(1)!.trim());
      return isKorean ? '$name님이 스낵챗에 참여했어요.' : '$name joined the Snack Chat.';
    }

    match = RegExp(r'^(.+) left the Snack Chat\.$').firstMatch(fallback);
    match ??= RegExp(r'^(.+)님이 스낵챗에서 나갔어요\.$').firstMatch(fallback);
    if (match != null) {
      final name = _redactInternalIdentifiers(match.group(1)!.trim());
      return isKorean ? '$name님이 스낵챗에서 나갔어요.' : '$name left the Snack Chat.';
    }

    match = RegExp(r'^The Snack Chat name changed to "(.+)"\.$')
        .firstMatch(fallback);
    match ??= RegExp(r'^스낵챗 이름이 "(.+)"로 변경됐어요\.$').firstMatch(fallback);
    if (match != null) {
      final title = match.group(1)!.trim();
      return isKorean
          ? '스낵챗 이름이 "$title"로 변경됐어요.'
          : 'The Snack Chat name changed to "$title".';
    }

    match = RegExp(r'^(.+) created a poll: (.+)$').firstMatch(fallback);
    match ??= RegExp(r'^(.+)님이 투표를 만들었어요: (.+)$').firstMatch(fallback);
    if (match != null) {
      final name = _redactInternalIdentifiers(match.group(1)!.trim());
      final question = match.group(2)!.trim();
      return isKorean
          ? '$name님이 투표를 만들었어요: $question'
          : '$name created a poll: $question';
    }

    match = RegExp(r'^Poll ended: (.+)$').firstMatch(fallback);
    match ??= RegExp(r'^투표가 종료됐어요: (.+)$').firstMatch(fallback);
    if (match != null) {
      final question = match.group(1)!.trim();
      return isKorean ? '투표가 종료됐어요: $question' : 'Poll ended: $question';
    }

    return null;
  }

  String _redactInternalIdentifiers(String value) {
    if (value.isEmpty) return value;
    return value.replaceAll(
      RegExp(r'[A-Za-z0-9_-]{20,}'),
      _genericUserLabel,
    );
  }

  Widget _buildOutgoingMessageMeta(
    SnackChatMessage message,
    String timeText,
    bool showTimeText,
  ) {
    final receipt = _readReceiptFor(message);
    final hasReceipt = receipt.total > 0;
    final everyoneConfirmed = hasReceipt && receipt.unread.isEmpty;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final failureReason = message.errorMessage?.trim() ?? '';
    final failureLabel = isKo
        ? failureReason.contains('업로드')
            ? '업로드 실패. 다시 시도'
            : '전송 실패. 다시 시도'
        : failureReason.contains('업로드')
            ? 'Upload failed. Retry'
            : 'Send failed. Retry';
    if (!message.isPending && !message.hasFailed && !showTimeText) {
      return const SizedBox(width: 5);
    }
    return Padding(
      padding: const EdgeInsets.only(right: 5, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.isPending)
            const Icon(Icons.schedule_rounded, size: 13, color: _tertiaryText)
          else if (message.hasFailed)
            Tooltip(
              message: failureReason.isEmpty ? failureLabel : failureReason,
              child: InkWell(
                onTap: () => _retryMessage(message),
                borderRadius: BorderRadius.circular(14),
                child: const SizedBox.square(
                  dimension: 28,
                  child: Center(
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 15,
                      color: Color(0xFFB42318),
                    ),
                  ),
                ),
              ),
            )
          else
            Tooltip(
              message: everyoneConfirmed
                  ? isKo
                      ? '모두 확인'
                      : 'Seen by everyone'
                  : hasReceipt
                      ? isKo
                          ? '${receipt.read.length}/${receipt.total}명 확인'
                          : '${receipt.read.length}/${receipt.total} seen'
                      : isKo
                          ? '전송됨'
                          : 'Sent',
              child: InkWell(
                onTap:
                    hasReceipt ? () => _showReadReceiptDetails(message) : null,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 28,
                  height: 24,
                  child: Center(
                    child: Icon(
                      everyoneConfirmed
                          ? Icons.done_all_rounded
                          : Icons.check_rounded,
                      size: 15,
                      color: everyoneConfirmed ? _secondaryText : _tertiaryText,
                    ),
                  ),
                ),
              ),
            ),
          if (showTimeText) _messageTimeText(timeText),
        ],
      ),
    );
  }

  Widget _messageTimeText(String timeText) => Text(
        timeText,
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: context.rf(10.5).clamp(10, 11.5).toDouble(),
          fontWeight: FontWeight.w600,
          color: _tertiaryText,
        ),
      );

  Widget _buildImageBubble({
    required SnackChatMessage message,
    required bool isMe,
  }) {
    final imageUrl = message.imageUrl;
    final storagePath = message.imagePath;
    final localPath = message.localImagePath;
    if ((imageUrl == null || imageUrl.isEmpty) &&
        (storagePath == null || storagePath.isEmpty) &&
        (localPath == null || localPath.isEmpty)) {
      return const SizedBox.shrink();
    }
    final heroTag = 'snack_chat_image_${widget.snackChatId}_${message.id}';
    final mediaSize = MediaQuery.sizeOf(context);
    final maxImageWidth =
        (mediaSize.width * 0.7).clamp(180.0, 380.0).toDouble();
    final maxImageHeight =
        (mediaSize.height * 0.38).clamp(240.0, 360.0).toDouble();

    Widget adaptiveImage(ImageProvider imageProvider) => SnackChatAdaptiveImage(
          imageProvider: imageProvider,
          maxWidth: maxImageWidth,
          maxHeight: maxImageHeight,
          error: _imageError(isMe),
        );

    return GestureDetector(
      onTap: message.isPending && imageUrl == null && storagePath == null
          ? null
          : () => _openImageViewer(
                imageUrl,
                storagePath: storagePath,
                heroTag: heroTag,
              ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxImageWidth,
          maxHeight: maxImageHeight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Hero(
            tag: heroTag,
            child: localPath?.isNotEmpty == true &&
                    (storagePath == null || message.isPending)
                ? adaptiveImage(FileImage(File(localPath!)))
                : storagePath?.isNotEmpty == true
                    ? SnackChatStorageImage(
                        storagePath: storagePath!,
                        imageBuilder: (_, imageProvider) =>
                            adaptiveImage(imageProvider),
                        loading: _imageLoading(),
                        error: imageUrl?.isNotEmpty == true
                            ? CachedNetworkImage(
                                imageUrl: imageUrl!,
                                cacheManager: AppImageCacheManager.instance,
                                imageBuilder: (_, imageProvider) =>
                                    adaptiveImage(imageProvider),
                                errorWidget: (_, __, ___) => _imageError(isMe),
                              )
                            : _imageError(isMe),
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl!,
                        cacheManager: AppImageCacheManager.instance,
                        imageBuilder: (_, imageProvider) =>
                            adaptiveImage(imageProvider),
                        placeholder: (_, __) => _imageLoading(),
                        errorWidget: (_, __, ___) => _imageError(isMe),
                      ),
          ),
        ),
      ),
    );
  }

  Widget _imageLoading() => const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );

  Widget _imageError(bool isMe) => Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: isMe ? Colors.white70 : Colors.black54,
        ),
      );

  Future<void> _openImageViewer(
    String? imageUrl, {
    String? storagePath,
    required String heroTag,
  }) async {
    _routeActive = false;
    try {
      await showFullscreenImageViewer(
        context,
        imageUrls: [imageUrl ?? ''],
        storagePaths: [storagePath],
        initialIndex: 0,
        heroTag: heroTag,
      );
    } finally {
      _routeActive = true;
      _scheduleMarkAsRead();
    }
  }

  String _formatTime(DateTime t) {
    final local = t.toLocal();
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final period =
        local.hour < 12 ? (isKo ? '오전' : 'AM') : (isKo ? '오후' : 'PM');
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$period $hour:$minute';
  }

  // 날짜가 바뀌는지 확인
  bool _shouldShowDateDivider(int index) {
    if (index == _messages.length - 1) {
      // 맨 처음(가장 오래된) 메시지는 항상 날짜 표시
      return true;
    }
    final currentMsg = _messages[index];
    final prevMsg = _messages[index + 1]; // reverse=true이므로 index+1이 더 오래된 메시지

    final currentDate = currentMsg.createdAt.toLocal();
    final prevDate = prevMsg.createdAt.toLocal();

    // 날짜가 다르면 구분선 표시
    return currentDate.year != prevDate.year ||
        currentDate.month != prevDate.month ||
        currentDate.day != prevDate.day;
  }

  // 날짜 구분선 UI
  Widget _buildDateDivider(DateTime dateTime) {
    final local = dateTime.toLocal();
    final now = DateTime.now();
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    String dateText;
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(local.year, local.month, local.day);

    if (messageDate == today) {
      dateText = isKo ? '오늘' : 'Today';
    } else if (messageDate == yesterday) {
      dateText = isKo ? '어제' : 'Yesterday';
    } else {
      // 올해면 월/일만, 다른 해면 년/월/일
      if (local.year == now.year) {
        dateText = isKo
            ? '${local.month}월 ${local.day}일'
            : '${_getMonthName(local.month)} ${local.day}';
      } else {
        dateText = isKo
            ? '${local.year}년 ${local.month}월 ${local.day}일'
            : '${_getMonthName(local.month)} ${local.day}, ${local.year}';
      }
    }

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: context.rs(12).clamp(10, 14).toDouble(),
          horizontal: context.rs(12).clamp(10, 16).toDouble(),
        ),
        child: Text(
          dateText,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: context.rf(11.5).clamp(10.5, 12).toDouble(),
            fontWeight: FontWeight.w600,
            color: _secondaryText,
          ),
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month - 1];
  }

  void _handlePushBackNavigation(SnackChat room) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (room.isFavoritedBy(currentUserId)) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const MainScreen(
            initialGroupTabIndex: snackChatTabIndex,
          ),
        ),
        (route) => false,
      );
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    }
  }
}
