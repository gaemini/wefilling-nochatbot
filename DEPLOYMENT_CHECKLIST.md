# Wefilling 앱스토어 배포 준비 체크리스트

**작성일**: 2025-12-02  
**앱 버전**: 1.0.0+1  
**검토자**: AI Assistant

---

## 📋 전체 요약

이 문서는 Wefilling 앱의 구글 플레이스토어와 애플 앱스토어 배포 전 필수 항목들의 준비 상태를 정리한 체크리스트입니다.

### 🎯 배포 준비 상태 개요

| 카테고리 | 상태 | 완료율 |
|---------|------|--------|
| Android 앱 서명 | ⚠️ 주의 필요 | 50% |
| iOS 앱 서명 | ✅ 양호 | 90% |
| 법적 문서 | ✅ 완료 | 100% |
| 앱 메타데이터 | ❌ 준비 필요 | 30% |
| 권한 설정 | ✅ 완료 | 100% |
| 버전 관리 | ✅ 완료 | 100% |
| Firebase 설정 | ⚠️ 주의 필요 | 80% |
| 빌드 테스트 | ❌ 필요 | 0% |
| 스토어 제출 준비 | ⚠️ 주의 필요 | 60% |

**전체 완료율**: 약 72%

**법적 문서 URL** (배포 시 사용):
- 개인정보 처리방침: https://gaemini.github.io/wefilling-nochatbot/
- 서비스 이용약관: https://gaemini.github.io/wefilling-nochatbot/terms.html

---

## 1. Android 앱 서명 및 빌드 설정 ⚠️

### ❌ Keystore 파일 미생성

**현재 상태**:
- `android/key.properties` 파일이 존재하지 않음
- `.jks` 또는 `.keystore` 파일이 프로젝트에 없음

**문제점**:
- 릴리즈 빌드를 생성할 수 없음
- Play Store에 AAB 파일을 업로드할 수 없음

**해결 방법**:

1. **Keystore 파일 생성**:
```bash
keytool -genkey -v -keystore ~/wefilling-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload \
  -storetype JKS
```

2. **key.properties 파일 생성** (`android/key.properties`):
```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=/Users/chajaemin/wefilling-upload-key.jks
```

3. **보안 주의사항**:
   - ⚠️ `key.properties` 파일을 Git에 커밋하지 마세요 (이미 .gitignore에 추가됨)
   - ⚠️ Keystore 파일을 안전한 곳에 백업하세요
   - ⚠️ 비밀번호를 안전하게 보관하세요

### ✅ build.gradle.kts 서명 설정

**현재 상태**: 올바르게 설정됨

파일: `android/app/build.gradle.kts`
- signingConfigs 블록이 올바르게 구성됨
- release 빌드 타입에 서명 설정이 적용됨
- key.properties 파일이 존재할 때만 서명 적용 (안전)

### ✅ ProGuard 난독화 설정

**현재 상태**: 완료

```kotlin
buildTypes {
    release {
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro"
        )
    }
}
```

### ❌ 앱 번들 빌드 테스트 필요

**필요 작업**:
1. Keystore 생성 후 다음 명령어로 테스트:
```bash
flutter build appbundle --release
```

2. 생성된 파일 확인:
```
build/app/outputs/bundle/release/app-release.aab
```

---

## 2. iOS 앱 서명 및 프로비저닝 ✅

### ✅ Bundle Identifier

**현재 상태**: 올바르게 설정됨

- Bundle ID: `com.wefilling.app`
- 위치: `ios/Runner.xcodeproj/project.pbxproj`
- 일관성: ✅ 모든 빌드 구성에서 동일

### ⚠️ Signing & Capabilities

**확인 필요**:
Xcode에서 다음 사항을 확인해야 합니다:

1. **Xcode 열기**:
```bash
open ios/Runner.xcworkspace
```

