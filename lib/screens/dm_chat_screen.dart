// lib/screens/dm_chat_screen.dart
// DM 대화 화면
// 메시지 목록과 입력창을 표시하고 실시간 메시지 전송/수신

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:linkify/linkify.dart' as linkify;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/conversation.dart';
import '../models/dm_message.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import '../services/dm_message_cache_service.dart';
import '../models/content_translation.dart';
import '../services/dm_service.dart';
import '../services/chat_outbox_store.dart';
import '../utils/chat_work_queue.dart';
import '../ui/widgets/snack_chat_outgoing_entrance.dart';
import '../ui/widgets/chat_reaction_widgets.dart';
import '../ui/widgets/motion_press.dart';
import '../ui/widgets/chat_reply_reveal.dart';
import '../ui/widgets/swipe_to_reply.dart';
import '../ui/widgets/retryable_chat_network_image.dart';
import '../services/dm_active_conversation.dart';
import '../services/navigation_service.dart';
import '../services/badge_service.dart';
import '../services/fcm_service.dart';
import '../services/post_service.dart';
import '../services/report_service.dart';
import '../services/storage_service.dart';
import '../services/snack_chat_document_import_service.dart';
import '../services/user_info_cache_service.dart';
import '../services/content_translation_service.dart';
import '../utils/time_formatter.dart';
import '../utils/snack_chat_translation_policy.dart';
import '../l10n/app_localizations.dart';
import '../constants/app_constants.dart';
import '../design/tokens.dart';
import 'package:intl/intl.dart';
import 'post_detail_screen.dart';
import '../ui/widgets/fullscreen_image_viewer.dart';
import 'dm_image_send_preview_screen.dart';
import 'friend_profile_screen.dart';
import '../ui/widgets/user_avatar.dart';
import '../utils/logger.dart';
import '../utils/chat_timing.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/sheets/translation_language_sheet.dart';
import '../ui/widgets/chat_video_tile.dart';
import '../ui/widgets/video_preparing_dialog.dart';
import '../services/media/video_prepare_service.dart';
import '../services/media/video_upload_policy.dart';
import 'video_playback_screen.dart';
import '../ui/sheets/snack_chat_file_confirmation_sheet.dart';
import '../config/snack_chat_file_policy.dart';
import '../config/app_backend.dart';
import '../l10n/ui_locale.dart';
import '../ui/widgets/chat_pill_composer.dart';
import '../utils/chat_message_typography.dart';
import '../ui/chat/chat_metrics.dart';
import '../ui/widgets/snack_chat_translation_split_button.dart';
import '../ui/widgets/dm_header_identity.dart';
import '../ui/widgets/snack_chat_translated_text.dart';
import '../l10n/translation_source_language.dart';
import '../services/clipboard_image_service.dart';
import '../ui/widgets/translate_hints.dart';

// DM 전용 색상
class DMColors {
  static const pageBg = Color(0xFFF4F5F3);
  static const surface = Colors.white;
  static const graphite = Color(0xFF344054);
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF667085);
  static const textTertiary = Color(0xFF98A2B3);
  static const divider = Color(0xFFE4E7EC);
  static const myMessageBg = graphite;
  static const myMessageText = Colors.white;
  static const otherMessageBg = surface;
  static const otherMessageText = textPrimary;
  static const composerBg = Color(0xFF242424);
  static const composerActionBg = Color(0xFF3A3A3C);
  static const inputBg = Colors.transparent;
  static const inputBorder = Colors.transparent;
}

enum _DmTranslationPriority { live, visible, adjacent }

class _DmTranslationCandidate {
  const _DmTranslationCandidate({
    required this.message,
    required this.priority,
    required this.distanceFromViewportCenter,
  });

  final DMMessage message;
  final _DmTranslationPriority priority;
  final double distanceFromViewportCenter;
}

class _DmTranslationOutcome {
  const _DmTranslationOutcome({
    required this.message,
    required this.requestKey,
    required this.result,
  });

  final DMMessage message;
  final String requestKey;
  final ContentTranslationResult? result;
}

class DMChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;

  /// 게시글 상세/카드에서 DM으로 진입한 경우, 첫 전송 메시지에 붙일 게시글 컨텍스트
  /// - 상대방 채팅창에 "게시글에서 보낸 메시지" 카드(썸네일+미리보기)로 표시된다.
  final String? originPostId;
  final String? originPostImageUrl;
  final String? originPostPreview;

  /// 스낵 답장: 대화방을 열자마자 보낼 사진/영상과 출처 한 줄.
  /// 기존 사진 미리보기·영상 확인 단계를 그대로 거친다.
  final File? initialReplyMedia;
  final bool initialReplyIsVideo;
  final String? initialReplyContext;

  /// 스낵 답장(글): 대화방을 열자마자 출처 한 줄과 함께 보낼 텍스트.
  /// 새 전송 경로를 만들지 않고 기존 입력창 전송(`_sendMessage`)을 쓴다.
  final String? initialReplyText;

  /// 입력창에 미리 채워 두는 초안(자동 전송하지 않는다). 예: 질문 [답하기].
  final String? initialDraftText;

  /// 글 답장을 입력창 전송 경로로 보낸 직후 한 번 불린다(성공 보장은 아님).
  final VoidCallback? onInitialReplySent;

  const DMChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    this.originPostId,
    this.originPostImageUrl,
    this.originPostPreview,
    this.initialReplyMedia,
    this.initialReplyIsVideo = false,
    this.initialReplyContext,
    this.initialReplyText,
    this.onInitialReplySent,
    this.initialDraftText,
  });

  @override
  State<DMChatScreen> createState() => _DMChatScreenState();
}

