# DM 푸시 알림 및 통합 배지 시스템

## 📋 개요

DM(Direct Message) 메시지도 잠금화면/알림센터에 푸시 알림이 표시되고, 앱 아이콘 배지는 **"일반 알림 수 + 안 읽은 DM 수"**를 통합하여 표시하는 완성도 있는 시스템입니다.

## 🎯 구현 완료 사항

### 1. **DM 푸시 알림 (서버 트리거)**
   - **위치**: `functions/src/index.ts`
   - **트리거**: `onDMMessageCreated`
   - **동작**: 
     - DM 메시지 생성 시 자동으로 FCM 푸시 발송
     - 발신자 이름, 메시지 프리뷰를 잠금화면에 표시
     - 익명 대화방의 경우 "익명"으로 표시
     - 이미지만 있는 경우 "📷 사진"으로 표시

### 2. **통합 배지 시스템**

#### 서버 측 (Cloud Functions)
   - **`onNotificationCreated`**: 일반 알림 푸시 시 배지 계산
   - **`onDMMessageCreated`**: DM 푸시 시 배지 계산
   - **계산 방식**:
     ```typescript
     badgeCount = (일반 알림 - dm_received 타입) + (모든 대화방의 unreadCount 합)
     ```

#### 클라이언트 측 (Flutter)
   - **위치**: `lib/services/badge_service.dart`
   - **메서드**: `BadgeService.syncNotificationBadge()`
   - **계산 방식**:
     ```dart
     totalBadge = notificationCount + dmUnreadCount
     ```
   - **동기화 시점**:
     - 앱 시작 시
     - DM 탭 진입 시
     - 알림 읽음 처리 시
     - DM 읽음 처리 시

### 3. **네비게이션 연동**
   - **위치**: `lib/services/navigation_service.dart`
   - **동작**: DM 푸시 알림 클릭 시 해당 대화방으로 자동 이동
   - **데이터**:
     ```dart
     type: 'dm_received'
     conversationId: '대화방ID'
     senderId: '발신자ID'
     senderName: '발신자이름'
     ```

### 4. **DM 읽음 처리 시 배지 동기화**
   - **위치**: `lib/services/dm_service.dart`
   - **동작**: `markAsRead()` 메서드에서 배지 자동 동기화

## 🔄 시스템 플로우

### DM 메시지 전송 플로우
```
1. 사용자가 DM 메시지 전송
   ↓
2. Firestore에 메시지 저장 (conversations/{id}/messages)
   ↓
3. Cloud Functions 트리거 발동 (onDMMessageCreated)
   ↓
4. 수신자의 FCM 토큰 조회
   ↓
5. 배지 계산 (일반 알림 + DM)
   ↓
6. FCM 푸시 발송 (잠금화면/알림센터 표시)
   ↓
7. 사용자가 푸시 클릭 → 대화방 화면 이동
```

### 배지 업데이트 플로우
```
[서버 측]
- 일반 알림 생성 → onNotificationCreated → 배지 계산 → FCM 발송
- DM 메시지 생성 → onDMMessageCreated → 배지 계산 → FCM 발송

[클라이언트 측]
- 앱 시작 → BadgeService.syncNotificationBadge()
- DM/알림 탭 진입 → BadgeService.syncNotificationBadge()
- 알림/DM 읽음 처리 → BadgeService.syncNotificationBadge()
```

## 📱 사용자 경험 (UX)

### 잠금화면 알림
```
┌─────────────────────────────────────┐
│ 🔵 Wefilling                        │
│                                     │
│ 철수                                │
│ 내일 저녁 같이 식사할래요?          │
│                                     │
│ 방금                                │
└─────────────────────────────────────┘
```

### 앱 아이콘 배지
```
┌─────────────┐
│             │  ⬅️ 빨간 원에 숫자 표시
│  Wefilling  │     (일반 알림 + DM)
│             │
│      5      │  ⬅️ 예: 일반 알림 3개 + DM 2개
└─────────────┘
```

### DM 탭 배지
```
하단 네비게이션:
[홈] [모임] [친구] [마이] [DM(2)]
                           ↑
                    안 읽은 DM 수만 표시
```

## 🧪 테스트 방법

### 1. DM 푸시 알림 테스트
```
1. 디바이스 A에서 로그인
2. 디바이스 B에서 다른 계정으로 로그인
3. B → A로 DM 전송
4. A의 잠금화면에 푸시 알림 표시 확인
5. 푸시 알림 클릭 → 대화방 자동 이동 확인
```

