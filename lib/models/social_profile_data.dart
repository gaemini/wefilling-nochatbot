import '../utils/nickname_policy.dart';

class SocialProfileData {
  const SocialProfileData({
    this.bio = '',
    this.interests = const <String>[],
    this.preferredActivities = const <String>[],
    this.conversationStarter = '',
    this.friendshipPrompt = '',
    this.department = '',
    this.grade = '',
    this.showDepartment = false,
    this.showGrade = false,
  });

  final String bio;
  final List<String> interests;
  final List<String> preferredActivities;
  final String conversationStarter;
  final String friendshipPrompt;
  final String department;
  final String grade;
  final bool showDepartment;
  final bool showGrade;

  factory SocialProfileData.fromMap(Map<String, dynamic>? map) {
    final data = map ?? const <String, dynamic>{};

    String conversationStarter() {
      final value = (data['conversationStarter'] ?? '').toString().trim();
      // 이전 선택지를 저장한 프로필도 상대방에게 묻는 현재 문구로
      // 표시되도록 정확히 일치하는 기존 문구만 안전하게 변환한다.
      if (value == '공강 시간에는 주로 무엇을 하나요?') {
        return '공강 시간에는 주로 무엇을 하시나요?';
      }
      return value;
    }

    List<String> strings(String key) {
      final value = data[key];
      if (value is! List) return const <String>[];
      return value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .take(5)
          .toList(growable: false);
    }

    return SocialProfileData(
      bio: (data['bio'] ?? '').toString().trim(),
      interests: strings('interests'),
      preferredActivities: strings('preferredActivities'),
      conversationStarter: conversationStarter(),
      friendshipPrompt: (data['friendshipPrompt'] ?? '').toString().trim(),
      department: (data['department'] ?? '').toString().trim(),
      grade: (data['grade'] ?? '').toString().trim(),
      showDepartment: data['showDepartment'] == true,
      showGrade: data['showGrade'] == true,
    );
  }

  int completionFor({bool hasProfilePhoto = false}) {
    var completed = 0;
    if (hasProfilePhoto) completed++;
    if (bio.isNotEmpty) completed++;
    if (interests.isNotEmpty) completed++;
    if (preferredActivities.isNotEmpty) completed++;
    if (conversationStarter.isNotEmpty) completed++;
    return (completed / 5 * 100).round();
  }

  int get completion => completionFor();

  Map<String, dynamic> toUpdateMap({bool hasProfilePhoto = false}) =>
      <String, dynamic>{
        'bio': bio.trim(),
        'interests': interests.take(5).toList(growable: false),
        'preferredActivities':
            preferredActivities.take(5).toList(growable: false),
        'conversationStarter': conversationStarter.trim(),
        'friendshipPrompt': friendshipPrompt.trim(),
        'department': department.trim(),
        'grade': grade.trim(),
        'showDepartment': showDepartment,
        'showGrade': showGrade,
        'profileCompletion': completionFor(
          hasProfilePhoto: hasProfilePhoto,
        ),
      };
}

class SocialProfileOption {
  const SocialProfileOption({
    required this.id,
    required this.ko,
    required this.en,
    this.zh,
  });

  final String id;
  final String ko;
  final String en;
  final String? zh;

  String label(String languageCode) => languageCode == 'zh'
      ? (zh ?? en)
      : languageCode == 'ko' ? ko : en;
}

class SocialProfileValidation {
  const SocialProfileValidation._();

  static String? nicknameError(String? rawValue, String languageCode) {
    final isKorean = languageCode == 'ko';
    return switch (NicknamePolicy.validate(rawValue)) {
      null => null,
      NicknameValidationIssue.empty =>
        (languageCode == 'zh' ? '请输入昵称。' : isKorean ? '닉네임을 입력해 주세요.' : 'Please enter a nickname.'),
      NicknameValidationIssue.length =>
        (languageCode == 'zh' ? '请输入2–20个字符。' : isKorean ? '닉네임은 2~20자로 입력해 주세요.' : 'Use 2–20 characters.'),
      NicknameValidationIssue.invalidCharacters => (languageCode == 'zh' ? '仅支持韩文、英文字母、数字和下划线。' : isKorean
          ? '한글, 영문, 숫자, _만 입력해 주세요.'
          : 'Use only Korean or English letters, numbers, and _.'),
      NicknameValidationIssue.letterRequired => (languageCode == 'zh' ? '请至少包含一个韩文或英文字母。' : isKorean
          ? '한글 또는 영문자를 하나 이상 포함해 주세요.'
          : 'Include at least one Korean or English letter.'),
      NicknameValidationIssue.reserved =>
        (languageCode == 'zh' ? '此昵称不可用。' : isKorean ? '사용할 수 없는 닉네임이에요.' : 'This nickname is reserved.'),
    };
  }
}

