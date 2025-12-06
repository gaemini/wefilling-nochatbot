# '남태평양' 계정 DM 메시지 표시 문제 진단 가이드

## 문제 상황
- **증상**: 대화방 목록은 보이지만 메시지 내용이 표시되지 않음
- **범위**: '남태평양' 계정만 발생 (다른 계정은 정상)
- **플랫폼**: Android/iOS 모두 동일한 문제

## 진단 코드 추가 완료

다음 위치에 상세 진단 로그가 추가되었습니다:

### 1. getMessages 메서드 (920-990줄)
- 현재 사용자 UID 출력
- 현재 시간 출력
- 대화방 정보 조회 (participants, userLeftAt, lastMessage 등)
- 서브컬렉션 확인
- 메시지 파싱 성공/실패 상세 로그

### 2. getUserMessageVisibilityStartTime 메서드 (1047-1095줄)
- 나간 시간과 현재 시간 비교
- 시간 차이 계산
- 미래 시간 오류 감지

## 테스트 방법

### 1단계: iOS 기기에 앱 설치
```bash
# Xcode에서 실행하거나
# TestFlight를 통해 배포
```

### 2단계: '남태평양' 계정으로 로그인
1. 앱 실행
2. '남태평양' 계정으로 로그인
3. DM 탭으로 이동

### 3단계: 로그 확인
Xcode Console 또는 디바이스 로그에서 다음 로그를 찾으세요:

```
📋 getMyConversations 시작
  - 현재 사용자: {UID}
```

이 UID를 기록하세요. 이것이 '남태평양' 계정의 Firebase UID입니다.

### 4단계: 문제 대화방 열기
1. 메시지가 안 보이는 대화방 클릭
2. 다음 로그 패턴을 찾으세요:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 getMessages 호출
  - conversationId: {ID}
  - visibilityStartTime: {시간 또는 null}
  - 현재 시간: {현재시간}
✓ 현재 사용자: {UID}
🔍 [진단] 대화방 정보:
  - participants: [...]
  - userLeftAt: {...}
  - lastMessage: ...
  - lastMessageTime: ...
📨 스냅샷 수신: X개 문서
```

### 5단계: 로그 분석

#### 케이스 1: userLeftAt 문제
로그에서 이런 내용이 보이면:
```
⚠️ 경고: 사용자가 대화방을 나간 기록이 있음!
  - 나간 시간: 2025-12-02 10:00:00
```

**원인**: 사용자가 대화방을 나간 것으로 기록되어 있음
**해결**: Firebase Console에서 해당 대화방의 `userLeftAt` 필드 삭제

#### 케이스 2: 미래 시간 문제
로그에서 이런 내용이 보이면:
```
⚠️ 경고: 나간 시간이 미래입니다! 이는 데이터 오류입니다.
```

**원인**: 서버 시간 동기화 오류 또는 데이터 손상
**해결**: Firebase Console에서 해당 대화방의 `userLeftAt` 필드 삭제

#### 케이스 3: 메시지가 없음
로그에서 이런 내용이 보이면:
```
📨 스냅샷 수신: 0개 문서
```

**원인**: 메시지가 실제로 없거나 잘못된 경로에 저장됨
**해결**: Firebase Console에서 `conversations/{conversationId}/messages/` 경로 확인

#### 케이스 4: 메시지 파싱 오류
로그에서 이런 내용이 보이면:
```
❌ 메시지 파싱 실패 (문서 ID: xxx)
   데이터: {...}
   오류: ...
```

**원인**: 메시지 데이터 구조가 잘못됨
**해결**: 로그에 표시된 데이터 구조 확인 및 수정

#### 케이스 5: 대화방이 없음
로그에서 이런 내용이 보이면:
```
⚠️ 대화방 문서가 메인 컬렉션에 존재하지 않음!
❌ 서브컬렉션에도 존재하지 않음!
```

**원인**: 대화방 데이터가 삭제되었거나 생성되지 않음
**해결**: 대화방 재생성 필요

## Firebase Console에서 확인할 사항

### 1. Authentication
- '남태평양' 계정의 UID 확인
- 계정이 활성화되어 있는지 확인

### 2. Firestore Database

#### A. 메인 컬렉션 확인
경로: `conversations/{conversationId}`

필수 필드:
- `participants`: ['남태평양_UID', '상대방_UID']
- `userLeftAt`: {} (비어있어야 함) 또는 남태평양_UID가 없어야 함
- `lastMessage`: 문자열
- `lastMessageTime`: Timestamp

#### B. 서브컬렉션 확인
경로: `users/{남태평양_UID}/conversations/{conversationId}`

동일한 필드 구조 확인

#### C. 메시지 확인
경로: `conversations/{conversationId}/messages/{messageId}`

필수 필드:
- `senderId`: UID
- `text`: 문자열
- `createdAt`: Timestamp

## 문제 해결 방법

### userLeftAt 필드 삭제 (Firebase Console)
1. Firestore Database 열기
2. `conversations/{conversationId}` 문서 찾기
3. `userLeftAt` 필드 확장
4. 남태평양 UID 키 삭제
5. 저장

### userLeftAt 필드 삭제 (Firebase CLI)
```javascript
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

// conversationId와 userId를 실제 값으로 교체
const conversationId = 'YOUR_CONVERSATION_ID';
const userId = 'YOUR_USER_ID';

db.collection('conversations').doc(conversationId).update({
  [`userLeftAt.${userId}`]: admin.firestore.FieldValue.delete()
});
```

## 추가 진단이 필요한 경우

로그를 전체 복사하여 다음 정보와 함께 제공:
1. '남태평양' 계정의 Firebase UID
2. 문제가 있는 대화방의 conversationId
3. getMessages 호출 시 전체 로그
4. Firebase Console에서 확인한 대화방 데이터 스크린샷

## 예방 조치

향후 동일한 문제를 방지하기 위해:
1. `userLeftAt` 필드 업데이트 시 타임스탬프 검증
2. 대화방 나가기 기능 테스트 강화
3. 서버 시간 동기화 확인







