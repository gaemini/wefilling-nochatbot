# 앱 아이콘(launcher icon) 관리 가이드

이 프로젝트는 **원본 아이콘(1024x1024) 1장만 관리**하고, 나머지 iOS/Android 아이콘 리소스는 `flutter_launcher_icons`로 **자동 생성**합니다.

## 원본 파일

- 원본(소스) 아이콘: `assets/app_icon/wefilling_app_icon_1024.png`
- 요구사항:
  - PNG
  - 1024×1024
  - 정사각형

## 생성 설정 위치

- 설정 파일: `pubspec.yaml`
- 설정 섹션: `flutter_launcher_icons`

## 아이콘 재생성 방법

프로젝트 루트에서 실행:

```bash
bash scripts/generate_app_icons.sh
```

또는 직접 실행:

```bash
flutter pub get
flutter pub run flutter_launcher_icons
```

## 반영 범위

- iOS: `ios/Runner/Assets.xcassets/AppIcon.appiconset/` 내부 PNG들(1024 포함)
- Android: `android/app/src/main/res/mipmap-*/` 및 `mipmap-anydpi-v26/` 등 런처 아이콘 리소스

## App Store에 실제로 보이게 하려면

아이콘 파일만 바꿔서는 App Store에 반영되지 않습니다. **새 iOS 빌드를 업로드**해야 하며, 일반적으로 build number를 증가시키고(App Store Connect 업로드) 새 버전을 배포해야 아이콘이 업데이트됩니다.

