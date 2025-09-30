# 디자인 시스템 사용 가이드

## 개요
이 문서는 앱의 일관된 디자인 시스템 사용을 위한 가이드라인입니다.

## 필수 Import 규칙

### BrandColors 또는 IconStyles를 사용하는 파일
다음 클래스들을 사용하는 모든 파일에는 반드시 아래 import를 추가해야 합니다:

```dart
import '../design/tokens.dart';  // UI 위젯 파일의 경우
import '../../design/tokens.dart';  // screens 폴더 파일의 경우
```

**사용하는 클래스들:**
- `BrandColors` - 브랜드 색상 (primary, secondary, 카테고리별 색상 등)
- `IconStyles` - 통일된 아이콘 (outlined 스타일)
- `ComponentStyles` - 컴포넌트 스타일 (버튼, 검색창 등)
- `DesignTokens` - 간격, 반지름, elevation 등

## 브랜드 컬러 사용법

### 주요 브랜드 컬러
```dart
BrandColors.primary        // #4A90E2 (메인 블루)
BrandColors.secondary      // #6BC9A5 (보조 그린)
BrandColors.success        // #27AE60 (성공 상태)
BrandColors.error          // #E74C3C (오류 상태)
BrandColors.warning        // #F39C12 (경고 상태)
```

### 카테고리별 컬러
```dart
BrandColors.study          // #4A90E2 (스터디)
BrandColors.food           // #FF8C42 (식사)
BrandColors.hobby          // #6BC9A5 (취미)
BrandColors.culture        // #9B59B6 (문화)
BrandColors.general        // #95A5A6 (기타)
```

### 중성 컬러
```dart
BrandColors.neutral50      // 가장 밝은 회색
BrandColors.neutral100     // 밝은 회색
BrandColors.neutral200     // ...
BrandColors.neutral500     // 중간 회색 (보조 텍스트용)
BrandColors.neutral600     // 어두운 회색 (아이콘용)
BrandColors.neutral900     // 가장 어두운 회색
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

## 컴포넌트 스타일 사용법

### 버튼 스타일
```dart
// Primary 버튼
ElevatedButton(
  style: ComponentStyles.primaryButton,
  onPressed: onPressed,
  child: Text('버튼 텍스트'),
)

// Secondary 버튼
OutlinedButton(
  style: ComponentStyles.secondaryButton,
  onPressed: onPressed,
  child: Text('버튼 텍스트'),
)

// Text 버튼
TextButton(
  style: ComponentStyles.textButton,
  onPressed: onPressed,
  child: Text('버튼 텍스트'),
)
```

### 검색창 스타일
```dart
TextField(
  decoration: ComponentStyles.searchFieldDecoration,
  // 다른 속성들...
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
