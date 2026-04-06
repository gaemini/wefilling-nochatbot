# iOS FCM 재활성화 (v1.0.33)

## 🎯 변경 사항

### 문제 상황
- **앱 아이콘 배지**: 정상 작동 ✅
- **상단바 푸시 알림**: 표시 안 됨 ❌

### 원인
v1.0.31~v1.0.32에서 iOS 크래시 문제를 해결하기 위해 **iOS FCM을 완전히 비활성화**했습니다.

```dart
// v1.0.31~v1.0.32 (Phase 5)
if (!kIsWeb && Platform.isIOS) {
  Logger.log('⚠️ iOS FCM 초기화 비활성화됨');
  return;  // FCM 초기화 스킵
}
```

이로 인해:
- **앱 아이콘 배지**: `BadgeService`가 직접 관리 → 정상 작동 ✅
- **푸시 알림**: `FCMService` 비활성화 → 표시 안 됨 ❌

---

## ✅ v1.0.33 수정사항

### 1. AuthProvider - iOS FCM 재활성화

**파일**: `lib/providers/auth_provider.dart` (1752-1785행)

#### 변경 전 (v1.0.32):
```dart
Future<void> _initializeFCMIfNeeded() async {
  // ✅ PHASE 5: iOS FCM 임시 완전 비활성화 (크래시 방지)
  if (!kIsWeb && Platform.isIOS) {
    Logger.log('⚠️ iOS FCM 초기화 비활성화됨');
    return;  // FCM 스킵
  }
  // ...
}
```

#### 변경 후 (v1.0.33):
```dart
Future<void> _initializeFCMIfNeeded() async {
  // ✅ v1.0.32: Firebase 초기화 순서 문제 해결 후 iOS FCM 재활성화
  // iOS 크래시가 여전히 발생하면 다시 비활성화 필요
  
  // 이미 초기화되었거나 사용자가 없으면 스킵
  if (_fcmInitialized || _user == null || _userData == null) {
    return;
  }
  
  // 이메일 인증이 완료된 사용자만 FCM 초기화
  final emailVerified = _userData!['emailVerified'] == true;
  if (!emailVerified) {
    Logger.log('📱 FCM 초기화 스킵: 이메일 인증 미완료');
    return;
  }
  
  try {
    if (kDebugMode) {
      debugPrint('📱 FCM 초기화 시작 (iOS 포함)');
    }
    await FCMService().initialize(_user!.uid);
    _fcmInitialized = true;
    if (kDebugMode) {
      debugPrint('✅ FCM 초기화 완료');
    }
  } catch (e) {
    Logger.error('⚠️ FCM 자동 초기화 실패 (계속 진행): $e');
  }
}
```

---

### 2. Google 로그인 - iOS FCM 재활성화

**파일**: `lib/providers/auth_provider.dart` (406-418행)

#### 변경 전:
```dart
// ✅ PHASE 5: iOS FCM 임시 비활성화
if (!kIsWeb && Platform.isIOS) {
  Logger.log('⚠️ iOS FCM 초기화 비활성화됨');
} else {
  await FCMService().initialize(_user!.uid);
}
```

#### 변경 후:
```dart
// FCM 초기화 (알림 기능)
try {
  if (kDebugMode) {
    debugPrint('📱 FCM 초기화 시작 (Google 로그인)');
  }
  await FCMService().initialize(_user!.uid);
  Logger.log('✅ FCM 초기화 완료');
} catch (e) {
  Logger.error('⚠️ FCM 초기화 실패 (계속 진행): $e');
}
```

---

### 3. Apple 로그인 - iOS FCM 재활성화

**파일**: `lib/providers/auth_provider.dart` (551-563행)

동일하게 iOS FCM 비활성화 로직 제거

---

### 4. Firebase Messaging 백그라운드 핸들러 재활성화

**파일**: `lib/main.dart` (175-195행)

#### 변경 전:
```dart
// ✅ iOS에서만 실행 (Android는 FCM 정상 작동)
if (!kIsWeb && Platform.isIOS) {
  // ⚠️ PHASE 5: iOS FCM 백그라운드 핸들러 등록 스킵 (임시)
  if (kDebugMode) {
    debugPrint('⚠️ iOS FCM 백그라운드 핸들러 등록 스킵');
  }
  // FirebaseMessaging.onBackgroundMessage(...)  ← 주석 처리됨
} else if (!kIsWeb && Platform.isAndroid) {
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
}
```

