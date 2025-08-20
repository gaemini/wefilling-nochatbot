import '../models/supported_language.dart';
import '../models/message.dart';
import 'chatbot_firestore_service.dart';

/// 채팅 관련 비즈니스 로직을 담당하는 서비스
class ChatbotService {
  static final ChatbotService _instance = ChatbotService._internal();
  factory ChatbotService() => _instance;
  ChatbotService._internal();

  final ChatbotFirestoreService _firestoreService = ChatbotFirestoreService();

  /// 질문 타입 분석 (확장된 카테고리)
  String analyzeQuestionType(String query, SupportedLanguage language) {
    final lowerQuery = query.toLowerCase();
    
    // 우선순위가 높은 카테고리부터 검사
    final Map<String, List<String>> typeKeywords = {
      'restaurants': _getRestaurantKeywords(language),      // 맛집/식당 - 우선순위 높음
      'facilities': _getFacilitiesKeywords(language),       // 시설 정보
      'academic': _getAcademicKeywords(language),           // 학사 정보
      'student_services': _getStudentServicesKeywords(language), // 학생 서비스
      'transportation': _getTransportationKeywords(language),    // 교통 정보
      'contact': _getContactKeywords(language),             // 연락처 정보
      'campus_life': _getCampusLifeKeywords(language),      // 캠퍼스 생활
      'emergency': _getEmergencyKeywords(language),         // 응급상황
    };
    
    // 키워드 매칭으로 질문 타입 결정 (우선순위 순)
    for (final entry in typeKeywords.entries) {
      final type = entry.key;
      final keywords = entry.value;
      
      for (final keyword in keywords) {
        if (lowerQuery.contains(keyword.toLowerCase())) {
          return type;
        }
      }
    }
    
    return 'basic'; // 기본 타입 (대학 기본 정보)
  }

  /// RAG 기반 응답 생성
  Future<Stream<String>> generateIntelligentResponse({
    required String query,
    required SupportedLanguage language,
  }) async {
    try {
      // 1. 질문 타입 분석
      final questionType = analyzeQuestionType(query, language);
      
      // 2. Firestore RAG 시스템을 통한 응답 생성
      return await _firestoreService.generateRAGResponse(
        query: query,
        language: language,
        questionType: questionType,
      );
    } catch (e) {
      // 에러 발생 시 에러 메시지 스트림 반환
      return Stream.value(getErrorMessage(language));
    }
  }

