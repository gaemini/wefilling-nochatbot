# DM 기능 수정 완료 요약

## 수정 날짜
2025-01-15

## 문제점
1. **친구 대화방이 생성되지 않는 문제**: 친구와 새로운 대화를 시작해도 DM 목록에 대화방이 표시되지 않음
2. **익명/친구 대화방 분리 문제**: 익명 채팅방과 친구 채팅방이 제대로 분리되지 않음
3. **대화방 나가기 후 동작 불명확**: 나간 사람과 안 나간 사람의 동작이 명확하지 않음

## 해결 방법

### 1. 대화방 생성 시 필수 필드 추가 (`dm_service.dart`)
```dart
final Map<String, dynamic> conversationData = {
  'participants': [currentUser.uid, otherUserId],
  'participantNames': {...},
  'participantPhotos': {...},
  'isAnonymous': {...},
  'lastMessage': '',
  'lastMessageTime': Timestamp.fromDate(now),
  'lastMessageSenderId': '',  // ✅ 추가
  'unreadCount': {...},
  'createdAt': Timestamp.fromDate(now),
  'updatedAt': Timestamp.fromDate(now),
  'archivedBy': [],
  'userLeftAt': {},  // ✅ 추가
  'rejoinedAt': {},  // ✅ 추가
};
```

**이유**: 
- `lastMessageSenderId`: 마지막 메시지 발신자 추적
- `userLeftAt`: 사용자가 대화방을 나간 시간 기록
- `rejoinedAt`: 사용자가 다시 들어온 시간 기록

### 2. 대화방 목록 필터링 로직 개선 (`dm_service.dart`)

**변경 전**: 복잡한 익명 대화방 필터링 로직
```dart
// ⭐ 추가: 익명 대화방에서 모든 상대방이 나간 경우만 숨김
if (show && conv.id.startsWith('anon_') && conv.userLeftAt.isNotEmpty) {
  // 복잡한 로직...
}
```

**변경 후**: 단순하고 명확한 필터링
```dart
// 🔧 1단계: archivedBy 체크 - 내가 보관한 대화방은 무조건 숨김
if (conv.archivedBy.contains(currentUser.uid)) {
  return false;
}

// 🔧 2단계: 나간/재입장 상태를 정확히 반영
// 1. 나간 적이 없으면 → 표시
// 2. 나갔지만 재입장하지 않은 상태 → 새 메시지가 오면 표시
// 3. 나간 후 재입장한 상태 → 마지막 액션에 따라 결정
```

**이유**: 
- `archivedBy` 체크를 먼저 수행하여 보관된 대화방을 확실히 숨김
- 익명 대화방 특별 처리 제거로 로직 단순화
- 나간/재입장 상태를 명확하게 판단

### 3. 익명/친구 대화방 분리 로직 개선 (`dm_list_screen.dart`)

**변경 전**: 게시글 DM 여부로 판단
```dart
final isPostDM = c.dmTitle != null && c.dmTitle!.isNotEmpty;
final passesType = _filter == DMFilter.friends 
    ? (!isAnon && !isPostDM)  // 친구 탭: 일반 친구 대화만
    : isAnon;  // 익명 탭: 모든 익명 대화
```

**변경 후**: conversationId와 isAnonymous 필드로 판단
```dart
// 익명 여부 확인: conversationId가 'anon_'으로 시작하거나 isAnonymous 필드 확인
final isAnonById = c.id.startsWith('anon_');
final isAnonByField = c.isOtherUserAnonymous(_currentUser!.uid);
final isAnon = isAnonById || isAnonByField;

// 친구 탭: 익명이 아닌 대화만 표시
// 익명 탭: 익명 대화만 표시
final passesType = _filter == DMFilter.friends 
    ? !isAnon  // 친구 탭: 익명이 아닌 대화
    : isAnon;  // 익명 탭: 익명 대화
```

**이유**:
- conversationId 형식(`anon_`으로 시작)으로 익명 여부를 1차 판단
- `isAnonymous` 필드로 2차 확인하여 정확성 향상
- 게시글 DM도 익명 대화방으로 올바르게 분류

### 4. 친구 대화 시작 시 플래그 추가 (`dm_list_screen.dart`)

**변경 전**:
```dart
final conversationId = await _dmService.getOrCreateConversation(
  friend.uid,
  isOtherUserAnonymous: false,
);
```

**변경 후**:
```dart
final conversationId = await _dmService.getOrCreateConversation(
  friend.uid,
  isOtherUserAnonymous: false,  // 친구는 익명이 아님
  isFriend: true,  // 친구 프로필에서 시작한 대화임을 명시
);
```

