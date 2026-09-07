# 포스트 번역 누락 보완 검토

> 후속 수정: 아래 내용은 이전 registry 구현의 검토 기록이다. GitHub 최신 `a77f2668`을 비교한 뒤 현재 실행 경로는 **카드 직접 요청 + 공용 cache/queue**로 단순화했다. Feed는 선택적 사전 로딩과 읽기 위치 보존만 맡으며 카드 실행을 제어하지 않는다. 운영 로그에서 금액 표현의 숫자 변환을 거절한 서버 검사도 발견해 보완했다. 이 후속 작업에서는 아래 회귀 테스트를 다시 실행하지 않았다.

검토일: 2026-09-05. 이번 요청에 대한 변경·검증만 기록한다. 작업 시작 전부터 존재하던 검색, 닉네임, 알림, 서버 번역 변경 등은 보존했다.

## [확정된 포스트 누락 원인]

클라이언트의 **등록 경로와 viewport 대기열 필터**에서 누락 가능한 경로를 확인했다.

- 기존 Board의 `_withPostAnchor`가 카드 생성 시점에만 포스트를 등록했다. 지연 생성되는 화면 밖 카드는 데이터 목록에 있어도 등록되지 않았다 (`POST_NOT_REGISTERED`).
- 등록된 후보도 70ms 대기 후 `_flushPostTranslationMicroBatch`에서 현재 viewport 후보와 다시 교집합을 취했다. 그 사이 스크롤로 벗어난 항목은 처리 대상에서 빠졌다 (`POST_PREFETCH_CANCELLED`).
- 실제 실행은 `loadAttachedScope`의 장착된 위젯 loader에 의존했다. 카드가 생성되지 않은 포스트는 이 경로로 요청할 수 없었다.

서버 batch, 권한 검사, 번역 품질 정책, cache 자체가 이번 누락의 원인이라는 증거는 확인되지 않았다. 사용자가 경험한 실제 postId는 아직 제공받지 못했다. 위 원인은 코드 경로와 재현 테스트로 확인한 것이며, 해당 운영 문서의 Gemini 호출까지 실측 추적했다고 주장하지 않는다.

## [기존 처리 경로]

목록 데이터 → 생성된 카드만 등록 → viewport 후보 → 70ms 후 viewport 재필터 → 장착된 loader → 공용 cache/queue → 서버 → 위젯.

화면 밖 데이터가 첫 등록 또는 재필터 단계에서 빠질 수 있었다.

## [수정 후 처리 경로]

현재 로드된 목록 → postId registry에 번역 대상 전체 등록 → viewport는 우선순위만 부여 → 제한된 요청 접수 → 기존 공용 cache/queue → 기존 서버 → ID별 결과 → 해당 카드 표시.

Today와 로드된 과거 페이지, ALL, 카테고리 피드에 적용했다. 화면 밖 포스트도 별도 스크롤 없이 처리한다. 아직 로드하지 않은 페이지를 번역 목적으로 추가 조회하지 않는다. 데이터 검색·필터링·페이지네이션의 기존 조회 조건은 변경하지 않았다.

## [포스트 항목 식별 방식]

- Registry: postId, 현재 원문의 sourceHash.
- 카드/번역 위젯: postId 기반 key. 본문 hash나 목록 index를 Widget identity로 사용하지 않는다.
- Callable/공용 cache: 기존 `post::postId` 식별, 대상 언어, sourceHash, 계정별 로컬 cache 및 기존 버전 검증 유지.
- 본문·투표 옵션의 실제 문구만 번역 hash에 포함한다. 좋아요·댓글 수·조회수·투표 수 변경은 재번역하지 않는다.
- 본문 수정 시 그 postId의 항목만 교체하며, 이전 sourceHash의 늦은 결과는 새 항목에 적용하지 않는다.

## [포스트 scope 정책]

화면 생명주기 동안 고정된 `post-feed:<instance>:post:<postId>`를 사용한다. 목록 순서, 개수, pagination으로 scope를 새로 만들지 않는다. 상세의 `post:<postId>` 및 댓글의 `post-comments:<postId>`와 UI 상태를 분리한다.

