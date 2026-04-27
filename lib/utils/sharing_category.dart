import '../models/post.dart';

/// 나눔(Sharing) 전용 카테고리 정의.
///
/// CreatePostScreen이 나눔 전용으로 개편되면서 새로 작성되는 글은 항상
/// 이 중 하나의 카테고리를 가진다. BoardScreen의 "나눔 / 피드" 탭 구분과
/// OptimizedPostCard의 배지 노출, PostDetailScreen의 진입 게이트 등
/// UI 레벨의 나눔 판단은 이 목록을 단일 기준으로 한다.
const List<String> kSharingCategoryOptions = <String>[
  '생활용품',
  '전자기기',
  '도서',
  '기타',
];

const Set<String> kSharingCategorySet = <String>{...kSharingCategoryOptions};

const String kSharingPostsCollectionPath = 'sharing_posts';

const Map<String, String> kSharingCategoryLabelsEn = <String, String>{
  '생활용품': 'Household',
  '전자기기': 'Electronics',
  '도서': 'Books',
  '기타': 'Other',
};

const Map<String, String> _sharingCategoryAliasToCanonical = <String, String>{
  '생활용품': '생활용품',
  'household': '생활용품',
  'households': '생활용품',
  'furniture': '생활용품',
  'daily necessities': '생활용품',
  'life': '생활용품',
  '전자기기': '전자기기',
  'electronics': '전자기기',
  'electronic': '전자기기',
  'device': '전자기기',
  'devices': '전자기기',
  '도서': '도서',
  'book': '도서',
  'books': '도서',
  'textbook': '도서',
  'textbooks': '도서',
  '기타': '기타',
  'other': '기타',
  'others': '기타',
  'etc': '기타',
  'misc': '기타',
};

String? canonicalSharingCategory(String? category) {
  final raw = category?.trim();
  if (raw == null || raw.isEmpty) return null;
  return _sharingCategoryAliasToCanonical[raw.toLowerCase()] ??
      _sharingCategoryAliasToCanonical[raw];
}

/// 해당 [Post]가 나눔 전용 카테고리를 가지고 있는지 여부.
bool isSharingPost(Post post) {
  if (post.collectionPath == kSharingPostsCollectionPath) return true;
  return canonicalSharingCategory(post.category) != null;
}

/// 문자열 카테고리로 직접 판단해야 할 때 사용.
bool isSharingCategory(String? category) =>
    canonicalSharingCategory(category) != null;
