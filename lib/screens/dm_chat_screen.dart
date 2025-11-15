// lib/screens/dm_chat_screen.dart
// DM 대화 화면
// 메시지 목록과 입력창을 표시하고 실시간 메시지 전송/수신

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/conversation.dart';
import '../models/dm_message.dart';
import '../services/dm_service.dart';
import '../services/post_service.dart';
import '../utils/time_formatter.dart';
import '../l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'post_detail_screen.dart';

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
  
  // 대화방이 없을 수 있으므로 초기에 스트림을 구독하지 않는다.
  Stream<List<DMMessage>>? _messagesStream;
  bool _conversationExists = false;
  
  Conversation? _conversation;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initConversationState();
  }
  Future<void> _initConversationState() async {
    try {
      print('🚀 대화방 초기화: ${widget.conversationId}');
      
      // conversationId 형식 확인
      print('🔍 대화방 ID 확인: ${widget.conversationId}');
      print('🔍 상대방 ID: ${widget.otherUserId}');
      
      // Firebase Auth UID 형식 검증 (20~30자 영숫자, 언더스코어 포함 가능)
      final uidPattern = RegExp(r'^[a-zA-Z0-9_-]{20,30}$');
      if (!uidPattern.hasMatch(widget.otherUserId)) {
        print('❌ 잘못된 userId 형식: ${widget.otherUserId} (길이: ${widget.otherUserId.length}자)');
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('이 사용자에게는 메시지를 보낼 수 없습니다'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // DM conversation ID 형식 검증 (타임스탬프 포함 형식도 지원)
      final validIdPattern = RegExp(r'^(anon_)?[a-zA-Z0-9_-]+_[a-zA-Z0-9_-]+(_[a-zA-Z0-9_-]+)?(_\d{13})?(__\d+)?$');
      if (!validIdPattern.hasMatch(widget.conversationId)) {
        print('❌ 잘못된 conversation ID 형식: ${widget.conversationId}');
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${AppLocalizations.of(context)!.error}: 잘못된 대화방 ID입니다'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      final conv = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .get();
      
      _conversationExists = conv.exists;
      
      // 대화방이 존재하지 않으면 메시지 전송 시까지 대기
      if (!_conversationExists) {
        print('📝 대화방이 존재하지 않음 - 메시지 전송 시까지 대기: ${widget.conversationId}');
        
        // 본인 DM 체크
        if (widget.otherUserId == _currentUser?.uid) {
          print('❌ 본인 DM 생성 시도 차단');
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('본인에게는 메시지를 보낼 수 없습니다'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }
        
        // 대화방이 없으면 생성하지 않고 대기 상태로 설정
        print('📝 대화방 미생성 상태 - 첫 메시지 전송 시 생성됨');
      }
      
      // 참여자 확인 및 재입장 처리 (대화방이 이미 존재했던 경우에만)
      if (_conversationExists && conv.exists) {
        final data = conv.data() as Map<String, dynamic>;
        final participants = List<String>.from(data['participants'] ?? []);
        
        // 본인이 본인에게 보낸 DM 체크
        final isSelfDM = participants.length == 2 && 
                        participants[0] == _currentUser?.uid && 
                        participants[1] == _currentUser?.uid;
        
        if (isSelfDM) {
          print('❌ 본인 DM은 허용되지 않음');
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('본인에게는 메시지를 보낼 수 없습니다'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }
        
        if (!participants.contains(_currentUser?.uid)) {
          print('❌ 대화방 참여자가 아님');
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${AppLocalizations.of(context)!.error}: 대화방 참여자가 아닙니다'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }

        // 🔁 마지막 액션이 "나가기"인 경우에만 재입장 처리
        final userLeftAt = (data['userLeftAt'] as Map<String, dynamic>? ?? {});
        final rejoinedAt = (data['rejoinedAt'] as Map<String, dynamic>? ?? {});
        
        if (_currentUser != null && userLeftAt[_currentUser!.uid] != null) {
          final leftTimestamp = userLeftAt[_currentUser!.uid] as Timestamp?;
          final rejoinTimestamp = rejoinedAt[_currentUser!.uid] as Timestamp?;
          
          if (leftTimestamp != null) {
            final leftTime = leftTimestamp.toDate();
            final rejoinTime = rejoinTimestamp?.toDate();
            
            // 마지막 액션이 "나가기"인 경우에만 재입장 처리
            if (rejoinTime == null || leftTime.isAfter(rejoinTime)) {
              print('🔁 마지막 액션이 "나가기" → 재입장 처리 실행');
              await _dmService.rejoinConversation(widget.conversationId);
            } else {
              print('✅ 이미 재입장 상태 → 재입장 처리 스킵');
            }
          }
        }
      }
      
      // 대화방이 존재하면 정상 진행 (재입장 기록 후 메시지 스트림 초기화)
      await _initializeMessagesStream();
      if (mounted) setState(() {});
      await _loadConversation();
      await _markAsRead();
    } catch (e) {
      print('대화 초기화 오류: $e');
      print('오류 상세: ${e.runtimeType} - ${e.toString()}');
      // 권한 오류인 경우 뒤로가기
      if (e.toString().contains('permission-denied')) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${AppLocalizations.of(context)!.error}: 접근 권한이 없습니다'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
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

  /// 메시지 스트림 초기화
  /// - 기본: 전체 대화 표시(일반 진입)
  /// - 예외: 사용자가 실제로 '채팅방 나가기'를 한 기록이 있으면, 그 시점 이후만 표시
  Future<void> _initializeMessagesStream({String? conversationId}) async {
    try {
      final targetConversationId = conversationId ?? widget.conversationId;
      print('📱 메시지 스트림 초기화:');
      print('  - 대상 conversationId: $targetConversationId');

      // 사용자가 실제로 '나가기'를 한 적이 있으면 해당 시점 이후만 표시
      final visibilityStartTime = await _dmService.getUserMessageVisibilityStartTime(targetConversationId);
      print('  - 가시성 시작 시간(leave 기록 기반): $visibilityStartTime');

      _messagesStream = _dmService.getMessages(
        targetConversationId,
        visibilityStartTime: visibilityStartTime, // null이면 전체 표시
      );
    } catch (e) {
      print('메시지 스트림 초기화 실패: $e');
      final targetConversationId = conversationId ?? widget.conversationId;
      _messagesStream = _dmService.getMessages(targetConversationId);
    }
  }

  /// 읽음 처리
  Future<void> _markAsRead() async {
    print('📖 읽음 처리 시작: ${widget.conversationId}');
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      await _dmService.markAsRead(widget.conversationId);
      print('✅ 읽음 처리 완료: ${widget.conversationId}');
      
      // UI 강제 업데이트를 위해 스트림 재초기화
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 100));
        print('🔄 스트림 리스너 업데이트 트리거');
      }
    } catch (e) {
      print('⚠️ 읽음 처리 중 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context)!.dm ?? "")),
        body: Center(
          child: Text(AppLocalizations.of(context)!.loginRequired ?? ""),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // 익명 게시글 DM인 경우에만 게시글로 돌아가기 배너 추가
          if (_conversation != null && 
              _conversation!.postId != null && 
              _conversation!.postId!.isNotEmpty &&
              _conversation!.isOtherUserAnonymous(_currentUser!.uid))
            _buildPostNavigationBanner(),
          Expanded(child: _buildMessageList()),
          _buildInputArea(),
        ],
      ),
    );
  }

  /// AppBar 타이틀 빌드
  Widget _buildAppBarTitle(String otherUserId, bool isAnonymous, bool hasCustomTitle, String? dmTitle) {
    // 익명이 아닌 경우 실시간 프로필 조회
    if (!isAnonymous && !hasCustomTitle) {
      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(otherUserId).get(),
        builder: (context, userSnapshot) {
          // 로딩 중이거나 오류가 있어도 기본 정보로 표시
          String displayName;
          String photoUrl;
          
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            // 로딩 중: 대화방에 저장된 이름 사용
            displayName = _conversation?.getOtherUserName(_currentUser!.uid) ?? 'Loading...';
            photoUrl = _conversation?.getOtherUserPhoto(_currentUser!.uid) ?? '';
          } else if (userSnapshot.hasData && userSnapshot.data!.exists) {
            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
            // 닉네임 우선, 없으면 displayName 사용
            displayName = userData?['nickname'] ?? userData?['displayName'] ?? 'Unknown';
            photoUrl = userData?['photoURL'] ?? '';
          } else {
            // 프로필 조회 실패 시 대화방에 저장된 이름 사용
            displayName = _conversation?.getOtherUserName(_currentUser!.uid) ?? 'Unknown';
            photoUrl = _conversation?.getOtherUserPhoto(_currentUser!.uid) ?? '';
          }

          return Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey[200],
                backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                child: photoUrl.isNotEmpty ? null : const Icon(Icons.person, size: 20),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      );
    } else {
      // 익명이거나 커스텀 타이틀이 있는 경우
      return Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.grey[200],
            child: const Icon(Icons.person, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasCustomTitle
                      ? '${AppLocalizations.of(context)!.topic}: $dmTitle'
                      : 'Anonymous',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasCustomTitle) ...[
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context)!.author ?? "",
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
      );
    }
  }

  /// AppBar 빌드
  PreferredSizeWidget _buildAppBar() {
    final otherUserId = widget.otherUserId;
    final isAnonymous = _conversation?.isOtherUserAnonymous(_currentUser!.uid) ?? false;
    
    final dmTitle = _conversation?.dmTitle;
    final hasCustomTitle = dmTitle != null && dmTitle.isNotEmpty;

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
      title: _buildAppBarTitle(otherUserId, isAnonymous, hasCustomTitle, dmTitle),
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
                  Text(AppLocalizations.of(context)!.blockThisUser ?? ""),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline, size: 20),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.leaveChatRoom),
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
  }


  /// 나가기 확인 다이얼로그
  Future<void> _confirmLeaveConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          Localizations.localeOf(context).languageCode == 'ko'
              ? AppLocalizations.of(context)!.leaveChatRoom
              : 'Leave chat',
        ),
        content: Text(
          Localizations.localeOf(context).languageCode == 'ko'
              ? '이 채팅방에서 나가시겠습니까?'
              : 'Are you sure you want to leave this chat?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel ?? ""),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              Localizations.localeOf(context).languageCode == 'ko' ? '나가기' : 'Leave',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
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
          _messagesStream = null; // StreamBuilder가 기존 구독을 해제함
        });
      }

      await _dmService.leaveConversation(widget.conversationId);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localizations.localeOf(context).languageCode == 'ko'
                ? '채팅방에서 나갔습니다. 다시 메시지를 보내면 이전 대화 내역은 보이지 않습니다.'
                : 'You left the chat. Previous messages will not be visible if you send a new message.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      print('대화방 나가기 오류: $e');
      
      // 오류가 발생해도 사용자에게는 성공적으로 나간 것처럼 처리 (인스타그램 방식)
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localizations.localeOf(context).languageCode == 'ko'
                ? '채팅방에서 나갔습니다'
                : 'You left the chat',
          ),
        ),
      );
    }
  }

  /// 메시지 목록 빌드
  Widget _buildMessageList() {
    if (_messagesStream == null) {
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

    return StreamBuilder<List<DMMessage>>(
      stream: _messagesStream!,
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
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
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
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
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
      // 실제로 메시지를 보낼 conversationId를 결정
      String actualConversationId = widget.conversationId;
      
      // 대화방이 존재하지 않으면 첫 메시지 전송 시 생성
      if (!_conversationExists) {
        print('📝 첫 메시지 전송 - 대화방 생성 시도');
        print('📝 기존 conversationId: ${widget.conversationId}');
        
        // conversationId에서 익명 여부와 postId 추출
        final isAnonymousConv = widget.conversationId.startsWith('anon_');
        String? postId;
        if (isAnonymousConv) {
          final parts = widget.conversationId.split('_');
          if (parts.length >= 4) {
            postId = parts.sublist(3).join('_');
            // __timestamp 형식의 접미사 제거
            if (postId.contains('__')) {
              postId = postId.split('__').first;
            }
          }
        }
        
        final newConversationId = await _dmService.getOrCreateConversation(
          widget.otherUserId,
          postId: postId,
          isOtherUserAnonymous: isAnonymousConv,
        );
        
        if (newConversationId == null) {
          print('❌ 대화방 생성 실패');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.cannotSendDM ?? ""),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          _messageController.text = text; // 메시지 복원
          return;
        }
        
        print('✅ 대화방 생성 성공: $newConversationId');
        print('📝 생성된 conversationId와 기존 ID 비교:');
        print('   - 생성된 ID: $newConversationId');
        print('   - 기존 ID: ${widget.conversationId}');
        print('   - 일치 여부: ${newConversationId == widget.conversationId}');
        
        // ✅ 수정: 새로 생성된 conversationId를 사용
        actualConversationId = newConversationId;
        _conversationExists = true;
      }
      
      print('📤 메시지 전송 시도: conversationId=$actualConversationId');
      final success = await _dmService.sendMessage(actualConversationId, text);
      print('📤 메시지 전송 결과: success=$success');
      
      if (success) {
        print('✅ 메시지 전송 성공 - 후속 처리 시작');
        
        // 첫 메시지 전송 시 대화방이 없었다면 생성 되었으므로 스트림을 초기화
        if (_messagesStream == null) {
          print('📱 메시지 스트림이 null - 초기화 시작 (actualConversationId 사용)');
          print('⚠️  첫 메시지 전송이므로 가시성 필터 없이 스트림 초기화');
          
          // 첫 메시지 전송 직후에는 가시성 필터를 적용하지 않음
          // (방금 보낸 메시지가 필터링되는 것을 방지)
          _messagesStream = _dmService.getMessages(
            actualConversationId,
            visibilityStartTime: null,  // 가시성 필터 없이 모든 메시지 표시
          );
          
          if (mounted) {
            setState(() {});
            print('✅ setState 호출 완료 - UI 업데이트 예정');
          }
        }
        if (_conversation == null) {
          print('📖 대화방 정보 로드 시작');
          await _loadConversation();
        }
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
              content: Text(AppLocalizations.of(context)!.messageSendFailed ?? ""),
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
            content: Text(AppLocalizations.of(context)!.error ?? ""),
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
      // 차단 로직 구현 (향후 추가)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('차단 기능은 곧 추가됩니다')),
      );
    }
  }

  /// 게시글 네비게이션 배너 빌드
  Widget _buildPostNavigationBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.article_outlined,
            color: Colors.blue.shade700,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.conversationStartedFromPost,
              style: TextStyle(
                color: Colors.blue.shade700,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _navigateToPost(_conversation!.postId!),
            style: TextButton.styleFrom(
              foregroundColor: Colors.blue.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              AppLocalizations.of(context)!.viewPost,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
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
            SnackBar(content: Text(AppLocalizations.of(context)!.postNotFound)),
          );
        }
      }
    } catch (e) {
      print('게시글 로드 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.postLoadError)),
        );
      }
    }
  }
}