목록 교체는 ID/원문 diff만 반영한다. 새 포스트, 삭제, 정렬, 카운터 변경이 정상 sibling의 번역 결과를 초기화하지 않는다. 계정/대상 언어 변경만 해당 세대 전체를 전환한다.

## [우선순위 정책]

1. Visible 포스트.
2. 기본 interactive 요청: 상세 본문, 펼친 댓글·답글 등 기존 호출자.
3. Near viewport.
4. Remaining loaded.
5. Pagination으로 새로 로드된 화면 밖 항목.

스크롤은 이전/현재 viewport 우선순위만 갱신하며, 요청 자체를 취소하지 않는다. Registry는 10번째 접수마다 오래 기다린 항목을, 공용 큐는 3번째 배치마다 오래 기다린 항목 한 자리를 우선해 starvation을 방지한다. 자동 요청 접수는 최대 10개, 기존 batch 5개·동시 batch 2개를 유지한다.

## [완전성 불변 조건]

각 등록 항목은 queued, loading, completed, sameLanguage, failedRetryable, failedFinal, removed 중 하나의 상태를 가진다.

`eligible = queued + loading + completed + sameLanguage + failedRetryable + failedFinal`

removed는 eligible에서 제외한다. queued/loading/failedRetryable이 남아 있으면 scope를 완료로 판정하지 않는다. 재시도를 소진한 실패도 성공으로 표시하지 않고 failedFinal로 유지한다.

개발/테스트용 검사로 eligible 집계, 결과 없는 completed, 요청 없는 loading, queue/pending 불일치, scheduler 누락 및 active batch 범위를 확인한다. 성공 로그는 verbose 모드에 한정하고 원문·문서 ID 대신 안전한 hash를 기록한다.

## [queue drain 및 recovery]

성공·부분 실패·예외 모두 `finally`에서 active slot을 반납하고 다음 queue를 확인한다. 플랫폼 응답이 멈춘 경우에도 70초 클라이언트 watchdog으로 무한 loading을 방지한다. 서비스가 제공하는 기존 항목별 재시도와 pending probe를 계속 사용한다.

첫 작업 묶음 drain 및 resume 시 registry의 결과 없는 고아 항목만 한 차례 복구한다. 서비스가 이미 재시도를 소진한 provider 실패를 registry가 다시 자동 번역하지 않는다. 사용자의 명시적 재시도가 성공하면 실패한 registry 항목만 최신 결과로 갱신한다.

스크롤마다 전체 재번역·전체 cache 삭제·전체 reconciliation을 실행하지 않는다. background에서는 신규 자동 접수를 멈추고 resume 시 이어간다. 이미 시작된 공유 요청은 다른 화면과 cache를 위해 완료할 수 있다.

## [부분 응답 처리]

기존 response ID Map을 유지한다. 응답 순서에 의존하지 않으며 알 수 없는 ID는 적용하지 않는다. 5개 중 세 번째 응답만 빠지면 그 항목만 재시도하고 정상 4개 결과는 보존한다. 빈 번역이나 필드 누락은 완료 cache에 넣지 않는다.

## [retry와 pending]

- 자동 일반 오류 재시도: 기존 최대 1회.
- 권한 없음/삭제: 자동 재시도하지 않음.
- 429/리소스 제한: 빠른 반복 호출 대신 15초 기반 backoff와 jitter.
- pending: 기존 제한된 probe를 사용하며 60초 서버 lock 이후의 복구 기회를 유지.
- 지속적인 pending: pending_timeout 실패로 끝내며 영구 loading으로 남기지 않음.
- 수동 재시도: 기존 15초 cooldown 및 실패 항목별 처리 유지.

실패는 성공 cache와 별개로 보관한다. 늦게 생성된 카드도 실패 상태를 인식하고 원문을 표시할 수 있다.

## [Feed·상세 cache 재사용]

UI scope는 분리하지만 동일 원문·대상 언어의 공용 memory/Hive cache 및 진행 중 요청은 공유한다. Feed와 상세에서 동시에 요청해도 같은 공용 요청을 재사용한다. 원문 → 번역 재전환은 API 호출 없이 표시만 전환한다.

