# TestFlight 로그 확인 가이드

## 1. 실시간 Xcode Console 로그 (가장 정확)

### 방법:
1. **iOS 기기를 Mac에 USB로 연결**
2. **Xcode 열기**
3. **Window → Devices and Simulators** (⇧⌘2)
4. **연결된 기기 선택**
5. **"Open Console" 버튼 클릭**
6. **TestFlight 앱 실행**
7. **실시간으로 모든 로그 확인 가능**

### 필터링:
- 검색창에 `wefilling` 입력 → 앱 로그만 표시
- 검색창에 `🔥` 또는 `Firebase` 입력 → Firebase 관련 로그만
- 검색창에 `⚠️` 입력 → 경고 로그만

### 중요 로그 키워드:
```
🧹 Firebase Messaging 캐시 정리
🔑 Firebase Keychain 정리
📌 버전 체크
🔄 문제 버전 감지
✅ FCM 토큰 삭제 완료
⚠️ iOS FCM 초기화 비활성화됨
```

---

## 2. Firebase Crashlytics (크래시 분석)

### 확인 방법:
1. **Firebase Console 접속**: https://console.firebase.google.com
2. **프로젝트 선택**: wefilling
3. **왼쪽 메뉴에서 "Crashlytics" 선택**
4. **크래시 목록 확인**

### 확인할 내용:
- **크래시 발생 시간**
- **스택 트레이스** (어디서 크래시가 발생했는지)
- **영향받은 사용자 수**
- **기기 및 OS 버전**

### 크래시 리포트 읽는 법:
```
Thread 0 Crashed:
0   libicucore.A.dylib    ulocimp_getSubtags
1   FirebaseMessaging     FIRMessagingCurrentLocale
2   FirebaseMessaging     FIRMessagingHasLocaleChanged
3   FirebaseMessaging     -[FIRMessagingTokenInfo isFreshWithIID:]
```
→ Firebase Messaging이 locale 정보를 처리하다가 크래시

---

## 3. 앱 내부 로그 (Custom Logs)

### 현재 버전에서 확인할 수 있는 로그:

#### 앱 시작 시:
```
🧹 Firebase Messaging 캐시 정리: X개 항목 삭제
🔑 Firebase Keychain 정리 완료
📌 버전 체크: "1.0.30" → "1.0.31"
🔄 문제 버전 감지: 1.0.30
✅ FCM 토큰 삭제 완료 (재생성 대기)
```

#### FCM 초기화 시:
```
⚠️ iOS FCM 초기화 비활성화됨 (임시 - 크래시 방지)
```

#### 로그인 시:
```
⚠️ iOS FCM 초기화 비활성화됨 (Google 로그인)
⚠️ iOS FCM 초기화 비활성화됨 (Apple 로그인)
```

---

## 4. iOS 시스템 로그 (.ips 파일)

### TestFlight 크래시 리포트 받는 방법:

#### 방법 1: App Store Connect
1. **App Store Connect 접속**: https://appstoreconnect.apple.com
2. **My Apps → wefilling 선택**
3. **TestFlight 탭**
4. **Builds → 최신 빌드 선택**
5. **"Crashes" 섹션 확인**
6. **.ips 파일 다운로드**

#### 방법 2: 기기에서 직접
1. **설정 → 개인정보 보호 및 보안**
2. **분석 및 개선사항**
3. **분석 데이터**
4. **wefilling으로 시작하는 파일 찾기**
5. **공유 버튼으로 내보내기**

---

## 5. 현재 상황 디버깅

### Phase 5 적용됨 (v1.0.31):
- **iOS에서 FCM 완전 비활성화**
- **앱은 정상 실행되어야 함**
- **푸시 알림은 작동하지 않음 (임시)**

### 확인할 사항:

#### ✅ 앱이 정상 실행되는지:
- 로그인 가능 여부
- 메인 화면 표시 여부
- 크래시 없이 4초 이상 실행되는지

#### ✅ Xcode Console에서 확인:
```
⚠️ iOS FCM 초기화 비활성화됨 (임시 - 크래시 방지)
```
→ 이 로그가 보이면 Phase 5가 정상 작동 중

#### ❌ 여전히 크래시가 발생한다면:
- 크래시가 FCM 초기화 **이전**에 발생하는 것
- 다른 근본 원인이 존재할 가능성
- Xcode Console 로그 전체를 확인하여 어느 단계에서 멈추는지 파악

---

## 6. 로그 수집 체크리스트

### TestFlight 테스트 시 수집할 정보:

- [ ] **Xcode Console 로그** (앱 시작부터 크래시까지 전체)
- [ ] **Crashlytics 크래시 리포트** (있는 경우)
- [ ] **앱 실행 시간** (몇 초 후 크래시되는지)
- [ ] **사용자 상태** (신규/기존, 로그인 여부)
- [ ] **마지막으로 출력된 로그 메시지**

### 로그 공유 방법:
1. Xcode Console에서 우클릭 → "Save Selection"
2. 텍스트 파일로 저장
3. 또는 스크린샷

---

## 7. 다음 단계 결정

### Case 1: 앱이 정상 실행됨
→ **FCM이 문제였음 확인**
→ Firebase SDK 다운그레이드 또는 다른 FCM 초기화 방법 시도

### Case 2: 여전히 크래시 발생
→ **FCM이 아닌 다른 원인**
→ Xcode Console 로그에서 크래시 직전 마지막 로그 확인
→ 예상 원인:
  - Firebase Auth 초기화
  - Firestore 초기화
  - Locale 설정
  - 다른 Firebase 서비스

### Case 3: 특정 시점에서 멈춤 (크래시 아님)
→ **무한 대기 상태**
→ 타임아웃 설정 필요
→ 어느 부분에서 멈추는지 로그로 확인

---

## 현재 버전 정보

- **버전**: 1.0.31 (47)
- **적용된 Phase**: 1 + 2 + 3 + 4 + 5 (모두 적용)
- **iOS FCM 상태**: **비활성화됨**
- **Android FCM 상태**: 정상 작동
- **예상 결과**: iOS 앱 정상 실행 (푸시 알림 제외)
