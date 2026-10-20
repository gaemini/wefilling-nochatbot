# 🚀 Wefilling 앱 배포 실전 가이드

**작성일**: 2025-12-02  
**앱 버전**: 1.0.0+1  
**배포 대상**: Google Play Store, Apple App Store

---

## 📋 배포 전 최종 체크

### ✅ 준비 완료 항목
- ✅ 법적 문서 URL: https://gaemini.github.io/wefilling-nochatbot/
- ✅ 권한 설정 (Android/iOS)
- ✅ 앱 버전: 1.0.0+1
- ✅ Firebase 설정
- ✅ ProGuard 난독화

### ⚠️ 즉시 처리 필요
1. Android Keystore 생성
2. Firebase 패키지명 수정
3. 스크린샷 촬영
4. 앱 설명 작성
5. 릴리즈 빌드 테스트

---

## 1️⃣ Android Keystore 생성 (15분)

### Step 1: Keystore 파일 생성

```bash
# 터미널에서 실행
keytool -genkey -v -keystore ~/wefilling-upload-key.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload \
  -storetype JKS
```

**입력 정보**:
```
키 저장소 비밀번호 입력: [안전한 비밀번호 입력]
새 비밀번호 다시 입력: [동일한 비밀번호 입력]
이름과 성을 입력하십시오: Christopher Watson
조직 단위 이름을 입력하십시오: Development
조직 이름을 입력하십시오: Wefilling
구/군/시 이름을 입력하십시오: Seoul
시/도 이름을 입력하십시오: Seoul
이 조직의 두 자리 국가 코드를 입력하십시오: KR
```

### Step 2: key.properties 파일 생성

```bash
# android/key.properties 파일 생성
cat > android/key.properties << 'EOF'
storePassword=YOUR_ACTUAL_PASSWORD
keyPassword=YOUR_ACTUAL_PASSWORD
keyAlias=upload
storeFile=/Users/chajaemin/wefilling-upload-key.jks
EOF
```

**⚠️ 중요**: `YOUR_ACTUAL_PASSWORD`를 실제 비밀번호로 교체하세요!

### Step 3: 백업

```bash
# Keystore 파일 백업 (안전한 곳에 복사)
cp ~/wefilling-upload-key.jks ~/Desktop/wefilling-upload-key-BACKUP.jks

# 비밀번호를 별도 파일에 저장 (안전한 곳에 보관)
echo "Keystore Password: [비밀번호]" > ~/Desktop/wefilling-keystore-password.txt
```

---

## 2️⃣ Firebase 패키지명 수정 (10분)

### 현재 문제
`android/app/google-services.json` 파일이 이전 패키지명(`com.example.flutter_practice3`)을 사용 중

### 해결 방법

1. **Firebase Console 접속**
   - https://console.firebase.google.com/
   - 프로젝트: `flutterproject3-af322` 선택

2. **Android 앱 추가 또는 수정**
   - 프로젝트 설정 (톱니바퀴 아이콘) > 일반
   - "앱 추가" 클릭
   - Android 선택
   - 패키지명: `com.wefilling.app` 입력
   - 앱 닉네임: `Wefilling` (선택사항)
   - "앱 등록" 클릭

3. **google-services.json 다운로드**
   - 새로 생성된 앱의 `google-services.json` 다운로드
   - 기존 파일 백업:
   ```bash
   mv android/app/google-services.json android/app/google-services.json.old
   ```
   - 새 파일을 `android/app/google-services.json`에 복사

4. **SHA-1 인증서 지문 추가 (중요!)**
   ```bash
   # Debug SHA-1 확인
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
   
   # Release SHA-1 확인
   keytool -list -v -keystore ~/wefilling-upload-key.jks -alias upload
   ```
   
   - Firebase Console에서 두 SHA-1 지문 모두 추가
   - 프로젝트 설정 > 일반 > Android 앱 > SHA 인증서 지문 추가

---

## 3️⃣ 스크린샷 촬영 (30분)

### Android 스크린샷 (최소 2개, 권장 4-8개)

