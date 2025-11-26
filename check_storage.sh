#!/bin/bash

echo "🔍 Firebase Storage 상태 확인 중..."
echo ""

# Firebase 프로젝트 ID
PROJECT_ID="flutterproject3-af322"
BUCKET_NAME="flutterproject3-af322.firebasestorage.app"

echo "📦 프로젝트: $PROJECT_ID"
echo "🗄️ 버킷: $BUCKET_NAME"
echo ""

# Storage 버킷 존재 확인
echo "1️⃣ Storage 버킷 접근 테스트..."
curl -s -I "https://firebasestorage.googleapis.com/v0/b/$BUCKET_NAME/o" | head -n 1

echo ""
echo "2️⃣ Firebase Console 링크:"
echo "   Storage: https://console.firebase.google.com/project/$PROJECT_ID/storage"
echo "   Firestore: https://console.firebase.google.com/project/$PROJECT_ID/firestore"
echo ""

echo "✅ 다음 단계:"
echo "   1. 위 Storage 링크로 접속"
echo "   2. posts/ 폴더에 이미지 파일이 있는지 확인"
echo "   3. 파일이 없으면 → 데이터 손실"
echo "   4. 파일이 있으면 → URL 형식 문제"
echo ""
