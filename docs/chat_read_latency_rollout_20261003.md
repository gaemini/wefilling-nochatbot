# 스낵챗·DM 읽음 확정 / 콘텍츠 열람 자동 읽음 / 송수신·방 진입 지연 개선 — 2026-10-03

브랜치 `release/1.2.4`, 기준 HEAD `23d555f6`(1.3.23 배포 준비 중). 기존 미커밋
UI 모션 변경은 보존했다. **운영 배포·운영 데이터 변경·실기기 측정은 하지 않았다.**
모든 클라이언트 변경은 dart-define 플래그 기본 OFF, 서버 변경은 추가 필드·멱등
로직이라 플래그 OFF 빌드와 구버전 앱(1.3.23)의 동작은 그대로다.

## 1. 변경 요약

### A. 읽음 확정 정확성·속도 (UI 불변)

| 항목 | 파일 | 내용 |
|---|---|---|
| 스낵챗 트리거 stamp | `functions/src/snack_chat.ts` `applySnackChatUnreadOnce` | 메시지·이벤트 마커에 `unreadRecipientIds`(실제로 unread를 올린 수신자) 기록. 커서가 이미 앞선 수신자는 `deliveryRecipientIds`에는 있지만 여기엔 없다. |
| 스낵챗 읽음 callable | `snack_chat.ts` `markSnackChatReadSecure` | 차감 floor를 `members/{uid}.unreadReconciledThroughSequence`(없으면 이전 `lastReadSequence`)로 분리하고 `(unreadRecipientIds ?? deliveryRecipientIds) ∋ uid`만 차감. `requireActiveUser`의 별도 왕복을 트랜잭션 `getAll`에 합침. 응답 형식 불변. 순수 헬퍼는 `snack_chat_unread_boundary.ts`. |
| 스낵챗 직접 읽음 쓰기 | `lib/services/snack_chat_service.dart` `advanceReadCursorDirect`, `lib/utils/snack_chat_read_policy.dart`, `lib/screens/snack_chat_screen.dart` `_drainActiveReadSync`/`_scheduleReadReconcile` | 플래그 `SNACK_CHAT_DIRECT_READ`. 멤버 문서에 reconcile stamp가 있을 때만(=새 서버 확인) Rules가 허용하는 자기 커서 쓰기 1회로 상대 화면의 미확인 수를 갱신. callable은 2.5초 병합·종료 시 flush로 방 `unreadCount`만 정합화. 방 목록/배지는 끝까지 읽은 경우에만 로컬 projection 0. `permission-denied`면 기존 callable로 fallback. |
| DM 읽음 id 워터마크 | `functions/src/dm_chat.ts`, `firestore.rules`(create 금지 키), `lib/models/dm_message.dart` `isReadThrough`, `lib/screens/dm_chat_screen.dart`, `lib/services/dm_message_cache_service.dart` | 워터마크가 전진할 때만 `lastReadMessageIdBy[uid]=throughMessageId` 기록. 발신자는 그 메시지를 목록에서 찾아 **목록 순서**로 읽음을 판정하므로 트리거가 쓰는 `receiptCreatedAt`을 기다리지 않는다. `serverCreatedAt`과 `lastReadAtBy` 직접 비교는 하지 않는다(역전 방지). 읽는 쪽 target은 목록 순서상 최신 수신 메시지, 확정 경계는 응답의 seconds/nanos. |
| DM callable 예산 | `dm_chat.ts`, `lib/services/dm_service.dart` | bounded read 512MB/120s → 256MB/60s, 클라이언트 timeout 120s → 20s(기존 2~30s backoff 유지). legacy `markDMConversationReadSecure`는 그대로. |

### B. 콘텍츠 직접 열람 시 자동 읽음 (플래그 `ACTIVE_CONTENT_AUTO_READ`)

| 항목 | 파일 | 내용 |
|---|---|---|
| 활성 콘텐츠 registry | 신규 `lib/services/active_content_registry.dart` | 화면이 보는 대상을 `types + targets`로 등록(`DMActiveConversation` 일반화). target 바운드만 허용, 빈 scope는 무시. |
| 미읽음 feed | 신규 `lib/services/unread_notification_feed.dart`, `notification_service.dart` `markNotificationDocumentsAsRead` | scope가 1개 이상일 때만 `notifications where userId==me && isRead==false limit 200` 리스너 1개. 서버 확정 snapshot만 사용. 일치 문서를 batch 읽음 + 기존 `_afterConfirmedRead`(OS 카드 제거·배지). scope가 비면 2초 후 종료. `FCMService.initialize`에서 `ensureStarted()`. |
| 포그라운드 푸시 | `lib/services/fcm_service.dart` | 비채팅 type의 payload가 활성 scope와 일치하면 로컬 배너 생략 + `markNotificationAsRead(notificationId)`. |
| 등록 지점 | `notification_read_observer.dart`(보이는 동안), `post_detail_screen.dart`, `meetup_detail_screen.dart`, `friend_profile_screen.dart`, `review_approval_screen.dart`, `snapshot_detail_screen.dart` | 기존 `markRelatedNotificationsAsRead` 호출 직후 등록, dispose에서 해제. 스냅 상세는 누락됐던 `readContext`도 전달. |

