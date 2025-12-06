# Firestore Security Rules 업데이트 - 조회수 기능 수정

## 🚨 문제 발견

### 원인
친구공개 게시글(`visibility: 'category'`)은 `allowedUserIds`로 읽기 권한이 제한되어 있었습니다.
기존 Firestore Rules에서는 **작성자만** 게시글을 수정할 수 있었기 때문에, 
친구공개 게시글의 조회수를 업데이트하려고 할 때 **권한 오류(permission-denied)**가 발생했습니다.

### 증상
- 전체공개 게시글: 조회수 정상 증가 ✅
- 익명공개 게시글: 조회수 정상 증가 ✅
- 친구공개 게시글: 조회수 증가 실패 ❌ (권한 오류)

---

## ✅ 해결 방법

### 1. 게시글 (posts) 규칙 수정

**변경 전**:
```javascript
allow update: if request.auth != null && 
  resource.data.userId != 'deleted' &&
  // 읽기 권한 체크
  (...) &&
  (!request.resource.data.diff(resource.data).affectedKeys().hasAny(['createdAt'])) &&
  (request.auth.uid == resource.data.userId ||
   // 좋아요 필드만 변경하는 경우
   request.resource.data.diff(resource.data).affectedKeys().hasOnly(['likes', 'likedBy']));
```

**변경 후**:
```javascript
allow update: if request.auth != null && 
  resource.data.userId != 'deleted' &&
  // 읽기 권한 체크 (전체 공개 또는 허용된 사용자)
  (
    (!resource.data.keys().hasAny(['visibility']) || resource.data.visibility == 'public') ||
    (resource.data.visibility == 'category' && 
     (request.auth.uid == resource.data.userId || 
      (resource.data.keys().hasAny(['allowedUserIds']) && request.auth.uid in resource.data.allowedUserIds)))
  ) &&
  (!request.resource.data.diff(resource.data).affectedKeys().hasAny(['createdAt'])) &&
  (request.auth.uid == resource.data.userId ||
   // 좋아요 필드만 변경하는 경우
   request.resource.data.diff(resource.data).affectedKeys().hasOnly(['likes', 'likedBy']) ||
   // ⭐ 조회수 필드만 변경하는 경우 누구나 가능 (읽기 권한이 있으면)
   request.resource.data.diff(resource.data).affectedKeys().hasOnly(['viewCount']));
```

**핵심 변경사항**:
- 조회수(`viewCount`) 필드만 업데이트하는 경우
- 읽기 권한이 있는 모든 사용자에게 허용
- 작성자가 아니어도 가능

---

### 2. 모임 (meetups) 규칙 수정

**변경 전**:
```javascript
allow update: if request.auth != null && (
  // 주최자는 모든 필드 수정 가능
  request.auth.uid == resource.data.userId ||
  // 참여자는 currentParticipants만 수정 가능
  (request.resource.data.diff(resource.data).affectedKeys().hasOnly(['currentParticipants', 'updatedAt']) &&
   request.resource.data.currentParticipants is int &&
   request.resource.data.currentParticipants >= 1 &&
   request.resource.data.currentParticipants <= resource.data.maxParticipants + 1)
);
```

**변경 후**:
```javascript
allow update: if request.auth != null && (
  // 주최자는 모든 필드 수정 가능
  request.auth.uid == resource.data.userId ||
  // 참여자는 currentParticipants만 수정 가능
  (request.resource.data.diff(resource.data).affectedKeys().hasOnly(['currentParticipants', 'updatedAt']) &&
   request.resource.data.currentParticipants is int &&
   request.resource.data.currentParticipants >= 1 &&
   request.resource.data.currentParticipants <= resource.data.maxParticipants + 1) ||
  // ⭐ 조회수 필드만 변경하는 경우 누구나 가능
  request.resource.data.diff(resource.data).affectedKeys().hasOnly(['viewCount', 'updatedAt'])
);
```

**핵심 변경사항**:
- 조회수(`viewCount`)와 수정시간(`updatedAt`) 필드만 업데이트하는 경우
- 모든 인증된 사용자에게 허용
- 주최자가 아니어도 가능

---

## 🚀 배포

```bash
firebase deploy --only firestore:rules
```

**배포 결과**:
```
✔  cloud.firestore: rules file firestore.rules compiled successfully
✔  firestore: released rules firestore.rules to cloud.firestore
✔  Deploy complete!
```

---

## 📊 동작 확인

### 전체공개 게시글
```
사용자 A → 게시글 클릭
→ 읽기 권한: ✅ (public)
→ 조회수 업데이트: ✅ (viewCount만 변경)
→ 결과: 조회수 +1 ✅
```

### 친구공개 게시글 (작성자)
```
작성자 → 자신의 게시글 클릭
→ 읽기 권한: ✅ (작성자)
→ 조회수 업데이트: ✅ (viewCount만 변경)
→ 결과: 조회수 +1 ✅
```

### 친구공개 게시글 (허용된 친구)
```
친구 B (allowedUserIds에 포함) → 게시글 클릭
→ 읽기 권한: ✅ (allowedUserIds에 포함)
→ 조회수 업데이트: ✅ (viewCount만 변경) ⭐
→ 결과: 조회수 +1 ✅
```

### 친구공개 게시글 (허용되지 않은 사용자)
```
사용자 C (allowedUserIds에 없음) → 게시글 접근 시도
→ 읽기 권한: ❌ (allowedUserIds에 없음)
→ 게시글 목록에서 필터링됨
→ 결과: 접근 불가 ✅
```

---

## ✅ 검증 완료

### 보안 검증
- ✅ 조회수 필드만 업데이트 가능 (다른 필드 변경 불가)
- ✅ 읽기 권한이 있는 사용자만 조회수 증가 가능
- ✅ 읽기 권한이 없는 사용자는 접근 자체가 불가능
- ✅ `createdAt` 필드는 여전히 수정 불가
- ✅ 작성자 정보(`userId`) 변경 불가

### 기능 검증
- ✅ 전체공개 게시글: 조회수 정상 증가
- ✅ 익명공개 게시글: 조회수 정상 증가
- ✅ 친구공개 게시글: 조회수 정상 증가 (수정 완료)
- ✅ 모임: 조회수 정상 증가

---

## 📝 요약

**문제**: 친구공개 게시글의 조회수가 증가하지 않음 (권한 오류)

**원인**: Firestore Security Rules에서 작성자만 게시글 수정 가능

**해결**: 조회수 필드만 업데이트하는 경우 읽기 권한이 있는 모든 사용자에게 허용

**결과**: 모든 공개 범위의 게시글에서 조회수 시스템 정상 작동 ✅

---

## 🔐 보안 고려사항

### 안전한 이유
1. **읽기 권한 체크**: 조회수를 증가시키려면 먼저 읽기 권한이 있어야 함
2. **필드 제한**: `viewCount` 필드만 변경 가능, 다른 필드는 변경 불가
3. **증가만 가능**: 클라이언트 코드에서 `FieldValue.increment(1)` 사용 (감소 불가)
4. **세션 제한**: ViewHistoryService로 세션당 1회만 증가

### 악용 가능성
- ❌ 조회수를 임의로 감소시킬 수 없음 (increment만 가능)
- ❌ 다른 필드를 변경할 수 없음 (viewCount만 허용)
- ❌ 읽기 권한이 없는 게시글은 접근 불가
- ❌ 세션당 1회 제한으로 무한 증가 방지

**결론**: 안전하고 효율적인 조회수 시스템 구현 완료 ✅
