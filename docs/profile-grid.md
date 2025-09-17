# 프로필 그리드 기능 문서

## 개요

프로필 그리드 기능은 사용자가 Instagram과 유사한 형태의 프로필 화면을 통해 자신의 포스트를 그리드 형태로 볼 수 있는 기능입니다. 이 기능은 Feature Flag로 제어되며 기본적으로 비활성화되어 있습니다.

## Feature Flag 설정

### 기본 설정
- **Flag 이름**: `FEATURE_PROFILE_GRID`
- **기본값**: `false` (비활성화)
- **제어 방법**: Firebase Remote Config, SharedPreferences, 환경변수

### 활성화 방법

#### 1. Firebase Remote Config (프로덕션 권장)
1. Firebase Console → Remote Config
2. 새 매개변수 추가:
   - **키**: `feature_profile_grid`
   - **기본값**: `false`
   - **조건**: 필요에 따라 설정 (예: 특정 사용자 그룹)
3. 변경사항 게시

#### 2. 로컬 오버라이드 (개발/테스트용)
```dart
// 개발 중 테스트를 위한 로컬 활성화
await FeatureFlagService().setLocalOverride(
  FeatureFlagService.FEATURE_PROFILE_GRID, 
  true
);
```

#### 3. 환경변수 (빌드 시)
```bash
flutter build apk --dart-define=FLUTTER_FEATURE_PROFILE_GRID=true
```

## 라우트 설정

### 접근 방법
- Feature Flag가 활성화된 경우에만 라우트 노출
- 기본 사용자는 기존 MyPageScreen 사용
- Deep Link: `/profile-grid/{userId}` (활성화된 경우에만)

### 네비게이션 예시
```dart
// Feature Flag 확인 후 네비게이션
if (FeatureFlagService().isFeatureEnabled(FeatureFlagService.FEATURE_PROFILE_GRID)) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => ProfileGridScreen(userId: targetUserId),
    ),
  );
} else {
  // 기존 프로필 화면으로 이동
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => MyPageScreen(),
    ),
  );
}
```

## 데이터베이스 스키마

### 사용자별 포스트 컬렉션
```
users/{userId}/posts/{postId}
{
  "postId": "string",
  "authorId": "string",
  "type": "text" | "image" | "meetup_review",
  "coverPhotoUrl": "string?",
  "text": "string",
  "createdAt": "timestamp",
  "visibility": "public" | "friends",
  "meta": {
    "likeCount": "number",
    "commentCount": "number",
    "meetupId": "string?" // meetup_review 타입인 경우
  }
}
```

### 하이라이트 컬렉션
```
users/{userId}/highlights/{highlightId}
{
  "id": "string",
  "title": "string",
  "thumbnailUrl": "string?",
  "backgroundColor": "string?",
  "postIds": ["string"],
  "createdAt": "timestamp"
}
```

### 통계 캐시 컬렉션
```
users/{userId}/stats/summary
{
  "posts": "number",
  "likes": "number", 
  "comments": "number",
  "lastUpdated": "timestamp"
}
```

## API 엔드포인트

### 주요 서비스 함수

#### ProfileDataAdapter
```dart
// 프로필 조회
Future<UserProfile?> fetchUserProfile(String uid)

// 포스트 스트림 (페이징 지원)
Stream<List<ProfilePost>> streamUserPosts(
  String uid, {
  int pageSize = 24,
  DocumentSnapshot? startAfter,
})

// 친구 관계 확인
Future<bool> isViewerFriend(String viewerUid, String ownerUid)

// 미팅 리뷰에서 포스트 생성
Future<bool> createPostFromReview(String userId, Map<String, dynamic> reviewData)

// 포스트 통계 조회
Future<Map<String, int>> getUserPostStats(String uid)
```

#### ProfileImageAdapter
```dart
// 프로필 포스트 이미지 업로드
Future<String?> uploadProfilePostImage(File imageFile, String userId)

// 여러 이미지 업로드
Future<List<String>> uploadMultipleImages(List<File> imageFiles, String userId)
```

### 사용 예시

```dart
// 프로필 데이터 로드
final adapter = ProfileDataAdapter();
final profile = await adapter.fetchUserProfile('user123');
final stats = await adapter.getUserPostStats('user123');

// 포스트 스트림 구독
adapter.streamUserPosts('user123', pageSize: 24).listen((posts) {
  // UI 업데이트
});

// 이미지 업로드
final imageAdapter = ProfileImageAdapter();
final imageUrl = await imageAdapter.uploadProfilePostImage(imageFile, 'user123');
```

