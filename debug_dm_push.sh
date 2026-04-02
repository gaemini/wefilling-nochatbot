#!/bin/bash

# DM 푸시 알림 디버깅 스크립트
# 사용법: ./debug_dm_push.sh

echo "🔍 DM 푸시 알림 디버깅 시작"
echo ""

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PACKAGE_NAME="com.wefilling.app"

echo -e "${BLUE}📱 1단계: 앱 실행 상태 확인${NC}"
adb shell pidof $PACKAGE_NAME > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ 앱이 실행 중입니다${NC}"
else
    echo -e "${RED}❌ 앱이 실행되지 않았습니다${NC}"
    echo -e "${YELLOW}💡 먼저 앱을 실행하고 로그인하세요${NC}"
    exit 1
fi
echo ""

echo -e "${BLUE}🔑 2단계: FCM 토큰 확인${NC}"
echo -e "${YELLOW}💡 로그에서 다음을 확인하세요:${NC}"
echo "   - ✅ FCM 토큰 생성 성공!"
echo "   - 📱 토큰 (앞 20자): ..."
echo "   - ✅ FCM 토큰 서버 저장 완료"
echo ""

echo -e "${BLUE}📊 3단계: 로그 모니터링 (Ctrl+C로 종료)${NC}"
echo ""

# 로그 클리어 후 모니터링
adb logcat -c
adb logcat | grep --line-buffered -E "FCM|토큰|DM|dm_received|📨|🔥|✅|❌|⚠️"