**필수 화면**:
1. 로그인 화면 (Google/Apple 로그인 버튼)
2. 홈 화면 (모임 목록)
3. 모임 상세 화면
4. 게시판 화면

**권장 추가 화면**:
5. 프로필 화면
6. 친구 목록
7. DM 화면

**촬영 방법**:
```bash
# 1. 에뮬레이터 실행 (Pixel 6 Pro 권장)
# Android Studio > Device Manager > Pixel 6 Pro

# 2. 앱 실행
flutter run

# 3. 각 화면에서 스크린샷 촬영
# 에뮬레이터 우측 메뉴 > 카메라 아이콘 클릭
# 또는 Cmd/Ctrl + S

# 4. 스크린샷 저장 위치 확인
# ~/Desktop 또는 에뮬레이터 설정에서 확인
```

**요구사항**:
- 해상도: 최소 320px, 최대 3840px
- 형식: PNG 또는 JPEG
- 파일명: `android_screenshot_1.png`, `android_screenshot_2.png`, ...

### iOS 스크린샷 (각 디바이스별 최소 3개)

**필요한 디바이스 크기**:
- 6.7" (iPhone 15 Pro Max): 1290 x 2796
- 6.5" (iPhone 14 Plus): 1242 x 2688
- 5.5" (iPhone 8 Plus): 1242 x 2208

**촬영 방법**:
```bash
# 1. 시뮬레이터 실행
# Xcode > Open Developer Tool > Simulator
# 각 디바이스 선택

# 2. 앱 실행
flutter run

# 3. 스크린샷 촬영
# Cmd + S

# 4. 저장 위치: ~/Desktop
```

**파일명 규칙**:
- `ios_6.7_screenshot_1.png`
- `ios_6.5_screenshot_1.png`
- `ios_5.5_screenshot_1.png`

---

## 4️⃣ 앱 설명 작성 (20분)

### Google Play Store

#### 짧은 설명 (80자 이내)
```
대학생을 위한 모임 플랫폼. 스터디, 식사, 취미 모임을 쉽게 만들고 참여하세요!
```
(42자)

#### 전체 설명
```markdown
🎓 위필링 - 함께하면 즐거운 대학 생활

대학생을 위한 모임 및 커뮤니티 플랫폼입니다.
스터디, 식사, 취미, 문화 활동 등 다양한 모임을 만들고 참여할 수 있습니다.

✨ 주요 기능

📅 모임 관리
• 스터디, 식사, 취미, 문화 등 다양한 카테고리
• 모임 생성 및 참여 신청
• 실시간 참여자 관리
• 모임 후기 작성

💬 커뮤니티
• 자유 게시판
• 댓글 및 좋아요
• 이미지 업로드
• 공개/비공개 설정

👥 친구 관리
• 친구 요청 및 수락
• 카테고리별 친구 분류
• 프로필 확인
• DM (다이렉트 메시지)

🔔 실시간 알림
• 모임 참여 승인
• 댓글 및 좋아요
• 친구 요청
• DM 메시지

🔒 안전한 서비스
• 대학 이메일 인증
• 개인정보 보호
• 차단 기능
• 신고 시스템

📱 편리한 사용
• 직관적인 UI/UX
• 빠른 로딩 속도
• 한국어/영어 지원
• Google/Apple 로그인

🎯 이런 분들께 추천합니다
• 새로운 친구를 만나고 싶은 대학생
• 스터디 그룹을 찾는 학생
• 같은 취미를 가진 친구를 찾는 분
• 대학 생활을 더 즐겁게 보내고 싶은 분

📧 문의: wefilling@gmail.com
🔒 개인정보 처리방침: https://gaemini.github.io/wefilling-nochatbot/
```

### Apple App Store

#### 부제목 (30자 이내)
```
대학생 모임 플랫폼
```
(11자)

#### 키워드 (100자 이내, 쉼표로 구분)
```
대학생,모임,스터디,친구,커뮤니티,소셜,네트워킹,대학,한양대,동아리
```
(42자)

#### 설명
Play Store 전체 설명과 동일

#### 프로모션 텍스트 (170자 이내, 선택사항)
```
🎉 새로운 모임 기능 추가!
이제 더 쉽게 모임을 만들고 참여할 수 있습니다.
대학 생활을 더욱 즐겁게 만들어보세요!
```

