# 배포 전 코드 점검 보고서 (2026-10-14)

- 브랜치: `main`(새 브랜치 없음). 푸시·Functions·규칙·색인 배포는 하지 않았다.
- 점검 범위: `89518d3e`(직전 main 병합) → `f515212d`, 112개 파일(+15,079 / −5,285)
  - 포스트 상세·대화형 댓글, 스낵챗(번역·입력창·글자·목록·그룹), DM, 스낵 v3(필링·서로 필링·만들기),
    내 정보·친구 프로필·같이하기, 그룹 목록·수정·새 그룹, 공유·딥링크
- 방법: 자동 점검 기준선 → 영역별 코드 읽기 점검(채팅·DM / 스낵 / 프로필·그룹 / 서버·규칙·플랫폼) → 검증된 항목 중 안전한 것만 수정 → 재점검

## 1. 요약 (기준선 → 현재)

| 항목 | 기준선 | 현재 |
|---|---|---|
| `flutter analyze` error | 1 | 1 (기존: `test/snack_chat_discovery_layout_test.dart` 없는 위젯 참조) |
| `flutter analyze` warning | 261 | 261 |
| `flutter analyze` info | 1,715 | 1,714 |
| `flutter test` 통과 / 실패 | 1,255 / 21 | 1,258 / 19 |
| Functions `npm run build` / `lint` | 통과 / 통과 | 통과 / 통과 |
| Functions 에뮬레이터 테스트(같이하기·필링·필링 규칙·반응·보안 규칙 62·포스트 스낵챗 14·첫 응답 규칙 17·알림 읽음) | 통과 | 통과(같이하기 재실행) |
| `flutter build apk --release` | — | 성공(208.5MB) |
| `flutter build ios --no-codesign` | — | 성공(217.5MB). `Podfile.lock`에 app_links·share_plus가 빠져 있어 함께 커밋 |
| `dart format` 차이 | 271개 파일 | 대량 변경이라 적용하지 않음(수정한 파일 1개만 별도 커밋) |

남은 실패 19개는 모두 `89518d3e` 시점에도 실패하던 테스트다(같은 시점 워크트리에서 재실행해 확인).
예외는 `snack_chat_empty_state_test` 2개 — 빈 화면 개편으로 문구가 바뀌어 옛 문구를 찾는 테스트(3장 R-12).

## 2. 수정한 항목