화면 dispose는 공유 cache를 지우지 않는다. dispose, 계정 변경, 대상 언어 변경, 원문 수정 이후의 늦은 응답은 현재 UI에 잘못 적용하지 않는다.

## [댓글·답글 수정 보호]

기존 댓글/답글 policy와 화면 구현은 이번 작업에서 수정하지 않았다. 댓글의 `post-comments:<postId>` scope, 댓글/부모 답글을 구분하는 UI key, 서버의 실제 comment document ID를 유지했다.

공용 서비스의 새 priority는 선택 인자이며 기존 호출자는 interactive 기본값으로 동작한다. 포스트 실패 중 댓글 완료와 댓글 실패 중 포스트·답글 완료를 모두 테스트했다.

## [테스트 결과]

Flutter 선택 회귀 테스트 **85개 통과**:

| 구분 | 개수 | 검증 범위 |
|---|---:|---|
| 신규 registry | 15 | 전체 등록, 1/5/6/17개, offscreen, 우선순위, 빠른 스크롤, 삽입/삭제/정렬/수정, 고아 복구, 언어, resume |
| 신규 공용 queue | 35 | 실제 서비스+모의 Callable/Hive, batching/concurrency, 부분 응답, 오류 격리, timeout/pending, 계정/언어, 다양한 본문, 공용 콘텐츠 타입 |
| 신규 feed widget | 5 | 미생성 카드 결과 표시, refresh/pagination, toggle/cache, 실패 원문, dispose, 번역 높이 변화 시 읽던 위치 |
| 기존 댓글·본문 policy/언어 | 15 | `post_translation_policy_test.dart` 및 `content_translation_language_policy_test.dart` |
| 기존 notification/hash cache | 7 | 알림 병합, 불필요한 재계산 방지, hash 호환 |
| 기존 ALL/카테고리 | 5 | 빈 목록, 다음 페이지 종료, timeout/재시도, 생성 버튼 |
| 기존 SnackChat policy | 3 | 내 메시지/의미 없는 문구 제외, 다국어 본문 대상 유지 |

서버 코드는 수정하지 않은 채 기존 오프라인 회귀 스크립트 2개도 통과했다:

- `node functions/scripts/test_content_translation_latency.js`
- `node functions/scripts/test_content_translation_temporal_policy.js`

신규 핵심 파일·모델·서비스·테스트 8개 정적 분석: 문제 없음.
전체 수정 Dart 파일 14개 분석: error 0, 기존 화면 파일에 warning 14 / info 68 남음. 따라서 전체 analyze가 완전한 clean이라고 보고하지 않는다. `git diff --check` 통과.

실행 명령:

```sh
flutter test --no-pub test/post_translation_registry_test.dart test/post_translation_queue_test.dart test/post_translation_feed_test.dart test/post_translation_policy_test.dart test/content_translation_language_policy_test.dart test/content_translation_notifications_test.dart test/translation_source_hash_cache_test.dart test/all_posts_screen_test.dart test/post_category_feed_timeout_test.dart test/snack_chat_translation_policy_test.dart
```

### 성능·비용 확인

모의 정상 응답 환경에서 1/5/6/17개는 각각 1/1/2/4번의 batch 호출로 전체 완료했다. batch당 최대 5개, 동시 batch 최대 2개였다. 17개 중 지연 생성된 마지막 카드도 이미 준비된 cache로 표시했고 추가 API 호출은 없었다. 중간 응답 한 개 누락 시 해당 ID만 한 번 추가 요청했다.

결과가 변경된 카드만 rebuild하도록 기존 알림 최적화를 유지했다. 스크롤 시 전체 sourceHash 재계산 대신 viewport 우선순위만 갱신한다. 10,000회 hash 조회 합성 벤치마크는 기존 방식 186,097μs / 현재 cache 방식 4,027μs였으나, 이는 **실기기 번역 지연이나 FPS 측정이 아니다**.

