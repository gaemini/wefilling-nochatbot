# iOS 앱스토어 배포 체크리스트

## ✅ 완료된 작업 (자동화됨)

### 1. Apple Sign In 구현 ✅
- **AuthService**: `signInWithApple()` 메소드 완전 구현
- **로그인 UI**: Apple Sign In 버튼 추가 및 처리 로직 완료
- **Entitlements**: `ios/Runner/Runner.entitlements` 파일 설정 완료
- **다국어 지원**: 한국어/영어 버튼 텍스트 지원

### 2. 권한 설명 영어화 ✅
- **Info.plist 업데이트**: 모든 권한 설명을 영어로 변경
  - 알림 권한: "This app needs notification permission to send alerts for comments, likes, and other activities."
  - 사진첩 권한: "This app needs photo library access to select profile pictures and post images."
  - 카메라 권한: "This app needs camera access to take profile pictures and photos for posts."

### 3. 앱 메타데이터 준비 ✅
- **파일 생성**: `ios_app_store_metadata.md`
- **앱 설명**: 영어 짧은 설명 및 상세 설명 작성
- **키워드**: App Store 검색 최적화 키워드 선정
- **카테고리**: Social Networking (주), Education (부)

### 4. 개인정보 처리방침 ✅
- **iOS 전용 정책**: `docs/privacy-policy-ios.html` 생성
- **Apple 정책 준수**: Apple Sign In, 데이터 수집 명시
- **GDPR 준수**: EU 사용자를 위한 법적 근거 명시

### 5. iOS 빌드 테스트 ✅
- **Release 빌드**: 성공적으로 완료 (83.6MB)
- **코드사인 준비**: `--no-codesign` 옵션으로 빌드 확인
- **의존성 확인**: 모든 iOS 패키지 정상 작동

---

## 🔧 수동으로 해야 할 작업들

### 1. Apple Developer 계정 설정 (필수)
```
1. Apple Developer Program 가입 ($99/년)
2. App ID 생성: com.wefilling.app
3. Sign in with Apple 기능 활성화
4. Provisioning Profile 생성
5. Distribution Certificate 생성
```

### 2. Xcode 프로젝트 설정
```
1. Xcode에서 프로젝트 열기
2. Bundle Identifier를 com.wefilling.app으로 고정 설정
3. Team 설정 (Apple Developer 계정)
4. Signing & Capabilities 확인
   - Sign in with Apple 추가
   - Push Notifications 추가
5. Deployment Target: iOS 15.0 확인
```

### 3. 앱 아이콘 및 스크린샷 제작
```
필수 제작 항목:
📱 앱 아이콘: 1024x1024 PNG
📱 iPhone 스크린샷:
   - 6.7" (1290x2796): 최소 3장
   - 6.5" (1242x2688): 최소 3장  
   - 5.5" (1242x2208): 최소 3장

권장 스크린샷:
1. 로그인 화면 (Apple/Google Sign In 표시)
2. 메인 게시판
3. 게시글 작성 화면
4. 모임 목록
5. 모임 상세 화면
6. 친구 목록
7. 프로필 화면
8. 알림 화면
```

### 4. App Store Connect 설정
```
1. 새 앱 생성
   - 앱 이름: Wefilling
   - Bundle ID: com.wefilling.app
   - SKU: com.wefilling.app

2. 앱 정보 입력
   - 카테고리: Social Networking
   - 연령 등급: 17+
   - 개인정보 처리방침 URL: [GitHub Pages URL]

3. 스토어 정보 입력
   - 앱 설명 (ios_app_store_metadata.md 참조)
   - 키워드
   - 스크린샷 업로드
   - 앱 아이콘 업로드

4. 개인정보 보호 설문
   - 데이터 수집 항목 명시
   - 제3자 공유: 아니요
   - 데이터 사용 목적 설명
```

### 5. Archive 및 업로드
```
1. Xcode에서 Archive 생성
   - Product → Archive
   - Release 구성으로 빌드

2. App Store Connect에 업로드
   - Organizer에서 Distribute App
   - App Store Connect 선택
   - 자동 서명 사용

3. TestFlight 베타 테스트
   - 내부 테스터 추가: wefilling@gmail.com
   - 베타 테스트 진행
```

### 6. 최종 검토 및 제출
```
1. App Store Review Guidelines 확인
2. 테스트 계정 정보 제공
   - 이메일: wefilling@gmail.com
   - 비밀번호: wefilling1234@
3. 검토 노트 작성 (영어)
4. 앱 제출 및 검토 대기
```

---

## 📋 중요 파일 위치

### 생성된 문서들
- **iOS 메타데이터**: `ios_app_store_metadata.md`
- **iOS 개인정보 정책**: `docs/privacy-policy-ios.html`
- **배포 체크리스트**: `ios_deployment_checklist.md` (이 파일)

### 수정된 설정 파일들
- **권한 설명**: `ios/Runner/Info.plist` (영어로 변경됨)
- **Apple Sign In**: `ios/Runner/Runner.entitlements` (이미 설정됨)

### 기존 구현 파일들
- **Apple 로그인**: `lib/services/auth_service.dart`
- **로그인 UI**: `lib/screens/login_screen.dart`
- **다국어 지원**: `lib/l10n/app_*.arb`

---

## ⚠️ 주의사항

### 1. Apple 정책 준수
- Google Sign In과 Apple Sign In 모두 제공 (완료)
- 권한 설명 영어 필수 (완료)
- 개인정보 처리방침 URL 필수 (준비됨)

### 2. 테스트 계정
- **이메일**: wefilling@gmail.com
- **비밀번호**: wefilling1234@
- 모든 기능 테스트 가능한 계정

### 3. 빌드 설정
- **최소 iOS 버전**: 15.0
- **Bundle ID**: com.wefilling.app (고정 필요)
- **앱 크기**: 83.6MB (적정 수준)

---

## 🚀 다음 단계

1. **Apple Developer 계정 준비** (1일)
2. **앱 아이콘 및 스크린샷 제작** (1-2일)
3. **Xcode 프로젝트 설정** (1일)
4. **App Store Connect 설정** (1일)
5. **Archive 및 업로드** (1일)
6. **TestFlight 테스트** (2-3일)
7. **App Store 제출** (1일)
8. **Apple 검토 대기** (1-7일)

**예상 총 소요시간**: 1-2주

---

**작성일**: 2025-11-12  
**상태**: iOS 배포 준비 완료 ✅