| # | 파일 | 내용 | 위험도 | 커밋 | 검증 |
|---|---|---|---|---|---|
| F-1 | `screens/snack_chat_screen.dart` | 메시지가 적어 스크롤이 생기지 않는 같이하기 방에서 `_hasMore`가 내려가지 않아 **제안 배너와 [좋아요]/[다음에]가 보이지 않음** → 방의 첫 메시지(sequence 1)도 맨 위로 인정 | 높음 | b1d1a337 | 코드 경로 확인, analyze |
| F-2 | `firestore.indexes.json`, `firestore.kr.indexes.json` | `together_proposals(fromUid ==, createdAt >=)` 복합 인덱스 누락 → 운영에서 **같이하기 제안이 전부 실패** 가능. 인덱스 추가 | 높음 | 1efaffcd | JSON 검증(에뮬레이터는 인덱스를 검사하지 않음) |
| F-3 | `screens/snapshot_detail_screen.dart` | DM 답장 입력 중 좌우로 넘기면 일시정지·입력 상태가 남아 영상 재생·탭 이동이 멈춤 → 입력 중엔 넘기지 않음. 편지 상태 확인 실패 시 스피너 고정 → 보내지 않은 것으로 가정하지 않고 종료 | 중간 | 5f0d5a2a | 스낵 테스트 180개 통과 |
| F-4 | `screens/snapshot_activity_sheet.dart` | `asBroadcastStream()`이 시트를 닫아도 조회자 리스너를 유지(열 때마다 누수) → 단일 구독으로. DM 열기 연타 가드 | 중간 | c7cac7bf | 스낵 테스트 통과 |
| F-5 | `ui/sheets/mutual_feel_sheet.dart` | [메시지] 연타 시 두 번째 `pop()`이 아래 화면(스낵 보기)을 닫고 DM이 두 번 열림, 예외 미처리 → 경로가 현재일 때만 진행, 예외 처리 | 중간 | 43dca730 | analyze, 테스트 |
| F-6 | `ui/widgets/groups_empty_state.dart` | 그룹 빈 화면 이름 칩이 가로로 꽉 참(새 그룹 화면과 같은 원인) → 내용 크기, 높이 34 유지 | 중간 | 4352eede | 새 테스트(높이 34·폭 < 120) |
| F-7 | `android/.../AndroidManifest.xml` | App Links 검증 필터에 응답하지 않는 `wefilling.app`(NXDOMAIN) → Android 11 이하에서 web.app 링크도 앱으로 바로 안 열림 → 호스트 제거 | 중간 | 6868592c | `host wefilling.app` NXDOMAIN 확인, APK 빌드 |
| F-8 | `functions/src/snack_chat.ts` | 모든 스낵챗 메시지 트리거가 방 문서 트랜잭션을 한 번 더 돎 → 대기 중 제안의 받는 사람일 때만. 늦게 온 이전 방 수락이 새 제안 문서를 `accepted`로 덮던 문제 → 같은 방일 때만 갱신 | 낮음~중간 | b7c432f2 | build·lint, 같이하기 에뮬레이터 통과 |
| F-9 | `services/snapshot_service.dart` | 계정 전환 후에도 이전 계정의 서로 필링 목록이 배지·정렬에 남음 → 전환 시 비우고, 늦게 온 결과 버림 | 낮음 | fe492bfe | 테스트 통과 |
| F-10 | `screens/friend_profile_screen.dart` | 다른 같이하기 칩 연타·이동 중 재탭으로 방이 겹쳐 열림 → 전체 진행 가드. 긴 활동 이름 말줄임 | 낮음~중간 | 500b2e88 (+ 포맷 a05cbe5c) | 테스트 통과 |
| F-11 | `services/profile_link.dart` | 콜드 스타트 링크가 `getInitialLink`와 스트림으로 두 번 와 프로필이 두 번 열릴 수 있음 → 3초 내 같은 링크 무시 | 낮음~중간 | 586874ca | 링크 테스트 통과 |
| F-12 | `screens/new_group_screen.dart` | 열었다 닫기만 해도 `dispose`에서 Firestore 서비스를 생성 → 만들 때만 생성 | 낮음 | 9615a47d | 새 그룹·빈 화면 테스트 63개 |
| F-13 | `screens/category_detail_screen.dart` | 그룹 삭제 연타 시 "삭제 실패"가 뒤따름 → 진행 가드. 첫 프레임 콜백 `mounted` 확인 | 낮음 | afb8604d | 그룹 테스트 통과 |
| F-14 | `screens/profile_grid_screen.dart` | 공유 진행 플래그를 확인만 하고 설정하지 않아 시트가 두 번 열림 → 설정·해제 | 낮음 | b916544d | analyze |
| F-15 | `ui/widgets/group_list_row.dart` | `+10` 이상이 24px 칸에서 잘림 → 칸 안에서 축소 | 낮음 | cd9af3f3 | 그룹 테스트 통과 |
| F-16 | `screens/notification_screen.dart` | 서로 필링 알림에 actorId가 없으면 빈 uid로 시트를 엶 → 푸시 경로와 같은 가드 | 낮음 | fcf55cf6 | analyze |
| F-17 | `widgets/notification_list_item.dart` | 썸네일 조회 실패(오프라인)가 앱 재시작 전까지 캐시에 남음 → 실패는 캐시하지 않음 | 낮음 | a9486fb7 | 테스트 통과 |
| F-18 | `test/tab_empty_states_test.dart` | 새 그룹 화면이 `RelationshipProvider`를 읽어 테스트 하네스가 실패 → Provider 제공, 이름 칸 기준으로 확인(검증 대상 동작은 동일) | — | 23b3f911 | 2개 실패 → 통과 |
| F-19 | `.gitignore` | Firebase 배포 캐시 `.firebase/`가 커밋돼 있음 → 제외 | 낮음 | 2a09f751 | — |

## 3. 보고만 한 항목 (손대지 않음, 위험도 순)

