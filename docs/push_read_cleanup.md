# 앱 내부 확인 → 선택적 OS 알림 제거

## 범위 / 정책

현재 작업 트리(기존 미커밋 변경 포함)에 적용. 운영 배포/운영 데이터 변경 없음.
발송 경로는 `index.ts:onNotificationCreated`, `onAdBannerChanged`, DM 생성 트리거,
`snack_chat.ts:onSnackChatMessageCreatedSecure`, `personal_todo_reminders.ts`이다.
`index.ts`의 비export legacy Snack trigger는 실제 배포 대상에서 제외했다.
관리자 `signup_completed`는 이메일 경로이지 앱 푸시 type이 아니다.

**기존 예외 정책 유지:** MainScreen은 NotificationScreen에
`markAllAsReadOnOpen: true`를 전달한다. 따라서 그 경로에서는 알림센터 진입 시
기존처럼 일반 알림을 모두 읽는다. 이번 작업에서 임의로 이 정책을 바꾸지 않았다.
대신 최초 서버 snapshot의 문서 ID만 고정해서 처리하므로 commit 중 도착한 새 문서는 제외한다.
DM/Snack 방 읽음 cursor나 채팅 미읽음 합계를 이 작업으로 변경하지 않는다.

## 실제 발송 type 연결 (23개)

일반 알림은 모두 `notifications/{notificationId}.userId`가 수신자이다.
서버 commit 성공 후 그 **문서 ID 집합만** OS에서 제거한다.
표의 연결은 코드 구현 결과이며, 각 종류의 실제 기기 FCM 전달/제거를 통과했다는 뜻은 아니다.

| type | 대상 / 실제 확인 위치 | 읽음·제거 범위 |
| --- | --- | --- |
| post_created | postId / 권한 검증 성공한 PostDetail | 해당 포스트의 해당 유형 ID |
| new_like | postId / 같은 화면 | 해당 포스트 좋아요 ID |
| new_comment | postId + commentId / 표시된 댓글 본문 | 그 댓글 ID만 |
| comment_reply | postId + commentId / 표시된 답글 본문 | 그 답글 ID만 |
| comment_like | postId + commentId / 표시된 댓글 본문 | 해당 댓글 좋아요 ID |
| friend_request | actorId + friendRequestId + 가능한 notificationGeneration / 표시된 받은 요청 | 그 요청 세대만; 수락/거절하지 않음 |
| friend_request_accepted | actorId / 로딩 성공한 친구 프로필 | 그 상대의 수락 알림 |
| meetup_created | meetupId / 서버 조회·접근 검증 후 상세 | 해당 밋업·유형 ID |
| meetup_full | meetupId / 같은 화면 | 동일 |
| meetup_cancelled | meetupId / 같은 화면 | 동일; 기존 삭제/만료 정책 유지 |
| meetup_participant_joined | meetupId / 같은 화면 | 동일 |
| meetup_participant_left | meetupId / 같은 화면 | 동일 |
| review_approval_request | requestId / 실제 요청 조회 성공 | 그 승인 요청 알림; 승인하지 않음 |
| snapshot_reaction | snapshotId / 이미지 준비·동영상 첫 프레임 | 해당 스냅 반응만; 댓글은 제외 |
| snapshot_comment | notificationId / 편지 로딩 성공 | 그 편지 알림 |
| snapshot_comment_reply | notificationId / 답장 편지 로딩 성공 | 그 답장 알림 |
| snapshot_feed_comment | snapshotId + commentId / 댓글 시트에서 실제 표시 | 그 댓글만 |
| snapshot_feed_comment_reply | snapshotId + commentId / 같은 시트 | 그 답글만 |
| snack_chat_invite | snackChatId / 서버 entry가 읽음 가능한 멤버십 확인 | 해당 방 초대 ID |
| snack_chat_message | recipientUserId + snackChatId + messageSequence | 확정 sequence 이하; 다른 방/새 sequence 보존 |
| dm_received | recipientUserId + conversationId + 서버 commit seconds/nanos | 확정 read watermark 이하; 다른 방/이후 commit 보존 |
| ad_updates | 공개 ads topic + bannerId + 서버 commit 버전 / 실제 표시된 배너 | 그 버전의 해당 기기 카드만 |
| personalTodoReminder | recipientUserId + 기존 todoNotificationDeliveries 문서 ID / 표시된 개인 할 일 | 발송 기록의 todoIds를 모두 확인한 경우만; 작업 완료와 무관 |

같은 `personalTodoReminder`의 **기기 반복 예약 경로**도 확인했다.
`personal_todo_local_notification_service.dart`의 기존 payload에 recipientUserId를 보완했다.
실제 표시된 todoId의 delivered 카드만 OS 표시 시각(기기 시계) 경계로 제거하며,
plugin.cancel을 호출하지 않으므로 다음 날 pending 반복 예약을 취소하지 않는다.
이 경계는 서버/채팅 읽음 추정에 사용하지 않으며 반복 슬롯의 제거 요청을 영구 재생하지 않는다.
실패 시 다음 해당 항목 확인에서 다시 시도한다. 소유자 메타데이터가 없는 legacy 예약은 추정 삭제하지 않는다.
기존 앱 시작 예약 복구의 `schedule()`이 활성 항목까지 먼저 cancel하던 경로도 수정했다.
활성 예약은 같은 ID로 pending alarm/request만 교체하고, 명시적 끄기·완료·보관 시의 취소는 유지한다.

