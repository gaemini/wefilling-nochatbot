# Keystore 생성 및 앱 서명 설정 가이드

## 1단계: Upload Key 생성

터미널에서 다음 명령어를 실행하여 upload key를 생성합니다:

```bash
keytool -genkey -v -keystore ~/wefilling-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload \
  -storetype JKS
```

### 입력 정보:
- **Password**: 안전한 비밀번호 설정 (잊지 말 것!)
- **Name**: 회사 또는 개인 이름
- **Organizational Unit**: 부서명 (선택사항, Enter로 skip 가능)
- **Organization**: 회사명
- **City/Locality**: 도시명
- **State/Province**: 시/도
- **Country Code**: KR

**중요**: 생성된 `wefilling-upload-key.jks` 파일과 비밀번호를 안전하게 백업하세요!

## 2단계: key.properties 파일 생성

`android/key.properties` 파일을 생성하고 다음 내용을 입력합니다:

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=/Users/chajaemin/wefilling-upload-key.jks
```

**중요**: 
- `YOUR_STORE_PASSWORD`와 `YOUR_KEY_PASSWORD`를 실제 비밀번호로 변경하세요
- 이 파일은 Git에 커밋하지 마세요 (.gitignore에 이미 추가됨)

## 3단계: build.gradle.kts 수정

`android/app/build.gradle.kts` 파일의 상단에 다음 코드를 추가합니다:

```kotlin
// Keystore 설정 로드
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    // ... 기존 plugins
}

// ... dependencies

android {
    // ... 기존 설정
    
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }
    
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            
            // ProGuard/R8 설정 (이미 추가됨)
            minifyEnabled = true
            shrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}
```

## 4단계: 릴리즈 빌드 테스트

```bash
# APK 빌드
flutter build apk --release

# AAB 빌드 (Play Store 업로드용)
flutter build appbundle --release
```

## 5단계: Google Play Console에서 App Signing 설정

1. [Google Play Console](https://play.google.com/console) 접속
2. 앱 선택 (또는 새 앱 만들기)
3. **릴리스 > 설정 > 앱 서명** 메뉴로 이동
4. **Google Play 앱 서명 사용 설정** 선택
5. 첫 AAB 파일 업로드 시 자동으로 Upload Key가 등록됩니다

## Upload Key vs App Signing Key

### Upload Key (업로드 키)
- 개발자가 직접 생성하고 보관
- AAB/APK를 Play Console에 업로드할 때 사용
- 분실 시 Google 지원팀을 통해 재설정 가능

### App Signing Key (앱 서명 키)
- Google Play가 관리하는 최종 배포용 키
- 실제 사용자에게 배포되는 APK는 이 키로 서명됨
- Google이 안전하게 보관

## 보안 주의사항

✅ **반드시 지켜야 할 것:**
- keystore 파일 (`.jks`)을 안전한 곳에 백업
- `key.properties` 파일을 Git에 커밋하지 않기
- 비밀번호를 안전하게 보관 (비밀번호 관리자 사용 권장)

❌ **절대 하지 말아야 할 것:**
- keystore 파일을 Git에 커밋
- key.properties를 Git에 커밋
- 비밀번호를 코드에 하드코딩
- keystore 파일을 공개 저장소에 업로드

## 문제 해결

### "Keystore file not found" 오류
- `key.properties`의 `storeFile` 경로가 올바른지 확인
- keystore 파일이 지정된 위치에 존재하는지 확인

### "Wrong password" 오류
- `key.properties`의 비밀번호가 올바른지 확인
- keystore 생성 시 사용한 비밀번호와 일치하는지 확인

### 빌드 시 서명 오류
- `flutter clean` 후 다시 빌드
- Android Studio에서 Invalidate Caches / Restart

