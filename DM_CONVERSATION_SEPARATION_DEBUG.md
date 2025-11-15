# DM 대화방 구분 문제 진단

## 🔍 문제 상황

**사용자 보고:**
> "다른 아이디면 다른 대화방이 만들어져야 하는데 대화방이 안 만들어지고 있어!!!!"

**가능한 문제:**
1. 같은 conversationId가 여러 친구에게 사용됨
2. conversationId는 다르지만 UI에서 같은 대화방으로 보임
3. Firestore 데이터가 잘못 저장됨

## 🔬 진단 로그 추가

### 1. 친구 선택 시 로그

```dart
// dm_list_screen.dart - _startConversationWithFriend()
print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
print('🚀 친구와 대화 시작');
print('  - 친구 이름: ${friend.displayNameOrNickname}');
print('  - 친구 UID: ${friend.uid}');
print('  - 내 UID: ${_currentUser?.uid}');
print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

// ... getOrCreateConversation 호출 ...

print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
print('✅ 대화방 생성/조회 완료');
print('  - conversationId: $conversationId');
print('  - 예상 형식: ${_currentUser?.uid}_${friend.uid} (사전순 정렬)');
print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
```

### 2. 대화방 열기 시 로그

```dart
// dm_list_screen.dart - _openConversation()
print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
print('📂 대화방 열기');
print('  - conversationId: ${conversation.id}');
print('  - participants: ${conversation.participants}');
print('  - 내 UID: ${_currentUser!.uid}');
print('  - 상대방 UID: $otherUserId');
print('  - 상대방 이름: ${conversation.getOtherUserName(_currentUser!.uid)}');
print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
```

## 📊 테스트 시나리오

### 시나리오 1: 서로 다른 친구 2명과 대화

**테스트 순서:**
1. 친구 목록에서 **친구 A** 선택
2. 로그 확인:
   ```
   🚀 친구와 대화 시작
     - 친구 이름: 친구A
     - 친구 UID: uidA
     - 내 UID: myUid
   
   ✅ 대화방 생성/조회 완료
     - conversationId: myUid_uidA (또는 uidA_myUid)
   ```
3. 대화방 나가기
4. 친구 목록에서 **친구 B** 선택
5. 로그 확인:
   ```
   🚀 친구와 대화 시작
     - 친구 이름: 친구B
     - 친구 UID: uidB
     - 내 UID: myUid
   
   ✅ 대화방 생성/조회 완료
     - conversationId: myUid_uidB (또는 uidB_myUid)
   ```

**예상 결과:**
- ✅ conversationId가 **완전히 다름**
- ✅ 친구 A와 친구 B의 대화방이 **분리됨**

**만약 conversationId가 같다면:**
- ❌ **심각한 버그!** conversationId 생성 로직 문제

### 시나리오 2: DM 목록에서 대화방 확인

**테스트 순서:**
1. DM 목록 열기
2. 각 대화방 카드 클릭 시 로그 확인:
   ```
   📂 대화방 열기
     - conversationId: xxx
     - participants: [myUid, friendUid]
     - 내 UID: myUid
     - 상대방 UID: friendUid
     - 상대방 이름: 친구이름
   ```

**예상 결과:**
- ✅ 각 대화방의 conversationId가 **다름**
- ✅ 각 대화방의 상대방 UID가 **다름**
- ✅ 각 대화방의 상대방 이름이 **다름**

**만약 같다면:**
- ❌ **심각한 버그!** Firestore 쿼리 또는 데이터 문제

## 🐛 가능한 버그 원인

### 원인 1: conversationId 생성 로직 문제

**현재 로직:**
```dart
String _generateConversationId(String uid1, String uid2, {bool anonymous = false, String? postId}) {
  final sorted = [uid1, uid2]..sort();
  
  if (!anonymous) {
    return '${sorted[0]}_${sorted[1]}';  // 일반 DM
  }
  final suffix = (postId != null && postId.isNotEmpty) ? postId : DateTime.now().millisecondsSinceEpoch.toString();
  return 'anon_${sorted[0]}_${sorted[1]}_$suffix';  // 익명 DM
}
```

**검증:**
- ✅ uid1과 uid2를 사전순 정렬
- ✅ 일반 DM: `uidA_uidB` 형식
- ✅ 익명 DM: `anon_uidA_uidB_postId` 형식

