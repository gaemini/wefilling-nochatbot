# 🍎 Xcode에서 iOS 빌드 및 제출 가이드

**버전**: 1.3.8+78
**최종 점검일**: 2026-09-04

---

## ✅ 사전 준비 완료 사항

### 1. 버전 업데이트 완료
- ✅ `pubspec.yaml`: **1.3.8+78**
- ✅ 앱스토어 제출 준비됨

### 2. iOS 환경 설정 완료
- ✅ CocoaPods 설치 완료
- ✅ Firebase SDK 설정
- ✅ Bundle ID: `com.wefilling.app`
- ✅ 푸시 알림: production 환경
- ✅ Privacy Manifest 완료
- ✅ 권한 설명: 한국어

### 3. 빌드 전 자동 점검

아래 명령이 통과해야 Xcode Archive 또는 IPA 생성을 진행합니다. Runner와
Share Extension의 배포 서명, 번들 ID, Firebase 프로젝트, App Check 환경,
버전 증가 여부를 함께 확인합니다.

```bash
bash scripts/ios_release.sh check
```

설치된 Apple Distribution 인증서로 검증된 IPA를 직접 만들려면 다음 명령을
사용합니다.

```bash
bash scripts/ios_release.sh build --yes
```

---

## 🚀 Xcode에서 빌드하기

### 1단계: Xcode 열기

```bash
open ios/Runner.xcworkspace
```

⚠️ **중요**: `.xcodeproj`가 아닌 `.xcworkspace`를 열어야 합니다!

---

### 2단계: Signing & Capabilities 설정

1. **프로젝트 네비게이터**에서 `Runner` 선택
2. **Signing & Capabilities** 탭 선택
3. **Team** 선택 (Apple Developer 계정)
4. **Automatically manage signing** 체크
5. `ShareExtension` 타깃도 같은 Team과 자동 서명을 사용하도록 확인

확인 사항:
- ✅ Bundle Identifier: `com.wefilling.app`
- ✅ Signing Certificate: 자동 선택됨
- ✅ Provisioning Profile: 자동 생성됨

> 자동 서명을 사용할 때 Runner와 ShareExtension의 `Code Signing Identity`는
> 기기 빌드 기준 `Apple Development`로 둡니다. Release/Profile에
> `Apple Distribution`을 직접 지정하면 자동 프로비저닝과 충돌합니다.
> App Store용 Archive는 내보내기 과정에서 Xcode가 설치된 배포 인증서로
> 자동 재서명합니다.

---

### 3단계: Release 스킴 선택

1. 상단 바에서 **Runner** > **Any iOS Device** 선택
2. **Product** > **Scheme** > **Edit Scheme...**
3. **Run** 선택 후 **Build Configuration**을 **Release**로 변경
4. Close

---

### 4단계: Archive 생성

1. **Product** > **Archive** 클릭
2. 빌드 완료까지 대기 (약 5-10분)
3. 성공하면 Organizer 창이 자동으로 열림

---

### 5단계: App Store Connect에 업로드

Organizer에서:

1. 생성된 Archive 선택
2. **Distribute App** 클릭
3. **App Store Connect** 선택 → Next
4. **Upload** 선택 → Next
5. **Automatically manage signing** 선택 → Next
6. 업로드 완료 대기

---

## 📱 App Store Connect에서 제출

### 1. 빌드 처리 대기

- 업로드 후 5-30분 대기
- App Store Connect에서 빌드 처리 중...
- 이메일로 알림 받음

### 2. 버전 정보 입력

**App Store Connect** > **나의 앱** > **Wefilling**

#### 버전 정보
- 버전: **1.3.8**
- 빌드: **78** (자동 선택)

#### 새로운 기능 (변경 로그)
```
버전 1.3.8 업데이트

• 앱 안정성 향상
• 성능 최적화
• 버그 수정 및 개선
```

