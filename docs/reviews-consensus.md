# 리뷰 합의 기능 (Review Consensus Feature)

## 📋 개요

리뷰 합의 기능은 모임 참여자들이 서로에게 리뷰를 요청하고, 합의된 의견을 도출할 수 있는 새로운 기능입니다. Feature Flag로 보호되어 안전하게 배포 및 롤백이 가능합니다.

## 🏗️ 아키텍처

### 전체 구조
```
리뷰 합의 기능
├── Feature Flag 시스템 (FeatureFlagService)
├── 어댑터 패턴 (기존 서비스 재사용)
├── 새로운 데이터 모델 (ReviewRequest, ReviewConsensus)
├── UI 화면 (ReviewRequestScreen, ReviewAcceptScreen)
├── 보안 규칙 (Firestore Rules 확장)
└── 테스트 및 검증
```

### 컴포넌트 구성
- **FeatureFlagService**: 기능 활성화/비활성화 제어
- **ReviewConsensusService**: 핵심 비즈니스 로직
- **ReviewAdapterServices**: 기존 서비스 재사용을 위한 어댑터
- **Data Models**: 새로운 데이터 구조 정의
- **UI Screens**: 사용자 인터페이스
- **Security Rules**: Firestore 보안 규칙

## 🚀 기능 명세

### 주요 기능

1. **리뷰 요청 생성**
   - 모임 참여자가 다른 참여자에게 리뷰 요청
   - 이미지 첨부 지원 (최대 5개)
   - 요청 메시지 작성
   - 7일 자동 만료

2. **리뷰 요청 응답**
   - 수락/거절 선택
   - 응답 메시지 작성 (선택사항)
   - 실시간 알림 발송

3. **리뷰 합의 도출**
   - 참여자별 평점 및 코멘트 수집
   - 자동 합의 타입 결정 (긍정적/부정적/중립적/혼재)
   - 태그 카운트 및 통계 생성

4. **알림 시스템**
   - 리뷰 요청/수락/거절/완료 알림
   - 기존 알림 시스템과 통합

## 💾 데이터베이스 스키마

### 새로운 컬렉션 (비파괴적 추가)

#### 1. meetings/{meetupId}/pendingReviews/{reviewId}
```javascript
{
  meetupId: string,           // 모임 ID
  requesterId: string,        // 요청자 ID
  requesterName: string,      // 요청자 이름
  recipientId: string,        // 수신자 ID  
  recipientName: string,      // 수신자 이름
  meetupTitle: string,        // 모임 제목
  message: string,            // 요청 메시지
  imageUrls: string[],        // 첨부 이미지 URLs
  status: string,             // pending/accepted/rejected/expired
  createdAt: Timestamp,       // 생성 시간
  respondedAt: Timestamp?,    // 응답 시간
  expiresAt: Timestamp,       // 만료 시간
  responseMessage: string?    // 응답 메시지
}
```

#### 2. meetings/{meetupId}/reviews/{consensusId}
```javascript
{
  meetupId: string,                    // 모임 ID
  meetupTitle: string,                 // 모임 제목
  hostId: string,                      // 주최자 ID
  hostName: string,                    // 주최자 이름
  participantIds: string[],            // 참여자 IDs
  participantReviews: {                // 참여자별 리뷰
    [userId]: {
      userId: string,
      userName: string,
      rating: number,
      comment: string,
      tags: string[],
      imageUrls: string[],
      submittedAt: Timestamp
    }
  },
  consensusType: string,               // positive/negative/neutral/mixed
  averageRating: number,               // 평균 평점
  summary: string,                     // 합의 요약
  consensusImageUrls: string[],        // 합의 이미지들
  tagCounts: { [tag]: number },        // 태그 카운트
  createdAt: Timestamp,                // 생성 시간
  finalizedAt: Timestamp,              // 최종화 시간
  statistics: object,                  // 통계 데이터
  metadata: object                     // 메타데이터
}
```