**문제 가능성:**
- ❌ uid1 또는 uid2가 잘못 전달됨
- ❌ 항상 같은 uid가 전달됨

### 원인 2: Firestore 데이터 문제

**가능한 시나리오:**
1. **participants 필드가 잘못 저장됨**
   ```json
   {
     "conversationId": "uidA_uidB",
     "participants": ["uidA", "uidC"]  // ❌ uidB가 아니라 uidC!
   }
   ```

2. **같은 conversationId가 여러 친구에게 재사용됨**
   ```json
   {
     "conversationId": "myUid_friendA",
     "participants": ["myUid", "friendA"]
   }
   // 나중에 friendB와 대화 시작
   {
     "conversationId": "myUid_friendA",  // ❌ 같은 ID!
     "participants": ["myUid", "friendB"]  // participants만 업데이트됨
   }
   ```

### 원인 3: UI 표시 문제

**가능한 시나리오:**
- conversationId는 다르지만
- UI에서 `getOtherUserId()`가 잘못된 값을 반환
- 결과: 다른 사람의 이름/프로필이 표시됨

## 🔧 디버깅 방법

### 1단계: 로그 확인

앱을 실행하고 다음 작업 수행:

1. **친구 A 선택**
   - 로그에서 `🚀 친구와 대화 시작` 확인
   - `친구 UID`와 `conversationId` 기록

2. **친구 B 선택**
   - 로그에서 `🚀 친구와 대화 시작` 확인
   - `친구 UID`와 `conversationId` 기록

3. **비교**
   - conversationId가 다른가? ✅ 정상
   - conversationId가 같은가? ❌ **버그 발견!**

### 2단계: Firestore 데이터 확인

Firebase Console에서 확인:

1. **Firestore Database** → `conversations` 컬렉션
2. 로그에 나온 conversationId 문서 열기
3. **확인 사항:**
   - `participants` 필드가 올바른가?
   - `conversationId`와 `participants`가 일치하는가?

**예시:**
```json
// conversationId: "uidA_uidB"
{
  "participants": ["uidA", "uidB"],  // ✅ 일치
  "participantNames": {
    "uidA": "친구A",
    "uidB": "친구B"
  }
}
```

### 3단계: 문제 유형 판단

**케이스 1: conversationId가 다르지만 UI에서 같은 대화방으로 보임**
- 원인: `getOtherUserId()` 또는 `getOtherUserName()` 버그
- 해결: `conversation.dart` 모델 수정

**케이스 2: conversationId가 같음**
- 원인: `_generateConversationId()` 버그 또는 잘못된 uid 전달
- 해결: `dm_service.dart` 수정

**케이스 3: Firestore participants가 잘못됨**
- 원인: 대화방 생성 시 잘못된 데이터 저장
- 해결: `getOrCreateConversation()` 수정

## 📝 사용자에게 요청할 정보

다음 정보를 제공해주세요:

1. **친구 A와 대화 시작 로그:**
   ```
   🚀 친구와 대화 시작
     - 친구 이름: ?
     - 친구 UID: ?
     - 내 UID: ?
   
   ✅ 대화방 생성/조회 완료
     - conversationId: ?
   ```

2. **친구 B와 대화 시작 로그:**
   ```
   🚀 친구와 대화 시작
     - 친구 이름: ?
     - 친구 UID: ?
     - 내 UID: ?
   
   ✅ 대화방 생성/조회 완료
     - conversationId: ?
   ```

3. **DM 목록에서 대화방 클릭 로그:**
   ```
   📂 대화방 열기
     - conversationId: ?
     - participants: ?
     - 상대방 UID: ?
     - 상대방 이름: ?
   ```

4. **증상 설명:**
   - 어떤 친구들과 대화했나요?
   - 대화방이 구분되지 않는다는 것은 무엇을 의미하나요?
     - 같은 대화방에 여러 친구의 메시지가 섞여 있나요?
     - 친구 A와 대화했는데 친구 B의 이름이 표시되나요?
     - 다른 증상이 있나요?

## ✅ 다음 단계

1. **앱 실행**
2. **서로 다른 친구 2명 선택**
3. **로그 복사해서 제공**
4. **문제 유형 판단**
5. **정확한 수정 진행**

이제 로그를 확인해서 정확한 문제를 찾을 수 있습니다! 🔍

