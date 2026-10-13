# 프로필 링크 웹 파일 (`https://wefilling.app/u/{uid}`)

도메인 `wefilling.app` 루트에 아래 구조 그대로 배포한다.

```
/.well-known/assetlinks.json              # Android App Links (Content-Type: application/json)
/.well-known/apple-app-site-association   # iOS Universal Links (확장자 없음, application/json)
/u/index.html                             # 모든 /u/* 요청을 이 파일로 rewrite
```

## 배포 전에 채울 값
- `assetlinks.json` — `REPLACE_WITH_*` 두 개: 릴리스 키스토어 SHA-256, Play 앱 서명 SHA-256
  (`keytool -list -v -keystore <keystore>` / Play Console → 앱 무결성).
- `apple-app-site-association` — Team ID `ULTS66B6QD`(프로젝트 설정에서 확인), 번들 `com.wefilling.app`.
- `u/index.html` — App Store 링크의 `id0000000000`을 실제 앱 ID로 교체.

## 앱 쪽 설정
- Android: `AndroidManifest.xml`의 `autoVerify` intent-filter (`https://wefilling.app/u/*`), `wefilling://u/{uid}`.
- iOS: 각 entitlements의 `applinks:wefilling.app` (Xcode에서 Associated Domains capability 확인).
- 링크 해석: `lib/services/profile_link.dart`.
