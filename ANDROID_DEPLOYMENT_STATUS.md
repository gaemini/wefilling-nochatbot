# Android 배포 상태 점검 보고서

**작성일**: 2025-12-15  
**현재 상태**: 배포 완료  
**검토 목적**: 차기 업데이트 대비 설정 일관성 확인

---

## 배포 상태 요약

✅ **Android 앱이 이미 Play Store에 배포되어 있습니다.**

이 보고서는 현재 배포된 상태를 기준으로, 향후 업데이트나 iOS와의 설정 일관성을 위해 확인이 필요한 항목들을 정리합니다.

---

## 1. 패키지명 및 Bundle ID 일관성 ✅

### 현재 설정

**Android 패키지명**:
```
applicationId = "com.wefilling.app"
```
위치: `android/app/build.gradle.kts`

**iOS Bundle ID**:
```
com.wefilling.app
```
위치: `ios/Runner.xcodeproj/project.pbxproj`

**Firebase Android 앱**:
```
package_name: "com.wefilling.app"
```
위치: `android/app/google-services.json`

### 검증 결과

✅ **모든 패키지명이 일치합니다**: `com.wefilling.app`

**영향**: 
- Firebase 서비스(FCM, Crashlytics, Auth 등)가 정상 작동
- 크로스 플랫폼 데이터 공유 문제 없음

---

## 2. 앱 서명 (Keystore) 상태 ⚠️

### 현재 상태

**keystore 파일**: 
```
❌ 프로젝트에서 확인되지 않음
❌ key.properties 파일 없음
```

### 배포 방식 추정

Play Store에 이미 배포되어 있다면, 다음 중 하나의 방식을 사용했을 가능성이 높습니다:

#### 방식 1: Play App Signing (Google 관리형) - 권장
- Google이 앱 서명 키를 관리
- 업로드 키만 로컬에서 관리
- **확인 방법**: Play Console > 설정 > 앱 무결성 > "App signing by Google Play" 활성화 여부

#### 방식 2: 수동 서명
- 개발자가 직접 keystore 파일 관리
- keystore 파일이 안전한 곳에 백업되어 있어야 함

### 권장 조치

#### 즉시 확인 필요:
1. **Play Console 접속**:
   - https://play.google.com/console
   - Wefilling 앱 선택
   - **설정** > **앱 무결성** 확인

2. **App Signing 상태 확인**:
   - "App signing by Google Play" 활성화 여부
   - 앱 서명 인증서 지문 확인
   - 업로드 인증서 지문 확인

3. **Keystore 백업 확인**:
   - 로컬 또는 안전한 저장소에 keystore 파일 백업 존재 여부
   - 비밀번호 안전 보관 여부

#### 차기 업데이트 시:
- keystore 파일 및 key.properties를 프로젝트에 추가 (Git에는 커밋하지 않음)
- 또는 Play App Signing 사용 시 업로드 키만 관리

---

## 3. Firebase 설정 일관성 ✅

### google-services.json

**패키지명**: `com.wefilling.app` ✅

**위치**: `android/app/google-services.json`

### 검증 결과

✅ **Firebase 설정이 올바릅니다**

**영향**:
- FCM 푸시 알림 정상 작동
- Firebase Auth/Firestore 정상 작동
- Crashlytics 정상 작동

---

## 4. 앱 권한 설정 ✅

### AndroidManifest.xml

**설정된 권한**:
```xml
✅ INTERNET - 네트워크 통신
✅ READ_MEDIA_IMAGES - 이미지 읽기 (Android 13+)
✅ READ_EXTERNAL_STORAGE - 외부 저장소 읽기 (Android 12 이하)
✅ POST_NOTIFICATIONS - 푸시 알림 (Android 13+)
✅ WAKE_LOCK - FCM 백그라운드 처리
✅ C2D_MESSAGE - FCM 수신
```

**앱 이름**:
```
android:label="Wefilling" ✅
```

### 검증 결과

✅ **모든 필수 권한이 올바르게 설정되어 있습니다**

---

## 5. ProGuard/R8 난독화 설정 ✅

### 현재 설정

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

