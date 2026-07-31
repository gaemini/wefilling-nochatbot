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
      conversationStarter:
          (data['conversationStarter'] ?? '').toString().trim(),
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
  });

  final String id;
  final String ko;
  final String en;

  String label(String languageCode) => languageCode == 'ko' ? ko : en;
}

class SocialProfileValidation {
  const SocialProfileValidation._();

  static final RegExp _nicknamePattern = RegExp(r'^[a-zA-Z0-9가-힣_\.]+$');

  static String? nicknameError(String? rawValue, String languageCode) {
    final value = rawValue?.trim() ?? '';
    final isKorean = languageCode == 'ko';
    if (value.isEmpty) {
      return isKorean ? '닉네임을 입력해 주세요.' : 'Please enter a nickname.';
    }
    if (value.length < 2 || value.length > 20) {
      return isKorean ? '닉네임은 2~20자로 입력해 주세요.' : 'Use 2–20 characters.';
    }
    if (!_nicknamePattern.hasMatch(value)) {
      return isKorean
          ? '한글, 영문, 숫자, 밑줄, 마침표만 사용할 수 있어요.'
          : 'Use letters, numbers, underscores, or periods.';
    }
    return null;
  }
}

class SocialProfileCatalog {
  const SocialProfileCatalog._();

  static const interests = <SocialProfileOption>[
    SocialProfileOption(id: 'restaurants', ko: '맛집', en: 'Food spots'),
    SocialProfileOption(id: 'cafe', ko: '카페', en: 'Cafes'),
    SocialProfileOption(id: 'running', ko: '러닝', en: 'Running'),
    SocialProfileOption(id: 'fitness', ko: '헬스', en: 'Fitness'),
    SocialProfileOption(id: 'soccer', ko: '축구', en: 'Soccer'),
    SocialProfileOption(id: 'basketball', ko: '농구', en: 'Basketball'),
    SocialProfileOption(id: 'travel', ko: '여행', en: 'Travel'),
    SocialProfileOption(id: 'photo', ko: '사진', en: 'Photography'),
    SocialProfileOption(id: 'movie', ko: '영화', en: 'Movies'),
    SocialProfileOption(id: 'music', ko: '음악', en: 'Music'),
    SocialProfileOption(id: 'game', ko: '게임', en: 'Gaming'),
    SocialProfileOption(id: 'reading', ko: '독서', en: 'Reading'),
    SocialProfileOption(id: 'language', ko: '외국어', en: 'Languages'),
    SocialProfileOption(id: 'study', ko: '스터디', en: 'Study'),
    SocialProfileOption(id: 'exhibition', ko: '전시', en: 'Exhibitions'),
    SocialProfileOption(id: 'performance', ko: '공연', en: 'Performances'),
    SocialProfileOption(id: 'volunteer', ko: '봉사', en: 'Volunteering'),
    SocialProfileOption(id: 'startup', ko: '창업', en: 'Startups'),
    SocialProfileOption(id: 'development', ko: '개발', en: 'Development'),
    SocialProfileOption(id: 'ai', ko: 'AI', en: 'AI'),
  ];

  static const activities = <SocialProfileOption>[
    SocialProfileOption(id: 'lunch', ko: '같이 점심 먹기', en: 'Grab lunch'),
    SocialProfileOption(id: 'cafe', ko: '카페 가기', en: 'Visit a cafe'),
    SocialProfileOption(id: 'running', ko: '러닝', en: 'Go running'),
    SocialProfileOption(id: 'workout', ko: '운동', en: 'Work out'),
    SocialProfileOption(id: 'exam_study', ko: '시험공부', en: 'Study for exams'),
    SocialProfileOption(
        id: 'language_exchange', ko: '언어 교환', en: 'Language exchange'),
    SocialProfileOption(id: 'movie', ko: '영화 보기', en: 'Watch a movie'),
    SocialProfileOption(id: 'exhibition', ko: '전시 관람', en: 'See an exhibition'),
    SocialProfileOption(id: 'travel', ko: '여행', en: 'Travel'),
    SocialProfileOption(id: 'photo', ko: '사진 찍기', en: 'Take photos'),
    SocialProfileOption(
        id: 'school_event', ko: '학교 행사 참여', en: 'Join campus events'),
    SocialProfileOption(id: 'club', ko: '동아리 활동', en: 'Club activities'),
    SocialProfileOption(id: 'chat', ko: '편하게 이야기하기', en: 'Have a casual chat'),
  ];

  static const conversationStarters = <SocialProfileOption>[
    SocialProfileOption(
        id: 'food',
        ko: '학교 근처 최애 맛집이 어디예요?',
        en: 'What is your favorite food spot near campus?'),
    SocialProfileOption(
        id: 'break',
        ko: '공강 시간에는 주로 무엇을 하나요?',
        en: 'What do you usually do between classes?'),
    SocialProfileOption(
        id: 'movie',
        ko: '요즘 가장 재미있게 본 영화는 무엇인가요?',
        en: 'What is the best movie you watched recently?'),
    SocialProfileOption(
        id: 'exercise',
        ko: '같이 시작하기 좋은 운동을 추천해 주세요.',
        en: 'What exercise is good to start together?'),
    SocialProfileOption(
        id: 'campus',
        ko: '학교생활에서 꼭 해보고 싶은 것이 있나요?',
        en: 'What do you want to try during campus life?'),
    SocialProfileOption(
        id: 'korea',
        ko: '한국에서 꼭 가보고 싶은 곳이 있나요?',
        en: 'Where would you like to visit in Korea?'),
    SocialProfileOption(
        id: 'recent',
        ko: '요즘 가장 빠져 있는 것은 무엇인가요?',
        en: 'What are you into these days?'),
  ];

  static const friendshipPrompts = <SocialProfileOption>[
    SocialProfileOption(
        id: 'say_hi',
        ko: '먼저 말 걸어주면 좋아해요.',
        en: 'I like it when you say hi first.'),
    SocialProfileOption(
        id: 'meal',
        ko: '같이 밥을 먹으면 금방 친해져요.',
        en: 'Sharing a meal helps me open up.'),
    SocialProfileOption(
        id: 'meme',
        ko: '밈을 보내주면 빨리 친해져요.',
        en: 'Send me a meme and we will click.'),
    SocialProfileOption(
        id: 'exercise',
        ko: '같이 운동하면 어색함이 사라져요.',
        en: 'Working out together breaks the ice.'),
    SocialProfileOption(
        id: 'dessert',
        ko: '카페와 디저트 이야기라면 언제든 환영해요.',
        en: 'Cafe and dessert talk is always welcome.'),
    SocialProfileOption(
        id: 'quiet',
        ko: '처음에는 조용하지만 친해지면 장난이 많아요.',
        en: 'I am quiet at first, playful later.'),
    SocialProfileOption(
        id: 'spontaneous',
        ko: '즉흥적인 약속도 좋아해요.',
        en: 'I enjoy spontaneous plans.'),
    SocialProfileOption(
        id: 'small_group',
        ko: '소수의 사람과 편하게 만나는 것을 좋아해요.',
        en: 'I prefer relaxed small-group meetups.'),
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
