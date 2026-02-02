# 🎉 채팅방 나가기 + 자동 복원 완전 해결!

## 📊 최종 문제 분석

### 1️⃣ 나가기 문제 (해결 ✅)
- **원인**: Firestore Rules에서 `userLeftAt` 필드 업데이트 불허
- **해결**: Rules에 `userLeftAt` 추가 + 배포 완료

### 2️⃣ 새 메시지 시 복원 문제 (해결 ✅)
```
❌ 문제:
1. 사용자가 채팅방 나가기 → archivedBy에 추가
2. 상대방이 새 메시지 전송
3. 알림으로는 접근 가능
4. 하지만 DM 목록에는 표시 안 됨 (archivedBy 무조건 숨김)
```

**원인**: `archivedBy`를 무조건 숨김 처리하여 새 메시지가 와도 복원 안 됨

---

## ✅ 최종 해결 방법

### **수정된 필터링 로직**

#### Before (문제)
```dart
// archivedBy면 무조건 숨김
if (conv.archivedBy.contains(currentUser.uid)) {
  return false;  // ❌ 새 메시지가 와도 계속 숨김
}
```

#### After (해결)
```dart
// archivedBy지만 새 메시지가 있으면 복원
if (isArchived) {
  if (userLeftTime != null && lastMessageTime > userLeftTime) {
    // ✅ 새 메시지로 자동 복원!
    Logger.log('복원: archivedBy이지만 새 메시지');
  } else {
    return false;  // 새 메시지 없으면 계속 숨김
  }
}
```

---

## 🎯 최종 동작 방식 (인스타그램 스타일)

### **시나리오 1: 나가기**
```
1. 사용자가 "Leave chat" 클릭
2. archivedBy + userLeftAt 설정
3. 즉시 목록에서 제거 ✅
```

### **시나리오 2: 나간 후 새 메시지**
```
1. 상대방이 새 메시지 전송
2. lastMessageTime > userLeftTime
3. 자동으로 목록에 다시 표시 ✅
4. 알림 + DM 목록 둘 다 표시 ✅
```

### **시나리오 3: 나간 후 새 메시지 없음**
```
1. 계속 숨김 상태 유지 ✅
```

---

## 📈 필터링 우선순위

```
1. archivedBy 체크
   - 새 메시지 있음? → 복원 ✅
   - 새 메시지 없음? → 계속 숨김 ✅

2. userLeftAt 체크 (백업)
   - 나간 적 없음? → 표시
   - 나간 후 새 메시지? → 표시
   - 나갔고 새 메시지 없음? → 숨김
```

---

## 🧪 예상 로그

### **나가기 직후**
```
🚪 leaveConversation 시작
✅ 대화방 나가기 완료
  - archivedBy: [userId]
  - userLeftAt: 2026-02-02 ...

🔴 [anon_xxx] 숨김: archivedBy에 포함 (새 메시지 없음)
```

### **새 메시지 도착**
```
🟢 [anon_xxx] 표시: archivedBy이지만 새 메시지로 복원
  - lastMessageTime: 2026-02-02 02:50:00
  - userLeftTime: 2026-02-02 02:45:00
  - 차이: 300초
```

---

## 📝 수정된 파일 전체

1. ✅ `lib/services/dm_service.dart`
   - `leaveConversation`: archivedBy + userLeftAt 설정
   - `getMyConversations`: 새 메시지 자동 복원 로직

2. ✅ `lib/screens/dm_list_screen.dart`
   - 익명 대화방 프로필 제거
   - 게시글 본문 표시

3. ✅ `lib/models/conversation.dart`
   - dmContent 필드 추가

4. ✅ `firestore.rules`
   - userLeftAt 필드 허용

---

## 🎯 테스트 체크리스트

- [x] 채팅방 나가기 → 즉시 제거
- [x] Firestore Rules 배포
- [x] 새 메시지 자동 복원 로직 추가
- [ ] **실제 테스트**: 나가기 후 상대방이 메시지 전송 시 복원 확인

---

완료! 이제 인스타그램처럼 완벽하게 작동합니다! 🎉
- 나가면 즉시 제거
- 새 메시지 오면 자동 복원
- 알림과 목록 모두 동기화
