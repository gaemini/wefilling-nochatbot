# Wefilling (위필링)

> 함께하면 즐거운 대학 생활

대학생을 위한 소셜 네트워킹 및 모임 관리 플랫폼

---

## 📱 주요 기능

- **게시판** - 게시글 작성, 댓글, 공개범위 설정
- **모임** - 스터디, 식사, 취미, 문화 모임 생성 및 참여
- **친구** - 친구 요청, 카테고리별 친구 관리
- **알림** - FCM 실시간 푸시 알림
- **프로필** - 사용자 프로필, 리뷰 시스템

---

## 🛠️ 기술 스택

### Frontend
- **Flutter** 3.7.0+
- **Dart** 3.7.0+
- **상태 관리**: Provider (MVVM 패턴)

### Backend
- **Firebase Authentication** - Google Sign-In
- **Cloud Firestore** - 데이터베이스
- **Firebase Storage** - 파일 저장
- **Cloud Functions** - 서버리스 백엔드
- **Firebase Messaging** - 푸시 알림

### 아키텍처
- **MVVM** (Model-View-ViewModel)
- **Repository Pattern**
- **Service Layer**

---

## 🚀 개발 환경 설정

### 1. 사전 요구사항

```bash
# Flutter SDK
flutter --version  # 3.7.0 이상

# FVM (권장)
brew install fvm
```

### 2. 프로젝트 클론

```bash
git clone <repository-url>
cd wefilling-nochatbot
```

### 3. Flutter 버전 설정 (FVM 사용 시)

```bash
# FVM으로 Flutter 버전 설치
fvm install

# FVM Flutter 사용
fvm flutter --version
```

### 4. 의존성 설치

```bash
# FVM 사용 시
fvm flutter pub get

# 일반 Flutter 사용 시
flutter pub get
```

### 5. Firebase 설정

1. `firebase_options.dart` 파일 확인
2. `android/app/google-services.json` 확인 (Android)
3. `ios/Runner/GoogleService-Info.plist` 확인 (iOS)

### 6. 실행

```bash
# 디버그 모드
fvm flutter run

# 프로필 모드 (성능 테스트)
fvm flutter run --profile

# 릴리즈 모드
fvm flutter run --release
```

---

## 📦 빌드

### Android APK

```bash
# 단일 APK
fvm flutter build apk --release

# Split APK (권장)
fvm flutter build apk --release --split-per-abi
```

### Android App Bundle (Play Store)

```bash
fvm flutter build appbundle --release
```

### iOS

```bash
fvm flutter build ios --release
```

---

## 🏗️ 프로젝트 구조

```
lib/
├── main.dart                 # 앱 진입점
├── constants/                # 상수 정의
├── models/                   # 데이터 모델
├── providers/                # 상태 관리 (ViewModel)
│   ├── auth_provider.dart
│   └── relationship_provider.dart
├── services/                 # 비즈니스 로직
│   ├── auth_service.dart
│   ├── post_service.dart
│   ├── meetup_service.dart
│   └── ...
├── repositories/             # 데이터 접근
├── screens/                  # 화면 (View)
├── widgets/                  # 재사용 컴포넌트
├── ui/                       # UI 컴포넌트
│   ├── widgets/
│   ├── dialogs/
│   └── animations/
├── design/                   # 디자인 시스템
│   ├── theme.dart
│   └── tokens.dart
└── utils/                    # 유틸리티 함수
```

---

## 🧪 테스트

```bash
# 단위 테스트
fvm flutter test

# 위젯 테스트
fvm flutter test test/widget_test.dart

# 통합 테스트
fvm flutter drive --target=test_driver/app.dart

# 커버리지
fvm flutter test --coverage
```

---

## 📊 코드 품질

### 분석

```bash
# 린팅
fvm flutter analyze

# 포맷팅
fvm flutter format lib/

# 미사용 코드 확인
fvm flutter pub run dart_code_metrics:metrics check-unused-code lib
```

### 권장 사항
- 린트 에러 0개 유지
- 함수 Cyclomatic Complexity ≤ 10
- 파일 크기 ≤ 500줄

---

## 🔐 보안

### 민감 정보 관리

```bash
# Git에 커밋하지 말 것
android/key.properties        # Keystore 정보
android/app/google-services.json (프로덕션)
ios/Runner/GoogleService-Info.plist (프로덕션)
*.jks                         # Keystore 파일
```

### 앱 서명

자세한 내용은 [KEYSTORE_SETUP_GUIDE.md](./KEYSTORE_SETUP_GUIDE.md) 참조

---

## 📚 문서

- [의존성 관리](./DEPENDENCIES.md) - 패키지 관리 가이드
- [디자인 시스템](./DESIGN_SYSTEM_GUIDE.md) - UI/UX 가이드
- [배포 가이드](./OPTIMIZATION_SUMMARY.md) - 플레이스토어 배포
- [Keystore 설정](./KEYSTORE_SETUP_GUIDE.md) - 앱 서명

---

## 🤝 기여 가이드

### 브랜치 전략

```bash
main          # 프로덕션 (플레이스토어)
develop       # 개발 브랜치
feature/*     # 기능 개발
bugfix/*      # 버그 수정
hotfix/*      # 긴급 수정
```

### 커밋 메시지

```
feat: 새로운 기능 추가
fix: 버그 수정
refactor: 코드 리팩토링
docs: 문서 수정
style: 코드 포맷팅
test: 테스트 추가/수정
chore: 빌드 설정, 의존성 업데이트
```

---

## 📱 지원 플랫폼

- ✅ Android (API 24+)
- ✅ iOS (iOS 12.0+)

---

## 📄 라이센스

이 프로젝트는 비공개 프로젝트입니다.

---

## 📞 문의

프로젝트 관련 문의사항이 있으시면 이슈를 등록해주세요.

---

## 🔄 버전 관리

### 최신 버전: 1.0.0+1

#### v1.0.0 (2025-01-13)
- 초기 플레이스토어 배포
- 회원탈퇴 완전 삭제 기능 구현
- ProGuard 난독화 적용
- 코드 최적화 및 정리
- 패키지명 변경: com.wefilling.app

---

## ⚙️ VS Code 설정

프로젝트에 `.vscode/settings.json`이 포함되어 있습니다.

추천 확장 프로그램:
- Dart
- Flutter
- Awesome Flutter Snippets
- Flutter Snippets

---

## 🎯 성능 지표

- APK 크기: ~40MB (목표: <50MB)
- 앱 시작 시간: <2초
- 60fps 유지 (대부분의 화면)

---

## 🚨 알려진 이슈

없음

---

**Built with ❤️ by Wefilling Team**