  /// 언어별 맛집/식당 관련 키워드 (최우선순위)
  List<String> _getRestaurantKeywords(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return ['맛집', '식당', '음식', '먹을', '레스토랑', '카페', '식사', '점심', '저녁', '아침', '메뉴', '배달', '테이크아웃'];
      case SupportedLanguage.english:
        return ['restaurant', 'food', 'eat', 'dining', 'cafe', 'meal', 'lunch', 'dinner', 'breakfast', 'menu', 'delivery', 'takeout'];
      case SupportedLanguage.chinese:
        return ['餐厅', '食物', '吃', '用餐', '咖啡厅', '餐', '午餐', '晚餐', '早餐', '菜单', '外卖', '打包'];
      case SupportedLanguage.japanese:
        return ['レストラン', '食べ物', '食べる', '食事', 'カフェ', '昼食', '夕食', '朝食', 'メニュー', '配達', 'テイクアウト'];
      case SupportedLanguage.french:
        return ['restaurant', 'nourriture', 'manger', 'repas', 'café', 'déjeuner', 'dîner', 'petit-déjeuner', 'menu', 'livraison', 'emporter'];
      case SupportedLanguage.russian:
        return ['ресторан', 'еда', 'есть', 'питание', 'кафе', 'обед', 'ужин', 'завтрак', 'меню', 'доставка', 'навынос'];
    }
  }

  /// 언어별 학생 서비스 관련 키워드
  List<String> _getStudentServicesKeywords(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return ['장학금', '상담', '지원', '서비스', '취업', '진로', '학생지원', '복지', '심리상담', '학습지원'];
      case SupportedLanguage.english:
        return ['scholarship', 'counseling', 'support', 'service', 'career', 'student support', 'welfare', 'psychological counseling', 'learning support'];
      case SupportedLanguage.chinese:
        return ['奖学金', '咨询', '支持', '服务', '就业', '职业', '学生支持', '福利', '心理咨询', '学习支持'];
      case SupportedLanguage.japanese:
        return ['奨学金', 'カウンセリング', 'サポート', 'サービス', 'キャリア', '学生支援', '福祉', '心理カウンセリング', '学習支援'];
      case SupportedLanguage.french:
        return ['bourse', 'conseil', 'soutien', 'service', 'carrière', 'soutien étudiant', 'bien-être', 'conseil psychologique', 'soutien apprentissage'];
      case SupportedLanguage.russian:
        return ['стипендия', 'консультирование', 'поддержка', 'сервис', 'карьера', 'поддержка студентов', 'благосостояние', 'психологическое консультирование', 'поддержка обучения'];
    }
  }

  /// 언어별 교통 관련 키워드
  List<String> _getTransportationKeywords(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return ['버스', '지하철', '교통', '가는법', '오는법', '찾아오는법', '주차', '주차장', '셔틀', '대중교통'];
      case SupportedLanguage.english:
        return ['bus', 'subway', 'metro', 'transport', 'how to get', 'directions', 'parking', 'shuttle', 'public transport'];
      case SupportedLanguage.chinese:
        return ['公交', '地铁', '交通', '怎么去', '路线', '停车', '停车场', '班车', '公共交通'];
      case SupportedLanguage.japanese:
        return ['バス', '地下鉄', '交通', '行き方', '道順', '駐車', '駐車場', 'シャトル', '公共交通'];
      case SupportedLanguage.french:
        return ['bus', 'métro', 'transport', 'comment aller', 'directions', 'parking', 'navette', 'transport public'];
      case SupportedLanguage.russian:
        return ['автобус', 'метро', 'транспорт', 'как добраться', 'направления', 'парковка', 'шаттл', 'общественный транспорт'];
    }
  }

  /// 언어별 연락처 관련 키워드
  List<String> _getContactKeywords(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return ['연락처', '전화', '전화번호', '이메일', '문의', '연락', '담당자', '상담원'];
      case SupportedLanguage.english:
        return ['contact', 'phone', 'telephone', 'email', 'inquiry', 'reach', 'person in charge', 'representative'];
      case SupportedLanguage.chinese:
        return ['联系方式', '电话', '邮箱', '咨询', '联系', '负责人', '代表'];
      case SupportedLanguage.japanese:
        return ['連絡先', '電話', 'メール', '問い合わせ', '連絡', '担当者', '代表'];
      case SupportedLanguage.french:
        return ['contact', 'téléphone', 'email', 'demande', 'contacter', 'responsable', 'représentant'];
      case SupportedLanguage.russian:
        return ['контакт', 'телефон', 'email', 'запрос', 'связаться', 'ответственный', 'представитель'];
    }
  }

  /// 언어별 학사 관련 키워드
  List<String> _getAcademicKeywords(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return ['수업', '강의', '시간표', '학점', '시험', '과제', '교수', '성적', '졸업', '학사', '전공'];
      case SupportedLanguage.english:
        return ['class', 'lecture', 'schedule', 'credit', 'exam', 'assignment', 'professor', 'grade', 'graduation', 'academic', 'major'];
      case SupportedLanguage.chinese:
        return ['上课', '讲课', '课程表', '学分', '考试', '作业', '教授', '成绩', '毕业', '学术', '专业'];
      case SupportedLanguage.japanese:
        return ['授業', '講義', '時間割', '単位', '試験', '課題', '教授', '成績', '卒業', '学術', '専攻'];
      case SupportedLanguage.french:
        return ['cours', 'conférence', 'horaire', 'crédit', 'examen', 'devoir', 'professeur', 'note', 'diplôme', 'académique', 'majeure'];
      case SupportedLanguage.russian:
        return ['урок', 'лекция', 'расписание', 'кредит', 'экзамен', 'задание', 'профессор', 'оценка', 'выпуск', 'академический', 'специальность'];
    }
  }

  /// 언어별 캠퍼스 생활 키워드
  List<String> _getCampusLifeKeywords(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return ['동아리', '학생회', '행사', '축제', '동호회', '클럽', '학생식당', '카페', '휴식', '친구'];
      case SupportedLanguage.english:
        return ['club', 'student council', 'event', 'festival', 'society', 'cafeteria', 'cafe', 'rest', 'friend', 'activity'];
      case SupportedLanguage.chinese:
        return ['社团', '学生会', '活动', '节日', '俱乐部', '学生餐厅', '咖啡厅', '休息', '朋友', '活动'];
      case SupportedLanguage.japanese:
        return ['サークル', '学生会', 'イベント', '祭り', 'クラブ', '学生食堂', 'カフェ', '休憩', '友達', '活動'];
      case SupportedLanguage.french:
        return ['club', 'conseil étudiant', 'événement', 'festival', 'société', 'cafétéria', 'café', 'repos', 'ami', 'activité'];
      case SupportedLanguage.russian:
        return ['клуб', 'студенческий совет', 'событие', 'фестиваль', 'общество', 'столовая', 'кафе', 'отдых', 'друг', 'деятельность'];
    }
  }

  /// 언어별 시설 관련 키워드
  List<String> _getFacilitiesKeywords(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return ['도서관', '헬스장', '체육관', '수영장', '건물', '시설', '컴퓨터실', '스터디룸', '주차장'];
      case SupportedLanguage.english:
        return ['library', 'gym', 'gymnasium', 'swimming pool', 'building', 'facility', 'computer lab', 'study room', 'parking'];
      case SupportedLanguage.chinese:
        return ['图书馆', '健身房', '体育馆', '游泳池', '建筑', '设施', '电脑室', '学习室', '停车场'];
      case SupportedLanguage.japanese:
        return ['図書館', 'ジム', '体育館', 'プール', '建物', '施設', 'コンピュータ室', '学習室', '駐車場'];
      case SupportedLanguage.french:
        return ['bibliothèque', 'gym', 'gymnase', 'piscine', 'bâtiment', 'installation', 'salle informatique', 'salle étude', 'parking'];
      case SupportedLanguage.russian:
        return ['библиотека', 'спортзал', 'гимназия', 'бассейн', 'здание', 'объект', 'компьютерный класс', 'учебная комната', 'парковка'];
    }
  }

  /// 언어별 응급상황 키워드
  List<String> _getEmergencyKeywords(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return ['응급', '긴급', '도움', '경찰', '소방서', '병원', '응급실', '신고', '사고', '위험'];
      case SupportedLanguage.english:
        return ['emergency', 'urgent', 'help', 'police', 'fire department', 'hospital', 'emergency room', 'report', 'accident', 'danger'];
      case SupportedLanguage.chinese:
        return ['紧急', '急迫', '帮助', '警察', '消防队', '医院', '急诊室', '报告', '事故', '危险'];
      case SupportedLanguage.japanese:
        return ['緊急', '急ぎ', '助け', '警察', '消防署', '病院', '救急室', '通報', '事故', '危険'];
      case SupportedLanguage.french:
        return ['urgence', 'urgent', 'aide', 'police', 'pompiers', 'hôpital', 'urgences', 'signaler', 'accident', 'danger'];
      case SupportedLanguage.russian:
        return ['экстренный', 'срочный', 'помощь', 'полиция', 'пожарная', 'больница', 'скорая', 'сообщить', 'авария', 'опасность'];
    }
  }

  /// 언어별 초기 인사말 반환
  String getInitialGreeting(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return '안녕하세요!\n\n한양대학교 ERICA 캠퍼스 챗봇입니다.\n\n학교 생활, 학사 정보, 캠퍼스 시설 등에 대해 궁금한 점이 있으시면 언제든 물어보세요!';
      
      case SupportedLanguage.english:
        return 'Hello!\n\nI am the Hanyang University ERICA campus chatbot.\n\nFeel free to ask me anything about campus life, academic information, facilities, and more!';
      
      case SupportedLanguage.chinese:
        return '您好！\n\n我是汉阳大学ERICA校区聊天机器人。\n\n如果您对校园生活、学术信息、校园设施等有任何疑问，请随时询问！';
      
      case SupportedLanguage.japanese:
        return 'こんにちは！\n\n漢陽大学ERICAキャンパスのチャットボットです。\n\nキャンパスライフ、学務情報、施設などについて何でもお気軽にお聞きください！';
      
      case SupportedLanguage.french:
        return 'Bonjour!\n\nJe suis le chatbot du campus ERICA de l\'Université Hanyang.\n\nN\'hésitez pas à me poser des questions sur la vie du campus, les informations académiques, les installations, et plus encore!';
      
      case SupportedLanguage.russian:
        return 'Привет!\n\nЯ чат-бот кампуса ERICA Университета Ханъян.\n\nНе стесняйтесь задавать мне вопросы о студенческой жизни, академической информации, кампусных удобствах и многом другом!';
    }
  }

  /// 언어 설정 완료 메시지 반환
  String getLanguageSetupCompleteMessage(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return '한국어로 설정되었습니다! 안녕하세요!';
      
      case SupportedLanguage.english:
        return 'Language set to English! Hello!';
      
      case SupportedLanguage.chinese:
        return '语言已设置为中文！您好！';
      
      case SupportedLanguage.japanese:
        return '日本語に設定されました！こんにちは！';
      
      case SupportedLanguage.french:
        return 'Langue définie en français! Bonjour!';
      
      case SupportedLanguage.russian:
        return 'Язык установлен на русский! Привет!';
    }
  }

  /// 언어별 환영 메시지 반환 (언어 변경 시)
  String getWelcomeMessage(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return '언어가 한국어로 변경되었습니다. 무엇을 도와드릴까요?';
      
      case SupportedLanguage.english:
        return 'Language changed to English. How can I help you?';
      
      case SupportedLanguage.chinese:
        return '语言已更改为中文。我可以为您做些什么？';
      
      case SupportedLanguage.japanese:
        return '言語が日本語に変更されました。何かお手伝いできることはありますか？';
      
      case SupportedLanguage.french:
        return 'Langue changée en français. Comment puis-je vous aider?';
      
      case SupportedLanguage.russian:
        return 'Язык изменен на русский. Чем могу помочь?';
    }
  }

  /// 언어별 입력 힌트 텍스트 반환
  String getInputHintText(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return '메시지를 입력하세요...';
      
      case SupportedLanguage.english:
        return 'Type your message...';
      
      case SupportedLanguage.chinese:
        return '输入您的消息...';
      
      case SupportedLanguage.japanese:
        return 'メッセージを入力してください...';
      
      case SupportedLanguage.french:
        return 'Tapez votre message...';
      
      case SupportedLanguage.russian:
        return 'Введите ваше сообщение...';
    }
  }

  /// 언어별 에러 메시지 반환
  String getErrorMessage(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return '죄송합니다. 요청을 처리하는 중에 오류가 발생했습니다. 나중에 다시 시도해주세요.';
      
      case SupportedLanguage.english:
        return 'Sorry, I encountered an error while processing your request. Please try again later.';
      
      case SupportedLanguage.chinese:
        return '抱歉，处理您的请求时遇到错误。请稍后再试。';
      
      case SupportedLanguage.japanese:
        return '申し訳ございませんが、リクエストの処理中にエラーが発生しました。後でもう一度お試しください。';
      
      case SupportedLanguage.french:
        return 'Désolé, j\'ai rencontré une erreur lors du traitement de votre demande. Veuillez réessayer plus tard.';
      
      case SupportedLanguage.russian:
        return 'Извините, произошла ошибка при обработке вашего запроса. Пожалуйста, попробуйте еще раз позже.';
    }
  }

  /// 언어별 언어 선택 화면 제목 반환
  String getLanguageSelectionTitle(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return '언어를 선택해주세요';
      
      case SupportedLanguage.english:
        return 'Please select your language';
      
      case SupportedLanguage.chinese:
        return '请选择您的语言';
      
      case SupportedLanguage.japanese:
        return '言語を選択してください';
      
      case SupportedLanguage.french:
        return 'Veuillez sélectionner votre langue';
      
      case SupportedLanguage.russian:
        return 'Пожалуйста, выберите ваш язык';
    }
  }

  /// 언어별 확인 버튼 텍스트 반환
  String getConfirmButtonText(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return '확인';
      
      case SupportedLanguage.english:
        return 'Confirm';
      
      case SupportedLanguage.chinese:
        return '确认';
      
      case SupportedLanguage.japanese:
        return '確認';
      
      case SupportedLanguage.french:
        return 'Confirmer';
      
      case SupportedLanguage.russian:
        return 'Подтвердить';
    }
  }

  /// 시스템 메시지 생성
  Message createSystemMessage(String content, SupportedLanguage language) {
    return Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isFromUser: false,
      timestamp: DateTime.now(),
      language: language.code,
    );
  }

  /// 언어별 앱 제목 반환
  String getAppTitle(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return '한양대학교 ERICA';
      
      case SupportedLanguage.english:
        return 'Hanyang University ERICA';
      
      case SupportedLanguage.chinese:
        return '汉阳大学ERICA';
      
      case SupportedLanguage.japanese:
        return '漢陽大学ERICA';
      
      case SupportedLanguage.french:
        return 'Université Hanyang ERICA';
      
      case SupportedLanguage.russian:
        return 'Университет Ханъян ERICA';
    }
  }

  /// 언어별 앱 부제목 반환
  String getAppSubtitle(SupportedLanguage language) {
    switch (language) {
      case SupportedLanguage.korean:
        return '챗봇 도우미';
      
      case SupportedLanguage.english:
        return 'Chatbot Assistant';
      
      case SupportedLanguage.chinese:
        return '聊天机器人助手';
      
      case SupportedLanguage.japanese:
        return 'チャットボットアシスタント';
      
      case SupportedLanguage.french:
        return 'Assistant Chatbot';
      
      case SupportedLanguage.russian:
        return 'Чат-бот помощник';
    }
  }
}
