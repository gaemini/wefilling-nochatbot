# 🔍 채팅방 나가기 기능 진단 리포트

## 📋 현재 구현 분석

### 1. **나가기 동작 (`leaveConversation`)**
```dart
// lib/services/dm_service.dart:1272
await convRef.update({
  'userLeftAt.${currentUser.uid}': Timestamp.fromDate(now),
  'updatedAt': Timestamp.fromDate(now),
});
```
✅ **정상 동작**: Firestore에 나간 시간 기록

---

### 2. **목록 필터링 (`getMyConversations`)**
```dart
// lib/services/dm_service.dart:720-740
if (userLeftTime == null) {
  show = true;  // 나간 적 없음
}
else if (lastMessageTime.compareTo(userLeftTime) > 0) {
  show = true;  // 나간 후 새 메시지
}
else {
  show = false; // 나갔고 새 메시지 없음
}
```

⚠️ **문제 발견!**

---

## 🐛 핵심 문제

### **시나리오 분석**

#### 상황 1: 마지막 메시지가 있는 채팅방에서 나가기
```
1. 사용자 A가 "안녕" 메시지 전송
   → lastMessageTime = 2026-02-02 14:00:00

2. 사용자 B가 채팅방 나가기 클릭
   → userLeftAt[B] = 2026-02-02 14:01:00
   
3. 필터링 체크:
   lastMessageTime (14:00:00) vs userLeftAt (14:01:00)
   → 14:00:00 < 14:01:00
   → show = false ✅ 정상 숨김
```

#### 상황 2: 나가는 순간과 마지막 메시지 시간이 거의 동시
```
1. 사용자 A가 "안녕" 메시지 전송
   → lastMessageTime = 2026-02-02 14:00:00.500

2. 사용자 B가 즉시 나가기 클릭
   → userLeftAt[B] = 2026-02-02 14:00:00.300
   
3. 필터링 체크:
   lastMessageTime (14:00:00.500) vs userLeftAt (14:00:00.300)
   → 14:00:00.500 > 14:00:00.300
   → show = true ❌ 잘못 표시됨!
```

#### 상황 3: 이전 코드 (`>= 비교`)
```dart
// 이전: >= 비교 사용
else if (lastMessageTime.compareTo(userLeftTime) >= 0) {
  show = true;
}

// 문제:
lastMessageTime == userLeftAt일 때도 표시됨
→ 나가는 시점의 메시지가 있으면 항상 표시
```

---

## 📊 진단 결과

### **현재 코드 상태**
- ✅ `>` 비교로 변경됨 (상황 3 해결)
- ⚠️ 하지만 타이밍 이슈 여전히 존재 (상황 2)

### **근본 원인**
1. **비동기 타이밍**: 메시지 전송과 나가기 동작의 타이밍 차이
2. **Firestore 업데이트 순서**: `lastMessageTime` 업데이트가 `userLeftAt`보다 나중에 반영될 수 있음
3. **클라이언트 시간 차이**: 서버 시간과 클라이언트 시간 불일치

---

## 🔧 해결 방안

### **방안 1: archivedBy 사용 (권장)**
가장 확실한 방법은 `archivedBy` 필드를 사용하는 것입니다.

```dart
// 나가기 시
await convRef.update({
  'archivedBy': FieldValue.arrayUnion([currentUser.uid]),
  'userLeftAt.${currentUser.uid}': Timestamp.fromDate(now),
  'updatedAt': Timestamp.fromDate(now),
});

// 필터링
final notArchived = !(conv.archivedBy.contains(currentUser.uid));
```

**장점:**
- ✅ 타이밍 이슈 없음
- ✅ 명확한 의도 표현
- ✅ 이미 코드에 구현되어 있음

**단점:**
- ❌ 나간 후 새 메시지가 와도 복원 안 됨 (인스타그램 방식 불가)

---

### **방안 2: lastMessageSenderId 추가 체크**
마지막 메시지를 보낸 사람이 자기 자신이 아닐 때만 표시

```dart
else if (lastMessageTime.compareTo(userLeftTime) > 0 && 
         conv.lastMessageSenderId != currentUser.uid) {
  show = true;
}
```

**장점:**
- ✅ 타이밍 이슈 일부 해결
- ✅ 인스타그램 방식 유지

**단점:**
- ⚠️ 완벽한 해결책은 아님

---

### **방안 3: 안전 마진 추가**
나간 시간에 1초 마진을 추가하여 타이밍 이슈 방지

```dart
else if (lastMessageTime.compareTo(userLeftTime.add(Duration(seconds: 1))) > 0) {
  show = true;
}
```

**장점:**
- ✅ 타이밍 이슈 대부분 해결
- ✅ 인스타그램 방식 유지

**단점:**
- ⚠️ 나가고 1초 이내 메시지가 오면 표시 안 됨

---

## 🎯 권장 솔루션

### **하이브리드 방식: archivedBy + userLeftAt**

```dart
// 나가기 시
await convRef.update({
  'archivedBy': FieldValue.arrayUnion([currentUser.uid]),
  'userLeftAt.${currentUser.uid}': Timestamp.fromDate(now),
  'updatedAt': Timestamp.fromDate(now),
});

// 필터링
if (conv.archivedBy.contains(currentUser.uid)) {
  // 보관된 대화방
  show = false;
} else if (userLeftTime == null) {
  show = true;
} else if (lastMessageTime.compareTo(userLeftTime) > 0) {
  show = true;
} else {
  show = false;
}

// 새 메시지 도착 시 자동 복원 (Cloud Function 또는 클라이언트)
if (새_메시지_도착 && archivedBy.contains(userId)) {
  archivedBy.remove(userId);
}
```

**장점:**
- ✅ 완전히 확실한 제거
- ✅ 타이밍 이슈 없음
- ✅ 선택적으로 인스타그램 방식 구현 가능

---

## 📝 진단 로그 추가

다음 로그를 확인하여 정확한 문제 파악:

```dart
Logger.log('🚪 leaveConversation 시작');
Logger.log('  - lastMessageTime: $lastMessageTime');
Logger.log('  - userLeftTime: $now');
Logger.log('  - 차이: ${now.difference(lastMessageTime).inMilliseconds}ms');
```

실제 앱에서 나가기를 시도하고 콘솔 로그를 확인해주세요.

---

## 🧪 테스트 체크리스트

- [ ] 메시지 없는 채팅방에서 나가기
- [ ] 마지막 메시지 후 시간이 지난 채팅방에서 나가기
- [ ] 메시지를 받자마자 즉시 나가기 (타이밍 테스트)
- [ ] 나간 후 새 메시지가 올 때 동작
- [ ] 익명 대화방에서 나가기
- [ ] 친구 대화방에서 나가기

---

## 🔍 다음 단계

1. 실제 앱에서 나가기 시도
2. 로그 확인 (`userLeftTime`과 `lastMessageTime` 비교)
3. 어느 방안을 선택할지 결정
4. 구현 및 테스트
