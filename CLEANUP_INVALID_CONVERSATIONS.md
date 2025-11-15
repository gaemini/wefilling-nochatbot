# 잘못된 DM 대화방 정리 가이드

## 🐛 발견된 문제

### 1. 타임스탬프가 붙은 일반 친구 DM (삭제 필요)
```
❌ RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179637046
❌ RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179603825
❌ RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179414956
❌ RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179090748
```

**문제:** 일반 친구 DM인데 타임스탬프가 붙어있음 (익명 DM 형식)
**원인:** `prepareConversationId` 함수가 잘못 사용됨
**해결:** 이 대화방들을 삭제하고 정상 대화방만 유지

### 2. 본인 DM (삭제 필요)
```
❌ anon_RhftBT9OEyagkaPUtO9v35KPh8E3_RhftBT9OEyagkaPUtO9v35KPh8E3_ILe7K7vcpsYei3aWyzGS
```

**문제:** 같은 UID가 두 번 (본인에게 DM)
**원인:** 본인 DM 차단 로직 우회
**해결:** 삭제

### 3. 정상 대화방 (유지)
```
✅ RhftBT9OEyagkaPUtO9v35KPh8E3_TjZWjNW75dMqCG1j51QVD1GhXIP2
✅ CNAYONUHSVMUwowhnzrxIn82ELs2_RhftBT9OEyagkaPUtO9v35KPh8E3
✅ RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3
✅ RhftBT9OEyagkaPUtO9v35KPh8E3_mhHqtlUU6mYDBcwSOk4ZzOBs5CB2
```

**형식:** `uid1_uid2` (타임스탬프 없음)
**유지:** 이 대화방들은 정상

## 🔧 정리 방법

### 방법 1: Firebase Console에서 수동 삭제

1. **Firebase Console 접속**: https://console.firebase.google.com/
2. **Firestore Database** → `conversations` 컬렉션
3. **다음 문서들 삭제:**
   - `RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179637046`
   - `RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179603825`
   - `RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179414956`
   - `RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179090748`
   - `anon_RhftBT9OEyagkaPUtO9v35KPh8E3_RhftBT9OEyagkaPUtO9v35KPh8E3_ILe7K7vcpsYei3aWyzGS`

### 방법 2: 자동 정리 스크립트 (권장)

Firebase Console의 Firestore에서 다음 쿼리 실행:

```javascript
// 1. 타임스탬프가 붙은 일반 DM 찾기
db.collection('conversations')
  .where(firebase.firestore.FieldPath.documentId(), '>=', 'A')
  .where(firebase.firestore.FieldPath.documentId(), '<', 'anon')
  .get()
  .then(snapshot => {
    snapshot.docs.forEach(doc => {
      const id = doc.id;
      // uid1_uid2_숫자 형식 찾기
      const parts = id.split('_');
      if (parts.length === 3 && /^\d+$/.test(parts[2])) {
        console.log('삭제 대상:', id);
        // doc.ref.delete(); // 주석 해제하여 실제 삭제
      }
    });
  });

// 2. 본인 DM 찾기
db.collection('conversations')
  .get()
  .then(snapshot => {
    snapshot.docs.forEach(doc => {
      const data = doc.data();
      const participants = data.participants || [];
      if (participants.length === 2 && participants[0] === participants[1]) {
        console.log('본인 DM 삭제 대상:', doc.id);
        // doc.ref.delete(); // 주석 해제하여 실제 삭제
      }
    });
  });
```

## ✅ 정리 후 확인

### 1. 앱 재실행
```bash
flutter run
```

### 2. DM 목록 확인
- 중복 대화방이 사라졌는지 확인
- 각 친구당 1개의 대화방만 표시되는지 확인

### 3. 새 대화 시작
- 친구 목록에서 친구 선택
- 로그 확인:
  ```
  🔑 _generateConversationId 호출:
    - 생성된 일반 ID: uid1_uid2
  ```
- ✅ 타임스탬프가 없어야 함!

## 🎯 예상 결과

**정리 전:**
```
RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3  ✅
RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179637046  ❌
RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179603825  ❌
RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3_1762179414956  ❌
```

**정리 후:**
```
RhftBT9OEyagkaPUtO9v35KPh8E3_YAZPixVXuAhU7Glu7ny66L0uyiI3  ✅
```

## 📝 주의사항

1. **메시지 손실:** 타임스탬프가 붙은 대화방의 메시지는 삭제됩니다
2. **백업 권장:** 삭제 전 Firebase Console에서 Export 권장
3. **테스트:** 삭제 전 1-2개만 먼저 삭제해서 테스트

## 🚀 다음 단계

1. ✅ **코드 수정 완료** - `prepareConversationId` 수정됨
2. ⏳ **Firestore 정리** - 잘못된 대화방 삭제 필요
3. ⏳ **앱 재실행** - 정상 작동 확인
4. ⏳ **테스트** - 새 대화 시작하여 확인

지금 바로 Firebase Console에서 위 대화방들을 삭제하세요!

