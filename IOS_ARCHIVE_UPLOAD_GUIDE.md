# iOS Archive 및 App Store Connect 업로드 가이드

## 목적
이 문서는 Xcode에서 Archive를 생성하고 App Store Connect에 업로드하여 실제 배포 가능한 상태를 검증하는 절차를 안내합니다.

## 사전 준비사항

### 1. Apple Developer 계정 확인
- Apple Developer Program 가입 완료
- Development Team ID: `ULTS66B6QD` (현재 프로젝트 설정)
- 계정에 App Manager 이상의 권한 필요

### 2. 인증서 및 프로비저닝 프로파일
Xcode가 자동으로 관리하도록 설정되어 있습니다:
- Signing & Capabilities에서 "Automatically manage signing" 활성화 확인
- Team 선택 확인

## Archive 생성 절차

### Step 1: Xcode 워크스페이스 열기

```bash
cd /Users/chajaemin/Desktop/wefilling-nochatbot
open ios/Runner.xcworkspace
```

**주의**: `Runner.xcodeproj`가 아닌 `Runner.xcworkspace`를 열어야 합니다 (CocoaPods 사용).

### Step 2: 빌드 구성 확인

1. Xcode 상단 메뉴에서:
   - **Product** > **Scheme** > **Runner** 선택
   - **Product** > **Destination** > **Any iOS Device (arm64)** 선택

2. 빌드 설정 확인:
   - 좌측 네비게이터에서 Runner 프로젝트 선택
   - Runner 타겟 선택
   - **Signing & Capabilities** 탭 확인:
     - Team: 올바른 팀 선택
     - Bundle Identifier: `com.wefilling.app`
     - Push Notifications capability 활성화 확인
     - Sign in with Apple capability 활성화 확인

### Step 3: Clean Build (선택사항이지만 권장)

```
Product > Clean Build Folder (Shift + Cmd + K)
```

### Step 4: Archive 생성

1. **Product** > **Archive** 클릭
2. 빌드 진행 (5-10분 소요)
3. 완료되면 Organizer 창이 자동으로 열림

**예상 결과**:
- Archive 성공 시: Organizer에 새 Archive가 표시됨
- 실패 시: 빌드 로그에서 에러 확인

### 일반적인 빌드 에러 및 해결방법

#### 에러 1: "No signing certificate found"
**해결**: 
- Xcode > Settings > Accounts에서 Apple ID 로그인 확인
- Signing & Capabilities에서 Team 재선택

#### 에러 2: "Provisioning profile doesn't include the aps-environment entitlement"
**해결**:
- 이미 수정 완료 (엔타이틀먼트 파일에 aps-environment 추가됨)
- Xcode를 재시작하고 다시 시도

#### 에러 3: CocoaPods 관련 에러
**해결**:
```bash
cd ios
pod deintegrate
pod install
```

## App Store Connect 업로드

### Step 1: Organizer에서 업로드

Archive 생성 완료 후:

1. **Window** > **Organizer** (또는 자동으로 열림)
2. **Archives** 탭 선택
3. 최신 Archive 선택
4. **Distribute App** 버튼 클릭

### Step 2: 배포 방법 선택

1. **App Store Connect** 선택
2. **Next** 클릭

### Step 3: 배포 옵션 선택

1. **Upload** 선택 (TestFlight 및 App Store 제출용)
2. **Next** 클릭

### Step 4: App Store Connect 옵션

다음 옵션들을 확인:
- ✅ **Include bitcode for iOS content**: NO (Flutter는 bitcode 미지원)
- ✅ **Upload your app's symbols**: YES (Crashlytics용)
- ✅ **Manage Version and Build Number**: Xcode가 자동 관리

**Next** 클릭

### Step 5: 자동 서명

1. **Automatically manage signing** 선택
2. **Next** 클릭

### Step 6: 최종 검토 및 업로드

1. 앱 정보 검토:
   - Bundle ID: `com.wefilling.app`
   - Version: `1.0.0`
   - Build: `4`
2. **Upload** 클릭
3. 업로드 진행 (5-15분 소요, 파일 크기에 따라 다름)

### Step 7: 업로드 완료 확인

업로드 완료 후:
1. "Upload Successful" 메시지 확인
2. App Store Connect에서 빌드 처리 대기 (5-30분)

## App Store Connect에서 빌드 확인

### 빌드가 나타나기까지

1. https://appstoreconnect.apple.com 접속
2. **나의 앱** 선택
3. **Wefilling** 앱 선택 (없으면 먼저 앱 등록 필요)
4. **TestFlight** 탭 또는 **앱 스토어** 탭 선택
5. **빌드** 섹션에서 업로드된 빌드 확인

**주의**: 
- 빌드가 나타나기까지 5-30분 소요
- "Processing" 상태에서 "Ready to Submit" 상태로 변경되어야 함
- 이메일로 처리 완료 알림 수신

### 빌드 처리 중 발생 가능한 이슈

#### 이슈 1: "Missing Compliance" 경고
**해결**: 
- 빌드 옆의 경고 아이콘 클릭
- 수출 규정 준수 정보 제공
- 암호화 사용 여부: "예" (HTTPS 사용)
- 면제 사유: "표준 암호화만 사용"

#### 이슈 2: "Invalid Binary"
**원인**: 
- 잘못된 Bundle ID
- 누락된 권한 설명
- Privacy Manifest 문제

**해결**: 
- 에러 메시지 확인
- 필요한 수정 후 재업로드

## 검증 체크리스트

업로드 성공 후 다음 항목들을 확인:

### Xcode Organizer
- [ ] Archive 생성 성공
- [ ] "Upload Successful" 메시지 확인
- [ ] 에러 없이 완료

### App Store Connect
- [ ] 빌드가 목록에 나타남
- [ ] "Processing" 상태 확인
- [ ] 5-30분 후 "Ready to Submit" 상태로 변경
- [ ] 수출 규정 준수 정보 제공 완료

### 이메일 알림
- [ ] "Your app is ready to submit" 이메일 수신

## 다음 단계

빌드 업로드 및 처리가 완료되면:

1. **TestFlight 테스트** (선택사항):
   - TestFlight 탭에서 내부 테스터 추가
   - 실제 기기에서 테스트

2. **App Store 제출**:
   - 앱 정보 입력 (메타데이터, 스크린샷 등)
   - 빌드 선택
   - 심사 제출

## 문제 해결

### 업로드가 실패하는 경우

1. **네트워크 확인**:
   - 안정적인 인터넷 연결 필요
   - VPN 사용 시 비활성화 시도

2. **Xcode 버전 확인**:
   - 최신 버전 사용 권장
   - App Store에서 Xcode 업데이트

3. **Apple Developer 계정 상태**:
   - 유효한 멤버십 확인
   - 계약 동의 완료 확인

4. **로그 확인**:
   - Xcode > Window > Devices and Simulators
   - 디바이스 로그에서 상세 에러 확인

### 추가 지원

- Apple Developer 포럼: https://developer.apple.com/forums/
- App Store Connect 도움말: https://developer.apple.com/help/app-store-connect/

## 요약

이 가이드를 따라 수행하면:
1. ✅ Xcode에서 Archive 생성
2. ✅ App Store Connect에 업로드
3. ✅ 빌드 처리 완료 확인
4. ✅ TestFlight 또는 App Store 제출 준비 완료

**현재 상태**: 코드 수정 완료, Archive 생성 및 업로드 준비 완료