class SocialProfileCatalog {
  const SocialProfileCatalog._();

  static const interests = <SocialProfileOption>[
    SocialProfileOption(id: 'restaurants', ko: '맛집', en: 'Food spots', zh: '美食探店'),
    SocialProfileOption(id: 'cafe', ko: '카페', en: 'Cafes', zh: '咖啡馆'),
    SocialProfileOption(id: 'running', ko: '러닝', en: 'Running', zh: '跑步'),
    SocialProfileOption(id: 'fitness', ko: '헬스', en: 'Fitness', zh: '健身'),
    SocialProfileOption(id: 'soccer', ko: '축구', en: 'Soccer', zh: '足球'),
    SocialProfileOption(id: 'basketball', ko: '농구', en: 'Basketball', zh: '篮球'),
    SocialProfileOption(id: 'travel', ko: '여행', en: 'Travel', zh: '旅行'),
    SocialProfileOption(id: 'photo', ko: '사진', en: 'Photography', zh: '摄影'),
    SocialProfileOption(id: 'movie', ko: '영화', en: 'Movies', zh: '电影'),
    SocialProfileOption(id: 'music', ko: '음악', en: 'Music', zh: '音乐'),
    SocialProfileOption(id: 'game', ko: '게임', en: 'Gaming', zh: '游戏'),
    SocialProfileOption(id: 'reading', ko: '독서', en: 'Reading', zh: '阅读'),
    SocialProfileOption(id: 'language', ko: '외국어', en: 'Languages', zh: '外语'),
    SocialProfileOption(id: 'study', ko: '스터디', en: 'Study', zh: '学习'),
    SocialProfileOption(id: 'exhibition', ko: '전시', en: 'Exhibitions', zh: '展览'),
    SocialProfileOption(id: 'performance', ko: '공연', en: 'Performances', zh: '演出'),
    SocialProfileOption(id: 'volunteer', ko: '봉사', en: 'Volunteering', zh: '志愿服务'),
    SocialProfileOption(id: 'startup', ko: '창업', en: 'Startups', zh: '创业'),
    SocialProfileOption(id: 'development', ko: '개발', en: 'Development', zh: '开发'),
    SocialProfileOption(id: 'ai', ko: 'AI', en: 'AI', zh: 'AI'),
  ];

  static const activities = <SocialProfileOption>[
    SocialProfileOption(id: 'lunch', ko: '같이 점심 먹기', en: 'Grab lunch', zh: '一起吃午饭'),
    SocialProfileOption(id: 'cafe', ko: '카페 가기', en: 'Visit a cafe', zh: '去咖啡馆'),
    SocialProfileOption(id: 'running', ko: '러닝', en: 'Go running', zh: '一起跑步'),
    SocialProfileOption(id: 'workout', ko: '운동', en: 'Work out', zh: '一起运动'),
    SocialProfileOption(id: 'exam_study', ko: '시험공부', en: 'Study for exams', zh: '备考'),
    SocialProfileOption(
        id: 'language_exchange', ko: '언어 교환', en: 'Language exchange', zh: '语言交流'),
    SocialProfileOption(id: 'movie', ko: '영화 보기', en: 'Watch a movie', zh: '看电影'),
    SocialProfileOption(id: 'exhibition', ko: '전시 관람', en: 'See an exhibition', zh: '看展'),
    SocialProfileOption(id: 'travel', ko: '여행', en: 'Travel', zh: '旅行'),
    SocialProfileOption(id: 'photo', ko: '사진 찍기', en: 'Take photos', zh: '拍照'),
    SocialProfileOption(
        id: 'school_event', ko: '학교 행사 참여', en: 'Join campus events', zh: '参加校园活动'),
    SocialProfileOption(id: 'club', ko: '동아리 활동', en: 'Club activities', zh: '社团活动'),
    SocialProfileOption(id: 'chat', ko: '편하게 이야기하기', en: 'Have a casual chat', zh: '轻松聊天'),
  ];

