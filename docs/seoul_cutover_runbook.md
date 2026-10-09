# 서울(asia-northeast3) 전환 런북

작성일 2026-10-05. 대상 프로젝트 `flutterproject3-af322`. 계획 원문은
`/Users/chajaemin/.claude/plans/zazzy-wiggling-noodle.md`(승인본), 배경은
`docs/seoul_region_migration_plan.md`.

## 결정 사항 요약

| 항목 | 결정 |
|---|---|
| Firestore | `(default)`(nam5)를 export → 삭제 → 5분 뒤 asia-northeast3에 `(default)`로 재생성 → import. DB ID가 같으므로 앱·서버의 DB 선택 코드, `storage.rules`, 1세대 Firestore 트리거는 수정하지 않음 |
| Functions | 콜러블(103)과 이벤트 함수(트리거 47 + 스케줄 6)를 **리전 환경변수로 분리**. 콜러블은 전환 전에 서울 선배포, 이벤트 함수는 전환 창에서만 이동 |
| Storage | 기존 객체는 US 버킷에 그대로. 신규 업로드만 서울 버킷으로. 소유 문서에 `storageBucket` 기록, 없으면 레거시 버킷으로 해석 |
| 구버전 앱 | 1.3.24 배포 후 Remote Config 강제 업데이트. 전환 시 us-central1 콜러블 삭제 |
| 전환 창 | 저트래픽 시간대, 목표 6시간 이내(반나절까지 허용) |

## P0에서 코드에 들어간 것 (배포 없음, 동작 변화 없음)

서버 `functions/`
- `src/backend.ts`: `callables()`/`triggers()` 빌더 팩토리(리전은 소스 상수
  `DEFAULT_CALLABLE_REGION`/`DEFAULT_EVENT_REGION`), `uploadBucket()`,
  `bucketFor(storageBucket)`, `allKnownBuckets()`, `withMailSecrets()`.
- 모든 1세대 빌더가 `callables.*`/`triggers.*`를 통해 생성됨. `onReportCreated`만
  `triggersIn('asia-northeast3')`(현재 서울 배포 유지).
- `functions.config()` 제거. `GMAIL_USER`는 `.env`, `GMAIL_PASSWORD`는
  Secret Manager(`withMailSecrets`가 메일 발송 함수 7개에 바인딩).
- Storage: 스냅(createSnapshot·피드 댓글 GIF·정리), 스낵챗 파일(prepare/commit/
  cancel/삭제 트리거), 외부 공유 포스트 이미지, 인스타그램 썸네일, 계정 삭제 시
  프로필 사진 정리가 모두 버킷 인식. 새 객체는 `UPLOAD_STORAGE_BUCKET`에 쓰고
  `storageBucket`(링크 프리뷰는 `thumbnailStorageBucket`)을 문서에 기록.
- `scripts/functions_only_filter.js`: 빌드 산출물에서 콜러블/이벤트 `--only`
  필터와 리전 인벤토리 출력. `scripts/compare_databases.js`: 전수 count+해시 비교.

클라이언트 `lib/`
- `config/app_backend.dart`: `AppFunctions.instance`, `AppStorage.uploads /
  forObject / ref / refFromUrl / allKnown`. 값은
  `assets/release/release_metadata.json`의 `backend` 블록(`functionsRegion`,
  `uploadStorageBucket`, `legacyStorageBucket`)에서 읽고, 컴파일 기본값과 일치
  여부를 `scripts/release_guard.py`가 검사(`functions/.env`의 업로드 버킷도 비교).
- Functions 호출 28곳 → `AppFunctions.instance`. 업로드 전부 → `AppStorage.uploads`.
- `storageBucket` 필드: DM 파일 메시지, 스낵챗 이미지/파일 메시지(+로컬 캐시·
  업로드 큐), 포스트 댓글 GIF, 스냅(아이템·피드 댓글·코멘트 레터),
  링크 프리뷰(`thumbnailStorageBucket`). 읽기는 모두 `AppStorage.forObject`.
  버킷이 기록되지 않은 경로 전용 참조(답장 미리보기 등)는 레거시 → 업로드 버킷 순으로 재시도.
- `ProfilePhotoPolicy`: 레거시·업로드 버킷 모두 허용.
- Firestore 규칙은 변경 없음(메시지/댓글 생성 규칙에 `hasOnly`가 없어 추가 키 허용
  — `firestore.rules` 1676~1979, 2340~2400, 1335~1499 확인함).

현재 값(P0): `functionsRegion=us-central1`, 업로드 버킷=레거시, `.env`도 동일.
→ 빌드해도 동작이 바뀌지 않는다.

## P1 — 인프라·리허설 (사용자 영향 없음)

0. 인증·비밀
   ```bash
   gcloud auth login && gcloud config set project flutterproject3-af322
   firebase login
   # 메일 비밀번호를 Secret Manager로 (값: 기존 functions:config:get gmail.password)
   firebase functions:secrets:set GMAIL_PASSWORD
   ```
   이 비밀이 없으면 이후 모든 `firebase deploy --only functions`가 실패한다.
   임시 우회: `.env`에 `WEFILLING_MAIL_SECRET=off`(메일 발송 건너뜀).
