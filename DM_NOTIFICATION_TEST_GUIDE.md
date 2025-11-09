# DM 알림·배지 수정사항 테스트 가이드

## 🎯 수정 완료 사항

### 1. 기존 기능 완전 보존
- **모든 기존 DM 기능은 그대로 동작**
- 새 기능은 Feature Flag로 제어 (기본 OFF)
- 문제 발생 시 즉시 롤백 가능

### 2. 추가된 기능들
1. **FCM 직접 전송**: DM 메시지 전송 시 실제 푸시 알림 발송
2. **배지 주기적 동기화**: 30초마다 배지 카운트 강제 새로고침
3. **라이프사이클 읽음 처리**: 앱 포어그라운드 복귀 시 자동 읽음 처리

## 🔧 테스트 방법

### Phase 1: 기본 동작 확인 (플래그 OFF)
```dart
// lib/utils/dm_feature_flags.dart에서 모든 플래그가 false인지 확인
static const bool enableDirectFCM = false;
static const bool enablePeriodicSync = false;
static const bool enableLifecycleRead = false;
```

**테스트 시나리오:**
1. DM 메시지 전송/수신
2. 배지 카운트 증가/감소
3. 읽음 처리
4. 대화방 목록

**예상 결과:** 기존과 완전히 동일하게 동작

### Phase 2: FCM 직접 전송 테스트
```dart
// 1단계: FCM 서버 키 설정 필요
// lib/services/fcm_direct_service.dart의 _fcmServerKey 값 설정

// 2단계: 플래그 활성화
static const bool enableDirectFCM = true;
static const bool enableDebugLogs = true; // 디버그 로그 활성화
```

**테스트 시나리오:**
1. A 사용자 → B 사용자에게 DM 전송
2. B 사용자가 앱을 백그라운드/종료 상태일 때
3. B 사용자에게 푸시 알림이 도착하는지 확인

**확인 포인트:**
- 기존 Firestore 알림 생성 + FCM 직접 전송 둘 다 실행
- 로그에서 "✅ FCM 직접 전송 성공" 메시지 확인
- B 사용자 디바이스에 실제 푸시 알림 도착

### Phase 3: 배지 주기적 동기화 테스트
```dart
static const bool enablePeriodicSync = true;
static const bool enableDebugLogs = true;
```

**테스트 시나리오:**
1. DM 메시지 수신 후 배지 카운트 확인
2. 30초 대기
3. 로그에서 "🔄 배지 주기적 동기화" 메시지 확인
4. 배지가 정확한 값으로 업데이트되는지 확인

### Phase 4: 라이프사이클 읽음 처리 테스트
```dart
static const bool enableLifecycleRead = true;
static const bool enableDebugLogs = true;
```

**테스트 시나리오:**
1. DM 채팅방 진입 (배지 있는 상태)
2. 홈 버튼으로 앱 백그라운드 전환
3. 앱 아이콘 터치로 포어그라운드 복귀
4. 로그에서 "🔄 앱 포어그라운드 복귀 - 읽음 처리 실행" 확인
5. 배지가 0으로 변경되는지 확인

## 🚨 문제 발생 시 즉시 롤백

```dart
// 모든 플래그를 false로 변경
class DMFeatureFlags {
  static const bool enableDirectFCM = false;
  static const bool enablePeriodicSync = false;
  static const bool enableLifecycleRead = false;
  static const bool enableDebugLogs = false;
}
```

**핫 리로드/재시작 후 기존 상태로 완전 복구됩니다.**

## 📝 로그 모니터링

디버그 로그 활성화 시 다음 메시지들을 확인하세요:

### FCM 직접 전송
```
📱 FCM 직접 전송 시작: [userId]
✅ FCM 직접 전송 성공: [userId]
❌ FCM 직접 전송 실패 (무시): [userId]
```

### 배지 주기적 동기화
```
🔄 배지 주기적 동기화 활성화됨 (30초마다)
🔢 getTotalUnreadCount 업데이트 - 시작
```

### 라이프사이클 읽음 처리
```
🔄 라이프사이클 관찰자 등록됨
🔄 앱 라이프사이클 변경: AppLifecycleState.resumed
🔄 앱 포어그라운드 복귀 - 읽음 처리 실행
```

## ⚠️ 주의사항

1. **FCM 서버 키**: 실제 테스트를 위해서는 Firebase 프로젝트의 서버 키가 필요합니다
2. **점진적 테스트**: 한 번에 모든 플래그를 켜지 말고 하나씩 테스트하세요
3. **로그 확인**: 각 기능이 정상 동작하는지 로그로 확인하세요
4. **기존 기능 우선**: 새 기능이 실패해도 기존 DM 기능은 정상 동작합니다

## 🎉 성공 기준

- [ ] 기존 DM 기능 100% 정상 동작 (플래그 OFF 상태)
- [ ] FCM 직접 전송으로 실제 푸시 알림 수신
- [ ] 배지 카운트가 실시간으로 정확하게 업데이트
- [ ] 앱 재진입 시 자동 읽음 처리로 배지 0 변경
- [ ] 모든 플래그 OFF 시 즉시 기존 상태로 복구