`review_comment`는 호출되지 않는 생성 helper, `review_like`, `review_published`,
`review_rejected`, `post_private`, `NEW_MEETUP` 등은 이번 조사에서 현재 발송 호출이
확인되지 않은 legacy/라우팅 선언이다. 신규 알림 유형은 만들지 않았다.
멘션/공지라는 독립 type도 새로 만들지 않았다. 실제 채팅 푸시로 전달되는 경우
기존 `snack_chat_message` 방/순번 계약을 그대로 적용한다.

## 식별자 / 시간 계약

- 일반 알림: notificationId, recipientUserId, target IDs, 서버 `sentAtMillis`.
  Android 기존 `notification_<sha256(notificationId)[0:40]>` / FCM id 0 유지.
  iOS는 userInfo/로컬 payload를 대조한 실제 delivered request.identifier를 제거한다.
- Snack: 기존 `snack_<hash(account:room)>`, Android id 0, iOS 기존 thread/collapse/local ID 유지.
  읽음 판정은 계속 messageSequence. 읽음 요청에 추가 조회/순번 체계를 도입하지 않았다.
- DM: 기존 `dm_<hash(account:room)>`, Android id 0와 기존 iOS local ID 유지.
  새 push의 `sentAtSeconds/sentAtNanos`는 문서 createTime이다.
  callable의 `readThroughAtSeconds/readThroughAtNanos`와 정수 비교한다.
  legacy milliseconds는 기존 보수적 경계만 사용한다. 단말 시각을 읽음 근거로 쓰지 않는다.
- Android 자동 FCM은 Notification.extras에 data를 보장하지 않는다.
  `NotificationDeliveryMetadataReceiver`는 FCM broadcast의 **식별자만** 저장한다.
  추가 알림 표시/재전송/네트워크 요청/구독/권한 요청은 하지 않는다.
  `notificationMetadataVersion=2`, `notificationCommitMillis`와 Android eventTimestamp를
  같은 서버 commit에서 만든다. tag + OS when으로 대응 메타데이터를 찾는다.
  같은 밀리초 bucket에는 가장 큰 sequence 또는 seconds/nanos를 보관하여 새 메시지를
  이전 읽음으로 삭제하지 않는다. 방당 최근 8개 bucket만 저장한다.
- 광고: 개인 수신자가 없는 기존 public topic을 유지한다. `audience=public`,
  `notificationId=ad:<bannerId>:<seconds:nanos>`로 정확한 버전을 구분한다.
  광고에는 기존에 사용자별 서버 읽음/배지 기록이 없으므로 새 알림센터 레코드를 만들지 않고
  해당 기기의 버전 확인만 기록한다. 서버는 실제 문서 updateTime을 notificationVersion에
  기록한다(메타데이터만 쓴 이벤트는 재발송하지 않음). Console에서 updatedAt을 그대로 두고
  수정해도 이전에 읽은 버전을 재사용하지 않는다. 이전 데이터 전체를 마이그레이션하지 않는다.
- 개인 할 일: 기존 일별 delivery ID를 재사용하고 isRead만 추가한다. 수신자 외 계정의 접근,
  발송 상태/대상 할 일 수정, isRead 역행은 Rules에서 거부한다. 일반/채팅 배지에 편입하지 않는다.

## 변경 파일과 보존 방법

- `notification_service.dart`: 단일/관련/모두 읽음의 계정·FCM session 캡처,
  서버 성공 문서만 후처리. 모두 읽음 snapshot 고정. 관련 읽음은 같은 프레임 요청을 합쳐
  owner+target의 top-level/legacy nested 필드를 조회; 댓글당 listener나 전체 DB scan 없음.
- `fcm_service.dart`: 기존 cancel* 경로에 확정 읽음 메타데이터와 앱 복귀/수신 시 재확인 연결.
  일반 ID 집합을 일괄 native 호출해서 카드마다 저장·enumeration을 반복하지 않음.
  실제 native 실패는 세션당 최대 3번의 이벤트 기반 재시도. 미지원/메타데이터 부족/대상 없음은
  실패와 구별한다. 서버 읽음과 OS 제거 성공을 혼동하지 않는다.
- `MainActivity.kt`, `AppDelegate.swift`, Android manifest/메타데이터 receiver:
  기존 선택 제거 확장. 제거 직전 OS postTime/date 및 메타데이터 교체를 재확인한다.
  추측에 의한 fallback cancel, cancelAll/removeAllDeliveredNotifications 사용 안 함.