1. 사전 확인(계획 위험 #1)
   ```bash
   gcloud app describe            # "does not contain an App Engine application" 이어야 함
   gcloud firestore databases describe --database='(default)'   # locationId nam5, deleteProtection 확인
   ```
   App Engine 앱이 있으면 중단 → 재계획(named DB + Storage 권한 재설계).
2. 버킷 생성
   ```bash
   gcloud storage buckets create gs://flutterproject3-af322-fs-export --location=US --uniform-bucket-level-access
   gcloud storage buckets create gs://flutterproject3-af322-fs-import --location=asia-northeast3 --uniform-bucket-level-access
   gcloud storage buckets create gs://flutterproject3-af322-kr --location=asia-northeast3 --uniform-bucket-level-access
   ```
   Firebase 콘솔 → Storage → "버킷 추가"로 `flutterproject3-af322-kr`를 연결(Firebase 규칙 적용 대상이 됨).
   `firebase.json`의 `storage`를 배열로 바꿔 두 버킷에 같은 규칙 배포:
   ```json
   "storage": [
     {"bucket": "flutterproject3-af322.firebasestorage.app", "rules": "storage.rules"},
     {"bucket": "flutterproject3-af322-kr", "rules": "storage.rules"}
   ]
   ```
   `firebase deploy --only storage` 후 콘솔에서 두 버킷 규칙이 같은지 확인.
   그다음 `functions/.env`의 `WEFILLING_UPLOAD_BUCKET=flutterproject3-af322-kr`로
   변경(아직 배포하지 않음. 배포는 P1-5에서 콜러블과 함께).
3. 인덱스 export: `scripts/export_live_indexes.sh` → `firestore.kr.indexes.json`
   (2026-10-05 실행 완료: 복합 59 + override 7, TTL 5. 로컬 `firestore.indexes.json`(50)은 사용 금지.
   전환 직전에 한 번 더 실행해 최신 상태로 갱신).
4. 리허설(데이터 검증 전용 named DB)
   ```bash
   gcloud firestore databases create --database=rehearsal --location=asia-northeast3 --type=firestore-native
   T=$(date -u +%Y-%m-%dT%H:%M:%SZ)
   gcloud firestore export gs://flutterproject3-af322-fs-export/rehearsal-$T --database='(default)'
   # --snapshot-time 은 PITR이 켜진 DB에서만 가능하다. 현재 (default)는 PITR OFF라 쓰지 않는다.
   # 전환 창에서는 동결 후 쓰기가 0이므로 일반 export가 그대로 일관된 스냅샷이다.
   gcloud storage cp -r gs://flutterproject3-af322-fs-export/rehearsal-$T gs://flutterproject3-af322-fs-import/
   gcloud firestore import gs://flutterproject3-af322-fs-import/rehearsal-$T --database=rehearsal
   cd functions
   node scripts/compare_databases.js --snapshot out/us.json --sample 200
   node scripts/compare_databases.js --snapshot out/rehearsal.json --database rehearsal --sample 200
   node scripts/compare_databases.js --compare out/us.json out/rehearsal.json   # exit 0 기대
   gcloud firestore databases delete --database=rehearsal
   ```
   export·copy·import 각 소요 시간을 기록(전환 창 길이 산정).
5. 서울 콜러블 선배포
   - `functions/src/backend.ts`: `DEFAULT_CALLABLE_REGION = 'asia-northeast3'` (이벤트 리전 상수는 그대로).
   ```bash
   cd functions && npm run build
   node scripts/functions_only_filter.js all --table | awk -F'\t' '{print $2, $3}' | sort | uniq -c
   #   callable asia-northeast3 103 / event us-central1 46 / event asia-northeast3 1 / schedule us-central1 6 이어야 함
   cd .. && firebase deploy --only "$(node functions/scripts/functions_only_filter.js callables)"
   ```
   삭제 프롬프트("us-central1의 … 삭제하시겠습니까")에는 **아니오**(구버전 앱 유지).
   `node scripts/audit_firebase_function_regions.js`로 콜러블이 양 리전에 있는지 확인.
   이 시점부터 P3 전까지 `firebase deploy --only functions`(전체)를 실행하지 말 것.
   핫픽스는 반드시 필터 사용: 콜러블은 위 명령, 이벤트는
   `--only "$(node functions/scripts/functions_only_filter.js events)"`.
6. 동결 도구 리허설: `FREEZE_ONLY=getUserProfileStats scripts/freeze_old_backend.sh freeze` → `status` → `unfreeze`.
7. 스케줄 함수 서울 배포 가능 여부: 함수 1개(`cleanupExpiredEmailVerifications`)를
   `backend.ts`의 `DEFAULT_EVENT_REGION`을 잠시 `asia-northeast3`로 두고
   `firebase deploy --only functions:cleanupExpiredEmailVerifications`(us-central1 삭제 **아니오**)
   → Cloud Scheduler 작업이 asia-northeast3에 생기면 OK, 확인 후 서울 사본 삭제
   (`firebase functions:delete cleanupExpiredEmailVerifications --region asia-northeast3`) 및 `.env` 복원.
   실패하면 스케줄 6개를 2세대 `onSchedule`로 전환하는 별도 작업 필요.

## P1 실행 기록 (2026-10-05)

| 단계 | 결과 |
|---|---|
| P1-1 App Engine | `gcloud app describe` → "does not contain an App Engine application". `(default)`: nam5, delete protection OFF, PITR OFF(버전 보존 1h) |
| P1-2 버킷 | `-fs-export`(US), `-fs-import`(asia-northeast3), `-kr`(asia-northeast3) 생성. `-kr`는 REST `buckets/{b}:addFirebase`로 Firebase에 연결. `firebase.json` storage 배열화 후 두 버킷에 `storage.rules` 배포 완료. `functions/.env` 업로드 버킷 = `-kr` |
| P1-3 인덱스 | `firestore.kr.indexes.json` 복합 59 + override 7(TTL 5) |
| P1-4 리허설 | export 58s(23.7MB, 27,775 문서) → copy 8s → import 206s → 인덱스 59개 READY·TTL 5개 ACTIVE ≤ 6분. `compare_databases.js`: 차이 30건 전부 export 이후 8분간 운영 쓰기/TTL 삭제분(쓰기 동결 시 MATCH 기대). 리허설 DB 삭제 완료 |
| P1-5 콜러블 선배포 | `backend.ts` `DEFAULT_CALLABLE_REGION='asia-northeast3'`. **콜러블 103개 서울 생성 완료**(us-central1 사본 유지, 12개 단위 분할 배포). `GMAIL_PASSWORD` secret 생성 후 메일 함수 7개 + `onReportCreated`(secret 바인딩) 배포. 1차 시도는 us-central1 업데이트로 들어갔다(아래 "사고 기록") |
| P1-6 동결 도구 | `freeze_old_backend.sh status us-central1` 정상(스케줄 7 job, 콜러블 open 확인). freeze/unfreeze 실행은 전환 창에서 |
| P1-7 스케줄 리전 | `gcloud scheduler locations list`에 asia-northeast3 포함 → 1세대 스케줄 함수 서울 배포 가능 |

사고 기록 (2026-10-05, P1-5 1차 시도)
- `firebase deploy`는 함수 목록을 찍어낼 때 코드를 **FUNCTIONS_EMULATOR=true** 로 로드한다. `backend.ts`가 에뮬레이터
  플래그를 보고 리전을 us-central1로 강제하던 바람에, 서울 선배포가 기존 us-central1 콜러블 96개 **업데이트**로
  실행됐다(신규 6개 포함: 조직 계정 콜러블 5 + `backfillInstagramPreviewThumbnails`). 삭제 프롬프트는 뜨지 않았다.
- 영향: us-central1 콜러블이 새 코드 + `.env`(업로드 버킷 `-kr`)로 실행된다. URL 기반 서버 업로드(외부 공유 포스트
  이미지, 인스타 썸네일)는 `-kr`에 저장되어도 URL에 버킷이 포함되어 구버전 앱에서 정상. 유일한 위험은
  `prepareSnackChatFileUpload`가 job에 `-kr`을 기록하는데 구버전 앱은 레거시 버킷에 올리므로 commit이 404로 실패하는 것.
- 추가 원인: `firebase deploy`는 함수 목록을 분석하는 단계에 **`.env` 값을 전달하지 않는다**(`.env`는 배포된 함수의
  런타임 env에만 적용). 리전을 `.env`로 결정하는 설계 자체가 틀렸다. 리전은 `backend.ts`의
  `DEFAULT_CALLABLE_REGION`/`DEFAULT_EVENT_REGION` 소스 상수로 옮겼고(커밋으로 변경), `.env`에는 리전 키가 없다.
  단일 함수(`getSnapshotServerTime`)로 "asia 생성 + us-central1 삭제 질문에 n" 동작을 확인한 뒤 전체 선배포.
- 교정: (1) `backend.ts`에서 에뮬레이터 리전 강제 제거, 리전 소스 상수화.
  (2) 파일 업로드 job 버킷은 서버 env가 아니라 **클라이언트가 선언한 버킷**(`storageBucket` 요청 필드, 없으면 레거시)으로
  기록·반환하고, pending job의 버킷이 다르면 재지정. (3) `.env`를 잠시 `WEFILLING_CALLABLE_REGION=us-central1`로 두고
  `prepareSnackChatFileUpload`,`commitSnackChatFileUpload`,`cancelSnackChatFileUpload`를 us-central1에 재배포 → `.env`를
  asia로 복원 → 96개 서울 선배포(expect 래퍼, 삭제 "n").
- 교훈: 배포 전 `FUNCTIONS_EMULATOR=true node scripts/functions_only_filter.js all --table`로 리전을 확인하고,
  첫 배포는 함수 1개로 리전을 검증한 뒤 전체를 배포한다.

발견 사항
- `firebase-functions` v1 `FunctionBuilder.runWith()`는 빌더 자신을 변경한다. 공용 빌더 인스턴스를 쓰면 한 함수의
  runtime 옵션(메모리·timeout·secrets·enforceAppCheck)이 다른 함수로 새어 나간다. `backend.ts`의
  `callables()`/`triggers()`는 호출마다 새 빌더를 돌려주는 팩토리로 바꿨고, HEAD 빌드와 새 빌드의 함수별
  `__endpoint` 옵션을 전수 비교해(156개) 의도한 차이(메일 secret 8개, DM bounded read 60s/256MB)만 남음을 확인했다.
  → `node scripts/functions_only_filter.js all --json --lib <other-build>` 로 재검증 가능.
- 1세대 함수를 한 리전에 수십 개 **신규 생성**하면 Cloud Build `Other API requests per minute` 할당량에 걸려 일부가
  "Build failed: Quota exceeded"로 실패한다(96개 중 27개만 성공). 업데이트는 영향이 적다. 생성은 12개씩 끊어 75초 간격으로
  배포하면 통과한다. P3의 이벤트 함수 53개 서울 생성도 같은 방식으로 나눠 배포할 것(전환 창 시간에 반영: 약 15~20분).
- Cloud Scheduler에 코드에 없는 잔여 job `firebase-schedule-expireSnackChats-us-central1`이 있다(과거 삭제된 함수).
  전환 시 us-central1 정리에 포함할 것: `gcloud scheduler jobs delete firebase-schedule-expireSnackChats-us-central1 --location us-central1`.
- `(default)`는 PITR OFF라 `--snapshot-time` export가 불가. 전환 창은 동결 후 일반 export로 진행한다.

P1 완료(2026-10-05 11:40 UTC): `GMAIL_PASSWORD` secret 생성(사용자) → 메일 함수 7개 + `onReportCreated` 서울 배포 →
asia-northeast3 콜러블 103개 ACTIVE, us-central1 사본 전부 유지. 서울 엔드포인트 스모크(`getSnapshotServerTime` →
UNAUTHENTICATED 응답, 정상 도달) 확인.

P2 코드 준비 완료: `release_metadata.json` `backend` = asia-northeast3 / `-kr`, `app_backend.dart` 기본값 동일, 가드 PASS.
남은 것은 사용자의 스토어 빌드·배포와 Remote Config 강제 업데이트(아래 P2).

## P2 — 앱 1.3.24 (DB는 아직 nam5)

1. (완료) `assets/release/release_metadata.json` `backend` = asia-northeast3 / `flutterproject3-af322-kr`,
   `lib/config/app_backend.dart` 기본값 동일. `release_guard.py`가 둘의 일치를 검사한다.
2. 디버그 빌드로 스모크: 포스트 이미지, 프로필 사진, DM 파일, 스낵챗 이미지/파일,
   스냅(사진·영상·GIF 댓글), 밋업 이미지, 인스타 공유 → 콘솔에서 `-kr` 버킷에 객체 생성 확인,
   기존(US) 이미지가 계속 보이는지 확인.
3. 스토어 배포(`scripts/android_release.sh`, iOS) → 승인 후 Remote Config
   `*_minimum_build=<1.3.24 build>`, `*_force_update=true`(`scripts/prepare_remote_config.py`).
4. 1주 채택률 확인. 서울 콜러블은 nam5 DB를 원격으로 사용(느리지만 정상).

## P3 — 전환 창

사전: 담당 2인, 커뮤니티 공지, P1 리허설 소요 시간 × 1.5 를 창으로 확보.

| # | 단계 | 명령 | 판정 |
|---|---|---|---|
| 1 | 동결 | `scripts/freeze_old_backend.sh freeze us-central1` / `… freeze asia-northeast3` | `status`에 open 없음, 스케줄 전부 PAUSED |
| 2 | 클라이언트 쓰기 차단 | `firebase deploy --config firebase.cutover.json --only firestore:rules` | 15분 대기, Monitoring 쓰기율 0 |
| 3 | 백업 | 동결·쓰기율 0 확인 후 `T=$(date -u +%Y-%m-%dT%H:%M:%SZ)` → `gcloud firestore export gs://…-fs-export/cut-$T --database='(default)'`(PITR OFF이므로 `--snapshot-time` 없이) → 완료 대기 → `gcloud storage cp -r … gs://…-fs-import/` → `node functions/scripts/compare_databases.js --snapshot out/cut-us.json` | export 완료, 스냅샷 파일 저장 |
| 4 | 삭제 | `gcloud firestore databases update --database='(default)' --no-delete-protection` → `gcloud firestore databases delete --database='(default)'` | |
| 5 | 재생성 | 5분 대기 → `gcloud firestore databases create --database='(default)' --location=asia-northeast3 --type=firestore-native --delete-protection --enable-pitr` | describe에 asia-northeast3 |
| 6 | 보호·스키마 | `firebase deploy --config firebase.cutover.json --only firestore` (denyall 규칙 + `firestore.kr.indexes.json`) → `gcloud firestore indexes composite list`로 READY, `gcloud firestore fields ttls list`로 TTL 5개 | 인덱스 전부 READY |
| 7 | import | `gcloud firestore import gs://…-fs-import/cut-$T --database='(default)'` | 완료 |
| 8 | 검증 | `node functions/scripts/compare_databases.js --snapshot out/cut-kr.json` → `--compare out/cut-us.json out/cut-kr.json` | `MATCH` |
| 9 | 이벤트 함수 | `functions/src/backend.ts` `DEFAULT_EVENT_REGION = 'asia-northeast3'`로 변경·커밋 → `cd functions && npm run build && node scripts/functions_only_filter.js all --table`로 전부 asia 확인 → `firebase deploy --only functions` (us-central1 전부 삭제 **예**) | `audit_firebase_function_regions.js`: us-central1 0 |
| 10 | 규칙 | `firebase deploy --only firestore:rules` (실제 `firestore.rules`), `firebase deploy --only storage` | |
| 11 | 해제 | `scripts/freeze_old_backend.sh unfreeze asia-northeast3` (스케줄 resume + invoker) | |
| 12 | 스모크 | 내부 계정으로 포스트·댓글·좋아요·밋업 참여·DM(텍스트/파일)·스낵챗(텍스트/이미지/파일)·스냅·신고 메일 각 1회. 로그는 asia-northeast3에만 | 전부 성공 |

**롤백(창 안)**: 서울 `(default)` export → 삭제 → 5분 → nam5 재생성 →
`cut-$T` import → `DEFAULT_EVENT_REGION`을 `us-central1`로 되돌려 빌드 → `firebase deploy --only functions`
(asia 이벤트 삭제 예) → 실제 규칙 배포 → 동결 해제. 앱 1.3.24는 서울 콜러블을
그대로 사용하므로 동작한다.

## P3 실행 기록 (2026-10-05, UTC)

| 시각 | 단계 | 결과 |
|---|---|---|
| 12:35–12:44 | 동결 | us-central1 스케줄 7개 PAUSED, 콜러블 invoker 제거 us-central1 106 / asia 103 |
| 12:45 | 쓰기 차단 | `firestore.denyall.rules` 배포 |
| 12:46→12:56 | 정지 확인 | 스냅샷 2회 비교: 사용자 쓰기 0, TTL 마커 삭제 2건만 |
| 12:56–12:57 | export | `cut-2026-10-05T12:56:51Z`, SUCCESSFUL, 27,791 문서, 23.7MB, import 버킷 복사 완료. 기준 스냅샷 `…-snapshot.json` 보관 |
| 12:59 | 삭제 | 미국 `(default)` 삭제 |
| 13:04 | 재생성 | 서울 `(default)` 생성 (delete protection ON, PITR ON, 7일 보존). ID 재사용 대기 5분 20초 |
| 13:05–13:12 | 스키마 | denyall 규칙 + 복합 인덱스 59 READY + TTL 5 ACTIVE (320초) |
| 13:13–13:16 | import | SUCCESSFUL 27,791 문서 (194초) |
| 13:16 | 검증 | 전수 비교: 사용자 데이터 전부 일치, 차이는 TTL이 삭제한 `_snack_chat_function_events` 마커 1개 |
| 13:17–13:34 | 이벤트 함수 | 53개 서울 생성(52 create + 1 update), us-central1 사본 51개 삭제. 할당량 실패 0 |
| 13:34 | 잔여 정리 | HEAD에 없던 옛 트리거 8개 us-central1에서 삭제 |
| 13:35 | 규칙 복원 | `firestore.rules` 배포 → 앱 읽기/쓰기 재개 |
| 13:36–13:45 | 동결 해제 | 콜러블 invoker 복원 asia 103 / us-central1 106, 스케줄 6개 ENABLED |

- 전면 중지 시간: 12:45 → 13:35 (규칙 기준 50분), 콜러블 완전 복원 13:45 (60분).
- Cloud Scheduler job은 함수 리전과 무관하게 **us-central1 location**에 생성된다(`firebase-schedule-*-asia-northeast3`).
  `freeze_old_backend.sh`로 스케줄을 다룰 때는 리전 인자를 `us-central1`로 줘야 한다.

- 결정: us-central1 콜러블은 1.3.23 앱을 위해 유지(강제 업데이트 전까지). 1.3.24 채택 후 별도 삭제.
- 발견: us-central1에 HEAD 소스에도 없는 옛 트리거 8개가 남아 있었음(`expireSnackChats`, `onFriendCategory{Updated,Deleted}Sync{Meetup,Post}AllowedUsers`,
  `onMeetupAudienceUpdatedCleanupParticipants`, `onSnapshotFriendCategoryChanged`, `onSnapshotFriendshipChanged`). 옛 코드가 서울 DB에
  반응하지 않도록 이벤트 함수 이전 직후 삭제.

## 전환 직후 발견·조치 (2026-10-06)

1. **스낵챗 이미지 전송 실패 + 무한 재전송** (서울 백엔드용 빌드에서 발생)
   - 원인 1: 메시지 생성 규칙의 `keys().hasOnly([...])`가 새 필드 `storageBucket`을 거부 → permission-denied.
   - 원인 2: 거절된 메시지를 아웃박스 복구가 자동 재시도(5회 백오프 후 앱 복귀 시 리셋) → 체감상 무한 반복.
   - 조치: 규칙에 `storageBucket`(레거시/서울 버킷만) 허용. 클라이언트는 규칙 거절(`wasSendRejected`)된 메시지를
     `_definitivelyRejectedIds`로 표시해 자동 재시도에서 제외하고, 수동 재시도(탭/메뉴)만 허용.
   - 에뮬레이터 테스트 추가: 이미지+레거시/서울 버킷 허용, 외부 버킷·텍스트 메시지의 버킷 필드 거부.
2. **규칙 1,000식 한도 여유 확보**: 에뮬레이터 커버리지 측정으로 `currentUserAccountAllowed()`(사용자 문서 get +
   16개 비교)가 요청당 최대 8회 평가됨을 확인. 메시지 생성은 `isChatParticipant()` 대신 이미 읽은 `roomBefore`로
   참여자 확인, 방 미리보기 업데이트는 같은 요청의 메시지 생성이 계정 상태를 이미 검증하므로 참여자 여부만 확인,
   `validImage`는 중복 검사 제거. (테스트 하네스가 이미지 미리보기를 `'[이미지]'`로 보내지 않아 실패 분기를 모두
   타며 한도를 넘긴 것이 처음 관측의 직접 원인이었고, 하네스도 수정.)
3. **이미지 업로드 속도**: 피커가 이미 1800px/q88 JPEG로 재인코딩하므로 600KB 이하 JPEG는 재압축 생략,
   크기는 픽셀 디코딩 없이 헤더(`ImageDescriptor`)로 읽음, 확인 시트가 열린 동안 압축·측정을 미리 수행,
   업로드는 메모리 바이트로 `putData`. DM 이미지도 같은 경로를 사용.
4. **푸시 콜드스타트 제거**: `onSnackChatMessageCreated`, `onDMMessageCreated`, `markDMConversationReadBoundedSecure`에
   warm instance 1개(`runtime_scaling.ts` `DEFAULT_CHAT_HOT_MIN_INSTANCES = 1`, 소스 상수). Firebase 추정 최소 비용
   월 $15.86(+us-central1 사본 $0.62). 되돌리려면 상수를 0으로 바꿔 세 함수를 재배포.
5. **배포 래퍼 사고**: `deploy_functions_keep_existing.sh`의 느슨한 정규식이 CLI가 다시 그린 "proceed with deployment? (Y/n) y"
   줄에 재매치해 키 입력 "y"를 한 번 더 보냈고, 그 입력이 다음 "삭제" 질문에 소비되어
   `markDMConversationReadBoundedSecure`의 us-central1 사본(그다음엔 asia 사본)이 삭제됐다. 두 번 모두 즉시 재생성했고
   (클라이언트는 not-found 시 Firestore 호환 읽음 처리로 폴백해 사용자 영향 없음), 래퍼는 질문 종류별로 한 번만
   응답하도록 고쳤다. 현재 양 리전 모두 ACTIVE.
6. **채팅 번역 기본값 = 원문**: `ContentTranslationService.showsOriginal`에서 `snack-room:*`/`dm-conversation:*` 스코프는
   저장된 방별 설정이 없으면 원문. 번역을 켠 방(저장값 false)은 유지. 포스트·댓글 등 다른 스코프는 변화 없음.

## 알림·배지·송수신 점검 결과와 조치 (2026-10-06)

사용자가 정리한 8개 요구를 코드 기준으로 점검한 결과. 상태: ✅ 구현됨 / 🔧 이번에 보완 / ⏳ 미해결(별도 작업).

| 구분 | 상태 | 내용 |
|---|---|---|
| 배지 정확성 | ✅ | 기기 배지 = 일반 알림 + DM + 스낵챗(`badge_service.dart`), 서버 push도 같은 합산 |
| | 🔧 | 서버가 `notificationUnreadTotal`을 버전 확인 없이 쓰던 것을 기기와 같은 규칙으로 통일(`functions/src/badge_policy.ts`). DM 푸시에 Android `notificationCount`(방별 안 읽음) 추가. 로그아웃 시 iOS에서도 전달된 카드 전부 제거 |
| | ⏳ | Android 기본 런처(Pixel 등)는 OS가 숫자 배지를 지원하지 않음. 다른 기기에서 읽어도 이 기기 배지는 다음 푸시/앱 열기 전까지 갱신되지 않음(무음 푸시 필요). DM 총합 reconcile은 버전 이전 시 1회만 |
| 알림 진입 안정성 | 🔧 | 로그아웃→재로그인 뒤 푸시 탭이 영구 대기하던 문제: `MainScreen`에서 라우팅 재무장. `recipientUserId` 없는 payload(광고·To-do)도 대기열 유지. 로컬 알림 탭으로 콜드스타트하는 경우 `getNotificationAppLaunchDetails`로 라우팅. 포스트 로드에 12초 상한(푸시 라우터·알림 화면). DM 방을 오프라인·캐시 없음 상태로 열면 스켈레톤이 영원히 남던 것을 12초 상한 + 재시도 UI로 교체 |
| 방별 알림 정리 | ✅ | 스낵챗: 방별 tag/collapse/thread, 최신 메시지로 교체 |
| | 🔧 | DM: iOS `apns-collapse-id`·`thread-id`, Android `collapseKey` 추가(이전엔 iOS에서 메시지마다 카드가 쌓임). Android에서 FCM이 그린 카드와 앱이 그린 카드가 같은 방에 두 장 보이던 것을 로컬 카드 표시 전 (tag, id 0) 슬롯 취소로 해결. V2 표시(방 제목/발신자/안 읽음 부제, MessagingStyle 이력) 서버·클라이언트 모두 기본 ON |
| 읽음 후 정리 | ✅ | 읽음 RPC 경계 이하 카드만 제거, 다른 방·새 메시지 카드 유지(native 양쪽) |
| | 🔧 | 콘텐츠 열람 자동 읽음(`ACTIVE_CONTENT_AUTO_READ`) 기본 ON: 포스트·밋업·스냅·프로필·리뷰 화면이 보이는 동안 해당 알림 문서를 읽음 처리하고 OS 카드 제거 |
| 새 알림 보호 | ✅ | 방 단위·경계 기반 취소만 사용. 전체 취소는 로그아웃/방 나가기만 |
| 전달 안정성 | ✅ | 토큰 레지스트리 소유권 이전·필터, 이벤트 마커 멱등, 3회 재시도 상한, 무효 토큰 정리 |
| | 🔧 | 탈퇴·미완료 계정 로그아웃 경로 4곳에서 토큰 해제가 빠져 있던 것 보완. `registerFcmToken` 실패 후 레거시 저장만 남는 경우 30초→최대 4회 재등록 시도. 일반 알림 로컬 카드 id를 iOS에서도 알림 문서 기준으로 고정(재전달 시 중복 카드 방지) |
| | ⏳ | FCM 전송 성공 직후 프로세스가 죽으면 재시도에서 1회 중복 가능(at-least-once). 그룹 DM은 `recipients[0]`에만 발송 |
| 표시 일관성 | 🔧 | DM 푸시 제목 `From 'x'`→발신자 이름, 본문·익명·사진 문구를 수신자 앱 언어(ko/en/zh)로. 스낵챗 `Snack Chat`/`Someone` 영어 고정 문구를 언어별로. Android 상태바 아이콘을 단색 `ic_notification`(5 밀도) + 포인트 색으로 지정(흰 사각형 문제) |
| | ⏳ | 일반 알림(좋아요·댓글 등) 템플릿은 ko/en만, 중국어 UI 사용자는 한국어로 수신 |
| 송수신 최적화 | ✅/🔧 | 서울 전환 완료, 스낵챗 직접 읽음 커서는 플래그 OFF 유지(앱 강제 종료 시 방 안 읽음 수 불일치 가능). 방 빠른 진입(DM·스낵챗)·수신 캐시 오프로드 기본 ON. 이미지 업로드 사전 압축, hot 함수 warm instance |

추가 결함(2026-10-06): **친구인데 친구 목록에 안 보임**. 친구·참여자 프로필 일괄 조회(`UsersRepository._loadClaimedProfiles`)가
"검색 노출" 규칙(`isSearchableUserAccountData`: 닉네임 `[a-zA-Z0-9가-힣_.]`만 허용, 검색 비공개·프로필 비공개 제외)으로
걸러서, 중국어·공백 닉네임이나 검색을 꺼 둔 친구가 목록에서 사라졌다. 관계 기반 목록은 탈퇴·정지·미완료 계정만 제외하는
`isVisibleUserAccountData`를 쓰도록 분리(검색 화면은 기존 규칙 유지). 테스트 `test/account_visibility_policy_test.dart`.

추가 결함(2026-10-07): **앱 아이콘으로 들어가 읽어도 스낵챗·DM 푸시 카드가 남고, 아이콘 숫자가 남는 경우**.
- 원인 1: OS 카드 제거가 "읽음 callable이 성공하고 cleared > 0"일 때만 실행됐다. 다른 기기에서 이미 읽었거나 callable이
  건너뛰어지면(읽을 것이 없음) 카드가 남았다. 원인 2: Android에서 FCM이 직접 그린 카드는 메타데이터 수신기가 기록한
  경우에만 찾을 수 있어, 기록이 없으면 제거 결과 -1로 끝났다. 원인 3: 배지 재계산이 캐시된 사용자 문서를 써서 방금 낮아진
  카운터가 반영되기 전 값으로 다시 그려졌다.
- 조치: 방 화면에서 최신 서버 메시지가 보일 때마다(`_scanConfirmedReadBoundary` / `_scheduleAutoMarkAsRead` 경로, 진입·
  재개·새 메시지 모두 포함) 읽음 callable과 무관하게 그 방의 카드를 `removeAllInRoom`으로 제거하고(네이티브 DM 분기에
  `removeAllInRoom` 추가), Android는 추가로 (tag, id 0) 슬롯과 로컬 카드 슬롯을 직접 취소(`cancelNotificationSlot`).
  배지는 `BadgeService.refreshNow(fresh: true)`로 사용자 문서를 서버에서 재조회한 뒤 재계산하며, 읽음 후·방 화면 갱신·
  앱 재개(iOS 포함) 시 항상 실행. 다른 방·이후 도착 메시지는 다음 푸시가 새 카드를 다시 올리므로 보호된다.

추가 결함(2026-10-07): **번역 재시도가 동작하지 않는 경우** (스낵챗·DM·포스트·밋업 공통). 조사 결과 단일 버그가 아니라
여러 가드가 겹쳐 있었다. 조치:
- 공용 서비스: 사용자 재시도가 큐에서 대기 중인 같은 요청에 합류하면 force 플래그가 버려지던 것 수정, 강제 재시도 시
  클라이언트의 "같은 언어" 추정을 건너뛰고 서버가 판정, 자동 요청에 영구 재생되던 실패 기록에 2분 만료 추가,
  범위 재시도(`retryOneFailedScopeItem`)가 "첫 실패 항목 1개·다른 항목 로딩 중이면 무시"에서 "실패 항목 전부·즉시"로,
  빈 원문 필드(밋업 장소/설명 비어 있음)를 응답 누락으로 보던 완전성 검사 수정.
- 포스트·밋업 위젯(`TranslatableContent`): "다시 번역" 라벨이 보이는데 탭 핸들러가 비어 있던 경우(서비스의 차단 기록이
  언어 변경 등으로 사라진 뒤) 해제, 결과 없음(예외)도 재시도 가능, 모든 사용자 재시도는 서버 재생성(`forceRefresh`).
- 스낵챗: 방 전체 단일 재시도 플래그를 메시지별로 분리(한 메시지 재시도 중 다른 메시지 재시도 불가 문제),
  대기 중 마이크로배치/지연 결과가 탭을 막던 것 제거, 탭 재시도 기본 서버 재생성, 투표 메시지의 `text` 키 누락으로
  해시가 어긋나 항상 `stale_translation_result`가 되던 것 수정.
- DM: 탭 재시도를 서버 재생성으로, 지연 결과가 새 결과를 덮지 않게 정리.
- 서버 변경 없음(`forceRetry`/`forceRegenerate`는 이미 실패·완료 캐시를 우회).

플래그 기본값 변경: `ACTIVE_CONTENT_AUTO_READ`, `SNACK_CHAT_FAST_ENTRY`, `DM_FAST_ENTRY`, `SNACK_CHAT_CACHE_OFFLOAD`,
`CHAT_PUSH_PRESENTATION_V2` = true (서버 `.env` `CHAT_PUSH_PRESENTATION_V2=true`). `SNACK_CHAT_DIRECT_READ`는 false 유지.
각 플래그는 `--dart-define=<FLAG>=false`로 끌 수 있다(스토어 빌드는 define을 싣지 않으므로 코드 기본값이 실제 값).

## P4 — 안정화
- 1주 모니터링: asia-northeast3 오류율, FCM, `[SnackChatTiming]`/`[DMChatTiming]` p95
  (`functions/scripts/report_chat_timing.js`, `docs/chat_latency_baseline.md`에 "서울 전환 후" 행 추가).
- export 버킷 30일 보존 후 정리. US 미디어 버킷은 유지(기존 URL/경로).
- `docs/seoul_region_migration_plan.md`에 결과 기록.

## 검증 기록 (P0, 2026-10-05)
- `functions`: `tsc` 0 오류, `eslint src` 0, 리전 인벤토리 103 callable / 46 event + 1(asia, onReportCreated) / 6 schedule.
- `node scripts/test_snack_chat_unread_boundary.js`, `test_chat_push_presentation.js` 통과.
- Firestore 에뮬레이터(`firebase emulators:exec --only firestore --project demo-chat-delivery`, Java 21): `test_chat_delivery_emulator.js`, `test_dm_read_boundary_emulator.js`, `test_notification_read_emulator.js` 전부 PASS(exit 0).
- Flutter: `flutter analyze` 변경 파일 error 0, `test/app_backend_test.dart` 11개 통과,
  기존 `dm_read_receipt_test`·`snack_chat_read_fast_path_test`·`dm_delivery_client_web_test`·
  `comment_gif_upload_test`·`snapshot_comment_*`·`snack_chat_file_policy_test`·`dm_message_reaction_test`·
  `snapshot_video_preparation_test` 통과.
- `scripts/release_guard.py validate_backend`: 현재 메타데이터 PASS, 리전 불일치 시 GuardFailure 확인.