### 검증 결과

✅ **난독화 및 리소스 최적화가 활성화되어 있습니다**

**영향**:
- 앱 크기 감소
- 코드 보안 강화
- 역공학 방지

---

## 6. 버전 관리 ✅

### 현재 버전

**pubspec.yaml**:
```yaml
version: 1.0.0+4
```

**의미**:
- Version Name: 1.0.0 (사용자에게 표시)
- Build Number: 4 (내부 버전, 증가해야 함)

### 검증 결과

✅ **버전 정보가 올바르게 설정되어 있습니다**

**주의**: 
- 다음 업데이트 시 Build Number를 5로 증가시켜야 함
- Version Name은 변경 범위에 따라 조정 (예: 1.0.1, 1.1.0, 2.0.0)

---

## 7. iOS와의 설정 일관성 ✅

### 크로스 플랫폼 확인

| 항목 | Android | iOS | 일치 여부 |
|------|---------|-----|----------|
| 패키지/Bundle ID | com.wefilling.app | com.wefilling.app | ✅ |
| 앱 이름 | Wefilling | Wefilling | ✅ |
| 버전 | 1.0.0+4 | 1.0.0+4 | ✅ |
| Firebase 프로젝트 | flutterproject3-af322 | flutterproject3-af322 | ✅ |
| 푸시 알림 | FCM | FCM + APNs | ✅ |

### 검증 결과

✅ **Android와 iOS 설정이 일관성 있게 구성되어 있습니다**

---

## 권장 조치 사항

### 🔴 즉시 확인 필요

1. **Play Console에서 App Signing 상태 확인**
   - App signing by Google Play 활성화 여부
   - 인증서 지문 확인
   - 업로드 키 백업 확인

2. **Keystore 백업 확인**
   - 로컬 keystore 파일 위치 확인
   - 비밀번호 안전 보관 확인
   - 백업 사본 생성 (안전한 곳에 보관)

### 🟡 차기 업데이트 시

3. **key.properties 파일 준비**
   - 업데이트 빌드 시 필요
   - Git에 커밋하지 않도록 .gitignore 확인 (이미 추가됨)

4. **SHA-1 인증서 지문 확인**
   - Firebase Console에 등록된 SHA-1 확인
   - Release 및 Debug 지문 모두 등록 확인

### 🟢 권장 사항

5. **ProGuard 규칙 검토**
   - `android/app/proguard-rules.pro` 파일 확인
   - Firebase/Flutter 플러그인 관련 규칙 추가 필요 시 업데이트

6. **버전 관리 전략**
   - 다음 업데이트: 1.0.0+5 (버그 수정)
   - 기능 추가: 1.1.0+5
   - 메이저 변경: 2.0.0+5

---

## 차기 업데이트 빌드 명령어

```bash
# 1. 버전 업데이트 (pubspec.yaml에서 수동 변경)
# version: 1.0.0+5

# 2. 클린 빌드
flutter clean
flutter pub get

# 3. AAB 빌드 (Play Store 업로드용)
flutter build appbundle --release

# 4. 빌드 확인
ls -lh build/app/outputs/bundle/release/app-release.aab

# 5. Play Console에 업로드
# Play Console > 프로덕션 > 새 버전 만들기 > AAB 업로드
```

---

## 요약

### 현재 상태
- ✅ Android 앱 배포 완료
- ✅ 패키지명 일관성 확보
- ✅ Firebase 설정 올바름
- ✅ 권한 설정 완료
- ✅ 난독화 활성화
- ⚠️ Keystore 백업 상태 확인 필요

### 다음 조치
1. Play Console에서 App Signing 상태 확인
2. Keystore 백업 확인 및 안전 보관
3. 차기 업데이트 시 key.properties 준비

### iOS 배포와의 관계
- Android는 이미 배포 완료, 안정적 운영 중
- iOS 배포가 완료되면 양쪽 플랫폼 모두 서비스 가능
- 크로스 플랫폼 설정 일관성 확보로 유지보수 용이

---

**작성자**: AI Assistant  
**마지막 업데이트**: 2025-12-15  
**문의**: wefilling@gmail.com