#### 스크린샷 (필수)
- 6.7" (iPhone 15 Pro Max): 최소 3개
- 6.5" (iPhone 14 Plus): 최소 3개
- 5.5" (iPhone 8 Plus): 최소 3개

**촬영 방법**:
```bash
# 시뮬레이터에서 앱 실행
flutter run

# Cmd + S로 스크린샷 촬영
# 저장 위치: ~/Desktop
```

#### App Privacy (개인정보 보호)

**수집하는 데이터**:
- 이름, 이메일 주소
- 프로필 사진
- 대학 정보
- 사용자 콘텐츠 (게시글, 메시지)

**데이터 사용 목적**:
- 앱 기능
- 제품 개인화

**추적 여부**: 아니오

#### 수출 규정 준수

- 암호화 사용: **예** (HTTPS)
- 면제 사유: **표준 암호화만 사용**

---

### 3. 심사 정보 입력

#### 심사 노트
```
심사자님께,

이 앱은 한양대학교 학생 전용 플랫폼으로, 
한양대학교 이메일(@hanyang.ac.kr) 인증이 필요합니다.

테스트 계정 정보:
- 이메일: hanwhapentest@gmail.com
- 로그인 방법: Google 로그인 선택 후 위 이메일로 로그인

이 테스트 계정은 이미 한양메일 인증이 완료되어 있어 
바로 사용 가능합니다.

감사합니다.
```

#### 연락처 정보
- 이메일: wefilling@gmail.com

---

### 4. 심사 제출

1. **버전 추가** 클릭
2. 모든 필수 항목 작성 확인
3. **심사 제출** 클릭
4. 확인 팝업에서 **제출** 클릭

---

## ⚠️ 문제 해결

### Archive 생성 실패 시

```bash
# 1. Pod 재설치
cd ios
pod deintegrate
pod install

# 2. Xcode 캐시 정리
# Xcode > Product > Clean Build Folder (Cmd + Shift + K)

# 3. 다시 Archive 시도
```

### Signing 오류 시

1. Xcode > Preferences > Accounts
2. Apple ID 확인
3. "Download Manual Profiles" 클릭
4. 다시 시도

### 빌드 오류 시

```bash
# Flutter 클린 및 재빌드
flutter clean
flutter pub get
cd ios
pod install
```

---

## 📊 현재 설정 상태

### ✅ 완료된 항목
- [x] 버전 1.3.8+78로 업데이트
- [x] CocoaPods 설치 완료
- [x] Firebase SDK 12.8.0
- [x] Bundle ID 설정
- [x] 푸시 알림 production 환경
- [x] Privacy Manifest 추가
- [x] 엔타이틀먼트 설정

### 📝 사용자 작업 필요
- [ ] Xcode에서 Signing 설정
- [ ] Archive 생성
- [ ] App Store Connect 업로드
- [ ] 스크린샷 준비
- [ ] 앱 설명 작성
- [ ] 심사 제출

---

## 🎯 예상 소요 시간

| 단계 | 시간 |
|------|------|
| Xcode Signing 설정 | 5분 |
| Archive 생성 | 5-10분 |
| 업로드 | 5-10분 |
| 빌드 처리 대기 | 5-30분 |
| 메타데이터 입력 | 30-60분 |
| 스크린샷 촬영 | 1-2시간 |
| **총 소요 시간** | **2-4시간** |

**심사 기간**: 1-3일 (평균 24-48시간)

---

## 📞 지원

**문제 발생 시**:
- Apple Developer 지원: https://developer.apple.com/support/
- Firebase 지원: https://firebase.google.com/support

**프로젝트 문서**:
- 개인정보 처리방침: https://gaemini.github.io/wefilling-nochatbot/
- 서비스 이용약관: https://gaemini.github.io/wefilling-nochatbot/terms.html

---

**준비 완료!** 🚀

이제 Xcode를 열고 Archive를 생성하세요!

```bash
open ios/Runner.xcworkspace
```
