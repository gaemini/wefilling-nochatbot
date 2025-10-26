#!/bin/bash
# Gmail 앱 비밀번호 설정 스크립트

echo "==================================="
echo "Gmail 앱 비밀번호 설정"
echo "==================================="
echo ""
echo "1. https://myaccount.google.com/apppasswords 접속"
echo "2. hanyangwatson@gmail.com 로그인"
echo "3. 앱 비밀번호 생성 (이름: Wefilling)"
echo "4. 생성된 16자리 비밀번호 복사 (공백 제거)"
echo ""
read -p "생성한 16자리 비밀번호를 입력하세요 (공백 제거): " password

if [ -z "$password" ]; then
    echo "❌ 비밀번호가 입력되지 않았습니다."
    exit 1
fi

# 공백 제거
password=$(echo "$password" | tr -d ' ')

echo ""
echo "설정 중..."
firebase functions:config:set gmail.password="$password"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Gmail 비밀번호가 설정되었습니다."
    echo ""
    echo "설정 확인:"
    firebase functions:config:get
    echo ""
    read -p "Functions를 재배포하시겠습니까? (y/n): " deploy
    
    if [ "$deploy" = "y" ] || [ "$deploy" = "Y" ]; then
        echo ""
        echo "Functions 재배포 중..."
        firebase deploy --only functions:sendEmailVerificationCode,functions:verifyEmailCode
        echo ""
        echo "✅ 배포 완료! 이제 실제 이메일로 인증번호가 전송됩니다."
    else
        echo ""
        echo "⚠️  Functions 재배포가 필요합니다."
        echo "다음 명령어로 배포하세요:"
        echo "firebase deploy --only functions:sendEmailVerificationCode,functions:verifyEmailCode"
    fi
else
    echo "❌ 설정 실패"
    exit 1
fi