#### 3. admin_settings/feature_flags
```javascript
{
  FEATURE_REVIEW_CONSENSUS: boolean,   // 리뷰 합의 기능
  FEATURE_ADVANCED_SEARCH: boolean,    // 고급 검색 기능
  FEATURE_VIDEO_UPLOAD: boolean,       // 비디오 업로드 기능
  FEATURE_REAL_TIME_CHAT: boolean,     // 실시간 채팅 기능
  updatedAt: Timestamp,                // 업데이트 시간
  updatedBy: string                    // 업데이트한 관리자 ID
}
```

### 기존 컬렉션 확장

#### user_settings/{userId}
```javascript
{
  notifications: {
    // 기존 알림 설정들...
    review_requested: boolean,         // 리뷰 요청 알림
    review_accepted: boolean,          // 리뷰 수락 알림  
    review_rejected: boolean,          // 리뷰 거절 알림
    review_completed: boolean          // 리뷰 완료 알림
  },
  updated_at: Timestamp
}
```

## 🔐 보안 규칙

### 새로운 보안 규칙 (기존 규칙에 추가)

```javascript
// Feature Flags (관리자만 변경 가능)
match /admin_settings/{document} {
  allow read: if request.auth != null;
  allow write: if isAdmin();
}

// 리뷰 요청 (모임 참여자만)
match /meetings/{meetupId}/pendingReviews/{reviewId} {
  allow read: if isRequesterOrRecipient();
  allow create: if isValidReviewRequest();
  allow update: if isValidStatusChange();
  allow delete: if false;
}

// 리뷰 합의 (참여자만 읽기, 서버만 쓰기)
match /meetings/{meetupId}/reviews/{consensusId} {
  allow read: if isParticipant(meetupId);
  allow create, update, delete: if false;
}
```

## 🧪 테스트 전략

### 단위 테스트
- Feature Flag 서비스 테스트
- 데이터 모델 테스트
- 어댑터 서비스 테스트
- 비즈니스 로직 테스트

### 통합 테스트
- Feature Flag 격리 테스트
- 기존 기능 호환성 테스트
- 보안 규칙 테스트
- UI 컴포넌트 테스트

### 성능 테스트
- 메모리 사용량 검증
- 앱 시작 시간 영향도 측정
- Firestore 쿼리 성능 테스트

## 📦 배포 가이드

### 1. 사전 준비
```bash
# 기존 기능 테스트
flutter test
flutter analyze

# 호환성 검증
dart scripts/compatibility_check.dart
```

### 2. Feature Flag 설정
```javascript
// Firestore에서 Feature Flag 비활성화 (기본값)
admin_settings/feature_flags: {
  FEATURE_REVIEW_CONSENSUS: false
}
```

### 3. 단계별 배포

#### 단계 1: 코드 배포 (기능 비활성화)
- 모든 새로운 코드 배포
- Feature Flag는 false로 유지
- 기존 기능 정상 동작 확인

#### 단계 2: 보안 규칙 업데이트
```bash
firebase deploy --only firestore:rules
```

#### 단계 3: 베타 테스트
- 일부 사용자에게만 Feature Flag 활성화
- 피드백 수집 및 버그 수정

#### 단계 4: 점진적 롤아웃
- Feature Flag를 true로 변경
- 사용자 반응 모니터링
- 필요시 즉시 롤백

### 4. 모니터링 포인트
- 앱 크래시율
- API 응답 시간
- Firestore 읽기/쓰기 횟수
- 사용자 피드백

## 🔄 롤백 계획

### 즉시 롤백 (Feature Flag 사용)
```javascript
// Firestore에서 즉시 비활성화
admin_settings/feature_flags: {
  FEATURE_REVIEW_CONSENSUS: false
}
```

### 완전 롤백 (코드 제거)
1. 새로운 화면 파일 제거
2. 새로운 서비스 파일 제거  
3. 보안 규칙에서 새로운 규칙 제거
4. 기존 코드에서 Feature Flag 관련 코드 제거

**주의**: 데이터베이스 스키마는 제거하지 않음 (데이터 보존)

## 🛠️ 개발 가이드

### 로컬 개발 환경 설정

#### 1. Feature Flag 로컬 활성화
```dart
// main.dart 또는 개발용 코드에서
final featureFlag = FeatureFlagService();
await featureFlag.setLocalFlag('FEATURE_REVIEW_CONSENSUS', true);
```