### C. 송수신·방 진입

| 항목 | 파일 | 내용 |
|---|---|---|
| DM 방 진입 (`DM_FAST_ENTRY`) | `dm_service.dart` `getCachedVisibilityStartTime`, `dm_chat_screen.dart` `_initializeMessagesStream`/`_reconcileVisibilityBoundary` | 서버 전용 `userLeftAt` 읽기를 기다리지 않고 캐시 힌트로 Hive 표시·리스너를 즉시 시작, 서버 경계가 다르면 그 경계로 재구독(더 늦으면 이전 행 제거). `_loadConversation` 중복 호출 1회 제거(플래그 무관). |
| 스낵챗 방 진입 (`SNACK_CHAT_FAST_ENTRY`) | `snack_chat.ts` `getSnackChatEntryContext`/`ensureSnackChatMembershipSecure`/`repairSnackChatMembershipIfNeeded`, `snack_chat_screen.dart` `_prepareEntryAndSubscribe` | entry context가 누락 멤버 문서를 스스로 복구(ensure와 같은 멱등 이벤트). 새 클라이언트는 ensure를 건너뛰고 entry context부터 호출, `failed-precondition`일 때만 ensure 후 1회 재시도. 두 callable 모두 `requireActiveUser` 왕복을 `getAll`에 합침. |
| 스낵챗 푸시 파이프라인 | `snack_chat.ts` `prepareSnackChatPush`/`claimPushAttempts`/`deliverSnackChatPush` | 수신자별 적격성·토큰 조회(병렬) → 이벤트당 **1회** claim 트랜잭션(이전엔 수신자별로 같은 문서에 5개 동시 트랜잭션) → 병렬 발송. 배지 합계는 토큰 조회와 병렬. 발신자 이름은 unread 트랜잭션과 병렬(클라이언트 값 신뢰 안 함). 마커 스키마·3회 제한·상태 의미 불변. |
| DM 트리거 | `functions/src/index.ts` `onDMMessageCreated` | 발신자·수신자·설정·토큰 레지스트리 읽기를 `Promise.all`로, 토큰 소유권 필터는 카운터 트랜잭션 뒤로 이동. 수신자 존재 검사 등 트랜잭션 이전 조건은 그대로. |
| 스낵챗 수신 캐시 (`SNACK_CHAT_CACHE_OFFLOAD`) | `snack_chat_local_cache_service.dart`, `snack_chat_screen.dart` | 메모리 스냅샷이 complete면 저장 목록(최대 2000개) decode를 건너뛰고 메모리에서 encode. 버스트 debounce 180→400ms. 디스크 포맷 불변. `Isolate.run` 오프로드는 적용하지 않았다(측정 후 결정). |
| 측정 (Phase 0) | `lib/utils/chat_timing.dart`, `snack_chat_screen.dart`, `index.ts`, 신규 `functions/scripts/report_chat_timing.js`, `docs/chat_latency_baseline.md` | `CHAT_TIMING_RELEASE`/`CHAT_TIMING_SAMPLE_RATE`로 내부 release 빌드 계측. 스낵챗 `roomEntryFirstPaint`, `entryContextResolved`, `readCallDuration(path)`, `memberReadObserved`; 서버 DM `cloudFunctionStartedAt`, `unreadTransactionCommitted`, `pushSendStartedAt/CompletedAt`. p50/p95 집계 스크립트. |
| 상시 비용 (Phase 3) | 신규 `functions/src/runtime_scaling.ts`, `onSnackChatMessageCreatedSecure`, `onDMMessageCreated`, `markDMConversationReadBoundedSecure` | 환경변수 `CHAT_HOT_FUNCTIONS_MIN_INSTANCES`(기본 0 = 변화 없음, 최대 3). 1로 두면 세 함수에 `minInstances:1`. 1세대는 인스턴스당 동시 1요청. |

## 2. 플래그 / 환경변수

