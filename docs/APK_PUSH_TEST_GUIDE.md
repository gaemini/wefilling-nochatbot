# APK 푸시 알림 테스트 가이드

## 🚨 문제 해결 완료 사항

### 수정된 내용
1. ✅ **앱 시작 시 FCM 조기 초기화 추가** (`main.dart`)
   - 로그인 전에 FCM 토큰 생성
   - Android 13+ 알림 권한 조기 확인

2. ✅ **상세한 디버깅 로그 추가** (`fcm_service.dart`)
   - FCM 초기화 6단계 로그
   - 토큰 생성/저장 상세 로그
   - 메시지 수신 상세 로그

3. ✅ **ProGuard 설정 완벽** (`proguard-rules.pro`)
   - FCM 관련 클래스 보존
   - Permission Handler 보존
   - Flutter Local Notifications 보존

## 📱 APK 테스트 절차

### 1단계: 클린 빌드

```bash
# 1. 완전 클린
cd /Users/chajaemin/Desktop/wefilling-nochatbot
flutter clean
rm -rf build/
rm -rf android/app/build/

# 2. 패키지 재설치
flutter pub get

# 3. Android 빌드 캐시 정리
cd android
./gradlew clean
cd ..

# 4. Release APK 빌드
flutter build apk --release

# 빌드 완료 후 APK 위치:
# build/app/outputs/flutter-apk/app-release.apk
```

### 2단계: APK 설치 및 테스트

#### A. 기존 앱 완전 삭제
```bash
# 앱 완전 삭제 (데이터 포함)
adb uninstall com.wefilling.app
```

#### B. 새 APK 설치
```bash
# APK 설치
adb install build/app/outputs/flutter-apk/app-release.apk
```

#### C. 로그 모니터링 시작
```bash
# 터미널 1: FCM 로그 모니터링
adb logcat | grep -E "FCM|firebase|notification|알림|토큰"

# 터미널 2: Flutter 로그 모니터링
adb logcat | grep -E "flutter|DEBUG"
```

### 3단계: 앱 실행 및 확인

#### ✅ 체크리스트

1. **앱 시작 시**
   - [ ] "📱 FCM 조기 초기화 시작..." 로그 확인
   - [ ] "🔥 FCM 토큰 생성 완료: ..." 로그 확인
   - [ ] 토큰이 20자 이상인지 확인

2. **로그인 후**
   - [ ] "🚀 FCM 초기화 시작" 로그 확인
   - [ ] "📱 1/6: 로컬 알림 채널 생성 중..." 로그 확인
   - [ ] "📱 2/6: Android 알림 권한 확인 중..." 로그 확인
   - [ ] "✅ Android 알림 권한 허용됨" 로그 확인
   - [ ] "📱 5/6: FCM 토큰 동기화 시작..." 로그 확인
   - [ ] "✅ FCM 토큰 생성 성공!" 로그 확인
   - [ ] "✅ FCM 토큰 서버 저장 완료" 로그 확인
   - [ ] "🎉 푸시 알림 시스템 준비 완료!" 로그 확인

3. **알림 권한 팝업**
   - [ ] Android 13+ 기기에서 알림 권한 팝업이 떴는가?
   - [ ] 권한을 허용했는가?

### 4단계: 푸시 알림 테스트

#### A. Firebase Console에서 테스트 메시지 전송

1. Firebase Console 접속
2. Cloud Messaging > 새 알림 보내기
3. 다음 내용으로 전송:

```json
{
  "notification": {
    "title": "테스트 알림",
    "body": "APK 푸시 알림 테스트입니다"
  },
  "data": {
    "type": "test",
    "click_action": "FLUTTER_NOTIFICATION_CLICK"
  },
  "android": {
    "notification": {
      "channel_id": "high_importance_channel",
      "priority": "high"
    }
  }
}
```

#### B. 테스트 시나리오

##### 시나리오 1: 포그라운드 (앱 실행 중)
1. 앱을 열어둔 상태
2. Firebase Console에서 알림 전송
3. **예상 결과**:
   - 로그: "📬 포어그라운드 메시지 수신!"
   - 로그: "  - 로컬 알림 표시 시도..."
   - 화면 상단에 알림 배너 표시

##### 시나리오 2: 백그라운드 (앱 홈으로 나감)
1. 앱 실행 → 홈 버튼으로 나가기
2. Firebase Console에서 알림 전송
3. **예상 결과**:
   - 알림 트레이에 알림 표시
   - 알림 클릭 시 앱 열림
   - 로그: "📱 백그라운드에서 앱 열림!"

##### 시나리오 3: 종료 상태 (앱 완전 종료)
1. 앱 실행 → 홈으로 나가기 (강제 종료 X)
2. 최근 앱 목록에서 앱 스와이프로 종료
3. Firebase Console에서 알림 전송
4. **예상 결과**:
   - 알림 트레이에 알림 표시
   - 알림 클릭 시 앱 열림
   - 로그: "📱 앱 종료 상태에서 알림으로 열림!"

⚠️ **주의**: "설정 > 앱 > Wefilling > 강제 종료"는 테스트하지 마세요!
→ Android는 강제 종료 상태에서 FCM을 받지 않습니다.

### 5단계: 문제 해결

#### 🔴 토큰이 생성되지 않음

**로그 확인**:
```
⚠️ FCM 토큰 생성 실패 - 나중에 재시도됩니다
```

**원인**:
- Firebase 초기화 실패
- google-services.json 누락
- 네트워크 문제

**해결**:
```bash
# 1. google-services.json 확인
ls -la android/app/google-services.json

# 2. 앱 완전 삭제 후 재설치
adb uninstall com.wefilling.app
adb install build/app/outputs/flutter-apk/app-release.apk

# 3. 앱 재시작
```