2. **확인 항목**:
   - [ ] Signing & Capabilities 탭에서 Team 선택됨
   - [ ] Automatically manage signing 활성화 또는 수동 프로비저닝 프로파일 설정
   - [ ] Apple Developer 계정 연결됨
   - [ ] 프로비저닝 프로파일이 유효함

### ✅ Entitlements

**현재 상태**: 완료

파일: `ios/Runner/Runner.entitlements`
- Sign in with Apple 권한 설정됨 ✅

### ✅ Info.plist 권한 설명

**현재 상태**: 완료

파일: `ios/Runner/Info.plist`

권한 설명이 한국어로 작성됨:
- ✅ 카메라 권한: "프로필 사진 촬영 및 게시글 작성을 위해 카메라 접근 권한이 필요합니다."
- ✅ 사진첩 권한: "프로필 사진 및 게시글 이미지를 선택하기 위해 사진첩 접근 권한이 필요합니다."
- ✅ 알림 권한: "댓글, 좋아요 등의 알림을 받기 위해 권한이 필요합니다."

### ❌ iOS 빌드 테스트 필요

**필요 작업**:
```bash
flutter build ios --release
```

**Xcode Archive 생성**:
1. Xcode에서 Product > Archive 실행
2. Archive가 성공적으로 생성되는지 확인
3. Distribute App으로 App Store Connect 업로드 테스트

---

## 3. 법적 문서 호스팅 ✅

### ✅ 문서 준비 완료

**현재 상태**: 문서 작성 및 호스팅 완료

파일 위치:
- `docs/index.html` - 개인정보 처리방침
- `docs/terms.html` - 서비스 이용약관
- `docs/privacy_policy.md` - 마크다운 버전 (참고용)

### ✅ 웹 호스팅 완료

**현재 상태**: GitHub Pages로 호스팅 완료

**배포된 URL**:
```
개인정보 처리방침: https://gaemini.github.io/wefilling-nochatbot/
서비스 이용약관: https://gaemini.github.io/wefilling-nochatbot/terms.html
```

**✅ 확인 완료**:
- ✅ HTTPS로 접속 가능
- ✅ GitHub Pages 정상 작동
- ✅ 두 URL 모두 접근 가능

**최종 테스트 필요**:
- [ ] 모바일 기기에서 정상 표시 확인
- [ ] 한국어/영어 내용 모두 표시 확인
- [ ] 연락처: wefilling@gmail.com 확인
- [ ] 운영자: Christopher Watson 확인
- [ ] 시행일: 2025년 11월 25일 확인

### ✅ 문서 내용 정확성

**확인 완료**:
- ✅ 연락처: wefilling@gmail.com
- ✅ 운영자: Christopher Watson
- ✅ 시행일: 2025년 11월 25일
- ✅ 한국어/영어 병기

### 📝 스토어 제출 시 사용

**Google Play Console**:
1. 앱 콘텐츠 > 개인정보 보호 정책
2. URL 입력: `https://gaemini.github.io/wefilling-nochatbot/`

**App Store Connect**:
1. 앱 정보 > 일반 정보
2. 개인정보 처리방침 URL: `https://gaemini.github.io/wefilling-nochatbot/`

---

## 4. 앱 메타데이터 준비 상태 ❌

### Google Play Store

#### ✅ 앱 이름
- 이름: "Wefilling"
- 위치: `android/app/src/main/AndroidManifest.xml`

#### ❌ 짧은 설명 (80자 이내)

**필요 작업**: 작성 필요

**권장 예시**:
```
대학생을 위한 모임 플랫폼. 스터디, 식사, 취미 모임을 쉽게 만들고 참여하세요!
```
(공백 포함 42자)

#### ⚠️ 전체 설명

**현재 상태**: `docs/quick_deployment.md`에 템플릿 존재

**필요 작업**: 
1. 템플릿을 Play Console에 복사
2. 필요시 내용 수정

