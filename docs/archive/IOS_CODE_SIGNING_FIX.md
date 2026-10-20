# iOS Code Signing 및 Keychain 접근 문제 해결 가이드

## 문제 요약
- **증상**: iOS 시뮬레이터에서 Google Sign-In과 Firebase Remote Config가 `keychain error (-34018)` 발생
- **근본 원인**: 시뮬레이터에서 코드 서명이 비활성화되어 Keychain 접근 불가
- **해결**: 시뮬레이터에서 Ad-Hoc 서명(`-`) 활성화 + Keychain Access Groups 추가

---

## 최종 해결 방법

### 1. 모든 Entitlements 파일에 Keychain Access Groups 추가

#### `ios/Runner/Runner.entitlements` (Debug)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>development</string>
	<key>com.apple.developer.applesignin</key>
	<array>
		<string>Default</string>
	</array>
	<key>keychain-access-groups</key>
	<array>
		<string>$(AppIdentifierPrefix)com.wefilling.app</string>
	</array>
</dict>
</plist>
```

#### `ios/Runner/RunnerProfile.entitlements` (Profile)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>production</string>
	<key>com.apple.developer.applesignin</key>
	<array>
		<string>Default</string>
	</array>
	<key>keychain-access-groups</key>
	<array>
		<string>$(AppIdentifierPrefix)com.wefilling.app</string>
	</array>
</dict>
</plist>
```

#### `ios/Runner/RunnerRelease.entitlements` (Release)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>production</string>
	<key>com.apple.developer.applesignin</key>
	<array>
		<string>Default</string>
	</array>
	<key>keychain-access-groups</key>
	<array>
		<string>$(AppIdentifierPrefix)com.wefilling.app</string>
	</array>
</dict>
</plist>
```

---

### 2. Xcode 프로젝트 서명 설정 (project.pbxproj)

#### Debug, Profile, Release 빌드 설정 모두 동일하게 적용:

```pbxproj
CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION = YES;
CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements; // 또는 각 config에 맞는 entitlements
CODE_SIGN_IDENTITY = "Apple Development";
"CODE_SIGN_IDENTITY[sdk=iphonesimulator*]" = "-";
CODE_SIGN_STYLE = Automatic;
DEVELOPMENT_TEAM = ULTS66B6QD;
```

**핵심 포인트:**
- `CODE_SIGNING_ALLOWED`와 `CODE_SIGNING_REQUIRED` 설정은 **삭제**
- 시뮬레이터용 서명 ID는 `"-"` (Ad-Hoc 서명)
- 실제 기기용 서명 ID는 `"Apple Development"`
- Automatic Code Signing 활성화

---

## 재현 가능한 완전 초기화 시퀀스

문제가 재발하거나 새로 설정할 때:

```bash
# 1. 완전 클린
flutter clean
rm -rf ios/Pods ios/Podfile.lock ~/Library/Caches/CocoaPods

# 2. Flutter 종속성 재생성
flutter pub get

# 3. CocoaPods 재설치
cd ios
pod cache clean --all
pod deintegrate
pod install
cd ..

# 4. 시뮬레이터 부팅 (필요시)
xcrun simctl boot "1CA052F6-D63B-4AD7-81D2-F1F5EE856DA3"
open -a Simulator

# 5. 앱 실행
flutter run -d "1CA052F6-D63B-4AD7-81D2-F1F5EE856DA3" --debug
```

---

## 검증 체크리스트

앱 실행 후 다음 로그가 **에러 없이** 나타나면 성공:

```
flutter: 🔥 Firebase 초기화 완료
flutter: 🛡️ App Check 활성화 완료
flutter: 🐞 Crashlytics 초기화 완료 (debug mode: true)
flutter: 💾 캐시 시스템 초기화 완료
flutter: ✅ Firestore 설정 완료 (캐시: 100MB)
flutter: ✅ Firebase Storage 접근 테스트: 성공
flutter: 🚩 FeatureFlagService 초기화 완료  // Remote Config 성공
flutter: 🌐 언어 로드 완료
```

**실패 징후:**
```
❌ Remote Config 가져오기 오류: [firebase_remote_config/unknown] Failed to get installations token. Error : Error Domain=com.firebase.installations Code=0 "Underlying error: The operation couldn't be completed. SecItemCopyMatching (-34018)"
```

이 에러가 나타나면 시뮬레이터 서명 설정 또는 entitlements가 제대로 적용되지 않은 것입니다.

---

## 주의사항

### ❌ 피해야 할 설정
```pbxproj
// 절대 사용하지 마세요:
"CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]" = NO;
"CODE_SIGNING_REQUIRED[sdk=iphonesimulator*]" = NO;
"CODE_SIGN_IDENTITY[sdk=iphonesimulator*]" = "";
```
→ 이 설정은 Keychain 접근을 완전히 차단합니다.

### ✅ 올바른 설정
```pbxproj
"CODE_SIGN_IDENTITY[sdk=iphonesimulator*]" = "-";
```
→ Ad-Hoc 서명으로 Keychain 접근 가능하면서 실제 인증서 없이도 작동합니다.

---

## AppAuth Pod 손상 시 해결법

에러:
```
Error (Xcode): lstat(/Users/.../ios/Pods/AppAuth/Sources/AppAuth.h): No such file or directory (2)
```

해결:
```bash
rm -rf ios/Pods ios/Podfile.lock ~/Library/Caches/CocoaPods
cd ios && pod cache clean --all && pod deintegrate && pod install && cd ..
flutter run
```

---

## 최종 상태 (2026-03-07)

- ✅ 시뮬레이터 빌드 성공
- ✅ Firebase Installations Keychain 접근 성공
- ✅ Remote Config 초기화 성공 (에러 없음)
- ✅ Google Sign-In Keychain 접근 가능
- ✅ AppAuth, Firebase SDK 모든 종속성 정상 설치

**재발 방지**: 이 문서의 설정을 유지하고, `project.pbxproj`를 직접 수정하지 마세요. Xcode에서 변경이 필요하면 이 가이드를 참고하여 수동으로 복원하세요.
