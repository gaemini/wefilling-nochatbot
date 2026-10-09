# 배포 전 보안·읽음·채팅 점검 기록 (2026-10-07)

대상: `release/1.2.4` 작업 트리(1.3.27+97 준비 중), Firebase 프로젝트 `flutterproject3-af322`.
범위: 코드 감사(앱·Rules·Functions) 3건, 서버 로그 11시간 분석, 에뮬레이터 검증. **운영 배포는 하지 않았다.**

## 1. 배포 전 핵심 결론

출시를 막아야 했던 문제 5건은 로컬에서 수정하고 에뮬레이터로 검증했다. 아직 배포(Rules/Storage/Functions)와 앱 빌드가 남아 있다.

| # | 출시 차단 문제 | 상태 |
|---|---|---|
| 1 | 공개 저장소(`gaemini/wefilling-nochatbot`)에 업로드 키스토어 비밀번호가 커밋돼 있음(`KEYSTORE_STATUS.md`). 키 파일(.jks)은 커밋된 적 없음 | 파일에서 제거. 비밀번호 교체는 사용자 작업(아래 6절) |
| 2 | 로그인한 누구나 `notifications` 문서를 임의 수신자·임의 제목/본문으로 만들 수 있고 서버가 그대로 푸시 발송 | Rules로 유형·행위자·수신자 검증 |
| 3 | 이메일 인증 4자리 코드 추측 가능: 재발급마다 시도 횟수 초기화, 시도 검사 비원자적, 쿨다운 없음 | 재발급 쿨다운 30초·시간당 6회, 트랜잭션 검사 |
| 4 | 모임장이 `meetup_reviews.approvedParticipants`를 직접 써서 동의 없이 타인 프로필에 후기 게시(서버 트리거가 그대로 게시·복원) | Rules로 참여자 본인만 수락/거절 |
| 5 | 게시글 좋아요·조회수·투표 집계, 모임 참여자 수·조회수, 프로필 후기 좋아요 수를 읽기 권한만 있으면 임의 값으로 변경 가능 | Rules로 본인 uid ±1, +1 증가만 허용 |

남은 위험(구조 변경이 필요해 이번에 손대지 않음, 2절 참고): `users` 문서 전체 읽기 노출, 익명 글 작성자 uid 노출, 한양 전용 콘텐츠 Rules 미강제, App Check 미강제, 심사용 데모 계정 백도어.

검증 상태 구분:
- 코드 기준 확인·수정: 완료.
- 에뮬레이터 검증(Rules·Functions 로직): 완료(5절).
- 운영 배포·Remote Config·스토어 빌드: 미실행(사용자 지시).
- 실기기 푸시·배지·런처 동작, Crashlytics: **미검증**(gcloud 인증 만료로 BigQuery/Crashlytics 조회 불가).

## 2. 발견 사항

심각도 기준: Critical = 타 계정 데이터·권한 침해 가능, High = 콘텐츠 위조/대량 남용, Medium = 제한적 남용, Low = 방어 심층.

### 2-1. 수정한 항목

