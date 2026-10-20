# 위필링 기능 지도

2026-10-20 코드 기준이에요. 기능마다 어디에 있는지(앱 / 서버)와 핵심 기능인지 보조 기능인지를 정리해요.

- **핵심 기능 4개:** 포스트와 댓글, 실시간 번역 스낵챗, 밋업, #태그
- **보조 기능:** 한양메일 인증처럼 핵심 기능을 돕거나 운영에 필요한 기능
- 하단 탭은 포스트 · 밋업 · 스낵챗 · 마이페이지 · DM 5개예요.

## 핵심 기능

### 1. 포스트와 댓글 (포스트 탭)

카드 하나가 대화가 시작되는 자리예요. 피드에서 읽고, 카드 위에서 바로 댓글을 남기고, 상세 화면에서 채팅처럼 이어서 말해요.

| 무엇 | 앱 | 서버 |
|---|---|---|
| 피드 | `lib/screens/board_screen.dart`, `lib/ui/widgets/optimized_post_card.dart` | `createPostSecure`(`functions/src/content_creation.ts`) |
| 카드 위 댓글 입력: 최근 댓글 한 줄, 화면에 들어올 때 한 번 반응, 번역 미리보기 | `lib/ui/widgets/post_card_comment_invite.dart`, `lib/services/comment_invite_nudge_gate.dart` | `posts.latestComment`(`functions/src/latest_comment.ts`, 댓글 트리거) |
| 상세: 채팅형 댓글, 사진 댓글, 밀어서 답장, 두 번 눌러 좋아요 | `lib/screens/post_detail_screen.dart`, `lib/ui/widgets/post_chat_*` | `onCommentCreated` / `onCommentDeleted` / `onCommentSoftDeleted`(`index.ts`) |
| 글쓰기·공개 범위(전체·친구·그룹·#태그 가진 사람·익명) | `lib/screens/create_post_screen.dart`, `lib/ui/sheets/tag_audience_sheet.dart` | `resolveTagAudience`(`interest_tags.ts`) |
| 글·댓글 번역 | `lib/ui/widgets/translatable_content.dart`, `lib/services/content_translation_service.dart` | `content_translation.ts` |

### 2. 실시간 번역 스낵챗 (스낵챗 탭) · DM

어떤 언어로 써도 읽는 사람에게는 그 사람의 언어로 보여요.

| 무엇 | 앱 | 서버 |
|---|---|---|
| 스낵챗 목록·방 | `lib/screens/snack_chat_tab_view.dart`, `snack_chat_screen.dart`, `create_snack_chat_screen.dart` | `snack_chat.ts` |
| 메시지 번역(한 메시지만 번역, 원문 보기) | `lib/ui/widgets/snack_chat_translated_text.dart` | `content_translation.ts`, `translation_language_guard.ts` |
| 찾아보기 | `lib/screens/snack_chat_discovery_screen.dart` | `snack_chat_discovery.ts` |
| 투표·일정 | `lib/screens/snack_chat_poll_schedule_screen.dart` | `snack_chat.ts` |
| DM | `lib/screens/dm_list_screen.dart`, `dm_chat_screen.dart` | `dm_chat.ts`, `dm_read_policy.ts`, `read_sync_policy.ts` |
| 스낵(오늘의 사진·영상, 필링 반응) | `lib/snapshot/`, `lib/screens/snapshot_*` | `snapshot.ts` |

### 3. 밋업 (밋업 탭)

| 무엇 | 앱 | 서버 |
|---|---|---|
| 날짜 바·주간 줄·목록, #태그 필터 | `lib/screens/home_screen.dart`, `lib/ui/widgets/board_meetup_card.dart` | |
| 만들기·고치기 | `lib/screens/create_meetup_screen.dart`, `edit_meetup_screen.dart`, `meetup_category_select_screen.dart` | `content_creation.ts` |
| 상세·참여 | `lib/screens/meetup_detail_screen.dart`, `user_meetups_screens.dart` | `index.ts` |
| 모임 후기 | `lib/screens/create_meetup_review_screen.dart`, `review_detail_screen.dart`, `review_approval_screen.dart` | `index.ts` |

### 4. #태그 (관심사)

태그는 방이 아니라 라벨이에요. 프로필에 최대 8개, 글·모임에 최대 3개 붙여요.

| 무엇 | 앱 | 서버(`functions/src/interest_tags.ts`) |
|---|---|---|
| 태그 둘러보기·검색·만들기(이름·설명·분류) | `lib/screens/tag_explore_screen.dart`, `lib/ui/sheets/tag_create_sheet.dart` | `exploreTags`, `searchTags`, `createTag` |
| 태그 페이지(사람·포스트·밋업) | `lib/screens/tag_page_screen.dart`, `tag_content_tabs.dart` | `getTagSummary`, `listTagHolders`, `updateTagDescription` |
| 마이페이지 관심 탭: 숫자 카드, 관심 지도, 새로 알게 될 사람 | `lib/ui/interest/`(`interest_tab.dart`, `interest_bento.dart`, `overlap_*`) | `getMyInterestOverview`, `getOverlapPeople`, `setSuggestionHidden` |
| 처음 사용자: 완성도 카드, 키캡 고르기 | `lib/ui/interest/first_run_interest.dart` | `setProfileTags` |
| 내 태그 저장(바로 반영, 실패 시 되돌림) | `lib/services/my_tags_store.dart` | `setProfileTags` |
| 태그 알림, 뜨는 태그 | `lib/ui/widgets/my_tags_new_row.dart` | `getMyTagNewCounts`, `computeTagTrends` |

## 보조 기능

| 기능 | 앱 | 서버 | 비고 |
|---|---|---|---|
| 로그인·가입 | `login_screen.dart`, `email_login_screen.dart`, `signup_method_selection_screen.dart`, `nickname_setup_screen.dart` | `registration_progress.ts`, `nickname_claims.ts` | |
| 한양메일 인증 | `hanyang_email_verification_screen.dart`, `lib/utils/hanyang_verification_helper.dart` | `hanyang_verification.ts`, `email_verification_policy.ts` | 한양대 전용 공개 범위와 학교 표시에만 쓰여요 |
| 친구·그룹 | `friends_page.dart`, `friend_categories_screen.dart`, `requests_page.dart` | `index.ts`, `frozen_audience.ts` | |
| 검색 | `unified_search_screen.dart` | `content_search.ts`, `user_search_index.ts` | |
| 알림 | `notification_screen.dart`, `notification_settings_screen.dart` | `badge_policy.ts`, `chat_push_presentation.ts` | |
| 기관 계정 | `organization_*` | `organization_accounts.ts` | |
| 학기 할 일 | `semester_todo_screen.dart` | `personal_todo_reminders.ts` | |
| 신고·차단·계정 삭제 | `blocked_users_screen.dart`, `account_delete_stepper_screen.dart` | `index.ts` | |

## 개발·운영 도구

일반 사용자에게는 보이지 않아요.

- `button_lab_screen.dart`, `ad_showcase_screen.dart`, `relationship_orbit_preview_screen.dart`: 디자인 확인용
- `release_diagnostics_screen.dart`, `admin_migration_screen.dart`, `semester_todo_admin_screen.dart`: 운영용

## 코드 구조

- `lib/screens/`: 화면
- `lib/ui/`: 공용 위젯·시트(`ui/interest/`는 태그·마이페이지 v4)
- `lib/services/`: Firebase 접근, 캐시, 번역
- `lib/models/`, `lib/providers/`: 데이터 모델과 상태
- `lib/l10n/`: ko/en/zh 문구(`app_*.arb`, `flutter gen-l10n`)
- `functions/src/`: Cloud Functions(서울 `asia-northeast3`)
- `firestore.rules`, `firestore.indexes.json`: 보안 규칙·인덱스

## 2026-10-20 정리한 것

- 앱 어디서도 쓰지 않는 파일 37개를 지웠어요.
  - 옛 프로필 그리드, 옛 리뷰 요청·수락, 옛 검색 결과, 쓰지 않는 위젯·도구 등
- 쓰지 않는 private 함수 49개와 필드·변수 19개, import를 지웠어요.
- 루트의 옛 배포·수정 보고서는 `docs/archive/`로 옮겼어요.
- 테스트만 쓰는 파일 16개는 남겼어요. 예: 스낵챗 요약, 리뷰 합의.
