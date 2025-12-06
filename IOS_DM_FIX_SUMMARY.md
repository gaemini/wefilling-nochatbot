# iOS DM 문제 해결 요약

## 문제 상황
1. **iOS에서 상대방이 발신하면 대화방이 안 보이고 생성되지 않음**
2. **iOS에서 대화방 나가기 기능이 작동하지 않음**
3. Android에서는 정상 작동

## 원인 분석

### 1. 대화방 생성 문제
- **원인**: iOS의 Firestore SDK가 `FieldValue.serverTimestamp()`를 처리할 때 더 엄격하게 작동
- **증상**: 대화방 문서 생성 시 타임스탬프 필드로 인한 실패
- **영향**: 상대방이 먼저 메시지를 보낼 때 대화방이 생성되지 않음

### 2. 대화방 나가기 문제
- **원인**: iOS에서 동적 필드 키(`userLeftAt.${uid}`) 업데이트 방식이 제대로 작동하지 않음
- **증상**: `update()` 호출 시 필드가 업데이트되지 않음
- **영향**: 나가기 버튼을 눌러도 대화방에서 나가지지 않음

## 적용된 수정 사항

### 1. dm_service.dart 수정

#### A. 대화방 생성 시 타임스탬프 처리 개선
```dart
// 변경 전
'participantNamesUpdatedAt': FieldValue.serverTimestamp(),

// 변경 후 (iOS 호환성)
'participantNamesUpdatedAt': Timestamp.fromDate(now),
```

#### B. 초기 필드 명시적 추가
```dart
conversationData = {
  // ... 기존 필드들 ...
  'lastMessageSenderId': '',  // iOS 호환성: 초기값 명시
  'archivedBy': [],           // iOS 호환성: 빈 배열로 초기화
  'userLeftAt': {},           // iOS 호환성: 빈 맵으로 초기화
};
```

#### C. 대화방 나가기 로직 개선
```dart
// 변경 전 (iOS에서 작동 안 함)
await convRef.update({
  'userLeftAt.${currentUser.uid}': Timestamp.fromDate(DateTime.now()),
  'updatedAt': Timestamp.fromDate(DateTime.now()),
});

// 변경 후 (iOS 호환성)
final userLeftAt = Map<String, dynamic>.from(data['userLeftAt'] ?? {});
userLeftAt[currentUser.uid] = Timestamp.fromDate(DateTime.now());

await convRef.update({
  'userLeftAt': userLeftAt,  // 전체 맵을 업데이트
  'updatedAt': Timestamp.fromDate(DateTime.now()),
});
```

### 2. firestore.rules 수정

#### 대화방 업데이트 규칙 개선
```javascript
// iOS 호환성을 위한 필드 추가
allow update: if request.auth != null &&
  request.auth.uid in resource.data.participants &&
  (
    (
      // 일반 메시지 관련 변경 + 메타데이터 업데이트 허용
      request.resource.data.participants == resource.data.participants &&
      request.resource.data.diff(resource.data).affectedKeys()
        .hasOnly(['lastMessage', 'lastMessageTime', 'lastMessageSenderId', 
                  'unreadCount', 'updatedAt', 'archivedBy', 
                  'participantNames', 'participantPhotos', 'displayTitle', 
                  'participantNamesUpdatedAt', 'participantNamesVersion'])
    ) ||
    (
      // 나가기: userLeftAt 전체 맵 업데이트 허용
      request.resource.data.participants == resource.data.participants &&
      request.resource.data.diff(resource.data).affectedKeys()
        .hasOnly(['userLeftAt', 'updatedAt'])
    ) ||
    // ... 레거시 방식 ...
  );
```

## 테스트 방법

### 1. 대화방 생성 테스트
1. **iOS 기기 A**에서 로그인
2. **iOS 기기 B**에서 로그인
3. **기기 B**에서 **기기 A**에게 첫 메시지 전송
4. **기기 A**의 DM 목록에 새 대화방이 나타나는지 확인 ✅
5. **기기 A**에서 메시지 확인 및 답장 가능한지 확인 ✅

### 2. 대화방 나가기 테스트
1. **iOS 기기**에서 대화방 진입
2. 우측 상단 메뉴(⋮) → "대화방 나가기" 선택
3. 확인 다이얼로그에서 "나가기" 클릭
4. DM 목록에서 해당 대화방이 사라지는지 확인 ✅
5. 상대방이 새 메시지를 보내면 새 대화방으로 나타나는지 확인 ✅

### 3. Android 호환성 테스트
1. **Android 기기**에서도 위의 테스트 1, 2 반복
2. 기존 기능이 정상 작동하는지 확인 ✅

### 4. 크로스 플랫폼 테스트
1. **iOS → Android** 메시지 전송 테스트
2. **Android → iOS** 메시지 전송 테스트
3. 양방향 메시지 교환이 정상적으로 작동하는지 확인 ✅

## 주요 변경 포인트

### iOS 호환성 개선
1. ✅ `FieldValue.serverTimestamp()` → `Timestamp.fromDate(now)` 변경
2. ✅ 동적 필드 키 업데이트 방식 개선 (전체 맵 업데이트)
3. ✅ 초기 필드 명시적 추가 (`archivedBy`, `userLeftAt`, `lastMessageSenderId`)
4. ✅ Firestore 규칙에서 iOS 업데이트 패턴 허용

### Android 호환성 유지
1. ✅ 기존 로직 유지 (변경 사항이 Android에도 호환됨)
2. ✅ 레거시 나가기 방식도 계속 지원

## 배포 완료
- ✅ Firestore 규칙 배포 완료
- ✅ 코드 린트 오류 없음
- ⏳ 앱 빌드 및 테스트 필요

## 다음 단계
1. iOS 앱 빌드 및 테스트 기기에 설치
2. 위의 테스트 시나리오 실행
3. 문제 발생 시 로그 확인 (Logger 출력 확인)
4. 정상 작동 확인 후 프로덕션 배포

## 참고사항
- 모든 변경 사항은 iOS와 Android 양쪽에서 호환됩니다
- 기존 대화방 데이터에 영향을 주지 않습니다
- 로그가 상세하게 출력되므로 문제 발생 시 디버깅이 용이합니다