---

## 5️⃣ 릴리즈 빌드 테스트 (30분)

### Android 빌드

```bash
# 1. 클린 빌드
flutter clean
flutter pub get

# 2. AAB 빌드 (Play Store 업로드용)
flutter build appbundle --release

# 3. 빌드 성공 확인
ls -lh build/app/outputs/bundle/release/app-release.aab

# 4. APK 빌드 (테스트용)
flutter build apk --release

# 5. APK 파일 확인
ls -lh build/app/outputs/flutter-apk/app-release.apk
```

**예상 결과**:
```
app-release.aab: 약 40-50MB
app-release.apk: 약 40-50MB
```

### iOS 빌드

```bash
# 1. 클린 빌드
flutter clean
flutter pub get

# 2. iOS 빌드
flutter build ios --release

# 3. Xcode에서 Archive 생성
open ios/Runner.xcworkspace
```

**Xcode에서**:
1. Product > Scheme > Runner 선택
2. Product > Destination > Any iOS Device 선택
3. Product > Archive
4. Archive 성공 확인

---

## 6️⃣ 실제 기기 테스트 (1시간)

### Android 테스트

```bash
# 1. 실제 기기 연결 (USB 디버깅 활성화)
adb devices

# 2. APK 설치
adb install build/app/outputs/flutter-apk/app-release.apk

# 3. 앱 실행 및 테스트
```

### iOS 테스트

Xcode에서:
1. 실제 기기 연결
2. Product > Destination > [내 기기] 선택
3. Product > Run
4. 앱 실행 및 테스트

### 테스트 체크리스트

#### 필수 기능 테스트
- [ ] Google 로그인 정상 작동
- [ ] Apple 로그인 정상 작동 (iOS)
- [ ] 한양대 이메일 인증
- [ ] 게시글 작성 (텍스트)
- [ ] 게시글 작성 (이미지 포함)
- [ ] 모임 생성
- [ ] 모임 참여
- [ ] 친구 요청
- [ ] DM 전송
- [ ] 푸시 알림 수신

#### 권한 테스트
- [ ] 카메라 권한 요청 (적절한 타이밍)
- [ ] 사진첩 권한 요청 (적절한 타이밍)
- [ ] 알림 권한 요청 (적절한 타이밍)
- [ ] 권한 거부 시 적절한 안내

#### 안정성 테스트
- [ ] 앱 시작 시 크래시 없음
- [ ] 화면 전환 시 크래시 없음
- [ ] 백그라운드/포그라운드 전환 정상
- [ ] 네트워크 오류 처리 확인

---

## 7️⃣ Google Play Store 제출 (1시간)

### Step 1: Play Console 접속

https://play.google.com/console

### Step 2: 새 앱 만들기

1. "앱 만들기" 클릭
2. 앱 세부정보:
   - 앱 이름: `Wefilling`
   - 기본 언어: `한국어(대한민국)`
   - 앱 또는 게임: `앱`
   - 무료 또는 유료: `무료`
3. 선언 체크박스 모두 선택
4. "앱 만들기" 클릭

### Step 3: 앱 콘텐츠 작성

#### 개인정보 처리방침
- URL: `https://gaemini.github.io/wefilling-nochatbot/`

#### 광고
- 앱에 광고 포함: `아니요`

#### 앱 액세스 권한
- 모든 기능 액세스 가능: `예`

#### 콘텐츠 등급
- 설문조사 시작
- 카테고리: `소셜 네트워킹`
- 모든 질문에 적절히 답변
- 예상 등급: `18+`

#### 타겟 고객 및 콘텐츠
- 타겟 연령: `18+`
- 아동 대상 여부: `아니요`

#### 데이터 보안

**수집하는 데이터**:
- 위치: 아니요
- 개인 정보:
  - 이름: 예 (필수)
  - 이메일 주소: 예 (필수)
- 금융 정보: 아니요
- 사진 및 동영상:
  - 사진: 예 (선택사항)
