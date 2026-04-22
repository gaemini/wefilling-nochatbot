import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/snack_chat.dart';
import '../models/snack_chat_message.dart';
import '../services/cache/app_image_cache_manager.dart';
import '../services/snack_chat_active_conversation.dart';
import '../services/snack_chat_service.dart';
import '../utils/logger.dart';
import '../services/storage_service.dart';
import '../services/user_info_cache_service.dart';
import '../ui/widgets/fullscreen_image_viewer.dart';
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
  bool _isInitialLoading = true;

  // build()마다 새 stream을 생성하면 매 setState마다 Firestore 리스너가
  // 등록/해제를 반복해 SDK 내부 상태가 불안정해진다.
  // initState에서 한 번만 생성하고 재사용한다.
  late final Stream<SnackChat?> _roomStream;
  Timer? _initialLoadingTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _roomStream = _snackChatService.watchSnackChat(widget.snackChatId);
    SnackChatActiveConversation.setActive(widget.snackChatId);
    _scrollController.addListener(_onScroll);
    _scheduleMarkAsRead();
    _subscribeToMessages();
    _subscribeToRoom();

    // 방어 코드: stream이 영원히 첫 이벤트를 내보내지 않는 경우
    // (네트워크 단절, Firestore 재연결 지연 등) 로딩 상태 해제
    _initialLoadingTimeoutTimer = Timer(const Duration(seconds: 12), () {
      if (mounted && _isInitialLoading) {
        setState(() => _isInitialLoading = false);
        Logger.warning('⚠️ [SnackChat] 초기 로딩 타임아웃 → 강제 해제');
      }
    });
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
    _msgSub = _snackChatService
        .watchMessages(widget.snackChatId)
        .listen(
      (incoming) {
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
      },
      onError: (e) {
        // 메시지 스트림 오류 시 _isInitialLoading 을 반드시 해제
        // 해제하지 않으면 화면이 무한 로딩 상태에 고정됨
        Logger.error('메시지 스트림 오류: $e');
        if (mounted) {
          setState(() {
            _isInitialLoading = false;
          });
        }
      },
    );
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
      final v = myUnread is int ? myUnread : (myUnread is num ? myUnread.toInt() : 0);
      
      // 🔍 디버깅: unreadCount 값 로깅
      print('🔔 [SnackChat] Room 문서 업데이트 감지:');
      print('  - snackChatId: ${widget.snackChatId}');
      print('  - myUnread: $v');
      print('  - lastMessage: ${data['lastMessage']}');
      print('  - lastMessageSenderId: ${data['lastMessageSenderId']}');
      
      if (v > 0) {
        print('  ⚠️ unreadCount > 0 감지, markAsRead 예약');
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
    // ✅ users 컬렉션을 기본 소스로 사용 → 닉네임 변경 시 자동 반영
    // senderName(메시지 저장 시점 스냅샷)은 getUserInfo 실패 시 fallback으로만 사용
    if (_senderNameCache.containsKey(senderId)) {
      return _senderNameCache[senderId]!;
    }
    final userInfo = await _userInfoCache.getUserInfo(senderId);
    final name = (userInfo?.nickname.isNotEmpty == true)
        ? userInfo!.nickname
        : (senderName?.isNotEmpty == true ? senderName! : senderId);
    _senderNameCache[senderId] = name;
    return name;
  }

  @override
  void dispose() {
    _initialLoadingTimeoutTimer?.cancel();
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
      stream: _roomStream,
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
          backgroundColor: const Color(0xFFFF9A47),
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            centerTitle: true,
            titleSpacing: 0,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  room.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  isKo
                      ? '${room.participantCount}명 참여'
                      : '${room.participantCount} Participants',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SnackChatInfoScreen(snackChatId: room.id),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.menu,
                  color: AppColors.pointColor,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: _isInitialLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline,
                                  size: 64,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  isKo
                                      ? '아직 메시지가 없습니다.\n첫 메시지를 보내보세요!'
                                      : 'No messages yet.\nSend the first message!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 14,
                                    color: Colors.grey.shade500,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                            itemCount: _messages.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              // 맨 아래(오래된 쪽)에 로딩 인디케이터
                              if (index == _messages.length) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: _isLoadingMore
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                );
                              }
                              final msg = _messages[index];
                              final isMe = msg.senderId == _uid;
                              
                              // 날짜 구분선 표시 여부
                              final bool showDateDivider = _shouldShowDateDivider(index);
                              
                              // 시간 표시 로직
                              final String timeText = _formatTime(msg.createdAt);
                              
                              // ✅ 시간 표시 로직: 이전 메시지와 시간이 다르거나 발신자가 다를 때만 표시
                              bool showTimeText = false;
                              if (index > 0) {
                                final prevMsg = _messages[index - 1];
                                final String prevTimeText = _formatTime(prevMsg.createdAt);
                                // 시간이 바뀌거나 발신자가 바뀌면 시간 표시
                                showTimeText = timeText != prevTimeText || prevMsg.senderId != msg.senderId;
                              } else {
                                // 가장 최근 메시지는 항상 시간 표시
                                showTimeText = true;
                              }
                              
                              // ✅ 이름 표시 로직: 이전 메시지와 발신자가 다르면 이름 표시
                              final bool showSenderName = index == _messages.length - 1 || // 맨 처음 메시지
                                  _messages[index + 1].senderId != msg.senderId; // 이전 메시지가 다른 사용자
                              
                              return Column(
                                children: [
                                  // 날짜 구분선
                                  if (showDateDivider) _buildDateDivider(msg.createdAt),
                                  // 메시지 버블
                                  _buildMessageBubble(
                                    message: msg,
                                    isMe: isMe,
                                    timeText: timeText,
                                    showTimeText: showTimeText,
                                    showSenderName: showSenderName,
                                  ),
                                ],
                              );
                            },
                          ),
              ),
              // 하단 입력창 영역 (흰색 배경)
              Container(
                color: Colors.white,
                child: SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    color: Colors.white,
                    child: Row(
                    children: [
                      IconButton(
                        onPressed: _isUploadingImage ? null : _pickAndSendImage,
                        icon: _isUploadingImage
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_circle, size: 30),
                        color: AppColors.pointColor,
                        tooltip: isKo ? '이미지 첨부' : 'Attach image',
                      ),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          maxLines: 4,
                          minLines: 1,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText:
                                isKo ? '메시지를 입력하세요...' : 'Type a message...',
                            filled: true,
                            fillColor: const Color(0xFFF3F4F6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        onPressed: _isSending ? null : _send,
                        backgroundColor: AppColors.pointColor,
                        child: _isSending
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send_rounded,
                                color: Colors.white),
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
      },
    );
  }

  Widget _buildMessageBubble({
    required SnackChatMessage message,
    required bool isMe,
    required String timeText,
    required bool showTimeText,
    required bool showSenderName,
  }) {
    final hasImage = message.imageUrl != null && message.imageUrl!.isNotEmpty;
    final hasText = message.text.trim().isNotEmpty;

    if (isMe) {
      // 내 메시지: 시간이 왼쪽에 표시
      return Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 60, right: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 시간 표시 (왼쪽)
            Visibility(
              visible: showTimeText,
              maintainAnimation: true,
              maintainSize: true,
              maintainState: true,
              child: Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 2),
                child: Text(
                  timeText,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            // 메시지 버블
            Flexible(
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  hasImage ? 8 : 12,
                  hasImage ? 8 : 10,
                  hasImage ? 8 : 12,
                  hasImage ? 8 : 10,
                ),
                constraints: const BoxConstraints(maxWidth: 290),
                decoration: BoxDecoration(
                  color: AppColors.pointColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
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
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
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
        padding: const EdgeInsets.only(bottom: 10, left: 12, right: 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ 이름 표시 (연속된 메시지면 첫 번째에만 표시)
            if (showSenderName)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: FutureBuilder<String>(
                  future: _getSenderName(message.senderId, message.senderName),
                  initialData: message.senderName ?? message.senderId,
                  builder: (context, snap) => Text(
                    snap.data ?? message.senderId,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
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
                    padding: EdgeInsets.fromLTRB(
                      hasImage ? 8 : 12,
                      hasImage ? 8 : 10,
                      hasImage ? 8 : 12,
                      hasImage ? 8 : 10,
                    ),
                    constraints: const BoxConstraints(maxWidth: 290),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
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
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // 시간 표시 (오른쪽)
                Visibility(
                  visible: showTimeText,
                  maintainAnimation: true,
                  maintainSize: true,
                  maintainState: true,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 2),
                    child: Text(
                      timeText,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Hero(
          tag: heroTag,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            cacheManager: AppImageCacheManager.instance,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              height: 140,
              width: 240,
              color: Colors.black12,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              height: 140,
              width: 240,
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
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                dateText,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  void _handlePushBackNavigation(SnackChat room) {
    if (room.isFavorited) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => MainScreen(initialGroupTabIndex: 1),
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
