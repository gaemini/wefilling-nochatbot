# Wefilling Interactive MVP

학교 기반 무료 나눔을 중심으로 피드, 친구 그룹, Snack Chat, DM, 마이페이지를 한 번에 체험할 수 있는 모바일 우선 PWA입니다.

## 포함된 사용자 흐름

- Apple/Google/이메일 로그인 화면과 데모 진입
- 나눔/피드 이중 탭
- Univ. 전용 게시글 게이트와 한양 이메일 인증 데모
- 나눔 글 작성 및 즉시 목록 반영
- 2단계 피드 작성과 전체/그룹 공개범위
- 친구 그룹 생성·편집 UI
- Today/All 구조의 Snack Chat, 즐겨찾기, 24/48시간 유지 옵션
- 친구/익명 DM 목록과 대화방
- 게시글 상세, 좋아요, 저장, 댓글, 나눔 신청, Snack Chat/DM 연결
- 프로필, 내 나눔, 설정, 한국어/영어 전환
- localStorage 기반 상태 보존
- PWA manifest와 오프라인 캐시

## 실행

별도 빌드가 필요하지 않습니다.

```bash
cd prototype/wefilling-pwa
python -m http.server 8080
```

브라우저에서 `http://localhost:8080`을 엽니다. 모바일 브라우저에서는 홈 화면에 추가해 standalone 앱처럼 사용할 수 있습니다.

## 테스트

`smoke_test.py`는 다음 흐름을 자동으로 검증합니다.

1. 로그인
2. 나눔 목록 진입
3. Univ. 글의 인증 게이트
4. 한양 이메일 인증
5. 나눔 글 작성
6. Snack Chat 메시지 전송
7. DM 메시지 전송
8. 프로필 화면

```bash
python smoke_test.py
```

테스트에는 Python Playwright와 Chromium이 필요합니다. `smoke_test.py`의 Chromium 경로는 실행 환경에 맞게 조정할 수 있습니다.

## 구현 범위와 다음 연결점

이 디렉터리는 UI/UX와 핵심 상태 전이를 빠르게 검증하기 위한 실행 가능한 프런트엔드 MVP입니다. 인증 코드 발송, Firestore 실시간 스트림, FCM, Firebase Storage, 서버 보안 규칙은 기존 Flutter/Firebase 앱의 서비스 계층과 연결해야 합니다. 데이터 구조와 화면 동작은 Wefilling의 최신 제품 구조인 `나눔 · 그룹 · DM · 마이페이지`를 따릅니다.