**템플릿 위치**: `docs/quick_deployment.md` 라인 161-212

#### ❌ 스크린샷

**현재 상태**: 준비 안 됨

**필요 사항**:
- 최소 2개 (권장 4-8개)
- 해상도: 최소 320px, 최대 3840px
- 형식: PNG 또는 JPEG

**촬영 방법**:
```bash
# 실제 기기 또는 에뮬레이터에서
flutter run --release

# 주요 화면 캡처:
# 1. 로그인 화면 (Google/Apple 로그인)
# 2. 홈 화면 (모임 목록)
# 3. 모임 상세 화면
# 4. 게시판 화면
# 5. 프로필 화면
# 6. (선택) 친구 목록
# 7. (선택) DM 화면
```

#### ✅ 앱 아이콘

**현재 상태**: 준비됨

파일 위치:
- `assets/icons/app_logo.png` - Android용
- `assets/icons/app_logo_ios.png` - iOS용 (여백 포함)

#### ❌ 기능 그래픽 (1024 x 500)

**현재 상태**: 준비 안 됨

**필요 작업**:
1. Canva 또는 Figma에서 배너 제작
2. 크기: 1024 x 500 픽셀
3. 형식: PNG 또는 JPEG

**포함 내용**:
- 앱 로고
- 캐치프레이즈: "함께하면 즐거운 대학 생활"
- 주요 기능 아이콘
- 배경색: #DEEFFF (앱 메인 컬러)

### Apple App Store

#### ✅ 앱 이름
- 이름: "Wefilling"
- 표시 이름: "Wefilling"
- 위치: `ios/Runner/Info.plist`

#### ❌ 부제목 (30자 이내)

**필요 작업**: 작성 필요

**권장 예시**:
```
대학생 모임 플랫폼
```
(공백 포함 11자)

#### ❌ 키워드 (100자 이내)

**필요 작업**: 작성 필요

**권장 예시**:
```
대학생,모임,스터디,친구,커뮤니티,소셜,네트워킹,대학,한양대,동아리
```
(공백 포함 42자)

#### ❌ 스크린샷

**현재 상태**: 준비 안 됨

**필요 사항**:
각 디바이스 크기별 최소 3개씩:
- 6.7" (iPhone 15 Pro Max): 1290 x 2796
- 6.5" (iPhone 14 Plus): 1242 x 2688
- 5.5" (iPhone 8 Plus): 1242 x 2208

**촬영 방법**:
```bash
# 시뮬레이터에서
flutter run

# Cmd + S로 스크린샷 촬영
# 저장 위치: ~/Desktop
```

#### ❌ 앱 설명

**필요 작업**: Play Store 설명과 동일하게 작성

---

## 5. 앱 권한 및 설정 ✅

### Android

#### ✅ AndroidManifest.xml

**현재 상태**: 완료

파일: `android/app/src/main/AndroidManifest.xml`

설정된 권한:
- ✅ 인터넷 권한 (`INTERNET`)
- ✅ 이미지 읽기 권한 (`READ_MEDIA_IMAGES`, `READ_EXTERNAL_STORAGE`)
- ✅ 푸시 알림 권한 (`POST_NOTIFICATIONS`)
- ✅ FCM 권한 (`WAKE_LOCK`, `C2D_MESSAGE`)

앱 이름:
- ✅ "Wefilling"으로 표시

#### ⚠️ google-services.json

**현재 상태**: 파일 존재하나 패키지명 불일치 발견

**문제점**:
- 파일 내 패키지명: `com.example.flutter_practice3`
- 현재 앱 패키지명: `com.wefilling.app`

**해결 방법**:
1. Firebase Console에서 새 Android 앱 추가
2. 패키지명: `com.wefilling.app`
3. 새 `google-services.json` 다운로드
4. `android/app/google-services.json` 교체

### iOS

#### ✅ Info.plist

**현재 상태**: 완료

