# 채팅 지연 baseline 측정 절차 (Phase 0)

작성: 2026-10-03, `release/1.2.4`. **아직 측정값은 없다.** 이 문서는 Phase 1~3
변경을 켜기 전에 같은 절차로 baseline을 먼저 기록하기 위한 것이다. 실기기와
운영 Firebase 프로젝트가 필요하므로 이 저장소 안에서는 실행하지 않았다.

## 측정 빌드

```sh
# 내부 측정용 release 빌드. 스토어 빌드에는 두 define을 넣지 않는다.
flutter build apk --release \
  --dart-define=CHAT_TIMING_RELEASE=true \
  --dart-define=CHAT_TIMING_SAMPLE_RATE=100
```

- `lib/utils/chat_timing.dart`: `CHAT_TIMING_RELEASE=true`이면 release에서도
  `[SnackChatTiming]` / `[DMChatTiming]` 라인을 `Logger`로 출력한다
  (`adb logcat` / Xcode console). 메시지 본문은 기록하지 않는다.
- `CHAT_TIMING_SAMPLE_RATE`는 0~100 정수(퍼센트). 같은 messageId/roomId의
  모든 stage는 함께 기록되거나 함께 생략된다.
- 서버 stage는 Functions 환경변수 `WEFILLING_VERBOSE_FUNCTION_LOGS=true`로
  켜고 Cloud Logging에서 `[SnackChatTiming]`, `[DMChatTiming]`을 필터한다.

## 시나리오 (계정 A/B, Android 1대 + iOS 1대 권장)

| # | 시나리오 | 반복 | 읽는 stage |
|---|---|---|---|
| 1 | A→B 텍스트 전송(둘 다 포그라운드) | 20회 양방향 | snack/dm `localFrame`, `queueWait`, `commit`, `receiverFrame`/`receiverBubbleRenderedAt` |
| 2 | B가 읽음 → A 화면에 반영 | 20회 | snack `memberReadObserved`, `readCallDuration(path=direct/callable)`; dm `peerReadObserved(sinceLastSendMs)`, `readCallDuration` |
| 3 | B 백그라운드에서 수신(푸시) | 10회 | 서버 `cloudFunctionStartedAt(commitAgeMs)`, `unreadUpdatedAt`/`unreadTransactionCommitted`, `pushSendStartedAt`, `pushSendCompletedAt(totalDurationMs)` |
| 4 | 방 진입 cold/warm | 각 5회 | snack `roomEntryFirstPaint(source)`, `entryContextResolved(fastEntry)`; dm `roomEntryFirstPaint(fastEntry)` |

- 서로 다른 기기의 wall clock을 빼서 편도 지연으로 보고하지 않는다. 같은
  기기의 Stopwatch 구간과 서버 `commitAgeMs`만 사용한다.
- `peerReadObserved.sinceLastSendMs`는 "내가 마지막으로 보낸 뒤 상대 읽음이
  보이기까지"이며 상대의 반응 시간을 포함한다. 두 기기를 같은 손으로 조작해
  동일 조건을 유지한다.

## 집계

```sh
cd functions
node scripts/report_chat_timing.js client_logcat.txt server_logs.txt
node scripts/report_chat_timing.js client_logcat.txt --json > baseline.json
```

p50/p95/p99/max를 stage별로 출력한다. 평균만 보지 않는다.

## 기록 (채워 넣기)

| 플래그 상태 | 날짜 | snack queueWait p95 | snack commit p95 | snack receiverFrame p95 | snack memberReadObserved→전송 p95 | dm readCallDuration p95 | dm peerReadObserved p95 | 푸시 totalDurationMs p95 | snack roomEntryFirstPaint p95 | dm roomEntryFirstPaint p95 |
|---|---|---|---|---|---|---|---|---|---|---|
| 모두 OFF (baseline) | | | | | | | | | | |
| `SNACK_CHAT_DIRECT_READ` ON | | | | | | | | | | |
| `DM_FAST_ENTRY` + `SNACK_CHAT_FAST_ENTRY` ON | | | | | | | | | | |
| 서버 Phase 2 배포 후 | | | | | | | | | | |
| `CHAT_HOT_FUNCTIONS_MIN_INSTANCES=1` | | | | | | | | | | |

같은 시나리오·같은 네트워크·같은 기기로만 행을 비교한다.
