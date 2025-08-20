import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/supported_language.dart';
import '../models/message.dart';
import '../services/chatbot_service.dart';
import '../services/chatbot_storage_service.dart';
import '../utils/chatbot_design_constants.dart';
import 'chatbot_language_selection_screen.dart';

class ChatbotScreen extends StatefulWidget {
  final SupportedLanguage? initialLanguage;
  
  const ChatbotScreen({super.key, this.initialLanguage});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatbotService _chatService = ChatbotService();
  final ChatbotStorageService _storageService = ChatbotStorageService();
  
  final List<Message> _messages = [];
  bool _isTyping = false;
  late SupportedLanguage _currentLanguage;

  @override
  void initState() {
    super.initState();
    _initializeLanguage();
  }

  void _initializeLanguage() async {
    await _storageService.initialize();
    if (widget.initialLanguage != null) {
      _currentLanguage = widget.initialLanguage!;
    } else {
      _currentLanguage = await _storageService.getLanguage();
    }
    _addInitialMessages();
  }

  void _addInitialMessages() {
    setState(() {
      // 초기 환영 메시지 추가
      _messages.add(
        Message.bot(
          content: _chatService.getInitialGreeting(_currentLanguage),
          language: _currentLanguage.code,
        ),
      );
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        Message.user(
          content: text,
          language: _currentLanguage.code,
        ),
      );
      _isTyping = true;
    });

    _messageController.clear();
    _scrollToBottom();

