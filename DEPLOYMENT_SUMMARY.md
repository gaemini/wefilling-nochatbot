# 배포 준비 상태 요약

**검토일**: 2025-12-02  
**앱 버전**: 1.0.0+1  
**전체 준비율**: 약 72%

**법적 문서 URL**:
- 개인정보 처리방침: https://gaemini.github.io/wefilling-nochatbot/
- 서비스 이용약관: https://gaemini.github.io/wefilling-nochatbot/terms.html

---

## 🚨 즉시 처리 필요 (배포 차단 항목)

### 1. Android Keystore 생성 ❌ **최우선**

현재 keystore 파일이 없어 릴리즈 빌드를 생성할 수 없습니다.

**해결 방법**:
```bash
# 1. Keystore 생성
keytool -genkey -v -keystore ~/wefilling-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload -storetype JKS

# 2. android/key.properties 파일 생성
# 내용:
# storePassword=YOUR_PASSWORD
# keyPassword=YOUR_PASSWORD
# keyAlias=upload
# storeFile=/Users/chajaemin/wefilling-upload-key.jks
```

⚠️ **주의**: 생성된 파일과 비밀번호를 안전하게 백업하세요!

### 2. Firebase 패키지명 불일치 ⚠️ **긴급**

`google-services.json` 파일의 패키지명이 이전 이름(`com.example.flutter_practice3`)으로 되어 있습니다.

**해결 방법**:
1. Firebase Console 접속
2. 프로젝트 설정 > Android 앱 추가
3. 패키지명: `com.wefilling.app`
4. 새 `google-services.json` 다운로드
5. `android/app/google-services.json` 교체

### 3. 스크린샷 준비 ❌ **필수**

앱스토어 제출에 필요한 스크린샷이 없습니다.

**필요 수량**:
- **Google Play**: 최소 2개 (권장 4-8개)
- **Apple App Store**: 각 디바이스별 최소 3개
  - iPhone 15 Pro Max (6.7")
  - iPhone 14 Plus (6.5")
  - iPhone 8 Plus (5.5")

**촬영 방법**:
```bash
flutter run --release
# 주요 화면 캡처: 로그인, 홈, 모임, 게시판, 프로필
```

### 4. 앱 설명 작성 ❌ **필수**

스토어 등록에 필요한 텍스트가 준비되지 않았습니다.

**필요 항목**:
- Play Store 짧은 설명 (80자 이내)
- Play Store 전체 설명
- App Store 부제목 (30자 이내)
- App Store 키워드 (100자 이내)

**템플릿 위치**: `docs/quick_deployment.md` 참조

---

## ⚠️ 확인 필요 항목

### 5. 법적 문서 URL ✅ **확인됨**

**현재 상태**: GitHub Pages로 호스팅 완료

**URL**:
- 개인정보 처리방침: https://gaemini.github.io/wefilling-nochatbot/
- 서비스 이용약관: https://gaemini.github.io/wefilling-nochatbot/terms.html

**최종 확인 필요**:
- [ ] 모바일 기기에서 정상 표시 확인
- [ ] 한국어/영어 내용 모두 표시 확인
- [ ] 연락처(wefilling@gmail.com) 확인
- [ ] 운영자(Christopher Watson) 확인

**스토어 제출 시 사용할 URL**:
```
개인정보 처리방침: https://gaemini.github.io/wefilling-nochatbot/
서비스 이용약관: https://gaemini.github.io/wefilling-nochatbot/terms.html
```

### 6. iOS 서명 설정

Xcode에서 서명 설정을 확인해야 합니다.

**확인 방법**:
```bash
open ios/Runner.xcworkspace
```

**확인 항목**:
- [ ] Signing & Capabilities 탭에서 Team 선택됨
- [ ] Automatically manage signing 활성화
- [ ] 프로비저닝 프로파일 유효

### 7. Cloud Functions 배포

함수 파일은 있으나 Firebase에 배포되었는지 확인 필요합니다.

**확인 방법**:
```bash
firebase login
firebase functions:list
```

---

## ✅ 잘 준비된 항목

### 권한 설정 ✅
- Android: 모든 필요 권한 설정 완료
- iOS: 권한 설명 한국어로 작성 완료

### 버전 관리 ✅
- pubspec.yaml: 1.0.0+1 설정 완료
- Android/iOS 버전 일관성 확인

### 보안 설정 ✅
- Firestore 규칙: 프로덕션 환경에 적합
- ProGuard 난독화: 활성화됨
- 이메일 인증: 한양대 이메일 검증 적용

### 앱 아이콘 ✅
- Android용: `assets/icons/app_logo.png`
- iOS용: `assets/icons/app_logo_ios.png`

---

## 📋 작업 우선순위

### 🔴 1단계: 즉시 (오늘 중)
1. Android Keystore 생성 (30분)
2. Firebase 패키지명 수정 (30분)
3. 빌드 테스트 (1시간)

### 🟡 2단계: 내일
4. 스크린샷 촬영 (2시간)
5. 앱 설명 작성 (1시간)
6. 법적 문서 URL 확인 (30분)
7. iOS 서명 확인 (30분)

### 🟢 3단계: 모레
8. 실제 기기 테스트 (3시간)
9. 스토어 등록 (2시간)
10. 최종 점검 (1시간)

**예상 배포 가능 시점**: 3일 후

---

## 📊 카테고리별 준비 상태

| 카테고리 | 상태 | 비고 |
|---------|------|------|
| Android 서명 | ⚠️ 50% | Keystore 생성 필요 |
| iOS 서명 | ✅ 90% | Xcode 확인만 필요 |
| 법적 문서 | ✅ 100% | URL 확인 완료 |
| 메타데이터 | ❌ 30% | 스크린샷, 설명 필요 |
| 권한 설정 | ✅ 100% | 완료 |
| 버전 관리 | ✅ 100% | 완료 |
| Firebase | ⚠️ 80% | 패키지명 수정 필요 |
| 테스트 | ❌ 0% | 릴리즈 빌드 테스트 필요 |
| 스토어 준비 | ⚠️ 60% | 계정은 있으나 등록 필요 |

---

## 🎯 다음 단계

### 지금 바로 시작하세요:

```bash
# 1. Keystore 생성
keytool -genkey -v -keystore ~/wefilling-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload -storetype JKS

# 2. key.properties 파일 생성
cat > android/key.properties << EOF
storePassword=YOUR_PASSWORD
keyPassword=YOUR_PASSWORD
keyAlias=upload
storeFile=/Users/chajaemin/wefilling-upload-key.jks
EOF

# 3. Firebase 설정 수정 후 빌드 테스트
flutter clean
flutter build appbundle --release
```

---

## 📚 상세 정보

전체 체크리스트는 [`DEPLOYMENT_CHECKLIST.md`](DEPLOYMENT_CHECKLIST.md) 파일을 참조하세요.

배포 가이드는 다음 문서들을 참조하세요:
- `docs/DEPLOYMENT_GUIDE.md` - 법적 문서 배포
- `docs/quick_deployment.md` - 빠른 배포 가이드
- `docs/keystore_setup.md` - Keystore 설정

---

**질문이나 문제가 있으시면 언제든지 문의하세요!**

📧 wefilling@gmail.com