- 파일 및 문서: 아니요
- 메시지:
  - 이메일: 아니요
  - SMS 또는 MMS: 아니요
  - 기타 인앱 메시지: 예 (필수)

**데이터 사용 목적**:
- 앱 기능
- 계정 관리

**데이터 처리**:
- 전송 중 암호화: 예
- 사용자가 데이터 삭제 요청 가능: 예

### Step 4: 스토어 등록정보

#### 기본 정보
- 앱 이름: `Wefilling`
- 짧은 설명: (위 4번 섹션 참조)
- 전체 설명: (위 4번 섹션 참조)

#### 그래픽
- 앱 아이콘: `assets/icons/app_logo.png` (512 x 512)
- 기능 그래픽: 1024 x 500 이미지 업로드 (필요시 Canva에서 제작)
- 스크린샷: 최소 2개 업로드

#### 분류
- 앱 카테고리: `소셜`
- 태그: `소셜 네트워킹`, `커뮤니티`

#### 연락처 세부정보
- 이메일: `wefilling@gmail.com`
- 웹사이트: `https://gaemini.github.io/wefilling-nochatbot/` (선택사항)

### Step 5: 프로덕션 트랙

1. "프로덕션" 탭 클릭
2. "새 버전 만들기" 클릭
3. AAB 업로드:
   ```bash
   # 파일 위치
   build/app/outputs/bundle/release/app-release.aab
   ```
4. 버전 이름: `1.0.0 (1)`
5. 출시 노트 작성:
   ```
   첫 출시 버전입니다.
   
   주요 기능:
   - 대학생 인증 (한양대 이메일)
   - 모임 생성 및 참여
   - 게시판 및 댓글
   - 친구 관리 및 DM
   - 실시간 푸시 알림
   ```

6. "검토" 클릭
7. 모든 항목 확인 후 "프로덕션으로 출시 시작" 클릭

---

## 8️⃣ Apple App Store 제출 (1.5시간)

### Step 1: App Store Connect 접속

https://appstoreconnect.apple.com

### Step 2: 새로운 앱 만들기

1. "나의 앱" > "+" 버튼 클릭
2. "새로운 앱" 선택
3. 앱 정보:
   - 플랫폼: `iOS`
   - 이름: `Wefilling`
   - 기본 언어: `한국어`
   - 번들 ID: `com.wefilling.app`
   - SKU: `com.wefilling.app.2025`
   - 사용자 액세스: `전체 액세스`

### Step 3: 앱 정보

1. 일반 정보:
   - 부제목: `대학생 모임 플랫폼`
   - 카테고리:
     - 기본: `소셜 네트워킹`
     - 보조: `라이프스타일` (선택사항)
   - 콘텐츠 권한: 만 12세 이상

2. 개인정보 보호:
   - 개인정보 처리방침 URL: `https://gaemini.github.io/wefilling-nochatbot/`

### Step 4: 가격 및 사용 가능 여부

- 가격: `무료`
- 사용 가능 국가: `대한민국` (또는 전 세계)

### Step 5: 버전 정보 (1.0.0)

#### 스크린샷
- 6.7" 디스플레이: 최소 3개 업로드
- 6.5" 디스플레이: 최소 3개 업로드
- 5.5" 디스플레이: 최소 3개 업로드

#### 설명
- 프로모션 텍스트: (위 4번 섹션 참조)
- 설명: (위 4번 섹션 참조)
- 키워드: `대학생,모임,스터디,친구,커뮤니티,소셜,네트워킹,대학,한양대,동아리`
- 지원 URL: `https://gaemini.github.io/wefilling-nochatbot/`
- 마케팅 URL: (선택사항)

#### 빌드
1. Xcode에서 Archive 업로드:
   - Xcode > Window > Organizer
   - Archives 탭에서 최신 Archive 선택
   - "Distribute App" 클릭
   - "App Store Connect" 선택
   - "Upload" 선택
   - 자동 서명 선택
   - "Upload" 클릭

2. App Store Connect에서 빌드 선택:
   - 빌드 섹션에서 "+" 클릭
   - 업로드된 빌드 선택 (5-10분 후 나타남)

### Step 6: App Privacy