- `notification_read_observer.dart`, `notification_read_policy.dart`: 설치된 visibility_detector 재사용.
  로딩 shell/화면 밖 댓글은 읽지 않음. type+수신자+대상 모든 차원을 일치시킨다.
- 관련 목적지 화면, 댓글 위젯, NavigationService, NotificationScreen:
  진입 시 선읽음을 실제 로딩/권한 확인 또는 항목 노출 뒤로 이동.
  포스트 확인으로 미노출 댓글·편지를 읽지 않음. 요청 수락/참여 승인 등의 업무 로직 불변.
- `ad_banner.dart`, `friend_request.dart`: 원정밀도 광고 버전과 기존 친구 요청 세대를 보존.
- `dm_service.dart`, `dm_chat.ts`, DM screen: 확정 경계 seconds/nanos 전달만 추가.
  이전 DM 말풍선 수정, receipt worker, 캐시/Outbox/집계 정책 보존.
- Snack screen: 읽음 요청 전 계정/session 확인, OS 후처리를 미리 완료로 기록하던 부분 제거.
  최초 미읽음 이동/anchor 및 요약 버튼은 유지하고 안내 문구/구분선만 제거.
- 서버 push 생성부: 기존 발송 경로에 식별 메타데이터 추가. 일반 알림/할 일은 보내기 직전
  isRead를 재확인. 기존 token/언어/차단/멤버십/소리/배지 계산은 유지.

## 검증

- 대상 Flutter 83개 통과: 읽음 scope/다른 계정·콘텐츠·댓글 보존, 할 일 전체 대상 확인,
  광고 nanoseconds 캐시 왕복, 기존 DM receipt/알림 정책/계정 배지 정책,
  광고 초기 스크롤, 편지 답장, 할 일 레이아웃·undo·다국어/작은 화면.
  광고 테스트는 누락돼 있던 앱 localization delegates를 테스트 harness에 제공했다.
  로컬 반복 예약의 startup 재등록이 delivered 카드를 취소하지 않는지 method-channel로 확인했고,
  기존 할 일 관리/계정 전환/예약/undo 회귀 13개도 통과했다.
- Firestore emulator: 최초 snapshot 뒤 도착한 새 알림 보존, 타 계정 알림 보존,
  읽음 후 지연/중복 create의 미읽음 재증가 방지, DM 전체 합계 불변,
  개인 할 일 owner-only/읽음 역행·업무 필드 변경 거부 통과.
  광고 Console 수정의 commit 버전 분리와 메타데이터 자기 재호출 억제도 실제 handler로 검증.
- 기존 chat emulator: DM stable ID/재시도/권한/차단/원자성/receipt,
  Snack 순번·수신 대상·중복/지연 집계 통과. 별도 DM 경계 emulator도 통과.
- TypeScript build, Android Kotlin compile, Swift frontend parse 통과.
- 변경 경로 Dart 분석: error 0. 기존 화면 등에서 warning/info가 남아 있어
  분석 전체가 무경고라고 보고하지 않는다.

**미검증/제한:** 연결된 Android/iOS 기기 없음. 실제 FCM/APNs 종료 상태 수신, receiver 실행,
OS 자동/로컬 카드 선택 제거, 소리·진동·badge·딥링크 조합, 실제 네트워크/채팅 성능은 미검증.
Swift parse는 iOS 전체 Xcode build/실기기 검증이 아니다. Google Play Services가 앱 broadcast를
우회하거나 legacy 알림에 식별 정보가 없으면 안전하게 남길 수 있다.
OS cancel API 자체에는 compare-and-cancel 원자 연산이 없으므로 최종 재확인 직후의 극소 교체
경합까지 0이라고 보장하지 않는다. 종료 중 이미 읽은 지연 푸시의 OS 표시를 항상 즉시 막지 않는다.
읽음 복구 메타데이터는 30일 보관하며, 과거 식별 불가 알림을 본문/작성자로 추정해 지우지 않는다.

## 배포

1. Rules: 기존 todoNotificationDeliveries에 수신자 자신의 isRead 변경만 허용하는 제한된 규칙.
2. Functions: onNotificationCreated, onAdBannerChanged, sendDailyPersonalTodoReminders,
   onDMMessageCreated, markDMConversationReadSecure, markDMConversationReadBoundedSecure,
   onSnackChatMessageCreated (`onSnackChatMessageCreatedSecure`의 index export 별칭).
   DM worker 등 이전 DM 수정의 배포 의존성은
   `dm_read_receipt_fix.md`도 함께 따른다.
3. **Android/iOS 새 앱 빌드 필수.** Android manifest/receiver와 양 플랫폼 native 선택 제거 변경 포함.
   새 payload 필드는 구버전이 무시할 수 있고 기존 방 tag/알림 channel/소리/라우팅은 유지한다.

신규 패키지, 신규 polling/listener, 신규 서버/FCM 발송 시스템, 인덱스 변경,
운영 데이터 일괄 마이그레이션 없음. 이번 작업에서 실제 운영 배포를 수행하지 않았다.
