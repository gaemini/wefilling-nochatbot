# 향상된 디자인 시스템 가이드 - Instagram 영감 + 독창성

## 개요
이 문서는 Instagram의 세련된 디자인에서 영감을 받아 개발된 독창적인 디자인 시스템 사용 가이드입니다.
가독성과 통일감을 최우선으로 하며, 현대적이고 완성도 높은 UI를 제공합니다.

## 필수 Import 규칙

### BrandColors 또는 IconStyles를 사용하는 파일
다음 클래스들을 사용하는 모든 파일에는 반드시 아래 import를 추가해야 합니다:

```dart
import '../design/tokens.dart';  // UI 위젯 파일의 경우
import '../../design/tokens.dart';  // screens 폴더 파일의 경우
```

**사용하는 클래스들:**
- `BrandColors` - Instagram 영감 색상 팔레트 (그라디언트, 모던 컬러)
- `TypographyStyles` - 향상된 타이포그래피 시스템 (가독성 최적화)
- `ComponentStyles` - Instagram 스타일 컴포넌트 (버튼, 카드, 액션 등)
- `IconStyles` - 통일된 아이콘 시스템
- `DesignTokens` - 간격, 반지름, 애니메이션 등

## 향상된 브랜드 컬러 시스템

### Instagram 영감 Primary Colors
```dart
BrandColors.primary        // #6366F1 (모던 인디고)
BrandColors.primaryLight   // #818CF8 (밝은 인디고)
BrandColors.secondary      // #EC4899 (인스타그램 핑크)
BrandColors.accent         // #10B981 (에메랄드 그린)
```

### 그라디언트 사용
```dart
BrandColors.primaryGradient  // 인디고→퍼플→핑크 그라디언트
BrandColors.subtleGradient   // 부드러운 배경 그라디언트
```

### 텍스트 컬러 (가독성 최적화)
```dart
BrandColors.textPrimary    // #0F172A (매우 진한 슬레이트)
BrandColors.textSecondary  // #475569 (중간 슬레이트)
BrandColors.textTertiary   // #64748B (밝은 슬레이트)
BrandColors.textHint       // #94A3B8 (매우 밝은 슬레이트)
```

## 향상된 타이포그래피 시스템

### Instagram 스타일 텍스트
```dart
// 사용자명 (굵고 작음)
TypographyStyles.username

// 캡션 (일반 굵기, 가독성 좋음)
TypographyStyles.caption

// 좋아요 수 (굵게)
TypographyStyles.likeCount

// 시간 표시 (작고 연하게)
TypographyStyles.timestamp
```

### 계층적 제목 시스템
```dart
TypographyStyles.displayLarge    // 36px, w800 (히어로 섹션)
TypographyStyles.headlineLarge   // 24px, w700 (페이지 제목)
TypographyStyles.titleLarge      // 18px, w600 (카드 제목)
TypographyStyles.bodyLarge       // 16px, w400 (본문)
```

## 아이콘 사용법

### 통일된 아이콘 스타일 (outlined)
```dart
IconStyles.home            // 홈
IconStyles.groups          // 모임
IconStyles.article         // 게시글
IconStyles.person          // 사용자
IconStyles.search          // 검색
IconStyles.add             // 추가
IconStyles.edit            // 수정
IconStyles.bookmark        // 북마크
IconStyles.favorite        // 좋아요
```

### 카테고리별 아이콘
```dart
IconStyles.study           // Icons.school_outlined
IconStyles.food            // Icons.restaurant_outlined
IconStyles.hobby           // Icons.palette_outlined
IconStyles.culture         // Icons.theater_comedy_outlined
IconStyles.general         // Icons.groups_outlined
```

## Instagram 스타일 컴포넌트 시스템

### 향상된 버튼 스타일
```dart
// Primary 버튼 (플랫한 디자인, 둥근 모서리)
ElevatedButton(
  style: ComponentStyles.primaryButton,
  onPressed: onPressed,
  child: Text('버튼 텍스트', style: TypographyStyles.buttonText),
)

// Secondary 버튼 (세련된 테두리)
OutlinedButton(
  style: ComponentStyles.secondaryButton,
  onPressed: onPressed,
  child: Text('버튼 텍스트'),
)
```