| # | 위치 | 내용 | 재현 | 권장 조치 | 기능 영향 |
|---|---|---|---|---|---|
| R-1 | `firestore.rules` (`snapshots/{id}/reactions`) | **반응 비공개 게이트가 이미 규칙 파일에 들어 있고 origin/main에도 푸시됨**(8206a2d6). 지금 규칙을 배포하면 1.3.31 이하 앱의 작성자 반응 목록 구독이 permission-denied → 조회자 목록이 막힘 | 구버전 앱으로 내 스낵 조회자 보기 | 최소 지원 버전 상향 전에는 **규칙 배포 금지**. 새 컬렉션 4개는 서버 전용이라 규칙 배포를 미뤄도 기능 영향 없음 | 배포 순서 |
| R-2 | `functions/src/snapshot.ts` `getSnapshotViewers` | `includeReaction === true`를 클라이언트가 직접 보내면 누가 필링했는지 알 수 있음(익명성) | 콜러블 직접 호출 | 최소 버전 상향 후 서버에서 파라미터 무시 | 동작 변경 |
| R-3 | `snack_chat.ts` `proposeTogetherSnackChat` | 받는 쪽이 [다음에]/수락하면 같은 활동을 즉시 다시 제안 가능(제안 문서 1개를 덮어써 쌍 한도 3에 걸리지 않음) → 반복 방·푸시 | A가 같은 활동을 연속 제안 | 활동별 쿨다운 또는 기록 문서 분리 | 동작 변경 |
| R-4 | `snack_chat.ts` 수락 시스템 메시지 | `같이 ${activity} · 수락했어요`에서 라벨이 '같이 점심 먹기'면 "같이 같이 점심 먹기", 보낸 사람 언어 라벨이 그대로 저장, 수락 알림 제목 한국어 고정 | 점심 제안 수락 | 문구·다국어 정리 | 문구 |
| R-5 | `dm_chat_screen.dart:5610` | 스낵 글 답장이 실제로 보내지지 않아도(차단·500자 초과 등) "보냈어요" 토스트 | 450자 이상 답장 | 입력창이 비었을 때만 콜백 | 동작 변경 |
| R-6 | `snack_chat.ts` `applyTogetherAccepted` 이후 | 커밋 뒤 시스템 메시지·알림 생성이 실패하면 재시도에서 `changed=false`라 영구 누락(중복은 없음) | 쓰기 실패 주입 | 부수 효과를 트랜잭션 안/아웃박스로 | 서버 구조 |
| R-7 | `snapshot.ts` 필링 묶음 알림 | `snapshot_feel_{id}`는 생성 시에만 푸시, 이미 읽었으면 이후 필링은 조용히 개수만 증가. 서로 필링 알림은 30일 뒤 TTL 전에 set되면 푸시 누락 | — | 정책 결정 | 동작 |
| R-8 | `profile_link.dart` | 같은 링크를 여러 번 열면 프로필이 쌓임(3초 이후) | 링크 3회 탭 | 최상단 경로 확인 | 흐름 |
| R-9 | `new_group_screen.dart` | 저장 중 뒤로 가기 허용 → 그룹은 만들어지지만 목록 강조·스낵바 없음 | 저장 중 뒤로 | 저장 중 뒤로 막기 | 흐름 |
| R-10 | `category_detail_screen.dart` | 이름·멤버 변경 후 뒤로 가면 확인 없이 버림(새 그룹은 확인함) | 수정 후 뒤로 | 확인 다이얼로그 | 흐름 |
| R-11 | `snapshot_comments_sheet.dart` | 읽기 전용(기본)인데 밀어서 답장·길게 눌러 답장이 동작해 숨은 입력창에 포커스 | 댓글 밀기 | 읽기 전용이면 답장 끄기 | 동작 |
| R-12 | `test/snack_chat_empty_state_test.dart` 2개 | 빈 화면 개편 뒤 옛 문구("필요한 시간만 열어 두는 번역 채팅" 등)를 찾음. 어느 쪽이 맞는지 판단하지 않음 | 테스트 실행 | 문구 확정 후 테스트 갱신 | 테스트 |
| R-13 | `together_service.dart` | 20초 클라이언트 타임아웃 후 "실패"를 보여도 서버는 성공할 수 있음(스트림이 곧 바로잡음) | 느린 네트워크 | — | 표시 |
| R-14 | `snack_chat.ts` propose | 차단·친구 확인이 트랜잭션 밖(TOCTOU). 푸시는 `onNotificationCreated` 차단 필터가 막음 | — | 트랜잭션 안으로 | 서버 |
| R-15 | 터치 영역 < 44 | 친구 프로필 [메시지]/[친구 ✓] 38, 내 정보 버튼 38, 그룹 바로가기 칩 32, 빈 화면·새 그룹 칩 30–34, `friend_picker` 빼기 버튼(실제 약 24) | — | 투명 여백(디자인 확인 후) | 디자인 |
| R-16 | `mypage_screen.dart:739` | 프로필 완성 안내에 중국어 없음, 질문이 이미 있어도 "질문 설정" 안내 | zh UI | 문구 | 문구 |
| R-17 | `profile_share_sheet.dart` | "링크 복사" 스낵바가 시트 아래(딤 뒤)에 떠 보기 어려움 | 공유 시트에서 복사 | 시트 안 표시 | 디자인 |
| R-18 | `snapshot_activity_sheet.dart:247,269` | 친구 요청·DM 실패에 댓글 실패 문구 사용 | — | 문구 | 문구 |
| R-19 | `snapshot_viewer_chrome.dart` | 스낵 약 90개 이상이면 진행 막대 간격이 폭을 넘음 | — | — | 낮음 |
| R-20 | `context.rf` 잔여 | meetup_detail 17, snapshot_comment_letter 13, snapshot_viewers 8, create_category(수정 모드) 8, snapshot_detail 6, post_detail 5, friends_page 5, create_snapshot 5, board 4, snapshot_comments 3 | — | 고정값 전환 여부 결정 | 디자인 |
| R-21 | `dart format` | 271개 파일 차이 | — | 별도 PR로 일괄 포맷 | 없음 |
| R-22 | 빌드 환경 | pubspec `sdk: ^3.6.0`이지만 lock 기준 Dart ≥3.12 / Flutter ≥3.44(app_links 7.2.2). 다른 머신·CI가 구버전이면 실패 | — | SDK 하한 명시 | 빌드 |