## UI 스펙

### 프로필 헤더
- **Avatar**: 88dp 원형
- **이름**: 18sp bold
- **서브텍스트**: 14sp muted
- **통계**: 숫자 16sp bold + 라벨 12sp muted (posts, participationCount, writtenPosts)
- **버튼**: 프로필 편집 outline, 높이 36dp, radius 18dp

### 하이라이트 릴
- **레이아웃**: 수평 스크롤
- **썸네일**: diameter 64dp
- **간격**: 16dp
- **스크롤**: BouncingScrollPhysics

### 포스트 그리드
- **레이아웃**: 3열 그리드
- **간격**: 2dp
- **페이징**: Lazy loading, 페이지 크기 24
- **썸네일**: center-crop
- **접근성**: 모든 터치 타깃 최소 48dp, 이미지에 semanticLabel

### 탭 토글
- **모드**: Grid/List/Tagged
- **기본값**: Grid
- **높이**: 44dp
- **인디케이터**: 하단 border

## 필요한 수동 작업

### 1. Firestore 보안 규칙 추가
```bash
# migration/firestore.rules.additions 파일의 내용을
# Firebase Console → Firestore → 규칙에 수동으로 추가
```

### 2. Firestore 인덱스 생성
```bash
# migration/firestore.indexes.md 파일의 지시에 따라
# Firebase Console에서 인덱스 생성
```

### 3. Firebase Remote Config 설정
1. Firebase Console → Remote Config
2. `feature_profile_grid` 매개변수 추가
3. 기본값: `false`
4. 필요시 조건부 값 설정

### 4. 의존성 설치
```bash
flutter pub get
```

## 테스트 방법

### 1. 로컬 테스트
```dart
// main.dart 또는 적절한 위치에서
await FeatureFlagService().init();
await FeatureFlagService().setLocalOverride(
  FeatureFlagService.FEATURE_PROFILE_GRID, 
  true
);
```

### 2. Firebase 연결 테스트
```dart
// Feature Flag 상태 확인
final isEnabled = FeatureFlagService().isFeatureEnabled(
  FeatureFlagService.FEATURE_PROFILE_GRID
);
print('Profile Grid 활성화: $isEnabled');
```

### 3. UI 테스트
1. 앱 실행
2. Feature Flag 활성화 확인
3. 프로필 화면 접근
4. 그리드, 헤더, 하이라이트 등 UI 요소 확인

### 4. 데이터 테스트
```dart
// 테스트 포스트 생성
final adapter = ProfileDataAdapter();
await adapter.createPostFromReview('testUser', {
  'content': 'Test post content',
  'imageUrl': 'https://example.com/image.jpg',
  'meetupId': 'meetup123',
});
```

## 롤백 방법

### 긴급 비활성화
1. **Remote Config**: Firebase Console에서 `feature_profile_grid`를 `false`로 변경
2. **로컬 비활성화**: 
   ```dart
   await FeatureFlagService().setLocalOverride(
     FeatureFlagService.FEATURE_PROFILE_GRID, 
     false
   );
   ```

### 완전 제거 (필요한 경우)
1. Feature Flag 관련 코드 주석처리
2. 라우트에서 ProfileGridScreen 제거
3. 메뉴에서 관련 링크 제거
4. 기존 MyPageScreen으로 모든 프로필 접근 리다이렉트

## 호환성 확인

### 기존 기능 유지
- ✅ 기존 MyPageScreen 정상 작동
- ✅ 기존 포스트 생성/조회 시스템 정상 작동
- ✅ 기존 Storage 업로드 시스템 재사용
- ✅ 기존 인증 시스템 재사용

### 새 기능 분리
- ✅ 새로운 컬렉션 사용 (users/{uid}/posts)
- ✅ 기존 posts 컬렉션과 독립적
- ✅ Feature Flag로 완전 분리
- ✅ 기존 UI 라우트와 충돌 없음

## 모니터링 및 로그

### 주요 이벤트 로깅
- 프로필 그리드 화면 접근
- 포스트 그리드 로드
- 이미지 업로드 성공/실패
- Feature Flag 상태 변경

### 성능 메트릭
- 프로필 로드 시간
- 포스트 그리드 렌더링 시간
- 이미지 로드 성공률
- 페이지네이션 성능

### 오류 추적
- Feature Flag 초기화 실패
- 프로필 데이터 로드 실패
- 이미지 업로드 실패
- 권한 관련 오류
