# DM 읽음 표시 수정 — 2026-09-25

현재 작업 트리의 변경사항을 보존한 상태에서 DM 읽음 경로만 수정했다.

## 확인한 원인

- 클라이언트는 `deferReceipts: true`로 요청하지만, 화면은 개별 `isRead`만 사용했다.
- 기존 방 문서 구독은 미읽음 카운터만 확인했다. 최근 40개 밖에 유지된 메시지는 receipt 변경을 받지 못할 수 있었다.
- `DMMessage.serverCreatedAt`은 이름과 달리 기존 `createdAt`을 읽는다. 구버전 단말 시각과 읽음 기준을 비교할 수 없다.
- 화면 build에서 읽음을 요청하고, 종료 시 서버 실행 시각까지 읽는 요청을 다시 보내고 있었다.
- 운영 함수 목록을 읽기 전용으로 확인한 결과 `markDMConversationReadSecure`, `onDMMessageCreated`, `onDMMessageRead`는 ACTIVE였으나 `onDMReceiptCleanupRequested`는 목록에 없었다. 개별 사용자 요청의 실행 로그까지 추적한 것은 아니다.

## 변경과 경계

수정 파일:

- 클라이언트: `lib/screens/dm_chat_screen.dart`, `lib/models/dm_message.dart`, `lib/services/dm_service.dart`, `lib/services/dm_message_cache_service.dart`.
- 서버/규칙: `functions/src/dm_chat.ts`, `functions/src/index.ts`의 DM 부분, 신규 `functions/src/dm_read_policy.ts`, `firestore.rules`. Functions 빌드로 기존 추적 대상 `functions/lib/index.js`와 source map도 갱신됐다.
- 검증: 신규 `test/dm_read_receipt_test.dart`, 신규 `functions/scripts/test_dm_read_boundary_emulator.js`, 기존 `functions/scripts/test_chat_delivery_emulator.js`의 DM 필드 위조 거부 검사.

- 기존 방 구독에서 상대의 `lastReadAtBy`를 받아 `isRead || receiptCreatedAt <= lastReadAtBy`로 표시한다. `receiptCreatedAt`이 없는 메시지는 기존 `isRead`를 사용한다.
- `receiptCreatedAt`은 생성 트리거가 Firestore 문서 `createTime`을 기록한다. Rules가 클라이언트의 생성·수정을 금지한다. `serverTimestamp()`와 `createTime`이 다를 수 있음도 에뮬레이터에서 확인했다.
- Timestamp의 seconds/nanoseconds를 그대로 비교·캐시한다. 표시를 위해 메시지 전체를 서버에 다시 쓰지 않는다. 과거 데이터 일괄 마이그레이션은 없다.
- 읽음 요청은 활성 화면에서 확보한 메시지 ID를 고정한다. 서버는 해당 방 문서의 실제 createTime을 확인한다. 처리 중 새 경계가 생기면 후속 처리하며 build는 요청하지 않는다.
- `markDMConversationReadBoundedSecure`를 별도 진입점으로 추가했다. 구서버가 알 수 없는 요청 필드를 무시하고 현재 시각까지 읽는 일을 피하기 위해서다. 미배포 시 넓은 범위의 구형 fallback으로 전환하지 않고 실패/재시도한다.
- 기존 구버전 callable과 receipt worker를 유지한다. 읽음 기준과 카운터 차감 기준(`unreadClearedAtBy`)을 구분한다. 마지막으로 집계한 생성 시각(`lastUnreadCreatedAtBy`)이 경계 내임을 증명할 때만 방 카운터를 일괄 차감한다.
- 더 새 메시지 또는 구버전 카운터가 있으면 기존 receipt 이벤트가 해당 메시지의 집계 여부(`unreadCountedFor`, 구버전은 해당 메시지의 기존 이벤트 기록)를 확인해 차감한다. 다른 방의 합계는 보존한다.
- 생성 이벤트의 읽음 판정과 푸시 직전 재확인도 같은 정밀도를 사용한다. 밀리초만 지원하는 OS 알림 제거는 경계 밀리초를 보수적으로 남겨 같은 밀리초의 새 알림을 삭제하지 않는다.
- 읽음 세대, 계정, 방 검증을 추가했다. 종료 요청은 관찰한 경계를 보존하고, 기존 계정 구독을 해당 요청 종료까지만 유지한다. 배지는 오래된 응답 총합 대신 기존 현재 계정의 배지 동기화를 사용한다.
- 캐시와 화면 병합은 확정 receipt를 보존한다. 작은 상대 읽음 기준은 `계정::dm::방::상대`로 저장한다. receipt만 바뀐 메시지 이벤트는 스크롤 보정을 하지 않는다.
- 최근 구독 수 40, 전송 큐, Outbox, 메시지 ID/정렬, 답장, 반응, 파일, 번역 구조를 유지했다. 스낵챗 및 공통 FCM/배지 구현은 수정하지 않았다.

