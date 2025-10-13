# 의존성 관리 문서

## 📦 Core Dependencies

### Firebase 관련
- **firebase_core** (^4.1.0) - Firebase 초기화 및 기본 설정
- **firebase_auth** (^6.0.2) - 사용자 인증 (Google Sign-In)
- **firebase_messaging** (^16.0.2) - FCM 푸시 알림
- **cloud_firestore** (^6.0.1) - 데이터베이스
- **cloud_functions** (^6.0.2) - 서버리스 함수
- **firebase_storage** (^13.0.1) - 파일 저장소
- **firebase_remote_config** (^6.0.1) - Feature Flag

### 상태 관리
- **provider** (^6.0.5) - 상태 관리 (MVVM 패턴)

### UI/UX
- **cached_network_image** (^3.4.1) - 이미지 캐싱
- **flutter_image_compress** (^2.1.0) - 이미지 압축
- **image_picker** (^1.0.4) - 갤러리/카메라 접근

### 유틸리티
- **uuid** (^4.5.1) - 고유 ID 생성
- **intl** (^0.20.2) - 날짜/시간 포맷팅
- **path** (^1.8.3) - 경로 처리
- **path_provider** (^2.1.1) - 로컬 경로 접근
- **http** (^1.1.0) - HTTP 클라이언트
- **url_launcher** (^6.1.14) - 외부 URL 실행
- **webview_flutter** (^4.4.2) - WebView
- **shared_preferences** (^2.2.2) - 로컬 저장소

### 소셜 기능
- **google_sign_in** (^7.2.0) - Google 로그인
- **translator** (^1.0.3+1) - 텍스트 번역
- **flutter_linkify** (^6.0.0) - URL 자동 링크

### 권한 관리
- **permission_handler** (^11.3.1) - 앱 권한 요청

---

## ⚠️ 의존성 관리 규칙

### 1. 버전 업데이트
```bash
# 월 1회 체크
flutter pub outdated

# 마이너 업데이트만 적용
flutter pub upgrade --minor-versions

# 메이저 업데이트는 신중히
flutter pub upgrade --major-versions package_name
```

### 2. 새 패키지 추가 시 체크리스트
- [ ] pub.dev Pub Points 130/130 확인
- [ ] 최근 6개월 이내 업데이트 확인
- [ ] GitHub Stars 1,000+ 확인
- [ ] Null Safety 지원 확인
- [ ] 라이센스 호환성 확인
- [ ] 테스트 후 pubspec.lock 커밋

### 3. 패키지 제거 시
```bash
# 1. pubspec.yaml에서 제거
# 2. 사용하지 않는 import 제거
flutter pub get
# 3. 테스트 실행
flutter test
flutter build apk --release
```

---

## 🔒 보안 관련 패키지

### Firebase 보안
- 모든 Firebase 패키지는 동일한 메이저 버전 유지 권장
- firebase_core 업데이트 시 다른 firebase_* 패키지도 함께 업데이트

### 인증 관련
- firebase_auth, google_sign_in은 호환성 중요
- 업데이트 시 반드시 테스트

---

## 📊 의존성 트리

```
wefilling
├── flutter (sdk)
├── firebase_core → 다른 모든 Firebase 패키지의 기반
│   ├── firebase_auth
│   ├── cloud_firestore
│   ├── firebase_storage
│   ├── firebase_messaging
│   └── cloud_functions
├── provider → AuthProvider, RelationshipProvider
└── google_sign_in → firebase_auth와 연동
```

---

## 🚨 알려진 이슈

### 1. Google Sign-In
- iOS에서 clientId 설정 필요
- `main.dart`에서 초기화 시 clientId 제공

### 2. Firebase Messaging
- Android 13+ POST_NOTIFICATIONS 권한 필요
- FCM 토큰 로그아웃 시 삭제 필수

### 3. Image Picker
- Android 13+ READ_MEDIA_IMAGES 권한 사용
- 구버전 Android는 READ_EXTERNAL_STORAGE

---

## 📅 업데이트 히스토리

### 2025-01-13
- convex_bottom_bar 제거 (미사용)
- country_flags 제거 (미사용)
- easy_localization 제거 (미사용)
- 패키지명 변경: com.wefilling.app

---

## 📞 문제 발생 시

1. `flutter clean && flutter pub get`
2. `flutter pub cache repair`
3. pubspec.lock 삭제 후 재생성
4. 의존성 충돌 시 dependency_overrides 사용 (최후의 수단)

