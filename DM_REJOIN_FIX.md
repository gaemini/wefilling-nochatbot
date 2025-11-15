# DM 재입장 문제 해결

## 🔍 문제 상황

**증상:**
- 대화방을 나갔다가 다시 들어오면 **매번 새롭게 메시지가 보임**
- 대화방 나가기 후 재입장 상태가 유지되지 않음
- 대화방을 열 때마다 `rejoinedAt`이 업데이트됨

**예상 동작:**
1. 대화방 나가기 → `userLeftAt` 기록
2. 대화방 다시 열기 → `rejoinedAt` 기록 (1회만)
3. 이후 대화방 열기 → 재입장 처리 스킵 (이미 재입장 상태)
4. 다시 나가기 → `userLeftAt` 업데이트
5. 다시 열기 → `rejoinedAt` 업데이트 (1회만)

**실제 동작:**
1. 대화방 나가기 → `userLeftAt` 기록
2. 대화방 다시 열기 → `rejoinedAt` 기록 ✅
3. **이후 대화방 열기 → `rejoinedAt` 또 업데이트** ❌
4. **메시지 가시성이 매번 초기화됨** ❌

## 🐛 근본 원인

### 문제 코드 (수정 전)

```dart
// dm_chat_screen.dart - _initConversationState()
final userLeftAt = (data['userLeftAt'] as Map<String, dynamic>? ?? {});
if (_currentUser != null && userLeftAt[_currentUser!.uid] != null) {
  print('🔁 이전에 나간 대화방 재입장 처리 실행');
  await _dmService.rejoinConversation(widget.conversationId);  // ❌ 매번 실행!
}
```

**문제점:**
1. `userLeftAt`에 값이 있으면 **무조건 재입장 처리**
2. `rejoinedAt`을 확인하지 않음
3. **마지막 액션이 "재입장"인데도 또 재입장 처리**
4. 결과: `rejoinedAt`이 매번 업데이트되어 메시지 가시성이 초기화됨

### 시나리오 예시

**사용자 A의 타임라인:**

```
1. 2025-11-15 10:00 - 대화방 나가기
   userLeftAt: 10:00
   rejoinedAt: null
   → 대화방 목록에서 사라짐

2. 2025-11-15 11:00 - 대화방 다시 열기
   userLeftAt: 10:00
   rejoinedAt: 11:00  ✅ (재입장 처리)
   → 11:00 이후 메시지만 표시

3. 2025-11-15 12:00 - 대화방 다시 열기 (같은 날)
   ❌ 문제: 또 재입장 처리 실행!
   userLeftAt: 10:00
   rejoinedAt: 12:00  ❌ (불필요한 업데이트)
   → 12:00 이후 메시지만 표시 (11:00~12:00 메시지 사라짐!)

4. 2025-11-15 13:00 - 대화방 다시 열기
   ❌ 문제: 또 재입장 처리 실행!
   userLeftAt: 10:00
   rejoinedAt: 13:00  ❌ (불필요한 업데이트)
   → 13:00 이후 메시지만 표시 (12:00~13:00 메시지 사라짐!)
```

**결과:**
- 대화방을 열 때마다 이전 메시지가 사라짐
- 사용자는 "대화방이 계속 초기화되는 것처럼" 느낌

## ✅ 해결 방법

### 수정된 코드

```dart
// dm_chat_screen.dart - _initConversationState()
// 🔁 마지막 액션이 "나가기"인 경우에만 재입장 처리
final userLeftAt = (data['userLeftAt'] as Map<String, dynamic>? ?? {});
final rejoinedAt = (data['rejoinedAt'] as Map<String, dynamic>? ?? {});

if (_currentUser != null && userLeftAt[_currentUser!.uid] != null) {
  final leftTimestamp = userLeftAt[_currentUser!.uid] as Timestamp?;
  final rejoinTimestamp = rejoinedAt[_currentUser!.uid] as Timestamp?;
  
  if (leftTimestamp != null) {
    final leftTime = leftTimestamp.toDate();
    final rejoinTime = rejoinTimestamp?.toDate();
    
    // ✅ 마지막 액션이 "나가기"인 경우에만 재입장 처리
    if (rejoinTime == null || leftTime.isAfter(rejoinTime)) {
      print('🔁 마지막 액션이 "나가기" → 재입장 처리 실행');
      await _dmService.rejoinConversation(widget.conversationId);
    } else {
      print('✅ 이미 재입장 상태 → 재입장 처리 스킵');
    }
  }
}
```

### 개선 사항

1. **`rejoinedAt` 확인 추가**
   - `userLeftAt`과 `rejoinedAt`을 모두 확인
   - 마지막 액션 판단

