# 프로필 링크 웹 파일

공유 링크: `https://flutterproject3-af322.web.app/u/{uid}` (Firebase Hosting 기본 도메인).
파일은 `hosting/profile_link/`에 있고, `firebase.json`의 `hosting` 설정으로 배포한다.

```
firebase deploy --only hosting --project flutterproject3-af322
```

## 확인/채울 값
- `assetlinks.json`: Play 앱 서명 키, 업로드 키(KEYSTORE_STATUS.md), 디버그 키 SHA-256이 들어 있다.
  **Play 앱 서명을 쓰면 Play Console → 앱 무결성의 "앱 서명 키" SHA-256도 추가해야** 스토어 설치본에서 링크가 앱으로 바로 열린다.
- `apple-app-site-association`: Team ID `ULTS66B6QD`, 번들 `com.wefilling.app`.
- 도메인을 `wefilling.app`으로 옮기면 같은 폴더를 그 도메인 루트에 배포하고, `lib/services/profile_link.dart`의 `webHost`를 바꾼다(두 도메인 모두 수신은 된다).

## 앱 쪽
- Android `autoVerify` intent-filter, iOS `applinks:` entitlement, 수신: `lib/services/profile_link.dart`.
- 로그인·가입 완료 전에 받은 링크는 보관했다가 메인 화면이 준비되면 연다.
