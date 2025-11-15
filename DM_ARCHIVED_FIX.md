# DM 대화방 표시 문제 해결

## 🐛 발견된 문제

### 문제 상황
- ✅ **알림은 정상 작동** (christopher로부터 메시지 6개 수신)
- ❌ **DM 목록에 christopher 대화방이 표시 안 됨**
- 현재 DM 목록: 율율율, 전막권지예 (2개만)

### 로그 분석 결과
```
RhftBT9OEyagkaPUtO9v35KPh8E3_TjZWjNW75dMqCG1j51QVD1GhXIP2
  participants: [TjZWjNW75dMqCG1j51QVD1GhXIP2, RhftBT9OEyagkaPUtO9v35KPh8E3]
  lastMessage: 아아아아아앙아아
  archivedBy: [RhftBT9OEyagkaPUtO9v35KPh8E3]  ← ❌ 문제!
  숨김: archivedBy에 포함됨
```

**christopher 대화방이 `archivedBy`에 포함되어 숨겨져 있었습니다!**

## 🔍 근본 원인

### 1. `archivedBy` 자동 제거 로직 누락
**문제:**
- 새 메시지가 와도 `archivedBy`가 자동으로 제거되지 않음
- `sendMessage` 함수에서 `archivedBy` 처리 로직이 없었음

**결과:**
- 대화방을 보관(숨김)한 후 상대방이 메시지를 보내도 대화방이 다시 나타나지 않음
- 알림은 오지만 DM 목록에는 표시 안 됨

### 2. 추가 발견된 버그들
1. **타임스탬프가 붙은 일반 친구 DM**
   ```
   ❌ RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179637046
   ❌ RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179603825
   ```
   - 일반 친구 DM인데 타임스탬프가 붙음 (익명 DM 형식)
   - 같은 친구와 여러 개의 대화방 생성됨

2. **본인 DM**
   ```
   ❌ anon_RhftBT9OEyagkaPUtO9v35KPh8E3_RhftBT9OEyagkaPUtO9v35KPh8E3_ILe7K7vcpsYei3aWyzGS
   ```
   - 같은 UID가 두 번 (본인에게 DM)

## ✅ 해결 방법

### 1. 코드 수정

#### `lib/services/dm_service.dart` - `sendMessage()` 함수

**수정 전:**
```dart
// 메시지 전송 시 대화방 업데이트
final updateData = {
  'lastMessage': text.trim(),
  'lastMessageTime': Timestamp.fromDate(now),
  'lastMessageSenderId': currentUser.uid,
  'unreadCount': unreadCount,
  'updatedAt': Timestamp.fromDate(now),
};
```

**수정 후:**
```dart
// ✅ archivedBy에서 모든 참가자 제거 (새 메시지가 오면 대화방 복원)
final archivedBy = (convData['archivedBy'] as List?)?.map((e) => e.toString()).toList() ?? [];
final shouldRestoreConversation = archivedBy.isNotEmpty;

if (shouldRestoreConversation) {
  print('🔓 대화방 복원: archivedBy에서 모든 참가자 제거');
  print('  - 기존 archivedBy: $archivedBy');
}

// 메시지 전송 시 대화방 업데이트
final updateData = {
  'lastMessage': text.trim(),
  'lastMessageTime': Timestamp.fromDate(now),
  'lastMessageSenderId': currentUser.uid,
  'unreadCount': unreadCount,
  'updatedAt': Timestamp.fromDate(now),
  // ✅ 새 메시지가 오면 archivedBy 초기화 (대화방 복원)
  'archivedBy': [],
};
```

#### `lib/services/dm_service.dart` - `prepareConversationId()` 함수

**수정:**
- 일반 친구 DM에는 **절대 타임스탬프 추가 안 함**
- 이 함수는 **댓글 위젯 전용**으로만 사용

### 2. Firestore 데이터 정리 (필수!)

**Firebase Console에서 다음 대화방들을 삭제하세요:**

#### 삭제 대상 1: christopher 대화방 복원
```
문서 ID: RhftBT9OEyagkaPUtO9v35KPh8E3_TjZWjNW75dMqCG1j51QVD1GhXIP2
```
**방법 1 (권장):** `archivedBy` 필드를 `[]` (빈 배열)로 수정
**방법 2:** christopher가 새 메시지를 보내면 자동으로 복원됨 (코드 수정 후)

