# Firestore 인덱스 추가 사항

프로필 그리드 기능을 위해 다음 인덱스들을 Firebase Console에서 수동으로 추가해야 합니다.

## 필요한 인덱스

### 1. 사용자별 포스트 정렬 인덱스

```
컬렉션 ID: users/{userId}/posts
필드:
  - authorId (오름차순)
  - createdAt (내림차순)
```

Firebase Console에서 설정:
1. Firestore → 인덱스 → 복합 인덱스 만들기
2. 컬렉션 ID: `users/{userId}/posts`
3. 필드 추가:
   - `authorId`: 오름차순
   - `createdAt`: 내림차순
4. 인덱스 만들기

### 2. 공개성별 포스트 필터링 인덱스

```
컬렉션 ID: users/{userId}/posts
필드:
  - visibility (오름차순)
  - createdAt (내림차순)
```

Firebase Console에서 설정:
1. 컬렉션 ID: `users/{userId}/posts`
2. 필드 추가:
   - `visibility`: 오름차순
   - `createdAt`: 내림차순

### 3. 포스트 타입별 필터링 인덱스

```
컬렉션 ID: users/{userId}/posts
필드:
  - type (오름차순)
  - createdAt (내림차순)
```

Firebase Console에서 설정:
1. 컬렉션 ID: `users/{userId}/posts`
2. 필드 추가:
   - `type`: 오름차순
   - `createdAt`: 내림차순

## 자동 생성 안내

위 인덱스들은 Firebase Console에서 쿼리 실행 시 자동으로 생성 제안이 나타날 수도 있습니다. 
제안이 나타나면 링크를 클릭하여 자동으로 생성할 수 있습니다.

## 인덱스 확인 방법

1. Firebase Console → Firestore → 인덱스
2. "복합" 탭에서 생성된 인덱스 확인
3. 상태가 "빌드 중" → "사용 중"으로 변경될 때까지 대기

## 주의사항

- 인덱스 생성에는 시간이 소요될 수 있습니다 (데이터량에 따라 몇 분~몇 시간)
- 인덱스 생성 중에도 앱은 정상 작동하지만 해당 쿼리는 느릴 수 있습니다
- 인덱스 생성 완료 후 쿼리 성능이 크게 향상됩니다
