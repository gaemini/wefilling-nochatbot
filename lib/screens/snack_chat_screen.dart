import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:image_picker/image_picker.dart';

import '../models/snack_chat.dart';
import '../models/snack_chat_message.dart';
import '../services/cache/app_image_cache_manager.dart';
import '../services/snack_chat_active_conversation.dart';
import '../services/snack_chat_service.dart';
import '../services/storage_service.dart';
import '../services/user_info_cache_service.dart';
import '../ui/widgets/fullscreen_image_viewer.dart';
import '../utils/responsive_helper.dart';
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

class _SnackChatScreenState extends State<SnackChatScreen> {
  static const Color _chatBackground = Color(0xFFF4F5F3);
  static const Color _outgoingBubble = Color(0xFF344054);
  static const Color _incomingBubble = Color(0xFFFFFFFF);
  static const Color _secondaryText = Color(0xFF667085);
  static const Color _tertiaryText = Color(0xFF98A2B3);
  static const Color _composerBackground = Color(0xFF252629);
  static const Color _composerAction = Color(0xFF4B4E55);
  static const Color _composerActionDisabled = Color(0xFF36383D);

  final SnackChatService _snackChatService = SnackChatService();
  final StorageService _storageService = StorageService();
  final UserInfoCacheService _userInfoCache = UserInfoCacheService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isSending = false;
  bool _isUploadingImage = false;
  Timer? _autoMarkReadDebounce;
  bool _autoMarkReadInFlight = false;
  final Map<String, String> _senderNameCache = {};
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ─── 페이지네이션 상태 ───────────────────────────────────────────
  StreamSubscription<List<SnackChatMessage>>? _msgSub;
  StreamSubscription<DocumentSnapshot>? _roomSub;
  final List<SnackChatMessage> _messages = [];
  final Set<String> _messageIds = {};
  DateTime? _oldestMessageTime;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isInitialLoading = true; // 초기 로딩 상태 추가

  @override
  void initState() {
    super.initState();
    SnackChatActiveConversation.setActive(widget.snackChatId);
    _scrollController.addListener(_onScroll);
    _scheduleMarkAsRead();
    _subscribeToMessages();
    _subscribeToRoom();
  }