| 심각도 | 증상 / 공격 조건 | 원인 | 파일 | 근거 | 수정 |
|---|---|---|---|---|---|
| Critical | 공개 GitHub 저장소에서 업로드 키 비밀번호 열람 가능 | 문서에 비밀번호 평문 기록 | `KEYSTORE_STATUS.md` | `gh repo view` → PUBLIC, `git log -S` 1커밋 | 제거(이력에는 남음) |
| Critical | 피싱·사칭 푸시, 차단 우회(actorId 생략), 배지 부풀리기, 서버 알림 ID 선점 | `notifications` create가 `request.auth != null`뿐 | `firestore.rules` notifications | `onNotificationCreated`는 일부 유형만 재검증, 나머지는 클라이언트 title/body 그대로 발송 | 유형 allow-list(new_like, meetup_participant_left, review_*)·actorId=본인·수신자 검증·키 allow-list·createdAt=서버시각 |
| Critical | 타인 이메일 소유 증명 → 한양 인증 위조, 타인 이메일 가입, 미완료 Auth 계정 탈취 | 9,000개 코드, 재발급 시 attempts=0, 검사 비원자적 | `functions/src/index.ts` sendEmailVerificationCode/verifyEmailCode | 코드 확인(4285-4690) | 쿨다운·상한·트랜잭션, 상수시간 비교 |
| High | 동의 없는 후기가 피해자 프로필에 게시되고 삭제해도 복원 | 모임장 update 전체 허용, 참여자 update에 hasOnly 없음 | `firestore.rules` meetup_reviews | `ensureMeetupReviewProfilePosts`가 approved 목록을 신뢰 | 모임장은 content/imageUrl(s)/updatedAt/meetupTitle만, 참여자는 자기 uid 이동만, 생성 시 approved/rejected 빈 목록 |
| High | 좋아요 수·조회수·투표 수/선택지 문구 조작, 타인 좋아요 삭제 | hasOnly만 검사 | `firestore.rules` posts | 클라이언트는 트랜잭션으로 본인 uid만 추가/제거 | `selfOnlyLikeToggle`, `counterIncrementedByOne`, `validPollVoteIncrement`(같은 트랜잭션의 본인 pollVotes 생성 필수) |
| High | 모임을 정원 초과/만원으로 조작 | 참여자 분기가 currentParticipants 임의 값 허용 | `firestore.rules` meetups | 현재 클라이언트 참여/취소는 콜러블(Admin SDK) 경유, 남은 클라이언트 트랜잭션은 participants도 써서 이미 거부됨 | 분기 제거, viewCount +1만 |
| High | `relationships` 위조로 친구 공개 후기 열람 | create/update 허용 | `firestore.rules` relationships | 클라이언트 쓰기 경로 없음(경로 상수만 존재) | 모든 쓰기 거부 |
| High | Storage `posts/`, `meetup_reviews/` 타인 파일 덮어쓰기·삭제, 임의 파일 호스팅 | `allow write: if isSignedIn()` | `storage.rules` | 경로에 소유자 없음 | create만, image/*, 15MB; 삭제·덮어쓰기 거부. 후기 업로드 클라이언트가 contentType 명시 |
| Medium | 참여자가 거절 뒤 스스로 승인, meetupId/userId 변경 | update 필드 제한 없음 | `firestore.rules` meetup_participants | 클라이언트 쓰기: 호스트 `{'status': ...}`만 | 호스트가 status(+updatedAt)만 |
| Medium | 친구 요청 직접 생성·수락 중 fromUid 변경 → 위조 "수락" 푸시 | create 허용, update hasOnly 없음 | `firestore.rules` friend_requests | 클라이언트는 콜러블만 사용 | create 거부, update는 status 계열 키만 |
| Medium | DM 메시지에 임의 키·과거/미래 createdAt, 대화방 ID에 제3자 uid | hasOnly 없음, ID와 participants 미결합 | `firestore.rules` conversations/messages | 모델 `DMMessage.toFirestore()` 키 확인 | 키 allow-list, createdAt은 서버시각 ±10분, ID는 정렬된 두 uid(또는 anon_ 접두) |
| Medium | 프로필 후기 좋아요/댓글 수 조작 | hasOnly만 | `firestore.rules` users/{uid}/posts | 클라이언트 arrayUnion/Remove + increment ±1 | 본인 uid, 카운트 변화 ±1, commentCount 0 이상 정수 |
| Medium | 비밀번호 재설정 5회 잠금을 60초마다 재발급으로 초기화 | 재발급이 status/attemptCount 덮어씀 | `functions/src/index.ts` requestPasswordResetCode | 코드 확인 | 잠금 5분 유지(`lockedAt`) |
| Medium | 번역 API 무제한 호출(forceRegenerate 반복 등) | 사용자별 상한 없음 | `functions/src/content_translation.ts` | 코드 확인 | 사용자별 Gemini 호출 항목 10분 600·재생성 60·일 5,000. 캐시 적중은 미계수 |
| Low | 탈퇴 관리자 메일 HTML 주입 | escape 누락 | `functions/src/index.ts` | 코드 확인 | `escapeHtml` 적용 |
| Low | 레거시 댓글 서브컬렉션에 타인 명의 작성 | userId 미검사 | `firestore.rules` posts/meetups comments | 클라이언트는 최상위 comments 사용 | userId=본인 |
| Low | 사용자가 자기 accountStatus/deletedAt 변경 | 보호 목록 누락 | `firestore.rules` users | 클라이언트 쓰기 없음 | 보호 목록 추가 |
| Low | Android 앱 데이터 백업으로 인증 상태·캐시 복사 | allowBackup 기본값 true | `AndroidManifest.xml` | 설정 확인 | `allowBackup="false"` |
| Low | 비밀 파일 커밋 방지 규칙 부재 | .gitignore | `.gitignore` | 확인 | serviceAccountKey*.json, *.p8/*.p12/*.pem, .env.local, .secret.local 추가 |

### 2-2. 확인됐지만 이번에 수정하지 않은 항목 (구조 변경 또는 정책 결정 필요)

| 심각도 | 내용 | 왜 보류했나 | 권장안 |
|---|---|---|---|
| Critical | `users/{uid}` 전체 문서를 로그인 사용자 누구나 get/list 가능: email, hanyangEmail, fcmToken(s), photoAccessToken, 숨긴 학과/학년, lastLogin 등 | 프로필 조회·검색·댓글 작성자 표시 등 수십 곳이 이 문서를 직접 읽음. 필드 분리(비공개 서브컬렉션 이동)와 서버·클라이언트 동시 수정이 필요 | 별도 작업: `users/{uid}/private/profile`로 email·토큰 이동, 서버 푸시는 registry/private 참조, 클라이언트 fcmTokens fallback 제거 후 Rules에서 list 제한 |
| High | 익명 게시글/댓글 문서에 실제 userId·ownerId·authorNickname 저장 → 읽기 권한만 있으면 작성자 식별 | 익명 DM, 차단, 번역 등이 uid를 사용. 데이터 모델 변경 | 서버 프로젝션(익명이면 작성자 필드 제거한 사본 제공) |
| High | 한양 전용 포스트·밋업을 Rules가 강제하지 않음(서버 번역 경로만 강제) | 목록 쿼리가 `visibility`로만 필터돼 Rules 조건 추가 시 전체 쿼리 거부 | 클라이언트 쿼리에 한양 필드 조건 추가 후 Rules 반영 |
| High | App Check: `sendEmailVerificationCode`/`verifyEmailCode` 등 다수 콜러블이 미강제 | 운영 로그 11시간에 "invalid AppCheck token… enforcement is disabled" 경고 113건(여러 함수). 강제 시 그 클라이언트는 즉시 실패 | 경고를 내는 클라이언트(디버그 빌드/미등록 디버그 토큰 여부) 확인 후 단계적 강제 |
| Medium | `review_demo@hanyang.ac.kr` + `0000` 심사용 백도어 | 스토어 심사 로그인에 필요 | 심사 기간에만 켜는 env 플래그로 전환 |
| Medium | `meetup_participants`에 `userEmail` 저장·밋업 열람자에게 노출 | 서버가 쓰는 필드이며 호스트 화면에서 사용 여부 확인 필요 | 사용처 없으면 저장 중단 |
| Medium | `reportUser`·`blockUser`가 호출마다 관리자 메일 2통, 본문 길이 제한 없음 | 메일 정책 결정 필요 | 사용자별 쿨다운·길이 제한 |
| Medium | `registerFcmToken`이 토큰 소유 증명 없이 등록(타 계정 토큰을 자기 것으로 이동 가능). 토큰 자체는 `users` 노출(위 Critical)로 알 수 있음 | users 노출 해결이 선행 | users 분리 후 재평가 |
| Medium | `friendships` 컬렉션 전체 list 가능(소셜 그래프 열람) | 친구 수/친구 여부 조회가 list에 의존하는지 확인 필요 | 본인 포함 문서만 읽기 |
| Low | `usesCleartextTraffic="true"`(챗봇 제거 전 설정) | iOS는 이미 http 차단. Android에서 http 이미지 링크 미리보기가 깨질 가능성 때문에 보류 | 다음 릴리스에서 false로 전환 |
| Low | 이메일 인증 코드 평문 저장(클라이언트 읽기는 거부됨) | 4자리 UX 유지 | 해시 저장 |

### 2-3. 서버 로그·Crashlytics

- `firebase functions:log` 12,703줄(2026-10-06 06:13~17:11 UTC): **오류(E) 0건**, 경고 113건 전부 App Check 토큰 디코딩 실패(강제 안 해 허용). 함수 간 충돌·크래시 징후 없음.
- Crashlytics/BigQuery: gcloud 재인증이 필요해 조회하지 못했다(미검증). `gcloud auth login` 후 재요청하거나 Firebase 콘솔 Crashlytics에서 1.3.26/1.3.27 빌드 기준으로 직접 확인.

## 3. 적용한 수정

| 파일 | 변경 | 호환성 |
|---|---|---|
| `firestore.rules` | 집계 보호 헬퍼(`listDiffOnlySelf`, `selfOnlyLikeToggle`, `counterIncrementedByOne`, `validPollVoteIncrement`), users 보호 필드, users/{uid}/posts, friend_requests, relationships, posts, 레거시 comments, meetups, meetup_reviews, meetup_participants, notifications, conversations(ID 결합), messages(키 allow-list·createdAt 범위) | 현재 클라이언트 쓰기 패턴(트랜잭션 본인 uid ±1, increment(1), arrayUnion/Remove 본인, serverTimestamp)과 일치. 구버전 DM의 기기 시각 createdAt은 ±10분 허용. 투표 선택지 10개 초과 문서는 투표 거부(앱 UI에 포스트 투표 생성 경로 없음) |
| `storage.rules` | posts/·meetup_reviews/ create 전용·image/*·15MB, profile_images 10MB·image/*, dm_images 15MB·image/*, meetup_images 15MB | 현재 클라이언트는 profile/dm/posts에 image/jpeg 명시. 후기 업로드는 이번에 명시 추가(구버전은 .jpg 확장자로 추론) |
| `lib/screens/create_meetup_review_screen.dart` | 후기 이미지 `SettableMetadata(contentType: 'image/jpeg')` | 없음 |
| `functions/src/email_verification_policy.ts`(신규) | 쿨다운·상한·시도 평가 순수 함수 | — |
| `functions/src/index.ts` | sendEmailVerificationCode: 트랜잭션 안 쿨다운 30초/시간당 6회(`lastSentAt`, `sendWindowStartedAt`, `sendCountInWindow`), 메일 실패 시 쿨다운 해제. verifyEmailCode: 시도 검사·증가·검증을 한 트랜잭션. requestPasswordResetCode: 잠금 5분 유지. 탈퇴 메일 escape | 응답 메시지·코드 동일. 쿨다운 초과 시 `resource-exhausted` + `{status:'rateLimited', retryAfterSeconds}` |
| `functions/src/content_translation.ts` | 사용자별 제공자 호출 할당량(`content_translation_usage/{uid}`), 초과 시 pending 잠금 복원 후 `resource-exhausted` 실패 응답 | 클라이언트는 `resource-exhausted`를 15초 백오프 재시도로 처리(기존 로직) |
| `android/app/src/main/AndroidManifest.xml` | `android:allowBackup="false"` | 기기 이전 시 로그인 재필요 |
| `.gitignore`, `KEYSTORE_STATUS.md` | 비밀 파일 패턴, 비밀번호 제거 | — |
| `lib/screens/notification_settings_screen.dart`, `lib/services/notification_settings_service.dart` | 글쓰기 화면과 동일한 디자인으로 재구성(상자·테두리·색 배경 제거, 반응형 폰트/간격, 하단 시스템 인셋 패딩, 640px 폭 제한). 마케팅 토글이 실제 `FCMService` 토픽 'ads' 구독/해제 호출. 저장 실패(false 반환) 시 토글 되돌림 | 설정 키·서버 판정(`notificationSettingAllows`) 동일 |
| `functions/scripts/test_email_verification_policy.js`, `functions/scripts/test_security_rules_emulator.js`(신규) | 검증 스크립트 | — |

## 4. 읽음·미읽음·배지의 최종 기준

| 숫자 | 정의 | 계산 주체·근거 |
|---|---|---|
| 스낵챗 방별 안 읽은 수 | `snack_chats/{room}.unreadCount[uid]`: 내 `members/{uid}.lastReadSequence`(또는 입장 시점) 이후 타인이 보낸 메시지 수 | 서버 트리거(`onSnackChatMessageCreatedSecure`)가 증가, `markSnackChatReadSecure`가 lastReadSequence 기준으로 재계산. 본인 메시지는 포함하지 않음 |
| 스낵챗 읽음 경계 | 화면에 실제 렌더링돼 확인된 마지막 메시지의 sequence(`_scanConfirmedReadBoundary`) | 클라이언트가 경계를 먼저 확정해 제출. Rules는 `lastReadSequence`가 단조 증가·`lastMessageSequence` 이하일 때만 허용 → 다른 기기의 늦은 과거 요청으로 후퇴하지 않음 |
| DM 방별 안 읽은 수 | `conversations/{id}.unreadCount[uid]` + `lastReadAtBy[uid]` 워터마크(나노초 정밀) | `markDMConversationReadBoundedSecure(readThrough)`가 보이는 마지막 메시지까지만 읽음 처리. 경계 이후 도착 메시지는 남음 |
| DM 총합 | `users/{uid}.dmUnreadTotal` | 서버 트리거가 방별 변화량을 반영. 클라이언트는 쓰기 불가(Rules) |
| 알림함 안 읽은 수 | `users/{uid}.notificationUnreadTotal`(counterVersion==1일 때 신뢰, 아니면 `notifications` where isRead==false 중 dm_received 제외 집계) | `onNotificationCreated`/읽음 처리·`reconcileNotificationUnreadTotalSecure` |
| 앱 아이콘 배지 | 알림함 안 읽은 수(dm_received 제외) + dmUnreadTotal + 스낵챗 방별 unreadCount 합 | 기기(`BadgeService`)와 서버 푸시 badge 페이로드(`badge_policy.ts`, DM/스낵 푸시) 모두 같은 식. 누적 ±1이 아니라 매번 재계산 |
| 시스템 푸시 카드 | 방 단위 그룹. 읽음 경계가 그 방의 최신 보이는 메시지를 덮을 때만 그 방 카드 제거(`coversLatestVisible`) | 다른 방 카드·배지는 유지. 전경 복귀·읽음 후 `BadgeService.refreshNow(fresh: true)`로 서버 값 재조회 |

동시 도착·중복·다중 기기·늦은 푸시: 읽음은 "제출한 경계까지"만 반영되고 경계는 단조 증가하므로 M10 읽는 중 도착한 M11은 미읽음으로 남는다(에뮬레이터 `test_dm_read_boundary_emulator`, `test_snack_chat_unread_boundary` 검증). 늦은 푸시의 badge 값은 다음 전경 복귀/읽음 시 서버 카운터로 덮어쓴다. 앱이 꺼진 동안 OS가 적용한 오래된 배지 값까지 막지는 못한다(플랫폼 한계).

## 5. 검증 결과

실행한 것:
- `functions`: `npm run build`(tsc) 통과, 변경 파일 eslint 통과.
- `node scripts/test_email_verification_policy.js`: 쿨다운·시간당 상한·윈도 리셋·Timestamp 유사 객체·레거시 문서·시도 평가 전부 통과.
- Firestore 에뮬레이터(Java 21, `demo-chat-delivery`):
  - `test_security_rules_emulator.js`(신규): 57개 허용/거부 시나리오 통과(알림 13, 포스트 집계 12, 밋업 3, 프로필 후기 5, 후기 8, 참여자 3, 관계/친구요청 4, DM 6, 레거시 댓글 2).
  - 기존 `test_chat_delivery_emulator.js`(DM 동시 전송·재시도·롤백·Rules·차단·같은 시각 페이지네이션·스낵챗 순번·이미지 버킷·읽음 커서), `test_dm_read_boundary_emulator.js`, `test_notification_read_emulator.js`, `test_snapshot_reaction_emulator.js`, `test_nickname_claims_emulator.js`: 최종 실행 전부 통과.
  - 처음 실행에서 `test_chat_delivery`가 두 지점에서 새 Rules에 걸렸다. (a) "구버전 클라이언트 기기 시각 createdAt" 케이스 → Rules를 서버시각 ±10분 허용으로 조정. (b) 테스트 전용 합성 대화방 ID `{room}_security`가 새 ID 결합 규칙에 거부 → 실제 클라이언트 형식(`anon_{a}_{b}_security`)으로 테스트 수정(앱 코드는 `a_b` 또는 `anon_a_b_suffix`만 생성).
- Storage 에뮬레이터: `storage.rules` 컴파일 통과(임시 설정으로 로드만 확인, 업로드 시나리오는 미실행).
- `flutter analyze` 변경 파일: 오류 0. `flutter test`(app_backend, account_visibility_policy, chat_notification_presentation, dm_delivery_client_web): 통과.

미실행·확인 불가:
- 실기기 푸시 수신·탭 진입·배지·런처별 동작, 앱 종료 상태 푸시: 미검증(기기 없음). 절차: 두 계정으로 스낵챗·DM 각각 메시지 → 아이콘으로 열어 읽음 → 카드 제거·배지 감소·다른 방 유지 확인.
- 다수 동시 접속 부하: 에뮬레이터 4인 동시 전송 수준만 확인.
- Crashlytics: gcloud 인증 만료.
- `test_snack_chat_discovery_emulator.js`: `scannedCount <= 160` 단언이 현재 구현(한 번에 600건 스캔, 9월 최적화 커밋)과 맞지 않아 실패. 이번 변경과 무관한 기존 테스트 불일치.

## 6. 배포에 필요한 작업 (순서)

1. **키스토어 비밀번호 교체(사용자)**: `keytool -storepasswd -keystore ~/wefilling-upload-key.jks` 및 `keytool -keypasswd -alias upload -keystore ~/wefilling-upload-key.jks` 로 변경 후 `android/key.properties` 갱신. 키 파일은 유출되지 않았으므로 Play 업로드 키 재설정까지는 필요 없다. 저장소를 비공개로 전환하거나 이력에서 해당 커밋을 제거하는 것을 권장.
2. **Functions 배포**(변경 함수만): `firebase deploy --only functions:sendEmailVerificationCode,functions:verifyEmailCode,functions:requestPasswordResetCode,functions:resetPasswordWithCode,functions:deleteAccountImmediately,functions:translateContentBatch`. 구버전 앱 호환: 응답 형식 동일. 되돌리기: 이전 빌드 재배포(`functions/lib` 이전 커밋) 또는 상수(`EMAIL_VERIFICATION_*`, `PASSWORD_RESET_LOCK_MS`, `TRANSLATION_MAX_*`) 완화.
3. **Firestore Rules 배포**: `firebase deploy --only firestore:rules`. 즉시 적용되며 구버전 앱의 알림 직접 생성(meetup_full 등 서버가 이미 대신 보내는 유형)은 거부돼 로그만 남고 기능 영향 없음. 되돌리기: `git checkout HEAD -- firestore.rules && firebase deploy --only firestore:rules`.
4. **Storage Rules 배포**: `firebase deploy --only storage`(두 버킷). 되돌리기 동일.
5. 앱 1.3.27+97 빌드·심사 제출 → 승인 후 Remote Config 최소 빌드 97 강제 업데이트(기존 절차).
6. 콘솔 확인(사용자): App Check 메트릭에서 유효하지 않은 토큰 비율과 출처, Crashlytics 최근 크래시, Firebase Auth 이메일 enumeration 보호 설정.

코드 수정으로 해결된 것: 2절 2-1 전부(배포 전까지는 효력 없음). 배포·설정이 있어야 해결되는 것: Rules/Storage/Functions 배포, 키 교체, App Check 강제(별도 결정).

## 7. 변경 불필요 항목

- 스낵챗 메시지 생성 Rules(`validClientMessageCreate`), 반응·투표·members 읽음 커서, 스냅샷, 조직 계정, DM 파일·스낵챗 파일 Storage 규칙: 감사 결과 이상 없음.
- `isAdmin`·`hanyangEmail` 등 계정 제한 필드: 클라이언트 쓰기 불가 확인.
- 링크 미리보기 SSRF 방어(`fetchSnackChatLinkPreview`, `resolveSharedLink`): 호스트 allow-list·사설 IP 차단·리다이렉트 재검사 확인.
- 아이디 검색(`searchSocialUsers`, `searchSnackChatInviteUserById`): App Check 강제, 활성 계정·차단 필터, 공개 필드만 반환.
- 비밀값: 서비스 계정 키·API 키 하드코딩 없음(Gemini/YouTube/Gmail은 Secret Manager). `google-services.json`은 클라이언트 설정값이라 정상.
- 읽음·배지 동기화 로직: 이번 점검에서 결함 없음.