### Instagram 스타일 액션 버튼
```dart
// 좋아요 버튼
ComponentStyles.likeButton(
  isLiked: isLiked,
  onTap: () => toggleLike(),
  size: 26,
)

// 북마크 버튼
ComponentStyles.bookmarkButton(
  isBookmarked: isBookmarked,
  onTap: () => toggleBookmark(),
  size: 26,
)

// 공유 버튼
ComponentStyles.shareButton(
  onTap: () => share(),
  size: 26,
)
```

### 향상된 입력 필드
```dart
// 검색창 (더 둥글게)
TextField(
  decoration: ComponentStyles.searchFieldDecoration,
)

// 댓글 입력창 (Instagram 스타일)
TextField(
  decoration: ComponentStyles.commentFieldDecoration,
)
```

## FAB 사용법

### 통일된 FAB 사용
```dart
// 글쓰기 FAB
AppFab.write(
  onPressed: () => navigateToCreatePost(),
  heroTag: 'write_fab',
)

// 모임 만들기 FAB
AppFab.createMeetup(
  onPressed: () => navigateToCreateMeetup(),
  heroTag: 'meetup_fab',
)

// 친구 추가 FAB
AppFab.addFriend(
  onPressed: () => navigateToAddFriend(),
  heroTag: 'friend_fab',
)
```

## Empty State 사용법

### 사전 정의된 Empty State
```dart
// 모임이 없을 때
AppEmptyState.noMeetups(
  onCreateMeetup: () => navigateToCreateMeetup(),
)

// 게시글이 없을 때
AppEmptyState.noPosts(
  onCreatePost: () => navigateToCreatePost(),
)

// 친구가 없을 때
AppEmptyState.noFriends(
  onSearchFriends: () => navigateToSearchFriends(),
)

// 검색 결과가 없을 때
AppEmptyState.noSearchResults(
  searchQuery: query,
  onClearSearch: () => clearSearch(),
)
```

## 체크리스트

### 새 파일 생성 시
- [ ] BrandColors나 IconStyles를 사용하나요?
- [ ] `import '../design/tokens.dart';` 또는 `import '../../design/tokens.dart';`를 추가했나요?
- [ ] 하드코딩된 색상 대신 BrandColors를 사용했나요?
- [ ] 하드코딩된 아이콘 대신 IconStyles를 사용했나요?

### 기존 파일 수정 시
- [ ] 새로운 BrandColors나 IconStyles를 추가했나요?
- [ ] 필요한 import가 있나요?
- [ ] 컴파일 오류가 없나요?

### 디자인 일관성 확인
- [ ] 모든 주요 버튼이 동일한 스타일을 사용하나요?
- [ ] 모든 아이콘이 outlined 스타일인가요?
- [ ] 검색창 플레이스홀더가 "검색어를 입력하세요"로 통일되어 있나요?
- [ ] FAB가 브랜드 컬러를 사용하나요?

## 문제 해결

### 컴파일 오류 발생 시
1. **"The getter 'BrandColors' isn't defined"** 오류:
   ```dart
   import '../design/tokens.dart';  // 또는 ../../design/tokens.dart
   ```

2. **"The getter 'IconStyles' isn't defined"** 오류:
   ```dart
   import '../design/tokens.dart';  // 또는 ../../design/tokens.dart
   ```

3. **"Member not found: 'error'"** 오류:
   - IconStyles에서 사용 가능한 아이콘 확인
   - 누락된 아이콘은 tokens.dart에 추가 필요

4. **"No named parameter with the name 'decoration'"** 오류:
   - Card 위젯은 decoration 매개변수가 없음
   - Container 위젯 사용하거나 Card의 기본 속성 활용
   ```dart
   // 잘못된 사용
   Card(decoration: ComponentStyles.cardDecoration, ...)
   
   // 올바른 사용
   Container(decoration: ComponentStyles.cardDecoration, child: ListTile(...))
   ```

5. **경로가 맞지 않는 경우**:
   - `lib/ui/widgets/` 폴더: `import '../../design/tokens.dart';`
   - `lib/screens/` 폴더: `import '../design/tokens.dart';`

### 색상이 일관되지 않는 경우
- 하드코딩된 색상 (`Colors.blue`, `Colors.red` 등) 대신 `BrandColors` 사용
- 카테고리별 색상은 `BrandColors.study`, `BrandColors.food` 등 사용

### 아이콘이 일관되지 않는 경우
- `Icons.home` 대신 `IconStyles.home` 사용
- 모든 아이콘이 outlined 스타일인지 확인

이 가이드라인을 따르면 일관된 디자인 시스템을 유지하고 컴파일 오류를 방지할 수 있습니다.
