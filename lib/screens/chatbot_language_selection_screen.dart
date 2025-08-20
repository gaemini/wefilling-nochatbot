import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/supported_language.dart';
import '../services/chatbot_storage_service.dart';
import '../services/chatbot_service.dart';
import '../utils/chatbot_design_constants.dart';


class ChatbotLanguageSelectionScreen extends StatefulWidget {
  const ChatbotLanguageSelectionScreen({super.key});

  @override
  State<ChatbotLanguageSelectionScreen> createState() => _ChatbotLanguageSelectionScreenState();
}

class _ChatbotLanguageSelectionScreenState extends State<ChatbotLanguageSelectionScreen>
    with TickerProviderStateMixin {
  final ChatbotStorageService _storageService = ChatbotStorageService();
  final ChatbotService _chatService = ChatbotService();
  
  SupportedLanguage? _selectedLanguage;
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadSavedLanguage();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: ChatbotDesignConstants.defaultAnimationDuration,
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  Future<void> _loadSavedLanguage() async {
    await _storageService.initialize();
    final savedLanguage = await _storageService.getLanguage();
    setState(() {
      _selectedLanguage = savedLanguage;
    });
  }

  Future<void> _selectLanguage(SupportedLanguage language) async {
    setState(() {
      _selectedLanguage = language;
    });
  }

  Future<void> _confirmSelection() async {
    if (_selectedLanguage == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _storageService.saveLanguage(_selectedLanguage!);
      await _storageService.setFirstLaunchComplete();

      if (mounted) {
        Navigator.of(context).pop(true); // 언어 변경 완료를 알림
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_chatService.getErrorMessage(
                _selectedLanguage ?? SupportedLanguage.korean)),
            backgroundColor: ChatbotDesignConstants.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChatbotDesignConstants.backgroundColor,
      appBar: AppBar(
        title: Text(
          '언어 설정',
          style: GoogleFonts.ptSans(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: ChatbotDesignConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: const EdgeInsets.all(ChatbotDesignConstants.largePadding),
            child: Column(
              children: [
                // 상단 여백
                const SizedBox(height: 20),

                // 앱 로고 및 제목
                _buildHeader(),

                const SizedBox(height: 40),

                // 언어 선택 제목
                _buildSelectionTitle(),

                const SizedBox(height: 32),

                // 언어 목록
                Expanded(
                  child: _buildLanguageList(),
                ),

                // 확인 버튼
                _buildConfirmButton(),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: ChatbotDesignConstants.primaryColor,
            borderRadius: BorderRadius.circular(40),
            boxShadow: ChatbotDesignConstants.strongShadow,
          ),
          child: const Icon(
            Icons.school,
            color: Colors.white,
            size: 40,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Hanyang University',
          style: GoogleFonts.ptSans(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: ChatbotDesignConstants.primaryTextColor,
          ),
        ),
        Text(
          'ERICA Campus',
          style: GoogleFonts.ptSans(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: ChatbotDesignConstants.secondaryTextColor,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionTitle() {
    return Text(
      _selectedLanguage != null
          ? _chatService.getLanguageSelectionTitle(_selectedLanguage!)
          : 'Please select your language',
      textAlign: TextAlign.center,
      style: GoogleFonts.ptSans(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: ChatbotDesignConstants.primaryTextColor,
      ),
    );
  }

  Widget _buildLanguageList() {
    return ListView.builder(
      itemCount: SupportedLanguage.allLanguages.length,
      itemBuilder: (context, index) {
        final language = SupportedLanguage.allLanguages[index];
        return _buildLanguageCard(language, index);
      },
    );
  }

  Widget _buildLanguageCard(SupportedLanguage language, int index) {
    final isSelected = _selectedLanguage == language;
    
    return AnimatedContainer(
      duration: ChatbotDesignConstants.fastAnimationDuration,
      margin: const EdgeInsets.only(bottom: ChatbotDesignConstants.defaultPadding),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _selectLanguage(language),
          borderRadius: BorderRadius.circular(ChatbotDesignConstants.borderRadius),
          child: Container(
            padding: const EdgeInsets.all(ChatbotDesignConstants.defaultPadding),
            decoration: BoxDecoration(
              color: isSelected 
                  ? ChatbotDesignConstants.primaryColor.withValues(alpha: 0.1)
                  : Colors.white,
              borderRadius: BorderRadius.circular(ChatbotDesignConstants.borderRadius),
              border: Border.all(
                color: isSelected 
                    ? ChatbotDesignConstants.primaryColor
                    : Colors.grey[300]!,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected 
                  ? ChatbotDesignConstants.strongShadow
                  : ChatbotDesignConstants.softShadow,
            ),
            child: Row(
              children: [
                // 언어 플래그/코드
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? ChatbotDesignConstants.primaryColor
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Center(
                    child: Text(
                      language.flag,
                      style: GoogleFonts.ptSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // 언어 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        language.nativeName,
                        style: GoogleFonts.ptSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isSelected 
                              ? ChatbotDesignConstants.primaryColor
                              : ChatbotDesignConstants.primaryTextColor,
                        ),
                      ),
                      Text(
                        language.englishName,
                        style: GoogleFonts.ptSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: ChatbotDesignConstants.secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 선택 인디케이터
                if (isSelected)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: ChatbotDesignConstants.primaryColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmButton() {
    final isEnabled = _selectedLanguage != null && !_isLoading;
    
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isEnabled ? _confirmSelection : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: ChatbotDesignConstants.primaryColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[300],
          disabledForegroundColor: Colors.grey[600],
          elevation: isEnabled ? 4 : 0,
          shadowColor: ChatbotDesignConstants.primaryColor.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChatbotDesignConstants.borderRadius),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                _selectedLanguage != null
                    ? _chatService.getConfirmButtonText(_selectedLanguage!)
                    : 'Confirm',
                style: GoogleFonts.ptSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
