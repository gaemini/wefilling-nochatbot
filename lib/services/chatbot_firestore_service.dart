import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/message.dart';
import '../models/supported_language.dart';

/// Firebase Functions RAG 시스템을 활용한 챗봇 서비스
class ChatbotFirestoreService {
  static final ChatbotFirestoreService _instance = ChatbotFirestoreService._internal();
  factory ChatbotFirestoreService() => _instance;
  ChatbotFirestoreService._internal();

  FirebaseFirestore? _firestore;
  FirebaseAuth? _auth;
  FirebaseFunctions? _functions;

  /// Firebase 초기화 상태 확인 및 인스턴스 접근
  FirebaseFirestore? get firestore {
    if (!_isFirebaseInitialized()) return null;
    return _firestore ??= FirebaseFirestore.instance;
  }

  FirebaseAuth? get auth {
    if (!_isFirebaseInitialized()) return null;
    return _auth ??= FirebaseAuth.instance;
  }

  FirebaseFunctions? get functions {
    if (!_isFirebaseInitialized()) return null;
    return _functions ??= FirebaseFunctions.instanceFor(region: 'asia-northeast3');
  }

  /// 컬렉션 이름
  static const String _messagesCollection = 'messages';
  static const String _conversationsCollection = 'conversations';

  /// Firebase 초기화 상태 확인
  bool _isFirebaseInitialized() {
    try {
      // Firebase 앱이 초기화되었는지 확인
      FirebaseFirestore.instance.app.name;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 현재 사용자 ID 가져오기 (익명 인증)
  Future<String?> getCurrentUserId() async {
    if (auth == null) {
      print('Firebase Auth가 초기화되지 않았습니다.');
      return 'anonymous_user_${DateTime.now().millisecondsSinceEpoch}';
    }
    
    User? user = auth!.currentUser;
    if (user == null) {
      try {
        print('익명 로그인 시도 중...');
        final credential = await auth!.signInAnonymously();
        user = credential.user;
        print('익명 로그인 성공: ${user?.uid}');
      } catch (e) {
        print('익명 로그인 실패: $e');
        print('익명 로그인이 비활성화되었거나 Firebase 설정에 문제가 있을 수 있습니다.');
        // 익명 로그인 실패 시 임시 ID 생성
        return 'anonymous_user_${DateTime.now().millisecondsSinceEpoch}';
      }
    }
    return user?.uid ?? 'anonymous_user_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Firebase Extensions Gemini API 기반 응답 생성
  Future<Stream<String>> generateRAGResponse({
    required String query,
    required SupportedLanguage language,
    required String questionType,
  }) async {
    try {
      print('RAG 응답 생성 시작: $query');
      
      // Firebase가 초기화되지 않은 경우 기본 응답 반환
      if (!_isFirebaseInitialized() || firestore == null) {
        print('Firebase가 초기화되지 않음, 기본 응답 반환');
        return Stream.value(_getDefaultResponse(query, language));
      }

      // 1. 사용자 ID 가져오기
      final userId = await getCurrentUserId();
      final discussionId = '${userId}_${DateTime.now().millisecondsSinceEpoch}';
      
      print('Discussion ID 생성: $discussionId');

      // 2. Firebase Extensions가 설치되지 않은 경우를 대비한 처리
      try {
        // Firestore에서 시스템 프롬프트 가져오기
        final systemPrompt = await _getSystemPromptFromFirestore(language, questionType);
        
        // generate 컬렉션에 메시지 직접 추가 (Extensions가 모니터링)
        await firestore!
            .collection('generate')
            .add({
          'createTime': FieldValue.serverTimestamp(),
          'prompt': systemPrompt + '\n\nUser Question: ' + query,
          'discussionId': discussionId,
          'userId': userId,
          'language': language.code,
          'questionType': questionType,
        });

        print('메시지 저장 완료, Extensions 응답 대기 중...');

        // 4. Extensions가 응답을 생성할 때까지 대기하고 스트림으로 반환
        return _waitForExtensionResponse(discussionId, language);
        
      } catch (firestoreError) {
        print('Firestore 저장 오류: $firestoreError');
        return Stream.value(_getExtensionNotInstalledMessage(language));
      }

    } catch (e) {
      print('Firebase Extensions Gemini 호출 실패: $e');
      // 에러 발생 시 기본 응답 반환
      return Stream.value(_getDefaultResponse(query, language));
    }
  }

  /// Firebase Extensions 응답 대기 및 스트림 반환
  Stream<String> _waitForExtensionResponse(String discussionId, SupportedLanguage language) async* {
    try {
      print('Extensions 응답 대기 시작: $discussionId');
      
      // generate 컬렉션에서 해당 discussionId의 응답 대기
      await for (final snapshot in firestore!
          .collection('generate')
          .where('discussionId', isEqualTo: discussionId)
          .orderBy('createTime', descending: true)
          .limit(1)
          .snapshots()) {
        
        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
          final data = doc.data();
          
          // Extensions가 추가한 응답 필드 확인
          final response = data['response'] as String?;
          final output = data['output'] as String?;
          final content = data['content'] as String?;
          
          // 응답이 있으면 반환
          final aiResponse = response ?? output ?? content;
          if (aiResponse != null && aiResponse.isNotEmpty) {
            print('Extensions 응답 수신: ${aiResponse.substring(0, aiResponse.length > 100 ? 100 : aiResponse.length)}...');
            yield aiResponse;
            return;
          }
        }
      }
      
      // 30초 후 타임아웃
      await Future.delayed(const Duration(seconds: 30));
      yield _getDefaultResponse('응답 대기 시간 초과', language);
    } catch (e) {
      print('Extension 응답 대기 중 오류: $e');
      yield _getDefaultResponse('응답 처리 중 오류 발생', language);
    }
  }

  /// Firestore에서 카테고리별 시스템 프롬프트 가져오기
  Future<String> _getSystemPromptFromFirestore(SupportedLanguage language, String questionType) async {
    try {
      // 1. 기본 시스템 프롬프트 가져오기
      String basePrompt = await _getBaseSystemPrompt();
      
      // 2. 카테고리별 특화 정보 가져오기
      String categoryInfo = await _getCategorySpecificInfo(questionType);
      
      // 3. 통합 프롬프트 구성
      return _buildMultilingualPrompt(basePrompt, categoryInfo, language, questionType);
      
    } catch (e) {
      print('Firestore 시스템 프롬프트 로드 실패: $e');
      return _buildSystemPrompt(language, questionType);
    }
  }

  /// 기본 시스템 프롬프트 가져오기
  Future<String> _getBaseSystemPrompt() async {
    try {
      final doc = await firestore!
          .collection('reference')
          .doc('basic_info_en')
          .get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return data['text'] as String? ?? _getDefaultBasePrompt();
      }
      
      return _getDefaultBasePrompt();
    } catch (e) {
      print('기본 프롬프트 로드 실패: $e');
      return _getDefaultBasePrompt();
    }
  }

  /// 카테고리별 특화 정보 가져오기
  Future<String> _getCategorySpecificInfo(String questionType) async {
    try {
      final docId = _getCategoryDocumentId(questionType);
      final doc = await firestore!
          .collection('reference')
          .doc(docId)
          .get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return data['text'] as String? ?? '';
      }
      
      print('카테고리별 정보 문서 없음: $docId');
      return '';
    } catch (e) {
      print('카테고리별 정보 로드 실패: $e');
      return '';
    }
  }

