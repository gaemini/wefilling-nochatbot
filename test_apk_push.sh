#!/bin/bash

# APK 푸시 알림 테스트 스크립트
# 사용법: ./test_apk_push.sh

set -e

echo "🚀 APK 푸시 알림 테스트 시작"
echo ""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
PACKAGE_NAME="com.wefilling.app"

# 1단계: APK 파일 확인
echo -e "${BLUE}📦 1단계: APK 파일 확인${NC}"
if [ ! -f "$APK_PATH" ]; then
    echo -e "${RED}❌ APK 파일이 없습니다: $APK_PATH${NC}"
    echo -e "${YELLOW}💡 먼저 빌드하세요: flutter build apk --release${NC}"
    exit 1
fi
echo -e "${GREEN}✅ APK 파일 확인: $(ls -lh $APK_PATH | awk '{print $5}')${NC}"
echo ""

# 2단계: 기존 앱 완전 삭제
echo -e "${BLUE}🗑️  2단계: 기존 앱 완전 삭제${NC}"
adb uninstall $PACKAGE_NAME 2>/dev/null && echo -e "${GREEN}✅ 기존 앱 삭제 완료${NC}" || echo -e "${YELLOW}⚠️  기존 앱 없음 (정상)${NC}"
echo ""

# 3단계: 새 APK 설치
echo -e "${BLUE}📲 3단계: 새 APK 설치${NC}"
adb install $APK_PATH
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ APK 설치 완료${NC}"
else
    echo -e "${RED}❌ APK 설치 실패${NC}"
    exit 1
fi
echo ""

# 4단계: 로그 모니터링 시작
echo -e "${BLUE}📊 4단계: 로그 모니터링 시작${NC}"
echo -e "${YELLOW}💡 이제 기기에서 앱을 실행하세요!${NC}"
echo ""
echo -e "${GREEN}✅ 확인할 로그:${NC}"
echo "   🔍 현재 권한 상태: notDetermined (아직 안 물어봄)"
echo "   🔔 알림 권한 요청 중..."
echo "   ✅ 권한 요청 완료!"
echo "   🔔 최종 권한 상태: authorized"
echo "   🔥 FCM 토큰 생성 완료!"
echo ""
echo -e "${YELLOW}📱 로그 모니터링 중... (Ctrl+C로 종료)${NC}"
echo ""

# FCM 관련 로그만 필터링
adb logcat -c  # 기존 로그 클리어
adb logcat | grep --line-buffered -E "FCM|firebase|알림|토큰|권한|🔥|📱|✅|❌|🔔|🔍"