  static const conversationStarters = <SocialProfileOption>[
    SocialProfileOption(
        id: 'food',
        ko: '학교 근처 최애 맛집이 어디예요?',
        en: 'What is your favorite food spot near campus?', zh: '学校附近你最喜欢哪家店？'),
    SocialProfileOption(
        id: 'break',
        ko: '공강 시간에는 주로 무엇을 하시나요?',
        en: 'What do you usually do between classes?', zh: '课间空闲时你通常做什么？'),
    SocialProfileOption(
        id: 'movie',
        ko: '요즘 가장 재미있게 본 영화는 무엇인가요?',
        en: 'What is the best movie you watched recently?', zh: '最近看过最好看的电影是什么？'),
    SocialProfileOption(
        id: 'exercise',
        ko: '같이 시작하기 좋은 운동을 추천해 주세요.',
        en: 'What exercise is good to start together?', zh: '有什么适合一起入门的运动？'),
    SocialProfileOption(
        id: 'campus',
        ko: '학교생활에서 꼭 해보고 싶은 것이 있나요?',
        en: 'What do you want to try during campus life?', zh: '校园生活中有什么想尝试的事？'),
    SocialProfileOption(
        id: 'korea',
        ko: '한국에서 꼭 가보고 싶은 곳이 있나요?',
        en: 'Where would you like to visit in Korea?', zh: '在韩国最想去哪里？'),
    SocialProfileOption(
        id: 'recent',
        ko: '요즘 가장 빠져 있는 것은 무엇인가요?',
        en: 'What are you into these days?', zh: '最近最感兴趣的是什么？'),
  ];

  static const friendshipPrompts = <SocialProfileOption>[
    SocialProfileOption(
        id: 'say_hi',
        ko: '먼저 말 걸어주면 좋아해요.',
        en: 'I like it when you say hi first.', zh: '欢迎你先来打招呼。'),
    SocialProfileOption(
        id: 'meal',
        ko: '같이 밥을 먹으면 금방 친해져요.',
        en: 'Sharing a meal helps me open up.', zh: '一起吃顿饭就能熟悉起来。'),
    SocialProfileOption(
        id: 'meme',
        ko: '밈을 보내주면 빨리 친해져요.',
        en: 'Send me a meme and we will click.', zh: '给我发表情包，我们很快就能聊起来。'),
    SocialProfileOption(
        id: 'exercise',
        ko: '같이 운동하면 어색함이 사라져요.',
        en: 'Working out together breaks the ice.', zh: '一起运动就不会尴尬了。'),
    SocialProfileOption(
        id: 'dessert',
        ko: '카페와 디저트 이야기라면 언제든 환영해요.',
        en: 'Cafe and dessert talk is always welcome.', zh: '随时欢迎聊咖啡馆和甜品。'),
    SocialProfileOption(
        id: 'quiet',
        ko: '처음에는 조용하지만 친해지면 장난이 많아요.',
        en: 'I am quiet at first, playful later.', zh: '刚认识时有点安静，熟了以后很爱闹。'),
    SocialProfileOption(
        id: 'spontaneous',
        ko: '즉흥적인 약속도 좋아해요.',
        en: 'I enjoy spontaneous plans.', zh: '我也喜欢说走就走的邀约。'),
    SocialProfileOption(
        id: 'small_group',
        ko: '소수의 사람과 편하게 만나는 것을 좋아해요.',
        en: 'I prefer relaxed small-group meetups.', zh: '喜欢轻松的小范围聚会。'),
  ];

  static String labelFor(
    String id,
    List<SocialProfileOption> options,
    String languageCode,
  ) {
    for (final option in options) {
      if (option.id == id) return option.label(languageCode);
    }
    return id;
  }
}