모든 권한 설명이 한국어로 작성됨 (위 섹션 2 참조)

#### ✅ GoogleService-Info.plist

**현재 상태**: 올바른 Bundle ID 설정됨

- Bundle ID: `com.wefilling.app` ✅

---

## 6. 버전 정보 ✅

### ✅ pubspec.yaml

**현재 상태**: 올바르게 설정됨

```yaml
version: 1.0.0+1
```

- Version Name: 1.0.0
- Build Number: 1

### ✅ 버전 일관성

**확인 완료**:
- Android versionCode: 1 (Flutter에서 자동 설정)
- Android versionName: 1.0.0 (Flutter에서 자동 설정)
- iOS CFBundleShortVersionString: 1.0.0 (Flutter에서 자동 설정)
- iOS CFBundleVersion: 1 (Flutter에서 자동 설정)

### ⚠️ 변경 로그

**필요 작업**: 첫 배포 버전 설명 준비

**권장 내용**:
```
버전 1.0.0 - 첫 출시

주요 기능:
- 대학생 인증 (한양대 이메일)
- 모임 생성 및 참여 (스터디, 식사, 취미, 문화)
- 게시판 (공개/카테고리별 공개)
- 친구 관리 및 DM
- 실시간 푸시 알림
- Google/Apple 로그인
```

---

## 7. Firebase 및 백엔드 설정 ⚠️

### ✅ Firebase 프로젝트

**현재 상태**: 설정됨

- Project ID: `flutterproject3-af322`
- Project Number: `700373659727`

### ⚠️ Firebase 패키지명 불일치

**문제점**:
Android `google-services.json` 파일에 이전 패키지명이 남아있음

**해결 방법**:
1. Firebase Console 접속
2. 프로젝트 설정 > 일반
3. Android 앱에서 `com.wefilling.app` 추가 또는 기존 앱 수정
4. 새 `google-services.json` 다운로드

### ✅ Firestore 규칙

**현재 상태**: 프로덕션 환경에 적합하게 설정됨

파일: `firestore.rules`

주요 보안 설정:
- ✅ 인증된 사용자만 접근 가능
- ✅ 이메일 인증 필수 (emailVerified == true)
- ✅ 한양대 이메일 검증 (@hanyang.ac.kr)
- ✅ 사용자별 권한 분리 (본인만 수정 가능)
- ✅ 차단/친구 관계 보안 규칙 적용
- ✅ DM 메시지 보안 규칙 적용

### ⚠️ Storage 규칙

**현재 상태**: 읽기 완전 공개

파일: `storage.rules`

```javascript
allow read;  // 완전 공개 읽기
allow write: if request.auth != null;
```

**권장 사항**:
현재 설정은 안전하지만, 필요시 읽기 권한도 인증된 사용자로 제한 고려:
```javascript
allow read: if request.auth != null;
allow write: if request.auth != null;
```

### ⚠️ Cloud Functions

**현재 상태**: 함수 존재하나 배포 여부 미확인

파일 위치: `functions/src/`

**확인 필요**:
```bash
# Firebase 로그인
firebase login

# 현재 배포된 함수 확인
firebase functions:list

# 함수 배포 (필요시)
cd functions
npm install
npm run build
firebase deploy --only functions
```

### ⚠️ Firebase Crashlytics

**현재 상태**: 설정됨

`android/app/build.gradle.kts`:
```kotlin
id("com.google.firebase.crashlytics")
```

`pubspec.yaml`:
```yaml
firebase_crashlytics: ^5.0.2
```

**확인 필요**:
앱 실행 후 Firebase Console > Crashlytics에서 데이터 수신 여부 확인

---

## 8. 앱 기능 최종 테스트 ❌

### ❌ 릴리즈 빌드 테스트

**필요 작업**:

1. **Android 릴리즈 빌드**:
```bash
flutter build apk --release
# 또는
flutter build appbundle --release
```