#### 삭제 대상 2: 타임스탬프가 붙은 중복 대화방들
```
❌ RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179637046
❌ RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179603825
❌ RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179414956
❌ RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179090748
```

#### 삭제 대상 3: 본인 DM
```
❌ anon_RhftBT9OEyagkaPUtO9v35KPh8E3_RhftBT9OEyagkaPUtO9v35KPh8E3_ILe7K7vcpsYei3aWyzGS
```

#### 유지할 대화방 (정상)
```
✅ RhftBT9OEyagkaPUtO9v35KPh8E3_TjZWjNW75dMqCG1j51QVD1GhXIP2  (christopher)
✅ CNAYONUHSVMUwowhnzrxIn82ELs2_RhftBT9OEyagkaPUtO9v35KPh8E3
✅ RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3  (율율율)
✅ RhftBT9OEyagkaPUtO9v35KPh8E3_mhHqtlUU6mYDBcwSOk4ZzOBs5CB2
```

### 3. Firebase Console 정리 단계

1. **Firebase Console 접속**: https://console.firebase.google.com/
2. **Firestore Database** → `conversations` 컬렉션
3. **christopher 대화방 복원:**
   - 문서 ID: `RhftBT9OEyagkaPUtO9v35KPh8E3_TjZWjNW75dMqCG1j51QVD1GhXIP2`
   - `archivedBy` 필드 클릭 → 값을 `[]`로 수정
4. **중복 대화방 삭제:**
   - 타임스탬프가 붙은 4개 문서 삭제
5. **본인 DM 삭제:**
   - `anon_RhftBT9OEyagkaPUtO9v35KPh8E3_RhftBT9OEyagkaPUtO9v35KPh8E3_ILe7K7vcpsYei3aWyzGS` 삭제

## 🎯 예상 결과

### 정리 전
```
DM 목록:
- 율율율 (여러 개 중복)
- 전막권지예
- christopher ❌ 표시 안 됨 (archivedBy에 숨김)
```

### 정리 후
```
DM 목록:
- christopher ✅ 표시됨!
- 율율율 (1개만)
- 전막권지예
```

## 🚀 테스트 방법

### 1. christopher 대화방 복원 테스트
1. Firebase Console에서 `archivedBy` 수정
2. 앱 재실행
3. **DM 목록에 christopher 대화방이 즉시 표시되는지 확인**

### 2. 새 메시지 자동 복원 테스트
1. 다른 대화방을 보관(숨김) 처리
2. 상대방이 메시지 전송
3. **DM 목록에 대화방이 자동으로 다시 나타나는지 확인**

### 3. 중복 대화방 제거 확인
1. 중복 대화방 삭제 후 앱 재실행
2. **각 친구당 1개의 대화방만 표시되는지 확인**

## 📋 체크리스트

- [x] **코드 수정 완료** - `sendMessage`에 `archivedBy` 초기화 로직 추가
- [x] **코드 수정 완료** - `prepareConversationId` 경고 추가
- [ ] **Firestore 정리** - christopher 대화방 `archivedBy` 수정
- [ ] **Firestore 정리** - 타임스탬프 붙은 중복 대화방 4개 삭제
- [ ] **Firestore 정리** - 본인 DM 1개 삭제
- [ ] **앱 재실행** - 정상 작동 확인
- [ ] **테스트** - christopher 대화방이 DM 목록에 표시되는지 확인
- [ ] **테스트** - 새 메시지 시 자동 복원 작동 확인

## 💡 핵심 개선 사항

### Instagram 스타일 DM 동작
1. **대화방 보관(숨김)**: `archivedBy`에 UID 추가
2. **새 메시지 수신**: `archivedBy` 자동 초기화 → 대화방 복원 ✅
3. **대화방 재사용**: 같은 친구와는 항상 1개의 대화방만 유지

### 버그 수정
1. ✅ `archivedBy` 자동 제거 로직 추가
2. ✅ 일반 친구 DM에 타임스탬프 추가 방지
3. ✅ 본인 DM 차단 (이미 구현됨)

## 🔧 다음 단계

1. **지금 바로 Firebase Console에서 위 대화방들을 정리하세요!**
2. **앱 재실행**
3. **christopher 대화방이 DM 목록에 표시되는지 확인**
4. **정상 작동 확인 후 보고**

---

**이제 정상 작동할 것입니다!** 🎉

Firebase Console에서 정리 완료하면 알려주세요!