#### 변경 후:
```dart
// 3. Firebase Messaging 안전 대기 및 백그라운드 핸들러 등록
try {
  await Future.delayed(const Duration(milliseconds: 500));
  
  // ✅ v1.0.33: iOS FCM 백그라운드 핸들러 재활성화
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    if (kDebugMode) {
      debugPrint('📱 FCM 백그라운드 핸들러 등록 완료 (iOS 포함)');
    }
  } catch (handlerError) {
    if (kDebugMode) {
      debugPrint('⚠️ FCM 핸들러 등록 실패 (무시): $handlerError');
    }
  }
} catch (e) {
  if (kDebugMode) {
    debugPrint('⚠️ Firebase Messaging 초기화 실패: $e');
  }
}
```

---

### 5. 버전 업데이트

- **버전**: `1.0.33+49`
- **마이그레이션 버전 목록**: `1.0.32` 추가

---

## 🎯 예상 결과

### ✅ v1.0.33 적용 후:

1. **앱 아이콘 배지**: 정상 작동 유지 ✅
2. **상단바 푸시 알림**: 정상 표시 ✅
3. **포어그라운드 로컬 알림**: 정상 표시 ✅
4. **백그라운드 푸시**: 정상 수신 ✅

---

## ⚠️ 중요: iOS 크래시 모니터링

### v1.0.32에서 적용된 크래시 해결책:

1. **Firebase 초기화 후 2초 안정화 대기** ← 핵심 수정
2. **Phase 1**: iOS AppDelegate - UserDefaults 캐시 정리
3. **Phase 2**: 버전 마이그레이션 - FCM 토큰 삭제
4. **Phase 3**: FCMService - 초기화 전 추가 토큰 정리
5. **Phase 4**: iOS AppDelegate - Keychain 정리

### v1.0.33에서 제거된 것:
- **Phase 5**: iOS FCM 완전 비활성화 (제거)

---

## 🔍 만약 iOS 크래시가 다시 발생한다면?

### 즉시 롤백 방법:

**1. AuthProvider 수정**:
```dart
Future<void> _initializeFCMIfNeeded() async {
  // iOS FCM 다시 비활성화
  if (!kIsWeb && Platform.isIOS) {
    Logger.log('⚠️ iOS FCM 초기화 비활성화됨 (재롤백)');
    return;
  }
  // ...
}
```

**2. Google/Apple 로그인 수정**:
```dart
if (!kIsWeb && Platform.isIOS) {
  Logger.log('⚠️ iOS FCM 초기화 비활성화됨');
} else {
  await FCMService().initialize(_user!.uid);
}
```

**3. main.dart 수정**:
```dart
if (!kIsWeb && Platform.isIOS) {
  debugPrint('⚠️ iOS FCM 백그라운드 핸들러 등록 스킵');
} else {
  FirebaseMessaging.onBackgroundMessage(...);
}
```

---

## 📱 TestFlight 테스트 체크리스트

### 필수 확인 사항:

#### ✅ 크래시 확인:
- [ ] 앱이 5초 이상 정상 실행됨
- [ ] 로그인 가능
- [ ] 메인 화면 표시
- [ ] Xcode Console에 "Firebase 안정화 대기 완료" 로그 확인

#### ✅ 푸시 알림 확인:
- [ ] 앱 아이콘 배지 숫자 표시
- [ ] 상단바 푸시 알림 표시 (앱이 백그라운드일 때)
- [ ] 포어그라운드 로컬 알림 표시 (앱이 실행 중일 때, 비활성 대화방)
- [ ] 푸시 알림 탭 시 해당 화면 이동

---

## 📊 v1.0.31 → v1.0.33 변경 요약

| 버전 | iOS FCM 상태 | iOS 크래시 | 푸시 알림 |
|------|-------------|-----------|----------|
| v1.0.31 | ❌ 비활성화 | ✅ 해결됨 | ❌ 표시 안 됨 |
| v1.0.32 | ❌ 비활성화 | ✅ 해결됨 | ❌ 표시 안 됨 |
| **v1.0.33** | **✅ 활성화** | **? 테스트 필요** | **✅ 정상 작동** |

---

## 결론

v1.0.32에서 적용한 **Firebase 초기화 후 2초 안정화 대기**로 근본 원인이 해결되었다고 판단하여, iOS FCM을 다시 활성화했습니다.

### 테스트 우선순위:
1. **iOS 크래시 발생 여부 확인** (최우선)
2. **푸시 알림 정상 작동 확인**

### 만약 크래시가 다시 발생하면:
→ 즉시 Phase 5 (FCM 비활성화) 재적용 필요

---

## 버전 정보
- **현재 버전**: 1.0.33 (49)
- **핵심 변경**: iOS FCM 재활성화
- **크래시 해결**: Firebase 초기화 후 2초 대기 (v1.0.32에서 적용)
