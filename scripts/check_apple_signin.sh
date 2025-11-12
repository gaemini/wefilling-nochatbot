#!/bin/bash

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🍎 Apple Sign In 설정 확인 스크립트"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

PROJECT_FILE="ios/Runner.xcodeproj/project.pbxproj"
PODFILE="pubspec.yaml"

# 1. Xcode Capability 확인
echo "1️⃣ Xcode Capability 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -f "$PROJECT_FILE" ]; then
    if grep -q "com.apple.developer.applesignin" "$PROJECT_FILE"; then
        echo "✅ Sign in with Apple Capability가 추가되어 있습니다"
    elif grep -q "com.apple.SignIn" "$PROJECT_FILE"; then
        echo "✅ Sign in with Apple Capability가 추가되어 있습니다"
    else
        echo "❌ Sign in with Apple Capability가 없습니다"
        echo ""
        echo "   해결 방법:"
        echo "   1. open ios/Runner.xcworkspace"
        echo "   2. Runner 타겟 선택"
        echo "   3. Signing & Capabilities 탭"
        echo "   4. + Capability 클릭"
        echo "   5. 'Sign in with Apple' 추가"
        echo ""
    fi
else
    echo "⚠️  프로젝트 파일을 찾을 수 없습니다"
fi
echo ""

# 2. sign_in_with_apple 패키지 확인
echo "2️⃣ sign_in_with_apple 패키지 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -f "$PODFILE" ]; then
    if grep -q "sign_in_with_apple" "$PODFILE"; then
        VERSION=$(grep "sign_in_with_apple" "$PODFILE" | awk '{print $2}')
        echo "✅ sign_in_with_apple 패키지가 설치되어 있습니다"
        echo "   버전: $VERSION"
    else
        echo "❌ sign_in_with_apple 패키지가 없습니다"
        echo "   pubspec.yaml에 추가 필요"
    fi
else
    echo "⚠️  pubspec.yaml 파일을 찾을 수 없습니다"
fi
echo ""

# 3. Bundle ID 확인
echo "3️⃣ Bundle ID 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -f "$PROJECT_FILE" ]; then
    BUNDLE_ID=$(grep -A 1 "PRODUCT_BUNDLE_IDENTIFIER" "$PROJECT_FILE" | grep "com\." | head -1 | sed 's/.*= //;s/;//' | tr -d ' ')
    echo "Bundle ID: $BUNDLE_ID"
    echo ""
    echo "💡 Apple Developer Console에서 확인:"
    echo "   https://developer.apple.com/account/resources/identifiers/list"
    echo "   → 위 Bundle ID 선택 → Sign in with Apple 체크 확인"
else
    echo "⚠️  Bundle ID를 확인할 수 없습니다"
fi
echo ""

# 4. iOS 최소 버전 확인
echo "4️⃣ iOS 최소 버전 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -f "ios/Podfile" ]; then
    IOS_VERSION=$(grep "platform :ios" ios/Podfile | grep -o "[0-9.]*" | head -1)
    echo "iOS 최소 버전: $IOS_VERSION"
    
    # iOS 13.0 이상 필요
    REQUIRED="13.0"
    if [ "$(printf '%s\n' "$REQUIRED" "$IOS_VERSION" | sort -V | head -n1)" = "$REQUIRED" ]; then
        echo "✅ Apple Sign In 요구사항 충족 (iOS 13.0+)"
    else
        echo "⚠️  iOS 13.0 이상 필요 (현재: $IOS_VERSION)"
    fi
else
    echo "⚠️  Podfile을 찾을 수 없습니다"
fi
echo ""

# 5. Info.plist 권한 확인
echo "5️⃣ Info.plist 권한 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
INFO_PLIST="ios/Runner/Info.plist"
if [ -f "$INFO_PLIST" ]; then
    if grep -q "NSPhotoLibraryUsageDescription" "$INFO_PLIST"; then
        echo "✅ NSPhotoLibraryUsageDescription 존재"
    else
        echo "❌ NSPhotoLibraryUsageDescription 누락"
    fi
    
    if grep -q "NSCameraUsageDescription" "$INFO_PLIST"; then
        echo "✅ NSCameraUsageDescription 존재"
    else
        echo "❌ NSCameraUsageDescription 누락"
    fi
else
    echo "⚠️  Info.plist를 찾을 수 없습니다"
fi
echo ""

# 6. 종합 판정
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 종합 판정"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ISSUES=0

if ! grep -q "com.apple.developer.applesignin" "$PROJECT_FILE" 2>/dev/null && ! grep -q "com.apple.SignIn" "$PROJECT_FILE" 2>/dev/null; then
    echo "🔴 Xcode Capability 미추가 (가장 중요!)"
    ((ISSUES++))
fi

if ! grep -q "sign_in_with_apple" "$PODFILE" 2>/dev/null; then
    echo "🔴 sign_in_with_apple 패키지 미설치"
    ((ISSUES++))
fi

if [ $ISSUES -eq 0 ]; then
    echo "✅ 모든 필수 설정 완료"
    echo ""
    echo "💡 Apple Sign In이 작동하지 않는다면:"
    echo "   • 시뮬레이터: 설정 → Apple ID 로그인 확인"
    echo "   • 실제 iPhone에서 테스트 권장"
else
    echo ""
    echo "⚠️  $ISSUES개의 문제 발견 - 위 항목을 먼저 해결해주세요"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