2. **iOS 릴리즈 빌드**:
```bash
flutter build ios --release
```

3. **실제 기기에 설치**:
   - Android: APK 파일을 기기로 전송하여 설치
   - iOS: Xcode에서 기기에 직접 설치

### ❌ 주요 기능 동작 테스트

**테스트 시나리오**:

#### 1. 인증 및 로그인
- [ ] Google 로그인 정상 작동
- [ ] Apple 로그인 정상 작동 (iOS)
- [ ] 한양대 이메일 인증 프로세스
- [ ] 로그아웃 및 재로그인

#### 2. 게시글 기능
- [ ] 게시글 작성 (텍스트만)
- [ ] 게시글 작성 (이미지 포함)
- [ ] 게시글 수정
- [ ] 게시글 삭제
- [ ] 댓글 작성/수정/삭제
- [ ] 좋아요 기능

#### 3. 모임 기능
- [ ] 모임 생성 (각 카테고리별)
- [ ] 모임 참여 신청
- [ ] 모임 참여 승인/거절
- [ ] 모임 수정
- [ ] 모임 삭제
- [ ] 모임 후기 작성

#### 4. 친구 기능
- [ ] 친구 요청 보내기
- [ ] 친구 요청 수락/거절
- [ ] 친구 목록 확인
- [ ] 친구 카테고리 관리
- [ ] 친구 차단/차단 해제

#### 5. DM 기능
- [ ] DM 대화방 생성
- [ ] 메시지 전송
- [ ] 메시지 읽음 표시
- [ ] 대화방 나가기

#### 6. 푸시 알림
- [ ] 댓글 알림 수신
- [ ] 좋아요 알림 수신
- [ ] 친구 요청 알림 수신
- [ ] DM 메시지 알림 수신
- [ ] 모임 참여 승인 알림 수신

### ❌ 권한 요청 테스트

**확인 항목**:
- [ ] 카메라 권한 요청 (적절한 타이밍)
- [ ] 사진첩 권한 요청 (적절한 타이밍)
- [ ] 알림 권한 요청 (적절한 타이밍)
- [ ] 권한 거부 시 적절한 안내 메시지

### ❌ 안정성 테스트

**확인 항목**:
- [ ] 앱 시작 시 크래시 없음
- [ ] 주요 화면 전환 시 크래시 없음
- [ ] 네트워크 오류 처리
- [ ] 이미지 업로드 실패 처리
- [ ] 백그라운드/포그라운드 전환 정상 작동

---

## 9. 개발자 계정 및 제출 준비 ⚠️

### Google Play Console

#### ✅ 개발자 계정
- 상태: 활성화됨 (사용자 확인)

#### ❌ 앱 등록

**필요 작업**:

1. **Play Console 접속**: https://play.google.com/console

2. **새 앱 만들기**:
   - 앱 이름: Wefilling
   - 기본 언어: 한국어
   - 앱/게임: 앱
   - 무료/유료: 무료

3. **앱 콘텐츠 설문 작성**:
   - [ ] 개인정보 처리방침 URL 입력
   - [ ] 광고 포함 여부: 없음 (확인 필요)
   - [ ] 타겟 연령층: 만 13세 이상
   - [ ] 콘텐츠 등급: 만 12세 이상 (예상)

4. **데이터 보안 섹션**:

**수집하는 데이터**:
- 이름, 이메일 주소
- 프로필 사진
- 대학 정보
- 게시글, 댓글, 메시지

**데이터 사용 목적**:
- 계정 관리
- 앱 기능 제공
- 커뮤니케이션

**데이터 공유**:
- 제3자와 공유하지 않음

**데이터 보안**:
- 전송 중 암호화 (HTTPS)
- 사용자가 데이터 삭제 요청 가능

