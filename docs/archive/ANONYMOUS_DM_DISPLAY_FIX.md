# 📝 익명 게시글 DM 표시명 수정 완료

## 🎯 요구사항

**게시글에서 시작된 익명 DM**: 게시글 본문으로 표시 (40자 제한)
**일반 익명 DM**: "Anonymous"로 표시

---

## 📊 현재 상황 분석

### 문제
- 게시글 기반 익명 DM이 "Anonymous"로 표시됨
- 원인: 이전 버전에서 생성된 대화방에는 `dmContent`가 없음

### 데이터 구조
```dart
conversation {
  postId: "xxx"           // ✅ 있음
  dmTitle: null           // ❌ 없음 (이전 버전)
  dmContent: null         // ❌ 없음 (이전 버전)
  lastMessage: "ㄴ그소"  // ✅ 있음
}
```

---

## ✅ 해결 방법

### **게시글 기반 판단 로직 개선**

#### Before
```dart
// dmContent 또는 dmTitle이 있어야만 게시글 기반으로 인식
final isPostBasedAnonymous = isAnonymous && (
  (dmContent != null && dmContent.isNotEmpty) || 
  (dmTitle != null && dmTitle.isNotEmpty)
);
```

#### After
```dart
// postId만 있어도 게시글 기반으로 인식
final isPostBasedAnonymous = isAnonymous && (
  (dmContent != null && dmContent.isNotEmpty) || 
  (dmTitle != null && dmTitle.isNotEmpty) ||
  (conversation.postId != null && conversation.postId!.isNotEmpty)  // 추가!
);
```

---

## 📋 표시 우선순위

### **게시글 기반 익명 DM (postId 있음)**

1. **게시글 본문** (`dmContent`)
   ```
   "같이 공부하실 분 구합니다. 장소는 한양대..." (40자)
   ```

2. **게시글 제목** (`dmTitle`)
   ```
   "제목: 스터디 모집"
   ```

3. **마지막 메시지** (`lastMessage`) - **폴백**
   ```
   "ㄴ그소" (40자 제한)
   ```
   - dmContent와 dmTitle이 둘 다 없을 때 (이전 버전 호환)

4. **"Anonymous"** - 메시지도 없을 때

### **일반 익명 DM (postId 없음)**
```
"Anonymous" 고정
```

---

## 🔍 디버그 로그

익명 대화방 데이터 확인:
```
🔍 익명 대화방 데이터:
  - ID: anon_...
  - dmTitle: null
  - dmContent: null
  - lastMessage: ㄴ그소
```

---

## 📱 예상 결과

| 대화방 타입 | dmContent | dmTitle | postId | 표시 |
|-----------|----------|---------|--------|------|
| 게시글 DM (새 버전) | ✅ 있음 | - | ✅ | "게시글 본문..." |
| 게시글 DM (이전 버전) | ❌ 없음 | ❌ 없음 | ✅ | "ㄴ그소" (마지막 메시지) |
| 게시글 DM (제목만) | ❌ | ✅ 있음 | ✅ | "제목: ..." |
| 일반 익명 DM | ❌ | ❌ | ❌ | "Anonymous" |

---

## 🎉 결과

**이전 버전에서 생성된 게시글 DM도 이제 정상적으로 표시됩니다!**
- 게시글 본문/제목이 있으면 → 표시
- 없으면 → 마지막 메시지로 대체 (이전 버전 호환)
- postId가 있는 모든 대화방 → 프로필 숨김

---

완료! 이제 모든 게시글 기반 익명 DM이 올바르게 표시됩니다! 🎉