이번 수정은 누락되던 offscreen 대상도 번역하므로, 그 항목을 아예 요청하지 않던 이전 오류 상태와 비교하면 총 호출량은 늘 수 있다. 이는 필요한 대상 복원이며 중복 요청·전체 재번역으로 비용을 줄이는 척하지 않는다. 운영 Gemini의 첫 번역 시간, p95, 전체 완료 시간 및 실제 요금은 이번 로컬 테스트로 실측하지 않았다.

### 실제 기기에 남은 검증

요청된 59개 시나리오는 위 테스트에서 여러 조건을 묶어 검증했지만, 모든 항목의 운영 기기 E2E를 수행한 것은 아니다. 특히 실제 문제가 있던 postId의 서버 로그 추적, 실제 Today↔ALL↔상세 navigation, 댓글/답글 작성·수정·삭제와 추가 페이지 로드, 그룹 권한 변경, iOS/Android 장시간 스크롤·실네트워크 복구·FPS 검증은 앱 업데이트 후 확인해야 한다. Gemini의 생성 번역 의미 품질은 모의 결과 테스트로 보증하지 않는다.

## [수정한 파일]

이번 요청에서 수정/추가한 제품 코드:

- `lib/models/content_translation.dart`: priority/항목 상태.
- `lib/services/content_translation_service.dart`: 우선순위/fairness, 결과 관측, watchdog, 진단.
- `lib/utils/post_translation_registry.dart`: 신규 loaded-data registry 및 제한된 복구.
- `lib/ui/widgets/post_translation_feed.dart`: 신규 화면 연결, viewport 우선순위, 읽던 위치 보정.
- `lib/ui/widgets/translatable_content.dart`: 실패 결과도 lazy 위젯에서 복원.
- `lib/ui/widgets/optimized_post_card.dart`: ID key 및 피드 scope 연결.
- `lib/ui/widgets/poll_post_widget.dart`: 동일 피드 scope/요청 재사용.
- `lib/screens/board_screen.dart`: 기존 viewport-only 자동 번역 경로 교체.
- `lib/screens/all_posts_screen.dart`, `lib/screens/post_category_feed_screen.dart`: 로드된 데이터 등록.

신규 테스트: `test/post_translation_registry_test.dart`, `test/post_translation_queue_test.dart`, `test/post_translation_feed_test.dart`, `test/support/translation_test_backend.dart`.

## [Cloud Functions 변경]

**없음.** 이번 요청으로 함수 수정·재배포를 하지 않았다. 워크트리에 보이는 기존 서버 변경은 이전 작업분이다.

## [Firestore 구조 변경]

**없음.** 컬렉션, 인덱스, 보안 규칙, 운영 데이터 변경 없음.

## [번역 version 변경]

**없음.** 기존 translation/prompt v7, quality v2 및 기존 wire 호환 검증 유지. 기본 Gemini 3.5 Flash Lite와 기존 Flash fallback 정책도 변경하지 않았다.

## [기존 기능 보호]

| 기능 | 이번 검증 상태 |
|---|---|
| 포스트 | 번역·피드 선택 회귀 테스트 통과. 작성/수정/삭제/좋아요/이미지 데이터 로직 변경 없음. 운영 CRUD E2E 미실행 |
| 댓글 | 기존 관련 테스트와 독립 queue 실패 격리 통과. 기존 화면/CRUD 코드 변경 없음 |
| 답글 | ID/부모 scope 정책 및 공용 queue 테스트 통과. 운영 답글 pagination E2E 미실행 |
| SnackChat | 기존 policy + 공용 번역 타입 테스트 통과. 실기기 채팅 송수신 E2E 미실행 |
| DM | 공용 번역 타입 테스트 통과. DM 화면/송수신 코드 변경 없음, E2E 미실행 |
| 밋업 | 공용 번역 타입 테스트 통과. 생성/참여/달력 코드 변경 없음, E2E 미실행 |
| push | 이번 수정 없음. 푸시 전송 E2E 미실행 |
| badge | 이번 수정 없음. 기기 배지 E2E 미실행 |

배포 측면에서는 **수정된 Flutter 앱을 빌드·업데이트해야 반영된다**. 이번에는 Android/iOS release 빌드나 스토어 업로드를 수행하지 않았다. 이 클라이언트 수정만을 위해 Firebase를 추가 배포할 필요는 없다.
