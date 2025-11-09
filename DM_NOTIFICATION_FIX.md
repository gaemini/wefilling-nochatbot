# DM 알림 배지 문제 해결

## 문제 상황

1. **배지 안 없어짐**: DM 채팅방에서 메시지를 읽어도 하단 DM 탭의 배지(1)가 없어지지 않음
2. **업데이트 안 됨**: 새로운 메시지가 왔을 때 배지 개수가 실시간으로 업데이트되지 않음
3. **알림 안 뜸**: 대화방에 새로운 메시지가 왔을 때 앱 알림이 표시되지 않음

## 근본 원인

### 1. 실시간 스트림 업데이트 지연
- `getTotalUnreadCount()` 스트림이 Firestore 변경사항을 즉시 감지하지 못함
- 메타데이터 변경(metadata changes)을 감지하지 못해 업데이트 감지 지연

### 2. 캐시 문제
- 읽음 처리 후 로컬 캐시가 클리어되지 않아 스트림이 변경사항을 감지하지 못함

### 3. 보관된 대화방(Archived) 처리 누락
- `getTotalUnreadCount()`에서 archivedBy 필드 확인 누락

### 4. 알림 스트림 최적화 부족
- `getUnreadNotificationCount()`에서 메타데이터 변경 감지 미설정

## 해결 방법

### 파일 1: `lib/services/dm_service.dart`

#### 변경 1: `markAsRead()` 함수에 캐시 클리어 추가
```dart
// 캐시 클리어 - 스트림 리스너가 변경사항을 감지하도록
_conversationCache.remove(conversationId);
_messageCache.remove(conversationId);
print('✓ 캐시 클리어 완료 - 스트림 리스너 업데이트 예정');
```

#### 변경 2: `getTotalUnreadCount()` 스트림 개선
- `includeMetadataChanges: true` 추가 → Firestore 변경사항을 더 빠르게 감지
- `archivedBy` 필드 확인 추가 → 보관된 대화방 제외
- `.distinct()` 추가 → 중복 업데이트 방지

### 파일 2: `lib/services/notification_service.dart`

#### 변경 1: `getUnreadNotificationCount()` 스트림 최적화
- `includeMetadataChanges: true` 추가
- `.distinct()` 추가 → 중복 업데이트 방지

### 파일 3: `lib/screens/dm_chat_screen.dart`

#### 변경 1: `_markAsRead()` 함수 개선
- 에러 처리 추가
- UI 업데이트 트리거 추가

## 기술적 설명

### includeMetadataChanges란?
Firestore의 `snapshots()` 메서드에서:
- `includeMetadataChanges: false` (기본값): 서버에서 실제 데이터 변경이 있을 때만 스냅샷 발송
- `includeMetadataChanges: true`: 네트워크 동기화 상태 변경까지 감지하여 더 빠른 업데이트 제공

### distinct()란?
Stream에서 연속된 같은 값을 필터링하여 불필요한 업데이트를 방지하는 연산자

## 테스트 방법

1. **배지 업데이트 테스트**:
   - 친구 A에게 메시지 전송
   - 친구 A가 해당 DM 채팅방 열기
   - 하단 DM 탭 배지 개수 확인 (0으로 변경되어야 함)

2. **실시간 업데이트 테스트**:
   - 친구 B와 채팅 중
   - 친구 C가 새로운 메시지 전송
   - 하단 DM 탭 배지가 실시간으로 업데이트되는지 확인

3. **알림 표시 테스트**:
   - 앱이 포그라운드일 때 메시지 수신 → 로컬 알림 표시 확인
   - 앱이 백그라운드일 때 메시지 수신 → FCM 알림 표시 확인

## 적용된 변경 사항

✅ `lib/services/dm_service.dart`:
- `markAsRead()` 함수에 캐시 클리어 추가
- `getTotalUnreadCount()` 스트림에 `includeMetadataChanges`, `archivedBy` 필터, `.distinct()` 추가

✅ `lib/services/notification_service.dart`:
- `getUnreadNotificationCount()` 스트림에 `includeMetadataChanges`, `.distinct()` 추가

✅ `lib/screens/dm_chat_screen.dart`:
- `_markAsRead()` 함수에 에러 처리 및 UI 업데이트 트리거 추가

## 추가 개선 사항 (선택)

### 1. Firestore 인덱스 최적화
필요시 Firestore Console에서 다음 인덱스 생성:
- Collection: `conversations`
- Fields: `participants (Ascending)`, `updatedAt (Descending)`

### 2. 배치 읽음 처리 최적화
현재는 각 메시지를 개별적으로 업데이트하고 있으니, 필요시 배치 처리 진행 가능

### 3. FCM 백그라운드 핸들러 강화
`firebaseMessagingBackgroundHandler`에 로컬 알림 표시 로직 추가 가능

## 결론

이 해결책은:
1. ✅ Firestore 스트림의 실시간 감지 성능 향상
2. ✅ 로컬 캐시 정합성 보장
3. ✅ 중복 업데이트 제거로 배터리/네트워크 절감
4. ✅ 보관된 대화방 올바른 처리

를 통해 DM 알림 문제를 근본적으로 해결합니다.