## 검증

- Flutter 대상 테스트 28개 통과: `dm_read_receipt_test`, `chat_delivery_policy_test`, `dm_message_reaction_test`, `notification_delivery_policy_test`, `snack_chat_read_visibility_test`, `snack_chat_send_state_test`.
- `functions` TypeScript 빌드 통과.
- Firestore 에뮬레이터 + 실제 Rules/함수 핸들러: `test_chat_delivery_emulator.js`의 DM 및 Snack Chat 검사 통과.
- `test_dm_read_boundary_emulator.js`: worker 지연, 생성 이벤트 역순, 오래된 요청, 나간 뒤 새 메시지, A/B방 합계, 중복 receipt, 단말 시계 왜곡, 정밀도, 구버전 카운터, 잘못된 계정/경계 거부 통과.
- 변경 Dart 파일 정적 분석: 오류 0. 기존 경고 13개 및 스타일 정보가 남아 있어 분석 명령의 종료 코드는 2다.
- 실기기 화면/OS 푸시, 계정 전환 UI의 종단 간 테스트, 실제 네트워크 속도 벤치마크, 운영 배포 후 검증은 수행하지 않았다. 운영 함수/규칙 배포도 하지 않았다.

재현 명령(에뮬레이터는 Java 21 이상 필요):

```sh
flutter test --no-pub test/dm_read_receipt_test.dart test/chat_delivery_policy_test.dart test/dm_message_reaction_test.dart test/notification_delivery_policy_test.dart test/snack_chat_read_visibility_test.dart test/snack_chat_send_state_test.dart
npm --prefix functions run build
# demo-chat-delivery 전용 로컬 Firestore를 127.0.0.1:8787에서 실행한 뒤:
FIRESTORE_EMULATOR_HOST=127.0.0.1:8787 node functions/scripts/test_chat_delivery_emulator.js
FIRESTORE_EMULATOR_HOST=127.0.0.1:8787 node functions/scripts/test_dm_read_boundary_emulator.js
```

## 배포 순서

새 앱보다 서버를 먼저 반영한다. 인덱스 변경이나 운영 데이터 일괄 변경은 없다.

1. 변경된 Firestore Rules: 서버 전용 receipt/카운터 필드 보호.
2. `markDMConversationReadSecure`, `onDMReceiptCleanupRequested`: 구버전 요청과 카운터 차감 기준, worker를 먼저 호환시킨다.
3. `onDMMessageCreated`, `onDMMessageRead`: 정확한 생성 시각, 집계 여부, 지연 이벤트 처리를 반영한다.
4. `markDMConversationReadBoundedSecure`: 범위 제한 진입점을 배포하고 테스트 계정으로 확인한다.
5. 앱 배포 후 두 계정으로 읽음·기존 알림·새 알림을 확인한다.

이 작업과 무관한 미커밋 Functions 변경도 있으므로 전체 Functions 일괄 배포 대신 위 이름을 지정한다.