  /// 질문 유형에 따른 문서 ID 매핑
  String _getCategoryDocumentId(String questionType) {
    switch (questionType) {
      case 'restaurants':
        return 'restaurants_info_en';
      case 'facilities':
        return 'facilities_info_en';
      case 'academic':
        return 'academic_info_en';
      case 'student_services':
        return 'student_services_en';
      case 'transportation':
        return 'transportation_info_en';
      case 'health_medical':
        return 'health_medical_en';
      case 'dormitory':
        return 'dormitory_info_en';
      case 'immigration_visa':
        return 'immigration_visa_en';
      case 'emergency':
        return 'emergency_safety_en';
      case 'cultural':
        return 'cultural_etiquette_en';
      case 'banking':
        return 'banking_communication_en';
      case 'portal':
        return 'portal_systems_en';
      case 'regional':
        return 'regional_info_en';
      case 'campus_life':
        return 'campus_life_info_en';
      default:
        return 'basic_info_en';
    }
  }

  /// 기본 시스템 프롬프트
  String _getDefaultBasePrompt() {
    return '''You are a helpful chatbot for Hanyang University ERICA campus.
You assist students with information about academic affairs, campus facilities, student life, dining options, transportation, and university services.
Always provide accurate, helpful, and friendly responses based on the provided context.
If you don't have sufficient information, politely indicate that you don't know and suggest where to find the information.''';
  }

  /// 다국어 프롬프트 구성 (기본 + 카테고리별 정보)
  String _buildMultilingualPrompt(String basePrompt, String categoryInfo, SupportedLanguage language, String questionType) {
    final languageInstruction = _getLanguageInstruction(language);
    final contextPrompt = _getContextPromptByQuestionType(questionType, language);
    
    String fullPrompt = basePrompt;
    
    // 카테고리별 정보가 있으면 추가
    if (categoryInfo.isNotEmpty) {
      fullPrompt += '\n\n=== Specific Information for ${questionType.toUpperCase()} ===\n$categoryInfo';
    }
    
    return '''$fullPrompt

$contextPrompt

$languageInstruction

Additional Guidelines:
1. Always respond in the requested language
2. If you don't know something, say so honestly
3. Provide relevant contact information when possible
4. Maintain a friendly and helpful tone
5. Focus on Hanyang University ERICA campus information
6. Use the specific category information above to provide detailed and accurate responses''';
  }