#### 데이터 수집
- 연락처 정보:
  - 이름: 예
  - 이메일 주소: 예
- 사용자 콘텐츠:
  - 사진 또는 동영상: 예
  - 기타 사용자 콘텐츠: 예 (게시글, 댓글)

#### 데이터 사용
- 앱 기능
- 제품 개인화

#### 추적
- 앱이 사용자를 추적합니까? `아니요`

### Step 7: 수출 규정 준수

- 암호화 사용: `예`
- 암호화 유형: `HTTPS만 사용` (면제 대상)

### Step 8: 제출

1. 모든 섹션 완료 확인 (노란색 점 없음)
2. "심사에 제출" 클릭
3. 확인 후 "제출" 클릭

---

## 9️⃣ 제출 후 체크리스트

### 즉시 확인
- [ ] Play Console에서 "심사 중" 상태 확인
- [ ] App Store Connect에서 "심사 대기 중" 상태 확인
- [ ] 제출 확인 이메일 수신

### 24시간 내
- [ ] Firebase Crashlytics 데이터 수신 확인
- [ ] 테스트 사용자에게 앱 공유 (TestFlight/내부 테스트)

### 심사 기간 중
- [ ] 이메일 정기 확인 (추가 정보 요청 가능)
- [ ] Play Console/App Store Connect 상태 확인

### 예상 심사 기간
- **Google Play**: 1-7일 (평균 1-2일)
- **Apple App Store**: 1-3일 (평균 24시간)

---

## 🔟 승인 후 작업

### 앱 출시 확인
```bash
# Play Store 링크 (승인 후 생성)
https://play.google.com/store/apps/details?id=com.wefilling.app

# App Store 링크 (승인 후 생성)
https://apps.apple.com/kr/app/wefilling/[앱ID]
```

### 홍보 준비
- [ ] 앱 스토어 링크 저장
- [ ] 소셜 미디어 공지 준비
- [ ] 지인들에게 공유
- [ ] 사용자 피드백 모니터링 시작

### 모니터링
- [ ] Firebase Crashlytics 확인
- [ ] 사용자 리뷰 확인
- [ ] 평점 모니터링
- [ ] 버그 리포트 대응

---

## 📞 문제 해결

### 빌드 실패
```bash
# 캐시 정리
flutter clean
cd android && ./gradlew clean && cd ..
flutter pub get

# 다시 빌드
flutter build appbundle --release
```

### Keystore 오류
```bash
# key.properties 경로 확인
cat android/key.properties

# Keystore 파일 존재 확인
ls -la ~/wefilling-upload-key.jks
```

### Firebase 오류
```bash
# google-services.json 패키지명 확인
grep "package_name" android/app/google-services.json

# 올바른 패키지명: "com.wefilling.app"
```

### iOS 서명 오류
- Xcode > Signing & Capabilities 확인
- Team 선택 확인
- 프로비저닝 프로파일 갱신

---

## 📚 참고 문서

- [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md) - 상세 체크리스트
- [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md) - 빠른 요약
- [docs/quick_deployment.md](docs/quick_deployment.md) - 배포 가이드
- [docs/keystore_setup.md](docs/keystore_setup.md) - Keystore 설정

---

## ✅ 최종 점검

배포 전 이 체크리스트를 다시 한번 확인하세요:

- [ ] Android Keystore 생성 완료
- [ ] Firebase 패키지명 `com.wefilling.app`로 수정
- [ ] 스크린샷 촬영 완료 (Android 2개 이상, iOS 각 디바이스별 3개)
- [ ] 앱 설명 작성 완료
- [ ] 릴리즈 빌드 성공 (AAB, IPA)
- [ ] 실제 기기 테스트 완료
- [ ] 법적 문서 URL 확인: https://gaemini.github.io/wefilling-nochatbot/
- [ ] 개발자 계정 활성화 (Play Console, App Store Connect)
- [ ] 모든 필수 정보 입력 완료

**모든 항목 완료 시 제출 가능!** 🎉

---

**작성자**: AI Assistant  
**마지막 업데이트**: 2025-12-02  
**문의**: wefilling@gmail.com










