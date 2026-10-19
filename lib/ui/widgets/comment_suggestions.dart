import '../../models/post_category.dart';

/// 카드 댓글 시트의 추천 문장. 서버·AI 없이 글 분류별 상수로 둔다.
/// 한 문장은 ko/en/zh를 함께 가져서, 칩은 내 언어로 보이고
/// 미리보기는 작성자 언어 버전을 번역 호출 없이 바로 쓴다.
class CommentSuggestion {
  const CommentSuggestion(this.ko, this.en, this.zh);

  final String ko;
  final String en;
  final String zh;

  /// ko/en/zh가 아니면 null.
  String? inLanguage(String code) => switch (code) {
        'ko' => ko,
        'en' => en,
        'zh' => zh,
        _ => null,
      };

  /// 화면 언어(ko/en/zh 밖이면 영어).
  String forUi(String code) => inLanguage(code) ?? en;
}

const _defaults = [
  CommentSuggestion('좋네요!', 'Nice!', '真不错！'),
  CommentSuggestion('저도 궁금해요', "I'm curious too", '我也很好奇'),
  CommentSuggestion('ㅋㅋㅋ 공감해요', 'So relatable', '太有同感了'),
];

const commentSuggestionsByCategory = <PostCategory, List<CommentSuggestion>>{
  PostCategory.style: [
    CommentSuggestion('너무 잘 어울려요', 'Looks great on you', '很适合你'),
    CommentSuggestion('어디서 샀어요?', 'Where did you get it?', '在哪里买的？'),
    CommentSuggestion('저도 따라 해 볼래요', 'I want to try it too', '我也想试试'),
  ],
  PostCategory.create: [
    CommentSuggestion('여기 어디예요?', 'Where is this?', '这是哪里？'),
    CommentSuggestion('저도 가 보고 싶어요', 'I want to go too', '我也想去'),
    CommentSuggestion('메뉴 추천해 주세요', 'Any menu picks?', '推荐一下菜单吧'),
  ],
  PostCategory.photo: [
    CommentSuggestion('사진 너무 좋아요', 'Love this photo', '照片太好看了'),
    CommentSuggestion('어디서 찍었어요?', 'Where was this taken?', '在哪里拍的？'),
    CommentSuggestion('분위기 최고예요', 'Such a great vibe', '氛围太棒了'),
  ],
  PostCategory.content: [
    CommentSuggestion('재밌게 봤어요', 'This was fun', '看得很开心'),
    CommentSuggestion('더 알려 주세요', 'Tell me more', '再多说说吧'),
    CommentSuggestion('저도 궁금했어요', 'I was curious too', '我也很好奇'),
  ],
  PostCategory.cafe: [
    CommentSuggestion('여기 어디예요?', 'Where is this café?', '这家店在哪？'),
    CommentSuggestion('커피 맛 어때요?', "How's the coffee?", '咖啡好喝吗？'),
    CommentSuggestion('같이 가고 싶어요', "Let's go together", '想一起去'),
  ],
  PostCategory.academicStudy: [
    CommentSuggestion('수업 화이팅!', 'Good luck in class!', '上课加油！'),
    CommentSuggestion('무슨 수업이에요?', 'Which class is it?', '是什么课？'),
    CommentSuggestion('저도 같이 공부해요', "Let's study together", '一起学习吧'),
  ],
  PostCategory.booksWriting: [
    CommentSuggestion('무슨 책이에요?', 'Which book is it?', '是什么书？'),
    CommentSuggestion('저도 읽어 볼게요', "I'll read it too", '我也去读读'),
    CommentSuggestion('글 잘 읽었어요', 'Enjoyed your writing', '写得真好'),
  ],
  PostCategory.travelLocal: [
    CommentSuggestion('여기 어디예요?', 'Where is this?', '这是哪里？'),
    CommentSuggestion('저도 가 보고 싶어요', 'I want to visit too', '我也想去'),
    CommentSuggestion('여행 즐거웠겠다', 'Sounds like a fun trip', '旅行一定很开心'),
  ],
  PostCategory.global: [
    CommentSuggestion('저도 궁금해요', "I'm curious too", '我也很好奇'),
    CommentSuggestion('좋은 정보 고마워요', 'Thanks for sharing', '谢谢分享'),
    CommentSuggestion('저도 같은 생각이에요', 'I feel the same', '我也这么想'),
  ],
  PostCategory.other: _defaults,
};

/// 글 분류의 추천 문장 3개(분류가 없거나 모르면 기본).
List<CommentSuggestion> commentSuggestionsFor(String categoryKey) =>
    commentSuggestionsByCategory[
        PostCategory.fromPersistedValue(categoryKey)] ??
    _defaults;
