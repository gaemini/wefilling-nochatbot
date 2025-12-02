# Apple Sign In 설정 가이드

## ✅ 코드 구현 완료!

Apple Sign In 기능이 코드에 성공적으로 통합되었습니다.
이제 Xcode에서 마지막 설정을 완료해주세요.

---

## ⚠️ 필수: Xcode에서 Capability 추가

Apple Sign In을 사용하려면 Xcode에서 다음 설정을 반드시 해주셔야 합니다:

### 단계별 가이드

1. **Xcode 열기**
   ```bash
   open ios/Runner.xcworkspace
   ```

2. **프로젝트 네비게이터에서 Runner 선택**
   - 좌측 파일 트리에서 맨 위에 있는 "Runner" 프로젝트 클릭

3. **타겟 선택**
   - "TARGETS" 섹션에서 "Runner" 선택

4. **Signing & Capabilities 탭으로 이동**
   - 상단 탭에서 "Signing & Capabilities" 클릭

5. **Capability 추가**
   - "+ Capability" 버튼 클릭 (왼쪽 상단)
   - 검색창에 "Sign in with Apple" 입력
   - "Sign in with Apple" 선택하여 추가

6. **프로젝트 저장**
   - `Command + S`로 저장

---

## 📱 테스트 방법

### 1. 앱 다시 빌드
```bash
flutter clean
flutter pub get
flutter build ios
```

### 2. 실제 iOS 기기에서 테스트
- **중요**: Apple Sign In은 시뮬레이터에서 제대로 작동하지 않을 수 있습니다
- 실제 iOS 기기에서 테스트하는 것을 권장합니다

### 3. 테스트 시나리오

**신규 사용자 (Apple 계정)**
1. "Apple로 로그인" 버튼 클릭
2. "회원가입 필요" 안내 확인
3. "회원가입하기" 클릭
4. 한양메일 인증 (예: abc@hanyang.ac.kr)
5. "Apple로 계속하기" 선택
6. Apple 인증 진행
7. 닉네임 설정
8. 완료!

**기존 사용자 (Google 계정) - 정상 작동 확인**
1. "Google로 로그인" 버튼 클릭
2. 기존과 동일하게 작동하는지 확인

---

## 🔒 보안 검증

### 한양메일 1개당 계정 1개 제한
- ✅ Google로 등록한 메일은 Apple로 등록 불가
- ✅ Apple로 등록한 메일은 Google로 등록 불가
- ✅ Cloud Functions에서 자동 처리

### 테스트 방법
1. Google 계정으로 회원가입 (예: test@hanyang.ac.kr)
2. 로그아웃
3. Apple 계정으로 로그인 시도
4. 동일한 한양메일(test@hanyang.ac.kr) 인증 시도
5. **예상 결과**: "이미 사용된 한양메일입니다" 에러

---

## 📋 구현 완료 항목

### iOS 설정
- ✅ NSPhotoLibraryUsageDescription 추가
- ✅ NSCameraUsageDescription 추가
- ✅ NSAllowsArbitraryLoads 제거 (보안 강화)

### 코드 구현
- ✅ sign_in_with_apple 패키지 추가
- ✅ AuthService.signInWithApple() 구현
- ✅ AuthProvider.signInWithApple() 구현
- ✅ 한양메일 인증 화면 업데이트 (Google/Apple 선택)
- ✅ 로그인 화면에 Apple 버튼 추가
- ✅ 다국어 지원 (한국어/영어)

### 기존 기능 보호
- ✅ Google 로그인 코드 변경 없음
- ✅ 한양메일 인증 로직 변경 없음
- ✅ 기존 사용자 로그인 플로우 동일

---

## ❓ 문제 해결 (트러블슈팅)

### 🔍 자동 진단 스크립트

문제를 빠르게 파악하려면 먼저 이 스크립트를 실행해보세요:

```bash
bash scripts/check_apple_signin.sh
```

이 스크립트는 다음을 자동으로 확인합니다:
- ✅ Xcode Capability 추가 여부
- ✅ sign_in_with_apple 패키지 설치
- ✅ Bundle ID
- ✅ iOS 최소 버전
- ✅ Info.plist 권한 설정

---

### 🚨 에러별 해결 방법

#### 에러 1: `[firebase_auth/unknown] An unknown error has occurred`

**증상**: Apple 로그인 버튼 클릭 시 즉시 실패

**원인 (우선순위순)**:

**1️⃣ Xcode Capability 미추가** (가장 흔함)
```bash
# 확인
open ios/Runner.xcworkspace
# Runner 타겟 → Signing & Capabilities 탭 → "Sign in with Apple" 있는지 확인

# 없다면 추가:
# + Capability 클릭 → "Sign in with Apple" 검색 → 추가
```

**2️⃣ 시뮬레이터에 Apple ID 미로그인**
```
시뮬레이터 → 설정 앱 → 맨 위 "Apple ID 로그인"
```

시뮬레이터에 Apple ID가 로그인되어 있지 않으면 Apple Sign In이 작동하지 않습니다.

