# ✅ 패키지명 변경 체크리스트

패키지명: `com.example.flutter_practice3` → `com.wefilling.app`

---

## 완료된 작업

### ✅ 1. android/app/build.gradle.kts

**위치**: `android/app/build.gradle.kts`

**변경사항**:
- ✅ **import 추가**: keystore properties 로딩을 위한 import 추가
- ✅ **namespace 변경**: `com.example.flutter_practice3` → `com.wefilling.app`
- ✅ **applicationId 변경**: `com.example.flutter_practice3` → `com.wefilling.app`
- ✅ **signingConfigs 추가**: release 빌드를 위한 signing 설정
- ✅ **release signingConfig 변경**: `debug` → `release`

**주요 코드**:
```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.wefilling.app"
    
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
    
    defaultConfig {
        applicationId = "com.wefilling.app"
        ...
    }
    
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            ...
        }
    }
}
```

---

### ✅ 2. MainActivity.kt 이동 및 수정

**이전 위치**: `android/app/src/main/kotlin/com/example/flutter_practice3/MainActivity.kt`  
**새 위치**: `android/app/src/main/kotlin/com/wefilling/app/MainActivity.kt`

**변경사항**:
- ✅ 새 폴더 생성: `com/wefilling/app/`
- ✅ 파일 이동 완료
- ✅ package 변경: `com.example.flutter_practice3` → `com.wefilling.app`
- ✅ 기존 폴더 삭제: `com/example/` 삭제 완료

**파일 내용**:
```kotlin
package com.wefilling.app

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
```

---

### ✅ 3. lib/main.dart

**변경사항**:
- ✅ **firebase_options.dart import**: 이미 추가되어 있음
- ✅ **DefaultFirebaseOptions 사용**: 이미 올바르게 설정되어 있음

**확인된 코드**:
```dart
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform
  );
  
  ...
}
```

---

### ✅ 4. android/key.properties 파일 생성

**위치**: `android/key.properties`

**내용**:
```properties
storePassword=YOUR_PASSWORD_HERE
keyPassword=YOUR_PASSWORD_HERE
keyAlias=upload
storeFile=/Users/chajaemin/wefilling-upload-key.jks
```

⚠️ **중요**: `YOUR_PASSWORD_HERE`를 실제 비밀번호로 교체해야 합니다!

---

### ✅ 5. .gitignore

**확인 완료**: 다음 항목들이 이미 포함되어 있음
- ✅ `*.jks`
- ✅ `*.keystore`
- ✅ `/android/key.properties`
- ✅ `/android/app/key.properties`
- ✅ `key.properties`

---

### ✅ 6. AndroidManifest.xml

**위치**: `android/app/src/main/AndroidManifest.xml`

**확인 결과**: 
- ✅ `package` 속성 없음 (Gradle의 `namespace`가 사용됨)
- ✅ 수정 불필요

---

## 🔧 다음 단계

### 1. 업로드 키 생성

터미널에서 실행:
```bash
keytool -genkey -v -keystore ~/wefilling-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload \
  -storetype JKS
```

**입력 정보**:
- 비밀번호: [안전한 비밀번호 - 기억할 것!]
- 이름: 차재민
- 조직: Wefilling
- 도시: Seoul
- 국가: KR

### 2. key.properties 비밀번호 업데이트

`android/key.properties` 파일을 열어서:
```properties
storePassword=실제비밀번호입력
keyPassword=실제비밀번호입력
keyAlias=upload
storeFile=/Users/chajaemin/wefilling-upload-key.jks
```

### 3. 빌드 테스트

```bash
# 캐시 정리
flutter clean

# 의존성 재설치
flutter pub get

# 디버그 빌드 테스트
flutter run

# 릴리즈 AAB 빌드
flutter build appbundle --release
```

### 4. 빌드 성공 확인

```bash
ls -la build/app/outputs/bundle/release/app-release.aab
```

파일이 존재하면 ✅ 완료!

---

## 📊 최종 확인

모든 작업 완료 후 확인:

```bash
# 생성된 파일 확인
ls -la lib/firebase_options.dart
ls -la android/app/google-services.json
ls -la android/app/src/main/kotlin/com/wefilling/app/MainActivity.kt
ls -la android/key.properties
ls -la ~/wefilling-upload-key.jks
ls -la build/app/outputs/bundle/release/app-release.aab
```

모두 존재하면 **Play Store 업로드 준비 완료!** 🎉

---

## ⚠️ 주의사항

1. **key.properties와 .jks 파일은 절대 Git에 커밋하지 마세요!**
2. **비밀번호는 안전하게 보관하세요!**
3. **업로드 키를 분실하면 앱을 업데이트할 수 없습니다!**

---

## 🆘 문제 해결

### 빌드 오류 발생 시:

1. **Gradle 캐시 정리**:
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
```

2. **Android Studio에서 Invalidate Caches**:
   - File → Invalidate Caches / Restart

3. **key.properties 경로 확인**:
   - `storeFile` 경로가 올바른지 확인
   - 파일이 실제로 존재하는지 확인

### Firebase 오류 발생 시:

1. **google-services.json 확인**:
   - `android/app/google-services.json` 파일 존재 확인
   - 파일 내 `package_name`이 `com.wefilling.app`인지 확인

2. **Firebase Console 확인**:
   - Firebase Console에서 패키지명이 `com.wefilling.app`으로 등록되었는지 확인
