  /// 언어별 응답 지침
  String _getLanguageInstruction(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return '''
IMPORTANT: You must respond ONLY in Korean (한국어).
Do not use any other language in your response.
번역 지침: 모든 답변은 한국어로만 제공해야 합니다.''';
      
      case SupportedLanguage.english:
        return '''
IMPORTANT: You must respond ONLY in English.
Do not use any other language in your response.''';
      
      case SupportedLanguage.chinese:
        return '''
IMPORTANT: You must respond ONLY in Chinese (中文).
Do not use any other language in your response.
翻译指南：所有回答必须仅用中文提供。''';
      
      case SupportedLanguage.japanese:
        return '''
IMPORTANT: You must respond ONLY in Japanese (日本語).
Do not use any other language in your response.
翻訳ガイドライン：すべての回答は日本語のみで提供する必要があります。''';
      
      case SupportedLanguage.french:
        return '''
IMPORTANT: You must respond ONLY in French (Français).
Do not use any other language in your response.
Instructions de traduction : Toutes les réponses doivent être fournies uniquement en français.''';
      
      case SupportedLanguage.russian:
        return '''
IMPORTANT: You must respond ONLY in Russian (Русский).
Do not use any other language in your response.
Инструкции по переводу: Все ответы должны предоставляться только на русском языке.''';
    }
  }

  /// 시스템 프롬프트 구성 (기본값)
  String _buildSystemPrompt(SupportedLanguage language, String questionType) {
    final basePrompt = _getSystemPromptByLanguage(language);
    final contextPrompt = _getContextPromptByQuestionType(questionType, language);
    
    return '''$basePrompt

$contextPrompt

답변 시 다음 지침을 따라주세요:
1. 정확하고 도움이 되는 정보를 제공하세요
2. 모르는 내용은 추측하지 말고 솔직히 모른다고 하세요
3. 가능하면 관련 부서나 연락처 정보를 제공하세요
4. 친근하고 예의바른 톤을 유지하세요''';
  }

  /// 언어별 시스템 프롬프트
  String _getSystemPromptByLanguage(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return '당신은 한양대학교 ERICA 캠퍼스의 도움이 되는 챗봇입니다. 외국인 유학생들의 학사 업무, 캠퍼스 시설, 학생 생활, 대학 서비스에 대한 정보를 도와줍니다.';
      case SupportedLanguage.english:
        return 'You are a helpful chatbot for Hanyang University ERICA campus. You assist international students with information about academic affairs, campus facilities, student life, and university services.';
      case SupportedLanguage.chinese:
        return '您是汉阳大学ERICA校区的helpful聊天机器人。您协助国际学生了解学术事务、校园设施、学生生活和大学服务信息。';
      case SupportedLanguage.japanese:
        return 'あなたは漢陽大学ERICAキャンパスの親切なチャットボットです。留学生の学務、キャンパス施設、学生生活、大学サービスに関する情報をサポートしています。';
      case SupportedLanguage.french:
        return 'Vous êtes un chatbot utile pour le campus ERICA de l\'Université Hanyang. Vous aidez les étudiants internationaux avec des informations sur les affaires académiques, les installations du campus, la vie étudiante et les services universitaires.';
      case SupportedLanguage.russian:
        return 'Вы полезный чат-бот кампуса ERICA Университета Ханъян. Вы помогаете иностранным студентам с информацией об академических делах, кампусных объектах, студенческой жизни и университетских услугах.';
    }
  }

  /// 질문 타입별 컨텍스트 프롬프트
  String _getContextPromptByQuestionType(String questionType, SupportedLanguage language) {
    switch (questionType) {
      case 'international':
        return '국제처 관련 질문입니다. 비자, 외국인 등록, 장학금, 기숙사 등에 대한 정보를 제공하세요.';
      case 'academic':
        return '학사 관련 질문입니다. 수업, 학점, 시험, 졸업 요건 등에 대한 정보를 제공하세요.';
      case 'campus_life':
        return '캠퍼스 생활 관련 질문입니다. 동아리, 행사, 학생식당, 편의시설 등에 대한 정보를 제공하세요.';
      case 'facilities':
        return '시설 관련 질문입니다. 도서관, 체육관, 건물, 실험실 등에 대한 정보를 제공하세요.';
      case 'local_spots':
        return '주변 지역 관련 질문입니다. 맛집, 교통, 쇼핑, 병원 등에 대한 정보를 제공하세요.';
      case 'emergency':
        return '응급상황 관련 질문입니다. 중요하고 즉시 도움이 될 수 있는 정보를 제공하세요.';
      default:
        return '일반적인 한양대학교 ERICA 캠퍼스 관련 질문입니다.';
    }
  }

  /// 기본 응답 생성 (Firebase 없이)
  String _getDefaultResponse(String query, SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return '안녕하세요! 현재 시스템 설정 중입니다. 곧 정상적인 서비스를 제공할 예정입니다.\n\n문의하신 "$query"에 대한 답변은 시스템이 준비되면 더 정확한 정보를 제공해드리겠습니다.';
      
      case SupportedLanguage.english:
        return 'Hello! The system is currently being set up. We will provide normal service soon.\n\nFor your inquiry "$query", we will provide more accurate information once the system is ready.';
      
      case SupportedLanguage.chinese:
        return '您好！系统目前正在设置中。我们将很快提供正常服务。\n\n关于您询问的"$query"，系统准备好后我们将提供更准确的信息。';
      
      case SupportedLanguage.japanese:
        return 'こんにちは！システムは現在設定中です。まもなく通常のサービスを提供いたします。\n\nお問い合わせの「$query」について、システムの準備ができ次第、より正確な情報を提供いたします。';
      
      case SupportedLanguage.french:
        return 'Bonjour! Le système est actuellement en cours de configuration. Nous fournirons bientôt un service normal.\n\nPour votre demande "$query", nous fournirons des informations plus précises une fois le système prêt.';
      
      case SupportedLanguage.russian:
        return 'Привет! Система в настоящее время настраивается. Мы скоро предоставим нормальный сервис.\n\nНа ваш запрос "$query" мы предоставим более точную информацию, как только система будет готова.';
    }
  }

  /// Firebase Extensions가 설치되지 않은 경우 메시지
  String _getExtensionNotInstalledMessage(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return '안녕하세요! 한양대학교 ERICA 캠퍼스 챗봇입니다.\n\n현재 AI 시스템이 설정 중입니다. Firebase Extensions "Build Chatbot with the Gemini API"가 설치되지 않았거나 올바르게 구성되지 않았습니다.\n\n관리자에게 문의하시거나 잠시 후 다시 시도해주세요.';
      
      case SupportedLanguage.english:
        return 'Hello! I am the Hanyang University ERICA campus chatbot.\n\nThe AI system is currently being configured. Firebase Extensions "Build Chatbot with the Gemini API" is not installed or configured properly.\n\nPlease contact the administrator or try again later.';
      
      case SupportedLanguage.chinese:
        return '您好！我是汉阳大学ERICA校区聊天机器人。\n\nAI系统目前正在配置中。Firebase Extensions "Build Chatbot with the Gemini API"未安装或配置不正确。\n\n请联系管理员或稍后再试。';
      
      case SupportedLanguage.japanese:
        return 'こんにちは！漢陽大学ERICAキャンパスのチャットボットです。\n\n現在AIシステムが設定中です。Firebase Extensions "Build Chatbot with the Gemini API"がインストールされていないか、正しく設定されていません。\n\n管理者にお問い合わせいただくか、しばらくしてからもう一度お試しください。';
      
      case SupportedLanguage.french:
        return 'Bonjour! Je suis le chatbot du campus ERICA de l\'Université Hanyang.\n\nLe système d\'IA est en cours de configuration. Firebase Extensions "Build Chatbot with the Gemini API" n\'est pas installé ou configuré correctement.\n\nVeuillez contacter l\'administrateur ou réessayer plus tard.';
      
      case SupportedLanguage.russian:
        return 'Привет! Я чат-бот кампуса ERICA Университета Ханъян.\n\nСистема ИИ в настоящее время настраивается. Firebase Extensions "Build Chatbot with the Gemini API" не установлена или неправильно настроена.\n\nПожалуйста, обратитесь к администратору или повторите попытку позже.';
    }
  }

  /// 메시지 저장
  Future<void> saveMessage({
    required Message message,
    required String conversationId,
  }) async {
    if (firestore == null) return;
    
    try {
      await firestore!
          .collection(_conversationsCollection)
          .doc(conversationId)
          .collection(_messagesCollection)
          .doc(message.id)
          .set(message.toJson());
    } catch (e) {
      print('메시지 저장 실패: $e');
    }
  }

  /// 대화 메시지 목록 가져오기
  Stream<List<Message>> getMessages(String conversationId) {
    if (firestore == null) {
      return Stream.value([]);
    }
    
    return firestore!
        .collection(_conversationsCollection)
        .doc(conversationId)
        .collection(_messagesCollection)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Message.fromJson(doc.data()))
          .toList();
    });
  }
}
