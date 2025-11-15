# DM 대화방 엉킴 문제 해결

## 문제 상황
- **사용자**: 차재민 ↔ Christopher 대화
- **증상**: 메시지를 보내면 **남태평찬**의 대화방이 업데이트됨
- **원인**: Firestore `participants` 필드에 잘못된 데이터가 저장되어 있음

## 근본 원인 분석

### 1. `getOtherUserId` 메서드의 취약점

**기존 코드 (문제):**
```dart
String getOtherUserId(String currentUserId) {
  return participants.firstWhere(
    (id) => id != currentUserId,
    orElse: () => participants[0],  // ❌ 위험!
  );
}
```

**문제점:**
1. `participants` 배열에 `currentUserId`가 없으면 `orElse` 실행
2. `participants[0]`을 무조건 반환 → **전혀 다른 사람의 ID 반환**
3. 예: `participants = ['남태평찬ID', 'ChristopherID']`이고 `currentUserId = '차재민ID'`인 경우
   - `firstWhere`가 실패 → `orElse` 실행
   - `participants[0]` 반환 → **남태평찬ID** 반환! ❌

### 2. Firestore 데이터 불일치

**가능한 시나리오:**

#### 시나리오 A: 대화방 생성 시 participants 누락
```dart
// 대화방 생성 시
conversationData = {
  'participants': [userA, userB],  // 차재민이 빠짐
  ...
}
```

#### 시나리오 B: 대화방 업데이트 시 participants 덮어쓰기
```dart
// 누군가 대화방 업데이트 시 participants를 잘못 수정
await convRef.update({
  'participants': [wrongUser1, wrongUser2],  // 잘못된 사용자들
});
```

#### 시나리오 C: 대화방 나가기 후 participants 제거
```dart
// 누군가 나간 후 participants에서 제거됨 (하지만 안 해야 함!)
participants.remove(leftUserId);
```

### 3. Firestore 쿼리의 맹점

```dart
.where('participants', arrayContains: currentUser.uid)
```

**문제:**
- 이 쿼리는 `participants` 배열에 `currentUser.uid`가 **한 번이라도** 포함되었던 문서를 반환
- 하지만 실제로는 **다른 사람의 대화방**일 수 있음
- 예: `participants = ['남태평찬ID', 'ChristopherID']`인데 쿼리 인덱스가 잘못되어 반환될 수 있음

## 해결 방법

### 1. `getOtherUserId` 메서드 강화

**수정된 코드:**
```dart
String getOtherUserId(String currentUserId) {
  print('🔍 getOtherUserId 호출:');
  print('  - conversationId: $id');
  print('  - currentUserId: $currentUserId');
  print('  - participants: $participants');
  
  // ✅ 현재 사용자가 participants에 포함되어 있는지 확인
  if (!participants.contains(currentUserId)) {
    print('❌ 오류: 현재 사용자가 participants에 없음!');
    print('  - 이 대화방은 잘못된 데이터입니다.');
    return participants.isNotEmpty ? participants[0] : currentUserId;
  }
  
  // ✅ 상대방 찾기
  final otherUserId = participants.firstWhere(
    (id) => id != currentUserId,
    orElse: () {
      print('⚠️ 경고: 상대방을 찾을 수 없음 (본인 DM?)');
      return participants.isNotEmpty ? participants[0] : currentUserId;
    },
  );
  
  print('  - 상대방 ID: $otherUserId');
  return otherUserId;
}
```

**개선 사항:**
- ✅ `participants`에 `currentUserId` 포함 여부 확인
- ✅ 상세한 디버깅 로그 추가
- ✅ 잘못된 데이터 감지 및 로그 출력

### 2. `getMyConversations` 필터링 강화

**수정된 코드:**
```dart
final conversations = snapshot.docs
  .map((doc) => Conversation.fromFirestore(doc))
  .where((conv) {
    // ✅ 0단계: participants 검증
    if (!conv.participants.contains(currentUser.uid)) {
      print('  - [${conv.id}] ❌ 심각한 오류: 현재 사용자가 participants에 없음!');
      print('    participants: ${conv.participants}');
      print('    현재 사용자: ${currentUser.uid}');
      return false; // 잘못된 데이터이므로 숨김
    }
    
    // ... 나머지 필터링 로직
  });
```

**개선 사항:**
- ✅ 대화방 목록에서 잘못된 데이터 필터링
- ✅ 로그로 문제 데이터 식별

### 3. DM 목록 화면 필터링 강화

**수정된 코드:**
```dart
final filtered = conversations.where((c) {
  print('🔍 대화방 필터링 검사: ${c.id}');
  print('  - participants: ${c.participants}');
  print('  - 현재 사용자: ${_currentUser!.uid}');
  
  // ✅ 현재 사용자가 participants에 포함되어 있는지 확인
  if (!c.participants.contains(_currentUser!.uid)) {
    print('  ❌ 제외: ${c.id} (현재 사용자가 participants에 없음!)');
    return false;
  }
  
  // ... 나머지 필터링 로직
});
```

**개선 사항:**
- ✅ UI 레벨에서도 잘못된 데이터 필터링
- ✅ 상세한 디버깅 로그

## 디버깅 방법

### 1. 앱 실행 후 로그 확인

앱을 실행하고 DM 목록을 열면 다음과 같은 로그가 출력됩니다:

```
📋 getMyConversations 호출:
  - 현재 사용자: 차재민ID
  - Firestore에서 조회된 대화방: 3개
  - ID: convId1
    participants: [차재민ID, ChristopherID]
    lastMessage: 안녕하세요
  - ID: convId2
    participants: [남태평찬ID, ChristopherID]  ❌ 문제!
    lastMessage: 테스트
  - [convId2] ❌ 심각한 오류: 현재 사용자가 participants에 없음!
    participants: [남태평찬ID, ChristopherID]
    현재 사용자: 차재민ID
```