| 이름 | 위치 | 기본 | 켜는 조건 |
|---|---|---|---|
| `SNACK_CHAT_DIRECT_READ` | 앱 define | false | 새 `markSnackChatReadSecure` + 트리거 배포 후. 멤버 stamp 없으면 코드가 스스로 callable 경로 유지 |
| `DM_FAST_ENTRY` | 앱 define | false | 서버 변경 불필요 |
| `SNACK_CHAT_FAST_ENTRY` | 앱 define | false | 새 `getSnackChatEntryContext` 배포 후(구서버면 `failed-precondition` fallback) |
| `ACTIVE_CONTENT_AUTO_READ` | 앱 define | false | 서버 변경 불필요 |
| `SNACK_CHAT_CACHE_OFFLOAD` | 앱 define | false | 서버 변경 불필요 |
| `CHAT_TIMING_RELEASE`, `CHAT_TIMING_SAMPLE_RATE` | 앱 define | false / 100 | 내부 측정 빌드만 |
| `CHAT_HOT_FUNCTIONS_MIN_INSTANCES` | Functions env | 0 | 비용 승인 후 1 |
| `WEFILLING_VERBOSE_FUNCTION_LOGS` | Functions env | false | 측정 기간만 |

## 3. 배포 순서

1. `firestore.rules`(DM create 금지 키 1개 추가) → `firebase deploy --only firestore:rules`.
2. Functions 빌드·배포: `markSnackChatReadSecure`, `onSnackChatMessageCreated`, `getSnackChatEntryContext`, `ensureSnackChatMembershipSecure`, `markDMConversationReadBoundedSecure`, `onDMMessageCreated`. 현재 dirty 트리의 UI 모션 변경과 분리된 커밋으로.
3. 측정 빌드(모든 플래그 OFF + `CHAT_TIMING_RELEASE=true`)로 `docs/chat_latency_baseline.md` baseline 기록.
4. 내부 빌드에서 플래그를 하나씩 ON → 같은 시나리오 재측정 → 스토어 빌드 기본 ON으로 전환.

## 4. 호환성

| 변경 | 구클라 ↔ 신서버 | 신클라 ↔ 구서버 |
|---|---|---|
| 스낵챗 stamp + floor | floor가 이전 `lastReadSequence`로 fallback → 결과 동일(에뮬레이터 legacy 시나리오로 확인) | stamp가 안 생기므로 callable만 사용(현행) |
| `lastReadMessageIdBy` | 필드 무시 | 필드 없음 → timestamp 규칙 |
| entry context 복구 | ensure 먼저 호출하는 구클라는 상위 호환 | `failed-precondition`이면 ensure 후 재시도 |
| 푸시 파이프라인 | 같은 마커 스키마 | 해당 없음 |
| minInstances | 설정만 | 해당 없음 |

## 5. 검증

- Functions `npm run build`, eslint(변경 파일) 통과.
- Firestore 에뮬레이터(저장소 Rules + 실제 핸들러, JDK 21 필요: `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`):
  `test_chat_delivery_emulator.js`(기존 전부 + 신규 "Snack direct read cursor fast path: C/T/K 순서 4종, Rules 역행/초과/추가 키/타인 거부, legacy floor"), `test_dm_read_boundary_emulator.js`(+`lastReadMessageIdBy` 기록·단조·비역행), `test_notification_read_emulator.js`, `test_snack_chat_unread_boundary.js`(16 시나리오), `test_chat_push_presentation.js` — 결과는 아래 "검증 결과" 참조.
- Flutter: `dm_read_receipt_test`(+목록 순서 규칙 5건), 신규 `snack_chat_read_fast_path_test`, 신규 `active_content_registry_test`(플래그 OFF/ON 두 번), 기존 `chat_delivery_policy_test`, `snack_chat_read_visibility_test`, `snack_chat_notification_policy_test`, `notification_read_policy_test`, `notification_delivery_policy_test`, `notification_unread_counter_policy_test`, `snack_chat_send_state_test`, `snack_chat_message_grouping_test`.
- 변경 Dart 파일 `flutter analyze`: error 0 (기존 warning/info는 그대로).
- **미수행:** 실기기 2대 시나리오, 운영 배포 후 검증, baseline 수치, 계정 전환 중 feed 동작의 종단 간 확인.

## 6. 보류·미적용·주의

- `dm_chat_screen.dart`의 Phase 0 stage(`roomEntryFirstPaint`, `peerReadObserved`, `readCallDuration`)는 이번 작업에서 적용하지 못했다(편집 도구 권한 거부). 스낵챗 쪽 stage와 서버 DM stage는 적용됨. DM 수신 측 `receiverFrame`·`localFrame`은 기존 stage로 측정 가능.
- `Isolate.run` encode 오프로드, DM 전송 ack 시점 "전송됨" 표시(C3), secure batch 전송 경로(C5)는 측정 전에는 적용하지 않는다.
- 알림센터 `markAllAsReadOnOpen` 정책, 푸시 탭 실패 시 fallback(미읽음 잔존)은 변경하지 않았다.
- feed는 차단 사용자 알림도 scope에 맞으면 읽음 처리한다(UI에서는 원래 숨겨지는 문서라 표시 영향 없음).
- `claimPushAttempts`는 수신자별 상태·3회 제한을 그대로 두고 트랜잭션만 합쳤다. 기존 `pending` 마커가 있는 이벤트의 재시도도 같은 규칙으로 이어진다.