2. **조건부 재입장 처리**
   ```dart
   if (rejoinTime == null || leftTime.isAfter(rejoinTime)) {
     // 재입장 처리
   }
   ```
   - `rejoinTime == null`: 한 번도 재입장하지 않음 → 재입장 처리
   - `leftTime.isAfter(rejoinTime)`: 마지막 액션이 "나가기" → 재입장 처리
   - 그 외: 이미 재입장 상태 → 스킵

3. **로그 개선**
   - 재입장 처리 실행: `🔁 마지막 액션이 "나가기" → 재입장 처리 실행`
   - 재입장 처리 스킵: `✅ 이미 재입장 상태 → 재입장 처리 스킵`

## 📊 수정 후 동작

**사용자 A의 타임라인 (수정 후):**

```
1. 2025-11-15 10:00 - 대화방 나가기
   userLeftAt: 10:00
   rejoinedAt: null
   → 대화방 목록에서 사라짐

2. 2025-11-15 11:00 - 대화방 다시 열기
   조건: rejoinTime == null
   → 재입장 처리 실행 ✅
   userLeftAt: 10:00
   rejoinedAt: 11:00
   → 11:00 이후 메시지만 표시

3. 2025-11-15 12:00 - 대화방 다시 열기
   조건: leftTime (10:00) < rejoinTime (11:00)
   → 재입장 처리 스킵 ✅
   userLeftAt: 10:00
   rejoinedAt: 11:00 (유지)
   → 11:00 이후 메시지 계속 표시

4. 2025-11-15 13:00 - 대화방 다시 열기
   조건: leftTime (10:00) < rejoinTime (11:00)
   → 재입장 처리 스킵 ✅
   userLeftAt: 10:00
   rejoinedAt: 11:00 (유지)
   → 11:00 이후 메시지 계속 표시

5. 2025-11-15 14:00 - 대화방 나가기 (다시)
   userLeftAt: 14:00
   rejoinedAt: 11:00
   → 대화방 목록에서 사라짐

6. 2025-11-15 15:00 - 대화방 다시 열기
   조건: leftTime (14:00) > rejoinTime (11:00)
   → 재입장 처리 실행 ✅
   userLeftAt: 14:00
   rejoinedAt: 15:00
   → 15:00 이후 메시지만 표시
```

**결과:**
- ✅ 대화방을 열 때마다 재입장 처리가 실행되지 않음
- ✅ 메시지 가시성이 유지됨
- ✅ 나가기 → 재입장 → 유지 → 나가기 → 재입장 사이클이 정상 작동

## 🎯 테스트 시나리오

### 시나리오 1: 나가기 → 재입장 (첫 번째)
1. 대화방 나가기
2. 대화방 다시 열기
3. **예상**: 재입장 처리 실행, `rejoinedAt` 업데이트
4. **확인**: 로그에 `🔁 마지막 액션이 "나가기" → 재입장 처리 실행` 출력

### 시나리오 2: 재입장 후 계속 유지
1. 대화방 나가기 → 재입장 (시나리오 1)
2. 대화방 닫기
3. 대화방 다시 열기
4. **예상**: 재입장 처리 스킵, `rejoinedAt` 유지
5. **확인**: 로그에 `✅ 이미 재입장 상태 → 재입장 처리 스킵` 출력

### 시나리오 3: 재입장 → 나가기 → 재입장
1. 대화방 나가기 → 재입장 (시나리오 1)
2. 대화방 다시 나가기
3. 대화방 다시 열기
4. **예상**: 재입장 처리 실행, `rejoinedAt` 업데이트
5. **확인**: 로그에 `🔁 마지막 액션이 "나가기" → 재입장 처리 실행` 출력

### 시나리오 4: 메시지 가시성 유지
1. 대화방 나가기 (10:00)
2. 상대방이 메시지 전송 (10:30)
3. 대화방 다시 열기 (11:00) → 재입장 처리
4. 10:30 메시지 확인 ✅
5. 대화방 닫기
6. 대화방 다시 열기 (12:00) → 재입장 처리 스킵
7. **예상**: 10:30 메시지 여전히 보임 ✅
8. **확인**: 메시지가 사라지지 않음

## 📝 수정된 파일

- **`/lib/screens/dm_chat_screen.dart`**
  - `_initConversationState()` 메서드 수정
  - `rejoinedAt` 확인 로직 추가
  - 조건부 재입장 처리 구현

## ✅ 요약

**문제:**
- 대화방을 열 때마다 재입장 처리가 실행되어 메시지 가시성이 초기화됨

**원인:**
- `userLeftAt`만 확인하고 `rejoinedAt`을 확인하지 않음

**해결:**
- `rejoinedAt`과 `userLeftAt`을 비교하여 마지막 액션이 "나가기"일 때만 재입장 처리

**결과:**
- ✅ 대화방 나가기 → 재입장 → 유지 사이클이 정상 작동
- ✅ 메시지 가시성이 유지됨
- ✅ 불필요한 재입장 처리가 실행되지 않음