**이유**: 친구 프로필에서 시작한 대화임을 명시하여 대화방 생성 시 올바른 처리

### 5. 대화방 나가기 주석 개선 (`dm_service.dart`)

```dart
/// 대화방 나가기 - 인스타그램 DM 방식 (타임스탬프 기록)
/// - 나간 사람: 이전 대화 내용 안 보임, 대화방도 목록에서 사라짐
/// - 안 나간 사람: 모든 대화 내용 계속 유지, 대화방도 유지
/// - 나간 후 새 메시지 오면: 나간 사람에게 대화방 다시 생김 (이전 대화는 여전히 안 보임)
```

**이유**: 대화방 나가기 동작을 명확하게 문서화

## 동작 방식

### 친구 대화방 생성 흐름
1. 친구 목록에서 친구 선택 → `+ 버튼` 클릭
2. `getOrCreateConversation()` 호출 (isFriend: true, isOtherUserAnonymous: false)
3. conversationId 생성: `uid1_uid2` 형식 (사전순 정렬)
4. Firestore에 대화방 문서 생성 (필수 필드 모두 포함)
5. DM 목록에 즉시 표시 (친구 탭)

### 익명 대화방 생성 흐름
1. 익명 게시글에서 DM 버튼 클릭
2. `getOrCreateConversation()` 호출 (isOtherUserAnonymous: true, postId: 게시글ID)
3. conversationId 생성: `anon_uid1_uid2_postId` 형식
4. Firestore에 대화방 문서 생성 (isAnonymous: true)
5. DM 목록에 즉시 표시 (익명 탭)

### 대화방 나가기 흐름
1. 대화방에서 "나가기" 선택
2. `leaveConversation()` 호출
3. `userLeftAt.{userId}` 필드에 현재 시간 기록
4. 대화방 목록에서 즉시 사라짐 (나간 사람만)
5. 안 나간 사람은 모든 대화 내용 유지

### 대화방 재입장 흐름
1. 나간 후 새 메시지 수신
2. DM 목록에 대화방 다시 표시
3. 대화방 클릭 → `rejoinConversation()` 자동 호출
4. `rejoinedAt.{userId}` 필드에 현재 시간 기록
5. 재입장 시점 이후 메시지만 표시

## 테스트 시나리오

### 1. 친구 대화방 생성 테스트
- [ ] 친구 목록에서 친구 선택 후 대화 시작
- [ ] DM 목록 친구 탭에 대화방이 즉시 표시되는지 확인
- [ ] 메시지 전송 후 대화방이 유지되는지 확인

### 2. 익명 대화방 생성 테스트
- [ ] 익명 게시글에서 DM 버튼 클릭
- [ ] DM 목록 익명 탭에 대화방이 즉시 표시되는지 확인
- [ ] 메시지 전송 후 대화방이 유지되는지 확인

### 3. 대화방 나가기 테스트
- [ ] 대화방에서 "나가기" 선택
- [ ] 나간 사람의 DM 목록에서 대화방이 사라지는지 확인
- [ ] 안 나간 사람의 DM 목록에서 대화방이 유지되는지 확인
- [ ] 나간 사람은 이전 메시지를 볼 수 없는지 확인
- [ ] 안 나간 사람은 모든 메시지를 볼 수 있는지 확인

### 4. 대화방 재입장 테스트
- [ ] 나간 후 상대방이 새 메시지 전송
- [ ] 나간 사람의 DM 목록에 대화방이 다시 표시되는지 확인
- [ ] 대화방 클릭 시 재입장 시점 이후 메시지만 표시되는지 확인
- [ ] 이전 메시지는 표시되지 않는지 확인

### 5. 익명/친구 탭 분리 테스트
- [ ] 친구 대화방이 친구 탭에만 표시되는지 확인
- [ ] 익명 대화방이 익명 탭에만 표시되는지 확인
- [ ] 게시글 DM이 익명 탭에 표시되는지 확인

## 주의사항

1. **Firestore Security Rules**: conversations 컬렉션에 대한 읽기/쓰기 권한이 올바르게 설정되어 있어야 합니다.
2. **인덱스**: `participants` + `lastMessageTime` 복합 인덱스가 필요합니다.
3. **마이그레이션**: 기존 대화방에 `lastMessageSenderId`, `userLeftAt`, `rejoinedAt` 필드가 없을 수 있으므로, 코드에서 null 체크를 수행합니다.

## 수정된 파일
- `/lib/services/dm_service.dart`
- `/lib/screens/dm_list_screen.dart`

