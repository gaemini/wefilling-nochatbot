# Firestore 컬렉션 사전 (Wefilling)

이 문서는 Wefilling 프로젝트의 Firestore 컬렉션을 **운영/개발 관점에서 일관되게 관리**하기 위한 “컬렉션 사전”입니다.

## 목표

- **컬렉션/문서 ID 규약 통일**: 오타/중복/정합성 문제 방지
- **핵심 필드 표준화**: 쿼리/인덱스/룰 변경 시 영향도 파악 용이
- **휘발 데이터 관리**: 만료 데이터 자동 정리(예: 이메일 인증번호)
- **권한 경계 명확화**: “클라이언트 직접 접근 금지” 컬렉션을 명시

## 공통 규약

- **컬렉션/필드명**: `snake_case` (예: `friend_requests`, `email_verifications`)
- **문서 ID**:
  - 이메일 기반 docId는 **정규화(normalized)** 사용: `trim + lowerCase`
  - 두 UID의 “쌍(pair)”은 **정렬 후 결합**:
    - `friendships`: `{uid1}__{uid2}` (사전순)
    - `conversations`: `{uid1}_{uid2}` (사전순)
  - 요청/차단은 방향성이 있으므로 **그대로 결합**:
    - `friend_requests`: `{fromUid}_{toUid}`
    - `blocks`: `{blockerUid}_{blockedUid}`

## 최상위 컬렉션

### 인증/한양메일 관련

- **`users/{uid}`**
  - **용도**: 사용자 프로필 + 한양메일 인증 결과 저장
  - **핵심 필드**:
    - `emailVerified: bool` (한양메일 인증 완료 여부)
    - `hanyangEmail: string` (인증된 한양메일, 정규화 저장 권장)
    - `createdAt`, `updatedAt`, `lastLogin`

- **`email_claims/{normalizedEmail}`** *(서버 전용)*
  - **용도**: 한양메일 “중복 사용 방지/점유” 레지스트리(유니크 락)
  - **핵심 필드**:
    - `email: string` (정규화 이메일)
    - `uid: string` (점유자)
    - `status: 'active' | 'released'`
    - `createdAt`, `updatedAt`, `releasedAt`
  - **접근**: 클라이언트 직접 접근 금지(룰에서 `false`)

- **`email_verifications/{normalizedEmail}`** *(서버 전용, 휘발성)*
  - **용도**: “4자리 인증번호(OTP)” 임시 저장(메일 인증용)
  - **핵심 필드**:
    - `code: string`
    - `expiresAt: Timestamp` (기본 5분)
    - `attempts: number` (최대 3회)
    - `emailNormalized: string`
  - **정리 정책**:
    - 성공/만료 시 즉시 삭제
    - 추가로 스케줄 함수로 만료 문서 주기적 청소 권장
  - **접근**: 클라이언트 직접 접근 금지(룰에서 `false`)

### 콘텐츠/커뮤니티

- **`posts/{postId}`**
  - **용도**: 커뮤니티 게시글(공개/카테고리 공개 포함)
  - **대표 서브컬렉션**:
    - `posts/{postId}/comments/{commentId}`
    - `posts/{postId}/pollVotes/{uid}` (1인 1표 기록)

- **`comments/{commentId}`**
  - **용도**: 최상위 댓글(게시글/모임 공통으로 쓰는 구조)

- **`meetups/{meetupId}`**
  - **용도**: 모임(이벤트) 문서
  - **대표 서브컬렉션**:
    - `meetups/{meetupId}/comments/{commentId}`

### DM/알림

- **`conversations/{conversationId}`**
  - **용도**: DM 대화방
  - **문서 ID 규칙**:
    - 일반: `{uid1}_{uid2}` (사전순)
    - 익명: `anon_{uid1}_{uid2}_{postId}` (규칙은 보안룰에 맞게 유지)
  - **서브컬렉션**:
    - `conversations/{conversationId}/messages/{messageId}`

- **`notifications/{notificationId}`**
  - **용도**: 앱 알림 데이터(읽음 처리 포함)

### 관계/친구

- **`friend_requests/{fromUid}_{toUid}`**
  - **용도**: 친구 요청(상태 기반)
  - **상태**: `PENDING | CANCELED | ACCEPTED | REJECTED`

- **`friendships/{uid1}__{uid2}`**
  - **용도**: 친구 관계(서버에서만 쓰기 권장)

- **`blocks/{blockerUid}_{blockedUid}`**
  - **용도**: 차단 관계(서버에서만 쓰기 권장)

- **`relationships/{relationshipId}`**
  - **용도**: 관계(친밀도 등) 저장

- **`friend_categories/{categoryId}`**
  - **용도**: 친구 카테고리(그룹)

### 후기/리뷰

- **`meetup_reviews/{reviewId}`**
  - **용도**: 모임 후기 원본(합의/참여자 승인 플로우 포함)

- **`review_requests/{requestId}`**
  - **용도**: 후기 승인 요청(참여자별 요청)

- **`reviews/{reviewId}`**
  - **용도**: 프로필/피드 노출용 후기(발행된 최종 형태)

- **`meetup_participants/{participantId}`**
  - **용도**: 모임 참가자 상태(신청/승인 등)

- **`meetings/{meetupId}/pendingReviews/{reviewId}`**
- **`meetings/{meetupId}/reviews/{consensusId}`**
  - **용도**: 리뷰 합의 기능 관련 서브컬렉션

### 설정/운영

- **`user_settings/{uid}`**
  - **용도**: 사용자 설정(알림 설정 등)

- **`admin_settings/{docId}`**
  - **용도**: 운영/피처 플래그(관리자만 쓰기)

- **`ad_banners/{bannerId}`**
  - **용도**: 광고 배너(관리자 콘솔에서 관리)

- **`recommended_places/{category}`**
  - **용도**: 추천 장소(카테고리별 문서)

- **`reports/{reportId}`**
  - **용도**: 신고(클라이언트 생성만 허용, 읽기/수정은 관리자 전용 권장)

## 운영 팁(권장)

- **ID/경로 상수화**: Flutter/Functions 모두 “컬렉션 이름 문자열”을 상수로 관리
- **휘발 데이터 청소**: `email_verifications`는 스케줄 함수로 만료 문서 정리
- **인덱스 관리**: “자주 쓰는 쿼리”는 `firestore.indexes.json`에 명시해 재현 가능하게 유지

