# Firebase 광고 배너 설정 가이드

이 가이드는 Firebase Console에서 광고 배너를 설정하는 방법을 안내합니다.

## 📋 목차
1. [Firebase Storage에 이미지 업로드](#1-firebase-storage에-이미지-업로드)
2. [Firestore에 광고 데이터 추가](#2-firestore에-광고-데이터-추가)
3. [광고 관리 (추가/수정/삭제)](#3-광고-관리)

---

## 1. Firebase Storage에 이미지 업로드

### 1-1. Firebase Console 접속
1. [Firebase Console](https://console.firebase.google.com/) 접속
2. 프로젝트 선택
3. 좌측 메뉴에서 **Storage** 클릭

### 1-2. 폴더 구조 생성
```
storage/
└── ad_images/
    ├── eastern_moon_pub.jpg
    ├── banner_001.jpg
    └── banner_002.jpg
```

### 1-3. 이미지 업로드
1. Storage 페이지에서 **폴더 만들기** 클릭
2. 폴더명: `ad_images` 입력
3. `ad_images` 폴더 클릭
4. **파일 업로드** 버튼 클릭
5. 이스턴문 이미지 선택 (`easternmoon.png`)
6. 업로드 완료 후 이미지 클릭
7. **다운로드 URL** 복사 (나중에 사용)

**예시 URL:**
```
https://firebasestorage.googleapis.com/v0/b/YOUR_PROJECT.appspot.com/o/ad_images%2Feastern_moon_pub.jpg?alt=media&token=...
```

---

## 2. Firestore에 광고 데이터 추가

### 2-1. Firestore Database 접속
1. Firebase Console 좌측 메뉴에서 **Firestore Database** 클릭
2. **컬렉션 시작** 클릭

### 2-2. 컬렉션 생성
- **컬렉션 ID**: `ad_banners`

### 2-3. 광고 문서 추가

#### 광고 1: 한양대 에리카 국제처
**문서 ID**: `banner_001` (자동 생성 가능)

```json
{
  "id": "banner_001",
  "title": "한양대 에리카 국제처",
  "description": "교환학생 프로그램 및 국제 교류 정보",
  "url": "https://oia.hanyang.ac.kr/",
  "imageUrl": null,
  "isActive": true,
  "order": 1,
  "createdAt": [서버 타임스탬프],
  "updatedAt": [서버 타임스탬프]
}
```

**Firebase Console에서 입력:**
1. **문서 추가** 클릭
2. 각 필드 입력:
   - `id` (string): "banner_001"
   - `title` (string): "한양대 에리카 국제처"
   - `description` (string): "교환학생 프로그램 및 국제 교류 정보"
   - `url` (string): "https://oia.hanyang.ac.kr/"
   - `imageUrl` (null): null (비워두기)
   - `isActive` (boolean): true
   - `order` (number): 1
   - `createdAt` (timestamp): 현재 시간
   - `updatedAt` (timestamp): 현재 시간

#### 광고 2: 한양대 에리카 중앙동아리
**문서 ID**: `banner_002`

```json
{
  "id": "banner_002",
  "title": "한양대 에리카 중앙동아리",
  "description": "다양한 동아리 활동과 학생 커뮤니티",
  "url": "https://esc.hanyang.ac.kr/-29",
  "imageUrl": null,
  "isActive": true,
  "order": 2,
  "createdAt": [서버 타임스탬프],
  "updatedAt": [서버 타임스탬프]
}
```

#### 광고 3: 이스턴문 - 예술가의 아지트 카페 ⭐
**문서 ID**: `banner_003`

```json
{
  "id": "banner_003",
  "title": "이스턴문 - 예술가의 아지트 카페",
  "description": "한양대 숨은 명소, 직접 만든 시그니처 디저트와 콜드브루",
  "url": "https://map.naver.com/p/entry/place/1375980272?lng=126.8398484&lat=37.3007216&placePath=%2Fhome&entry=plt&searchType=place",
  "imageUrl": "https://firebasestorage.googleapis.com/v0/b/YOUR_PROJECT.appspot.com/o/ad_images%2Feastern_moon_pub.jpg?alt=media&token=...",
  "isActive": true,
  "order": 3,
  "createdAt": [서버 타임스탬프],
  "updatedAt": [서버 타임스탬프]
}
```

**주의:** `imageUrl`에는 위에서 복사한 Firebase Storage URL을 붙여넣으세요!

---

## 3. 광고 관리

### 새 광고 추가
1. Firestore Database > `ad_banners` 컬렉션
2. **문서 추가** 클릭
3. 위 형식에 맞춰 필드 입력
4. **저장**
5. 앱에서 즉시 반영됨! 🎉

### 광고 수정
1. 수정할 문서 클릭
2. 필드 값 수정
3. 앱에서 즉시 반영됨!

### 광고 비활성화
1. 해당 문서의 `isActive` 필드를 `false`로 변경
2. 앱에서 즉시 숨겨짐

### 광고 삭제
1. 문서 우측 메뉴 (⋮) 클릭
2. **문서 삭제** 선택

### 광고 순서 변경
1. 각 광고의 `order` 필드 값 변경
2. 작은 숫자가 먼저 표시됨

---

## 📱 실시간 업데이트

- Firebase를 사용하므로 **앱 재배포 없이** 광고를 변경할 수 있습니다
- Firestore에서 광고를 추가/수정/삭제하면 모든 사용자의 앱에서 **즉시 반영**됩니다
- 이미지도 Firebase Storage를 사용하므로 언제든지 교체 가능합니다

---

## 🔧 Firestore 보안 규칙

광고 데이터는 읽기 전용으로 설정하는 것을 권장합니다:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // 광고 배너는 모든 사용자가 읽을 수 있음
    match /ad_banners/{bannerId} {
      allow read: if true;  // 모든 사용자 읽기 가능
      allow write: if false; // 관리자만 수정 가능 (Console에서만)
    }
  }
}
```

---

## 📸 이미지 권장 사양

- **형식**: JPG, PNG, WebP
- **크기**: 800x600px ~ 1200x800px
- **용량**: 500KB 이하 권장
- **비율**: 4:3 또는 16:9

---

## ⚡ 빠른 시작

1. **이미지 업로드** (선택사항)
   - Storage > ad_images 폴더 생성
   - 이미지 업로드
   - URL 복사

2. **Firestore 데이터 추가**
   - Firestore > ad_banners 컬렉션 생성
   - 위 예시대로 문서 3개 추가

3. **앱 실행**
   ```bash
   flutter run
   ```

4. 완료! 🎉


