# Wefilling 회원가입 및 로그인 메커니즘 문서

## 📋 목차
1. [개요](#개요)
2. [회원가입 프로세스](#회원가입-프로세스)
3. [로그인 프로세스](#로그인-프로세스)
4. [비회원 로그인 거부 메커니즘](#비회원-로그인-거부-메커니즘)
5. [회원 탈퇴 처리](#회원-탈퇴-처리)
6. [탈퇴 후 재가입 독립성](#탈퇴-후-재가입-독립성)
7. [Firebase 보안 규칙](#firebase-보안-규칙)
8. [핵심 코드 구조](#핵심-코드-구조)
9. [상태 비교표](#상태-비교표)

---

## 개요

Wefilling은 한양대학교 학생 전용 커뮤니티 앱으로, **한양메일 인증**을 통해서만 회원가입이 가능합니다. 비회원의 무단 로그인을 차단하면서도, 탈퇴한 사용자의 게시글은 익명 처리하여 대화 맥락을 유지하는 시스템입니다.

### 주요 특징
- ✅ 한양메일 인증 필수
- ✅ Google 계정 연동
- ✅ 비회원 로그인 거부 (회원가입은 가능)
- ✅ 탈퇴 후 게시글 맥락 유지 (Deleted로 표시)
- ✅ 재가입 가능 (과거 활동과 독립적)

---

## 회원가입 프로세스

### 전체 흐름

```
로그인 화면
    ↓
"회원가입하기" 버튼
    ↓
한양메일 인증 화면
    ↓
① 한양메일 입력
    ↓
② 인증번호 전송
    ↓
③ 인증번호 입력 및 확인
    ↓
④ Google 계정 연동
    ↓
⑤ Firestore 사용자 문서 생성
    ↓
닉네임 설정 화면
    ↓
메인 화면 (회원가입 완료)
```

### 상세 단계

#### 1단계: 한양메일 인증

**화면**: `HanyangEmailVerificationScreen`

```dart
// 사용자 입력
한양메일: student@hanyang.ac.kr
```

**처리**:
- Cloud Functions `sendEmailVerificationCode` 호출
- 4자리 랜덤 인증번호 생성
- 이메일로 전송
- Firestore `email_verifications` 컬렉션에 저장 (5분 유효)

#### 2단계: 인증번호 확인

```dart
// 사용자 입력
인증번호: 1234
```

**처리**:
- Cloud Functions `verifyEmailCode` 호출
- 코드 일치 여부 확인
- 성공 시 다음 단계 진행

#### 3단계: Google 계정 연동

**처리**:
```dart
// AuthProvider.signInWithGoogle()
await _googleSignIn.authenticate();
await _auth.signInWithCredential(credential);
```

#### 4단계: 사용자 문서 생성

**위치**: `AuthProvider.completeEmailVerification()`

```dart
await _firestore.collection('users').doc(_user!.uid).set({
  'uid': _user!.uid,
  'email': _user!.email,
  'displayName': _user!.displayName ?? '',
  'photoURL': _user!.photoURL ?? '',
  'nickname': '',
  'emailVerified': true,      // ⭐ 핵심 필드
  'hanyangEmail': hanyangEmail,
  'createdAt': FieldValue.serverTimestamp(),
  'lastLogin': FieldValue.serverTimestamp(),
});
```

#### 5단계: 닉네임 설정

**화면**: `NicknameSetupScreen`

```dart
// 사용자 입력
닉네임: 홍길동
국적: 한국

// 업데이트
await authProvider.updateUserProfile(
  nickname: nickname,
  nationality: nationality,
);
```

---

## 로그인 프로세스

### 기존 회원 로그인 흐름

```
로그인 화면
    ↓
"구글 계정으로 로그인" 버튼
    ↓
Google 인증
    ↓
Firestore 문서 확인
    ↓
[분기점]
├─ 문서 없음 → ❌ 차단
├─ emailVerified != true → ❌ 차단
└─ 정상 회원 → ✅ 로그인 성공
       ↓
   [분기점]
   ├─ 닉네임 없음 → 닉네임 설정 화면
   └─ 닉네임 있음 → 메인 화면
```

### 차단 로직

**위치**: `AuthProvider.signInWithGoogle()`

```dart
// 1. Firestore 문서 확인
final docSnapshot = await _firestore
    .collection('users')
    .doc(_user!.uid)
    .get();

// [차단 포인트 1] 문서 없음
if (!docSnapshot.exists) {
  print('❌ 신규 사용자: 회원가입이 필요합니다.');
  await _googleSignIn.signOut();
  await _auth.signOut();
  return false; // 차단
}

// [차단 포인트 2] 한양메일 미인증
final userData = docSnapshot.data();
if (userData?['emailVerified'] != true) {
  print('❌ 한양메일 인증이 완료되지 않았습니다.');
  await _googleSignIn.signOut();
  await _auth.signOut();
  return false; // 차단
}

// 정상 회원 처리
await _updateExistingUserDocument();
await _loadUserData();
return true; // 로그인 성공
```

---

## 비회원 로그인 거부 메커니즘

> **중요**: "거부"는 로그인을 거부하는 것이지, 회원가입을 막는 것이 아닙니다. 비회원은 정상적인 회원가입 절차(한양메일 인증 → Google 연동)를 거치면 로그인할 수 있습니다.

### 비회원 정의

#### A. 새로운 사용자
```
Firebase Auth: ❌ 없음
Firestore users: ❌ 없음
게시글/댓글: ❌ 없음
```

#### B. 탈퇴한 사용자
```
Firebase Auth: ❌ 삭제됨
Firestore users: ❌ 삭제됨
게시글/댓글: ✅ 익명 처리됨
```

### 로그인 거부 시나리오

#### 시나리오 1: 새로운 사용자

```
1. "구글 계정으로 로그인" 클릭
2. Google 인증 성공 (Firebase Auth 생성)
3. Firestore 확인: docSnapshot.exists == false
4. 즉시 로그아웃 처리
5. "회원가입이 필요합니다" 메시지 표시
→ 로그인 거부 ✅

해결 방법:
→ "회원가입하기" 버튼 클릭
→ 한양메일 인증 절차 진행
→ 정상 회원가입 후 로그인 가능
```

#### 시나리오 2: 탈퇴한 사용자

```
[배경]
- 과거 회원가입 및 활동
- deleteAccountImmediately로 탈퇴
  * users 문서 삭제
  * Auth 계정 삭제
  * 게시글은 익명 처리 (userId='deleted', authorNickname='Deleted')

[재로그인 시도]
1. 동일 Google 계정으로 "구글 계정으로 로그인" 클릭
2. Google 인증 성공 (새 Auth 생성, 새로운 UID 부여)
3. Firestore 확인: docSnapshot.exists == false (탈퇴로 삭제됨)
4. 즉시 로그아웃 처리
5. "회원가입이 필요합니다" 메시지 표시
→ 로그인 거부 ✅

해결 방법:
→ "회원가입하기" 버튼 클릭
→ 한양메일 재인증 절차 진행
→ 새로운 계정으로 회원가입 (과거 활동과 독립적)
→ 과거 게시글(userId='deleted')과는 연결되지 않음
```

---

## 회원 탈퇴 처리

### 탈퇴 방식

**Cloud Functions**: `deleteAccountImmediately`

**위치**: `functions/src/index.ts`

### 처리 내역

#### 1. 게시글 익명 처리 (삭제하지 않음)

```typescript
const postsSnap = await db.collection('posts')
  .where('userId', '==', uid)
  .get();

postsSnap.forEach((doc) => {
  batch.update(doc.ref, {
    userId: 'deleted',              // ⭐ 특수 값 (과거 UID와 분리)
    authorNickname: 'Deleted',      // ⭐ 한/영 모두 "Deleted"로 통일
    authorPhotoURL: '',
    updatedAt: serverTimestamp(),
  });
});
```

**표시 규칙**:
- 한국어 버전: "Deleted"
- 영어 버전: "Deleted"
- 일반 익명과 구분하기 위해 통일된 표시

#### 2. 댓글 익명 처리 (삭제하지 않음)

```typescript
const commentsSnap = await db.collection('comments')
  .where('userId', '==', uid)
  .get();

commentsSnap.forEach((doc) => {
  batch.update(doc.ref, {
    userId: 'deleted',              // ⭐ 특수 값 (과거 UID와 분리)
    authorNickname: 'Deleted',      // ⭐ 한/영 모두 "Deleted"로 통일
    authorPhotoUrl: '',
  });
});
```

#### 3. 개인 데이터 삭제

```typescript
// 모임 삭제
meetupsSnap.forEach((doc) => batch.delete(doc.ref));

// 친구 관계 삭제
friendships.forEach((doc) => batch.delete(doc.ref));

// 친구 요청 삭제
friendRequests.forEach((doc) => batch.delete(doc.ref));

// 차단 목록 삭제
blocks.forEach((doc) => batch.delete(doc.ref));

// 알림 삭제
notifications.forEach((doc) => batch.delete(doc.ref));

// 사용자 문서 삭제 ⭐
batch.delete(db.collection('users').doc(uid));
```

#### 4. Storage 파일 삭제

```typescript
const bucket = admin.storage().bucket();
await bucket.deleteFiles({ prefix: `profile_images/${uid}` });
await bucket.deleteFiles({ prefix: `post_images/${uid}` });
```

#### 5. Firebase Auth 계정 삭제

```typescript
await admin.auth().deleteUser(uid);
```

### 탈퇴 결과

| 항목 | 처리 방식 | 결과 |
|-----|---------|------|
| **사용자 문서** | 삭제 | ❌ 없음 |
| **Auth 계정** | 삭제 | ❌ 없음 |
| **게시글** | 익명 처리 | ✅ 유지 (작성자: Deleted, userId: 'deleted') |
| **댓글** | 익명 처리 | ✅ 유지 (작성자: Deleted, userId: 'deleted') |
| **모임** | 삭제 | ❌ 없음 |
| **친구 관계** | 삭제 | ❌ 없음 |
| **프로필 사진** | 삭제 | ❌ 없음 |
| **게시글 이미지** | 삭제 | ❌ 없음 |

### 재가입 시 처리

탈퇴한 사용자가 재가입하면:
- 새로운 Firebase Auth UID 부여 (과거 UID와 다름)
- 새로운 users 문서 생성
- **과거 게시글(userId='deleted')과 연결되지 않음** ⭐
- 완전히 새로운 사용자로 시작

### 탈퇴한 계정으로 로그인 시도 시 처리

탈퇴한 계정으로 로그인을 시도하면:

1. **로그인 단계**:
   - Firebase Auth 로그인은 성공 (Google 계정은 여전히 유효)
   - Firestore `users` 문서 확인 → 문서 없음 감지
   - 로그인 거부 및 회원가입 필요 안내 표시

2. **닉네임 설정 단계** (만약 로그인이 통과된 경우):
   - `updateUserProfile()` 메서드에서 문서 존재 여부 확인
   - 문서가 없으면 자동으로 새 문서 생성 (set 사용)
   - 문서가 있으면 기존 방식대로 업데이트 (update 사용)
   - 이를 통해 `not-found` 오류 방지

3. **사용자 안내**:
   - "회원가입이 필요합니다" 다이얼로그 표시
   - 신규 사용자 또는 탈퇴한 계정임을 명확히 안내
   - 한양메일 인증을 통한 회원가입 유도

---

## 탈퇴 후 재가입 독립성

### 독립성 보장 메커니즘

탈퇴한 사용자가 재가입할 때, 과거 활동과 완전히 독립되도록 설계되었습니다.

#### 1. UID 분리

```
[탈퇴 전]
userId: "abc123xyz"        // Firebase Auth UID
게시글: userId="abc123xyz"

[탈퇴 시]
Auth 계정 삭제
게시글: userId="deleted"   // 특수 값으로 변경

[재가입 시]
userId: "def456uvw"        // 새로운 Firebase Auth UID
→ 과거 게시글(userId="deleted")과 연결 불가 ✅
```

#### 2. 재가입 시 새 계정 생성

**회원가입 절차**:
```
1. "회원가입하기" 클릭
2. 한양메일 재인증 (필수)
3. Google 계정 연동
4. 새로운 Firebase Auth 계정 생성 (새 UID)
5. 새로운 Firestore users 문서 생성
6. 닉네임 설정
→ 완전히 새로운 사용자로 시작
```

#### 3. 과거 게시글과의 관계

| 구분 | 과거 게시글 | 재가입 후 |
|-----|-----------|----------|
| **userId** | 'deleted' | 새로운 UID |
| **authorNickname** | 'Deleted' | 새 닉네임 |
| **소유권** | 없음 | 새 게시글만 소유 |
| **수정/삭제** | 불가능 | 새 게시글만 가능 |

**결론**: 탈퇴 후 재가입한 사용자는 과거 게시글을 수정하거나 삭제할 수 없으며, 과거 활동 기록도 조회할 수 없습니다.

---

## Firebase 보안 규칙

### Firestore 보안 규칙

비회원 로그인 거부 및 권한 문제 방지를 위한 Firestore 보안 규칙:

#### 1. users 컬렉션 규칙

```javascript
match /users/{userId} {
  // 읽기: 인증된 사용자만
  allow read: if request.auth != null;
  
  // 생성: 회원가입 시 (본인 문서만, emailVerified 필수)
  allow create: if request.auth != null 
    && request.auth.uid == userId
    && request.resource.data.emailVerified == true
    && request.resource.data.hanyangEmail.matches('.*@hanyang.ac.kr$');
  
  // 수정: 본인 문서만
  allow update: if request.auth != null 
    && request.auth.uid == userId;
  
  // 삭제: 본인 문서만
  allow delete: if request.auth != null 
    && request.auth.uid == userId;
}
```

#### 2. posts 컬렉션 규칙

```javascript
match /posts/{postId} {
  // 읽기: 인증된 사용자만
  allow read: if request.auth != null;
  
  // 생성: 정회원만 (emailVerified 확인)
  allow create: if request.auth != null
    && exists(/databases/$(database)/documents/users/$(request.auth.uid))
    && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.emailVerified == true
    && request.resource.data.userId == request.auth.uid;
  
  // 수정: 본인 게시글만 (userId='deleted'는 수정 불가)
  allow update: if request.auth != null
    && resource.data.userId == request.auth.uid
    && resource.data.userId != 'deleted';
  
  // 삭제: 본인 게시글만 (userId='deleted'는 삭제 불가)
  allow delete: if request.auth != null
    && resource.data.userId == request.auth.uid
    && resource.data.userId != 'deleted';
}
```

#### 3. comments 컬렉션 규칙

```javascript
match /comments/{commentId} {
  // 읽기: 인증된 사용자만
  allow read: if request.auth != null;
  
  // 생성: 정회원만
  allow create: if request.auth != null
    && exists(/databases/$(database)/documents/users/$(request.auth.uid))
    && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.emailVerified == true
    && request.resource.data.userId == request.auth.uid;
  
  // 수정: 본인 댓글만 (userId='deleted'는 수정 불가)
  allow update: if request.auth != null
    && resource.data.userId == request.auth.uid
    && resource.data.userId != 'deleted';
  
  // 삭제: 본인 댓글만 (userId='deleted'는 삭제 불가)
  allow delete: if request.auth != null
    && resource.data.userId == request.auth.uid
    && resource.data.userId != 'deleted';
}
```

### 보안 규칙 핵심 포인트

#### 1. emailVerified 검증
- 모든 쓰기 작업(생성)에서 `emailVerified == true` 확인
- 비회원은 게시글/댓글 작성 불가

#### 2. userId='deleted' 보호
- 탈퇴한 사용자의 게시글/댓글 수정/삭제 방지
- 재가입한 사용자도 과거 게시글 수정 불가

#### 3. 한양메일 검증
- users 문서 생성 시 `@hanyang.ac.kr` 도메인 확인
- 회원가입 단계에서 이중 검증

#### 4. 읽기 권한
- 인증된 사용자만 데이터 읽기 가능
- 완전 비회원은 아무것도 볼 수 없음

### 권한 문제 방지

| 시나리오 | 동작 | 결과 |
|---------|------|------|
| **비회원이 게시글 작성 시도** | emailVerified 없음 | ❌ 거부 |
| **탈퇴 사용자 게시글 수정** | userId='deleted' | ❌ 거부 |
| **재가입 사용자가 과거 게시글 수정** | 다른 UID | ❌ 거부 |
| **정회원이 자신의 게시글 수정** | 모든 조건 충족 | ✅ 허용 |

---

## 핵심 코드 구조

### 파일 구조

```
lib/
├── providers/
│   └── auth_provider.dart          # 인증 상태 관리
├── services/
│   ├── auth_service.dart           # (사용 안 함)
│   └── account_deletion_service.dart
├── screens/
│   ├── login_screen.dart           # 로그인 화면
│   ├── hanyang_email_verification_screen.dart
│   ├── nickname_setup_screen.dart
│   └── account_delete_stepper_screen.dart

functions/
└── src/
    └── index.ts                    # Cloud Functions
```

### 주요 메서드

#### AuthProvider

```dart
class AuthProvider {
  // 회원가입 절차
  Future<Map<String, dynamic>> sendEmailVerificationCode(String email);
  Future<bool> verifyEmailCode(String email, String code);
  Future<bool> completeEmailVerification(String hanyangEmail);
  
  // 로그인 처리
  Future<bool> signInWithGoogle();
  
  // 내부 메서드
  Future<void> _updateExistingUserDocument();
  Future<void> _loadUserData();
}
```

#### Cloud Functions

```typescript
// 이메일 인증
export const sendEmailVerificationCode = ...
export const verifyEmailCode = ...

// 회원 탈퇴
export const deleteAccountImmediately = ...
```

---

## 상태 비교표

### 사용자 유형별 상태

| 사용자 유형 | Firebase Auth | Firestore users 문서 | emailVerified | 게시글/댓글 | 로그인 시도 | 재가입 |
|-----------|--------------|-------------------|---------------|-----------|-----------|--------|
| **신규 사용자** | ❌ 없음 | ❌ 없음 | - | ❌ 없음 | ❌ 거부 | ✅ 가능 |
| **회원가입 중** | ✅ 있음 | ✅ 있음 | ❌ false | ❌ 없음 | ❌ 거부 | - |
| **정회원** | ✅ 있음 | ✅ 있음 | ✅ true | ✅ 있음 | ✅ 성공 | - |
| **탈퇴한 사용자** | ❌ 삭제 | ❌ 삭제 | - | ✅ 익명 처리 (Deleted) | ❌ 거부 | ✅ 가능 (새 계정) |

### Firestore 문서 구조

#### users 컬렉션

```javascript
{
  uid: "firebase_auth_uid",
  email: "user@google.com",
  displayName: "홍길동",
  photoURL: "https://...",
  nickname: "홍길동",
  nationality: "한국",
  emailVerified: true,        // ⭐ 핵심
  hanyangEmail: "student@hanyang.ac.kr",
  createdAt: Timestamp,
  lastLogin: Timestamp
}
```

#### 탈퇴한 사용자의 게시글

```javascript
{
  postId: "post_id",
  userId: "deleted",          // ⭐ 특수 값 (실제 UID가 아님)
  authorNickname: "Deleted",  // ⭐ 한/영 모두 "Deleted"
  authorPhotoURL: "",
  title: "게시글 제목",
  content: "게시글 내용",    // 유지됨
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

**중요**: 
- `userId: "deleted"`는 실제 Firebase Auth UID가 아닌 특수 값입니다.
- 재가입한 사용자는 새로운 UID를 받으므로 이 게시글과 연결되지 않습니다.
- Firebase 보안 규칙에서 `userId == "deleted"`인 게시글은 수정/삭제가 차단됩니다.

---

## 보안 고려사항

### 1. 한양메일 인증 필수
- 한양대학교 학생만 가입 가능
- 이메일 인증 없이 Google 로그인만으로는 접근 불가

### 2. 로그인 거부 메커니즘
- Firestore 문서 존재 여부로 1차 거부
- `emailVerified` 필드로 2차 거부
- 거부 시 즉시 로그아웃 처리
- **회원가입 절차를 거치면 로그인 가능**

### 3. 재가입 방지 없음
- 탈퇴 후 재가입 가능 (의도된 동작)
- 재가입 시 한양메일 재인증 필요

### 4. 게시글 맥락 유지
- 탈퇴해도 게시글/댓글은 유지
- 커뮤니티 대화 흐름 보존
- "Deleted"로 표시하여 탈퇴 사용자 구분
- userId='deleted'로 변경하여 개인정보 보호

### 5. Firebase 보안 규칙
- emailVerified 필드로 정회원만 쓰기 권한
- userId='deleted' 게시글은 수정/삭제 불가
- 재가입 사용자도 과거 게시글 접근 불가
- 권한 문제 및 보안 이슈 방지

---

## 테스트 체크리스트

### 회원가입
- [ ] 한양메일 인증번호 전송
- [ ] 잘못된 인증번호 입력 시 오류
- [ ] Google 계정 연동
- [ ] Firestore 문서 생성 확인
- [ ] 닉네임 설정 완료

### 로그인
- [ ] 정회원 로그인 성공
- [ ] 신규 사용자 로그인 거부
- [ ] 탈퇴한 사용자 로그인 거부
- [ ] 한양메일 미인증 사용자 로그인 거부
- [ ] 거부된 사용자 회원가입 후 로그인 성공

### 탈퇴
- [ ] 게시글 "Deleted"로 표시 확인
- [ ] 댓글 "Deleted"로 표시 확인
- [ ] userId='deleted'로 변경 확인
- [ ] users 문서 삭제 확인
- [ ] Auth 계정 삭제 확인
- [ ] 재로그인 거부 확인

### 재가입
- [ ] 탈퇴 후 재가입 가능
- [ ] 새로운 UID 부여 확인
- [ ] 과거 게시글과 독립적 확인
- [ ] 과거 게시글 수정/삭제 불가 확인

### Firebase 보안
- [ ] emailVerified 검증 동작
- [ ] userId='deleted' 수정 차단
- [ ] 비회원 쓰기 권한 차단
- [ ] 권한 오류 없음

---

## 버전 정보

- **문서 작성일**: 2025-01-20
- **Flutter 버전**: 3.x
- **Firebase SDK**: 최신
- **작성자**: Wefilling 개발팀

---

## 문의

시스템 관련 문의사항이 있으시면 개발팀에 연락해주세요.

