# 빠른 배포 가이드 (Quick Deployment Guide)

**목표**: 30분 안에 앱스토어 제출 준비 완료하기

---

## 🚀 Step 1: 법적 문서 웹 호스팅 (10분)

### GitHub Pages로 배포하기

```bash
# 1. 현재 디렉토리 확인
cd /Users/chajaemin/Desktop/wefilling-nochatbot

# 2. Git 상태 확인
git status

# 3. 변경사항 커밋 (아직 안 했다면)
git add .
git commit -m "Add legal documents for app store submission"

# 4. GitHub에 푸시
git push origin main

# 만약 원격 저장소가 없다면:
# git remote add origin https://github.com/[사용자명]/wefilling-nochatbot.git
# git push -u origin main
```

### GitHub Pages 활성화

1. **GitHub 저장소 페이지** 접속
   - https://github.com/[사용자명]/wefilling-nochatbot

2. **Settings** 클릭 (상단 탭)

3. 왼쪽 메뉴에서 **Pages** 클릭

4. **Source** 섹션 설정:
   - Branch: `main` 선택
   - Folder: `/docs` 선택
   - **Save** 클릭

5. **5-10분 대기** 후 URL 확인:
   ```
   https://[사용자명].github.io/wefilling-nochatbot/
   ```

### URL 확인

배포 완료 후 다음 URL을 브라우저에서 테스트:

```
개인정보 처리방침:
https://[사용자명].github.io/wefilling-nochatbot/index.html

서비스 이용약관:
https://[사용자명].github.io/wefilling-nochatbot/terms.html
```

✅ **완료 기준**: 두 URL 모두 정상 접속 및 내용 표시

---

## 📸 Step 2: 스크린샷 촬영 (10분)

### Android 스크린샷

#### 방법 1: 실제 기기 사용 (권장)

```bash
# 1. 앱 실행
flutter run --release

# 2. 주요 화면 캡처 (최소 4개)
# - 로그인 화면
# - 홈 화면 (모임 목록)
# - 모임 상세 화면
# - 프로필 화면

# 3. 갤러리에서 스크린샷 확인
# 4. PC로 전송 (USB, 클라우드 등)
```

#### 방법 2: 에뮬레이터 사용

```bash
# 1. 에뮬레이터 실행 (Android Studio)
# Pixel 6 Pro (1440 x 3120) 권장

# 2. 앱 실행
flutter run

# 3. 에뮬레이터 우측 메뉴에서 카메라 아이콘 클릭
# 또는 Cmd/Ctrl + S

# 4. 저장 위치: ~/Desktop
```

**필요한 스크린샷**:
1. 로그인 화면 (Google/Apple 로그인 버튼 표시)
2. 홈 화면 (모임 목록)
3. 모임 상세 화면
4. 게시판 화면
5. 프로필 화면
6. (선택) 친구 목록
7. (선택) DM 화면

### iOS 스크린샷

#### 방법 1: 실제 기기 사용 (권장)

```bash
# 1. 앱 실행
flutter run --release

# 2. 스크린샷 촬영
# iPhone 15 Pro Max: 볼륨 업 + 사이드 버튼
# iPhone 8 이하: 홈 버튼 + 전원 버튼

# 3. 사진 앱에서 확인
# 4. AirDrop 또는 iCloud로 Mac에 전송
```

#### 방법 2: 시뮬레이터 사용

```bash
# 1. 시뮬레이터 실행 (Xcode)
# iPhone 15 Pro Max 권장

# 2. 앱 실행
flutter run

# 3. 스크린샷 촬영
# Cmd + S

# 4. 저장 위치: ~/Desktop
```

**필요한 디바이스별 스크린샷**:
- **6.7" (iPhone 15 Pro Max)**: 3-10개
- **6.5" (iPhone 14 Plus)**: 3-10개
- **5.5" (iPhone 8 Plus)**: 3-10개

✅ **완료 기준**: 각 플랫폼별 최소 4개 스크린샷 확보

---

## 📝 Step 3: 앱 설명 작성 (10분)

### Google Play Store

#### 짧은 설명 (80자 이내)

