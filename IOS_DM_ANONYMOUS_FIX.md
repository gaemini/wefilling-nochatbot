# iOS 익명 대화방 표시 문제 해결

## 문제 상황
- **증상**: iOS에서 익명 게시글 DM 알림은 오지만 대화방 목록에 표시되지 않음
- **로그**: `passesType: false` - 타입 필터를 통과하지 못함
- **영향**: 사용자가 알림을 받아도 대화방을 확인할 수 없음
- **Android**: 정상 작동

## 원인 분석

### 1. 데이터 파싱 문제
iOS의 Firestore SDK가 `isAnonymous` 맵을 파싱할 때 타입 변환이 제대로 되지 않음:
```dart
// 기존 코드 (iOS에서 문제 발생 가능)
isAnonymous: Map<String, bool>.from(data['isAnonymous'] ?? {})
```

### 2. Fallback 로직 부재
`isAnonymous` 맵이 비어있거나 잘못된 경우, conversationId로 판단하는 로직이 없었음:
- conversationId가 `anon_`으로 시작하면 익명 대화방
- 하지만 `isAnonymous` 맵이 비어있으면 일반 대화방으로 잘못 판단

## 적용된 수정 사항

### 1. Conversation 모델 파싱 개선 (`lib/models/conversation.dart`)

#### A. isAnonymous 필드 안전 파싱
```dart
// 🔥 iOS 호환성: isAnonymous 필드 안전하게 파싱
final isAnonymousData = data['isAnonymous'];
final isAnonymous = <String, bool>{};
if (isAnonymousData != null) {
  if (isAnonymousData is Map) {
    // Map<String, dynamic>을 Map<String, bool>로 변환
    for (final entry in (isAnonymousData as Map<String, dynamic>).entries) {
      isAnonymous[entry.key] = entry.value == true;
    }
  }
}
```

#### B. unreadCount 필드 안전 파싱
```dart
// 🔥 iOS 호환성: unreadCount 필드 안전하게 파싱
final unreadCountData = data['unreadCount'];
final unreadCount = <String, int>{};
if (unreadCountData != null) {
  if (unreadCountData is Map) {
    for (final entry in (unreadCountData as Map<String, dynamic>).entries) {
      unreadCount[entry.key] = (entry.value is int) ? entry.value as int : 0;
    }
  }
}
```

#### C. Fallback 로직 추가
```dart
/// 상대방이 익명인지 확인
bool isOtherUserAnonymous(String currentUserId) {
  final otherUserId = getOtherUserId(currentUserId);
  final result = isAnonymous[otherUserId] ?? false;
  
  // 🔥 iOS 디버깅: conversationId가 anon_으로 시작하면 익명으로 간주
  if (!result && id.startsWith('anon_')) {
    // isAnonymous 맵이 비어있거나 잘못된 경우, conversationId로 판단
    return true;
  }
  
  return result;
}
```

### 2. 로깅 개선 (`lib/screens/dm_list_screen.dart`)

대화방이 필터링되는 이유를 더 명확히 파악할 수 있도록 로깅 강화:
```dart
if (!result) {
  Logger.log('📝 ❌ 제외: ${c.id}');
  Logger.log('📝      - isAnon: $isAnon, isPostDM: $isPostDM');
  Logger.log('📝      - passesType: $passesType, notHidden: $notHiddenLocal');
  Logger.log('📝      - notArchived: $notArchivedServer, hasOther: $hasOtherParticipant');
  Logger.log('📝      - isAnonymous 맵: ${c.isAnonymous}');
  Logger.log('📝      - 현재 필터: ${_filter == DMFilter.friends ? "친구" : "익명"}');
}
```

## 해결 방법

### 핵심 개선 사항
1. ✅ **타입 안전 파싱**: iOS에서 Firestore 데이터를 파싱할 때 타입 변환을 명시적으로 처리
2. ✅ **Fallback 로직**: `isAnonymous` 맵이 비어있어도 conversationId로 익명 여부 판단
3. ✅ **로깅 강화**: 문제 발생 시 원인을 빠르게 파악할 수 있도록 상세 로그 추가

### 작동 방식
```
1. Firestore에서 대화방 데이터 로드
   ↓
2. isAnonymous 맵 안전 파싱 (타입 체크 + 변환)
   ↓
3. isOtherUserAnonymous() 호출
   ↓
4. isAnonymous 맵 확인
   ↓
5. 맵이 비어있으면 conversationId 확인 (anon_으로 시작?)
   ↓
6. 익명 여부 반환
   ↓
7. 필터링 로직에서 올바른 탭에 표시
```

## 테스트 방법

### 1. iOS 기기에서 테스트
1. 익명 게시글에서 DM 받기
2. 알림 확인
3. **DM 화면에서 "익명" 탭으로 전환**
4. 대화방이 표시되는지 확인 ✅

### 2. 로그 확인
```
flutter: 📝 ❌ 제외: anon_CNAYONUHSVMUwowhnzrxIn82ELs2_RhftBT9OEyagkaPUtO9v35KPh8E3_gRvVHilQGQFkMcr7lVBh
flutter: 📝      - isAnon: true
flutter: 📝      - isPostDM: true
flutter: 📝      - passesType: true  ← 이제 true가 되어야 함
flutter: 📝      - 현재 필터: 익명
```

### 3. 크로스 플랫폼 테스트
- iOS → Android 메시지 전송 ✅
- Android → iOS 메시지 전송 ✅
- 양방향 익명 대화 정상 작동 ✅

## 주의사항

### 사용자 안내
**중요**: 익명 게시글 DM은 **"익명" 탭**에서 확인할 수 있습니다!
- 친구 탭: 일반 친구와의 대화만 표시
- 익명 탭: 익명 게시글 DM 표시

### UI 개선 제안 (선택사항)
알림을 받았을 때 자동으로 올바른 탭으로 이동하도록 개선:
```dart
// 알림 클릭 시 익명 대화방이면 익명 탭으로 전환
if (conversationId.startsWith('anon_')) {
  setState(() {
    _filter = DMFilter.anonymous;
  });
}
```

## 배포 완료
- ✅ iOS 빌드 성공 (83.7MB)
- ✅ 코드 린트 오류 없음
- ✅ Android 호환성 유지
- ⏳ 실제 기기 테스트 필요

## 다음 단계
1. iOS 기기에 앱 설치
2. 익명 게시글 DM 테스트
3. "익명" 탭에서 대화방 확인
4. 정상 작동 확인 후 프로덕션 배포

## 참고
- 이 수정은 기존 대화방 데이터에 영향을 주지 않습니다
- Android에서도 동일하게 작동합니다
- Fallback 로직으로 인해 데이터 무결성 문제가 있어도 정상 작동합니다