    // 실제 AI 서비스 호출
    _generateAIResponse(text);
  }

  /// Firebase Extensions Gemini API를 통한 실제 AI 응답 생성
  void _generateAIResponse(String query) async {
    try {
      // ChatService를 통해 응답 생성
      final responseStream = await _chatService.generateIntelligentResponse(
        query: query,
        language: _currentLanguage,
      );

      // 스트림으로부터 응답 받기
      responseStream.listen(
        (response) {
          if (mounted) {
            setState(() {
              _messages.add(
                Message.bot(
                  content: response,
                  language: _currentLanguage.code,
                ),
              );
              _isTyping = false;
            });
            _scrollToBottom();
          }
        },
        onError: (error) {
          print('AI 응답 생성 오류: $error');
          if (mounted) {
            setState(() {
              _messages.add(
                Message.bot(
                  content: _getErrorResponse(),
                  language: _currentLanguage.code,
                ),
              );
              _isTyping = false;
            });
            _scrollToBottom();
          }
        },
      );
    } catch (e) {
      print('AI 응답 호출 오류: $e');
      if (mounted) {
        setState(() {
          _messages.add(
            Message.bot(
              content: _getErrorResponse(),
              language: _currentLanguage.code,
            ),
          );
          _isTyping = false;
        });
        _scrollToBottom();
      }
    }
  }

  /// 오류 발생 시 응답 메시지
  String _getErrorResponse() {
    switch (_currentLanguage) {
      case SupportedLanguage.korean:
        return '죄송합니다. 응답을 생성하는 중에 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
      case SupportedLanguage.english:
        return 'Sorry, an error occurred while generating a response. Please try again in a moment.';
      case SupportedLanguage.chinese:
        return '抱歉，生成回复时发生错误。请稍后再试。';
      case SupportedLanguage.japanese:
        return '申し訳ございませんが、応答の生成中にエラーが発生しました。しばらくしてからもう一度お試しください。';
      case SupportedLanguage.french:
        return 'Désolé, une erreur s\'est produite lors de la génération d\'une réponse. Veuillez réessayer dans un moment.';
      case SupportedLanguage.russian:
        return 'Извините, произошла ошибка при генерации ответа. Пожалуйста, попробуйте еще раз через некоторое время.';
    }
  }

  void _changeLanguage() async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ChatbotLanguageSelectionScreen(),
      ),
    ).then((result) async {
      // 언어 변경 후 돌아왔을 때 처리
      final newLanguage = await _storageService.getLanguage();
      if (newLanguage != _currentLanguage) {
        setState(() {
          _currentLanguage = newLanguage;
          _messages.add(_createSystemMessage(
            _chatService.getLanguageSetupCompleteMessage(newLanguage),
          ));
        });
        _scrollToBottom();
      }
    });
  }

  Message _createSystemMessage(String content) {
    return Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isFromUser: false,
      timestamp: DateTime.now(),
      language: _currentLanguage.code,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: ChatbotDesignConstants.defaultAnimationDuration,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChatbotDesignConstants.backgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.school,
                color: ChatbotDesignConstants.primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _chatService.getAppTitle(_currentLanguage),
                  style: GoogleFonts.ptSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _chatService.getAppSubtitle(_currentLanguage),
                  style: GoogleFonts.ptSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: ChatbotDesignConstants.primaryColor,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.language),
            onSelected: (value) {
              if (value == 'change_language') {
                _changeLanguage();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'change_language',
                child: Row(
                  children: [
                    const Icon(Icons.language, size: 20),
                    const SizedBox(width: 8),
                    Text(_getChangeLanguageText()),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 메시지 목록
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(ChatbotDesignConstants.defaultPadding),
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length && _isTyping) {
                        return _buildTypingIndicator();
                      }
                      final message = _messages[index];
                      return _buildMessageBubble(message);
                    },
                  ),
          ),

          // 메시지 입력 영역
          _buildMessageInput(),
        ],
      ),
    );
  }

  String _getChangeLanguageText() {
    switch (_currentLanguage) {
      case SupportedLanguage.korean:
        return '언어 변경';
      case SupportedLanguage.english:
        return 'Change Language';
      case SupportedLanguage.chinese:
        return '更改语言';
      case SupportedLanguage.japanese:
        return '言語変更';
      case SupportedLanguage.french:
        return 'Changer de langue';
      case SupportedLanguage.russian:
        return 'Изменить язык';
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: ChatbotDesignConstants.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              size: 40,
              color: ChatbotDesignConstants.primaryColor,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _getStartChatText(),
            style: GoogleFonts.ptSans(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: ChatbotDesignConstants.primaryTextColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getStartChatSubtext(),
            textAlign: TextAlign.center,
            style: GoogleFonts.ptSans(
              fontSize: 14,
              color: ChatbotDesignConstants.secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  String _getStartChatText() {
    switch (_currentLanguage) {
      case SupportedLanguage.korean:
        return '채팅을 시작해보세요!';
      case SupportedLanguage.english:
        return 'Start chatting!';
      case SupportedLanguage.chinese:
        return '开始聊天吧！';
      case SupportedLanguage.japanese:
        return 'チャットを始めましょう！';
      case SupportedLanguage.french:
        return 'Commencez à chatter!';
      case SupportedLanguage.russian:
        return 'Начните чат!';
    }
  }

  String _getStartChatSubtext() {
    switch (_currentLanguage) {
      case SupportedLanguage.korean:
        return '한양대학교 ERICA에 대해\n궁금한 것을 물어보세요';
      case SupportedLanguage.english:
        return 'Ask anything about\nHanyang University ERICA';
      case SupportedLanguage.chinese:
        return '询问关于汉阳大学ERICA\n的任何问题';
      case SupportedLanguage.japanese:
        return '漢陽大学ERICAについて\n何でもお聞きください';
      case SupportedLanguage.french:
        return 'Posez des questions sur\nl\'Université Hanyang ERICA';
      case SupportedLanguage.russian:
        return 'Задавайте вопросы о\nУниверситете Ханъян ERICA';
    }
  }

  Widget _buildMessageBubble(Message message) {
    final isUser = message.isFromUser;
    final isSystem = _isSystemMessage(message);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: ChatbotDesignConstants.smallPadding),
      child: isSystem 
          ? _buildSystemMessageBubble(message)
          : _buildUserOrBotMessageBubble(message, isUser),
    );
  }

  bool _isSystemMessage(Message message) {
    // 시스템 메시지인지 확인하는 로직
    return message.content.contains('설정되었습니다') ||
           message.content.contains('Language set to') ||
           message.content.contains('语言已设置') ||
           message.content.contains('に設定されました') ||
           message.content.contains('définie en') ||
           message.content.contains('установлен на');
  }

  Widget _buildSystemMessageBubble(Message message) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ChatbotDesignConstants.defaultPadding,
          vertical: ChatbotDesignConstants.smallPadding,
        ),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(ChatbotDesignConstants.smallBorderRadius),
        ),
        child: Text(
          message.content,
          textAlign: TextAlign.center,
          style: GoogleFonts.ptSans(
            fontSize: 12,
            color: ChatbotDesignConstants.secondaryTextColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildUserOrBotMessageBubble(Message message, bool isUser) {
    return Row(
      mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isUser) ...[
          _buildAvatar(false),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width *
                  ChatbotDesignConstants.messageBubbleMaxWidthRatio,
            ),
            padding: const EdgeInsets.all(ChatbotDesignConstants.defaultPadding),
            decoration: BoxDecoration(
              color: isUser
                  ? ChatbotDesignConstants.userMessageColor
                  : ChatbotDesignConstants.botMessageColor,
              borderRadius: BorderRadius.circular(ChatbotDesignConstants.borderRadius)
                  .copyWith(
                bottomLeft: isUser
                    ? const Radius.circular(ChatbotDesignConstants.borderRadius)
                    : const Radius.circular(4),
                bottomRight: isUser
                    ? const Radius.circular(4)
                    : const Radius.circular(ChatbotDesignConstants.borderRadius),
              ),
              boxShadow: ChatbotDesignConstants.softShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.content,
                  style: GoogleFonts.ptSans(
                    fontSize: ChatbotDesignConstants.defaultFontSize,
                    color: isUser
                        ? Colors.white
                        : ChatbotDesignConstants.primaryTextColor,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: GoogleFonts.ptSans(
                    fontSize: 10,
                    color: isUser
                        ? Colors.white.withValues(alpha: 0.7)
                        : ChatbotDesignConstants.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isUser) ...[
          const SizedBox(width: 8),
          _buildAvatar(true),
        ],
      ],
    );
  }

  Widget _buildAvatar(bool isUser) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isUser
            ? ChatbotDesignConstants.userMessageColor
            : ChatbotDesignConstants.primaryColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ChatbotDesignConstants.softShadow,
      ),
      child: Icon(
        isUser ? Icons.person : Icons.smart_toy,
        color: Colors.white,
        size: 18,
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: ChatbotDesignConstants.smallPadding),
      child: Row(
        children: [
          _buildAvatar(false),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(ChatbotDesignConstants.defaultPadding),
            decoration: BoxDecoration(
              color: ChatbotDesignConstants.botMessageColor,
              borderRadius: BorderRadius.circular(ChatbotDesignConstants.borderRadius)
                  .copyWith(
                bottomLeft: const Radius.circular(4),
              ),
              boxShadow: ChatbotDesignConstants.softShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  _buildTypingDot(i),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingDot(int index) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 600 + (index * 200)),
      curve: Curves.easeInOut,
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: ChatbotDesignConstants.secondaryTextColor,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(ChatbotDesignConstants.defaultPadding),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.05),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: _chatService.getInputHintText(_currentLanguage),
                  hintStyle: GoogleFonts.ptSans(
                    color: ChatbotDesignConstants.secondaryTextColor,
                  ),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(ChatbotDesignConstants.borderRadius),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(ChatbotDesignConstants.borderRadius),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(ChatbotDesignConstants.borderRadius),
                    borderSide: const BorderSide(
                      color: ChatbotDesignConstants.primaryColor,
                      width: 2,
                    ),
                  ),
                ),
                style: GoogleFonts.ptSans(
                  fontSize: ChatbotDesignConstants.defaultFontSize,
                ),
                maxLines: null,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: ChatbotDesignConstants.primaryColor,
                borderRadius: BorderRadius.circular(ChatbotDesignConstants.borderRadius),
                boxShadow: ChatbotDesignConstants.softShadow,
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                ),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