```
대학생을 위한 모임 플랫폼. 스터디, 식사, 취미 모임을 쉽게 만들고 참여하세요!
```

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
```

### Apple App Store

#### 부제목 (30자 이내)

```
대학생 모임 플랫폼
```

#### 설명 (Play Store와 동일하게 작성)

#### 키워드 (100자 이내, 쉼표로 구분)

```
대학생,모임,스터디,친구,커뮤니티,소셜,네트워킹,대학,한양대,동아리
```

#### 프로모션 텍스트 (170자 이내, 선택사항)

```
🎉 새로운 모임 기능 추가!
이제 더 쉽게 모임을 만들고 참여할 수 있습니다.
대학 생활을 더욱 즐겁게 만들어보세요!
```

✅ **완료 기준**: Play Store 및 App Store 설명 문서 준비 완료

---

## 🎨 Step 4: 기능 그래픽 제작 (선택사항)

### Play Store 기능 그래픽 (1024 x 500)

**온라인 도구 사용**:
- [Canva](https://www.canva.com) - 무료 템플릿 제공
- [Figma](https://www.figma.com) - 디자인 도구

**포함할 내용**:
- 앱 로고
- 주요 기능 아이콘
- 캐치프레이즈: "함께하면 즐거운 대학 생활"
- 스크린샷 미리보기

**디자인 가이드**:
- 배경색: #DEEFFF (앱 메인 컬러)
- 텍스트: 굵고 읽기 쉽게
- 이미지: 고해상도

✅ **완료 기준**: 1024 x 500 PNG 파일 준비

---

## 📤 Step 5: 스토어 제출

### Google Play Console

1. **Play Console 접속**: https://play.google.com/console

2. **앱 만들기** (처음인 경우)
   - 앱 이름: Wefilling
   - 기본 언어: 한국어
   - 앱/게임: 앱
   - 무료/유료: 무료

3. **앱 콘텐츠 작성**
   - 개인정보 처리방침 URL 입력
   - 광고 포함 여부 선택
   - 콘텐츠 등급 설정 (만 12세 이상)
   - 타겟 고객층 선택

4. **스토어 등록정보**
   - 앱 이름: Wefilling
   - 짧은 설명 입력
   - 전체 설명 입력
   - 앱 아이콘 업로드
   - 스크린샷 업로드 (최소 2개)
   - 기능 그래픽 업로드

5. **프로덕션 트랙**
   - AAB 파일 업로드
   ```bash
   flutter build appbundle --release
   # 파일 위치: build/app/outputs/bundle/release/app-release.aab
   ```

6. **검토 제출**

### App Store Connect

1. **App Store Connect 접속**: https://appstoreconnect.apple.com

2. **새로운 앱 만들기**
   - 플랫폼: iOS
   - 이름: Wefilling
   - 기본 언어: 한국어
   - 번들 ID: com.wefilling.app
   - SKU: com.wefilling.app

3. **앱 정보**
   - 부제목 입력
   - 카테고리: 소셜 네트워킹
   - 개인정보 처리방침 URL 입력
   - 지원 URL 입력

4. **가격 및 사용 가능 여부**
   - 가격: 무료
   - 국가: 대한민국 (또는 전 세계)

5. **버전 정보**
   - 버전: 1.0.0
   - 설명 입력
   - 키워드 입력
   - 스크린샷 업로드 (각 디바이스별)

6. **빌드 업로드**
   ```bash
   # Xcode에서 Archive 생성
   flutter build ios --release
   
   # Xcode 열기
   open ios/Runner.xcworkspace
   
   # Product > Archive
   # Distribute App > App Store Connect
   ```

7. **App Privacy (개인정보 보호)**
   - 수집하는 데이터 유형 선택
   - 데이터 사용 목적 선택
   - 추적 여부: 아니오

8. **검토 제출**

✅ **완료 기준**: 양쪽 스토어에 앱 제출 완료

---

## ✅ 최종 체크리스트

배포 전 다음 항목을 모두 확인하세요:

### 법적 문서
- [ ] 개인정보 처리방침 URL 작동 확인
- [ ] 서비스 이용약관 URL 작동 확인
- [ ] HTTPS 접속 가능 확인
- [ ] 모바일에서 정상 표시 확인

### 스크린샷
- [ ] Android 스크린샷 4-8개 준비
- [ ] iOS 스크린샷 각 디바이스별 3개 이상 준비
- [ ] 고해상도 이미지 확인
- [ ] 실제 앱 화면 캡처 확인

### 앱 설명
- [ ] Play Store 짧은 설명 작성 (80자)
- [ ] Play Store 전체 설명 작성
- [ ] App Store 부제목 작성 (30자)
- [ ] App Store 설명 작성
- [ ] App Store 키워드 작성 (100자)

### 빌드 파일
- [ ] Android AAB 파일 생성 확인
- [ ] iOS Archive 생성 확인
- [ ] 릴리즈 모드 빌드 확인
- [ ] 서명 확인 (Android keystore, iOS certificate)

### 스토어 설정
- [ ] Play Console 계정 생성
- [ ] App Store Connect 계정 생성
- [ ] 개발자 계정 활성화 확인
- [ ] 결제 정보 등록 (필요 시)

### 테스트
- [ ] 실제 기기에서 릴리즈 빌드 테스트
- [ ] 주요 기능 동작 확인
- [ ] 크래시 없음 확인
- [ ] 권한 요청 정상 작동 확인

---

## 🎉 완료!

모든 단계를 완료하셨다면 이제 앱 스토어 리뷰를 기다리시면 됩니다.

### 예상 리뷰 기간
- **Google Play Store**: 1-7일 (평균 1-2일)
- **Apple App Store**: 1-3일 (평균 24시간)

### 리뷰 중 연락이 올 수 있는 경우
- 추가 정보 요청
- 스크린샷 교체 요청
- 개인정보 처리방침 수정 요청
- 기능 설명 추가 요청

### 승인 후 할 일
- [ ] 앱 스토어 링크 확인
- [ ] 지인들에게 공유
- [ ] 소셜 미디어 홍보
- [ ] 사용자 피드백 모니터링
- [ ] 버그 리포트 대응

---

## 📞 도움이 필요하신가요?

### 참고 문서
- [APP_STORE_COMPLIANCE_CHECKLIST.md](APP_STORE_COMPLIANCE_CHECKLIST.md) - 상세 체크리스트
- [DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) - 법적 문서 배포 가이드
- [KEYSTORE_SETUP_GUIDE.md](KEYSTORE_SETUP_GUIDE.md) - Android 앱 서명

### 공식 문서
- [Google Play Console 도움말](https://support.google.com/googleplay/android-developer)
- [App Store Connect 도움말](https://developer.apple.com/help/app-store-connect)
- [Flutter 배포 가이드](https://docs.flutter.dev/deployment)

### 문의
- **이메일**: wefilling@gmail.com
- **개발자**: Christopher Watson

---

**작성일**: 2025-11-26  
**예상 소요 시간**: 30-60분  
**난이도**: 중급