#### 2. 테스트 데이터 준비
```dart
// 테스트용 모임 생성
// 테스트용 사용자 계정 준비
// 모임 참여자 설정
```

### 새로운 기능 추가 시 가이드

1. **Feature Flag 확인**: 모든 새로운 기능은 Feature Flag로 보호
2. **어댑터 패턴 사용**: 기존 서비스 재사용
3. **비파괴적 변경**: 기존 데이터 구조 변경 금지
4. **보안 우선**: 새로운 API는 보안 규칙 필수
5. **테스트 우선**: 기능 구현 전 테스트 케이스 작성

## 📊 성능 최적화

### 데이터베이스 인덱스 (수동 생성 필요)
```javascript
// 필요한 복합 인덱스들
pendingReviews: [recipientId, status, createdAt]
pendingReviews: [requesterId, createdAt]  
notifications: [userId, isRead, createdAt]
```

### 캐시 전략
- Feature Flag 값 캐싱 (5분)
- 사용자 프로필 캐싱 (1시간)
- 모임 정보 캐싱 (30분)

### 메모리 최적화
- 싱글톤 패턴 사용
- 이미지 캐시 제한
- 주기적 캐시 정리

## 🚨 문제 해결

### 자주 발생하는 문제들

#### 1. Feature Flag가 작동하지 않음
```dart
// 해결방법
final featureFlag = FeatureFlagService();
featureFlag.clearCache(); // 캐시 초기화
final isEnabled = await featureFlag.isReviewConsensusEnabled;
```

#### 2. 보안 규칙 오류
- Firestore 콘솔에서 규칙 문법 확인
- 테스트 사용자로 권한 테스트
- 규칙 시뮬레이터 사용

#### 3. 알림이 전송되지 않음
- 알림 설정 확인
- Feature Flag 상태 확인
- Firebase Functions 로그 확인

### 디버깅 도구

#### 1. Feature Flag 상태 확인
```dart
final flags = await FeatureFlagService().getAllFlags();
print('Current flags: $flags');
```

#### 2. 서비스 상태 점검
```dart
await ReviewConsensusSmokeTest.runSmokeTests();
```

#### 3. 보안 규칙 테스트
```dart
runSecurityTests();
```

## 📝 변경 로그

### v1.0.0 (2024-01-15)
- 리뷰 합의 기능 초기 릴리즈
- Feature Flag 시스템 구축
- 기존 서비스 어댑터 패턴 적용
- 새로운 데이터 모델 정의
- UI 화면 구현
- 보안 규칙 확장
- 종합 테스트 및 문서화

## 🤝 기여 가이드

### 코드 기여 시 체크리스트
- [ ] Feature Flag로 기능 보호 여부
- [ ] 기존 기능 호환성 확인
- [ ] 단위 테스트 작성
- [ ] 보안 규칙 검토
- [ ] 성능 영향도 평가
- [ ] 문서 업데이트

### Pull Request 템플릿
```markdown
## 변경 내용
- [ ] 새로운 기능 추가
- [ ] 버그 수정
- [ ] 성능 개선
- [ ] 문서 업데이트

## 호환성 체크리스트
- [ ] 기존 게시판/모임 기능 정상 동작 확인
- [ ] 기존 이미지 업로드/프로필 포스트 생성 동작 확인
- [ ] 보안 규칙 테스트 통과
- [ ] Cloud Functions 테스트 통과
- [ ] Feature Flag 기본값 false로 동작 확인

## 테스트 결과
- 단위 테스트: [ ] 통과 / [ ] 실패
- 통합 테스트: [ ] 통과 / [ ] 실패
- 호환성 테스트: [ ] 통과 / [ ] 실패

## 롤백 방법
(기능을 롤백하는 방법 명시)
```

## 📞 지원 및 연락처

- **기술 문의**: [개발팀 이메일]
- **버그 신고**: [이슈 트래커 링크]
- **기능 제안**: [피드백 채널]

---

**⚠️ 주의사항**: 이 기능은 Feature Flag로 보호됩니다. 프로덕션 환경에서는 반드시 단계적으로 활성화하고, 문제 발생 시 즉시 비활성화할 수 있도록 준비해주세요.