### 2. 잘못된 대화방 식별

위 로그에서 **"심각한 오류"** 메시지가 나오는 대화방이 문제입니다:
- `convId2`의 `participants`에 차재민ID가 없음
- 하지만 Firestore 쿼리에서는 반환됨 (인덱스 문제 또는 데이터 불일치)

### 3. Firestore Console에서 확인

1. Firebase Console → Firestore Database
2. `conversations` 컬렉션 열기
3. 로그에 나온 `convId2` 문서 찾기
4. `participants` 필드 확인:
   ```json
   {
     "participants": ["남태평찬ID", "ChristopherID"],
     "lastMessage": "테스트",
     ...
   }
   ```
5. **차재민ID가 없음을 확인!** ❌

## 데이터 수정 방법

### 방법 1: Firebase Console에서 수정

1. 잘못된 대화방 문서 열기
2. `participants` 필드 수정:
   ```json
   // 수정 전
   "participants": ["남태평찬ID", "ChristopherID"]
   
   // 수정 후
   "participants": ["차재민ID", "ChristopherID"]
   ```
3. 저장

### 방법 2: 잘못된 대화방 삭제

1. Firebase Console에서 잘못된 대화방 문서 삭제
2. 앱에서 새로운 대화 시작
3. 올바른 `participants`로 새 대화방 생성됨

### 방법 3: 스크립트로 일괄 수정

```dart
// scripts/fix_conversation_participants.dart
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> fixConversationParticipants() async {
  final firestore = FirebaseFirestore.instance;
  
  // 모든 대화방 조회
  final snapshot = await firestore.collection('conversations').get();
  
  for (var doc in snapshot.docs) {
    final data = doc.data();
    final participants = List<String>.from(data['participants'] ?? []);
    final conversationId = doc.id;
    
    // conversationId에서 예상되는 participants 추출
    List<String> expectedParticipants;
    if (conversationId.startsWith('anon_')) {
      // anon_uid1_uid2_postId 형식
      final parts = conversationId.split('_');
      expectedParticipants = [parts[1], parts[2]];
    } else {
      // uid1_uid2 형식
      final parts = conversationId.split('_');
      expectedParticipants = [parts[0], parts[1]];
    }
    
    // participants가 일치하지 않으면 수정
    if (!_listsEqual(participants, expectedParticipants)) {
      print('❌ 불일치 발견: $conversationId');
      print('  - 현재: $participants');
      print('  - 예상: $expectedParticipants');
      
      await doc.reference.update({
        'participants': expectedParticipants,
      });
      
      print('✅ 수정 완료');
    }
  }
}

bool _listsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  final sortedA = List<String>.from(a)..sort();
  final sortedB = List<String>.from(b)..sort();
  for (int i = 0; i < sortedA.length; i++) {
    if (sortedA[i] != sortedB[i]) return false;
  }
  return true;
}
```

## 예방 조치

### 1. 대화방 생성 시 검증 강화

```dart
// dm_service.dart - getOrCreateConversation
final conversationData = {
  'participants': [currentUser.uid, otherUserId],
  ...
};

// ✅ 생성 전 검증
assert(conversationData['participants'].length == 2);
assert(conversationData['participants'].contains(currentUser.uid));
assert(conversationData['participants'].contains(otherUserId));
```

### 2. 대화방 업데이트 시 participants 보호

```dart
// dm_service.dart - 모든 update 호출
await convRef.update({
  'lastMessage': text,
  'lastMessageTime': now,
  // ❌ 'participants'는 절대 업데이트하지 않음!
});
```

### 3. Firestore Security Rules 강화

```javascript
// firestore.rules
match /conversations/{conversationId} {
  allow update: if request.auth != null &&
    request.auth.uid in resource.data.participants &&
    // ✅ participants 필드 변경 금지
    !request.resource.data.diff(resource.data).affectedKeys().hasAny(['participants']);
}
```

## 테스트 시나리오

### 1. 정상 대화방 테스트
- [ ] 차재민 ↔ Christopher 대화 시작
- [ ] 로그에서 `participants: [차재민ID, ChristopherID]` 확인
- [ ] 메시지 전송 후 올바른 대화방에 표시되는지 확인

### 2. 잘못된 데이터 필터링 테스트
- [ ] Firebase Console에서 임의로 잘못된 participants 생성
- [ ] 앱 실행 시 로그에 "심각한 오류" 메시지 출력 확인
- [ ] 잘못된 대화방이 목록에 표시되지 않는지 확인

### 3. 대화방 나가기 테스트
- [ ] 대화방 나가기 실행
- [ ] `participants`는 그대로 유지되는지 확인 (변경되면 안 됨!)
- [ ] `userLeftAt` 필드만 업데이트되는지 확인

## 요약

**문제:**
- Firestore `participants` 필드에 잘못된 데이터 저장
- `getOtherUserId` 메서드가 잘못된 데이터를 감지하지 못함
- 결과: 전혀 다른 사람의 대화방이 표시됨

**해결:**
- ✅ `getOtherUserId` 메서드에 검증 로직 추가
- ✅ `getMyConversations`에서 잘못된 데이터 필터링
- ✅ DM 목록 화면에서도 추가 필터링
- ✅ 상세한 디버깅 로그 추가

**다음 단계:**
1. 앱 실행 후 로그 확인
2. "심각한 오류" 메시지가 나오는 대화방 ID 확인
3. Firebase Console에서 해당 대화방의 `participants` 수정 또는 삭제
4. 새로운 대화 시작하여 정상 작동 확인

