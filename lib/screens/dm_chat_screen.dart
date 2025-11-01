// lib/screens/dm_chat_screen.dart
// DM 대화 화면
// 메시지 목록과 입력창을 표시하고 실시간 메시지 전송/수신

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/conversation.dart';
import '../models/dm_message.dart';
import '../services/dm_service.dart';
import '../utils/time_formatter.dart';
import '../l10n/app_localizations.dart';
import 'package:intl/intl.dart';

// DM 전용 색상
class DMColors {
  static const myMessageBg = Color(0xFF4A90E2); // Primary blue
  static const myMessageText = Colors.white;
  static const otherMessageBg = Color(0xFFF0F0F0); // Light grey
  static const otherMessageText = Color(0xFF333333); // Dark grey
  static const inputBg = Color(0xFFF8F8F8);
  static const inputBorder = Color(0xFFE0E0E0);
}

class DMChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;

  const DMChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
  });

  @override
  State<DMChatScreen> createState() => _DMChatScreenState();
}

class _DMChatScreenState extends State<DMChatScreen> {
  final DMService _dmService = DMService();
  final _currentUser = FirebaseAuth.instance.currentUser;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  
  // 메시지 스트림은 initState에서 단 한 번만 생성하여
  // 입력 중 setState가 발생하더라도 재구독되지 않도록 고정한다.
  late final Stream<List<DMMessage>> _messagesStream;
  
  Conversation? _conversation;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 스트림 고정 (재구독 방지)
    _messagesStream = _dmService.getMessages(widget.conversationId);
    _loadConversation();
    _markAsRead();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 대화방 정보 로드
  Future<void> _loadConversation() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .get();
      
      if (doc.exists && mounted) {
        setState(() {
          _conversation = Conversation.fromFirestore(doc);
        });
      }
    } catch (e) {
      print('대화방 정보 로드 오류: $e');
    }
  }

  /// 읽음 처리
  Future<void> _markAsRead() async {
    await Future.delayed(const Duration(milliseconds: 500));
    await _dmService.markAsRead(widget.conversationId);
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context)!.dm)),
        body: Center(
          child: Text(AppLocalizations.of(context)!.loginRequired),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildInputArea(),
        ],
      ),
    );
  }

  /// AppBar 빌드
  PreferredSizeWidget _buildAppBar() {
    final otherUserName = _conversation?.getOtherUserName(_currentUser!.uid) ?? '';
    final otherUserPhoto = _conversation?.getOtherUserPhoto(_currentUser!.uid) ?? '';
    final isAnonymous = _conversation?.isOtherUserAnonymous(_currentUser!.uid) ?? false;
    
    final dmTitle = _conversation?.dmTitle;
    final primaryTitle = (dmTitle != null && dmTitle.isNotEmpty)
        ? dmTitle
        : (isAnonymous 
            ? AppLocalizations.of(context)!.anonymousUser 
            : otherUserName);
    final secondaryTitle = (dmTitle != null && dmTitle.isNotEmpty)
        ? AppLocalizations.of(context)!.author
        : null;

    String _formatHeaderDate() {
      final date = _conversation?.lastMessageTime ?? _conversation?.createdAt;
      if (date == null) return '';
      return DateFormat('yyyy.MM.dd').format(date);
    }

    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black87),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.grey[200],
            backgroundImage: !isAnonymous && otherUserPhoto.isNotEmpty
                ? NetworkImage(otherUserPhoto)
                : null,
            child: (!isAnonymous && otherUserPhoto.isNotEmpty)
                ? null
                : const Icon(Icons.person, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  primaryTitle,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (secondaryTitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondaryTitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (_conversation != null) ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                _formatHeaderDate(),
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.black87),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'block',
              child: Row(
                children: [
                  const Icon(Icons.block, size: 20, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.blockThisUser),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'block') {
              _showBlockConfirmation();
            }
          },
        ),
      ],
    );
  }

  /// 메시지 목록 빌드
  Widget _buildMessageList() {
    return StreamBuilder<List<DMMessage>>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.loadingMessages,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          print('❌ 메시지 로드 오류: ${snapshot.error}');
          
          // Permission denied 오류 감지
          final errorMessage = snapshot.error.toString();
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
                      '권한 오류',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Firebase Security Rules가 배포되지 않았거나\n권한이 없습니다.\n\n앱을 다시 시작해주세요.',
                      style: TextStyle(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          
          return Center(
            child: Text(
              '${AppLocalizations.of(context)!.error}: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final messages = snapshot.data ?? [];

        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.noMessages,
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          reverse: true,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isMine = message.isMine(_currentUser!.uid);
            
            // 같은 발신자의 연속 메시지인지 확인
            final isConsecutive = index < messages.length - 1 &&
                messages[index + 1].senderId == message.senderId;

            return _buildMessageBubble(message, isMine, isConsecutive);
          },
        );
      },
    );
  }

  /// 메시지 버블 빌드
  Widget _buildMessageBubble(DMMessage message, bool isMine, bool isConsecutive) {
    if (isMine) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: EdgeInsets.only(
            left: 60,
            right: 12,
            top: isConsecutive ? 2 : 8,
            bottom: 2,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: DMColors.myMessageBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message.text,
                style: const TextStyle(
                  color: DMColors.myMessageText,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    TimeFormatter.formatMessageTime(context, message.createdAt),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                  if (message.isRead) ...[
                    const SizedBox(width: 4),
                    Text(
                      AppLocalizations.of(context)!.read,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    } else {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
            left: 12,
            right: 60,
            top: isConsecutive ? 2 : 8,
            bottom: 2,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: DMColors.otherMessageBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: const TextStyle(
                  color: DMColors.otherMessageText,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                TimeFormatter.formatMessageTime(context, message.createdAt),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  /// 입력창 빌드
  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[200]!, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: DMColors.inputBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: DMColors.inputBorder, width: 0.5),
                ),
                child: TextField(
                  controller: _messageController,
                  maxLines: null,
                  maxLength: 500,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)!.typeMessage,
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 15),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: InputBorder.none,
                    counterText: '',
                  ),
                  style: const TextStyle(fontSize: 15, height: 1.4),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            
            const SizedBox(width: 8),
            
            // 전송 버튼 - DM 아이콘과 구분되는 상향 화살표 버튼
            InkWell(
              onTap: _messageController.text.trim().isEmpty ? null : _sendMessage,
              customBorder: const CircleBorder(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _messageController.text.trim().isEmpty
                      ? Colors.grey[300]
                      : DMColors.myMessageBg,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 메시지 전송
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLoading) return;

    setState(() => _isLoading = true);
    _messageController.clear();

    try {
      final success = await _dmService.sendMessage(widget.conversationId, text);
      
      if (success) {
        // 메시지 목록 맨 아래로 스크롤
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.messageSendFailed),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        // 실패 시 텍스트 복원
        _messageController.text = text;
      }
    } catch (e) {
      print('메시지 전송 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.error),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      _messageController.text = text;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 차단 확인 다이얼로그
  Future<void> _showBlockConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.blockThisUser),
        content: Text(AppLocalizations.of(context)!.blockConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
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
      // 차단 로직 구현 (향후 추가)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('차단 기능은 곧 추가됩니다')),
      );
    }
  }
}

