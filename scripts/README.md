# Firebase 추천 장소 설정 스크립트

## 사전 준비

### 1. Service Account Key 다운로드

1. Firebase Console 접속
2. 프로젝트 설정 > 서비스 계정
3. "새 비공개 키 생성" 클릭
4. 다운로드한 JSON 파일을 프로젝트 루트에 `serviceAccountKey.json`으로 저장

**중요**: `serviceAccountKey.json`은 절대 Git에 커밋하지 마세요!

### 2. Node.js 패키지 설치

```bash
cd scripts
npm install
```

## 사용 방법

### 추천 장소 데이터 설정

```bash
cd scripts
npm run setup-places
```

또는

```bash
cd scripts
node setup_recommended_places.js
```

## 실행 결과

스크립트가 성공적으로 실행되면 다음과 같은 출력을 볼 수 있습니다:

```
🚀 추천 장소 데이터 설정 시작...

✅ 스터디 카테고리 설정 완료
✅ 식사 카테고리 설정 완료
✅ 카페 카테고리 설정 완료
✅ 문화 카테고리 설정 완료
✅ 기타 카테고리 설정 완료

🎉 모든 추천 장소 데이터 설정 완료!

📋 설정된 데이터 확인:

study: 2개의 장소
meal: 3개의 장소
hobby: 3개의 장소
culture: 2개의 장소
other: 0개의 장소
```

## 설정되는 데이터

### 스터디 (study)
- 스터디 카페 1
- 스터디 카페 2

### 식사 (meal)
- 음식점 1
- 음식점 2
- 음식점 3

### 카페 (hobby)
- 카페 1
- 카페 2
- 카페 3

### 문화 (culture)
- 보드게임 카페
- 노래방

### 기타 (other)
- (빈 배열)

## 문제 해결

### "Cannot find module 'firebase-admin'"
```bash
cd scripts
npm install
```

### "serviceAccountKey.json not found"
Firebase Console에서 Service Account Key를 다운로드하고 프로젝트 루트에 저장하세요.

### 권한 오류
Service Account에 Firestore 쓰기 권한이 있는지 확인하세요.

## 주의사항

- 이 스크립트는 기존 데이터를 덮어씁니다
- 프로덕션 환경에서 실행하기 전에 백업을 권장합니다
- Service Account Key는 절대 공개하지 마세요