**3️⃣ 시뮬레이터 제약**

Apple Sign In은 시뮬레이터에서 불안정할 수 있습니다.
→ **실제 iPhone에서 테스트 강력 권장**

---

#### 에러 2: Apple 로그인이 취소됨

**증상**: Apple 로그인 다이얼로그가 나타난 후 취소 버튼 클릭

**해결**: 정상 동작입니다. 다시 시도하세요.

---

#### 에러 3: 네트워크 오류

**증상**: 인터넷 연결 문제

**해결**:
- WiFi 연결 확인
- VPN 사용 시 비활성화 후 재시도

---

### 📱 시뮬레이터 vs 실제 기기

#### 시뮬레이터에서 테스트

**설정 필요**:
1. 시뮬레이터 실행
2. 설정 앱 열기
3. 맨 위 "Sign in to your iPhone" 클릭
4. Apple ID 로그인 (실제 Apple 계정)
5. 앱 실행하여 테스트

**제약 사항**:
- ⚠️ 일부 기능이 불안정할 수 있음
- ⚠️ Face ID/Touch ID 시뮬레이션 제한
- ⚠️ `unknown` 에러가 발생할 수 있음

**권장하지 않음**: 가능하면 실제 기기 사용

---

#### 실제 iOS 기기에서 테스트 (강력 권장) ✅

**장점**:
- ✅ 기기에 로그인된 Apple ID 자동 사용
- ✅ Face ID/Touch ID로 빠른 인증
- ✅ 안정적이고 실제 사용자 경험과 동일
- ✅ 비밀번호 입력 불필요

**테스트 방법**:
1. iPhone을 Mac에 USB로 연결
2. Xcode에서 상단 기기 선택 드롭다운 클릭
3. 연결된 iPhone 선택
4. `Command + R` (또는 Play 버튼)
5. iPhone에서 "Apple로 로그인" 버튼 클릭
6. Face ID/Touch ID로 인증
7. 완료!

---

### 🔧 상세 로그 확인하기

앱을 실행할 때 콘솔 로그를 주의 깊게 보세요:

**정상 작동 시**:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🍎 Apple Sign In 시작
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🍎 AppleAuthProvider 생성 중...
🍎 AppleAuthProvider 생성 완료 (scopes: email, name)
🍎 Firebase Auth signInWithProvider 호출 중...
🍎 Apple Sign In 성공!
   User ID: abc123...
   Email: privaterelay@appleid.com
   Display Name: John Doe
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Capability 미추가 시**:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🍎 Apple Sign In 시작
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🍎 AppleAuthProvider 생성 중...
🍎 AppleAuthProvider 생성 완료 (scopes: email, name)
🍎 Firebase Auth signInWithProvider 호출 중...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🍎 Apple Sign In 실패 (FirebaseAuthException)
   에러 코드: unknown
   에러 메시지: An unknown error has occurred.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💡 해결 방법:
   1. Xcode에서 "Sign in with Apple" Capability 추가 확인
   2. 시뮬레이터의 경우 설정에서 Apple ID 로그인 확인
   3. 실제 iOS 기기에서 테스트 권장
```

---

### 🎯 단계별 체크리스트

Apple Sign In이 작동하지 않을 때 순서대로 확인하세요:

- [ ] **1단계**: `bash scripts/check_apple_signin.sh` 실행
- [ ] **2단계**: Xcode에서 "Sign in with Apple" Capability 추가 확인
- [ ] **3단계**: 시뮬레이터 사용 시 → 설정에서 Apple ID 로그인
- [ ] **4단계**: 앱 재빌드 (`flutter clean && flutter build ios`)
- [ ] **5단계**: 실제 iPhone에서 테스트

---

### 📞 추가 지원

위 방법으로도 해결되지 않으면:

1. **Flutter 콘솔 로그** 전체 복사
2. **Xcode 콘솔 로그** 확인
3. **Firebase Console** → Functions 로그 확인
4. Apple Developer Console에서 Bundle ID 설정 확인

---

### 💡 자주 묻는 질문 (FAQ)

**Q: 시뮬레이터에서 Apple Sign In이 작동하지 않아요**
A: 시뮬레이터 설정에서 Apple ID 로그인이 필요합니다. 또는 실제 기기에서 테스트하세요.

**Q: Google은 되는데 Apple만 안 돼요**
A: Xcode에서 "Sign in with Apple" Capability 추가 여부를 확인하세요.

**Q: "이미 사용된 한양메일" 에러가 안 나와요**
A: 정상입니다. Cloud Functions에서 처리하므로 한양메일 인증 단계에서 에러가 표시됩니다.

**Q: Apple ID 이메일이 "privaterelay@appleid.com" 형식이에요**
A: 정상입니다. 사용자가 이메일 숨기기를 선택한 경우 Apple이 제공하는 프록시 이메일입니다.

---

**모든 설정이 완료되면 Apple Sign In을 사용할 수 있습니다!** 🎉