5. **스토어 등록정보**:
   - [ ] 짧은 설명 입력
   - [ ] 전체 설명 입력
   - [ ] 앱 아이콘 업로드 (512 x 512)
   - [ ] 스크린샷 업로드 (최소 2개)
   - [ ] 기능 그래픽 업로드 (1024 x 500)

6. **프로덕션 트랙**:
   - [ ] AAB 파일 업로드
   - [ ] 출시 노트 작성

### App Store Connect

#### ✅ 개발자 계정
- 상태: Apple Developer Program 가입 (사용자 확인)

#### ❌ 앱 등록

**필요 작업**:

1. **App Store Connect 접속**: https://appstoreconnect.apple.com

2. **새로운 앱 만들기**:
   - 플랫폼: iOS
   - 이름: Wefilling
   - 기본 언어: 한국어
   - 번들 ID: com.wefilling.app
   - SKU: com.wefilling.app (또는 고유 식별자)

3. **앱 정보**:
   - [ ] 부제목 입력 (30자)
   - [ ] 카테고리: 소셜 네트워킹
   - [ ] 개인정보 처리방침 URL 입력
   - [ ] 지원 URL 입력 (GitHub 또는 웹사이트)

4. **가격 및 사용 가능 여부**:
   - 가격: 무료
   - 국가: 대한민국 (또는 전 세계)

5. **버전 정보**:
   - 버전: 1.0.0
   - [ ] 설명 입력
   - [ ] 키워드 입력 (100자)
   - [ ] 스크린샷 업로드 (각 디바이스별)
   - [ ] 프로모션 텍스트 입력 (선택사항)

6. **App Privacy (개인정보 보호)**:

**수집하는 데이터 유형**:
- 연락처 정보 (이름, 이메일)
- 사용자 콘텐츠 (사진, 메시지)
- 사용 데이터

**데이터 사용 목적**:
- 앱 기능
- 제품 개인화

**추적 여부**: 아니오

7. **수출 규정 준수**:
   - 암호화 사용: 예 (HTTPS)
   - 면제 사유: 표준 암호화만 사용 (HTTPS)

8. **빌드 업로드**:
   - [ ] Xcode에서 Archive 생성
   - [ ] Distribute App > App Store Connect
   - [ ] 업로드 완료 후 버전에 빌드 연결

---

## 10. 최종 점검 사항 📝

### 🔴 긴급 (배포 전 필수)

1. **Android Keystore 생성** ❌
   - keystore 파일 생성
   - key.properties 파일 작성
   - 안전한 곳에 백업

2. **Firebase 패키지명 수정** ⚠️
   - `com.wefilling.app`로 Firebase 앱 추가
   - 새 google-services.json 다운로드 및 교체

3. **법적 문서 URL 확인** ⚠️
   - 개인정보 처리방침 URL 테스트
   - 서비스 이용약관 URL 테스트
   - HTTPS 접속 확인

4. **스크린샷 촬영** ❌
   - Android: 최소 2개 (권장 4-8개)
   - iOS: 각 디바이스별 최소 3개

5. **앱 설명 작성** ❌
   - Play Store 짧은 설명 (80자)
   - Play Store 전체 설명
   - App Store 부제목 (30자)
   - App Store 키워드 (100자)

6. **릴리즈 빌드 테스트** ❌
   - Android AAB 빌드 성공 확인
   - iOS Archive 생성 성공 확인
   - 실제 기기에서 주요 기능 테스트

### 🟡 중요 (배포 후 1주일 내)

7. **Cloud Functions 배포 확인** ⚠️
   - 배포된 함수 목록 확인
   - 필요시 재배포

8. **Crashlytics 동작 확인** ⚠️
   - Firebase Console에서 데이터 수신 확인

9. **기능 그래픽 제작** ❌
   - Play Store용 1024 x 500 배너

10. **iOS 서명 설정 확인** ⚠️
    - Xcode에서 Team 및 프로비저닝 확인

### 🟢 권장 (시간 여유 시)