#### 🔴 알림 권한 팝업이 안 뜸

**로그 확인**:
```
⚠️ Android 알림 권한 이미 허용됨
또는
⚠️ Android 알림 권한 영구 거부됨
```

**원인**:
- 이전에 이미 권한을 허용/거부함
- Android 12 이하 (자동 허용)

**확인**:
```bash
# 권한 상태 확인
adb shell dumpsys package com.wefilling.app | grep "android.permission.POST_NOTIFICATIONS"
```

**해결**:
- 앱 완전 삭제 후 재설치
- 또는 설정 > 앱 > Wefilling > 권한 > 알림 확인

#### 🔴 알림이 표시되지 않음

**체크리스트**:
1. [ ] 토큰이 생성되었는가?
2. [ ] 알림 권한이 허용되었는가?
3. [ ] 알림 채널이 생성되었는가?
4. [ ] 서버에서 올바른 형식으로 전송했는가?

**로그 확인**:
```bash
# FCM 메시지 수신 확인
adb logcat | grep "포어그라운드 메시지 수신"
adb logcat | grep "백그라운드에서 앱 열림"
```

**알림 채널 확인**:
```
설정 > 앱 > Wefilling > 알림
- "High Importance Notifications" 채널 활성화 확인
- "Meetup Notifications" 채널 활성화 확인
```

#### 🔴 백그라운드/종료 상태에서만 안 옴

**원인**:
- `firebaseMessagingBackgroundHandler` 등록 누락
- ProGuard가 FCM 클래스 제거

**확인**:
```bash
# main.dart 확인
grep "onBackgroundMessage" lib/main.dart

# ProGuard 규칙 확인
cat android/app/proguard-rules.pro | grep "firebase.messaging"
```

**해결**:
- 이미 수정됨 (main.dart 143번째 줄)
- ProGuard 규칙 이미 추가됨

## 🎯 성공 기준

### ✅ 모든 시나리오에서 알림이 정상 작동

1. **포그라운드**: 로컬 알림 배너 표시
2. **백그라운드**: 알림 트레이 표시 + 클릭 시 앱 열림
3. **종료 상태**: 알림 트레이 표시 + 클릭 시 앱 열림

### ✅ 로그 확인

```
🔥 FCM 토큰 생성 완료: abcd1234...
✅ Android 알림 권한 허용됨
✅ FCM 토큰 서버 저장 완료
🎉 푸시 알림 시스템 준비 완료!
```

## 📊 디버깅 명령어 모음

```bash
# 1. 앱 완전 삭제
adb uninstall com.wefilling.app

# 2. APK 설치
adb install build/app/outputs/flutter-apk/app-release.apk

# 3. 앱 실행
adb shell am start -n com.wefilling.app/com.wefilling.app.MainActivity

# 4. 로그 모니터링
adb logcat | grep -E "FCM|firebase|notification|알림|토큰"

# 5. 권한 확인
adb shell dumpsys package com.wefilling.app | grep "android.permission.POST_NOTIFICATIONS"

# 6. 알림 채널 확인
adb shell dumpsys notification | grep "wefilling"

# 7. FCM 토큰 확인 (앱 내에서 출력)
adb logcat | grep "FCM 토큰"

# 8. 앱 강제 종료 (테스트용 - 실제로는 사용 X)
adb shell am force-stop com.wefilling.app
```

## 🔧 추가 팁

### Android Studio에서는 되는데 APK에서 안 되는 이유

1. **Debug vs Release 빌드 차이**
   - Debug: 권한이 이미 허용된 상태
   - Release: 처음 설치 시 권한 요청 필요

2. **ProGuard 코드 난독화**
   - Release 빌드는 ProGuard가 적용됨
   - FCM 관련 클래스가 제거될 수 있음
   - → 이미 proguard-rules.pro에서 보존 처리됨

3. **Firebase 초기화 타이밍**
   - Debug: 느린 시작으로 충분한 초기화 시간
   - Release: 빠른 시작으로 타이밍 이슈 가능
   - → main.dart에서 조기 초기화 추가됨

### 실제 사용자 환경 테스트

```bash
# 1. 앱 완전 삭제
adb uninstall com.wefilling.app

# 2. APK 설치
adb install build/app/outputs/flutter-apk/app-release.apk

# 3. 앱 실행 (사용자처럼)
# - 기기에서 직접 앱 아이콘 클릭
# - 회원가입/로그인
# - 알림 권한 허용

# 4. 테스트
# - 다른 계정으로 댓글/좋아요
# - 모임 참여
# - DM 전송
```

## 📝 체크리스트

### 빌드 전
- [ ] `flutter clean` 실행
- [ ] `flutter pub get` 실행
- [ ] `google-services.json` 존재 확인
- [ ] ProGuard 규칙 확인

### 빌드
- [ ] `flutter build apk --release` 성공
- [ ] APK 파일 생성 확인

### 설치
- [ ] 기존 앱 완전 삭제
- [ ] 새 APK 설치
- [ ] 로그 모니터링 시작

### 테스트
- [ ] 앱 시작 시 FCM 토큰 생성 로그 확인
- [ ] 로그인 후 FCM 초기화 로그 확인
- [ ] 알림 권한 팝업 확인 (Android 13+)
- [ ] 포그라운드 알림 테스트
- [ ] 백그라운드 알림 테스트
- [ ] 종료 상태 알림 테스트

### 성공 확인
- [ ] 모든 시나리오에서 알림 수신
- [ ] 알림 클릭 시 올바른 화면 이동
- [ ] 로그에 에러 없음

## 🎉 완료!

모든 테스트가 통과하면 APK 푸시 알림이 정상 작동하는 것입니다!