## 4. 배포 차단 후보

1. **R-1 규칙 배포 시점** — 최소 지원 버전 상향 전 `firestore:rules` 배포 금지(구버전 앱 조회자 목록 오류).
2. **F-2 색인** — 수정했지만 **함수 배포 전에 색인을 먼저 배포하고 빌드 완료를 확인**해야 한다. 운영에 이미 있는지는 확인하지 못함.
3. **iOS Associated Domains** — Apple Developer의 App ID에서 기능이 켜져 있고 프로비저닝 프로필에 반영돼야 서명 빌드가 성공하고 링크가 열린다.

## 5. 배포 전 체크리스트

1. 색인: `firebase deploy --only firestore:indexes` → 콘솔에서 `together_proposals` 빌드 완료 확인
2. Functions: `proposeTogetherSnackChat`, `respondTogetherProposal`, `onSnackChatMessageCreatedSecure`(F-8), `toggleSnapshotReaction`, `getMyMutualFeels`, `getSnapshotViewers`, `onNotificationCreated` — 새 앱 출시 **전**
   - 배포 시점부터 구버전 앱 조회자 목록의 하트 표시가 사라짐(오류는 아님)
3. Hosting: 배포 완료(assetlinks·AASA 200 확인). 변경 시에만 재배포
4. 앱: 스토어 빌드 번호 확인(현재 pubspec `1.3.31+102` — 이번 점검 중 릴리스 빌드가 자동으로 올린 번호는 되돌림)
5. 플래그: `SnackFeatureFlags.publicComments = false`, `letters = false`(원격 설정 연결 없음 → 항상 기본값)
6. 규칙: 최소 지원 버전을 새 앱 버전 이상으로 올린 **뒤에만** 배포

## 6. 핵심 흐름 스모크 테스트 (수동 확인 필요)

자동 통합 테스트가 없어 아래는 확인하지 못했다. 각 단계에서 화면 깨짐·중복 열림·오류 스낵바를 본다.

- [ ] 로그인 → 홈 → 포스트 상세 → 댓글·답장·사진 → 번역 전환
- [ ] 스낵챗 목록 → 방 → 메시지·사진·밀어서 답장 → 번역 → 즐겨찾기
- [ ] DM → 상단바 번역 → 답장
- [ ] 스낵 만들기(사진·영상·그룹 공개) → 보기 → 필링 → DM 답장(입력 중 넘기기 안 됨, F-3) → 서로 필링 알림
- [ ] 내 정보 → 프로필 편집 → 친구 목록
- [ ] 친구 프로필 → 같이하기 → 받는 쪽에 배너 표시(F-1) → 수락 / 다음에
- [ ] 그룹: 빈 화면 칩(F-6) → 새 그룹(이름 + 친구) → 수정 → 삭제
- [ ] 알림 목록의 각 타입 이동
- [ ] 로그아웃 → 다른 계정 로그인(서로 필링 배지 초기화, F-9)
- [ ] QR 스캔 → 앱 → 프로필(Android 11 이하 기기 포함, F-7)

## 7. 확인하지 못한 항목

- 운영 Firestore에 `together_proposals` 색인이 이미 있는지(로컬 CLI로 운영 조회 안 함)
- `test_comment_image_rules_emulator`: Storage 에뮬레이터(9199)가 필요해 이번 실행에서는 확인 불가
- iOS 서명 빌드, 실기기 동작, 다크 모드
- 오버플로우 매트릭스는 새 그룹·빈 화면 테스트에만 있음. 다른 바뀐 화면(포스트 상세, 스낵챗, DM, 스낵 보기, 내 정보, 친구 프로필)은 해당 위젯 테스트 범위만 확인
- 5초 이상 느린 테스트 목록(리포터가 테스트별 시간을 내지 않음)
- `flutter pub outdated`: 목록만 저장, 업그레이드하지 않음

## 부록

자동 점검 원본: `/tmp/audit/` (analyze 전후, test 전후, format, functions build·lint·emulator, pub outdated, build 로그)