### 2. 배지 통합 테스트
```
1. 일반 알림 3개 + DM 2개 상태에서
2. 앱 아이콘 배지: 5 표시 확인
3. DM 1개 읽음 → 배지: 4로 변경 확인
4. 일반 알림 1개 읽음 → 배지: 3으로 변경 확인
5. 모두 읽음 → 배지 제거 확인
```

### 3. 로그 확인 (디버깅)
```dart
// 클라이언트 로그
BadgeService: 일반 알림(3) + DM(2) = 5
BadgeService: 배지 설정(5)
```

```typescript
// 서버 로그
📨 새 DM 메시지 감지: conv123/msg456
  - 발신자: userA
  - 수신자: userB
  📊 배지 계산: 일반 알림(3) + DM(2) = 5
✅ DM 푸시 전송 완료: 2/2
```

## 🚀 배포 방법

### 1. Cloud Functions 배포
```bash
cd functions
npm run build
firebase deploy --only functions:onDMMessageCreated
firebase deploy --only functions:onNotificationCreated
```

### 2. Flutter 앱 빌드
```bash
# iOS
flutter build ios --release
open ios/Runner.xcworkspace

# Android
flutter build appbundle --release
```

## 🔧 설정 확인 사항

### Firestore 인덱스
- `conversations` 컬렉션:
  - `participants` (array-contains) + `lastMessageTime` (descending)
  
### Firestore 규칙
```javascript
// conversations/{conversationId}/messages 서브컬렉션
match /messages/{messageId} {
  allow read, write: if request.auth != null 
    && request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participants;
}
```

### FCM 권한 (iOS)
- `ios/Runner/Info.plist`에 알림 권한 포함 확인
- Apple Developer에서 Push Notifications 기능 활성화

## 📊 배지 계산 공식

### 서버 (TypeScript)
```typescript
// 일반 알림 수 (dm_received 제외)
const notificationCount = unreadAll - unreadDm;

// DM 안 읽은 수
let dmUnreadCount = 0;
convsSnap.docs.forEach((doc) => {
  const data = doc.data();
  const archivedBy = data.archivedBy || [];
  if (archivedBy.includes(userId)) return; // 보관 제외
  
  const unreadCount = data.unreadCount || {};
  const myUnread = unreadCount[userId] || 0;
  dmUnreadCount += myUnread;
});

// 최종 배지
const badgeCount = notificationCount + dmUnreadCount;
```

### 클라이언트 (Dart)
```dart
// 일반 알림 수 (dm_received 제외)
final notificationCount = unreadAll - unreadDmNotif;

// DM 안 읽은 수
int dmUnreadCount = 0;
for (final doc in convsSnap.docs) {
  final archivedBy = List<String>.from(data['archivedBy'] ?? []);
  if (archivedBy.contains(user.uid)) continue; // 보관 제외
  
  final unreadCount = Map<String, int>.from(data['unreadCount'] ?? {});
  final myUnread = unreadCount[user.uid] ?? 0;
  dmUnreadCount += myUnread;
}

// 최종 배지
final totalBadge = notificationCount + dmUnreadCount;
```

## ✅ 완료 체크리스트

- [x] DM 푸시 알림 서버 트리거 구현
- [x] 통합 배지 계산 (서버)
- [x] 통합 배지 동기화 (클라이언트)
- [x] DM 푸시 클릭 시 네비게이션
- [x] DM 읽음 처리 시 배지 동기화
- [x] 앱 시작 시 배지 동기화
- [x] 탭 전환 시 배지 동기화
- [x] TypeScript 컴파일 성공
- [ ] Firebase 배포
- [ ] 실기기 테스트

## 🎨 완성도 포인트

1. **일관성**: 모든 알림(일반 + DM)이 하나의 배지 숫자로 통합
2. **실시간성**: 메시지 읽음 처리 즉시 배지 업데이트
3. **정확성**: 보관된 대화방 제외, 나간 대화방 제외
4. **사용자 친화**: 푸시 클릭 시 정확한 화면으로 이동
5. **성능**: 서버에서 배치 처리, 클라이언트에서 캐싱

---

**구현 완료일**: 2026-02-04
**구현자**: AI Assistant (Claude Sonnet 4.5)
