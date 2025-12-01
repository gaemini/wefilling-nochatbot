# displayName-nickname 동기화 가이드

## 🎯 목적
Firestore의 `users` 컬렉션에서 `displayName`과 `nickname` 필드를 동기화하여 일관성을 유지합니다.

## ✅ 이미 완료된 작업

### 1. 코드 수정 완료
- `lib/providers/auth_provider.dart` 수정
  - `updateUserProfile()`: nickname 업데이트 시 displayName도 함께 동기화
  - `updateNickname()`: nickname 업데이트 시 displayName도 함께 동기화

### 2. 앞으로의 동작
앞으로 사용자가 닉네임을 변경하면:
```dart
// 자동으로 displayName도 nickname과 동일하게 설정됨
{
  'nickname': '새로운닉네임',
  'displayName': '새로운닉네임',  // ✅ 자동 동기화
  'updatedAt': FieldValue.serverTimestamp()
}
```

## 🔄 기존 사용자 데이터 동기화

기존 사용자들의 `displayName`을 `nickname`과 동기화하려면 아래 두 가지 방법 중 하나를 선택하세요.

---

## 📋 방법 1: Firebase Console에서 실행 (추천)

### 단계:

1. **Firebase Console 접속**
   - https://console.firebase.google.com/
   - 프로젝트 선택: `flutterproject3-af322`

2. **Firestore Database로 이동**
   - 왼쪽 메뉴 > Firestore Database
   - 데이터 탭 클릭

3. **브라우저 개발자 도구 열기**
   - Windows/Linux: `F12` 또는 `Ctrl + Shift + I`
   - Mac: `Cmd + Option + I`

4. **Console 탭으로 이동**

5. **스크립트 복사 & 붙여넣기**
   - `scripts/sync_displayname_nickname.js` 파일 내용 전체 복사
   - Console에 붙여넣기
   - `Enter` 키 눌러 실행

6. **결과 확인**
   ```
   🎉 동기화 작업 완료!
   📊 처리 결과:
      ✅ 업데이트됨: X명
      ⏭️  건너뜀: Y명
      ❌ 오류: 0명
   ```

---

## 🚀 방법 2: Flutter 스크립트로 실행

### 전제조건:
- Flutter 개발 환경 설정 완료
- Firebase 프로젝트 연결 완료

### 실행 명령:
```bash
cd /Users/chajaemin/Desktop/wefilling-nochatbot
flutter run scripts/sync_displayname_nickname.dart
```

---

## ⚙️ 스크립트 동작 방식

### 처리 로직:
```javascript
모든 사용자 문서 순회:
  ├─ nickname이 없음 → ⚠️  건너뜀
  ├─ displayName == nickname → ✅ 건너뜀 (이미 동기화됨)
  └─ displayName != nickname → 🔄 displayName을 nickname으로 업데이트
```

### 배치 처리:
- 500개씩 배치로 처리하여 Firestore 할당량 초과 방지
- 안전한 트랜잭션 처리

### 업데이트 내용:
```javascript
{
  displayName: nickname,  // displayName을 nickname과 동일하게
  updatedAt: serverTimestamp()  // 업데이트 시간 기록
}
```

---

## 🔍 동기화 전/후 비교

### Before (동기화 전):
```json
{
  "userId": "abc123",
  "nickname": "정민지",
  "displayName": "Minji Jung",  // ❌ 불일치
  "email": "jmcha22@hanyang.ac.kr"
}
```

### After (동기화 후):
```json
{
  "userId": "abc123",
  "nickname": "정민지",
  "displayName": "정민지",  // ✅ 일치
  "email": "jmcha22@hanyang.ac.kr",
  "updatedAt": "2025-10-09T20:00:00Z"
}
```

---

## 📌 주의사항

### 1. 백업 권장
- 동기화 전 Firestore 데이터 백업 권장
- Firebase Console > Firestore Database > 내보내기

### 2. 실행 시점
- 사용자가 적은 시간대에 실행 권장
- 오전 3-5시 등 트래픽이 적은 시간

### 3. 재실행 가능
- 스크립트는 멱등성(idempotent)을 보장
- 여러 번 실행해도 안전함
- 이미 동기화된 사용자는 자동으로 건너뜀

### 4. 오류 발생 시
- 부분 실패 시 오류 로그 확인
- 스크립트 재실행으로 누락된 사용자 처리 가능

---

## 📊 예상 결과

### 샘플 출력:
```
🚀 displayName과 nickname 동기화 스크립트 시작
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 사용자 데이터 조회 중...
✅ 총 150명의 사용자 발견

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 동기화 작업 시작
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

👤 사용자 ID: TjZWjNW75dMqCG1j51QVD1GhXIP2
   현재 nickname: 정민지
   현재 displayName: Minji Jung
   🔄 업데이트 예정: displayName = "정민지"

👤 사용자 ID: CNAYONUHSVMUwowhnzrxIn82ELs2
   현재 nickname: 남평찬
   현재 displayName: 남평찬
   ✅ 건너뜀: 이미 동기화됨

...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💾 최종 배치 커밋 중... (73개 항목)
✅ 최종 배치 커밋 완료

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 동기화 작업 완료!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 처리 결과:
   ✅ 업데이트됨: 73명
   ⏭️  건너뜀: 77명
   ❌ 오류: 0명
   📋 총 사용자: 150명
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## ✨ 완료 후 확인

### 1. Firestore Console에서 확인
- users 컬렉션 > 임의의 문서 선택
- `displayName` 필드가 `nickname`과 동일한지 확인

### 2. 앱에서 확인
- 앱 재시작
- 댓글에 표시되는 닉네임이 정확한지 확인
- 프로필에 표시되는 이름이 정확한지 확인

---

## 🆘 문제 해결

### Q1: "firebase is not defined" 오류
- Firebase Console에서 실행하는지 확인
- Firestore Database 페이지에서 실행하는지 확인

### Q2: 권한 오류 발생
- Firebase Console에 로그인된 계정 확인
- 프로젝트 소유자 또는 편집자 권한 필요

### Q3: 일부 사용자만 업데이트됨
- 스크립트를 다시 실행하면 됨
- 이미 동기화된 사용자는 자동으로 건너뜀

---

## 📞 지원

문제가 발생하면 아래 정보와 함께 문의하세요:
- Firebase 프로젝트 ID: `flutterproject3-af322`
- 오류 메시지 (Console에서 복사)
- 실행 환경 (Firebase Console / Flutter)