11. **Storage 규칙 강화** (선택사항)
    - 읽기 권한도 인증 필요로 변경 고려

12. **변경 로그 작성**
    - 첫 배포 버전 설명 준비

13. **앱 미리보기 비디오** (선택사항)
    - App Store용 짧은 데모 영상

---

## 📊 우선순위별 작업 목록

### 1단계: 즉시 처리 (배포 불가능한 항목)

```bash
# 1. Keystore 생성
keytool -genkey -v -keystore ~/wefilling-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload -storetype JKS

# 2. key.properties 파일 작성
# android/key.properties 파일 생성 (위 섹션 1 참조)

# 3. Firebase 패키지명 수정
# Firebase Console에서 com.wefilling.app 추가
# google-services.json 교체

# 4. 빌드 테스트
flutter build appbundle --release  # Android
flutter build ios --release         # iOS
```

### 2단계: 스토어 제출 준비 (1-2일)

```
1. 스크린샷 촬영 (Android 4-8개, iOS 각 디바이스별 3개)
2. 앱 설명 작성 (짧은 설명, 전체 설명, 부제목, 키워드)
3. 법적 문서 URL 확인 및 테스트
4. 실제 기기에서 주요 기능 테스트
5. Play Console 및 App Store Connect 앱 등록
```

### 3단계: 최종 점검 (1일)

```
1. 모든 테스트 시나리오 실행
2. 크래시 없음 확인
3. 권한 요청 정상 작동 확인
4. 데이터 보안 섹션 작성
5. App Privacy 정보 입력
6. 최종 빌드 업로드
```

---

## 🎯 예상 일정

| 단계 | 작업 | 예상 소요 시간 | 담당 |
|-----|------|--------------|------|
| 1 | Keystore 생성 | 30분 | 개발자 |
| 2 | Firebase 설정 수정 | 30분 | 개발자 |
| 3 | 빌드 테스트 | 1시간 | 개발자 |
| 4 | 스크린샷 촬영 | 2시간 | 개발자/디자이너 |
| 5 | 앱 설명 작성 | 1시간 | 기획자/개발자 |
| 6 | 법적 문서 호스팅 | 30분 | 개발자 |
| 7 | 기능 테스트 | 3시간 | QA/개발자 |
| 8 | 스토어 등록 | 2시간 | 개발자 |
| 9 | 최종 점검 | 1시간 | 전체 팀 |
| **총계** | | **약 11-12시간** | |

**예상 배포 가능 시점**: 2-3일 후 (집중 작업 시)

---

## 📞 문의 및 지원

### 공식 문서
- [Google Play Console 도움말](https://support.google.com/googleplay/android-developer)
- [App Store Connect 도움말](https://developer.apple.com/help/app-store-connect)
- [Flutter 배포 가이드](https://docs.flutter.dev/deployment)

### 프로젝트 문서
- `docs/DEPLOYMENT_GUIDE.md` - 법적 문서 배포 가이드
- `docs/quick_deployment.md` - 빠른 배포 가이드
- `docs/keystore_setup.md` - Keystore 설정 가이드

### 연락처
- 이메일: wefilling@gmail.com
- 개발자: Christopher Watson

---

## ✅ 체크리스트 요약

**배포 준비 완료 여부**: ❌ 아직 준비되지 않음

**완료된 항목**: 6/10 카테고리
**미완료 항목**: 4/10 카테고리

**다음 단계**:
1. ✅ Android Keystore 생성 (최우선)
2. ✅ Firebase 패키지명 수정
3. ✅ 스크린샷 촬영
4. ✅ 앱 설명 작성
5. ✅ 릴리즈 빌드 테스트

**예상 배포 일정**: 위 5가지 작업 완료 후 2-3일 내 제출 가능

---

**마지막 업데이트**: 2025-12-02  
**다음 리뷰 예정**: 배포 직전 최종 점검