  /// DM의 _scheduleAutoMarkAsRead와 동일한 패턴 (250ms debounce)
  void _scheduleMarkAsRead() {
    if (!mounted) return;
    if (_autoMarkReadInFlight) return;
    _autoMarkReadDebounce?.cancel();
    _autoMarkReadDebounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      if (_autoMarkReadInFlight) return;
      _autoMarkReadInFlight = true;
      try {
        await _snackChatService.markAsRead(widget.snackChatId);
      } catch (_) {
        // best-effort
      } finally {
        _autoMarkReadInFlight = false;
      }
    });
  }

  void _subscribeToMessages() {
    _msgSub =
        _snackChatService.watchMessages(widget.snackChatId).listen((incoming) {
      if (!mounted) return;
      _scheduleMarkAsRead();
      setState(() {
        // 초기 로딩 완료
        _isInitialLoading = false;

        for (final m in incoming) {
          if (!_messageIds.contains(m.id)) {
            _messageIds.add(m.id);
            _messages.add(m);
          }
        }
        _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (_messages.isNotEmpty) {
          _oldestMessageTime = _messages.last.createdAt;
        }
      });
    });
  }

  /// 방 문서 실시간 감시: CF의 increment를 감지하면 즉시 다시 markAsRead 실행
  void _subscribeToRoom() {
    final uid = _uid;
    if (uid == null) return;
    _roomSub = FirebaseFirestore.instance
        .collection('snack_chats')
        .doc(widget.snackChatId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data();
      if (data == null) return;
      final unreadMap = data['unreadCount'] as Map<String, dynamic>? ?? {};
      final myUnread = unreadMap[uid];
      final v =
          myUnread is int ? myUnread : (myUnread is num ? myUnread.toInt() : 0);

      if (v > 0) {
        _scheduleMarkAsRead();
      }
    });
  }

  void _onScroll() {
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
        before: _oldestMessageTime,
      );
      if (!mounted) return;
      setState(() {
        for (final m in older) {
          if (!_messageIds.contains(m.id)) {
            _messageIds.add(m.id);
            _messages.add(m);
          }
        }
        if (older.isEmpty || older.length < 30) _hasMore = false;
        if (_messages.isNotEmpty) {
          _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _oldestMessageTime = _messages.last.createdAt;
        }
      });
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<String> _getSenderName(String senderId, String? senderName) async {
    if (senderName != null && senderName.isNotEmpty) return senderName;
    if (_senderNameCache.containsKey(senderId)) {
      return _senderNameCache[senderId]!;
    }
    final userInfo = await _userInfoCache.getUserInfo(senderId);
    final name =
        (userInfo?.nickname.isNotEmpty == true) ? userInfo!.nickname : senderId;
    _senderNameCache[senderId] = name;
    return name;
  }

  @override
  void dispose() {
    _autoMarkReadDebounce?.cancel();
    _roomSub?.cancel();
    if (SnackChatActiveConversation.isActive(widget.snackChatId)) {
      SnackChatActiveConversation.setActive(null);
    }
    _msgSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      final ok = await _snackChatService.sendMessage(widget.snackChatId, text);
      if (ok && mounted) {
        _messageController.clear();
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_isUploadingImage || _isSending) return;
    final uid = _uid;
    if (uid == null) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 88,
      );
      if (picked == null) return;

      setState(() => _isUploadingImage = true);
      final imageUrl = await _storageService.uploadDmImage(
        File(picked.path),
        userId: uid,
        conversationId: widget.snackChatId,
      );
      if (imageUrl == null || imageUrl.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지 업로드에 실패했습니다.')),
        );
        return;
      }

      final ok = await _snackChatService.sendImageMessage(
        widget.snackChatId,
        imageUrl: imageUrl,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지 전송에 실패했습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return StreamBuilder<SnackChat?>(
      stream: _snackChatService.watchSnackChat(widget.snackChatId),
      builder: (context, roomSnap) {
        final room = roomSnap.data;
        if (room == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('대화방을 찾을 수 없습니다.')),
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
              toolbarHeight: context.rh(50, min: 48, max: 52),
              leadingWidth: 46,
              centerTitle: false,
              titleSpacing: 0,
              iconTheme: IconThemeData(
                color: const Color(0xFF111827),
                size: context.ri(20).clamp(19, 21).toDouble(),
              ),
              title: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.2,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        room.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize:
                              context.rf(15.5).clamp(14.5, 16.5).toDouble(),
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                        ),
                      ),
                    ),
                    SizedBox(width: context.rs(6).clamp(4, 7).toDouble()),
                    Text(
                      '${room.participantCount}',
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: context.rf(13).clamp(12, 14).toDouble(),
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SnackChatInfoScreen(snackChatId: room.id),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.menu_rounded,
                    color: Color(0xFF344054),
                  ),
                  iconSize: context.ri(20).clamp(19, 21).toDouble(),
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: isKo ? '채팅방 정보' : 'Chat information',
                ),
                SizedBox(width: context.rs(2).clamp(0, 4).toDouble()),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: _isInitialLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: _secondaryText,
                              ),
                            )
                          : _messages.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.chat_bubble_outline,
                                        size: context
                                            .ri(42)
                                            .clamp(38, 46)
                                            .toDouble(),
                                        color: _tertiaryText,
                                      ),
                                      SizedBox(height: context.rs(10)),
                                      Text(
                                        isKo
                                            ? '아직 메시지가 없습니다.\n첫 메시지를 보내보세요!'
                                            : 'No messages yet.\nSend the first message!',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontFamily: 'Pretendard',
                                          fontSize: context
                                              .rf(14)
                                              .clamp(13, 15)
                                              .toDouble(),
                                          color: _secondaryText,
                                          height: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  controller: _scrollController,
                                  reverse: true,
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  scrollCacheExtent:
                                      const ScrollCacheExtent.viewport(1.25),
                                  padding: EdgeInsets.fromLTRB(
                                    context.rs(10).clamp(8, 14).toDouble(),
                                    context.rs(10).clamp(8, 14).toDouble(),
                                    context.rs(10).clamp(8, 14).toDouble(),
                                    context.rs(6).clamp(4, 8).toDouble(),
                                  ),
                                  itemCount:
                                      _messages.length + (_hasMore ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    // 맨 아래(오래된 쪽)에 로딩 인디케이터
                                    if (index == _messages.length) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        child: Center(
                                          child: _isLoadingMore
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: _secondaryText,
                                                  ),
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      );
                                    }
                                    final msg = _messages[index];
                                    final isMe = msg.senderId == _uid;

                                    // 날짜 구분선 표시 여부
                                    final bool showDateDivider =
                                        _shouldShowDateDivider(index);

                                    final String timeText =
                                        _formatTime(msg.createdAt);
                                    final groupedWithNewer = index > 0 &&
                                        shouldGroupSnackChatMessages(
                                          msg,
                                          _messages[index - 1],
                                        );
                                    final groupedWithOlder =
                                        index < _messages.length - 1 &&
                                            shouldGroupSnackChatMessages(
                                              msg,
                                              _messages[index + 1],
                                            );
                                    final showTimeText = !groupedWithNewer;
                                    final showSenderName =
                                        !isMe && !groupedWithOlder;

                                    return Column(
                                      children: [
                                        // 날짜 구분선
                                        if (showDateDivider)
                                          _buildDateDivider(msg.createdAt),
                                        // 메시지 버블
                                        _buildMessageBubble(
                                          message: msg,
                                          isMe: isMe,
                                          timeText: timeText,
                                          showTimeText: showTimeText,
                                          showSenderName: showSenderName,
                                          groupedWithNewer: groupedWithNewer,
                                          groupedWithOlder: groupedWithOlder,
                                        ),
                                      ],
                                    );
                                  },
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
              child: DecoratedBox(
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
                        tooltip: isKo ? '이미지 첨부' : 'Attach image',
                        onPressed: _isUploadingImage ? null : _pickAndSendImage,
                        enabledColor: _composerAction,
                        disabledColor: _composerActionDisabled,
                        child: _isUploadingImage
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                Icons.add_rounded,
                                size: context.ri(24).clamp(22, 25).toDouble(),
                                color: Colors.white,
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
                              maxLines: 4,
                              minLines: 1,
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
                          final canSend =
                              value.text.trim().isNotEmpty && !_isSending;
                          return AnimatedOpacity(
                            opacity: canSend || _isSending ? 1 : 0.45,
                            duration: const Duration(milliseconds: 150),
                            child: _buildComposerButton(
                              width: sendWidth,
                              height: actionExtent,
                              radius: actionExtent / 2,
                              tooltip: isKo ? '전송' : 'Send',
                              onPressed: canSend ? _send : null,
                              enabledColor: _composerAction,
                              disabledColor: _composerActionDisabled,
                              child: _isSending
                                  ? const SizedBox.square(
                                      dimension: 17,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      Icons.arrow_upward_rounded,
                                      size: context
                                          .ri(21)
                                          .clamp(19, 22)
                                          .toDouble(),
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
    final hasImage = message.imageUrl != null && message.imageUrl!.isNotEmpty;
    final hasText = message.text.trim().isNotEmpty;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth =
        (screenWidth * (hasImage ? 0.70 : 0.68)).clamp(150.0, 420.0).toDouble();
    final horizontalPadding = context.rs(2).clamp(0, 4).toDouble();
    final bottomSpacing = groupedWithNewer ? 3.0 : 10.0;
    final bubblePadding = EdgeInsets.fromLTRB(
      hasImage ? 6 : 12,
      hasImage ? 6 : 9,
      hasImage ? 6 : 12,
      hasImage ? 6 : 9,
    );
    final textStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: context.rf(14).clamp(13.5, 15).toDouble(),
      fontWeight: FontWeight.w600,
      height: 1.35,
      color: isMe ? Colors.white : const Color(0xFF111827),
    );
    final bubbleRadius = BorderRadius.only(
      topLeft: Radius.circular(!isMe && groupedWithOlder ? 6 : 16),
      topRight: Radius.circular(isMe && groupedWithOlder ? 6 : 16),
      bottomLeft: Radius.circular(!isMe && groupedWithNewer ? 6 : 16),
      bottomRight: Radius.circular(isMe && groupedWithNewer ? 6 : 16),
    );

    if (isMe) {
      // 내 메시지: 시간이 왼쪽에 표시
      return Padding(
        padding: EdgeInsets.only(
          bottom: bottomSpacing,
          left: horizontalPadding,
          right: horizontalPadding,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 시간 표시 (왼쪽)
            if (showTimeText)
              Padding(
                padding: const EdgeInsets.only(right: 5, bottom: 2),
                child: Text(
                  timeText,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: context.rf(10.5).clamp(10, 11.5).toDouble(),
                    fontWeight: FontWeight.w600,
                    color: _tertiaryText,
                  ),
                ),
              ),
            // 메시지 버블
            Flexible(
              child: Container(
                padding: bubblePadding,
                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                decoration: BoxDecoration(
                  color: _outgoingBubble,
                  borderRadius: bubbleRadius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasImage)
                      _buildImageBubble(
                        message: message,
                        isMe: true,
                      ),
                    if (hasImage && hasText) const SizedBox(height: 8),
                    if (hasText)
                      Text(
                        message.text,
                        style: textStyle,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // 상대방 메시지: 이름 위에, 시간이 오른쪽에 표시
      return Padding(
        padding: EdgeInsets.only(
          bottom: bottomSpacing,
          left: horizontalPadding,
          right: horizontalPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ 이름 표시 (연속된 메시지면 첫 번째에만 표시)
            if (showSenderName)
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 4),
                child: FutureBuilder<String>(
                  future: _getSenderName(message.senderId, message.senderName),
                  initialData: message.senderName ?? message.senderId,
                  builder: (context, snap) => Text(
                    snap.data ?? message.senderId,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 메시지 버블
                Flexible(
                  child: Container(
                    padding: bubblePadding,
                    constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                    decoration: BoxDecoration(
                      color: _incomingBubble,
                      borderRadius: bubbleRadius,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasImage)
                          _buildImageBubble(
                            message: message,
                            isMe: false,
                          ),
                        if (hasImage && hasText) const SizedBox(height: 8),
                        if (hasText)
                          Text(
                            message.text,
                            style: textStyle,
                          ),
                      ],
                    ),
                  ),
                ),
                // 시간 표시 (오른쪽)
                if (showTimeText)
                  Padding(
                    padding: const EdgeInsets.only(left: 5, bottom: 2),
                    child: Text(
                      timeText,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: context.rf(10.5).clamp(10, 11.5).toDouble(),
                        fontWeight: FontWeight.w600,
                        color: _tertiaryText,
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

  Widget _buildImageBubble({
    required SnackChatMessage message,
    required bool isMe,
  }) {
    final imageUrl = message.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      return const SizedBox.shrink();
    }
    final heroTag = 'snack_chat_image_${widget.snackChatId}_${message.id}';

    return GestureDetector(
      onTap: () => _openImageViewer(imageUrl, heroTag: heroTag),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width * 0.7)
              .clamp(180.0, 380.0)
              .toDouble(),
          maxHeight: 320,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Hero(
            tag: heroTag,
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              cacheManager: AppImageCacheManager.instance,
              fit: BoxFit.contain,
              placeholder: (_, __) => Container(
                height: 132,
                width: 220,
                color: Colors.black12,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                height: 132,
                width: 220,
                color: Colors.black12,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: isMe ? Colors.white70 : Colors.black54,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openImageViewer(String imageUrl, {required String heroTag}) {
    showFullscreenImageViewer(
      context,
      imageUrls: [imageUrl],
      initialIndex: 0,
      heroTag: heroTag,
    );
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

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: context.rs(12).clamp(10, 14).toDouble(),
      ),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFFD9DDE3))),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.rs(10)),
            child: Text(
              dateText,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: context.rf(12).clamp(11, 12.5).toDouble(),
                fontWeight: FontWeight.w600,
                color: _secondaryText,
              ),
            ),
          ),
          const Expanded(child: Divider(color: Color(0xFFD9DDE3))),
        ],
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
