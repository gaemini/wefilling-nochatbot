# 추천 장소 기능 설정 가이드

## 개요
카테고리별 추천 장소 기능이 추가되었습니다. 사용자가 모임 카테고리를 선택하면 해당 카테고리에 맞는 추천 장소가 표시되고, 선택 시 자동으로 Location 필드에 URL이 입력됩니다.

## Firebase 데이터 구조

```
recommended_places (컬렉션)
├── study (문서)
│   └── places: [
│       { name: "스터디 카페 1", url: "https://...", order: 1 },
│       { name: "스터디 카페 2", url: "https://...", order: 2 }
│     ]
├── meal (문서)
│   └── places: [...]
├── hobby (문서) // 카페 카테고리
│   └── places: [...]
├── culture (문서)
│   └── places: [...]
└── other (문서)
    └── places: []
```

## 초기 데이터 설정 방법

### 방법 1: Firebase Console에서 수동 설정 (권장)

1. Firebase Console 접속
2. Firestore Database 선택
3. `recommended_places` 컬렉션 생성
4. 각 카테고리별 문서 생성:
   - `study`
   - `meal`
   - `hobby`
   - `culture`
   - `other`
5. 각 문서에 `places` 필드 추가 (배열 타입)
6. 배열에 장소 객체 추가:
   ```json
   {
     "name": "장소 이름",
     "url": "네이버 지도 URL",
     "order": 1
   }
   ```

### 방법 2: 코드를 통한 자동 설정

앱 실행 시 한 번만 다음 코드를 실행하세요:

```dart
import 'package:wefilling/utils/firebase_setup_helper.dart';

// 앱 초기화 후 실행
await FirebaseSetupHelper.setupRecommendedPlaces();
```

**주의**: 이 메서드는 기존 데이터를 덮어씁니다. 한 번만 실행하세요.

## URL 관리

### URL 추가/수정
Firebase Console에서 직접 수정하거나, 다음 메서드를 사용할 수 있습니다:

```dart
await FirebaseSetupHelper.updateCategoryPlaces('study', [
  {
    'name': '새로운 스터디 카페',
    'url': 'https://map.naver.com/...',
    'order': 1,
  },
  // ... 더 많은 장소
]);
```

### 현재 설정된 URL

#### 스터디 (study)
1. 스터디 카페 1: https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/37762082?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071903&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98
2. 스터디 카페 2: https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/1083319174?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071903&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98

#### 식사 (meal)
1. 음식점 1: https://map.naver.com/p/search/%EC%9D%8C%EC%8B%9D%EC%A0%90/place/1647183115?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071902&locale=ko&svcName=map_pcv5&searchText=%EC%9D%8C%EC%8B%9D%EC%A0%90
2. 음식점 2: https://map.naver.com/p/search/%EC%9D%8C%EC%8B%9D%EC%A0%90/place/2020521950?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071902&locale=ko&svcName=map_pcv5&searchText=%EC%9D%8C%EC%8B%9D%EC%A0%90
3. 음식점 3: https://map.naver.com/p/search/%EC%9D%8C%EC%8B%9D%EC%A0%90/place/33657511?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071902&locale=ko&svcName=map_pcv5&searchText=%EC%9D%8C%EC%8B%9D%EC%A0%90

#### 카페 (hobby)
1. 카페 1: https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/33239471?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071901&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98
2. 카페 2: https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/1182416697?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071902&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98
3. 카페 3: https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/1114967069?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071902&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98

#### 문화 (culture)
1. 보드게임 카페: https://map.naver.com/p/search/%EB%B3%B4%EB%93%9C%EA%B2%8C%EC%9E%84/place/2078177472?c=13.66,0,0,0,dh&placePath=/home?from=map&fromPanelNum=2&timestamp=202512071903&locale=ko&svcName=map_pcv5&searchText=%EB%B3%B4%EB%93%9C%EA%B2%8C%EC%9E%84
2. 노래방: https://map.naver.com/p/search/%EB%85%B8%EB%9E%98%EB%B0%A9/place/1395923818?c=14.77,0,0,0,dh&placePath=/home?from=map&fromPanelNum=2&timestamp=202512071904&locale=ko&svcName=map_pcv5&searchText=%EB%85%B8%EB%9E%98%EB%B0%A9

#### 기타 (other)
- 현재 빈 배열 (추천 장소 없음)

## Firestore 보안 규칙

다음 규칙을 추가하여 모든 사용자가 추천 장소를 읽을 수 있도록 하세요:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // 추천 장소는 모든 사용자가 읽을 수 있음
    match /recommended_places/{category} {
      allow read: if true;
      // 쓰기는 관리자만 (Firebase Console에서 수동 관리)
      allow write: if false;
    }
  }
}
```

## 사용자 경험

1. 사용자가 카테고리 선택
2. 선택한 카테고리의 추천 장소가 자동으로 표시됨
3. 추천 장소 중 하나를 선택하면 Location 필드에 URL 자동 입력
4. "직접 입력" 옵션으로 수동 입력도 가능
5. 추천 장소가 없으면 "추천 장소가 없습니다" 메시지 표시

## 광고 관리

- URL은 광고 용도로 사용 가능
- Firebase Console에서 실시간으로 URL 변경 가능
- 앱 업데이트 없이 광고 링크 관리 가능
- order 필드로 표시 순서 조정 가능

## 테스트

1. 카테고리 선택 시 추천 장소 표시 확인
2. 추천 장소 선택 시 Location 필드 자동 입력 확인
3. 직접 입력 선택 시 필드 초기화 확인
4. Firebase 데이터 없을 시 에러 없이 빈 메시지 표시 확인
5. 모임 생성 시 URL이 정상적으로 저장되는지 확인

## 문제 해결

### 추천 장소가 표시되지 않음
- Firebase Console에서 데이터가 올바르게 설정되었는지 확인
- Firestore 보안 규칙에서 read 권한이 허용되었는지 확인
- 네트워크 연결 상태 확인

### 데이터 형식 오류
- 각 장소 객체에 name, url, order 필드가 모두 있는지 확인
- order는 숫자 타입이어야 함
- places는 배열 타입이어야 함

## 유지보수

- 정기적으로 URL이 유효한지 확인
- 계절별/이벤트별로 추천 장소 업데이트
- 사용자 피드백을 반영하여 장소 추가/제거
- Firebase Console에서 직접 관리하면 앱 재배포 불필요