class _DMChatScreenState extends State<DMChatScreen>
    with WidgetsBindingObserver, RouteAware {
  final DMService _dmService = DMService();
  final StorageService _storageService = StorageService();
  final SnackChatDocumentImportService _documentImporter =
      SnackChatDocumentImportService.instance;
  final UserInfoCacheService _userInfoCacheService = UserInfoCacheService();
  final _currentUser = FirebaseAuth.instance.currentUser;
  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final ContentTranslationService _translationService =
      ContentTranslationService.instance;
  final GlobalKey _messageViewportKey = GlobalKey();
  final Map<String, GlobalKey> _messageLayoutKeys = <String, GlobalKey>{};
  final Set<String> _unavailableReplyTargetIds = <String>{};
  final Map<String, ContentTranslationResult> _messageTranslations =
      <String, ContentTranslationResult>{};
  final Map<String, String> _translationSourceSignatures = <String, String>{};
  final Set<String> _translationCacheLookupsInFlight = <String>{};
  final Set<String> _translationRequestsInFlight = <String>{};
  final Map<String, _DmTranslationCandidate> _translationCandidates =
      <String, _DmTranslationCandidate>{};
  final Map<String, DateTime> _liveTranslationPriorityUntil =
      <String, DateTime>{};
  final Map<String, int> _translationFailures = <String, int>{};
  final Map<String, DateTime> _translationRetryAfter = <String, DateTime>{};
  final Map<String, _DmTranslationOutcome> _deferredTranslationOutcomes =
      <String, _DmTranslationOutcome>{};
  static const Duration _translationMicroBatchWindow =
      Duration(milliseconds: 70);
  static const int _translationBatchSize = 5;
  static const int _translationAdjacentPrefetchLimit = 2;
  Timer? _translationMicroBatchTimer;
  Timer? _translationRetryTimer;
  bool _translationScanScheduled = false;
  bool _translationModeReady = false;
  String? _targetLanguageCode;
  bool _translationLanguageSheetOpen = false;
  bool _translationLifecycleInitialized = false;
  bool _isUserScrolling = false;
  bool _receivedInitialMessageSnapshot = false;
  int _translationStateGeneration = 0;
  late int _translationLanguageRevision;
  late bool _translationShowsOriginal;
  // 번역 선택 항목(기본 꺼짐 플래그): 메시지 하나만 번역, 처음 알림 줄.
  final Set<String> _singleTranslateIds = <String>{};
  final Set<String> _singleTranslateLoading = <String>{};
  bool _translateHintDismissed = true;
  Stream<DMUserInfo?>? _otherUserInfoStream;
  // UX: 캐시 스냅샷(fromCache) → 서버 스냅샷 전환으로 인한 플리커를 방지하기 위해
  // 서버에서 확인된 최신 상대 프로필 정보를 별도로 보관한다.
  DMUserInfo? _serverOtherUserInfo;
  bool _serverOtherUserInfoFetchInFlight = false;
  bool _isOtherAccountDeleted = false;
  Timer? _autoMarkReadDebounce;
  bool _autoMarkReadInFlight = false;
  int _readGeneration = 0;
  Timestamp? _peerReadThrough;
  // The peer's server-written read-through message id. Resolved against the
  // loaded list so own messages flip to "읽음" by exact order without waiting
  // for the trigger-written receiptCreatedAt.
  String? _peerReadMessageId;
  Timestamp? _confirmedReadThrough;
  // The newest incoming message this reader has confirmed on the server. Older
  // incoming messages without receiptCreatedAt are covered by list order and
  // must not be re-targeted (each retarget is a callable round trip).
  DMMessage? _confirmedReadTargetMessage;
  DMMessage? _pendingReadTarget;
  final Set<String> _confirmedLegacyReadIds = {};
  int _autoMarkReadRetryAttempt = 0;
  Future<void>? _autoMarkReadOperation;
  String? _inFlightReadTargetId;
  Future<void>? _exitReadOperation;
  bool _exitReadFlushStarted = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _conversationReadSub;
  AppLifecycleState _appLifecycleState = AppLifecycleState.detached;

  // 대화방이 없을 수 있으므로 초기에 서버 구독을 시작하지 않는다.
  StreamSubscription<List<DMMessage>>? _recentMessagesSub;
  StreamSubscription<List<DMReaction>>? _reactionSub;
  final Map<String, String> _myReactions = <String, String>{};
  final _reactionMotionEvents = ChatReactionMotionEvents();
  final Map<String, String?> _confirmedReactions = <String, String?>{};
  final Map<String, String?> _pendingReactionTargets = <String, String?>{};
  final Set<String> _reactionMutationsInFlight = <String>{};
  int _reactionSubscriptionGeneration = 0;
  List<DMMessage> _messages = <DMMessage>[];
  Object? _messagesError;
  bool _isMessagesLoading = false; // 캐시/서버 초기 로드
  bool _isLoadingMore = false; // 과거 페이지 로드
  bool _hasMore = true; // 더 과거 메시지가 있는지(추정)
  DateTime? _visibilityStartTime; // leave 기록 기반 가시성 시작 시간
  // 초기 진입 체감 속도를 위해 "최근 N개"만 먼저 보여준다.
  // (과거 메시지는 사용자가 위로 스크롤하면 자동으로 추가 로드)
  static const int _recentLimit = 40;
  static const int _pageSize = 50;
  // 로컬 캐시도 과하게 많이 읽으면 첫 렌더가 무거워질 수 있어 recentLimit에 맞춘다.
  static const int _initialCacheLimit = _recentLimit;

  // ✅ 한번 로딩한 대화방은 화면이 살아있는 동안(나가기 전까지) 메모리 상태를 유지한다.
  // - 같은 conversationId에 대해 _initializeMessagesStream가 다시 호출되어도
  //   로컬 캐시로 _messages를 덮어쓰지 않게 하기 위한 가드.
  final Set<String> _hydratedFromLocalCacheConversationIds = <String>{};

  // 첫 메시지 전송으로 실제 conversationId가 바뀔 수 있어, 화면 내에서는 별도로 추적한다.
  String _activeConversationId = '';
  // null: 아직 확인 전(초기 로딩), false: 없음(첫 메시지 전송 시 생성), true: 존재
  bool? _conversationExists;
  bool _isConversationInitializing = true;

  Conversation? _conversation;
  final _outbox = ChatOutboxStore.instance;
  static final _dispatch = ChatWorkQueue();
  static final _imagePreparation = ChatWorkQueue();
  static final _filePreparation = ChatWorkQueue();
  final Map<String, DMMessage> _outgoing = {};
  final Set<String> _sendingIds = {};
  final Set<String> _entranceIds = {};
  final Set<String> _restoredOutboxes = {};
  final Map<String, double> _uploadById = {};
  final Map<String, double> _downloadById = {};
  final Set<String> _openingFileIds = <String>{};
  final Set<String> _cancelledOutgoingIds = <String>{};
  final Set<String> _committingOutgoingIds = <String>{};
  DateTime? _lastLocalSentAt;
  bool _followingLatest = false;
  bool _accountInvalidated = false;
  StreamSubscription<User?>? _accountSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _directBlockSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _reverseBlockSubscription;
  int _messageGeneration = 0;
  Timer? _messageReconnect;
  Timer? _outboxRetry;
  final Map<String, int> _outboxRetryAttempts = {};
  bool _isLeaving = false; // 나가기 진행 중 플래그
  static const String _anonTitlePrefsPrefix =
      'dm_anon_title__'; // conversationId -> post content
  String? _preloadedDmContent; // 미리 로드된 게시글 본문(대화방 제목용)
  String? _backfilledPostId; // dmContent 백필을 1회만 수행하기 위한 가드
  bool _isBlocked = false; // 차단 여부
  bool _isBlockedBy = false; // 차단당한 여부
  bool _directBlockStatusServerConfirmed = false;
  bool _reverseBlockStatusServerConfirmed = false;
  bool get _blockStatusReady =>
      _directBlockStatusServerConfirmed && _reverseBlockStatusServerConfirmed;
  bool get _directInteractionRestricted =>
      !_blockStatusReady || _isBlocked || _isBlockedBy;
  File? _pendingImage; // 첨부 대기 이미지 (1장 제한)
  // Images compressed while the preview screen was open, keyed by picked path.
  final Map<String, PreparedChatImage> _preparedImages = <String, PreparedChatImage>{};
  SnackChatSelectedFile? _pendingFile;
  DMMessage? _replyingTo;
  double? _uploadProgress; // 이미지 업로드 진행률 (0~1)
  bool _originPostContextAttached = false; // 현재 진입(세션)에서 게시글 컨텍스트를 1회만 부착
  bool _composerPostContextDismissed = false; // 입력창 위 미리보기 카드 닫힘 여부

  void _setActiveConversationId(String conversationId) {
    final previousConversationId = _activeConversationId;
    final translationConversationChanged =
        previousConversationId != conversationId;
    _activeConversationId = conversationId;
    if (translationConversationChanged) {
      _readGeneration++;
      _peerReadThrough = null;
      _peerReadMessageId = null;
      _confirmedReadThrough = null;
      _confirmedReadTargetMessage = null;
      _confirmedLegacyReadIds.clear();
      _pendingReadTarget = null;
      _autoMarkReadInFlight = false;
      _autoMarkReadOperation = null;
      _inFlightReadTargetId = null;
      _autoMarkReadDebounce?.cancel();
      _autoMarkReadRetryAttempt = 0;
      _exitReadFlushStarted = false;
      _myReactions.clear();
      _reactionMotionEvents.clear();
      _confirmedReactions.clear();
      _pendingReactionTargets.clear();
      _reactionMutationsInFlight.clear();
      _subscribeToReactions(conversationId);
    }
    unawaited(_restoreOutbox(conversationId));
    if (_translationLifecycleInitialized && translationConversationChanged) {
      _resetTranslationStateForConversation();
      unawaited(_prepareTranslationMode());
    }
    // 포그라운드 DM 배너 억제를 위해 현재 화면의 실제 대화방 ID를 항상 동기화한다.
    if (_appLifecycleState == AppLifecycleState.resumed) {
      DMActiveConversation.setActive(conversationId);
    }
    _watchConversationReadState(conversationId);
  }

  void _subscribeToReactions(String conversationId) {
    final generation = ++_reactionSubscriptionGeneration;
    final previous = _reactionSub;
    _reactionSub = null;
    unawaited(previous?.cancel() ?? Future<void>.value());
    if (conversationId.trim().isEmpty || _currentUser == null) return;
    _reactionSub = _dmService.watchMyReactions(conversationId).listen(
      (reactions) {
        if (!mounted || generation != _reactionSubscriptionGeneration) return;
        final next = <String, String>{
          for (final reaction in reactions) reaction.messageId: reaction.emoji,
        };
        setState(() {
          final messageIds = <String>{
            ..._myReactions.keys,
            ..._confirmedReactions.keys,
            ...next.keys,
          };
          for (final messageId in messageIds) {
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
      onError: (Object error) {
        Logger.error('DM reaction stream failed: $error');
      },
    );
  }

  void _watchConversationReadState(String conversationId) {
    unawaited(_conversationReadSub?.cancel() ?? Future<void>.value());
    final me = _currentUser;
    if (me == null) return;
    final generation = _readGeneration;
    unawaited(DMMessageCacheService()
        .peerReadThrough(me.uid, conversationId, widget.otherUserId)
        .then<void>((peer) {
      if (!mounted || generation != _readGeneration ||
          !_canSendFor(me.uid, conversationId)) return;
      if (peer != null && (_peerReadThrough == null ||
          peer.compareTo(_peerReadThrough!) > 0)) {
        setState(() => _peerReadThrough = peer);
      }
    }).catchError((Object error) => Logger.error('DM read cache failed', error)));
    unawaited(DMMessageCacheService()
        .peerReadMessageId(me.uid, conversationId, widget.otherUserId)
        .then<void>((cachedId) {
      if (!mounted || generation != _readGeneration ||
          !_canSendFor(me.uid, conversationId)) return;
      if (cachedId != null && _peerReadMessageId == null) {
        setState(() => _peerReadMessageId = cachedId);
      }
    }).catchError(
        (Object error) => Logger.error('DM read id cache failed', error)));
    _conversationReadSub = FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (!mounted || generation != _readGeneration ||
          !_canSendFor(me.uid, conversationId)) return;
      if (!snapshot.metadata.hasPendingWrites) {
        final reads = snapshot.data()?['lastReadAtBy'];
        final peer = reads is Map ? reads[widget.otherUserId] : null;
        final readIds = snapshot.data()?['lastReadMessageIdBy'];
        final peerIdRaw = readIds is Map ? readIds[widget.otherUserId] : null;
        final peerId =
            peerIdRaw is String && peerIdRaw.isNotEmpty ? peerIdRaw : null;
        final watermarkAdvanced = peer is Timestamp &&
            (_peerReadThrough == null || peer.compareTo(_peerReadThrough!) > 0);
        if (watermarkAdvanced) {
          setState(() => _peerReadThrough = peer);
          unawaited(DMMessageCacheService().peerReadThrough(
              me.uid, conversationId, widget.otherUserId, confirmed: peer)
              .then<void>((_) {}).catchError((Object error) =>
                  Logger.error('DM read cache write failed', error)));
        }
        // The server only rewrites the id when the watermark advanced, so a
        // server snapshot's value is authoritative for the current watermark.
        if (peerId != null &&
            (watermarkAdvanced || _peerReadMessageId == null) &&
            peerId != _peerReadMessageId) {
          setState(() => _peerReadMessageId = peerId);
          unawaited(DMMessageCacheService()
              .peerReadMessageId(me.uid, conversationId, widget.otherUserId,
                  confirmed: peerId)
              .then<void>((_) {})
              .catchError((Object error) =>
                  Logger.error('DM read id cache write failed', error)));
        }
      }
      final raw = snapshot.data()?['unreadCount'];
      final value = raw is Map ? raw[me.uid] : null;
      final myUnread = value is num ? value.toInt() : 0;
      if (myUnread > 0) {
        // Retry an observed boundary when the room changes, but never expand
        // it to unseen messages just because the room counter is nonzero.
        _scheduleAutoMarkAsRead(
          _messages,
        );
      }
    }, onError: (Object error) {
      Logger.error('❌ [DM 읽음] 대화방 카운터 구독 오류: $error');
    });
  }

  @override
  void initState() {
    super.initState();
    _accountSubscription =
        FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid != _currentUser?.uid) {
        _accountInvalidated = true;
        if (DMActiveConversation.isActive(_activeConversationId)) {
          DMActiveConversation.setActive(null);
        }
        _readGeneration++;
        _autoMarkReadDebounce?.cancel();
        unawaited(_conversationReadSub?.cancel());
        _messageGeneration++;
        _messageReconnect?.cancel();
        _outboxRetry?.cancel();
        unawaited(_recentMessagesSub?.cancel());
        _recentMessagesSub = null;
        _reactionSubscriptionGeneration++;
        unawaited(_reactionSub?.cancel());
        _reactionSub = null;
        _myReactions.clear();
        _reactionMotionEvents.clear();
        _confirmedReactions.clear();
        _pendingReactionTargets.clear();
      }
    });
    WidgetsBinding.instance.addObserver(this);
    _appLifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.detached;

    if (Logger.isVerboseEnabled) Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    if (Logger.isVerboseEnabled)
      Logger.log('🔍 [FCM 진단 2단계] DMChatScreen.initState 호출');
    if (Logger.isVerboseEnabled)
      Logger.log('  - widget.conversationId: ${widget.conversationId}');
    if (Logger.isVerboseEnabled)
      Logger.log('  - widget.otherUserId: ${widget.otherUserId}');
    if (Logger.isVerboseEnabled)
      Logger.log('  - widget.originPostId: ${widget.originPostId}');
    if (Logger.isVerboseEnabled) Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    // ✅ 현재 보고 있는 DM 대화방 추적 (포그라운드 DM 알림 억제에 사용)
    _setActiveConversationId(widget.conversationId);
    if (widget.initialReplyMedia != null ||
        (widget.initialReplyText ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_sendInitialSnackReply()),
      );
    }
    final draft = (widget.initialDraftText ?? '').trim();
    if (draft.isNotEmpty) {
      _messageController.text = widget.initialDraftText!;
      _messageController.selection = TextSelection.collapsed(
        offset: _messageController.text.length,
      );
    }
    _translationLanguageRevision = _translationService.languageRevision;
    _translationShowsOriginal =
        _translationService.showsOriginal(_translationScope);
    _translationService.addListener(_handleTranslationServiceChange);
    _translationLifecycleInitialized = true;
    unawaited(_prepareTranslationMode());
    if (TranslateHintFlags.firstHint) unawaited(_loadTranslateHintState());
    _otherUserInfoStream =
        _userInfoCacheService.watchUserInfo(widget.otherUserId);
    _scrollController.addListener(_onScroll);

    _watchBlockStatus(); // 열린 DM에도 차단 변경을 즉시 반영
    _preloadPostContentIfAnonymous(); // 익명이면 게시글 본문 미리 로드
    _initConversationState();

    // 상대 프로필은 서버 기준 최신값을 먼저 확보 (캐시 플리커 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isAnonymous) return;
      _ensureServerOtherUserInfo(widget.otherUserId);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) NavigationService.routeObserver.subscribe(this, route);
  }

  @override
  void didPushNext() {
    if (DMActiveConversation.isActive(_activeConversationId)) {
      DMActiveConversation.setActive(null);
    }
  }

  @override
  void didPopNext() {
    if (!mounted || _appLifecycleState != AppLifecycleState.resumed ||
        _accountInvalidated || _isLeaving) return;
    DMActiveConversation.setActive(_activeConversationId);
    _scheduleAutoMarkAsRead(_messages);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state != AppLifecycleState.resumed) {
      _outboxRetry?.cancel();
      _outboxRetry = null;
    }
    if (state == AppLifecycleState.resumed && !_accountInvalidated) {
      if (_recentMessagesSub == null && _conversationExists == true) {
        unawaited(_initializeMessagesStream());
      }
      final retryable = _outgoing.values
          .where((m) => m.deliveryState == DMDeliveryState.uncertain)
          .toList()
        ..sort((a, b) => -_compareMessagesDesc(a, b));
      if (!_directInteractionRestricted) {
        for (final message in retryable) {
          _queueOutgoing(_activeConversationId, message);
        }
      }
      if (ModalRoute.of(context)?.isCurrent == true) {
        DMActiveConversation.setActive(_activeConversationId);
      }
      _scheduleAutoMarkAsRead(_messages);
      _scheduleVisibleTranslations();
    } else if (DMActiveConversation.isActive(_activeConversationId)) {
      DMActiveConversation.setActive(null);
      _translationMicroBatchTimer?.cancel();
      _translationMicroBatchTimer = null;
      _translationCandidates.clear();
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted || !_scrollController.hasClients) return;
    final follow = _scrollController.offset <= 100;
    final anchor = follow ? null : _captureMessageAnchor();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (follow) {
        _followLatest(wasNearLatest: true);
      } else {
        _restoreMessageAnchor(anchor);
      }
    });
  }

  String get _translationScope => 'dm-conversation:$_activeConversationId';

  void _resetTranslationStateForConversation() {
    _translationStateGeneration++;
    _translationMicroBatchTimer?.cancel();
    _translationMicroBatchTimer = null;
    _translationRetryTimer?.cancel();
    _translationRetryTimer = null;
    _translationScanScheduled = false;
    _translationModeReady = false;
    _receivedInitialMessageSnapshot = false;
    _messageTranslations.clear();
    _translationSourceSignatures.clear();
    _translationCacheLookupsInFlight.clear();
    _translationRequestsInFlight.clear();
    _translationCandidates.clear();
    _liveTranslationPriorityUntil.clear();
    _translationFailures.clear();
    _translationRetryAfter.clear();
    _deferredTranslationOutcomes.clear();
    _messageLayoutKeys.clear();
    _unavailableReplyTargetIds.clear();
    _translationLanguageRevision = _translationService.languageRevision;
    _translationShowsOriginal =
        _translationService.showsOriginal(_translationScope);
  }

  Future<void> _prepareTranslationMode() async {
    final conversationId = _activeConversationId;
    if (conversationId.isEmpty) return;
    final generation = _translationStateGeneration;
    await _translationService.loadDmConversationMode(conversationId);
    if (!mounted ||
        generation != _translationStateGeneration ||
        conversationId != _activeConversationId) {
      return;
    }
    setState(() {
      _translationModeReady = true;
      _translationShowsOriginal =
          _translationService.showsOriginal(_translationScope);
    });
    _scheduleVisibleTranslations();
    unawaited(_refreshTargetLanguageLabel());
  }

  void _handleTranslationServiceChange() {
    if (!mounted) return;
    final languageRevision = _translationService.languageRevision;
    final showingOriginal =
        _translationService.showsOriginal(_translationScope);
    final languageChanged = languageRevision != _translationLanguageRevision;
    final modeChanged = showingOriginal != _translationShowsOriginal;
    if (!languageChanged && !modeChanged) return;
    if (languageChanged) unawaited(_refreshTargetLanguageLabel());

    setState(() {
      _translationLanguageRevision = languageRevision;
      _translationShowsOriginal = showingOriginal;
      // 방 번역 상태가 바뀌면 메시지 하나씩 켠 번역은 방 설정을 따른다.
      _singleTranslateIds.clear();
      _singleTranslateLoading.clear();
      if (languageChanged) {
        _translationStateGeneration++;
        // 스낵챗과 같이: 세대가 바뀌면 진행 중이던 준비 결과가 버려지므로
        // 준비를 다시 한다(그렇지 않으면 번역 버튼이 비활성으로 남는다).
        _translationModeReady = false;
        _translationMicroBatchTimer?.cancel();
        _translationMicroBatchTimer = null;
        _translationRetryTimer?.cancel();
        _translationRetryTimer = null;
        _messageTranslations.clear();
        _translationSourceSignatures.clear();
        _translationCacheLookupsInFlight.clear();
        _translationRequestsInFlight.clear();
        _translationCandidates.clear();
        _liveTranslationPriorityUntil.clear();
        _translationFailures.clear();
        _translationRetryAfter.clear();
        _deferredTranslationOutcomes.clear();
      } else if (showingOriginal) {
        // 이미 시작된 요청은 캐시에 저장되도록 두되 아직 서버 요청 전인
        // 후보는 제거하여 원문 보기 중 불필요한 비용이 생기지 않게 한다.
        _translationMicroBatchTimer?.cancel();
        _translationMicroBatchTimer = null;
        _translationCandidates.clear();
        _translationRequestsInFlight.removeAll(
          _deferredTranslationOutcomes.keys,
        );
        _deferredTranslationOutcomes.clear();
      }
    });
    if (languageChanged) {
      unawaited(_prepareTranslationMode());
    } else if (_translationModeReady && !showingOriginal) {
      _scheduleVisibleTranslations();
    }
  }

  bool _canTranslateMessage(DMMessage message) {
    final uid = _currentUser?.uid.trim() ?? '';
    final senderId = message.senderId.trim();
    if (uid.isEmpty || senderId.isEmpty || message.id.trim().isEmpty) {
      return false;
    }
    if (senderId == uid || message.type == 'system') return false;
    return hasTranslatableSnackChatText(message.text);
  }

  Map<String, String> _translationSourceFields(DMMessage message) =>
      message.text.trim().isEmpty
          ? const <String, String>{}
          : <String, String>{'text': message.text};

  String _translationSourceSignature(DMMessage message) {
    final fields = _translationSourceFields(message);
    final keys = fields.keys.toList(growable: false)..sort();
    return keys.map((key) {
      final value = fields[key]!;
      return '${key.length}:$key${value.length}:$value';
    }).join('|');
  }

  String _translationRequestKey(DMMessage message) =>
      '${message.id}\u0000${_translationSourceSignature(message)}';

  ContentTranslationRequest _translationRequestForMessage(
    DMMessage message, {
    String? conversationId,
  }) =>
      ContentTranslationRequest(
        contentType: 'dm',
        contentId: message.id,
        parentId: conversationId ?? _activeConversationId,
        sourceFields: _translationSourceFields(message),
      );

  bool _isCompleteTranslation(
    DMMessage message,
    ContentTranslationResult? result,
  ) {
    if (result == null || !result.isReady) return false;
    final fields = _translationSourceFields(message);
    if (fields.isEmpty) return false;
    return fields.entries.every(
      (entry) =>
          entry.value.trim().isEmpty ||
          (result.translatedFields[entry.key] ?? '').trim().isNotEmpty,
    );
  }

  ContentTranslationResult? _currentTranslation(DMMessage message) {
    if (!_canTranslateMessage(message)) return null;
    final signature = _translationSourceSignature(message);
    if (_translationSourceSignatures[message.id] == signature) {
      final local = _messageTranslations[message.id];
      if (_isCompleteTranslation(message, local)) return local;
    }
    final shared = _translationService.latestResultFor(
      _translationRequestForMessage(message),
    );
    return _isCompleteTranslation(message, shared) ? shared : null;
  }

  bool _isTranslationPending(DMMessage message) {
    if (!_canTranslateMessage(message) ||
        _translationShowsOriginal ||
        _currentTranslation(message) != null) {
      return false;
    }
    final key = _translationRequestKey(message);
    return _translationCacheLookupsInFlight.contains(key) ||
        _translationCandidates.containsKey(key) ||
        _deferredTranslationOutcomes.containsKey(key) ||
        _translationRequestsInFlight.contains(key);
  }

  Widget _buildDmTranslatedText(DMMessage message) {
    final result = _currentTranslation(message);
    final translatedText = (result?.translatedFields['text'] ?? '').trim();
    final canShowTranslation = (!_translationShowsOriginal ||
            _singleTranslateIds.contains(message.id)) &&
        result?.isReady == true &&
        result?.isSameLanguage != true &&
        translatedText.isNotEmpty;
    final pending = _isTranslationPending(message);
    final requestKey = _translationRequestKey(message);
    final failed = !_translationShowsOriginal &&
        result == null &&
        (_translationFailures[requestKey] ?? 0) >= 2 &&
        !pending;
    final presentationKey = canShowTranslation
        ? 'translated:${result!.sourceHash}:${result.targetLanguage}'
        : 'original:${_translationSourceSignature(message)}';

    // 스낵챗과 같은 표시: 같은 자리에서 원문/번역 교차 페이드, 번역 중에는 300ms 뒤
    // 원문이 옅게 깜빡이고, 발 줄은 상태(번역 중 / 원문 언어 / 다시 번역)만 알린다.
    final l10n = AppLocalizations.of(context)!;
    final style = chatMessageTextStyle(context, color: DMColors.otherMessageText);
    final state = result?.isSameLanguage == true || !_translationModeReady
        ? SnackChatTranslationState.none
        : canShowTranslation
            ? SnackChatTranslationState.translated
            : pending
                ? SnackChatTranslationState.pending
                : failed
                    ? SnackChatTranslationState.failed
                    : SnackChatTranslationState.none;
    return SnackChatTranslatedText(
      key: ValueKey<String>('dm-message-text:${message.id}'),
      state: state,
      presentationKey: presentationKey,
      original: _buildDmLinkifiedText(message.text, style),
      translated: canShowTranslation
          ? _buildDmLinkifiedText(translatedText, style)
          : null,
      sourceLanguageLabel: canShowTranslation
          ? translationSourceLanguageLabel(context, result!.sourceLanguage)
          : '',
      showTranslationLabel: '',
      showOriginalLabel: '',
      translatingLabel: l10n.chatTranslationTranslating,
      retryLabel: l10n.chatTranslationRetry,
      onRetry: failed ? () => _retryFailedDmTranslation(message) : null,
    );
  }

  Widget _buildDmLinkifiedText(String text, TextStyle style) =>
      ChatTextScope.body(
        context,
        child: Linkify(
          text: text,
          options: const linkify.LinkifyOptions(humanize: false),
          linkifiers: const [linkify.UrlLinkifier()],
          onOpen: (link) => _openDmUrl(link.url),
          style: style,
          linkStyle: style.copyWith(
            decoration: TextDecoration.underline,
            decorationColor: style.color,
          ),
        ),
      );

  Future<void> _openDmUrl(String rawUrl) async {
    final value = rawUrl.trim();
    final normalized = value.startsWith('www.') ? 'https://$value' : value;
    final uri = Uri.tryParse(normalized);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    try {
      var opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      if (!opened) throw StateError('URL launch was rejected.');
    } catch (_) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: isChineseUi(context)
            ? '无法打开链接。'
            : Localizations.localeOf(context).languageCode == 'ko'
                ? '링크를 열 수 없어요.'
                : 'Could not open the link.',
      );
    }
  }

  void _scheduleVisibleTranslations() {
    if (!mounted ||
        !_translationModeReady ||
        _translationShowsOriginal ||
        _activeConversationId.isEmpty ||
        _appLifecycleState != AppLifecycleState.resumed ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    if (_translationScanScheduled) return;
    _translationScanScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _translationScanScheduled = false;
      if (!mounted ||
          !_translationModeReady ||
          _translationShowsOriginal ||
          _appLifecycleState != AppLifecycleState.resumed ||
          !(ModalRoute.of(context)?.isCurrent ?? false)) {
        return;
      }
      unawaited(_primeVisibleTranslationCandidates());
    });
  }

  List<_DmTranslationCandidate> _translationCandidatesNearViewport({
    required int limit,
    bool includeQueued = false,
  }) {
    if (limit <= 0) return const <_DmTranslationCandidate>[];
    final viewportObject =
        _messageViewportKey.currentContext?.findRenderObject();
    final viewport = viewportObject is RenderBox && viewportObject.attached
        ? viewportObject
        : null;
    final viewportTop = viewport?.localToGlobal(Offset.zero).dy ?? 0;
    final viewportBottom = viewport == null
        ? MediaQuery.sizeOf(context).height
        : viewportTop + viewport.size.height;
    final viewportHeight = (viewportBottom - viewportTop).abs();
    final adjacentExtent = viewportHeight * 0.2;
    final viewportCenter = (viewportTop + viewportBottom) / 2;
    final now = DateTime.now();
    _liveTranslationPriorityUntil.removeWhere(
      (_, expiresAt) => !expiresAt.isAfter(now),
    );

    final candidates = <_DmTranslationCandidate>[];
    for (final message in _messages) {
      if (!_canTranslateMessage(message) ||
          _currentTranslation(message) != null) {
        continue;
      }
      final requestKey = _translationRequestKey(message);
      if (_translationRequestsInFlight.contains(requestKey) ||
          _translationCacheLookupsInFlight.contains(requestKey) ||
          _deferredTranslationOutcomes.containsKey(requestKey) ||
          (!includeQueued && _translationCandidates.containsKey(requestKey))) {
        continue;
      }
      final retryAfter = _translationRetryAfter[requestKey];
      if (retryAfter != null && retryAfter.isAfter(now)) continue;
      if ((_translationFailures[requestKey] ?? 0) >= 2) continue;

      final renderObject =
          _messageLayoutKeys[message.id]?.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final top = renderObject.localToGlobal(Offset.zero).dy;
      final bottom = top + renderObject.size.height;
      final visible = bottom > viewportTop && top < viewportBottom;
      final adjacent = bottom > viewportTop - adjacentExtent &&
          top < viewportBottom + adjacentExtent;
      if (!adjacent) continue;
      final live =
          _liveTranslationPriorityUntil[message.id]?.isAfter(now) == true;
      candidates.add(
        _DmTranslationCandidate(
          message: message,
          priority: live
              ? _DmTranslationPriority.live
              : visible
                  ? _DmTranslationPriority.visible
                  : _DmTranslationPriority.adjacent,
          distanceFromViewportCenter:
              (((top + bottom) / 2) - viewportCenter).abs(),
        ),
      );
    }
    candidates.sort((a, b) {
      final priority = a.priority.index.compareTo(b.priority.index);
      if (priority != 0) return priority;
      return a.distanceFromViewportCenter.compareTo(
        b.distanceFromViewportCenter,
      );
    });
    final selected = <_DmTranslationCandidate>[];
    var adjacentCount = 0;
    for (final candidate in candidates) {
      if (candidate.priority == _DmTranslationPriority.adjacent &&
          adjacentCount >= _translationAdjacentPrefetchLimit) {
        continue;
      }
      selected.add(candidate);
      if (candidate.priority == _DmTranslationPriority.adjacent) {
        adjacentCount++;
      }
      if (selected.length >= limit) break;
    }
    return selected;
  }

  Future<void> _primeVisibleTranslationCandidates() async {
    if (!_translationModeReady ||
        _translationShowsOriginal ||
        _appLifecycleState != AppLifecycleState.resumed ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    final available = 10 - _translationCacheLookupsInFlight.length;
    if (available <= 0) return;
    final candidates = _translationCandidatesNearViewport(limit: available);
    if (candidates.isEmpty) return;

    final generation = _translationStateGeneration;
    final revision = _translationLanguageRevision;
    final conversationId = _activeConversationId;
    final uiLanguage = Localizations.localeOf(context).languageCode;
    final keys = <String>{
      for (final candidate in candidates)
        _translationRequestKey(candidate.message),
    };
    setState(() => _translationCacheLookupsInFlight.addAll(keys));

    Map<String, ContentTranslationResult> cached;
    try {
      cached = await _translationService.cachedResultsFor(
        <ContentTranslationRequest>[
          for (final candidate in candidates)
            _translationRequestForMessage(
              candidate.message,
              conversationId: conversationId,
            ),
        ],
        uiLanguageCode: uiLanguage,
      );
    } catch (_) {
      cached = const <String, ContentTranslationResult>{};
    }
    if (!mounted ||
        generation != _translationStateGeneration ||
        revision != _translationLanguageRevision ||
        conversationId != _activeConversationId) {
      return;
    }

    setState(() {
      for (final candidate in candidates) {
        final original = candidate.message;
        final requestKey = _translationRequestKey(original);
        _translationCacheLookupsInFlight.remove(requestKey);
        final current = _messageById(original.id);
        if (current == null ||
            !_canTranslateMessage(current) ||
            _translationRequestKey(current) != requestKey) {
          continue;
        }
        final request = _translationRequestForMessage(
          current,
          conversationId: conversationId,
        );
        final result = cached[request.serverId];
        if (_isCompleteTranslation(current, result)) {
          if (_isUserScrolling) {
            _deferredTranslationOutcomes[requestKey] = _DmTranslationOutcome(
              message: current,
              requestKey: requestKey,
              result: result,
            );
          } else {
            _messageTranslations[current.id] = result!;
            _translationSourceSignatures[current.id] =
                _translationSourceSignature(current);
            _translationFailures.remove(requestKey);
            _translationRetryAfter.remove(requestKey);
            _liveTranslationPriorityUntil.remove(current.id);
          }
        } else if (!_translationShowsOriginal) {
          _translationCandidates[requestKey] = _DmTranslationCandidate(
            message: current,
            priority: candidate.priority,
            distanceFromViewportCenter: candidate.distanceFromViewportCenter,
          );
        }
      }
    });
    _scheduleTranslationMicroBatch();
  }

  DMMessage? _messageById(String id) {
    for (final message in _messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  void _scheduleTranslationMicroBatch() {
    if (_translationCandidates.isEmpty ||
        _translationMicroBatchTimer != null ||
        _translationShowsOriginal) {
      return;
    }
    _translationMicroBatchTimer = Timer(
      _translationMicroBatchWindow,
      _flushTranslationMicroBatch,
    );
  }

  Future<void> _flushTranslationMicroBatch() async {
    _translationMicroBatchTimer = null;
    if (!mounted ||
        !_translationModeReady ||
        _translationShowsOriginal ||
        _appLifecycleState != AppLifecycleState.resumed ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      _translationCandidates.clear();
      return;
    }

    // 빠른 스크롤 중 화면을 이미 벗어난 일반 후보는 API 단계 전에 버린다.
    // 새 실시간 메시지는 짧은 live 우선순위 동안만 예외로 유지한다.
    final stillNear = _translationCandidatesNearViewport(
      limit: 10,
      includeQueued: true,
    );
    final nearKeys = <String>{
      for (final candidate in stillNear)
        _translationRequestKey(candidate.message),
    };
    final now = DateTime.now();
    final selected = _translationCandidates.entries
        .where((entry) =>
            nearKeys.contains(entry.key) ||
            (entry.value.priority == _DmTranslationPriority.live &&
                _liveTranslationPriorityUntil[entry.value.message.id]
                        ?.isAfter(now) ==
                    true))
        .map((entry) => entry.value)
        .toList(growable: false)
      ..sort((a, b) {
        final priority = a.priority.index.compareTo(b.priority.index);
        if (priority != 0) return priority;
        return a.distanceFromViewportCenter.compareTo(
          b.distanceFromViewportCenter,
        );
      });
    _translationCandidates.clear();
    final messages = selected
        .take(_translationBatchSize)
        .map((candidate) => candidate.message)
        .toList(growable: false);
    if (messages.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    await _translateVisibleMessages(messages);
  }

  Future<void> _translateVisibleMessages(
    List<DMMessage> messages, {
    bool userInitiatedRetry = false,
    bool forceRefresh = false,
  }) async {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final generation = _translationStateGeneration;
    final revision = _translationLanguageRevision;
    final conversationId = _activeConversationId;
    final uiLanguage = Localizations.localeOf(context).languageCode;
    final eligible = messages.where((message) {
      final key = _translationRequestKey(message);
      return _canTranslateMessage(message) &&
          _currentTranslation(message) == null &&
          !_translationRequestsInFlight.contains(key);
    }).toList(growable: false);
    if (eligible.isEmpty) return;

    setState(() {
      for (final message in eligible) {
        _translationRequestsInFlight.add(_translationRequestKey(message));
      }
    });
    final outcomes = await Future.wait<_DmTranslationOutcome>(
      eligible.map((message) async {
        final key = _translationRequestKey(message);
        final failureCount = _translationFailures[key] ?? 0;
        ContentTranslationResult? result;
        try {
          result = await _translationService.request(
            _translationRequestForMessage(
              message,
              conversationId: conversationId,
            ),
            uiLanguageCode: uiLanguage,
            scope: _translationScope,
            manualRetry: failureCount > 0 || userInitiatedRetry,
            userInitiatedRetry: userInitiatedRetry,
            forceRefresh: forceRefresh,
          );
        } catch (_) {
          result = null;
        }
        return _DmTranslationOutcome(
          message: message,
          requestKey: key,
          result: result,
        );
      }),
    );
    if (!mounted ||
        generation != _translationStateGeneration ||
        revision != _translationLanguageRevision ||
        conversationId != _activeConversationId) {
      return;
    }

    if (_isUserScrolling && !_translationShowsOriginal) {
      setState(() {
        for (final outcome in outcomes) {
          _deferredTranslationOutcomes[outcome.requestKey] = outcome;
        }
      });
      return;
    }
    _commitDmTranslationOutcomes(outcomes);
  }

  void _commitDmTranslationOutcomes(List<_DmTranslationOutcome> outcomes) {
    if (!mounted || outcomes.isEmpty) return;
    final follow =
        !_scrollController.hasClients || _scrollController.offset <= 100;
    final anchor = follow ? null : _captureMessageAnchor();
    setState(() {
      for (final outcome in outcomes) {
        _translationRequestsInFlight.remove(outcome.requestKey);
        _translationCacheLookupsInFlight.remove(outcome.requestKey);
        final current = _messageById(outcome.message.id);
        if (current == null ||
            !_canTranslateMessage(current) ||
            _translationRequestKey(current) != outcome.requestKey) {
          _translationFailures.remove(outcome.requestKey);
          _translationRetryAfter.remove(outcome.requestKey);
          continue;
        }
        if (_isCompleteTranslation(current, outcome.result)) {
          _messageTranslations[current.id] = outcome.result!;
          _translationSourceSignatures[current.id] =
              _translationSourceSignature(current);
          _translationFailures.remove(outcome.requestKey);
          _translationRetryAfter.remove(outcome.requestKey);
          _liveTranslationPriorityUntil.remove(current.id);
        } else {
          final failures = (_translationFailures[outcome.requestKey] ?? 0) + 1;
          _translationFailures[outcome.requestKey] = failures;
          if (failures < 2 &&
              (outcome.result == null || outcome.result!.isTransientFailure)) {
            _translationRetryAfter[outcome.requestKey] = DateTime.now().add(
              const Duration(seconds: 15),
            );
          } else {
            _translationRetryAfter.remove(outcome.requestKey);
          }
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isUserScrolling) return;
      if (follow) {
        _followLatest(wasNearLatest: true);
      } else {
        _restoreMessageAnchor(anchor);
      }
    });
    _scheduleTranslationRetryScan();
    _scheduleVisibleTranslations();
  }

  void _commitDeferredDmTranslations() {
    if (!mounted || _isUserScrolling || _deferredTranslationOutcomes.isEmpty) {
      return;
    }
    final outcomes =
        _deferredTranslationOutcomes.values.toList(growable: false);
    _deferredTranslationOutcomes.clear();
    _commitDmTranslationOutcomes(outcomes);
  }

  void _retryFailedDmTranslation(DMMessage message) {
    if (!_translationModeReady ||
        _translationShowsOriginal ||
        !_canTranslateMessage(message) ||
        _currentTranslation(message) != null) {
      return;
    }
    final key = _translationRequestKey(message);
    // A deferred (uncommitted) outcome for this message is stale once the
    // user asks again; drop it so it cannot overwrite the fresh result.
    _deferredTranslationOutcomes.remove(key);
    if (_translationRequestsInFlight.contains(key) ||
        _translationCacheLookupsInFlight.contains(key)) {
      return;
    }
    _translationRetryAfter.remove(key);
    unawaited(
      _translateVisibleMessages(
        <DMMessage>[message],
        userInitiatedRetry: true,
        // Explicit tap: regenerate instead of replaying a cached failure.
        forceRefresh: true,
      ),
    );
  }

  void _scheduleTranslationRetryScan() {
    _translationRetryTimer?.cancel();
    _translationRetryTimer = null;
    if (_translationShowsOriginal || _translationRetryAfter.isEmpty) return;
    final now = DateTime.now();
    DateTime? next;
    for (final retryAt in _translationRetryAfter.values) {
      if (next == null || retryAt.isBefore(next)) next = retryAt;
    }
    if (next == null) return;
    final delay = next.difference(now);
    _translationRetryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        _translationRetryTimer = null;
        _scheduleVisibleTranslations();
      },
    );
  }

  void _markNewIncomingMessagesForTranslation(
    Iterable<DMMessage> messages,
  ) {
    final uid = _currentUser?.uid;
    if (uid == null) return;
    final expiresAt = DateTime.now().add(const Duration(seconds: 3));
    for (final message in messages) {
      if (message.senderId != uid && _canTranslateMessage(message)) {
        _liveTranslationPriorityUntil[message.id] = expiresAt;
      }
    }
  }

  /// 이 메시지의 언어가 내 번역 언어와 다르다고 이미 알려져 있는지(캐시·서버
  /// 감지 값만 본다. 알기 위해 새로 요청하지 않는다).
  bool _isKnownOtherLanguage(DMMessage message) {
    final known = _translationService
        .latestOutcomeFor(_translationRequestForMessage(message));
    if (known == null || known.isSameLanguage) return false;
    return known.sourceLanguage.trim().isNotEmpty || known.isReady;
  }

  bool _showsSingleTranslateButton(DMMessage message) =>
      TranslateHintFlags.singleMessageButton &&
      _translationModeReady &&
      _translationShowsOriginal &&
      !_singleTranslateIds.contains(message.id) &&
      _canTranslateMessage(message) &&
      _isKnownOtherLanguage(message);

  Future<void> _translateSingleMessage(DMMessage message) async {
    final id = message.id;
    final request = _translationRequestForMessage(message);
    final ready = _translationService.latestResultFor(request);
    setState(() {
      _singleTranslateIds.add(id);
      if (ready == null) _singleTranslateLoading.add(id);
    });
    if (ready != null) return;
    ContentTranslationResult? result;
    try {
      result = await _translationService.request(request);
    } catch (_) {
      result = null;
    }
    if (!mounted) return;
    setState(() {
      _singleTranslateLoading.remove(id);
      if (result == null || !result.isReady) _singleTranslateIds.remove(id);
    });
  }

  Future<void> _loadTranslateHintState() async {
    final dismissed = await TranslateHintStore.isDismissed(
      _currentUser?.uid ?? '',
      _activeConversationId,
    );
    if (mounted && dismissed != _translateHintDismissed) {
      setState(() => _translateHintDismissed = dismissed);
    }
  }

  void _dismissTranslateHint() {
    setState(() => _translateHintDismissed = true);
    unawaited(TranslateHintStore.dismiss(
      _currentUser?.uid ?? '',
      _activeConversationId,
    ));
  }

  Widget _buildTranslateFirstHint() {
    final show = TranslateHintFlags.firstHint &&
        !_translateHintDismissed &&
        _translationModeReady &&
        _translationShowsOriginal &&
        _messages.any((message) =>
            _canTranslateMessage(message) && _isKnownOtherLanguage(message));
    if (!show) return const SizedBox.shrink();
    final code = _targetLanguageCode;
    final language = code == null
        ? ''
        : ContentTranslationService.supportedLanguages[code] ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TranslateFirstHintBar(
        languageLabel: language,
        onTranslate: () {
          _dismissTranslateHint();
          unawaited(_toggleDmTranslation());
        },
        onDismiss: _dismissTranslateHint,
      ),
    );
  }

  Future<void> _toggleDmTranslation() async {
    if (!_translationModeReady || _activeConversationId.isEmpty) return;
    await _translationService.toggleDmConversation(_activeConversationId);
  }

  Future<void> _openDmTranslationLanguageSettings() async {
    if (_translationLanguageSheetOpen) return;
    _translationLanguageSheetOpen = true;
    try {
      final code =
          await showTranslationLanguageSheet(context, forSnackChat: true);
      // 언어를 고르면 꺼져 있던 대화 번역을 켠다.
      if (code != null && mounted && _translationShowsOriginal) {
        await _toggleDmTranslation();
      }
    } finally {
      _translationLanguageSheetOpen = false;
      _scheduleVisibleTranslations();
    }
  }

  void _ensureServerOtherUserInfo(String userId) {
    if (_serverOtherUserInfo != null) return;
    if (_serverOtherUserInfoFetchInFlight) return;
    _serverOtherUserInfoFetchInFlight = true;

    FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get(const GetOptions(source: Source.server))
        .then((doc) {
      if (!mounted) return;
      final data = doc.data();
      final status = (data?['status'] ?? '').toString().trim().toLowerCase();
      final isDeleted = !doc.exists ||
          data == null ||
          data['isDeleted'] == true ||
          data['deleted'] == true ||
          data['disabled'] == true ||
          data['isSuspended'] == true ||
          status == 'deleted' ||
          status == 'suspended';
      setState(() {
        _isOtherAccountDeleted = isDeleted;
        if (isDeleted) {
          _serverOtherUserInfo = null;
        } else {
          final nickname =
              (data['nickname'] ?? data['name'] ?? 'User').toString().trim();
          final photoVersionRaw = data['photoVersion'];
          _serverOtherUserInfo = DMUserInfo(
            uid: userId,
            nickname: nickname.isEmpty ? 'User' : nickname,
            photoURL: (data['photoURL'] ?? '').toString(),
            photoVersion: photoVersionRaw is int
                ? photoVersionRaw
                : int.tryParse('$photoVersionRaw') ?? 0,
            isFromCache: false,
          );
        }
      });
    }).catchError((Object error) {
      // 네트워크 오류를 탈퇴로 오판하지 않는다. 실제 전송 시
      // DMService가 서버 문서를 다시 확인한다.
      Logger.error('상대 프로필 서버 확인 실패: $error');
    }).whenComplete(() {
      _serverOtherUserInfoFetchInFlight = false;
    });
  }

  bool get _isPeerDeleted {
    if (_isAnonymous) return false;
    if (_isOtherAccountDeleted) return true;
    final status = _conversation?.participantStatus[widget.otherUserId];
    final name = _conversation?.getOtherUserName(_currentUser!.uid) ?? '';
    return status == 'deleted' || name == 'DELETED_ACCOUNT';
  }

  void _openOtherUserProfile({
    String? nickname,
    String? photoURL,
  }) {
    final userId = widget.otherUserId.trim();
    if (_isAnonymous || _isPeerDeleted || userId.isEmpty) return;

    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          userId: userId,
          nickname: nickname,
          photoURL: photoURL,
          allowNonFriendsPreview: true,
        ),
      ),
    );
  }

  /// 현재 대화 상대와 관련된 두 문서만 구독해 전체 목록 재조회와
  /// 메시지별 차단 조회를 피한다.
  void _watchBlockStatus() {
    final currentUid = _currentUser?.uid;
    if (currentUid == null || widget.otherUserId.trim().isEmpty) return;
    final blocks = FirebaseFirestore.instance.collection('blocks');
    _directBlockSubscription = blocks
        .doc('${currentUid}_${widget.otherUserId}')
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (mounted) {
        _applyBlockStatus(
          isBlocked: snapshot.exists,
          directServerConfirmed: !snapshot.metadata.isFromCache,
        );
      }
    }, onError: (Object error) {
      Logger.error('내 차단 상태 구독 실패: $error');
    });
    _reverseBlockSubscription = blocks
        .doc('${widget.otherUserId}_$currentUid')
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (mounted) {
        _applyBlockStatus(
          isBlockedBy: snapshot.exists,
          reverseServerConfirmed: !snapshot.metadata.isFromCache,
        );
      }
    }, onError: (Object error) {
      // 오프라인/권한 오류에서는 마지막으로 확인한 제한을 풀지 않는다.
      Logger.error('피차단 상태 구독 실패: $error');
    });
  }

  void _applyBlockStatus({
    bool? isBlocked,
    bool? isBlockedBy,
    bool directServerConfirmed = false,
    bool reverseServerConfirmed = false,
  }) {
    final nextBlocked = isBlocked ?? _isBlocked;
    final nextBlockedBy = isBlockedBy ?? _isBlockedBy;
    final nextDirectConfirmed =
        _directBlockStatusServerConfirmed || directServerConfirmed;
    final nextReverseConfirmed =
        _reverseBlockStatusServerConfirmed || reverseServerConfirmed;
    final becameRestricted =
        (nextBlocked || nextBlockedBy) && !(_isBlocked || _isBlockedBy);
    final becameReady =
        nextDirectConfirmed && nextReverseConfirmed && !_blockStatusReady;
    if (nextBlocked == _isBlocked &&
        nextBlockedBy == _isBlockedBy &&
        nextDirectConfirmed == _directBlockStatusServerConfirmed &&
        nextReverseConfirmed == _reverseBlockStatusServerConfirmed) {
      return;
    }
    setState(() {
      _isBlocked = nextBlocked;
      _isBlockedBy = nextBlockedBy;
      _directBlockStatusServerConfirmed = nextDirectConfirmed;
      _reverseBlockStatusServerConfirmed = nextReverseConfirmed;
    });
    if (becameRestricted) {
      _outboxRetry?.cancel();
      _outboxRetry = null;
      _markUncertainMessagesFailedByBlock();
      return;
    }
    if (becameReady && !_directInteractionRestricted) {
      final pending = _outgoing.values
          .where((message) =>
              message.deliveryState != DMDeliveryState.sent &&
              message.deliveryState != DMDeliveryState.failed)
          .toList()
        ..sort((a, b) => -_compareMessagesDesc(a, b));
      for (final message in pending) {
        _queueOutgoing(_activeConversationId, message, automatic: true);
      }
      _scheduleUncertainRecovery();
    }
  }

  void _markUncertainMessagesFailedByBlock() {
    final owner = _currentUser?.uid;
    final room = _activeConversationId;
    if (owner == null || room.isEmpty) return;
    final changed = <DMMessage>[];
    for (final entry in _outgoing.entries.toList()) {
      if (entry.value.deliveryState == DMDeliveryState.sent ||
          entry.value.deliveryState == DMDeliveryState.failed) continue;
      final failed =
          entry.value.copyWith(deliveryState: DMDeliveryState.failed);
      _outgoing[entry.key] = failed;
      final index = _messages.indexWhere((message) => message.id == entry.key);
      if (index >= 0) _messages[index] = failed;
      changed.add(failed);
    }
    if (changed.isNotEmpty && mounted) setState(() {});
    for (final message in changed) {
      unawaited(
        _outbox
            .put(owner, room, message.id, message.toLocalMap())
            .catchError((Object error) {
          Logger.error('차단 중 DM 대기 상태 저장 실패: $error');
        }),
      );
    }
  }

  String? _extractPostIdFromConversationId(String conversationId) {
    if (!conversationId.startsWith('anon_')) return null;
    final parts = conversationId.split('_');
    if (parts.length < 4) return null;
    var postId = parts.sublist(3).join('_');
    // __timestamp 형식의 접미사 제거
    if (postId.contains('__')) {
      postId = postId.split('__').first;
    }
    return postId.isEmpty ? null : postId;
  }

  /// 익명 게시글 DM이면 게시글 본문을 미리 로드 (AppBar에 즉시 표시)
  Future<void> _preloadPostContentIfAnonymous() async {
    final postId = _extractPostIdFromConversationId(widget.conversationId);
    if (postId == null) return;

    try {
      // 1) 로컬 캐시(SharedPreferences) 우선 - UX 개선 (즉시 표시)
      final prefs = await SharedPreferences.getInstance();
      final cached =
          (prefs.getString('$_anonTitlePrefsPrefix${widget.conversationId}') ??
                  '')
              .trim();
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _preloadedDmContent = cached;
        });
        return;
      }

      // 2) Firestore에서 게시글 본문 로드
      final postDoc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .get();
      final content =
          postDoc.exists ? (postDoc.data()?['content'] as String?) : null;
      if (!mounted) return;
      if (content != null && content.trim().isNotEmpty) {
        final normalized = content.trim();
        await prefs.setString(
            '$_anonTitlePrefsPrefix${widget.conversationId}', normalized);
        setState(() {
          _preloadedDmContent = normalized;
        });
      }
    } catch (e) {
      Logger.error('포스트 본문 미리 로드 실패: $e');
    }
  }

  /// 기존 대화방 문서에 dmContent가 없으면 게시글 본문으로 1회 백필
  Future<void> _ensureDmContentBackfilled({required String postId}) async {
    if (_backfilledPostId == postId) return;

    try {
      final postDoc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .get();
      final content =
          postDoc.exists ? (postDoc.data()?['content'] as String?) : null;
      final normalized = content?.trim() ?? '';
      if (normalized.isEmpty) {
        _backfilledPostId = postId; // 더 시도해도 의미 없으므로 가드
        return;
      }

      // UI용 프리로드도 갱신
      if (mounted) {
        setState(() {
          _preloadedDmContent = normalized;
        });
      }

      // 로컬 캐시 저장(다음 진입부터 즉시 표시)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            '$_anonTitlePrefsPrefix${widget.conversationId}', normalized);
      } catch (_) {}

      // 대화방 문서에 dmContent가 비어있을 때만 best-effort로 업데이트 (목록도 같이 정상화)
      final convRef = FirebaseFirestore.instance
          .collection('conversations')
          .doc(_activeConversationId);
      final convDoc = await convRef.get();
      if (convDoc.exists) {
        final data = convDoc.data() as Map<String, dynamic>;
        final existing = (data['dmContent'] as String?)?.trim() ?? '';
        if (existing.isEmpty) {
          try {
            await convRef.update({'dmContent': normalized});
          } catch (e) {
            // Rules 상 업데이트가 막혀도 UI는 게시글에서 직접 가져와 표시하면 됨
            Logger.error('dmContent 백필 업데이트 실패(무시): $e');
          }
        }
      }

      _backfilledPostId = postId;
    } catch (e) {
      Logger.error('dmContent 백필 실패(무시): $e');
      _backfilledPostId = postId;
    }
  }

  Future<void> _initConversationState() async {
    final room = _activeConversationId;
    final owner = _currentUser?.uid;
    final generation = _readGeneration;
    bool current() => mounted && generation == _readGeneration &&
        owner != null && _canSendFor(owner, room);
    try {
      if (mounted) {
        setState(() {
          _isConversationInitializing = true;
          _conversationExists = null;
        });
      }

      // Firebase Auth UID 형식 검증 (20~30자 영숫자, 언더스코어 포함 가능)
      final uidPattern = RegExp(r'^[a-zA-Z0-9_-]{20,30}$');
      if (!uidPattern.hasMatch(widget.otherUserId)) {
        if (Logger.isVerboseEnabled)
          Logger.log(
              '❌ 잘못된 userId 형식: ${widget.otherUserId} (길이: ${widget.otherUserId.length}자)');
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text((isChineseUi(context)
                  ? '无法向此用户发送消息'
                  : Localizations.localeOf(context).languageCode == 'ko'
                      ? '이 사용자에게는 메시지를 보낼 수 없습니다'
                      : 'Cannot send message to this user')),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // DM conversation ID 형식 검증 (타임스탬프 포함 형식도 지원)
      final validIdPattern = RegExp(
          r'^(anon_)?[a-zA-Z0-9_-]+_[a-zA-Z0-9_-]+(_[a-zA-Z0-9_-]+)?(_\d{13})?(__\d+)?$');
      if (!validIdPattern.hasMatch(_activeConversationId)) {
        if (Logger.isVerboseEnabled)
          Logger.log('❌ 잘못된 conversation ID 형식: $_activeConversationId');
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('${AppLocalizations.of(context)!.error}: 잘못된 대화방 ID입니다'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      final convRef = FirebaseFirestore.instance
          .collection('conversations')
          .doc(_activeConversationId);

      // 0) Firestore 로컬 캐시 우선으로 빠르게 존재 여부를 판단 (재진입 UX 개선)
      DocumentSnapshot<Map<String, dynamic>>? cachedConv;
      var conversationLoadStarted = false;
      try {
        cachedConv = await convRef.get(const GetOptions(source: Source.cache));
      } catch (_) {
        cachedConv = null;
      }
      if (!current()) return;

      if (cachedConv != null && cachedConv.exists) {
        _conversationExists = true;
        if (mounted) {
          setState(() {
            // 캐시에 존재하면 메시지/캐시 로딩을 바로 시작하고 스켈레톤을 빨리 해제한다.
            _isConversationInitializing = false;
          });
        }
        // 메시지/대화방 로딩은 백그라운드에서 진행 (UI 블로킹 방지)
        unawaited(
            _initializeMessagesStream(conversationId: _activeConversationId));
        unawaited(_loadConversation());
        conversationLoadStarted = true;
        _scheduleAutoMarkAsRead(
          _messages,
        );
      }

      // 1) 서버로 최종 확인 (권한/참여자 검증 포함). Bounded: offline with no
      // cached room previously left the skeleton up forever.
      final conv = await convRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
      if (!current()) return;

      _conversationExists = conv.exists;
      if (mounted) setState(() {});

      // 대화방이 존재하지 않으면 메시지 전송 시까지 대기
      if (_conversationExists == false) {
        // 본인 DM 체크
        if (widget.otherUserId == _currentUser?.uid) {
          if (Logger.isVerboseEnabled) Logger.log('❌ 본인 DM 생성 시도 차단');
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text((isChineseUi(context)
                    ? '不能给自己发消息'
                    : Localizations.localeOf(context).languageCode == 'ko'
                        ? '본인에게는 메시지를 보낼 수 없습니다'
                        : 'Cannot send message to yourself')),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }

        // 대화방이 없으면 생성하지 않고 대기 상태로 설정
      }

      // 참여자 확인 (대화방이 이미 존재했던 경우에만)
      if (_conversationExists == true && conv.exists) {
        final data = conv.data() as Map<String, dynamic>;
        final participants = List<String>.from(data['participants'] ?? []);

        // 본인이 본인에게 보낸 DM 체크
        final isSelfDM = participants.length == 2 &&
            participants[0] == _currentUser?.uid &&
            participants[1] == _currentUser?.uid;

        if (isSelfDM) {
          if (Logger.isVerboseEnabled) Logger.log('❌ 본인 DM은 허용되지 않음');
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text((isChineseUi(context)
                    ? '不能给自己发消息'
                    : Localizations.localeOf(context).languageCode == 'ko'
                        ? '본인에게는 메시지를 보낼 수 없습니다'
                        : 'Cannot send message to yourself')),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }

        if (!participants.contains(_currentUser?.uid)) {
          if (Logger.isVerboseEnabled) Logger.log('❌ 대화방 참여자가 아님');
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    '${AppLocalizations.of(context)!.error}: 대화방 참여자가 아닙니다'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }
      }

      // 대화방이 존재하면 정상 진행
      if (_conversationExists == true) {
        // 이미 캐시 경로에서 시작했을 수 있으므로, 중복 구독/중복 로딩을 피하기 위해
        // 메시지 스트림이 아직 없다면 시작한다.
        if (_recentMessagesSub == null) {
          unawaited(
              _initializeMessagesStream(conversationId: _activeConversationId));
        }
        // The cache branch already fetched the conversation (server-first
        // get); a second identical read only adds a round trip.
        if (!conversationLoadStarted) unawaited(_loadConversation());
        _scheduleAutoMarkAsRead(
          _messages,
        );
      }
    } catch (e) {
      Logger.error('대화 초기화 오류: $e');
      if (!current()) return;
      Logger.error('오류 상세: ${e.runtimeType} - ${e.toString()}');
      // Not reachable (offline/timeout) and nothing cached: surface the error
      // with a retry instead of an endless skeleton.
      if (_conversationExists == null &&
          _messages.isEmpty &&
          !e.toString().contains('permission-denied') &&
          mounted) {
        setState(() => _messagesError = e);
      }
      // 권한 오류인 경우 뒤로가기
      if (e.toString().contains('permission-denied')) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('${AppLocalizations.of(context)!.error}: 접근 권한이 없습니다'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } finally {
      if (current()) {
        setState(() {
          _isConversationInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    NavigationService.routeObserver.unsubscribe(this);
    _messageGeneration++;
    _messageReconnect?.cancel();
    _outboxRetry?.cancel();
    unawaited(_directBlockSubscription?.cancel());
    unawaited(_reverseBlockSubscription?.cancel());
    // PopScope를 거치지 않고 라우트가 제거되는 경우에도 백그라운드 읽음
    // 동기화를 시작한다. 이 Future는 화면 생명주기와 독립적으로 완료된다.
    _startBackgroundReadFlush();
    // Keep the existing account guard alive only until the frozen exit request
    // finishes, including logout/relogin while its response is delayed.
    final exitRead = _exitReadOperation;
    if (exitRead == null) {
      unawaited(_accountSubscription?.cancel());
    } else {
      unawaited(exitRead.whenComplete(() => _accountSubscription?.cancel()));
    }
    _readGeneration++;
    // ✅ 현재 화면이 활성 대화방이면 해제
    if (DMActiveConversation.isActive(_activeConversationId)) {
      DMActiveConversation.setActive(null);
    }
    _autoMarkReadDebounce?.cancel();
    _translationMicroBatchTimer?.cancel();
    _translationRetryTimer?.cancel();
    _translationService.removeListener(_handleTranslationServiceChange);
    WidgetsBinding.instance.removeObserver(this);
    _conversationReadSub?.cancel();
    _recentMessagesSub?.cancel();
    _reactionSubscriptionGeneration++;
    _reactionSub?.cancel();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleAutoMarkAsRead(
    List<DMMessage> messages,
  ) {
    if (!mounted) return;
    if (_appLifecycleState != AppLifecycleState.resumed ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    final me = _currentUser;
    if (me == null) return;
    if (_isLeaving || _accountInvalidated || _exitReadFlushStarted ||
        !_canSendFor(me.uid, _activeConversationId)) return;
    _reconcileConversationNotifications(messages, me.uid);
    DMMessage? target;
    for (final message in messages) {
      if (message.senderId == me.uid || message.deliveryState != DMDeliveryState.sent ||
          message.isReadThrough(_confirmedReadThrough,
              watermarkMessage: _confirmedReadTargetMessage) ||
          _confirmedLegacyReadIds.contains(message.id)) continue;
      // Newest by canonical list order. A message whose receiptCreatedAt has
      // not been written by the trigger yet is still a valid boundary: the
      // server resolves its createTime from the document itself.
      if (target == null || DMMessage.compareDescending(message, target) < 0) {
        target = message;
      }
    }
    if (target == null) return;
    _pendingReadTarget = target;
    if (_autoMarkReadInFlight) return;
    _autoMarkReadDebounce?.cancel();
    unawaited(_performAutoMarkAsRead());
  }

  int _notificationReconcileMillis = 0;

  /// Newest incoming message on screen → every OS card for this conversation
  /// is covered. Remove them and recount the badge from the server, without
  /// depending on the read callable (which is skipped when the watermark is
  /// already current, e.g. after reading on another device).
  void _reconcileConversationNotifications(
    List<DMMessage> messages,
    String owner,
  ) {
    var latest = 0;
    for (final message in messages) {
      if (message.senderId == owner ||
          message.deliveryState != DMDeliveryState.sent) continue;
      final millis = message.serverCreatedAt?.millisecondsSinceEpoch ??
          message.createdAt.millisecondsSinceEpoch;
      if (millis > latest) latest = millis;
    }
    if (latest <= 0 || latest <= _notificationReconcileMillis) return;
    _notificationReconcileMillis = latest;
    final conversationId = _activeConversationId;
    if (conversationId.isEmpty) return;
    unawaited(FCMService()
        .cancelDmNotification(
          conversationId,
          throughSentAtMillis: latest,
          coversLatestVisible: true,
          expectedOwner: owner,
        )
        .catchError((Object error) {
      Logger.error('DM 화면 기준 알림 정리 실패', error);
    }));
    unawaited(BadgeService.refreshNow(fresh: true).catchError((Object error) {
      Logger.error('DM 화면 기준 배지 갱신 실패', error);
    }));
  }

  Future<void> _performAutoMarkAsRead() async {
    if (!mounted || _autoMarkReadInFlight || _isLeaving) return;
    final target = _pendingReadTarget;
    final owner = _currentUser?.uid;
    if (target == null || owner == null) return;
    final generation = _readGeneration;
    _autoMarkReadInFlight = true;
    _inFlightReadTargetId = target.id;
    if (Logger.isVerboseEnabled)
      Logger.log(
          '📖 [markAsRead] 실행 - conversationId: $_activeConversationId (즉시 트리거)');
    final conversationId = _activeConversationId;
    final operation = () async {
      final result = await _dmService.markAsRead(conversationId,
          throughMessageId: target.id, expectedUserId: owner);
      _scheduleDmReadPostProcessing(conversationId, result, owner);
      if (generation != _readGeneration || !mounted ||
          !_canSendFor(owner, conversationId)) return;
      // Prefer the exact boundary the server confirmed (seconds + nanos); the
      // target's receiptCreatedAt may not have been written yet.
      final confirmed = result.readThroughAtSeconds > 0
          ? Timestamp(result.readThroughAtSeconds, result.readThroughAtNanos)
          : target.receiptCreatedAt;
      if (confirmed != null && (_confirmedReadThrough == null ||
          confirmed.compareTo(_confirmedReadThrough!) > 0)) {
        _confirmedReadThrough = confirmed;
      }
      final previousTarget = _confirmedReadTargetMessage;
      if (previousTarget == null ||
          DMMessage.compareDescending(target, previousTarget) < 0) {
        _confirmedReadTargetMessage = target;
      }
      _confirmedLegacyReadIds.add(target.id);
      if (_pendingReadTarget?.id == target.id) _pendingReadTarget = null;
    }();
    _autoMarkReadOperation = operation;
    try {
      await operation;
      if (generation != _readGeneration) return;
      _autoMarkReadRetryAttempt = 0;
      if (Logger.isVerboseEnabled)
        Logger.log('✅ [markAsRead] 완료 - conversationId: $conversationId');
    } catch (e) {
      if (generation != _readGeneration || !mounted) return;
      Logger.error('❌ [markAsRead] 실패: $e');
      _autoMarkReadRetryAttempt =
          (_autoMarkReadRetryAttempt + 1).clamp(1, 5).toInt();
      final retrySeconds =
          (1 << _autoMarkReadRetryAttempt).clamp(2, 30).toInt();
      _autoMarkReadDebounce?.cancel();
      _autoMarkReadDebounce = Timer(
        Duration(seconds: retrySeconds),
        () => _scheduleAutoMarkAsRead(
          _messages,
        ),
      );
    } finally {
      if (generation == _readGeneration) {
        if (identical(_autoMarkReadOperation, operation)) {
          _autoMarkReadOperation = null;
          _inFlightReadTargetId = null;
        }
        _autoMarkReadInFlight = false;
        if (_autoMarkReadRetryAttempt == 0) {
          _scheduleAutoMarkAsRead(_messages);
        }
      }
    }
  }

  void _scheduleDmReadPostProcessing(
    String conversationId,
    DMReadResult result,
    String owner,
  ) {
    if (_accountInvalidated || FirebaseAuth.instance.currentUser?.uid != owner) return;
    unawaited(
      BadgeService.refreshNow(fresh: true).catchError(
        (Object error) => Logger.error('DM 읽음 배지 갱신 실패', error),
      ),
    );
    if (result.readThroughAtMillis > 0) {
      unawaited(
        FCMService()
            .cancelDmNotification(
              conversationId,
              throughSentAtMillis: result.readThroughAtMillis,
              throughSeconds: result.readThroughAtSeconds,
              throughNanos: result.readThroughAtNanos,
              expectedOwner: owner,
            )
            .catchError(
              (Object error) => Logger.error('DM 읽음 알림 정리 실패', error),
            ),
      );
    }
  }

  /// 대화방 정보 로드
  Future<void> _loadConversation() async {
    final room = _activeConversationId;
    final generation = _readGeneration;
    final owner = _currentUser?.uid;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(room)
          .get();

      if (doc.exists && mounted && generation == _readGeneration &&
          owner != null && _canSendFor(owner, room)) {
        setState(() {
          _conversation = Conversation.fromFirestore(doc);
        });

        // 익명 게시글 DM의 경우: dmContent가 없으면 게시글에서 본문을 가져와 1회 백필
        final conv = _conversation;
        if (conv != null &&
            conv.postId != null &&
            conv.postId!.isNotEmpty &&
            conv.isOtherUserAnonymous(_currentUser!.uid)) {
          final existingContent = (conv.dmContent ?? '').trim();
          if (existingContent.isEmpty) {
            await _ensureDmContentBackfilled(postId: conv.postId!);
          } else if (_preloadedDmContent == null ||
              _preloadedDmContent!.isEmpty) {
            // 이미 dmContent가 있으면 프리로드에도 반영
            if (mounted) {
              setState(() {
                _preloadedDmContent = existingContent;
              });
            }
          }
        }
      }
    } catch (e) {
      Logger.error('대화방 정보 로드 오류: $e');
    }
  }

  /// Fast-entry follow-up: fetch the server-owned leave boundary and, when it
  /// differs from the one already in use, resubscribe with the authoritative
  /// value. A later boundary (a leave performed on another device) hides the
  /// older rows; an earlier or absent one reveals history that the hint hid.
  Future<void> _reconcileVisibilityBoundary(
      String room, int generation, DateTime? used) async {
    try {
      final server = await _dmService.getUserMessageVisibilityStartTime(room);
      if (!mounted ||
          generation != _messageGeneration ||
          room != _activeConversationId) {
        return;
      }
      if (server == used) return;
      _visibilityStartTime = server;
      if (server != null && mounted) {
        setState(() {
          _messages = _messages.where((message) {
            final committed = message.serverCreatedAt;
            // Local pending packets stay; only committed rows older than the
            // server boundary are hidden.
            return committed == null || !committed.toDate().isBefore(server);
          }).toList();
        });
      }
      // Resubscribes with _visibilityStartTime already set, so the nested
      // reconcile sees an equal boundary and stops.
      unawaited(_initializeMessagesStream(conversationId: room));
    } catch (error) {
      Logger.error('DM 가시성 경계 재확인 실패', error);
    }
  }

  /// 메시지 스트림 초기화
  /// - 기본: 전체 대화 표시(일반 진입)
  /// - 예외: 사용자가 실제로 '채팅방 나가기'를 한 기록이 있으면, 그 시점 이후만 표시
  Future<void> _initializeMessagesStream({String? conversationId}) async {
    final room = conversationId ?? _activeConversationId;
    final owner = _currentUser?.uid;
    if (owner == null || !_canSendFor(owner, room)) return;
    if (_recentMessagesSub != null && _messagesError == null) return;
    final generation = ++_messageGeneration;
    bool current() =>
        mounted && generation == _messageGeneration && _canSendFor(owner, room);
    _messageReconnect?.cancel();
    final previous = _recentMessagesSub;
    _recentMessagesSub = null;
    await previous?.cancel();
    try {
      DateTime? visibility;
      if (DMService.fastEntryEnabled) {
        // Fast entry: cached history and the live listener start with the
        // best-known boundary (previous resolution or the local cache hint).
        // The server-only boundary is reconciled below without blocking the
        // first paint; a later server boundary drops the older rows again.
        visibility = _visibilityStartTime ??
            await _dmService.getCachedVisibilityStartTime(room);
        if (!current()) return;
        unawaited(_reconcileVisibilityBoundary(room, generation, visibility));
      } else {
        visibility = await _dmService.getUserMessageVisibilityStartTime(room);
        if (!current()) return;
      }
      _visibilityStartTime = visibility;
      unawaited(_restoreOutbox(room));
      // Start cache read and live subscription together. Live objects win every
      // overlap, including a snapshot received while Hive is still opening.
      if (_hydratedFromLocalCacheConversationIds.add(room)) {
        unawaited(_dmService
            .loadCachedMessages(room,
                limit: _initialCacheLimit, visibilityStartTime: visibility)
            .then((cached) {
          if (!current() || cached.isEmpty || _receivedInitialMessageSnapshot)
            return;
          setState(() => _messages = _mergeRecentIntoAll(_messages, cached));
          _scheduleVisibleTranslations();
        }));
      }
      _isMessagesLoading = _messages.isEmpty;
      void retry(Object? error) {
        if (!current()) return;
        final old = _recentMessagesSub;
        _recentMessagesSub = null;
        unawaited(old?.cancel());
        setState(() {
          _messagesError = error;
          _isMessagesLoading = false;
        });
        final permission =
            error is FirebaseException && error.code == 'permission-denied';
        if (!permission) {
          _messageReconnect?.cancel();
          _messageReconnect = Timer(const Duration(seconds: 2), () {
            if (current())
              unawaited(_initializeMessagesStream(conversationId: room));
          });
        }
      }

      _recentMessagesSub = _dmService
          .watchRecentMessagesAndCache(room,
              limit: _recentLimit, visibilityStartTime: visibility)
          .listen((recent) {
        if (!current()) return;
        final watch = Stopwatch()..start();
        final follow =
            !_scrollController.hasClients || _scrollController.offset <= 100;
        final anchor = follow ? null : _captureMessageAnchor();
        final known = _messages.map((m) => m.id).toSet();
        final incoming = _receivedInitialMessageSnapshot
            ? recent.where((m) => !known.contains(m.id)).toList()
            : <DMMessage>[];
        final previousById = {for (final message in _messages) message.id: message};
        final layoutChanged = !_receivedInitialMessageSnapshot || recent.any((m) {
          final old = previousById[m.id];
          return old == null || old.createdAt != m.createdAt ||
              old.deliveryState != m.deliveryState || old.text != m.text ||
              old.imageUrl != m.imageUrl ||
              !mapEquals(old.reactionCounts, m.reactionCounts);
        });
        for (final message in recent) {
          if (message.deliveryState == DMDeliveryState.sent &&
              _outgoing.remove(message.id) != null) {
            _outboxRetryAttempts.remove(message.id);
            unawaited(
                _outbox.remove(owner, room, message.id).catchError((Object e) {
              Logger.error('DM outbox acknowledgement persistence failed: $e');
            }));
          }
        }
        setState(() {
          _messages = _mergeRecentIntoAll(recent, _messages);
          _messagesError = null;
          _isMessagesLoading = false;
          _receivedInitialMessageSnapshot = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!current()) return;
          if (!layoutChanged) return;
          if (follow) {
            _followLatest(wasNearLatest: true);
          } else {
            _restoreMessageAnchor(anchor);
          }
          if (ChatTiming.enabled)
            ChatTiming.record(
                '[DMChatTiming] stage=receiverFrame roomId=$room durationMs=${watch.elapsedMilliseconds}');
        });
        if (layoutChanged) {
          _markNewIncomingMessagesForTranslation(incoming);
          _scheduleVisibleTranslations();
        }
        _scheduleAutoMarkAsRead(_messages);
      }, onError: (Object error) => retry(error), onDone: () => retry(null));
    } catch (error) {
      if (!current()) return;
      setState(() {
        _messagesError = error;
        _isMessagesLoading = false;
      });
      _messageReconnect = Timer(const Duration(seconds: 2), () {
        if (current())
          unawaited(_initializeMessagesStream(conversationId: room));
      });
    }
  }

  int _compareMessagesDesc(DMMessage a, DMMessage b) =>
      DMMessage.compareDescending(a, b);

  List<DMMessage> _mergeRecentIntoAll(
      List<DMMessage> recent, List<DMMessage> existingAll) {
    final existingById = <String, DMMessage>{
      for (final message in existingAll) message.id: message,
    };
    final incoming = {
      for (final message in recent)
        message.id: (_reactionMutationsInFlight.contains(message.id) ||
                _pendingReactionTargets.containsKey(message.id))
            ? message.copyWith(
                reactionCounts: existingById[message.id]?.reactionCounts ??
                    message.reactionCounts,
              )
            : message,
    }.values.toList()
      .map((message) => message.preserveConfirmedReceipt(existingById[message.id]))
      .toList()
      ..sort(_compareMessagesDesc);
    final ids = incoming.map((m) => m.id).toSet();
    final retained = existingAll.where((m) => !ids.contains(m.id)).toList();
    final merged = <DMMessage>[];
    var a = 0;
    var b = 0;
    while (a < incoming.length && b < retained.length) {
      merged.add(_compareMessagesDesc(incoming[a], retained[b]) <= 0
          ? incoming[a++]
          : retained[b++]);
    }
    merged.addAll(incoming.skip(a));
    merged.addAll(retained.skip(b));
    // 메모리 상한: 너무 오래 열어두거나 과거를 많이 불러와도 과도한 메모리 사용을 방지
    const int hardCap = 800;
    if (merged.length > hardCap) {
      return [
        ...merged.take(hardCap),
        ...merged
            .skip(hardCap)
            .where((message) => message.deliveryState != DMDeliveryState.sent),
      ];
    }
    return merged;
  }

  void _onScroll() {
    if (!mounted) return;

    // 번역 가시성 판정은 스크롤 종료를 기다리지 않는다. 기존 페이지 로드
    // 조건과 독립적으로 현재 배치된 말풍선만 다음 프레임에 확인한다.
    _scheduleVisibleTranslations();

    if (_conversationExists != true) return;
    if (_isLoadingMore) return;
    if (!_hasMore) return;
    if (_isConversationInitializing) return;
    if (_messages.isEmpty) return;
    if (!_scrollController.hasClients) return;

    // reverse=true에서 "더 과거(위)"로 스크롤할수록 pixels가 maxScrollExtent에 가까워진다.
    const threshold = 240.0;
    final pos = _scrollController.position;
    // ✅ 중요: 초기 attach/레이아웃 단계에서 maxScrollExtent가 0인 경우,
    // pos.pixels(대개 0)가 조건을 만족해 자동으로 과거 페이지를 연쇄 로드할 수 있다.
    // "사용자가 실제로 스크롤했을 때만" 과거 로드를 트리거한다.
    if (pos.maxScrollExtent <= 0) return;
    if (pos.userScrollDirection == ScrollDirection.idle) return;

    if (pos.pixels >= (pos.maxScrollExtent - threshold)) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (!mounted) return;
    if (_conversationExists != true) return;
    if (_isLoadingMore) return;
    if (!_hasMore) return;
    if (_messages.isEmpty) return;

    setState(() {
      _isLoadingMore = true;
    });

    final room = _activeConversationId;
    final generation = _messageGeneration;
    try {
      final cursor = _messages.last;
      final before = cursor.createdAt; // 가장 오래된 메시지보다 더 과거를 로드
      final older = await _dmService.fetchOlderMessages(
        _activeConversationId,
        before: before,
        beforeId: cursor.id,
        beforeTimestamp: cursor.serverCreatedAt,
        limit: _pageSize,
        visibilityStartTime: _visibilityStartTime,
      );

      if (!mounted) return;

      if (room != _activeConversationId ||
          generation != _messageGeneration ||
          _accountInvalidated) return;

      if (older.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoadingMore = false;
        });
        return;
      }

      setState(() {
        _messages = _mergeRecentIntoAll(older, _messages);
        _isLoadingMore = false;
        if (older.length < _pageSize) {
          _hasMore = false;
        }
      });
      _scheduleVisibleTranslations();
      _scheduleAutoMarkAsRead(_messages);
    } catch (e) {
      Logger.error('이전 메시지 로드 실패(무시): $e');
      if (!mounted || room != _activeConversationId ||
          generation != _messageGeneration || _accountInvalidated) return;
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  Widget _buildLoadMoreIndicator() {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    // 버튼은 제거하고(요청사항), 스크롤 자동 로드만 사용한다.
    return const SizedBox.shrink();
  }

  void _startBackgroundReadFlush() {
    if (_activeConversationId.isEmpty || _isLeaving || _exitReadFlushStarted) {
      return;
    }
    _exitReadFlushStarted = true;
    _autoMarkReadDebounce?.cancel();
    final conversationId = _activeConversationId;
    final owner = _currentUser?.uid;
    final target = _pendingReadTarget;
    if (owner == null || target == null || _accountInvalidated) return;
    final pending = _autoMarkReadOperation;
    final inFlightTargetId = _inFlightReadTargetId;

    _exitReadOperation = (() async {
        if (pending != null) {
          try {
            await pending;
            if (inFlightTargetId == target.id) return;
          } catch (_) {
            // Only a failed request needs another attempt at the same boundary.
          }
        }

        if (_accountInvalidated || FirebaseAuth.instance.currentUser?.uid != owner ||
            _confirmedLegacyReadIds.contains(target.id)) return;
        // Freeze the observed boundary before route disposal, never server now.
        final result = await _dmService
            .markAsRead(conversationId,
                throughMessageId: target.id, expectedUserId: owner)
            .timeout(const Duration(seconds: 12));
        _scheduleDmReadPostProcessing(conversationId, result, owner);
      })()
          .catchError((Object error) {
        Logger.error('❌ [DM 읽음] 화면 종료 동기화 실패: $error');
      });
    unawaited(_exitReadOperation);
  }

  Widget _readAwareRoute({required Widget child}) {
    return PopScope<Object?>(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _startBackgroundReadFlush();
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 화면 글자는 1.3배까지, 메시지 본문만 1.6배까지(ChatTextScope).
    return ChatTextScope(
      child: Builder(builder: _buildDmScreen),
    );
  }

  Widget _buildDmScreen(BuildContext context) {
    if (_currentUser == null) {
      return _readAwareRoute(
        child: Scaffold(
          appBar: AppBar(title: Text(AppLocalizations.of(context)!.dm)),
          body: Center(
            child: Text(AppLocalizations.of(context)!.loginRequired),
          ),
        ),
      );
    }

    return _readAwareRoute(
      child: Scaffold(
        backgroundColor: DMColors.pageBg,
        appBar: _buildAppBar(),
        body: Column(
          children: [
            // 익명 게시글 DM인 경우에만 게시글로 돌아가기 배너 추가
            if (_conversation != null &&
                _conversation!.postId != null &&
                _conversation!.postId!.isNotEmpty &&
                _conversation!.isOtherUserAnonymous(_currentUser.uid))
              _buildPostNavigationBanner(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: KeyedSubtree(
                      key: _messageViewportKey,
                      child: _buildMessageList(),
                    ),
                  ),
                ],
              ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  /// 스낵챗과 같은 [文A | 언어 ⌄] 분할 버튼(상단 바). 대화가 있을 때만 보인다.
  List<Widget> _buildDmTranslationActions() {
    if (!(_conversationExists == true || _messages.isNotEmpty)) {
      return const <Widget>[];
    }
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final zh = isChineseUi(context);
    final translationOn = !_translationShowsOriginal;
    final code = _targetLanguageCode;
    return <Widget>[
      SnackChatTranslationSplitButton(
        translationOn: translationOn,
        enabled: _translationModeReady,
        // 번역을 켠 뒤 첫 요청이 진행 중이고 아직 번역된 메시지가 없을 때.
        busy: translationOn &&
            _translationRequestsInFlight.isNotEmpty &&
            _messageTranslations.isEmpty,
        languageLabel: code == null
            ? ''
            : ContentTranslationService.supportedLanguages[code] ?? '',
        toggleSemanticLabel: translationOn
            ? (zh ? '查看原文' : (isKo ? '원문 보기' : 'View original'))
            : (zh ? '查看译文' : (isKo ? '번역 보기' : 'View translation')),
        languageSemanticLabel:
            zh ? '翻译语言' : (isKo ? '번역 언어 설정' : 'Translation language'),
        onToggle: _toggleDmTranslation,
        onOpenLanguage: _openDmTranslationLanguageSettings,
        toggleKey: const ValueKey('dm_translation_toggle'),
        languageKey: const ValueKey('dm_translation_language_settings'),
        languageMaxWidth: 96,
      ),
    ];
  }

  /// 상단 바 언어 이름. targetLanguage는 비동기라 state에 보관한다.
  Future<void> _refreshTargetLanguageLabel() async {
    final revision = _translationService.languageRevision;
    final code = await _translationService.targetLanguage(
      uiLanguageCode: Localizations.localeOf(context).languageCode,
    );
    if (!mounted || revision != _translationService.languageRevision) return;
    if (code != _targetLanguageCode) setState(() => _targetLanguageCode = code);
  }

  bool get _isAnonymous {
    return _activeConversationId.startsWith('anon_') ||
        (_conversation?.isOtherUserAnonymous(_currentUser!.uid) ?? false);
  }

  /// AppBar 빌드
  static const double _dmToolbarHeight = ChatMetrics.headerHeight;

  /// 세 갈래(로딩·익명 게시글·일반)가 함께 쓰는 상단바 틀.
  /// 높이 52, 흰색, 아래 1px #EBEBEB, 그림자 없음.
  AppBar _buildDmAppBar({
    required Widget identity,
    required List<Widget> actions,
  }) {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      scrolledUnderElevation: 0,
      toolbarHeight: _dmToolbarHeight,
      titleSpacing: 0,
      shape: const Border(bottom: BorderSide(color: Color(0xFFEBEBEB))),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black87),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 48),
        onPressed: () => Navigator.pop(context),
      ),
      title: identity,
      actions: actions,
    );
  }

  String _formatHeaderDate() {
    final date = _conversation?.lastMessageTime ?? _conversation?.createdAt;
    if (date == null) return '';
    return DateFormat('yyyy.MM.dd').format(date);
  }

  PreferredSizeWidget _buildAppBar() {
    final otherUserId = widget.otherUserId;
    final dmContent = (_conversation?.dmContent ?? _preloadedDmContent)?.trim();
    final postId = _conversation?.postId ??
        _extractPostIdFromConversationId(_activeConversationId);
    final isPostBasedAnonymous =
        _isAnonymous && (postId != null && postId.isNotEmpty);

    // ⏳ 로딩 상태: 데이터가 준비되지 않았을 때
    if (_conversation == null && (dmContent == null || dmContent.isEmpty)) {
      final l10n = AppLocalizations.of(context)!;
      final resolvedName = _isAnonymous
          ? (l10n.anonymous ?? 'Anonymous')
          : (_serverOtherUserInfo?.nickname ?? '');
      final resolvedPhotoUrl =
          _isAnonymous ? '' : (_serverOtherUserInfo?.photoURL ?? '');
      final resolvedPhotoVersion =
          _isAnonymous ? 0 : (_serverOtherUserInfo?.photoVersion ?? 0);

      // 대화방이 없어도 상대 프로필을 먼저 보여준다(오류 오해 방지)
      return _buildDmAppBar(
        identity: DmHeaderIdentity(
          avatar: UserAvatar(
            uid: otherUserId,
            photoUrl: resolvedPhotoUrl,
            photoVersion: resolvedPhotoVersion,
            isAnonymous: _isAnonymous,
            size: 36,
            placeholderColor: const Color(0xFFE5E7EB),
            placeholderIconSize: 20,
          ),
          title: resolvedName.trim(),
          subtitle: null,
          showSkeleton: resolvedName.trim().isEmpty,
          semanticsLabel: AppLocalizations.of(context)!.viewProfile,
          onTap: _isAnonymous || _isPeerDeleted
              ? null
              : () => _openOtherUserProfile(
                    nickname: resolvedName,
                    photoURL: resolvedPhotoUrl,
                  ),
        ),
        actions: _buildDmTranslationActions(),
      );
    }

    // 🎯 익명 게시글 DM: AppBar 제목을 "게시글 본문"으로 표시
    if (isPostBasedAnonymous) {
      final primaryTitle = (dmContent != null && dmContent.isNotEmpty)
          ? dmContent
          : AppLocalizations.of(context)!.anonymous;
      final secondaryTitle = AppLocalizations.of(context)!.anonymous;
      final headerDate = _formatHeaderDate();

      return _buildDmAppBar(
        identity: DmHeaderIdentity(
          avatar: const CircleAvatar(
            radius: 18,
            backgroundColor: Color(0xFFEAECF0),
            child: Icon(
              Icons.person_outline_rounded,
              size: 19,
              color: DMColors.textSecondary,
            ),
          ),
          title: primaryTitle,
          // 익명 · 날짜(날짜가 없으면 익명만)
          subtitle: headerDate.isEmpty
              ? secondaryTitle
              : '$secondaryTitle · $headerDate',
          semanticsLabel: AppLocalizations.of(context)!.viewProfile,
          onTap: null,
        ),
        actions: [
          ..._buildDmTranslationActions(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.black87),
            constraints: const BoxConstraints(minWidth: 44),
            padding: EdgeInsets.zero,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 4,
            color: Colors.white,
            surfaceTintColor: Colors.white,
            offset: const Offset(0, 8),
            onSelected: (value) {
              if (value == 'leave') {
                _confirmLeaveConversation();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'leave',
                height: 48,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6B7280).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.exit_to_app,
                        size: 16,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)!.leaveChatRoom ?? "채팅방 나가기",
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }

    // 초기 표시 값을 캐시 상태에 따라 조건부로 설정
    // - ⚠️ 대화방(_conversation)이 아직 로드되지 않은 상태에서는 "탈퇴 계정"으로 판단하지 않는다.
    //   (이 오판 때문에 'Deleted Account'가 잠깐 보였다가 사라지는 플리커가 발생할 수 있음)
    final hasCachedConversation = _conversation != null;
    final cachedStatus = _conversation?.participantStatus[otherUserId];
    final cachedName = _conversation?.getOtherUserName(_currentUser!.uid) ?? '';
    final deletedLabel =
        AppLocalizations.of(context)!.deletedAccount ?? 'Deleted Account';

    // 익명이 아닐 때만 탈퇴 계정 체크
    final isCachedDeleted = _isPeerDeleted ||
        (!_isAnonymous &&
            hasCachedConversation &&
            (cachedStatus == 'deleted' ||
                cachedName == 'DELETED_ACCOUNT' ||
                cachedName == deletedLabel));

    // 서버 최신값을 백그라운드로 확보 (옛 값 노출 방지)
    if (!_isAnonymous && !isCachedDeleted) {
      _ensureServerOtherUserInfo(otherUserId);
    }

    // 실시간으로 사용자 정보 조회 (일반 DM만)
    return PreferredSize(
      preferredSize: const Size.fromHeight(_dmToolbarHeight + 1),
      child: StreamBuilder<DMUserInfo?>(
        stream: (_isAnonymous || isCachedDeleted) ? null : _otherUserInfoStream,
        // 캐시 기반 초기값을 UI에 노출하지 않는다(플리커 방지)
        initialData: null,
        builder: (context, snapshot) {
          final info = snapshot.data;
          final DMUserInfo? freshFromStream =
              (info != null && info.isFromCache == false) ? info : null;
          final DMUserInfo? resolved = _serverOtherUserInfo ?? freshFromStream;
          final bool isUserInfoReady = resolved != null;

          final otherUserName = (isCachedDeleted || resolved == null)
              ? (isCachedDeleted ? deletedLabel : '')
              : (resolved.nickname == 'DELETED_ACCOUNT'
                  ? deletedLabel
                  : resolved.nickname);

          // photoURL이 있으면 표시하되, 캐시 스냅샷은 노출하지 않는다.
          final otherUserPhoto =
              (isCachedDeleted || resolved == null) ? '' : resolved.photoURL;
          final otherUserPhotoVersion =
              (isCachedDeleted || resolved == null) ? 0 : resolved.photoVersion;

          final primaryTitle = _isAnonymous
              ? AppLocalizations.of(context)!.anonymous
              : otherUserName;
          // 날짜는 이름 아래 보조 줄. 대화방이 없으면 보조 줄을 숨긴다.
          final headerDate =
              _conversation == null ? '' : _formatHeaderDate();

          return _buildDmAppBar(
            identity: DmHeaderIdentity(
              avatar: UserAvatar(
                uid: otherUserId,
                photoUrl: otherUserPhoto,
                photoVersion: otherUserPhotoVersion,
                isAnonymous: _isAnonymous,
                size: 36,
                placeholderColor: const Color(0xFFE5E7EB),
                placeholderIconSize: 20,
              ),
              title: primaryTitle,
              subtitle: headerDate.isEmpty ? null : headerDate,
              showSkeleton:
                  !_isAnonymous && !isCachedDeleted && !isUserInfoReady,
              semanticsLabel: AppLocalizations.of(context)!.viewProfile,
              onTap: _isAnonymous || isCachedDeleted
                  ? null
                  : () => _openOtherUserProfile(
                        nickname: otherUserName,
                        photoURL: otherUserPhoto,
                      ),
            ),
            actions: [
              ..._buildDmTranslationActions(),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.black87),
                constraints: const BoxConstraints(minWidth: 44),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                color: Colors.white,
                surfaceTintColor: Colors.white,
                offset: const Offset(0, 8),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'block',
                    height: 48,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.block,
                            size: 16,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          AppLocalizations.of(context)!.blockThisUser ?? "",
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(height: 1),
                  PopupMenuItem(
                    value: 'delete',
                    height: 48,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6B7280).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.exit_to_app,
                            size: 16,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          AppLocalizations.of(context)!.leaveChatRoom,
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'block') {
                    _showBlockConfirmation();
                  } else if (value == 'delete') {
                    _confirmLeaveConversation();
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// 채팅방 보관(삭제) - 서버 플래그 기반
  Future<void> _archiveConversation() async {
    try {
      await _dmService.archiveConversation(_activeConversationId);
      if (!mounted) return;
      Navigator.pop(context);
      final isKo = Localizations.localeOf(context).languageCode == 'ko';
      AppSnackBar.show(
        context,
        message: (isChineseUi(context)
            ? '此聊天已从列表中移除。'
            : isKo
                ? '채팅방이 목록에서 삭제되었습니다'
                : 'This chat has been removed from your list.'),
        type: AppSnackBarType.info,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: '${AppLocalizations.of(context)!.error}: $e',
        type: AppSnackBarType.error,
      );
    }
  }

  /// 나가기 확인 다이얼로그
  Future<void> _confirmLeaveConversation() async {
    // 중요한 액션임을 알림 (로그아웃 다이얼로그와 동일 UX)
    HapticFeedback.mediumImpact();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        final isKo = Localizations.localeOf(dialogContext).languageCode == 'ko';

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          elevation: 8,
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          title: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: BrandColors.error.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.exit_to_app_rounded,
                  color: BrandColors.error,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.leaveChatRoom,
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          content: Text(
            (isChineseUi(context)
                ? '确定退出此聊天？'
                : isKo
                    ? '이 채팅방에서 나가시겠습니까?'
                    : 'Are you sure you want to leave this chat?'),
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF374151),
              height: 1.5,
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(dialogContext).pop(false);
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300, width: 1),
                      ),
                      backgroundColor: Colors.white,
                    ),
                    child: Text(
                      l10n.cancel ?? '',
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      Navigator.of(dialogContext).pop(true);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: BrandColors.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      disabledBackgroundColor: const Color(0xFFE5E7EB),
                    ),
                    child: Text(
                      (isChineseUi(context)
                          ? '退出'
                          : isKo
                              ? '나가기'
                              : 'Leave'),
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _leaveConversation();
    }
  }

  /// 대화방 나가기
  Future<void> _leaveConversation() async {
    try {
      // 스트림을 먼저 해제해 나간 직후 권한 오류가 토스트로 보이지 않게 한다
      if (mounted) {
        setState(() {
          _isLeaving = true;
          _recentMessagesSub?.cancel();
          _recentMessagesSub = null;
          _messages = <DMMessage>[];
          _messagesError = null;
        });
      }

      final owner = _currentUser?.uid;
      final result = await _dmService.leaveConversation(_activeConversationId);
      if (owner != null) {
        _scheduleDmReadPostProcessing(_activeConversationId, result, owner);
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (isChineseUi(context)
                ? '你已退出聊天。再次发消息时，将无法查看之前的记录。'
                : Localizations.localeOf(context).languageCode == 'ko'
                    ? '채팅방에서 나갔습니다. 다시 메시지를 보내면 이전 대화 내역은 보이지 않습니다.'
                    : 'You left the chat. Previous messages will not be visible if you send a new message.'),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      Logger.error('대화방 나가기 오류: $e');
      if (!mounted) return;
      setState(() {
        _isLeaving = false;
        _isMessagesLoading = true;
      });
      unawaited(_initializeMessagesStream(conversationId: _activeConversationId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (isChineseUi(context)
                ? '退出聊天失败，请重试。'
                : Localizations.localeOf(context).languageCode == 'ko'
                    ? '채팅방 나가기에 실패했습니다. 다시 시도해 주세요.'
                    : 'Could not leave the chat. Please try again.'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLeaving = false;
        });
      }
    }
  }

  /// 메시지 목록 빌드
  Widget _buildMessageList() {
    // ✅ 대화방이 없다고 확정되기 전까지는(초기화 중) '없음' 문구 대신 스켈레톤을 유지한다.
    if (_conversationExists == false &&
        !_isConversationInitializing &&
        _messages.isEmpty) {
      return _buildStartConversationPlaceholder(isConversationCreated: false);
    }

    // ✅ 초기화/존재 확인 중이라도, 메시지가 이미 있으면(로컬 캐시 등) 바로 렌더링한다.
    if ((_isConversationInitializing || _conversationExists == null) &&
        _messages.isEmpty) {
      return _buildConversationLoadingSkeleton();
    }

    if (_messagesError != null) {
      Logger.error('❌ 메시지 로드 오류: $_messagesError');
      final errorMessage = _messagesError.toString();
      if (errorMessage.contains('permission-denied')) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  (isChineseUi(context)
                      ? '权限错误'
                      : Localizations.localeOf(context).languageCode == 'ko'
                          ? '권한 오류'
                          : 'Permission Error'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  (isChineseUi(context)
                      ? 'Firebase安全规则尚未部署，或你没有访问权限。\n\n请重新启动应用。'
                      : Localizations.localeOf(context).languageCode == 'ko'
                          ? 'Firebase Security Rules가 배포되지 않았거나\n권한이 없습니다.\n\n앱을 다시 시작해주세요.'
                          : 'Firebase Security Rules are not deployed\nor you don\'t have permission.\n\nPlease restart the app.'),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }

      // Transient failure (offline, timeout): offer a retry that re-runs the
      // whole room check instead of leaving a dead end.
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '${AppLocalizations.of(context)!.error}: $_messagesError',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _messagesError = null;
                  _isConversationInitializing = true;
                });
                unawaited(_initConversationState());
              },
              icon: const Icon(Icons.refresh),
              label: Text(isChineseUi(context)
                  ? '重试'
                  : Localizations.localeOf(context).languageCode == 'ko'
                      ? '다시 시도'
                      : 'Retry'),
            ),
          ],
        ),
      );
    }

    if (_isMessagesLoading && _messages.isEmpty) {
      return _buildConversationLoadingSkeleton();
    }

    final messages = _messages;
    if (messages.isEmpty) {
      // 대화방 존재 확인이 끝나지 않았으면 스켈레톤을 유지한다.
      if (_conversationExists == null || _isConversationInitializing) {
        return _buildConversationLoadingSkeleton();
      }
      return _buildStartConversationPlaceholder(isConversationCreated: true);
    }

    _scheduleVisibleTranslations();

    // ✅ 읽음/안읽음 표시는 "최신 안읽음 1개 + 최신 읽음 1개"만 노출
    final myUid = _currentUser!.uid;
    String? latestMyUnreadMessageId;
    String? latestMyReadMessageId;
    DMMessage? peerReadMessage;
    final peerReadMessageId = _peerReadMessageId;
    if (peerReadMessageId != null) {
      for (final m in messages) {
        if (m.id == peerReadMessageId) {
          peerReadMessage = m;
          break;
        }
      }
    }
    for (final m in messages) {
      if (m.senderId != myUid || m.deliveryState != DMDeliveryState.sent)
        continue;
      final isRead = m.isReadThrough(_peerReadThrough,
          watermarkMessage: peerReadMessage);
      if (!isRead && latestMyUnreadMessageId == null) {
        latestMyUnreadMessageId = m.id;
      } else if (isRead && latestMyReadMessageId == null) {
        latestMyReadMessageId = m.id;
      }
      if (latestMyUnreadMessageId != null && latestMyReadMessageId != null)
        break;
    }

    String? _statusFor(DMMessage m) {
      if (m.senderId != myUid || m.deliveryState != DMDeliveryState.sent)
        return null;
      if (m.id == latestMyUnreadMessageId) return '1';
      if (m.id == latestMyReadMessageId)
        return AppLocalizations.of(context)!.read;
      return null;
    }

    String timeLabel(int index) =>
        TimeFormatter.formatMessageTime(context, messages[index].createdAt);
    final indices = <Key, int>{
      for (var i = 0; i < messages.length; i++)
        _messageLayoutKeys.putIfAbsent(messages[i].id, GlobalKey.new): i,
    };

    return NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        final scrolling = notification.direction != ScrollDirection.idle;
        if (_isUserScrolling != scrolling) {
          _isUserScrolling = scrolling;
          if (!scrolling) _commitDeferredDmTranslations();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width < 360 ? 10 : 14,
          // 번역 버튼을 상단 바로 옮겨 목록 위에 떠 있는 요소가 없다.
          12,
          MediaQuery.sizeOf(context).width < 360 ? 10 : 14,
          14,
        ),
        reverse: true,
        itemCount: messages.length + (_hasMore ? 1 : 0),
        findChildIndexCallback: (key) => indices[key],
        itemBuilder: (context, index) {
          // reverse=true에서 "마지막 인덱스"는 화면 상단(가장 과거) 영역에 위치한다.
          if (_hasMore && index == messages.length) {
            return _buildLoadMoreIndicator();
          }

          final message = messages[index];
          final isMine = message.isMine(_currentUser!.uid);
          final String? statusText = _statusFor(message);

          // 시간/읽음 라벨은 동일 내용이 연속될 때 마지막(더 최신) 1개만 노출
          final String timeText = timeLabel(index);
          final String? prevTimeText = index > 0 ? timeLabel(index - 1) : null;
          final String? prevStatusText =
              index > 0 ? _statusFor(messages[index - 1]) : null;
          final bool showTimeText =
              prevTimeText == null || timeText != prevTimeText;
          final bool showStatusText = statusText != null &&
              (prevStatusText == null || statusText != prevStatusText);

          // 같은 발신자의 연속 메시지인지 확인
          final isConsecutive = index < messages.length - 1 &&
              messages[index + 1].senderId == message.senderId;

          // 날짜 구분선 표시 여부 확인 (해당 날짜의 첫 메시지 위에 표시)
          final showDateSeparator = index == messages.length - 1 ||
              !_isSameDay(message.createdAt, messages[index + 1].createdAt);

          return KeyedSubtree(
            key: _messageLayoutKeys.putIfAbsent(message.id, GlobalKey.new),
            child: Column(
              children: [
                if (showDateSeparator) _buildDateSeparator(message.createdAt),
                // 밀어서 답장: 메뉴에 '답장'이 보이는 조건(_canReplyToMessage)과 같다.
                SwipeToReply(
                  enabled: _canReplyToMessage(message),
                  onReply: () => _beginReply(message),
                  semanticsLabel: AppLocalizations.of(context)!.chatReply,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onLongPress: _canReplyToMessage(message)
                        ? () => _showMessageActions(message)
                        : message.type == 'file'
                        ? () => _showPendingFileActions(message)
                        : null,
                    child: Column(
                      crossAxisAlignment: isMine
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        _buildOutgoingPresentation(
                          message,
                          _buildMessageBubble(
                            message,
                            isMine,
                            isConsecutive,
                            timeText: timeText,
                            showTimeText: showTimeText,
                            statusText: statusText,
                            showStatusText: showStatusText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildConversationLoadingSkeleton() {
    // "대화방 없음" 문구가 먼저 보이는 UX를 방지하기 위한 초기 로딩 스켈레톤
    // - Shimmer 의존성을 추가하지 않고, 가벼운 회색 버블 6개만 렌더링한다.
    final base2 = Colors.grey.shade100;
    final widths = <double>[0.62, 0.48, 0.72, 0.40, 0.66, 0.52];

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: widths.length,
      itemBuilder: (context, i) {
        final isMine = i.isEven;
        final w = MediaQuery.sizeOf(context).width * widths[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: w,
              height: 16 + (i % 3) * 10,
              decoration: BoxDecoration(
                color: isMine ? const Color(0xFFD0D5DD) : base2,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStartConversationPlaceholder({
    required bool isConversationCreated,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    final resolvedName = _isAnonymous
        ? (l10n.anonymous ?? 'Anonymous')
        : (_serverOtherUserInfo?.nickname.trim().isNotEmpty == true
            ? _serverOtherUserInfo!.nickname.trim()
            : '');

    final resolvedPhotoUrl =
        _isAnonymous ? '' : (_serverOtherUserInfo?.photoURL ?? '');
    final resolvedPhotoVersion =
        _isAnonymous ? 0 : (_serverOtherUserInfo?.photoVersion ?? 0);

    final title = resolvedName.isNotEmpty
        ? ((isChineseUi(context)
            ? '与${resolvedName}聊天'
            : isKo
                ? '$resolvedName님과 대화를 시작해보세요'
                : 'Start a chat with $resolvedName'))
        : ((isChineseUi(context)
            ? '开始聊天'
            : isKo
                ? '대화를 시작해보세요'
                : 'Start a chat'));

    final subtitle = (isChineseUi(context)
        ? '发送第一条消息创建聊天，\n然后在这里继续交流。'
        : isKo
            ? '첫 메시지를 보내면 대화방이 자동으로 생성되고\n여기서 계속 대화할 수 있어요.'
            : 'Send your first message to create the chat,\nthen continue the conversation here.');

    final hint = isKo
        ? (isConversationCreated
            ? '대화가 시작되면 여기에 메시지가 표시됩니다.'
            : '아직 대화방이 없어요. 메시지를 보내면 시작됩니다.')
        : (isConversationCreated
            ? 'Messages will appear here once the chat starts.'
            : 'No chat yet. Send a message to start.');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            UserAvatar(
              uid: widget.otherUserId,
              photoUrl: resolvedPhotoUrl,
              photoVersion: resolvedPhotoVersion,
              isAnonymous: _isAnonymous,
              size: 72,
              placeholderColor: const Color(0xFFE5E7EB),
              placeholderIconSize: 28,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
                height: isChineseUi(context) ? 1.3 : 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: DMColors.textTertiary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 같은 날짜인지 확인
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  /// 날짜 구분선 빌드
  Widget _buildDateSeparator(DateTime date) {
    final weekdays = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
    final weekday = weekdays[date.weekday - 1];
    final dateText = '${date.month}월 ${date.day}일 $weekday';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      child: Text(
        dateText,
        style: TextStyle(
          color: const Color(0xFF8A8A8A),
          fontSize: ChatMetrics.dateSeparatorSize,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Future<void> _showMessageActions(DMMessage message) async {
    if (!_canReplyToMessage(message)) return;
    HapticFeedback.selectionClick();
    final selected = await showModalBottomSheet<String>(
      context: context,
      requestFocus: false,
      useSafeArea: true,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withValues(alpha: .42),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D5DD),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 10),
              _buildDmMessageQuickActions(sheetContext, message),
              ..._buildDmCopyActions(sheetContext, message),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected.startsWith('reaction:')) {
      final emoji = selected.substring('reaction:'.length);
      if (chatReactionEmojis.contains(emoji)) {
        await _toggleReaction(message, emoji);
      }
      return;
    }
    if (selected == 'copy') {
      await ClipboardImageService.instance.copyText(message.text);
      _showCopiedSnackBar(ok: true);
      return;
    }
    if (selected == 'copyImage') {
      final url = message.imageUrl ?? '';
      _showCopiedSnackBar(
        ok: url.isNotEmpty &&
            await ClipboardImageService.instance.copyImageFromUrl(url),
      );
      return;
    }
    if (selected != 'reply') return;
    _beginReply(message);
  }

  /// 길게 누르기 시트의 복사 줄: 글이 있으면 `복사`, 사진이면 `이미지 복사`.
  List<Widget> _buildDmCopyActions(BuildContext sheetContext, DMMessage message) {
    final code = Localizations.localeOf(sheetContext).languageCode;
    final zh = isChineseUi(sheetContext);
    final hasText = message.text.trim().isNotEmpty;
    final hasImage = (message.imageUrl ?? '').trim().isNotEmpty;
    Widget tile(String key, IconData icon, String label) => InkWell(
          key: ValueKey<String>('dm_action_$key'),
          onTap: () => Navigator.of(sheetContext).pop(key),
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Icon(icon, size: 21, color: DMColors.graphite),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: uiFontFamily(sheetContext, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    return [
      if (hasText || hasImage) const SizedBox(height: 6),
      if (hasText)
        tile('copy', Icons.content_copy_rounded,
            zh ? '复制' : code == 'ko' ? '복사' : 'Copy'),
      if (hasImage)
        tile('copyImage', Icons.image_outlined,
            zh ? '复制图片' : code == 'ko' ? '이미지 복사' : 'Copy image'),
    ];
  }

  void _showCopiedSnackBar({required bool ok}) {
    if (!mounted) return;
    final code = Localizations.localeOf(context).languageCode;
    final zh = isChineseUi(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text(ok
          ? (zh ? '已复制' : code == 'ko' ? '복사했어요' : 'Copied')
          : (zh ? '无法复制' : code == 'ko' ? '복사하지 못했어요' : 'Couldn\'t copy')),
    ));
  }

  /// 답장 모드 진입. 길게 누르기 메뉴의 '답장'과 밀어서 답장이 함께 쓴다.
  void _beginReply(DMMessage message) {
    if (!_canReplyToMessage(message)) return;
    setState(() => _replyingTo = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _messageFocusNode.requestFocus();
    });
  }

  Widget _buildDmMessageQuickActions(
    BuildContext sheetContext,
    DMMessage message,
  ) {
    final l10n = AppLocalizations.of(sheetContext)!;
    final selectedReaction = _myReactions[message.id];

    Widget actionSlot({
      required String semanticLabel,
      required VoidCallback onTap,
      required Widget child,
      Color backgroundColor = Colors.transparent,
    }) {
      return Expanded(
        child: Semantics(
          button: true,
          label: semanticLabel,
          child: Tooltip(
            message: semanticLabel,
            child: MotionPress(
              pressedScale: .9,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 48,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          for (final emoji in chatReactionEmojis)
            actionSlot(
              semanticLabel:
                  '${selectedReaction == emoji ? l10n.chatReactionRemove : l10n.chatReactionAdd} $emoji',
              onTap: () => Navigator.of(sheetContext).pop('reaction:$emoji'),
              backgroundColor: selectedReaction == emoji
                  ? AppColors.pointColor.withValues(alpha: .10)
                  : Colors.transparent,
              child: ChatReactionIcon(emoji),
            ),
          Container(
            width: 1,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            color: DMColors.divider,
          ),
          actionSlot(
            semanticLabel: l10n.chatReply,
            onTap: () => Navigator.of(sheetContext).pop('reply'),
            backgroundColor: const Color(0xFFF2F4F7),
            child: const Icon(
              Icons.reply_rounded,
              size: 23,
              color: DMColors.graphite,
            ),
          ),
        ],
      ),
    );
  }

  bool _canReplyToMessage(DMMessage message) =>
      !_directInteractionRestricted &&
      message.deliveryState == DMDeliveryState.sent &&
      message.serverCreatedAt != null &&
      message.id.trim().isNotEmpty &&
      message.senderId.trim().isNotEmpty;

  Future<void> _toggleReaction(DMMessage message, String emoji) async {
    if (!_canReplyToMessage(message) || !chatReactionEmojis.contains(emoji)) {
      return;
    }
    final previous = _myReactions[message.id];
    final target = previous == emoji ? null : emoji;
    if (target != null) _reactionMotionEvents.record(message.id, target);
    if (!_reactionMutationsInFlight.contains(message.id) &&
        !_pendingReactionTargets.containsKey(message.id)) {
      _confirmedReactions[message.id] = previous;
    }
    setState(() => _applyReactionTargetInState(message.id, target));
    _pendingReactionTargets[message.id] = target;
    await _flushReactionMutations(message.id);
  }

  void _applyReactionTargetInState(String messageId, String? target) {
    final current = _myReactions[messageId];
    if (current == target) return;
    if (target == null) {
      _myReactions.remove(messageId);
    } else {
      _myReactions[messageId] = target;
    }
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    final counts = Map<String, int>.from(_messages[index].reactionCounts);
    if (current != null) {
      final remaining = (counts[current] ?? 1) - 1;
      if (remaining <= 0) {
        counts.remove(current);
      } else {
        counts[current] = remaining;
      }
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
          await _dmService
              .setReaction(
                conversationId: _activeConversationId,
                messageId: messageId,
                emoji: target,
              )
              .timeout(const Duration(seconds: 10));
          _confirmedReactions[messageId] = target;
        } on TimeoutException {
          // A Firestore write can still be queued after the Future times out.
          // Keep the explicit target so a late acknowledgement cannot flicker.
          _confirmedReactions[messageId] = target;
        } catch (_) {
          if (!_pendingReactionTargets.containsKey(messageId) && mounted) {
            setState(() => _applyReactionTargetInState(
                  messageId,
                  _confirmedReactions[messageId],
                ));
            AppSnackBar.show(
              context,
              message: AppLocalizations.of(context)!.chatReactionSaveFailed,
              type: AppSnackBarType.error,
            );
          }
        }
      }
    } finally {
      _reactionMutationsInFlight.remove(messageId);
      if (_pendingReactionTargets.containsKey(messageId)) {
        unawaited(_flushReactionMutations(messageId));
      }
    }
  }

  Future<void> _showReactionUsers(DMMessage message, String emoji) async {
    try {
      final reactions = await _dmService.fetchMessageReactions(
        conversationId: _activeConversationId,
        messageId: message.id,
      );
      final userIds = reactions
          .where((reaction) => reaction.emoji == emoji)
          .map((reaction) => reaction.userId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (!mounted) return;
      final cached = <String, DMUserInfo?>{
        for (final id in userIds)
          id: _userInfoCacheService.getCachedUserInfo(id),
      };
      final usersFuture = _userInfoCacheService.getUserInfoBatch(userIds);
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        builder: (sheetContext) => FutureBuilder<Map<String, DMUserInfo?>>(
          future: usersFuture,
          initialData: cached,
          builder: (context, snapshot) {
            final profiles = <String, DMUserInfo?>{...cached};
            if (snapshot.data != null) profiles.addAll(snapshot.data!);
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(
                  '${AppLocalizations.of(context)!.chatReactionPeople} · ${userIds.length}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: DMColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                ...userIds.map((id) {
                  final profile = profiles[id];
                  final name = profile?.nickname.trim();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: UserAvatar(
                      uid: id,
                      photoUrl: profile?.photoURL ?? '',
                      photoVersion: profile?.photoVersion ?? 0,
                      isAnonymous: profile?.isDeletedAccount == true,
                      size: 38,
                    ),
                    title: Text(
                      name?.isNotEmpty == true
                          ? name!
                          : AppLocalizations.of(context)!.user,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DMColors.textPrimary,
                      ),
                    ),
                    trailing: ChatReactionIcon(emoji, size: 20),
                  );
                }),
              ],
            );
          },
        ),
      );
    } catch (_) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: AppLocalizations.of(context)!.chatReactionSaveFailed,
        type: AppSnackBarType.error,
      );
    }
  }

  Future<void> _showPendingFileActions(DMMessage message) async {
    if (message.type != 'file' ||
        message.deliveryState == DMDeliveryState.sent) {
      return;
    }
    if (_committingOutgoingIds.contains(message.id)) {
      AppSnackBar.show(
        context,
        message: isChineseUi(context)
            ? '正在确认发送。'
            : Localizations.localeOf(context).languageCode == 'ko'
                ? '전송을 확정하는 중이에요.'
                : 'Finalizing delivery.',
        type: AppSnackBarType.info,
      );
      return;
    }
    final shouldCancel = await showModalBottomSheet<bool>(
      context: context,
      requestFocus: false,
      useSafeArea: false,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withValues(alpha: .42),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ListTile(
          minTileHeight: 58,
          leading: const Icon(Icons.close_rounded, color: Color(0xFFD92D20)),
          title: Text(
            isChineseUi(context)
                ? '取消文件发送'
                : Localizations.localeOf(context).languageCode == 'ko'
                    ? '파일 전송 취소'
                    : 'Cancel file upload',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFFD92D20),
            ),
          ),
          onTap: () => Navigator.of(sheetContext).pop(true),
        ),
      ),
    );
    if (!mounted || shouldCancel != true) return;
    await _cancelPendingFile(message);
  }

  Future<void> _cancelPendingFile(DMMessage message) async {
    final owner = _currentUser?.uid;
    final room = _activeConversationId;
    if (owner == null ||
        message.senderId != owner ||
        _committingOutgoingIds.contains(message.id)) {
      return;
    }
    _cancelledOutgoingIds.add(message.id);
    unawaited(_storageService.cancelDmFileUpload(
      userId: owner,
      conversationId: room,
      messageId: message.id,
      fileExtension: message.fileExtension ?? '',
    ));
    await _outbox.remove(owner, room, message.id);
    if (!mounted || !_canSendFor(owner, room)) return;
    setState(() {
      _outgoing.remove(message.id);
      _messages.removeWhere((candidate) => candidate.id == message.id);
      _uploadById.remove(message.id);
    });
  }

  String _replySenderLabel(DMMessage message) {
    return _senderLabelForId(message.senderId);
  }

  String _senderLabelForId(String? senderId) {
    if (senderId == _currentUser?.uid) {
      return isChineseUi(context)
          ? '我'
          : Localizations.localeOf(context).languageCode == 'ko'
              ? '나'
              : 'You';
    }
    if (_isAnonymous) {
      return isChineseUi(context)
          ? '匿名'
          : Localizations.localeOf(context).languageCode == 'ko'
              ? '익명'
              : 'Anonymous';
    }
    final name = _serverOtherUserInfo?.nickname.trim() ?? '';
    return name.isNotEmpty
        ? name
        : (isChineseUi(context)
            ? '对方'
            : Localizations.localeOf(context).languageCode == 'ko'
                ? '상대방'
                : 'Other person');
  }

  String _replyPreviewText(DMMessage message) {
    if (message.type == 'file') {
      return '📎 ${message.fileName?.trim().isNotEmpty == true ? message.fileName!.trim() : message.text.replaceFirst('📎', '').trim()}';
    }
    if (message.text.trim().isNotEmpty) return message.text.trim();
    if ((message.imageUrl ?? '').trim().isNotEmpty ||
        (message.localImagePath ?? '').trim().isNotEmpty) {
      return isChineseUi(context)
          ? '图片'
          : Localizations.localeOf(context).languageCode == 'ko'
              ? '사진'
              : 'Photo';
    }
    return isChineseUi(context)
        ? '无法查看的消息'
        : Localizations.localeOf(context).languageCode == 'ko'
            ? '확인할 수 없는 메시지'
            : 'Message unavailable';
  }

  String? _replySnapshotText(DMMessage message) {
    final text = message.text;
    return text.isEmpty ? null : text;
  }

  Future<void> _jumpToMessage(String rawMessageId) async {
    final messageId = rawMessageId.trim();
    if (messageId.isEmpty) return;
    var index = _messages.indexWhere((message) => message.id == messageId);
    DMMessage? target = index < 0 ? null : _messages[index];
    var missingWasConfirmed = false;

    if (index < 0) {
      try {
        target = await _dmService.getMessageFromServer(
          _activeConversationId,
          messageId,
          visibilityStartTime: _visibilityStartTime,
        );
        missingWasConfirmed = target == null;
      } catch (_) {
        // 오프라인/일시 오류라면 현재 페이지 캐시로 계속 찾되 부재로 확정하지 않는다.
      }
      if (!mounted) return;

      if (target != null) {
        final deadline = DateTime.now().add(const Duration(seconds: 12));
        var cycles = 0;
        while (mounted &&
            _messages.every((message) => message.id != messageId) &&
            _hasMore &&
            cycles < 16 &&
            DateTime.now().isBefore(deadline)) {
          if (_isLoadingMore) {
            await Future<void>.delayed(const Duration(milliseconds: 60));
            continue;
          }
          cycles++;
          final previousOldestId = _messages.isEmpty ? null : _messages.last.id;
          await _loadMoreMessages();
          if (!mounted) return;
          final currentOldestId = _messages.isEmpty ? null : _messages.last.id;
          if (previousOldestId == currentOldestId) break;
        }
        index = _messages.indexWhere((message) => message.id == messageId);
        if (index < 0) {
          // 중간 페이지가 일시적으로 끊겨도 서버에서 확인된 원문 한 건만
          // 임시로 배치한다. 다음 실시간 병합은 동일 ID로 자연스럽게 합쳐진다.
          setState(() {
            _messages = <DMMessage>[
              ..._messages.where((message) => message.id != messageId),
              target!,
            ]..sort(_compareMessagesDesc);
            _unavailableReplyTargetIds.remove(messageId);
          });
          index = _messages.indexWhere((message) => message.id == messageId);
        }
      }
    }

    if (!mounted || index < 0) {
      if (missingWasConfirmed) {
        setState(() => _unavailableReplyTargetIds.add(messageId));
      }
      AppSnackBar.show(
        context,
        message: isChineseUi(context)
            ? '无法查看原消息。'
            : Localizations.localeOf(context).languageCode == 'ko'
                ? '원본 메시지를 확인할 수 없어요.'
                : 'The original message is unavailable.',
        type: AppSnackBarType.info,
      );
      return;
    }
    if (_unavailableReplyTargetIds.remove(messageId)) setState(() {});
    final revealed = await _revealMessage(messageId, index);
    if (!revealed && mounted) {
      AppSnackBar.show(
        context,
        message: isChineseUi(context)
            ? '无法显示原消息位置。'
            : Localizations.localeOf(context).languageCode == 'ko'
                ? '원본 메시지 위치를 표시하지 못했어요.'
                : 'Could not show the original message position.',
        type: AppSnackBarType.info,
      );
    }
  }

  Future<bool> _revealMessage(String messageId, int index) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return false;
      final context = _messageLayoutKeys[messageId]?.currentContext;
      if (context != null && context.mounted) {
        await Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: .45,
        );
        return true;
      }
      if (!_scrollController.hasClients) continue;
      final position = _scrollController.position;
      final denominator = (_messages.length - 1).clamp(1, 1 << 30);
      final ratio = (index / denominator).clamp(0.0, 1.0);
      final offset = position.minScrollExtent +
          (position.maxScrollExtent - position.minScrollExtent) * ratio;
      await _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
    return _messageLayoutKeys[messageId]?.currentContext != null;
  }

  Widget _buildOutgoingPresentation(DMMessage message, Widget bubble) {
    final retryable = message.deliveryState == DMDeliveryState.failed ||
        message.deliveryState == DMDeliveryState.uncertain;
    // Match Snack Chat's optimistic presentation: a locally-created bubble is
    // already the sending feedback, so do not add a second loading indicator.
    // Failed/uncertain messages keep the existing explicit retry affordance.
    if (!retryable) {
      return SnackChatOutgoingEntrance(
        key: ValueKey('dm_entrance_${message.id}'),
        animateOnMount: _entranceIds.contains(message.id),
        onAnimationClaimed: () => _entranceIds.remove(message.id),
        child: bubble,
      );
    }
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final label = message.deliveryState == DMDeliveryState.uncertain
        ? (isChineseUi(context)
            ? '确认发送状态 · 重试'
            : isKo
                ? '전송 확인 필요 · 재시도'
                : 'Delivery unconfirmed · Retry')
        : message.deliveryState == DMDeliveryState.failed
            ? AppLocalizations.of(context)!.messageSendFailed
            : (isChineseUi(context)
                ? '发送中'
                : isKo
                    ? '전송 중'
                    : 'Sending');
    final indicator = message.deliveryState == DMDeliveryState.failed
        ? const Icon(Icons.error_outline_rounded,
            size: 17, color: Color(0xFFD92D20))
        : const Icon(Icons.schedule_rounded,
            size: 17, color: Color(0xFF667085));
    return SnackChatOutgoingEntrance(
      key: ValueKey('dm_entrance_${message.id}'),
      animateOnMount: _entranceIds.contains(message.id),
      onAnimationClaimed: () => _entranceIds.remove(message.id),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        bubble,
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 3),
          child: Semantics(
            button: true,
            label: label,
            child: Tooltip(
              message: label,
              child: MotionPress(
                enabled: !_sendingIds.contains(message.id),
                pressedScale: .9,
                child: InkResponse(
                  onTap: !_sendingIds.contains(message.id)
                      ? () => _queueOutgoing(_activeConversationId, message)
                      : null,
                  radius: 20,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 30,
                    ),
                    child: Center(child: indicator),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildInlineReactionBar(DMMessage message) {
    final maxWidth = MediaQuery.sizeOf(context).width < 360 ? 78.0 : 106.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: ChatReactionBar(
        counts: message.reactionCounts,
        myReaction: _myReactions[message.id],
        animateLocalSelectionOnMount: _reactionMotionEvents.claim(message.id, _myReactions[message.id]),
        // The reaction lives beside, rather than inside, both bubble colors.
        isOutgoing: false,
        addLabel: AppLocalizations.of(context)!.chatReactionAdd,
        removeLabel: AppLocalizations.of(context)!.chatReactionRemove,
        peopleLabel: AppLocalizations.of(context)!.chatReactionPeople,
        showCount: false,
        onToggle: (emoji) => _toggleReaction(message, emoji),
        onShowUsers: (emoji) => _showReactionUsers(message, emoji),
      ),
    );
  }

  /// 메시지 버블 빌드
  Widget _buildMessageBubble(
    DMMessage message,
    bool isMine,
    bool isConsecutive, {
    required String timeText,
    bool showTimeText = true,
    String? statusText,
    bool showStatusText = true,
  }) {
    // 게시글 컨텍스트는 postId만 있어도 카드로 노출한다.
    final hasPostContext =
        (message.postId != null && message.postId!.trim().isNotEmpty);
    final hasImage = message.imageUrl != null && message.imageUrl!.isNotEmpty;
    final hasFile = message.type == 'file' &&
        ((message.fileStoragePath ?? '').trim().isNotEmpty ||
            (message.localFilePath ?? '').trim().isNotEmpty);
    final hasText = message.text.trim().isNotEmpty && !hasFile;
    final hasReply = (message.replyToMessageId ?? '').trim().isNotEmpty;
    // 게시글 컨텍스트가 있으면 "이미지 단독"으로 취급하지 않음 (컨텍스트 카드도 함께 렌더링)
    final hasLocalImage = !hasImage && message.localImagePath != null;
    final isImageOnly =
        hasImage && !hasText && !hasPostContext && !hasReply && !hasFile;
    // 보내는 중인 로컬 사진과 영상도 말풍선 배경 없이 미디어만 보여준다.
    final isLocalImageOnly =
        hasLocalImage && !hasText && !hasPostContext && !hasReply && !hasFile;
    final isVideoOnly = hasFile &&
        SnackChatFilePolicy.isVideoMime(message.fileMimeType) &&
        !hasPostContext &&
        !hasReply;
    Widget bareLocalImage() => ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(File(message.localImagePath!),
              width: 220,
              height: 160,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                  width: 140,
                  height: 100,
                  child: Icon(Icons.broken_image_outlined))),
        );

    final hasRichContent = hasImage ||
        hasFile ||
        hasLocalImage ||
        hasPostContext ||
        isImageOnly ||
        isVideoOnly ||
        isLocalImageOnly;
    final bubbleMaxWidth = MediaQuery.sizeOf(context).width *
        (hasRichContent
            ? ChatMetrics.mediaBubbleWidthFactor
            : ChatMetrics.textBubbleWidthFactor);

    if (isMine) {
      final bubbleChild = isImageOnly
          ? _buildImageBubble(
              imageUrl: message.imageUrl!,
              isMine: true,
              heroTag: 'dm_image_${widget.conversationId}_${message.id}',
            )
          : isVideoOnly
              ? _buildFileBubble(message, isMine: true)
              : isLocalImageOnly
                  ? bareLocalImage()
                  : Container(
              padding: ChatMetrics.bubblePadding,
              decoration: const BoxDecoration(
                color: DMColors.myMessageBg,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(ChatMetrics.bubbleRadius),
                  topRight: Radius.circular(ChatMetrics.bubbleRadius),
                  bottomLeft: Radius.circular(ChatMetrics.bubbleRadius),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (hasReply) ...[
                    _buildReplyQuote(message, isMine: true),
                    if (hasPostContext || hasImage || hasFile || hasText)
                      const SizedBox(height: 8),
                  ],
                  if (hasPostContext) ...[
                    _buildPostContextCard(message, isMine: true),
                    if (hasImage || hasText) const SizedBox(height: 8),
                  ],
                  if (hasImage) ...[
                    _buildImageBubble(
                      imageUrl: message.imageUrl!,
                      isMine: true,
                      heroTag:
                          'dm_image_${widget.conversationId}_${message.id}',
                    ),
                    if (hasText) const SizedBox(height: 8),
                  ],
                  if (hasLocalImage) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(message.localImagePath!),
                          width: 220,
                          height: 160,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(
                              width: 140,
                              height: 100,
                              child: Icon(Icons.broken_image_outlined))),
                    ),
                    if (hasText) const SizedBox(height: 8),
                  ],
                  if (hasFile) _buildFileBubble(message, isMine: true),
                  if (hasText)
                    _buildDmLinkifiedText(
                      message.text,
                      chatMessageTextStyle(
                        context,
                        color: DMColors.myMessageText,
                      ),
                    ),
                ],
              ),
            );

      return Padding(
        padding: EdgeInsets.only(
          left: MediaQuery.sizeOf(context).width < 360 ? 42 : 56,
          right: 0,
          top: isConsecutive ? ChatMetrics.groupGap : ChatMetrics.senderGap,
          bottom: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 시간과 읽음 표시
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Visibility(
                  visible: showTimeText,
                  maintainAnimation: true,
                  maintainSize: true,
                  maintainState: true,
                  child: Text(
                    timeText,
                    style: TextStyle(
                      color: ChatMetrics.timeColor,
                      fontSize: ChatMetrics.timeSize,
                      height: ChatMetrics.timeLine / ChatMetrics.timeSize,
                    ),
                  ),
                ),
                if (statusText != null)
                  Visibility(
                    visible: showStatusText,
                    maintainAnimation: true,
                    maintainSize: true,
                    maintainState: true,
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: ChatMetrics.timeColor,
                        fontSize: ChatMetrics.readCountSize,
                        height: ChatMetrics.readCountLine /
                            ChatMetrics.readCountSize,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 6),
            // 메시지 버블 (이미지만 있으면 테두리 없음)
            Flexible(
              child: MotionPress(
                enabled: _canReplyToMessage(message) || message.type == 'file' || message.type == 'image',
                pressedScale: .985,
                child: Container(
                  key: ValueKey('dm_bubble_${message.id}'),
                  // 텍스트 말풍선은 화면 폭의 0.63, 사진·파일·카드는 0.76까지.
                  constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
                  child: bubbleChild,
                ),
              ),
            ),
            if (message.reactionCounts.isNotEmpty) ...[
              const SizedBox(width: 5),
              _buildInlineReactionBar(message),
            ],
          ],
        ),
      );
    } else {
      final bubbleChild = isImageOnly
          ? _buildImageBubble(
              imageUrl: message.imageUrl!,
              isMine: false,
              heroTag: 'dm_image_${widget.conversationId}_${message.id}',
            )
          : isVideoOnly
              ? _buildFileBubble(message, isMine: false)
              : Container(
              padding: ChatMetrics.bubblePadding,
              decoration: const BoxDecoration(
                color: DMColors.otherMessageBg,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(ChatMetrics.bubbleRadius),
                  topRight: Radius.circular(ChatMetrics.bubbleRadius),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(ChatMetrics.bubbleRadius),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasReply) ...[
                    _buildReplyQuote(message, isMine: false),
                    if (hasPostContext || hasImage || hasFile || hasText)
                      const SizedBox(height: 8),
                  ],
                  if (hasPostContext) ...[
                    _buildPostContextCard(message, isMine: false),
                    if (hasImage || hasText) const SizedBox(height: 8),
                  ],
                  if (hasImage) ...[
                    _buildImageBubble(
                      imageUrl: message.imageUrl!,
                      isMine: false,
                      heroTag:
                          'dm_image_${widget.conversationId}_${message.id}',
                    ),
                    if (hasText) const SizedBox(height: 8),
                  ],
                  if (hasFile) _buildFileBubble(message, isMine: false),
                  if (hasText) _buildDmTranslatedText(message),
                ],
              ),
            );

      return Padding(
        padding: EdgeInsets.only(
          left: 0,
          right: MediaQuery.sizeOf(context).width < 360 ? 42 : 56,
          top: isConsecutive ? ChatMetrics.groupGap : ChatMetrics.senderGap,
          bottom: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 메시지 버블 (이미지만 있으면 테두리 없음)
            Flexible(
              child: MotionPress(
                enabled: _canReplyToMessage(message) || message.type == 'file' || message.type == 'image',
                pressedScale: .985,
                child: Container(
                  key: ValueKey('dm_bubble_${message.id}'),
                  // 텍스트 말풍선은 화면 폭의 0.63, 사진·파일·카드는 0.76까지.
                  constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
                  child: bubbleChild,
                ),
              ),
            ),
            if (message.reactionCounts.isNotEmpty) ...[
              const SizedBox(width: 5),
              _buildInlineReactionBar(message),
            ],
            // 선택 항목: 이 메시지 하나만 번역(말풍선 오른쪽, 시간 앞).
            if (_showsSingleTranslateButton(message) ||
                _singleTranslateLoading.contains(message.id))
              TranslateSingleMessageButton(
                busy: _singleTranslateLoading.contains(message.id),
                onPressed: () => unawaited(_translateSingleMessage(message)),
              ),
            const SizedBox(width: 6),
            // 시간 표시
            Visibility(
              visible: showTimeText,
              maintainAnimation: true,
              maintainSize: true,
              maintainState: true,
              child: Text(
                timeText,
                style: TextStyle(
                  color: ChatMetrics.timeColor,
                  fontSize: ChatMetrics.timeSize,
                  height: ChatMetrics.timeLine / ChatMetrics.timeSize,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildReplyQuote(DMMessage message, {required bool isMine}) {
    final messageId = message.replyToMessageId?.trim() ?? '';
    final sender = _senderLabelForId(message.replyToSenderId);
    final storedText = message.replyToText?.trim() ?? '';
    final unavailable = _unavailableReplyTargetIds.contains(messageId);
    final imageUrl = unavailable ? '' : message.replyToImageUrl?.trim() ?? '';
    final unavailableLabel = isChineseUi(context)
        ? '无法查看的消息'
        : Localizations.localeOf(context).languageCode == 'ko'
            ? '확인할 수 없는 메시지'
            : 'Message unavailable';
    final preview = unavailable
        ? unavailableLabel
        : storedText.isNotEmpty
            ? storedText
            : imageUrl.isNotEmpty
                ? (isChineseUi(context)
                    ? '图片'
                    : Localizations.localeOf(context).languageCode == 'ko'
                        ? '사진'
                        : 'Photo')
                : unavailableLabel;
    final foreground = isMine ? Colors.white : const Color(0xFF344054);
    final secondary = isMine ? Colors.white70 : const Color(0xFF667085);
    final jumpLabel = isChineseUi(context)
        ? '查看原消息'
        : Localizations.localeOf(context).languageCode == 'ko'
            ? '원본 메시지로 이동'
            : 'Go to original message';
    return MotionPressBoundary(
      child: Semantics(
        button: messageId.isNotEmpty && !unavailable,
        label: '$sender, $preview${unavailable ? '' : ', $jumpLabel'}',
        child: Tooltip(
          message: unavailable ? unavailableLabel : jumpLabel,
          child: InkWell(
            onTap: messageId.isEmpty || unavailable
                ? null
                : () => _jumpToMessage(messageId),
            borderRadius: BorderRadius.circular(9),
            child: Container(
              constraints: const BoxConstraints(minWidth: 120, maxWidth: 250),
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
              decoration: BoxDecoration(
                color: isMine
                    ? Colors.white.withValues(alpha: .10)
                    : const Color(0xFFF2F4F7),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 2.5,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isMine ? Colors.white70 : const Color(0xFF2D9CDB),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (imageUrl.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 34,
                        height: 34,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => SizedBox.square(
                          dimension: 34,
                          child: Icon(
                            Icons.image_outlined,
                            size: 18,
                            color: secondary,
                          ),
                        ),
                        errorWidget: (_, __, ___) => SizedBox.square(
                          dimension: 34,
                          child: Icon(
                            Icons.image_outlined,
                            size: 18,
                            color: secondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: ChatMetrics.replyNameSize,
                            fontWeight: FontWeight.w600,
                            color: secondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: ChatMetrics.replyTextSize,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: foreground,
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
      ),
    );
  }

  Widget _buildFileBubble(DMMessage message, {required bool isMine}) {
    if (SnackChatFilePolicy.isVideoMime(message.fileMimeType)) {
      final progress = _uploadById[message.id] ?? _downloadById[message.id];
      return ChatVideoTile(
        thumbnailDataUrl: message.videoThumbnail,
        durationMs: message.videoDurationMs ?? 0,
        width: message.videoWidth ?? 0,
        height: message.videoHeight ?? 0,
        progress: progress,
        failed: message.deliveryState == DMDeliveryState.failed,
        onTap: _openingFileIds.contains(message.id)
            ? null
            : () => _openDmFile(message),
      );
    }
    final name = message.fileName?.trim().isNotEmpty == true
        ? message.fileName!.trim()
        : message.text.replaceFirst('📎', '').trim();
    final extension = message.fileExtension?.trim().toUpperCase() ?? '';
    final size = message.fileSize ?? 0;
    final progress = _downloadById[message.id] ?? _uploadById[message.id];
    final primary = isMine ? Colors.white : const Color(0xFF101828);
    final secondary = isMine ? Colors.white70 : const Color(0xFF667085);
    return Semantics(
      button: true,
      label: name,
      child: InkWell(
        onTap: _openingFileIds.contains(message.id)
            ? null
            : () => _openDmFile(message),
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 190, maxWidth: 260),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 42,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isMine
                          ? Colors.white.withValues(alpha: .12)
                          : const Color(0xFFF2F4F7),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(Icons.insert_drive_file_outlined,
                        size: 23, color: secondary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name.isEmpty
                            ? (isChineseUi(context)
                                ? '文件'
                                : Localizations.localeOf(context)
                                            .languageCode ==
                                        'ko'
                                    ? '파일'
                                    : 'File')
                            : name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: primary,
                          fontSize: 13.5,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (extension.isNotEmpty) extension,
                          if (size > 0) SnackChatFilePolicy.formatBytes(size),
                        ].join(' · '),
                        style: TextStyle(
                          color: secondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (progress != null && progress < 1) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            minHeight: 3,
                            backgroundColor: isMine
                                ? Colors.white24
                                : const Color(0xFFE4E7EC),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isMine ? Colors.white : const Color(0xFF2D9CDB),
                            ),
                          ),
                        ),
                      ],
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

  Future<void> _openDmFile(DMMessage message) async {
    if (!_openingFileIds.add(message.id)) return;
    if (mounted) setState(() {});
    final isVideo = SnackChatFilePolicy.isVideoMime(message.fileMimeType);
    try {
      final localPath = message.localFilePath?.trim() ?? '';
      if (localPath.isNotEmpty && await File(localPath).exists()) {
        if (isVideo) {
          if (!mounted) return;
          await VideoPlaybackScreen.open(
            context,
            localFile: File(localPath),
            title: message.fileName,
          );
          return;
        }
        final result = await OpenFilex.open(localPath);
        if (result.type != ResultType.done) throw StateError(result.message);
        return;
      }
      final owner = _currentUser?.uid;
      final room = _activeConversationId;
      final storagePath = message.fileStoragePath?.trim() ?? '';
      final expectedPrefix =
          'dm_files/${message.senderId}/$room/${message.id}/';
      if (owner == null ||
          storagePath.isEmpty ||
          !storagePath.startsWith(expectedPrefix)) {
        throw StateError('invalid-dm-file');
      }
      if (isVideo) {
        if (!mounted) return;
        await VideoPlaybackScreen.open(
          context,
          reference: AppStorage.ref(
            storagePath,
            storageBucket: message.storageBucket,
          ),
          title: message.fileName,
        );
        return;
      }
      final local = await _storageService.downloadDmFile(
        ownerUid: owner,
        conversationId: room,
        messageId: message.id,
        storagePath: storagePath,
        storageBucket: message.storageBucket,
        fileName: message.fileName ?? 'file',
        fileSize: message.fileSize ?? 0,
        onProgress: (progress) {
          if (!mounted || room != _activeConversationId) return;
          setState(() => _downloadById[message.id] = progress);
        },
      );
      if (!mounted || room != _activeConversationId) return;
      final result = await OpenFilex.open(local.path);
      if (result.type != ResultType.done) throw StateError(result.message);
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: isChineseUi(context)
            ? '无法打开文件。'
            : Localizations.localeOf(context).languageCode == 'ko'
                ? '파일을 열 수 없어요.'
                : 'Could not open the file.',
        type: AppSnackBarType.error,
      );
      Logger.error('DM 파일 열기 실패: $error');
    } finally {
      _openingFileIds.remove(message.id);
      if (mounted) {
        setState(() => _downloadById.remove(message.id));
      }
    }
  }

  Widget _buildPostContextCard(DMMessage message, {required bool isMine}) {
    final postId = message.postId?.trim() ?? '';
    final img = (message.postImageUrl?.trim().isNotEmpty ?? false)
        ? message.postImageUrl!.trim()
        : '';
    final preview = (message.postPreview ?? '').trim();
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return MotionPress(
      enabled: postId.isNotEmpty,
      pressedScale: .985,
      child: GestureDetector(
        onTap: postId.isEmpty ? null : () => _navigateToPost(postId),
        child: Container(
          decoration: BoxDecoration(
            color: isMine
                ? Colors.white.withOpacity(0.10)
                : const Color(0xFFF2F4F7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (img.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CachedNetworkImage(
                      imageUrl: img,
                      fit: BoxFit.cover,
                      fadeInDuration: MotionTokens.fast,
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, __) => _buildMediaPlaceholder(
                        isMine: isMine,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, __, ___) => _buildMediaPlaceholder(
                        isMine: isMine,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: Icon(
                          Icons.image_outlined,
                          size: 20,
                          color: isMine ? Colors.white70 : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 16,
                          color: isMine ? Colors.white70 : Colors.grey.shade700,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            (isChineseUi(context)
                                ? '来自一条动态'
                                : isKo
                                ? '포스트에서 보낸 메시지'
                                : 'Sent from a post'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isMine
                                  ? Colors.white70
                                  : Colors.grey.shade800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (postId.isNotEmpty)
                          Text(
                            (isChineseUi(context)
                                ? '查看'
                                : isKo
                                ? '보기'
                                : 'View'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isMine
                                  ? Colors.white
                                  : DMColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        preview,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: isMine ? Colors.white : Colors.grey.shade800,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageBubble({
    required String imageUrl,
    required bool isMine,
    required String heroTag,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = screenWidth < 400 ? screenWidth * 0.62 : 240.0;
    const maxHeight = 240.0;

    return MotionPress(
      pressedScale: .985,
      child: GestureDetector(
        onTap: () => _openImageViewer(imageUrl, heroTag: heroTag),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
            child: Hero(
              tag: heroTag,
              child: RetryableChatNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                fadeInDuration: MotionTokens.fast,
                fadeOutDuration: Duration.zero,
                placeholder: (_, __) => _buildMediaPlaceholder(
                  isMine: isMine,
                  borderRadius: BorderRadius.circular(14),
                  child: const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorBuilder: (_, __, ___, retry) => _buildMediaPlaceholder(
                  isMine: isMine,
                  borderRadius: BorderRadius.circular(14),
                  child: Semantics(
                    button: true,
                    label: (isChineseUi(context)
                        ? '重新加载图片'
                        : Localizations.localeOf(context).languageCode == 'ko'
                        ? '이미지 다시 불러오기'
                        : 'Retry image'),
                    child: TextButton.icon(
                      onPressed: retry,
                      style: TextButton.styleFrom(
                        foregroundColor: isMine
                            ? Colors.white70
                            : Colors.grey[700],
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        minimumSize: const Size(44, 44),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(
                        (isChineseUi(context)
                            ? '重新加载'
                            : Localizations.localeOf(context).languageCode == 'ko'
                            ? '다시 불러오기'
                            : 'Retry'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaPlaceholder({
    required bool isMine,
    required BorderRadius borderRadius,
    required Widget child,
  }) {
    final bg =
        isMine ? Colors.white.withOpacity(0.16) : const Color(0xFFF3F4F6);
    final border = isMine
        ? Colors.white.withOpacity(0.22)
        : Colors.black.withOpacity(0.06);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: borderRadius,
        border: Border.all(color: border),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  void _openImageViewer(String imageUrl, {required String heroTag}) {
    // 다른 페이지(게시글/후기 등)와 동일한 전체화면 이미지 뷰어 사용
    showFullscreenImageViewer(
      context,
      imageUrls: [imageUrl],
      initialIndex: 0,
      heroTag: heroTag,
    );
  }

  /// 입력창 빌드
  Widget _buildInputArea() => ValueListenableBuilder<TextEditingValue>(
        valueListenable: _messageController,
        builder: (context, value, _) => _buildComposer(),
      );

  Widget _buildComposer() {
    final peerDeleted = _isPeerDeleted;

    final originPostId = (widget.originPostId ?? '').trim();
    final shouldShowComposerPostContext = originPostId.isNotEmpty &&
        !_originPostContextAttached &&
        !_composerPostContextDismissed;

    return Container(
      color: DMColors.pageBg,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 4),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).width < 360 ? 8 : 12,
            vertical: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChatReplyReveal(
                replyId: _replyingTo?.id,
                child: _replyingTo == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildComposerReplyPreview(_replyingTo!),
                      ),
              ),
              // ✅ 게시글에서 DM으로 진입한 경우: "보내기 전" 컨텍스트 미리보기 카드
              // - 사용자는 메시지를 입력한 뒤 전송할 수 있고,
              // - 첫 전송 시에만 실제 메시지에 post_context로 부착된다.
              if (shouldShowComposerPostContext) ...[
                _buildComposerPostContextPreview(),
                const SizedBox(height: 8),
              ],
              if (_conversationExists == false &&
                  !_isAnonymous &&
                  !peerDeleted &&
                  !_directInteractionRestricted) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    (isChineseUi(context)
                        ? '发送第一条消息，开始聊天。'
                        : Localizations.localeOf(context).languageCode == 'ko'
                            ? '첫 메시지를 보내면 대화방이 생성돼요.'
                            : 'Send your first message to create this chat.'),
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_pendingImage != null) ...[
                _buildAttachmentPreview(),
                const SizedBox(height: 8),
              ],
              _buildTranslateFirstHint(),
              // 화면 아래에 떠 있는 어두운 알약(스낵챗과 같은 ChatPillComposer).
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _messageController,
                builder: (context, value, _) {
                  final disabled = peerDeleted || _directInteractionRestricted;
                  final hasDraft = value.text.trim().isNotEmpty ||
                      _pendingImage != null ||
                      _pendingFile != null;
                  final zh = isChineseUi(context);
                  final isKo =
                      Localizations.localeOf(context).languageCode == 'ko';
                  return ChatPillComposer(
                    enabled: !disabled,
                    showSend: hasDraft,
                    canSend: !disabled && hasDraft,
                    onCamera: () => _pickImageFrom(ImageSource.camera),
                    onGallery: () => _pickImageFrom(ImageSource.gallery),
                    // 사진·영상은 사진 버튼에 있으니 +는 파일 첨부만 남는다.
                    onAttach: _pickFile,
                    attachIcon: Icons.attach_file_rounded,
                    onSend: _sendMessage,
                    cameraLabel: zh ? '相机' : (isKo ? '카메라' : 'Camera'),
                    galleryLabel:
                        zh ? '相册' : (isKo ? '사진 보관함' : 'Photo library'),
                    attachLabel: zh ? '文件' : (isKo ? '파일' : 'File'),
                    sendLabel: zh ? '发送' : (isKo ? '전송' : 'Send'),
                    textField: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        enabled: !disabled,
                        // 사진 붙여넣기: 길게 눌러 붙여넣기·키보드 클립보드.
                        contextMenuBuilder: (context, state) =>
                            pasteImageAwareContextMenu(
                          context,
                          state,
                          (image) => unawaited(_sendPastedImage(image)),
                        ),
                        contentInsertionConfiguration:
                            ContentInsertionConfiguration(
                          allowedMimeTypes: kPastableImageMimeTypes,
                          onContentInserted: (content) async {
                            final image =
                                await readKeyboardInsertedImage(content);
                            if (image != null) await _sendPastedImage(image);
                          },
                        ),
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 500,
                        textInputAction: TextInputAction.newline,
                        cursorColor: Colors.white,
                        decoration: InputDecoration(
                          hintText: peerDeleted
                              ? (zh
                                  ? '无法给已注销的账号发消息'
                                  : isKo
                                      ? '탈퇴한 계정에게는 메시지를 보낼 수 없어요'
                                      : 'You cannot message a deleted account')
                              : (_isBlocked || _isBlockedBy)
                                  ? '차단된 사용자에게 메시지를 보낼 수 없습니다'
                                  : AppLocalizations.of(context)!.typeMessage,
                          hintStyle: chatMessageTextStyle(
                            context,
                            color: chatComposerPlaceholder,
                          ),
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                          border: InputBorder.none,
                          counterText: '',
                        ),
                        style: chatMessageTextStyle(
                          context,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposerReplyPreview(DMMessage message) {
    final imageUrl = message.imageUrl?.trim() ?? '';
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF2D9CDB),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _replySenderLabel(message),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyPreviewText(message),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                  ),
                ),
              ],
            ),
          ),
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                placeholder: (_, __) => const SizedBox.square(
                  dimension: 40,
                  child: Icon(
                    Icons.image_outlined,
                    size: 21,
                    color: Color(0xFF667085),
                  ),
                ),
                errorWidget: (_, __, ___) => const SizedBox.square(
                  dimension: 40,
                  child: Icon(
                    Icons.image_outlined,
                    size: 21,
                    color: Color(0xFF667085),
                  ),
                ),
              ),
            ),
          ],
          Semantics(
            button: true,
            label: isChineseUi(context)
                ? '取消回复'
                : Localizations.localeOf(context).languageCode == 'ko'
                    ? '답장 취소'
                    : 'Cancel reply',
            child: MotionPress(
              pressedScale: .9,
              child: IconButton(
                tooltip: isChineseUi(context)
                    ? '取消回复'
                    : Localizations.localeOf(context).languageCode == 'ko'
                        ? '답장 취소'
                        : 'Cancel reply',
                onPressed: () => setState(() => _replyingTo = null),
                icon: const Icon(Icons.close_rounded, size: 19),
                color: const Color(0xFF667085),
                constraints:
                    const BoxConstraints.tightFor(width: 42, height: 42),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposerPostContextPreview() {
    final postId = (widget.originPostId ?? '').trim();
    final img = (widget.originPostImageUrl ?? '').trim();
    final preview = (widget.originPostPreview ?? '').trim();
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    return MotionPress(
      enabled: postId.isNotEmpty,
      pressedScale: .985,
      child: GestureDetector(
        onTap: postId.isEmpty ? null : () => _navigateToPost(postId),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 썸네일 (있으면)
              if (img.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: img,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 56,
                      height: 56,
                      color: Colors.grey[200],
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 56,
                      height: 56,
                      color: Colors.grey[200],
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.article_outlined,
                        size: 22,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.article_outlined,
                    size: 22,
                    color: Color(0xFF6B7280),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (isChineseUi(context)
                                ? '聊聊这条动态'
                                : isKo
                                ? '이 게시글에 대해 DM 보내기'
                                : 'Message about this post'),
                            style: TextStyle(
                              fontFamily: uiFontFamily(context, 'Inter'),
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _composerPostContextDismissed = true;
                            });
                          },
                          customBorder: const CircleBorder(),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              size: 18,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        preview,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4B5563),
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview() {
    final isKorean = Localizations.localeOf(context).languageCode == 'ko';
    final showProgress = _uploadProgress != null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              _pendingImage!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (isChineseUi(context)
                      ? '已选1张图片'
                      : isKorean
                          ? '이미지 1장 선택됨'
                          : '1 image selected'),
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                if (showProgress) ...[
                  Text(
                    (isChineseUi(context)
                        ? '上传中… ${((_uploadProgress ?? 0) * 100).round()}%'
                        : isKorean
                            ? '업로드 중... ${((_uploadProgress ?? 0) * 100).round()}%'
                            : 'Uploading... ${((_uploadProgress ?? 0) * 100).round()}%'),
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (_uploadProgress ?? 0).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: const Color(0xFFE5E7EB),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          DMColors.myMessageBg),
                    ),
                  ),
                ] else ...[
                  Text(
                    (isChineseUi(context)
                        ? '对方将可以看到'
                        : isKorean
                            ? '전송하면 상대방에게 이미지가 표시됩니다'
                            : 'It will be visible to the other user'),
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF6B7280),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _pendingImage = null;
                _uploadProgress = null;
              });
            },
            icon: const Icon(Icons.close, size: 18),
            color: Colors.grey[600],
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        withData: false,
        withReadStream: false,
        allowedExtensions:
            SnackChatFilePolicy.allowedMimeByExtension.keys.toList(),
      );
      if (!mounted || picked == null || picked.files.isEmpty) return;
      final selected = picked.files.single;
      if (selected.size > SnackChatFilePolicy.maxFileBytes) {
        throw const SnackChatFileValidationException(
          '파일은 20MB 이하만 전송할 수 있습니다.',
        );
      }
      final readablePath = await _documentImporter.resolveReadablePath(
        fileName: selected.name,
        pickerPath: selected.path,
        identifier: selected.identifier,
      );
      if (readablePath == null) {
        throw const SnackChatFileValidationException(
          '선택한 파일을 읽을 수 없습니다.',
        );
      }
      final validated = await SnackChatFilePolicy.validatePath(
        readablePath,
        displayName: selected.name,
        reportedSize: selected.size,
      );
      if (!mounted) return;
      final confirmed = await showSnackChatFileConfirmationSheet(
        context,
        files: <SnackChatSelectedFile>[validated],
        temporary24h: false,
        retentionDescription: isChineseUi(context)
            ? '文件将保存在此私信中。'
            : Localizations.localeOf(context).languageCode == 'ko'
                ? '파일은 이 DM 대화에 보관됩니다.'
                : 'The file remains available in this DM.',
      );
      if (!mounted || confirmed == null || confirmed.isEmpty) return;
      setState(() => _pendingFile = confirmed.first);
      await _sendMessage(preserveDraft: true);
    } on SnackChatFileValidationException catch (error) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: error.message,
        type: AppSnackBarType.error,
      );
    } catch (error, stackTrace) {
      Logger.error('DM 파일 선택 실패', error, stackTrace);
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: isChineseUi(context)
            ? '无法选择文件。'
            : Localizations.localeOf(context).languageCode == 'ko'
                ? '파일을 선택할 수 없어요.'
                : 'Could not select the file.',
        type: AppSnackBarType.error,
      );
    }
  }

  bool _initialReplyHandled = false;

  /// 스낵 답장 미디어를 대화방 진입 직후 한 번 보낸다.
  /// 사진은 출처 한 줄을 캡션으로 함께, 영상은 확인 직후 출처 한 줄을 먼저 보낸다.
  Future<void> _sendInitialSnackReply() async {
    if (_initialReplyHandled) return;
    _initialReplyHandled = true;
    final media = widget.initialReplyMedia;
    final replyText = (widget.initialReplyText ?? '').trim();
    if (media == null && replyText.isEmpty) return;
    // 상대 계정 상태 등 첫 로딩이 자리 잡을 시간을 준다.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    final contextLine = (widget.initialReplyContext ?? '').trim();
    if (media == null) {
      // 글 답장: 출처 한 줄과 본문을 한 메시지로 보낸다.
      _messageController.text =
          contextLine.isEmpty ? replyText : '$contextLine\n$replyText';
      await _sendMessage();
      widget.onInitialReplySent?.call();
      return;
    }
    void fillContext() {
      if (contextLine.isEmpty) return;
      if (_messageController.text.trim().isEmpty) {
        _messageController.text = contextLine;
      }
    }

    if (widget.initialReplyIsVideo) {
      await _sendPickedVideo(
        media,
        beforeSend: contextLine.isEmpty
            ? null
            : () async {
                fillContext();
                await _sendMessage();
              },
      );
    } else {
      await _sendPickedImageFile(media, beforeSend: fillContext);
    }
  }

  Future<void> _pickImageFrom(ImageSource source) async {
    try {
      // 갤러리는 사진과 영상을 한 화면에서 고른다(시스템 포토 피커).
      final xfile = source == ImageSource.gallery
          ? await _imagePicker.pickMedia()
          : await _imagePicker.pickImage(source: source);
      if (xfile == null) return;

      if (!mounted) return;

      if (_looksLikeVideo(xfile)) {
        await _sendPickedVideo(File(xfile.path));
        return;
      }
      await _sendPickedImageFile(File(xfile.path));
    } catch (e) {
      Logger.error('이미지 선택 오류: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (isChineseUi(context)
                ? '无法选择图片'
                : Localizations.localeOf(context).languageCode == 'ko'
                    ? '이미지를 불러올 수 없습니다'
                    : 'Unable to pick an image'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 붙여넣은 사진: 임시 파일로 저장해 사진 보내기 경로(미리보기 → 전송)로 넘긴다.
  Future<void> _sendPastedImage(ClipboardImage image) async {
    final file =
        await ClipboardImageService.instance.saveToTemporaryFile(image);
    if (!mounted) return;
    await _sendPickedImageFile(file);
  }

  /// 사진 한 장을 미리보기에서 확인받고 보낸다. [beforeSend]는 확인 직후,
  /// 전송 직전에 호출된다(예: 캡션 채우기).
  Future<void> _sendPickedImageFile(
    File pickedFile, {
    VoidCallback? beforeSend,
  }) async {
    try {
      // Compress and measure while the preview screen is open so the send
      // itself only has to upload.
      final preparing = _storageService.prepareChatImage(pickedFile);
      final shouldSend = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DMImageSendPreviewScreen(imageFile: pickedFile),
          fullscreenDialog: true,
        ),
      );

      if (!mounted || shouldSend != true) {
        unawaited(preparing.then((prepared) => prepared?.dispose()));
        return;
      }

      final prepared = await preparing;
      if (prepared != null) {
        _preparedImages[pickedFile.path] = prepared;
      }
      beforeSend?.call();
      setState(() {
        _pendingImage = pickedFile;
        _uploadProgress = null;
      });
      await _sendMessage();
    } catch (e) {
      Logger.error('이미지 선택 오류: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (isChineseUi(context)
                ? '无法选择图片'
                : Localizations.localeOf(context).languageCode == 'ko'
                    ? '이미지를 불러올 수 없습니다'
                    : 'Unable to pick an image'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  static const Set<String> _videoExtensions = {
    'mp4', 'mov', 'm4v', '3gp', 'mkv', 'webm', 'avi', 'mpeg', 'mpg',
  };

  bool _looksLikeVideo(XFile file) {
    final mime = (file.mimeType ?? '').toLowerCase();
    if (mime.startsWith('video/')) return true;
    if (mime.startsWith('image/')) return false;
    final extension = SnackChatFilePolicy.extensionOf(file.name.isNotEmpty
        ? file.name
        : file.path);
    return _videoExtensions.contains(extension);
  }

  /// 갤러리에서 고른 영상: 540p로 압축하고 썸네일을 만든 뒤 파일 메시지로 보낸다.
  Future<void> _sendPickedVideo(
    File source, {
    Future<void> Function()? beforeSend,
  }) async {
    if (_pendingFile != null || _pendingImage != null) return;
    final limits = VideoUploadPolicy.dm;
    File? staged;
    try {
      final file = await runWithVideoPreparingDialog<SnackChatSelectedFile>(
        context,
        () async {
          final prepared = await VideoPrepareService.instance
              .prepare(source, limits: limits);
          final meta =
              await VideoPrepareService.instance.chatVideoMeta(prepared);
          final stem = p.basenameWithoutExtension(source.path);
          staged = await VideoPrepareService.instance
              .stageForSend(prepared, stem: stem);
          final validated = await SnackChatFilePolicy.validatePath(
            staged!.path,
            displayName: '${stem.isEmpty ? 'video' : stem}.mp4',
          );
          return validated.withVideoMeta(meta);
        },
      );
      if (!mounted) return;
      final confirmed = await showSnackChatFileConfirmationSheet(
        context,
        files: <SnackChatSelectedFile>[file],
        temporary24h: false,
        retentionDescription: isChineseUi(context)
            ? '视频将保存在此私信中。'
            : Localizations.localeOf(context).languageCode == 'ko'
                ? '영상은 이 DM 대화에 보관됩니다.'
                : 'The video remains available in this DM.',
      );
      if (!mounted || confirmed == null || confirmed.isEmpty) return;
      if (beforeSend != null) {
        await beforeSend();
        if (!mounted) return;
      }
      setState(() => _pendingFile = confirmed.first);
      await _sendMessage(preserveDraft: true);
    } on SnackChatFileValidationException catch (error) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: error.message,
        type: AppSnackBarType.error,
      );
    } catch (error, stackTrace) {
      Logger.error('DM 영상 준비 실패', error, stackTrace);
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: videoPrepareErrorMessage(context, error, limits),
        type: AppSnackBarType.error,
      );
    } finally {
      // 전송 큐가 자기 저장소로 복사한 뒤이므로 임시 사본은 지운다.
      final temp = staged;
      if (temp != null) {
        unawaited(Future<void>.delayed(const Duration(seconds: 30), () async {
          try {
            if (await temp.exists()) await temp.delete();
          } catch (_) {}
        }));
      }
    }
  }

  Future<void> _sendMessage({bool preserveDraft = false}) async {
    final owner = _currentUser?.uid;
    final room = _activeConversationId;
    if (owner == null ||
        !_canSendFor(owner, room) ||
        _isPeerDeleted ||
        _directInteractionRestricted) return;
    final typedText = _messageController.text.trim();
    final image = _pendingImage;
    final selectedFile = _pendingFile;
    final text = selectedFile == null
        ? typedText
        : '${selectedFile.isVideo ? '🎬' : '📎'} ${selectedFile.originalFileName}';
    if ((text.isEmpty && image == null && selectedFile == null) ||
        typedText.length > 500) return;
    final replyTarget = _replyingTo;
    if (replyTarget != null && !_canReplyToMessage(replyTarget)) return;
    final watch = Stopwatch()..start();
    final attach = !_originPostContextAttached &&
        !_composerPostContextDismissed &&
        (widget.originPostId ?? '').trim().isNotEmpty;
    final now = DateTime.now();
    final at = _lastLocalSentAt != null && !now.isAfter(_lastLocalSentAt!)
        ? _lastLocalSentAt!.add(const Duration(microseconds: 1))
        : now;
    _lastLocalSentAt = at;
    final message = DMMessage(
      id: _dmService.createMessageId(room),
      senderId: owner,
      text: text,
      createdAt: at,
      isRead: false,
      deliveryState: DMDeliveryState.sending,
      localImagePath: image?.path,
      localFilePath: selectedFile?.path,
      fileName: selectedFile?.originalFileName,
      fileExtension: selectedFile?.fileExtension,
      fileMimeType: selectedFile?.mimeType,
      fileSize: selectedFile?.fileSize,
      videoDurationMs: selectedFile?.videoMeta?.durationMs,
      videoWidth: selectedFile?.videoMeta?.width,
      videoHeight: selectedFile?.videoMeta?.height,
      videoThumbnail: selectedFile?.videoMeta?.thumbnailDataUrl,
      replyToMessageId: replyTarget?.id,
      replyToSenderId: replyTarget?.senderId,
      replyToText: replyTarget == null ? null : _replySnapshotText(replyTarget),
      replyToImageUrl: replyTarget?.imageUrl,
      type: selectedFile != null
          ? 'file'
          : attach
              ? 'post_context'
              : 'text',
      postId: attach ? widget.originPostId : null,
      postImageUrl: attach ? widget.originPostImageUrl : null,
      postPreview: attach ? widget.originPostPreview : null,
    );
    final keepFocus = _messageFocusNode.hasFocus;
    if (!preserveDraft) _messageController.clear();
    _entranceIds.add(message.id);
    Timer(SnackChatOutgoingEntrance.claimWindow,
        () => _entranceIds.remove(message.id));
    setState(() {
      _pendingImage = null;
      _pendingFile = null;
      _replyingTo = null;
      _uploadProgress = null;
      if (attach) _originPostContextAttached = true;
      _outgoing[message.id] = message;
      _messages = _mergeRecentIntoAll([message], _messages);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (keepFocus && !_messageFocusNode.hasFocus)
        _messageFocusNode.requestFocus();
      _followLatest();
      if (ChatTiming.enabled)
        ChatTiming.record(
            '[DMChatTiming] stage=localFrame messageId=${message.id} durationMs=${watch.elapsedMilliseconds}');
    });
    _queueOutgoing(room, message);
  }

  bool _canSendFor(String owner, String room) =>
      !_accountInvalidated &&
      !_isLeaving &&
      FirebaseAuth.instance.currentUser?.uid == owner &&
      _activeConversationId == room;

  void _queueOutgoing(String room, DMMessage packet, {bool automatic = false}) {
    if (_directInteractionRestricted) return;
    if (!_canSendFor(packet.senderId, room)) return;
    if (!_sendingIds.add(packet.id)) return;
    if (!automatic) _outboxRetryAttempts.remove(packet.id);
    final owner = packet.senderId;
    final persisted = _outbox
        .put(owner, room, packet.id, packet.toLocalMap())
        .then<Object?>((_) => null, onError: (Object error) => error);
    final isTextOnly =
        packet.localImagePath == null && packet.localFilePath == null;
    Future<void> operation({required bool persistInsideDispatch}) async {
      var message = packet.copyWith(deliveryState: DMDeliveryState.sending);
      try {
        if (!persistInsideDispatch) {
          final persistenceError = await persisted;
          if (persistenceError != null) throw persistenceError;
        }
        if (_cancelledOutgoingIds.contains(message.id)) return;
        if (_directInteractionRestricted) {
          throw StateError('blocked-direct-message');
        }
        if (!_canSendFor(owner, room)) return;
        _updateOutgoing(room, message);
        if (message.localImagePath != null && message.imageUrl == null) {
          if (!await _ensureSendRoom(room, message))
            throw StateError('room-unavailable');
          message = await _imagePreparation.run(owner, () async {
            if (!_canSendFor(owner, room))
              throw StateError('account-or-room-changed');
            final path = await _outbox.retainImage(
                owner, message.id, message.localImagePath!);
            message = message.copyWith(localImagePath: path);
            await _outbox.put(owner, room, message.id, message.toLocalMap());
            if (!_canSendFor(owner, room))
              throw StateError('account-or-room-changed');
            // Prepared bytes (if the picker flow produced them) are keyed by the
            // originally picked path; retries after a restart simply prepare
            // again inside uploadDmImage.
            final prepared = _preparedImages.remove(message.localImagePath) ??
                _preparedImages.remove(path);
            final String? url;
            try {
              url = await _storageService.uploadDmImage(File(path),
                  userId: owner,
                  conversationId: room,
                  prepared: prepared, onProgress: (progress) {
                if (mounted && _canSendFor(owner, room)) {
                  setState(() => _uploadById[message.id] = progress);
                }
              });
            } finally {
              unawaited(prepared?.dispose());
            }
            if (url == null || url.isEmpty) throw StateError('upload-failed');
            final uploaded = message.copyWith(imageUrl: url);
            await _outbox.put(owner, room, uploaded.id, uploaded.toLocalMap());
            return uploaded;
          });
        }
        if (message.localFilePath != null && message.fileStoragePath == null) {
          if (!await _ensureSendRoom(room, message)) {
            throw StateError('room-unavailable');
          }
          message = await _filePreparation.run(owner, () async {
            if (_cancelledOutgoingIds.contains(message.id)) {
              throw StateError('file-upload-cancelled');
            }
            if (!_canSendFor(owner, room)) {
              throw StateError('account-or-room-changed');
            }
            final extension = message.fileExtension ?? '';
            final path = await _outbox.retainFile(
              owner,
              message.id,
              message.localFilePath!,
              extension,
            );
            final checked = await SnackChatFilePolicy.validatePath(
              path,
              displayName: message.fileName,
              reportedSize: message.fileSize,
            );
            if (_cancelledOutgoingIds.contains(message.id)) {
              throw StateError('file-upload-cancelled');
            }
            message = message.copyWith(
              localFilePath: path,
              fileName: checked.originalFileName,
              fileExtension: checked.fileExtension,
              fileMimeType: checked.mimeType,
              fileSize: checked.fileSize,
            );
            await _outbox.put(owner, room, message.id, message.toLocalMap());
            if (!_canSendFor(owner, room)) {
              throw StateError('account-or-room-changed');
            }
            final result = await _storageService.uploadDmFile(
              File(path),
              userId: owner,
              conversationId: room,
              messageId: message.id,
              fileName: checked.originalFileName,
              fileExtension: checked.fileExtension,
              mimeType: checked.mimeType,
              fileSize: checked.fileSize,
              onProgress: (progress) {
                if (mounted && _canSendFor(owner, room)) {
                  setState(() => _uploadById[message.id] = progress);
                }
              },
            );
            if (_cancelledOutgoingIds.contains(message.id)) {
              throw StateError('file-upload-cancelled');
            }
            if (result == null) throw StateError('file-upload-failed');
            final uploaded = message.copyWith(
              fileStoragePath: result.storagePath,
              storageBucket: result.storageBucket,
            );
            await _outbox.put(owner, room, uploaded.id, uploaded.toLocalMap());
            return uploaded;
          });
        }
        if (_cancelledOutgoingIds.contains(message.id)) return;
        if (!_canSendFor(owner, room)) return;
        _committingOutgoingIds.add(message.id);
        if (mounted && _canSendFor(owner, room)) setState(() {});
        late final DMDeliveryState result;
        try {
          late Future<DMDeliveryState> delivery;
          await _dispatch.run<void>('$owner::$room', () async {
            // Text commits enter this queue in tap order before waiting for
            // their local outbox write. The write still completes before the
            // network call. Once DMService has registered its stable-ID commit,
            // response resolution and outbox cleanup no longer occupy this
            // screen-level ordering gate.
            if (persistInsideDispatch) {
              final persistenceError = await persisted;
              if (persistenceError != null) throw persistenceError;
            }
            if (_cancelledOutgoingIds.contains(message.id)) {
              throw StateError('outgoing-cancelled');
            }
            if (_directInteractionRestricted) {
              delivery = Future<DMDeliveryState>.value(
                DMDeliveryState.failed,
              );
              return;
            }
            if (!_canSendFor(owner, room)) {
              delivery = Future<DMDeliveryState>.value(
                DMDeliveryState.uncertain,
              );
              return;
            }
            if (!await _ensureSendRoom(room, message)) {
              delivery = Future<DMDeliveryState>.value(
                DMDeliveryState.failed,
              );
              return;
            }
            if (!_canSendFor(owner, room)) {
              delivery = Future<DMDeliveryState>.value(
                DMDeliveryState.uncertain,
              );
              return;
            }
            delivery = _dmService.sendMessage(room, message);
          });
          result = await delivery;
        } finally {
          _committingOutgoingIds.remove(message.id);
          if (mounted && _canSendFor(owner, room)) setState(() {});
        }
        if (result == DMDeliveryState.sent) {
          await _outbox.remove(owner, room, message.id);
        } else {
          await _outbox.put(owner, room, message.id,
              message.copyWith(deliveryState: result).toLocalMap());
        }
        _updateOutgoing(room, message.copyWith(deliveryState: result));
      } catch (error) {
        if (_cancelledOutgoingIds.contains(message.id)) return;
        final failed = message.copyWith(deliveryState: DMDeliveryState.failed);
        try {
          await _outbox.put(owner, room, message.id, failed.toLocalMap());
        } catch (_) {}
        _updateOutgoing(room, failed);
        Logger.error('DM outgoing preparation failed: $error');
      } finally {
        if (_cancelledOutgoingIds.remove(packet.id)) {
          try {
            await _outbox.remove(owner, room, packet.id);
          } catch (_) {}
        }
        _sendingIds.remove(packet.id);
        if (mounted) setState(() => _uploadById.remove(packet.id));
        _scheduleUncertainRecovery();
      }
    }

    // Invoking immediately registers text commits in tap order. Image/file
    // preparation remains on its existing independent queues.
    unawaited(operation(persistInsideDispatch: isTextOnly));
  }

  void _scheduleUncertainRecovery() {
    if (!mounted ||
        _outboxRetry != null ||
        _accountInvalidated ||
        _isLeaving ||
        _directInteractionRestricted ||
        _appLifecycleState != AppLifecycleState.resumed) return;
    final retryable = _outgoing.values.where((message) =>
        message.deliveryState == DMDeliveryState.uncertain &&
        !_sendingIds.contains(message.id) &&
        (_outboxRetryAttempts[message.id] ?? 0) < 3);
    if (retryable.isEmpty) return;
    final attempt = retryable
        .map((m) => _outboxRetryAttempts[m.id] ?? 0)
        .reduce((a, b) => a < b ? a : b);
    final room = _activeConversationId;
    // A bounded foreground retry also recovers when connectivity returns without
    // a lifecycle event. Same IDs/ordered queues keep a late commit idempotent.
    _outboxRetry = Timer(Duration(seconds: 2 << attempt), () {
      _outboxRetry = null;
      if (!mounted ||
          _accountInvalidated ||
          _directInteractionRestricted ||
          room != _activeConversationId ||
          _appLifecycleState != AppLifecycleState.resumed) return;
      final pending = _outgoing.values
          .where((message) =>
              message.deliveryState == DMDeliveryState.uncertain &&
              !_sendingIds.contains(message.id) &&
              (_outboxRetryAttempts[message.id] ?? 0) < 3)
          .toList()
        ..sort((a, b) => -_compareMessagesDesc(a, b));
      for (final message in pending) {
        _outboxRetryAttempts.update(message.id, (n) => n + 1,
            ifAbsent: () => 1);
        _queueOutgoing(room, message, automatic: true);
      }
    });
  }

  Future<bool> _ensureSendRoom(String room, DMMessage message) async {
    if (!_canSendFor(message.senderId, room)) return false;
    if (_conversationExists == true) return true;
    final id = await _dmService.getOrCreateConversation(widget.otherUserId,
        postId: message.postId ??
            widget.originPostId ??
            (room.startsWith('anon_')
                ? room.split('_').skip(3).join('_').split('__').first
                : null),
        isOtherUserAnonymous: room.startsWith('anon_'),
        requestedConversationId: room);
    if (id != room || !_canSendFor(message.senderId, room)) return false;
    _conversationExists = true;
    if (mounted) {
      setState(() {});
      unawaited(_initializeMessagesStream(conversationId: room));
    }
    return true;
  }

  void _updateOutgoing(String room, DMMessage message) {
    if (!mounted || !_canSendFor(message.senderId, room)) return;
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index >= 0 &&
        _messages[index].serverCreatedAt != null &&
        _messages[index].deliveryState == DMDeliveryState.sent) return;
    // The transaction acknowledgement proves delivery but does not contain the
    // canonical timestamp. Keep the local ordering slot until the live object
    // arrives, instead of inserting a device-time "sent" item into sorted history.
    final displayed = message.deliveryState == DMDeliveryState.sent &&
            message.serverCreatedAt == null
        ? message.copyWith(deliveryState: DMDeliveryState.sending)
        : message;
    setState(() {
      _outgoing[message.id] = displayed;
      if (index >= 0) _messages[index] = displayed;
    });
  }

  Future<void> _restoreOutbox(String room) async {
    final owner = _currentUser?.uid;
    if (owner == null || !_restoredOutboxes.add(room)) return;
    try {
      final packets = await _outbox.load(owner, room);
      if (!mounted || !_canSendFor(owner, room)) return;
      final messages = packets
          .map(DMMessage.fromLocalMap)
          .where((m) => m.senderId == owner)
          .toList()
        ..sort((a, b) => -DMMessage.compareDescending(a, b));
      setState(() {
        for (final message in messages) {
          _outgoing.putIfAbsent(message.id, () => message);
        }
        final pending = _outgoing.values.toList()..sort(_compareMessagesDesc);
        _messages = _mergeRecentIntoAll(_messages, pending);
      });
      if (_isBlocked || _isBlockedBy) {
        _markUncertainMessagesFailedByBlock();
        return;
      }
      for (final message in messages) {
        if (!_directInteractionRestricted &&
            message.deliveryState != DMDeliveryState.failed)
          _queueOutgoing(room, message);
      }
    } catch (error) {
      _restoredOutboxes.remove(room);
      Logger.error('DM outbox restore failed: $error');
    }
  }

  ({GlobalKey key, double dy})? _captureMessageAnchor() {
    for (final message in _messages) {
      final key = _messageLayoutKeys[message.id];
      final box = key?.currentContext?.findRenderObject();
      if (key != null && box is RenderBox && box.attached) {
        final dy = box.localToGlobal(Offset.zero).dy;
        if (dy > 120 && dy < MediaQuery.sizeOf(context).height - 160) {
          return (key: key, dy: dy);
        }
      }
    }
    return null;
  }

  void _restoreMessageAnchor(({GlobalKey key, double dy})? anchor) {
    if (anchor == null ||
        !_scrollController.hasClients ||
        _scrollController.position.userScrollDirection != ScrollDirection.idle)
      return;
    final box = anchor.key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final delta = box.localToGlobal(Offset.zero).dy - anchor.dy;
    final position = _scrollController.position;
    final next = (position.pixels - delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((next - position.pixels).abs() > .5) _scrollController.jumpTo(next);
  }

  void _followLatest({bool wasNearLatest = false}) {
    if (!_scrollController.hasClients ||
        _followingLatest ||
        _scrollController.position.userScrollDirection !=
            ScrollDirection.idle ||
        (!wasNearLatest && _scrollController.offset > 100)) return;
    final target = _scrollController.position.minScrollExtent;
    if ((_scrollController.offset - target).abs() < .5) return;
    _followingLatest = true;
    unawaited(_scrollController
        .animateTo(target,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic)
        .whenComplete(() => _followingLatest = false));
  }

  /// 차단 확인 다이얼로그
  Future<void> _showBlockConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.blockThisUser ?? ""),
        content: Text(AppLocalizations.of(context)!.blockConfirm ?? ""),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel ?? ""),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              AppLocalizations.of(context)!.block,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final ok = await ReportService.blockUser(widget.otherUserId);
        if (!mounted) return;

        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.userBlockedSuccess),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
          // 차단 즉시 DM 화면 종료 (접근 차단 UX + 심사 재현성)
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.userBlockFailed),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)!.error}: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 게시글 네비게이션 배너 빌드
  Widget _buildPostNavigationBanner() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width < 360 ? 12 : 16,
        vertical: 9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: DMColors.divider)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.article_outlined,
            color: DMColors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              (isChineseUi(context)
                  ? '此对话来自一条动态'
                  : Localizations.localeOf(context).languageCode == 'ko'
                      ? '이 대화는 포스트에서 시작되었습니다'
                      : 'This conversation started from a post'),
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                color: DMColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _navigateToPost(_conversation!.postId!),
            style: TextButton.styleFrom(
              foregroundColor: DMColors.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              (isChineseUi(context)
                  ? '查看动态'
                  : Localizations.localeOf(context).languageCode == 'ko'
                      ? '포스트 보기'
                      : 'View Post'),
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 게시글로 이동
  Future<void> _navigateToPost(String postId) async {
    try {
      // PostService를 사용하여 postId로 Post 객체 가져오기
      final post = await PostService().getPostById(postId);
      if (post != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailScreen(post: post),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text((isChineseUi(context)
                    ? '动态不存在'
                    : Localizations.localeOf(context).languageCode == 'ko'
                        ? '포스트를 찾을 수 없습니다'
                        : 'Post not found'))),
          );
        }
      }
    } catch (e) {
      Logger.error('포스트 로드 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text((isChineseUi(context)
                  ? '加载动态时出错'
                  : Localizations.localeOf(context).languageCode == 'ko'
                      ? '포스트를 불러오는 중 오류가 발생했습니다'
                      : 'An error occurred while loading the post'))),
        );
      }
    }
  }
}
