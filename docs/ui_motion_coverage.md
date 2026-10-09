# Wefilling UI motion coverage

검토일: 2026-10-02. 로컬 코드의 표현 계층 작업 기록이며 전체 서비스/실기기 검증 완료 보고가 아니다.

## 작업 기준과 보존

- 브랜치: `release/1.2.4`.
- 시작/완료 HEAD: `23d555f689b3c3510c3be12b96c11812a53aa9fe`. 커밋하지 않았다.
- 원격: `gaemini/wefilling-nochatbot`; 읽기 전용 `git ls-remote`에서 해당 브랜치가 같은 SHA임을 확인했다. pull/reset/stash/push/merge 없음.
- 시작 시 존재한 채팅·스낵 모션 및 테스트 미커밋 변경을 유지하고 그 위에 보완했다.
- 실제 pubspec 버전: `1.3.22+92`. 요청의 다른 버전 표기를 로컬 버전으로 간주하거나 버전을 변경하지 않았다.
- `.fvmrc`: 3.47.2. 설치 SDK: Flutter 3.44.7 / Dart 3.12.2. 설치된 SDK에서 지원하는 API를 확인해 사용했고 업그레이드/재설치 안 함.
- `third_party/cloud_firestore_platform_interface` override 유지. 의존 패키지/lockfile/패치 변경 없음. 이번에는 패키지 자체 회귀 테스트를 새로 실행하지 않았다.
- Snapshot=스낵, SnackChat=단체 채팅, DM=1:1, Post=포스트.
- 서버/Rules/인덱스/리전/검색/읽음/알림/메시지 저장/ID/순번/Outbox/만료/반응 정책 변경 없음.
- 실제 연결점에만 모션을 추가했다. 새 폰트/패키지, 새 busy lock/debounce, 자동 submit, 상시 ticker, 전역 포인터 차단 없음.
- 기능의 성공·실패는 기존 state/service 그대로다. 눌림/말풍선 등장/FCM 응답 등을 업무 성공으로 취급하지 않는다.

## 이번에 확인하여 보완한 표현 계층 결함

1. 부모/자식 Listener가 동시에 press할 수 있었다. MotionPress의 로컬 조상 억제와 MotionPressBoundary를 사용한다. gesture recognizer, 콜백, 이벤트 소비는 소유하지 않는다.
2. pointer cancel/drag에서도 최소 눌림 시간이 남을 수 있었다. cancel, 10px 초과 이동, 추가 포인터, route 비현재 상태, lifecycle inactive는 즉시 시각 상태를 정리한다. 보조 버튼은 press하지 않는다.
3. dispose 후 포인터 up 전달을 테스트로 재현했다. mounted 검사와 타이머 취소로 종료 State 접근을 막았다.
4. 공통 icon/FAB의 enabled=true + callback=null에서 활성 표시/haptic 가능성을 확인했다. effectiveEnabled를 실제 callback과 맞췄다.
5. press와 선택 pulse가 곱해질 수 있었다. resetToken으로 선택 변화 시 press를 종료한다.
6. 기존 칩 재마운트와 로컬 반응으로 새 칩이 처음 생기는 경우가 구분되지 않았다. 화면 수명의 최대 64개/400ms local visual event를 한 번 claim한다. 기존 칩의 늦은 서버 선택 동기화도 local claim이 없으면 pulse하지 않는다. 계정/방 초기화 경로에서 clear한다. 서버·영구 반응 상태가 아니다.
7. 기존 별도 iOS reduceMotion 플래그를 기존 MediaQuery.disableAnimations 계약에 연결했다. accessibleNavigation과 같은 의미로 간주하지 않는다.
8. 스낵 editor/preview 전환에서 outgoing subtree를 보유하면 같은 캔버스 GlobalKey/controller subtree가 중복 소유될 수 있었다. 기존 AnimatedSwitcher의 layoutBuilder는 현재 subtree만 유지하도록 했다. 인코딩/업로드/미디어 교체 처리 경로는 변경하지 않았다.
9. custom route에서 iOS 기본 back transition을 덮는 위험을 줄였다. 기존 Post/Snapshot의 국소 route만 native iOS/interactive back을 위임한다.
10. 테스트 fixture에 앱 번역 설정이 빠져 기존 UI가 null localization으로 실패했다. BoardMeetupCard는 기존 fake translation backend, 가입 UI는 localizations/prefs mock과 draft restore 대기를 보완했다. 생산 가입/밋업 동작을 테스트에 맞추지 않았다.

## 실제 진입 경로별 액션 분류

조건과 콜백은 원본 구현을 유지한다. 아래는 기능군별 묶음이며 공통 버튼과 호출부를 독립 구현으로 중복 세지 않는다. 상세 callback 발췌는 뒤의 소스 부록에서 확인한다.

- `custom_applied`: 실제 공통/개별 사용처의 맞춤 피드백 연결(기존 연결 유지도 포함).
- `native_preserved`: 이미 적절한 Flutter/플랫폼 피드백을 유지.
- `intentionally_static`: 입력·drag·zoom·미디어 탐색 등 transform을 피하는 이유가 있음.
- `blocked_unverified`: 실행 환경/권한/플랫폼 검증이 없거나 도달 경로 확인이 불충분. 적용 성공으로 숨기지 않음.

| 화면 | 사용자 행동 | 파일:심볼 | 구현 | callback | enabled/loading | profile | 중첩 위험 처리 | 분류 | 검증 근거 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 공통 | 주요 CTA | lib/ui/widgets/app_button.dart:AppButton.build | AppButton | onPressed | 기존 enabled·loading·null callback 유지 | primary .975 | 호출부 중복 wrapping 없음 | custom_applied | 즉시 콜백·disabled 테스트 |
| 공통 | 뒤로·닫기·검색·첨부 아이콘 | lib/ui/widgets/app_icon_button.dart:AppIconButton.build | AppIconButton | _handleTap → onPressed | enabled && onPressed != null | icon .92 + 기존 ripple/focus | 부모 MotionPress 로컬 억제 | custom_applied | 연타·Enter·Space·null/haptic 테스트 |
| 공통 | 원형/문구 FAB | lib/ui/widgets/app_fab.dart:AppFab.build | AppFab | _handleTap → onPressed | effectiveEnabled; 기존 haptic만 | 원형 .92 / extended .975 | 계층 내 단일 wrapper | custom_applied | null callback·haptic 없음 테스트 |
| 공통 | 친구 요청·취소·수락·거절·해제 | lib/widgets/relationship_action_button.dart:RelationshipActionButton.build | 공유 관계 버튼 | onPressed | 기존 null/busy 상태 그대로 | primary .975 | 개별 사용처 이중 wrapping 없음 | custom_applied | 320/360/390/430·KO/EN/ZH·큰 글자 |
| 탭 | 하단 탭 선택·재선택 | lib/widgets/adaptive_bottom_navigation.dart:AdaptiveBottomNavigation | 기존 공통 구현 | onTap | 기존 탭 callback | 기존 press/선택 아이콘 전환 | 각 탭만; 화면 switcher 추가 안 함 | custom_applied (기존 유지) | 기존 연결 모션 유지; 탭 회귀 테스트 |
| 헤더 | 로고·검색·알림·To-do | lib/screens/main_screen.dart:MainScreen / lib/widgets/semester_todo_app_bar_button.dart:SemesterTodoAppBarButton | 로고 개별 + AppIconButton | 기존 onTap/onPressed | 기존 표시 조건 | 로고 row .99 / 공통 icon | 캐시된 탭 State 보존 | custom_applied | 소스 연결; 실기기 탭 수명 미검증 |
| 인증 | 이메일 로그인·가입·다음·인증·재전송 | lib/screens/email_login_screen.dart / email_signup_screen.dart / password_setup_screen.dart / password_reset_screen.dart / hanyang_email_verification_screen.dart | AppButton 및 native 버튼 | 기존 submit/retry/navigation | 기존 busy·검증·재전송 조건 | 공통 primary 또는 native state layer | 입력 위젯 wrapper 없음 | custom_applied / native_preserved | 소스 연결; 실제 인증 서버 호출 안 함 |
| 인증 | Google/Apple 로그인·방법 선택·언어·약관 | lib/screens/login_screen.dart / signup_method_selection_screen.dart / terms_agreement_sheet.dart | Filled/Elevated/TextButton·기존 언어 선택 | 기존 OAuth/선택/약관 callback | 기존 availability/loading | nativeControl / 기존 choice | OAuth/권한창 시스템 기본 | native_preserved | login locale layout; 실인증 미검증 |
| 가입 | 닉네임 입력·국적·사진·관심사 | lib/screens/nickname_setup_screen.dart:_basicProfileStep / _showNationalityPicker / _interestsStep | TextFormField·InkWell·native choice | 기존 picker/선택/다음 | 기존 composing/availability/busy | 입력 static / native 선택 | 기존 UID·중복 검증 그대로 | native_preserved / intentionally_static | 가입 UI 2개 테스트; 국적 Dropdown 복원하지 않음 |
| 포스트 | 하트·저장·댓글·DM·공유·좋아요 목록 | lib/ui/widgets/post_action_group.dart:PostActionGroup.build | 기존 개별 MotionPress/선택 pulse | onLikeTapUp/onLikeLongPress/onSaveTap/기존 callback | 기존 isSaving·nullable callback | 기존 heart/save pulse; resetToken 추가 | pulse 시작 시 press 종료 | custom_applied | 0→1·9→10·연타·long press·동기화 테스트 |
| 포스트 | 카드 열기·메뉴·투표·신고 | lib/ui/widgets/optimized_post_card.dart:OptimizedPostCard / lib/ui/widgets/poll_post_widget.dart | InkWell·PopupMenu/native controls | 기존 onTap/onSelected | 기존 공개/차단/소유자 조건 | native state layer | 전체 포스트 scale 없음 | native_preserved | 원래 탐색·투표 callback 유지; 기기 미검증 |
| 포스트 | 작성자·카테고리 진입 | lib/ui/widgets/optimized_post_card.dart:_buildPostMeta / lib/screens/post_detail_screen.dart | 개별 MotionPress | 기존 profile/category callback | 익명·삭제·nullable 조건 그대로 | row .99 | 독립 액션만 반응 | custom_applied | 소스 연결; 카드 전체 scale 없음 |
| 포스트 | 작성·수정·이미지·첨부 삭제·공개범위 | lib/screens/create_post_screen.dart / edit_post_screen.dart / lib/ui/widgets/post_category_selector.dart | AppButton/native choice·개별 미디어 | 기존 게시/저장/삭제/picker | 기존 _isSubmitting·선택 조건 | 미디어 .985 / remove .92 / choice 기존 | 첨부 삭제 시 미디어 부모 억제 | custom_applied / native_preserved | 소스 조건 대조; 실제 업로드 안 함 |
| 포스트 | 상세 route push/pop | lib/screens/post_detail_screen.dart:PostDetailMotionRoute | 기존 route 국소 보완 | Navigator 원래 반환값 | 권한 변경 없음 | Android 기존 fade/작은 slide; iOS native | Hero/전역 route 교체 없음 | custom_applied / native_preserved | iOS edge-back·Android handlePopRoute widget test |
| 댓글 | 포스트 댓글·작성자·답장 취소·신고 | lib/ui/widgets/enhanced_comment_widget.dart:buildContent / lib/screens/post_detail_screen.dart | 프로필 개별; 본문 기존 gesture | 기존 profile/action/reply callback | 기존 차단·삭제·소유자 조건 | profile .99 / cancel .92; 본문 정적 | 전체 댓글 row transform 없음 | custom_applied / intentionally_static | 소스 연결; 텍스트 선택/메뉴 보존 |
| 스낵 | 트레이 열기·내 스낵 + | lib/snapshot/snapshot_today_section.dart:_SnackTileShell / _MySnackTile / _open / _create | 개별 MotionPress | 기존 상세/생성 callback | 기존 접근·선택 조건 | tile .975 / + .91; opacity 없음 | + 포인터가 부모 press 억제 | custom_applied | 중첩 callback 테스트; 실제 트레이 기기 미검증 |
| 스낵 | 상세 하트·댓글·편지·조회자·작성자·닫기·메뉴 | lib/screens/snapshot_detail_screen.dart:_submitReaction / _SnapshotBottomControls / _SnapshotTopRegion | 개별 + AppIconButton | 기존 reaction/comments/letter/viewers/profile | 기존 1회 반응·권한·만료 조건 | 기존 pulse / icon / 작성자 .99 | 새 하트 수/반응 원본 없음 | custom_applied | snapshot motion/layout; 서버 반응 전송 안 함 |
| 스낵 | 좌우 탐색·사진·영상 재생 | lib/screens/snapshot_detail_screen.dart:_moveTo / lib/snapshot/snapshot_storage_video.dart | 기존 gesture/player | 기존 onTapUp/swipe/play | 기존 preload·expiry·현재 ID | 페이지 내부 기존 모션; 재생 static | 제스처 threshold/자동 넘김 변경 없음 | intentionally_static / native_preserved | snapshot layout/motion; 실제 player 미검증 |
| 스낵 | 상세 진입/뒤로 | lib/screens/snapshot_detail_screen.dart:SnapshotDetailMotionRoute | MaterialPageRoute 국소 전환 | 기존 Navigator callback | 권한/공개 프리뷰 동일 | Android 짧은 fade/slide; iOS native | 원본/썸네일 중복 Hero 없음 | custom_applied / native_preserved | native edge-back·Android back widget test |
| 스낵 편집 | 텍스트 추가·목록·색/정렬·구간/공개·다음·게시 | lib/screens/create_snapshot_screen.dart:_continueFromEditor / _upload | 실제 기존 버튼 + common | 기존 edit/preview/게시 callback | 기존 5개·12초·busy 조건 | icon/primary/choice 기존 | 편집·미리보기 outgoing subtree 미보유 | custom_applied / native_preserved | 빠른 editor reversal 단일 GlobalKey 캔버스 테스트 |
| 스낵 편집 | 레이어 입력·이동·pinch·trim | lib/screens/create_snapshot_screen.dart:_buildTextLayer / beginDrag / snapshotEditorMotionLayout | 기존 GestureDetector·TextField | 기존 ID 기반 편집/drag/scale | 기존 editing·처리 세대 | staticGesture | press wrapper 없음; 실제 canvas 기준 유지 | intentionally_static | 좌표/합성 변경 없음; native 인코딩 미검증 |
| 스낵 댓글 | 작성·전송·GIF 입력·목록·편지·조회자·보관 | lib/screens/snapshot_comments_sheet.dart / snapshot_comment_letter_screen.dart / snapshot_viewers_screen.dart / snapshot_archive_screen.dart | send 개별 + native 행/버튼 | 기존 _submit/선택/조회 | 기존 canSend·권한 조건 | send .90 / 기타 native | IME·GIF 경로·댓글 store 그대로 | custom_applied / native_preserved | 소스 연결; OS 키보드 GIF 미검증 |
| 채팅 | 스낵챗/DM 전송·첨부·사진/파일 확인 | lib/screens/snack_chat_screen.dart:_buildComposerButton / lib/screens/dm_chat_screen.dart:_buildComposer / dm_image_send_preview_screen.dart | 개별 MotionPress/native preview | 기존 _send/_sendMessage/첨부 | 기존 canSend·업로드/busy; 공통 잠금 추가 없음 | send .90 / attach .90 / native 확인 | 입력 TextField 안정된 슬롯 | custom_applied / native_preserved | send state/outgoing 회귀; 네트워크 전송 안 함 |
| 채팅 | 메시지 long press·복사·답장·재시도·삭제 | lib/screens/snack_chat_screen.dart:_buildMessageBubble / _showMessageActions / lib/screens/dm_chat_screen.dart:_buildMessageList / _buildDmMessageQuickActions | 말풍선/메뉴만 개별 | 기존 메뉴·retry/reply callback | 기존 메시지 권한·실패 상태 | bubble .985 / menu .99 / icon | 시간·읽음·avatar·reaction 전체 row 축소 안 함 | custom_applied | scroll cancel·long press·send state·DM read 테스트 |
| 채팅 | 반응 선택·해제·사용자 목록 | lib/ui/widgets/chat_reaction_widgets.dart:ChatReactionPickerRow / ChatReactionBar / ChatReactionMotionEvents | 공유 + 화면별 local event | onSelected/onToggle/onShowUsers | 기존 실제 selected·counts | press .90 → 로컬 첫 생성 pulse 1.15 | resetToken 종료; event 한번 claim | custom_applied | 기존 mount pulse 없음·local 0→1·방 분리 clear 테스트 |
| 채팅 | 링크·인용·사진 열기 | lib/ui/widgets/snack_chat_message_extras.dart / lib/screens/dm_chat_screen.dart | 개별 media + MotionPressBoundary | 기존 link/reply/image callback | 기존 pending·Storage/접근 조건 | media .985; link/quote native | preview/quote 부모 시각 억제; Linkify 제스처 유지 | custom_applied / intentionally_static | 공통 boundary 테스트; 실제 링크 중첩 기기 미검증 |
| 채팅 | 답장 프리뷰 추가·교체·취소 | lib/ui/widgets/chat_reply_reveal.dart:ChatReplyReveal | 공통 내용 fade | 기존 reply ID/취소 callback | 기존 reply 선택값 | 짧은 fade; 높이/slide 없음 | 이전 child IgnorePointer/ExcludeSemantics | custom_applied | draft·cursor·IME composing·focus 유지 |
| 채팅 | 로컬 outgoing 등장·번역 펼치기 | lib/ui/widgets/snack_chat_outgoing_entrance.dart / soft_translate_reveal.dart | 기존 ID claim/번역 helper | 원래 상태 전달 | 기존 local ID/claimWindow·번역 결과 | 기존 entrance/soft reveal; reduced no replay | ACK/복구로 새 entrance 유발 안 함 | custom_applied | outgoing·send/read 회귀; 실제 지연 ACK 기기 미검증 |
| 채팅 목록/정보 | 방 열기·즐겨찾기·만들기·참여자·언어·나가기 | lib/screens/snack_chat_tab_view.dart / snack_chat_info_screen.dart / dm_list_screen.dart / create_snack_chat_screen.dart / snack_chat_discovery_screen.dart | native 행/메뉴 + 공통 + profile 개별 | 기존 open/select/settings/leave | 기존 만료·참여·권한 조건 | native state layer; profile .99 | 목록 전체 scale 없음 | custom_applied / native_preserved | 소스 연결; 실제 권한/푸시 진입 미검증 |
| 밋업 | 목록·카테고리·달력·날짜·오늘·pager | lib/screens/home_screen.dart:MeetupHomePage / lib/ui/widgets/meetup_home_card.dart / lib/widgets/date_selector.dart | 기존 Ink/day marker/native controls | 기존 select/open/calendar callback | 기존 필터·조회·선택 조건 | native/기존 choice | 달력 pager 이중 애니메이션 없음 | native_preserved | 소스 분류; 실제 월 전환 기기 미검증 |
| 밋업 | 포스트 내 밋업 카드·위치 | lib/ui/widgets/board_meetup_card.dart:BoardMeetupCard / _InlineMeta | 카드 native / 위치 개별 | onTap/onLocationTap | 기존 nullable 위치 callback | card native / location .99 | 위치만 눌림; 카드 callback 0 | custom_applied / native_preserved | 실제 카드 위젯 location 회귀 포함 7개 |
| 밋업 | 만들기·참여/취소·수락/거절·참가자·공개범위 | lib/screens/create_meetup_screen.dart / edit_meetup_screen.dart / meetup_detail_screen.dart / meetup_participants_screen.dart / meetup_visibility_group_select_screen.dart | common/native + 개별 primary | 기존 submit/participation/approval | 기존 busy·정원·권한 | primary .975 / destructive .99/native | 신청을 승인 성공으로 표현 안 함 | custom_applied / native_preserved | 소스 guard 대조; 실제 신청 안 함 |
| 밋업/후기 | 사진·링크·후기 작성/승인/댓글 | lib/screens/meetup_detail_screen.dart / create_meetup_review_screen.dart / review_detail_screen.dart / review_approval_screen.dart / review_comments_screen.dart | 미디어 개별 + native/common | 기존 image/link/review callback | 기존 _isSubmitting·권한 | media .985 / remove .92 / link .99 | 원래 후기 API·이미지 뷰어 유지 | custom_applied / native_preserved | 소스 연결; 실제 승인/업로드 미검증 |
| 친구/그룹 | 검색·프로필·요청·그룹 선택/추가/수정/삭제 | lib/screens/friend_categories_screen.dart / friends_page.dart / requests_page.dart / create_category_screen.dart / category_detail_screen.dart | RelationshipActionButton/common/native·개별 slot | 기존 relation/group callback | 기존 차단·상태·loading | 공통 primary; slot .99 / native row | 행 안 친구 액션만; 새 관계 state 없음 | custom_applied / native_preserved | 소스 사용처; 관계 버튼 다국어 회귀 |
| 프로필 | 내/친구 사진·후기·설정·저장 | lib/screens/mypage_screen.dart / friend_profile_screen.dart / profile_edit_screen.dart | photo/review 개별 + native/common | 기존 viewer/profile/save | 기존 URL·삭제·소유권 조건 | photo/review .985 / profile row .99 | 공유 프로필 캐시 그대로 | custom_applied / native_preserved | 소스 guard 대조; 실제 사진/저장 미검증 |
| To-do | 주차·달력·추가·수정·삭제·완료·펼치기·학생 유형 | lib/screens/semester_todo_screen.dart / student_type_selection_screen.dart | 기존 native Checkbox/controls + common | 기존 todo/save/complete/selection | 기존 busy/학생 유형 조건 | nativeControl / 기존 motion | 전체 Checkbox scale 없음; 재정렬 정책 그대로 | native_preserved / custom_applied | semester todo layout·키보드·SafeArea 회귀 |
| 검색 | 검색어 삭제·필터·사람/포스트/모임 결과 | lib/screens/unified_search_screen.dart / search_users_page.dart / meetup_search_screen.dart | clear 개별·native row/common | 기존 invalidate/clear/open | 기존 query/session/generation | clear .92 / native rows | controller/커서·검색 API 그대로 | custom_applied / native_preserved | 소스 연결; 실제 검색 서버 요청 안 함 |
| 알림 | 항목 열기·개별/모두 읽음·삭제/설정 | lib/screens/notification_screen.dart / lib/widgets/notification_list_item.dart | native Ink/menu/common | 기존 read/open/delete callback | 기존 계정·읽음 성공 조건 | native state layer | Dismissible/OS 제거 정책 변경 없음 | native_preserved | 소스 분류; OS 지연 푸시 미검증 |
| 설정 | 언어·알림 Switch·인증·차단해제·로그아웃·탈퇴 | lib/screens/account_settings_screen.dart / notification_settings_screen.dart / blocked_users_screen.dart / account_delete_stepper_screen.dart | native ListTile/Switch + common | 기존 settings/confirm callback | 기존 busy·확인·Auth 조건 | nativeControl / destructive native | Switch 추가 scale 없음·확인 정책 유지 | native_preserved / custom_applied | nested switch widget test; 실제 계정 작업 안 함 |
| 운영자/조직 | 관리·마이그레이션·학기 편집·조직 초대/수정 | lib/screens/admin_migration_screen.dart / semester_todo_admin_screen.dart / organization_home_screen.dart / organization_profile_edit_screen.dart | native/common | 기존 admin/organization callback | 기존 관리자·소유자 권한 그대로 | native/공통 primary | 권한 노출/운영 데이터 호출 변경 없음 | native_preserved / blocked_unverified | 소스 분류만; 운영 권한·실행 미검증 |
| 메뉴/시스템 | 날짜/시간·공개범위·신고·확인·공유·사진·권한창 | 관련 native menu/dialog/picker; 위 파일 부록 참조 | native/app-owned common | 기존 onSelected/confirm/SDK | 기존 취소·권한·busy | nativeControl / destructive native | Navigator/OS surface 강제 wrapping 없음 | native_preserved / blocked_unverified | 소스 확인; 실제 OS SDK 창 미검증 |
| 광고 | 배너·페이지 전환·외부 링크 | lib/widgets/ad_banner_widget.dart:AdBannerWidget | 실제 클릭 카드 개별 | 기존 _handleAdTap | 기존 광고 선택·callback | card .985 | 부모 switcher stable banner key 보존 | custom_applied | 소스 key 대조; 광고 서버/외부 링크 미검증 |

## 추가 recognizer / Cupertino 확인

| 화면/행동 | 파일:심볼 | callback/조건 | 구현/profile | 중첩 처리 | 분류/근거 |
| --- | --- | --- | --- | --- | --- |
| 포스트 본문 URL | lib/ui/widgets/post_linkified_text.dart:_rebuildSpans | LinkableElement에만 _openExternalUrl; visibleSourceLength 유지 | TextSpan/TapGestureRecognizer; staticGesture | 전체 포스트 transform 없음; recognizer 재설계 안 함 | intentionally_static; 실제 URL 실행 미검증 |
| 댓글 URL | lib/ui/widgets/enhanced_comment_widget.dart:_buildLinkifiedSpans | LinkableElement에만 _openLinkUrl | TextSpan/TapGestureRecognizer; staticGesture | 댓글 전체 row transform 없음 | intentionally_static; OS 선택/링크는 blocked_unverified |
| 밋업 시간 | lib/screens/create_meetup_screen.dart:CupertinoDatePicker | 기존 선택 시간 변경 callback | nativeControl | 별도 scale 없음 | native_preserved; 앱이 그리는 picker만 유지 |
| To-do 시간 | lib/screens/semester_todo_screen.dart:CupertinoDatePicker | 기존 편집/시간 조건 | nativeControl | 별도 scale 없음 | native_preserved; 예약 정책 변경 없음 |
| 스낵챗 일정 선택 | lib/screens/snack_chat_poll_schedule_screen.dart:CupertinoPicker.builder | 기존 일정 선택 callback | nativeControl | scroll/선택 feedback 유지 | native_preserved; 일정 생성 요청 변경 없음 |

## 미검증 / 의도적 보존

| 영역 | 분류 | 남은 확인 / 이유 |
| --- | --- | --- |
| 앱 설치본 전체 액션·VoiceOver/TalkBack 실제 activate | blocked_unverified | widget semantics/focus를 유지했지만 연결 기기가 없어 전체 경로를 실제로 눌러 보지 못함 |
| Android predictive back·푸시/deep-link 진입 복귀 | blocked_unverified | handlePopRoute widget test만 수행. 실제 시스템/콜드 스타트 navigation 검증 아님 |
| iOS 시스템 Reduce Motion·edge-back | blocked_unverified | 플랫폼 accessibility test flag/live update와 Cupertino route gesture 테스트. 물리 기기 설정/영상 증거 없음 |
| OS 사진/권한/OAuth/외부 공유 시트 | native_preserved / blocked_unverified | 앱이 직접 그리지 않는 surface. SDK 경로 변경 없음; 실제 플랫폼 실행 안 함 |
| 실제 영상 player·빠른 사진 넘김·native 합성/인코딩 | blocked_unverified | 단일 canvas/key 전환·기존 layout 검사만 수행. plugin player/controller 실제 native 동작 미검증 |
| 장문 번역·키보드 GIF·실채팅 지연 ACK/재접속 | blocked_unverified | 기존 send/read/outgoing 모델 및 reply IME 회귀만 통과. 운영 메시지/번역/업로드 요청하지 않음 |
| compact 채팅 반응 칩의 터치 영역 | blocked_unverified | 기존 minHeight 30의 밀도를 유지. 목표 44/48dp를 전체 기기에서 충족했다고 주장하지 않음. 실제 인접 hit area 검토 필요 |
| native Linkify/텍스트 선택과 bubble press | intentionally_static / blocked_unverified | quote/link preview는 boundary; 텍스트 recognizer 교체 없음. 실제 OS 선택/링크 제스처 충돌은 기기 확인 필요 |
| 운영자/조직 권한별 조건부 액션 | blocked_unverified | 소스 callback/컨트롤 분류만 확인; 운영 권한 변경/실제 마이그레이션 실행 없음 |
| AppLikeButton | intentionally_static | 현재 production 외부 사용처 미발견. 미사용 scale controller의 구조를 정리하지 않음 |
| AnimatedButton, EnhancedFab, SocialActionButton, StoryCategories | intentionally_static | 현재 외부 production 생성 호출 미발견. 실제 경로 대신 이 보조 위젯만 고쳤다고 보고하지 않음 |
| ProfileGridScreen/PostGrid/HighlightReels, SearchResultPage, ReviewAcceptScreen | intentionally_static | 현재 production 외부 진입 미발견. ReviewAccept의 비어 있는 이미지 callback을 새 기능으로 구현하지 않음 |
| 성능/frame/전송 latency | blocked_unverified | profile/device 측정 없음. 60/120Hz 목표 달성·속도 개선을 주장하지 않음 |

## 검증 명령과 결과

```sh
/Users/chajaemin/flutter/bin/flutter test --no-pub \
  test/motion_press_regression_test.dart \
  test/motion_route_ownership_test.dart \
  test/motion_interaction_test.dart \
  test/chat_motion_interaction_test.dart \
  test/snapshot_motion_interaction_test.dart \
  test/post_action_group_test.dart \
  test/post_detail_motion_route_test.dart \
  test/adaptive_bottom_navigation_test.dart \
  test/snack_chat_outgoing_entrance_test.dart \
  test/snack_chat_send_state_test.dart \
  test/snack_chat_read_visibility_test.dart \
  test/dm_message_reaction_test.dart \
  test/dm_read_receipt_test.dart \
  test/snapshot_preview_layout_test.dart \
  test/snapshot_detail_layout_test.dart \
  test/board_meetup_card_test.dart \
  test/semester_todo_layout_test.dart \
  test/login_locale_layout_test.dart \
  test/nickname_setup_screen_test.dart --reporter expanded
```

- 위 최종 묶음: **19개 파일, 159개 통과**, exit 0. 전체 앱 테스트나 운영 기능 검증이 아니다.
- 마지막 채팅 hydration pulse 조건 보완 후 직접 연결된 `chat_motion_interaction_test`와 `motion_press_regression_test` **14개를 다시 통과**했다. 같은 테스트의 재실행을 별도 고유 테스트 수에 더하지 않았다.
- 빠른 tap, cancel/drag, 보조·다중 포인터, dispose, route cover, inactive 복원; 중첩 버튼/boundary/Switch; callback 한 번/disabled 0회; Enter/Space; local 0→1 pulse와 기존 mount 무반응을 포함한다.
- 포스트 하트/저장 상태와 count 전환, 채팅 outgoing claim/send state/read receipt, snapshot page/layout, reply draft/커서/composing/focus, native iOS back/Android back, 편집 canvas key 빠른 왕복을 포함한다.
- 관계 버튼 320/360/390/430px × KO/EN/ZH × 2.0x, 기존 login locale layout 및 To-do SafeArea/키보드 회귀를 실행했다. 모든 실제 화면의 모든 조합이 검증된 것은 아니다.
- route 테스트는 생산 route 타입에 placeholder content를 사용한다. Firebase 연결 화면 전체의 통합 실행은 아니다.
- 변경/추가 Dart 파일 대상으로 `dart analyze --format machine <파일목록>`: **ERROR 0 / WARNING 150 / INFO 510**, exit 2. 경고의 해당 소스 줄은 HEAD에도 존재함을 대조했다. 새 helper/test의 info 없음. 기존 경고를 관련 없는 cleanup으로 지우지 않았다.
- `git diff --check` 통과.
- `adb devices -l`: 연결 기기 없음. `xcrun simctl list devices booted`: 부팅된 기기 없음. 화면 녹화/프레임 캡처 없음.
- 앱 빌드/APK/스토어 업데이트, Firebase 배포, push/merge 없음. 로컬 Flutter 진입 `lib/main.dart → MeetupApp → MainScreen/auth routes`에서 연결된다. 설치된 앱에는 새 앱 빌드/배포 전 반영되지 않는다.

## 버튼 인터랙션 6유형 — 2026-10-05 적용

기획서 「위필링 버튼 인터랙션 디자인 계획서」를 기존 모션 기반(`MotionPress`,
`MotionSelectionPulse`, `MotionStateIcon`, `MotionTokens`) 위에 조합으로 적용했다.
화면 구성·문구·콜백·검증·정책은 바꾸지 않았다. 스낵챗(S11~S16) 포함.
개발용 비교 화면: `lib/screens/button_lab_screen.dart`(kDebugMode, `/button-lab`,
계정 설정 → "버튼 랩").

### 공통 프리미티브

| 유형 | 조합 | 스케일 | 시간 | 햅틱 | 감소 동작 |
|---|---|---|---|---|---|
| 1 기본 눌림 | `MotionPress` / `AppIconButton` / `AppFab` | 아이콘 .92 · 텍스트/탭 .985 · 행 .99 | press 90 / release 160 | 없음 | 변형 없음 |
| 2 선택 | `MotionSelectable`(`lib/ui/widgets/motion_selectable.dart`) + 호출부 `AnimatedContainer`/`AnimatedDefaultTextStyle`/`MotionStateIcon` | 칩 .97 · 세그먼트/탭 .985 · 행 1.0(스케일 없음) | 전환 `MotionTokens.state` 200 | 없음 | `MotionTokens.of` → 0ms, 색/체크만 |
| 3 반응·체크 | `MotionPress(resetToken)` + `MotionSelectionPulse` + `MotionStateIcon` | 좋아요 .88 · 저장 .9 · 체크 .9 | pulse 90+80 · 아이콘 200/140 | 성공 후 `likeSelected`/`checkCompleted` | 아이콘 교체만 |
| 4 처리 | `MotionProcessingButton`(`motion_processing_button.dart`) + `ProcessingFeedback` | .975 | 성공 체크 전환 200, 유지 600 | 선택적 `processingSuccess` | 즉시 교체 |
| 5 연속 실행 | `MotionPress(enabled: canSend, .90)` (기존) | .90 | press/release만 | 없음 | 없음 |
| 6 주의 행동 | `MotionPress(.99)` / `MotionProcessingButton(cautiousScale, feedback: null)` | .99 | 성공 단계 없음 | 없음 | 없음 |

- `MotionTokens.of(context, duration)`: 감소 동작이면 0ms. 새 코드는 리터럴 ms를 쓰지 않는다.
- `MotionHaptics`(`lib/utils/motion_haptics.dart`): `likeSelected`·`checkCompleted`·`processingSuccess` 3종만. 기존 `HapticFeedback.*` 직접 호출과 `AppIconButton`의 lightImpact는 그대로. 신규 호출 지점은 할 일 완료 성공(`semester_todo_screen.dart` `_togglePersonalTodo`)과 밋업 참여 성공(`meetup_detail_screen.dart`) 2곳 + ButtonLab.
- `ProcessingFeedback.success()`는 호출부가 **실제 결과를 받은 뒤**에만 호출한다. busy는 호출부 플래그에서만 파생되므로 요청 전에 스피너·성공이 먼저 보일 수 없다. 라벨 슬롯은 한 인스턴스를 유지해 버튼 크기가 변하지 않는다.
- `_PostSelectionPulse`(post_action_group) 삭제 → `MotionSelectionPulse(key: ValueKey('post_selection_pulse'))`로 통일.

### 처리형: 실제 결과 표시 가능 여부

| 버튼 | busy | 결과 | 적용 |
|---|---|---|---|
| 밋업 참여/확정 `_buildBottomButton` | `_isLoading` | 있음(`success` 지역) | `ProcessingFeedback.success()` + 참여 성공 햅틱 |
| 밋업 나가기/취소 | `_isLoading` | 있음 | 주의 행동형 .99, 성공 연출 없음. **나가기에 확인 다이얼로그 없음(기존 정책, 변경 안 함)** |
| 가입 완료/다음, 모임 생성, 즐겨찾기 저장, 학생 유형 저장, 프로필 저장, 할 일 편집 저장 | 각 플래그 | 성공 시 화면 이동 | 눌림 + 기존 busy 표시만(`feedback: null` 또는 `MotionPress`) |
| 로그인(소셜/이메일), 스냅 업로드, 친구 요청 수락/거절/취소, DM·스낵챗 전송 | 기존 | — | 변경 없음(이미 적용 또는 새 대기 조건 금지) |

### 선택형 적용 지점
관심사 칩(`social_profile_fields.dart`, 가입·프로필 편집 공용), 밋업 카테고리 탭·공개범위 세그먼트, 스냅 공개범위/그룹 행, 그룹 다중 선택 행, 학생 유형, 할 일 주차 탭, DM 목록 탭, 로그인 언어, 마이페이지 그리드/리스트 토글, 검색·요약 picker 칩, 스낵챗 생성의 활성 시간 세그먼트, 스낵챗 정보의 토글 아이콘. Material `TabBar` 4곳은 `Tab.child`에 `MotionPress(.985)`만 두고 인디케이터는 native 유지. 알림 설정 `Switch`는 상위 press가 없어 변경하지 않았다.

### 기록
- 할 일 주차 탭 라벨은 기존 테스트가 `Text.style`을 직접 읽으므로 인라인 style을 유지했다(밑줄 컨테이너만 토큰 전환).
- 마이페이지 그리드/리스트 토글은 기존 36×36이라 48dp 미만이다. 더 줄이지 않았고 제품 확인 항목으로 남긴다.
- 밋업 참여 성공 체크는 참여 직후 버튼이 '나가기'로 바뀌어 거의 보이지 않을 수 있다(의도: fire-and-forget, 이동을 지연하지 않음). 햅틱은 동작한다.
- 실기기 확인 미수행: Android/iOS에서 ButtonLab 5행 비교, VoiceOver/TalkBack, iOS Reduce Motion ON에서 색/체크만 남는지.

### 검증 명령 (추가)

```sh
flutter test --no-pub test/motion_selectable_test.dart test/motion_processing_button_test.dart \
  test/motion_haptics_test.dart test/button_lab_screen_test.dart test/post_action_group_test.dart \
  test/semester_todo_layout_test.dart test/login_locale_layout_test.dart test/nickname_setup_screen_test.dart
```

## App Start Flow — 2026-10-03 추가 적용

이 절이 시작/로그인 관련 최신 기록이다. 뒤의 소스 후보 부록은 2026-10-02 감사 시점의 검색용 줄 번호이며 이번에 이동한 심볼은 이름으로 찾는다. 이전 작업을 보존했다. 친구요청 버튼은 후속 사용자 요청에 따라 오른쪽 상단 고정 배치에서 기존 작성자 정보 옆 위치로 복원된 상태를 유지한다.

기준: `release/1.2.4`, 시작/끝 HEAD `23d555f689b3c3510c3be12b96c11812a53aa9fe`. 미커밋 상태로 반영. FVM 설정 3.47.2 / 설치 Flutter 3.44.7·Dart 3.12.2; SDK/의존성/버전 변경 없음.

실제 경로: `main → 기존 Firebase/AppCheck/locale/cache 초기화 → MultiProvider(AuthProvider, RelationshipProvider) → MeetupApp.home → 기존 auth/가입/조직 분기 → MainScreen._screenCache[0] → BoardScreen`.

초기화 중에는 provider나 서버 호출을 소유하지 않는 임시 `AppStartupSurface`를 먼저 렌더한다. 초기화가 끝나면 원래 앱 루트로 교체한다. 초기화 순서와 서비스 생성 횟수는 그대로이며, 실제 앱 진입을 기다리는 최소 표시 시간은 없다.

| 화면 | 버튼/터치/상태 | 파일:심볼 | 현재 구현/적용 모션 | 실제 적용 | 검증 | 비고 |
| --- | --- | --- | --- | --- | --- | --- |
| Native launch | OS splash | 기존 Android/iOS launch | 기존 정적 surface 유지 | native_preserved | 파일/동작 변경 안 함 | 실기기 콜드 스타트 미검증 |
| Flutter bootstrap | 초기화 대기 | main.dart:main / app_start_motion.dart:AppStartupSurface | 기존 await 이전에 흰 배경/로고 표시; 일회성 fade·10px reveal | custom_applied | AppBootScreen widget test | 이 surface는 AuthProvider/Firestore/NavigationService를 만들지 않음 |
| Boot 지연 | 진행 표시 | app_start_motion.dart:AppBootScreen | 실제 대기 750ms 후에만 작은 spinner/KO·EN·ZH 문구 | custom_applied | delay/dispose 테스트 | 타이머는 장식 표시만 지연; 인증/초기화는 기다리지 않음 |
| Boot 오류 | 안전한 복구 안내 | main.dart:main의 bootstrap catch / AppBootScreen.failed | 닫고 다시 열기 안내; 기존 오류 보고 유지 | custom_applied / blocked_unverified | 오류 UI 320px·2.0x·3개 언어 테스트 | 부분 초기화 서비스를 중복 실행할 위험 때문에 임의 retry 버튼 안 만듦. 실제 초기화 실패 주입 미실행 |
| Auth gate | 복원/로그인 요청 | main.dart:MeetupApp.home / AppLoginSurface | 최초 복원은 boot; 이미 표시한 로그인은 submitting/failure에도 같은 State 유지 | custom_applied | 실제 공유 surface의 focus/input 유지 테스트 | 서버의 가입 완료·조직 계정·초대 분기 유지. 인증 화면 성공을 모션이 결정하지 않음 |
| Login entrance | 로고/본문/버튼 | login_screen.dart:_LoginScreenState | 기존 1.2초·20% slide를 280ms fade로 축소; slide 0; reduced motion 즉시 | custom_applied | login locale layout 및 reduced fake-login 테스트 | 기존 컨트롤러 재사용; 추가 전체 fade를 겹치지 않음 |
| Login method | Google/Apple/이메일/가입 이동 | login_screen.dart:_LoginMethodButton | 기존 브랜드 FilledButton + press .975; 기존 null callback/busy 유지 | custom_applied | Google 요청 연타·취소 후 재시도(fake) | handler도 최신 isLoading 확인. 실제 Google/Apple SDK 인증 미검증 |
| Email login | 로그인/진행/실패 | email_login_screen.dart:_handleLogin | press .975; 기존 spinner/inline error; loading guard | custom_applied | 프레임 재빌드 전 연타, false 응답 후 값 유지/재시도(fake) | 성공/가입 복구/메인 Navigator 경로 그대로 |
| Email input | 비밀번호 표시·입력·찾기·뒤로 | email_login_screen.dart:build | 표시 아이콘 .92; 다른 버튼 native 유지; TextFormField 그대로 | custom_applied / native_preserved / intentionally_static | 실제 이메일 화면 widget test | 새 기능·입력 controller 교체 없음 |
| 첫 메인 | Board 포함 IndexedStack body | main_screen.dart:MainScreen.build / AppEntryFade | 첫 mount의 body만 짧은 fade; 같은 subtree rebuild에는 재생 안 함 | custom_applied | stable child/reduced 테스트 + 하단 탭 회귀 | MainScreen 캐시/GlobalKey/탭 수명/배지 시작/외부 공유 경로 유지 |
| Board 초기 목록 | skeleton/content | board_screen.dart 기존 PostLoadingTransition 사용처 / post_loading_transition.dart | 기존 180ms crossfade 재사용; outgoing만 IgnorePointer/ExcludeSemantics | custom_applied (기존 유지/보완) | outgoing 액션 차단 테스트 | 조회·preload·목록/포스트 ID key·오류/빈 결과 정책 변경 없음. 리스트 stagger 추가 없음 |
| 첫 화면 액션 | 검색/알림/To-do/FAB/포스트/스낵/하단 탭 | 기존 common 및 실제 연결 위젯 | 직전 작업의 motion 그대로 | custom_applied / native_preserved | common/post/snapshot/tab 회귀 | 같은 버튼에 wrapper 중복 추가 안 함 |
| Snack/채팅/DM | 기존 모션/데이터 처리 | 기존 Snapshot·SnackChat·DM 구현 | 이번 작업에서는 새 수정 없음 | 기존 분류 유지 | snapshot motion/send state/DM receipt 대상 테스트 | ACK·queue·read·번역·Storage·공개범위·푸시·알림·badge 데이터 로직 untouched |

### 이번 실행과 남은 확인

#### 후속 재확인 및 최소 보완 — 2026-10-03

- 재첨부된 요청의 부팅·로그인·첫 메인 진입 구현은 이미 현재 작업 트리에 반영되어 있어 중복 구현하지 않았다. 기존 공통 버튼/Snapshot/SnackChat/DM 모션과 데이터 처리를 보존했다.
- `AppBootScreen`은 지연 안내가 나타날 때 중앙 Column의 높이가 바뀌어 로고가 위로 이동했다. 320px 테스트에서 y=207→169(38 logical px) 이동을 먼저 재현했다. 안내의 실제 글자 배율/언어 기준 공간을 미리 확보하고, 표시 전에는 semantics를 숨기며 spinner 자체를 생성하지 않도록 보완했다. 초기화/인증 지연 추가 없음.
- 새 회귀 테스트: 너비 320/360/390/430 × 글자 배율 1.0/1.3/2.0에서 로고 위치 유지, 숨겨진 진행 ticker 없음, 하단 48px SafeArea, overflow 예외 없음 확인.
- 후속 실행: `flutter test --no-pub test/app_start_motion_test.dart test/login_locale_layout_test.dart --reporter expanded` **23개 통과**. 아래 22/78개 기록은 이전 실행이며 합산하지 않는다. 실제 SDK 인증/첫 Board 통합 및 기기 콜드 스타트 검증을 대신하지 않는다.
- 후속 정적 분석: `dart analyze lib/ui/widgets/app_start_motion.dart test/app_start_motion_test.dart` **No issues found**, `git diff --check` 통과. 앱 빌드/APK/설치/서버 배포 없음.

#### 앞선 적용 시 검증 기록

- `flutter test --no-pub test/app_start_motion_test.dart test/login_locale_layout_test.dart --reporter expanded`: **22개 통과** (시작/로그인 신규 7개 + 기존 다국어 레이아웃 15개).
- 마지막 변경 후 `app_start_motion`, `motion_interaction`, `post_action_group`, `snapshot_motion_interaction`, `snack_chat_send_state`, `dm_read_receipt`, `adaptive_bottom_navigation`: **78개 통과**. 위 7개를 재실행했으므로 중복 집계하지 않는다.
- `dart analyze --format machine`으로 이번 7개 Dart 파일 검사: ERROR/WARNING 0. 기존 main/login/main screen의 INFO는 남겨둠. 전체 저장소 무경고 판정이 아니다.
- `git diff --check` 수행. 앱 빌드/APK/배포/push/merge/서버 배포 없음. 운영 계정·메시지·읽음·파일로 테스트하지 않았다.
- Android **SM_S916N** 연결은 확인했지만 새 코드 빌드·설치가 없어 이번 수정의 실제 기기 실행/영상 캡처는 하지 않았다. 부팅된 iOS simulator 없음.
- 실제 Firebase 복원/초기화 지연·오류, 자동 로그인→Board 통합, Apple 로그인, OS 키보드/콜드 스타트/딥링크 및 frame/latency 측정은 **blocked_unverified**. widget fake와 static 호출 경로 확인을 실제 운영/기기 검증으로 취급하지 않는다.
- 새 로컬 코드의 진입은 `lib/main.dart`이다. 설치된 앱에는 새 앱 빌드·설치/배포 전 반영되지 않는다.

## 소스 액션 감사 부록

다음은 이번 검토에서 기록한 UI 소스의 callback 후보 카탈로그다. **847개 후보 / 136개 파일은 실제 버튼 수나 적용률이 아니다.** helper의 semantic 위임, 같은 버튼의 tap/long press, 공통 위젯 정의/사용처, 비활성/null callback, 미사용 화면도 함께 나온다. 클래스/심볼은 검색용으로 가까운 선언을 기록했으며 중첩 지역 함수는 실제 상위 심볼과 함께 확인해야 한다.

분류는 컨트롤과 wrapper 연결의 소스 근거이다. 장비·권한별 실행 성공을 의미하지 않는다. 본문의 진입 경로 표와 미검증 표가 런타임 검증 범위를 우선한다. callback/조건 발췌는 최대 180자이므로 완전한 조건은 연결된 원본을 참조한다. native/haptic/원래 gesture의 의미는 변경하지 않았다.

<details>
<summary>lib/screens/account_delete_stepper_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _AccountDeleteStepperScreenState._buildCompactReasonStep:155 | onTap | InkWell | () => setState(() => _selectedReason = reason), child: Padding( padding: const EdgeInsets.symmetric(vertical: 9), child: Row( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AccountDeleteStepperScreenState._buildCompactIdentityStep:437 | onChanged | TextField | (_) { if (_reauthErrorMessage != null) { setState(() => _reauthErrorMessage = null); } | input / text | intentionally_static | IME·선택·링크의 입력 State를 모션으로 재생성하지 않음 |
| _AccountDeleteStepperScreenState._buildCompactIdentityStep:458 | onPressed | IconButton | () { setState(() { _obscureCurrentPassword = !_obscureCurrentPassword; }); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AccountDeleteStepperScreenState._buildCompactIdentityStep:485 | onPressed | TextButton | _isProcessing ? null : _openPasswordReset, style: TextButton.styleFrom( foregroundColor: AppColors.pointColor, padding: const EdgeInsets.symmetric(vertical: 8), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AccountDeleteStepperScreenState._onContinue:739 | onPressed | TextButton | () => Navigator.pop(context, false), child: Text(loc.cancel), ), TextButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AccountDeleteStepperScreenState._onContinue:743 | onPressed | TextButton | () => Navigator.pop(context, true), child: Text( loc.deleteAccount, style: const TextStyle(color: Colors.red), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AccountDeleteStepperScreenState.build:844 | onPressed | IconButton | () => Navigator.pop(context), ), title: Text( loc.deleteAccount, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AccountDeleteStepperScreenState.build:909 | onPressed | ElevatedButton | _isProcessing ? null : _onContinue, style: ElevatedButton.styleFrom( elevation: 0, backgroundColor: isLastStep | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AccountDeleteStepperScreenState.build:944 | onPressed | TextButton | _isProcessing ? null : _onCancel, style: TextButton.styleFrom( foregroundColor: const Color(0xFF64748B), minimumSize: const Size.fromHeight(44), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/account_settings_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _AccountSettingsScreenState.build:55 | onPressed | IconButton | () => Navigator.pop(context), ), title: Text( AppLocalizations.of(context)!.accountSettings ?? "", | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AccountSettingsScreenState._buildListItem:275 | onTap | InkWell | onTap, child: Container( padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0), child: Row( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AccountSettingsScreenState.applyAndClose:427 | onPressed | TextButton | () => Navigator.pop(sheetContext), style: TextButton.styleFrom( foregroundColor: const Color(0xFF667085), minimumSize: const Size(88, 44), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AccountSettingsScreenState._showResetPasswordDialog:466 | onPressed | TextButton | () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel), ), TextButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AccountSettingsScreenState._showResetPasswordDialog:470 | onPressed | TextButton | () async { Navigator.pop(context); setState(() => _isLoading = true);  | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AccountSettingsScreenState._showAppInfoDialog:634 | onPressed | IconButton | () => Navigator.pop(dialogContext), tooltip: MaterialLocalizations.of(dialogContext) .closeButtonTooltip, icon: const Icon(Icons.close_rounded), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AccountSettingsScreenState._showAppInfoDialog:741 | onPressed | TextButton | () => Navigator.pop(dialogContext), style: TextButton.styleFrom( foregroundColor: AppColors.pointColor, minimumSize: const Size(72, 44), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _LanguageOptionTile.build:786 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(10), child: Padding( padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/ad_showcase_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _AdShowcaseScreenState.build:128 | onPressed | IconButton | () => Navigator.pop(context), ), title: Text.rich( TextSpan( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AdShowcaseScreenState._buildAdCard:283 | onTap | InkWell | () => _launchUrl(banner.url), borderRadius: BorderRadius.circular(16), child: Padding( padding: const EdgeInsets.all(20), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/admin_migration_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _AdminMigrationScreenState._runMigration:62 | onPressed | TextButton | () => Navigator.pop(context, false), child: const Text('취소'), ), ElevatedButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AdminMigrationScreenState._runMigration:66 | onPressed | ElevatedButton | () => Navigator.pop(context, true), style: ElevatedButton.styleFrom( backgroundColor: Colors.red, foregroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AdminMigrationScreenState.build:203 | onPressed | ElevatedButton | _isLoading ? null : _checkStatus, icon: const Icon(Icons.refresh), label: const Text('상태 새로고침'), style: ElevatedButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AdminMigrationScreenState.build:214 | onPressed | ElevatedButton | _isLoading \|\| (_migrationStatus?['needsMigration'] != true) ? null : _runMigration, icon: const Icon(Icons.play_arrow), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/all_posts_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _AllPostsScreenState._buildFooter:267 | onPressed | TextButton | _loadMore, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text((isChineseUi(context) ? '加载更多' : isKo ? '더 불러오기' : 'Load more')), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AllPostsScreenState.build:342 | onPressed | TextButton | _loadFirstPage, icon: const Icon(Icons.refresh_rounded), label: Text((isChineseUi(context) ? '重试' : isKo ? '다시 시도' : 'Try again')), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/blocked_users_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _BlockedUsersScreenState._unblockAnonymousPost:162 | onPressed | TextButton | () => Navigator.of(context).pop(false), child: Text((isChineseUi(context) ? '取消' : isKo ? '취소' : 'Cancel')), ), ElevatedButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _BlockedUsersScreenState._unblockAnonymousPost:166 | onPressed | ElevatedButton | () => Navigator.of(context).pop(true), child: Text((isChineseUi(context) ? '取消屏蔽' : isKo ? '해제' : 'Unblock')), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _BlockedUsersScreenState._showUnblockConfirmDialog:231 | onPressed | TextButton | () => Navigator.of(context).pop(false), child: Text( (isChineseUi(context) ? '取消' : isKo ? '취소' : 'Cancel'), style: TextStyle( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _BlockedUsersScreenState._showUnblockConfirmDialog:242 | onPressed | ElevatedButton | () => Navigator.of(context).pop(true), style: ElevatedButton.styleFrom( backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _BlockedUsersScreenState.build:300 | onPressed | IconButton | () => Navigator.of(context).pop(), ), title: Text( AppLocalizations.of(context)!.blockList ?? "", | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _BlockedUsersScreenState._buildErrorState:361 | onPressed | ElevatedButton | _loadBlockedUsers, icon: const Icon(Icons.refresh), label: Text((isChineseUi(context) ? '重试' : isKo ? '다시 시도' : 'Retry')), style: ElevatedButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _BlockedUsersScreenState._buildBlockedUserCard:516 | onPressed | TextButton | () => _unblockUser(blockedUser), style: TextButton.styleFrom( foregroundColor: const Color(0xFF6366F1), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _BlockedUsersScreenState._buildBlockedAnonymousPostCard:615 | onPressed | TextButton | () => _unblockAnonymousPost(blockedPost), child: Text( (isChineseUi(context) ? '取消屏蔽' : isKo ? '차단 해제' : 'Unblock'), style: TextStyle( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/board_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| BoardScreenState.build:851 | onPressed | FloatingActionButton | () { HapticFeedback.lightImpact(); _openCreatePost(); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| BoardScreenState._buildTodaySectionHeader:1023 | onPressed | TextButton | onAction, style: TextButton.styleFrom( foregroundColor: const Color(0xFF475467), minimumSize: const Size(44, 36), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| BoardScreenState._buildHistoricalPostsFooter:1447 | onPressed | TextButton | () { if (_pagedPosts.isEmpty) { unawaited(_loadFirstHistoricalPage()); } else { | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| BoardScreenState._buildTodayMeetupCarousel:1733 | onTap | Semantics | () => _navigateToMeetupDetail(meetup), ); }, ), | semantics delegation | intentionally_static | 동일 액션의 접근성 위임; 별도 버튼으로 중복 집계하지 않음 |
| BoardScreenState._buildErrorWidget:1991 | onPressed | ElevatedButton | () => unawaited( _refreshBoardFeed(_cachedTodayPosts ?? const <Post>[]), ), child: const Text('다시 시도'), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/category_detail_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _CategoryDetailScreenState.build:209 | onPressed | IconButton | () => Navigator.pop(context), ), title: Row( mainAxisSize: MainAxisSize.min, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CategoryDetailScreenState.build:234 | onPressed | TextButton | (_hasChanges && !_isSaving) ? _save : null, style: TextButton.styleFrom( padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), minimumSize: const Size(0, 40), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CategoryDetailScreenState.build:402 | onPressed | IconButton | () { _searchController.clear(); setState(() => _searchQuery = ''); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CategoryDetailScreenState.build:418 | onChanged | TextField | (value) => setState(() => _searchQuery = value), ), ), | input / text | intentionally_static | IME·선택·링크의 입력 State를 모션으로 재생성하지 않음 |
| _CategoryDetailScreenState._buildFriendSelectionTile:502 | onTap | Semantics | () => _toggleFriend(friend.uid), excludeSemantics: true, child: Material( color: Colors.transparent, | semantics delegation | intentionally_static | 동일 액션의 접근성 위임; 별도 버튼으로 중복 집계하지 않음 |
| _CategoryDetailScreenState._buildFriendSelectionTile:508 | onTap | InkWell | () => _toggleFriend(friend.uid), borderRadius: BorderRadius.circular(12), child: Padding( padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CategoryDetailScreenState._buildSelectedFriendSlot:571 | onTap | Semantics | () => _toggleFriend(friend.uid), excludeSemantics: true, child: MotionPress( pressedScale: .99, | semantics delegation | intentionally_static | 동일 액션의 접근성 위임; 별도 버튼으로 중복 집계하지 않음 |
| _CategoryDetailScreenState._buildSelectedFriendSlot:576 | onTap | GestureDetector | () => _toggleFriend(friend.uid), child: Column( mainAxisSize: MainAxisSize.min, children: [ | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/screens/create_category_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _CreateCategoryScreenState._buildIconPicker:201 | onTap | InkResponse | () { setState(() { _selectedIcon = iconName; }); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateCategoryScreenState._buildCenteredTitle:347 | onPressed | IconButton | () => Navigator.pop(context), tooltip: MaterialLocalizations.of(context).closeButtonTooltip, ), flexibleSpace: _buildCenteredTitle(title), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateCategoryScreenState._buildCenteredTitle:356 | onPressed | IconButton | _handleSave, tooltip: actionLabel, icon: Icon( Icons.check_rounded, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateCategoryScreenState._buildCenteredTitle:367 | onPressed | TextButton | _handleSave, icon: Icon( Icons.check_rounded, size: context.ri(18).clamp(17, 20).toDouble(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ColorChoice.build:520 | onTap | InkResponse | onTap, radius: 24, child: SizedBox.square( dimension: 44, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/create_meetup_review_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _CreateMeetupReviewScreenState._buildImageTile:393 | onTap | GestureDetector | onRemove, child: Container( width: 24, height: 24, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _CreateMeetupReviewScreenState.build:440 | onPressed | IconButton | isBusy ? null : () => Navigator.pop(context), tooltip: MaterialLocalizations.of(context).backButtonTooltip, ), title: MediaQuery.withClampedTextScaling( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateMeetupReviewScreenState.build:462 | onPressed | IconButton | isBusy ? null : _submitReview, icon: isBusy ? const SizedBox.square( dimension: 18, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateMeetupReviewScreenState.build:559 | onPressed | TextButton | isBusy \|\| selectedCount >= maxImages ? null : _pickImages, style: TextButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/create_meetup_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _CreateMeetupScreenState._showTimePickerSheet:228 | onTap | InkWell | () => Navigator.pop( sheetContext, l10n.undecided, ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateMeetupScreenState._showExitConfirmationDialog:555 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(false), style: TextButton.styleFrom( foregroundColor: const Color(0xFF667085), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateMeetupScreenState._showExitConfirmationDialog:577 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(true), style: TextButton.styleFrom( foregroundColor: const Color(0xFF344054), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateMeetupScreenState.build:839 | onPressed | IconButton | () async { final shouldExit = await _showExitConfirmationDialog(); if (shouldExit && mounted) { _closeScreen(shouldSaveAutofill: false); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateMeetupScreenState.build:864 | onPressed | IconButton | _openMeetupFavorites, icon: Icon( Icons.star_border_rounded, size: context.ri(22).clamp(21, 24).toDouble(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateMeetupScreenState.build:1107 | onPressed | TextButton | _selectThumbnailImage, style: TextButton.styleFrom( foregroundColor: const Color(0xFF475467), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateMeetupScreenState.build:1214 | onTap | GestureDetector | () => _removeMeetupImageAt(0), child: Container( padding: const EdgeInsets.all(6), decoration: const BoxDecoration( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _CreateMeetupScreenState._buildBottomActionButton:1643 | onTap | InkWell | isDisabled ? null : onPressed, borderRadius: BorderRadius.circular(12), child: Ink( decoration: BoxDecoration( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateMeetupScreenState._buildCategorySelectField:1768 | onTap | InkWell | _openMeetupCategorySelection, child: Container( constraints: BoxConstraints( minHeight: context.rh(48, min: 46, max: 52), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateMeetupScreenState._buildPublicDurationSection:1961 | onTap | InkWell | _showPublicDurationSheet, borderRadius: BorderRadius.circular(8), child: Container( constraints: const BoxConstraints(minHeight: 48), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateMeetupScreenState._buildMeetupDateSection:2066 | onTap | InkWell | () { setState(() { _isCalendarExpanded = !_isCalendarExpanded; }); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateMeetupScreenState._buildTimeField:2266 | onTap | InkWell | _showTimePickerSheet, child: Container( constraints: BoxConstraints( minHeight: context.rh(48, min: 46, max: 52), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateMeetupScreenState._buildParticipantsField:2314 | onTap | InkWell | _showMaxParticipantsSheet, child: Container( constraints: BoxConstraints( minHeight: context.rh(48, min: 46, max: 52), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PublicDurationOption.build:2368 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(12), child: AnimatedContainer( duration: const Duration(milliseconds: 160), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _VisibilitySegmentedControl.item:2452 | onTap | InkWell | onTap, child: AnimatedContainer( duration: const Duration(milliseconds: 160), curve: Curves.easeOut, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MiniImageThumb.build:2669 | onTap | GestureDetector | onRemove, child: Container( padding: const EdgeInsets.all(4), decoration: const BoxDecoration( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/screens/create_post_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _CreatePostScreenState._buildImageSourceOption:537 | onTap | InkWell | onTap, child: ConstrainedBox( constraints: const BoxConstraints(minHeight: 52), child: Row( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreatePostScreenState._confirmSubmitPost:781 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(false), style: TextButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreatePostScreenState._confirmSubmitPost:804 | onPressed | ElevatedButton | () => Navigator.of(dialogContext).pop(true), style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 12), backgroundColor: AppColors.pointColor, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreatePostScreenState._handleClose:879 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(), child: Text((isChineseUi(context) ? '继续编辑' : isKo ? '계속 작성' : 'Keep writing')), ), TextButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreatePostScreenState._handleClose:883 | onPressed | TextButton | () => Navigator.of(dialogContext) .pop(ExternalShareComposeOutcome.discarded), child: Text( (isChineseUi(context) ? '放弃修改' : isKo ? '공유 요청 폐기' : 'Discard'), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreatePostScreenState._handleClose:891 | onPressed | FilledButton | () => Navigator.of(dialogContext) .pop(ExternalShareComposeOutcome.saved), child: Text((isChineseUi(context) ? '保留草稿' : isKo ? '초안 유지' : 'Keep draft')), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreatePostScreenState._submitPost:1138 | onPressed | IconButton | _handleClose, tooltip: MaterialLocalizations.of(context).closeButtonTooltip, ), flexibleSpace: _buildCenteredComposerTitle(l10n.writeStory), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreatePostScreenState._submitPost:1146 | onPressed | IconButton |  (_canProceed && !_isSubmitting) ? _goToVisibilityStep : null, icon: Icon( Icons.arrow_forward_rounded, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreatePostScreenState._submitPost:1180 | onPressed | IconButton | _isSubmitting ? null : () => _goToStep(0), tooltip: MaterialLocalizations.of(context).backButtonTooltip, ), flexibleSpace: _buildCenteredComposerTitle(l10n.writeStory), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreatePostScreenState._submitPost:1191 | onPressed | IconButton | _isSubmitting ? null : _submitPost, tooltip: l10n.share, icon: _isSubmitting ? const SizedBox.square( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _CreatePostScreenState._submitPost:1209 | onPressed | TextButton | _isSubmitting ? null : _submitPost, icon: _isSubmitting ? const SizedBox.square( dimension: 15, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _CreatePostScreenState._buildAddImageButton:1313 | onPressed | TextButton | canAddImage ? _showImageSourceSheet : null, style: TextButton.styleFrom( foregroundColor: const Color(0xFF475467), disabledForegroundColor: const Color(0xFF98A2B3), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreatePostScreenState._buildSelectedImagesStrip:1351 | onTap | GestureDetector | () => _previewSelectedImages(initialIndex: index), child: Stack( children: [ ClipRRect( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _CreatePostScreenState._buildSelectedImagesStrip:1369 | onTap | GestureDetector | () => _removeImage(index), child: Container( width: 24, height: 24, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _CreatePostScreenState._buildVisibilityOption:1528 | onTap | InkWell | onTap, child: Padding( padding: EdgeInsets.symmetric( vertical: context.rs(11).clamp(9, 13).toDouble(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreatePostScreenState._buildGroupSelectionButton:1617 | onTap | InkWell | () { final nextSelection = List<String>.from(_selectedCategoryIds); if (isSelected) { nextSelection.remove(category.id); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/create_snack_chat_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _CreateSnackChatScreenState.build:193 | onPressed | IconButton | _isSubmitting ? null : () { if (_stepIndex == 1) { | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnackChatScreenState.build:208 | onPressed | TextButton |  canContinue ? () => setState(() => _stepIndex = 1) : null, style: TextButton.styleFrom( foregroundColor: const Color(0xFF344054), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnackChatScreenState.build:244 | onPressed | TextButton | _isSubmitting \|\| !canCreate ? null : () { FocusManager.instance.primaryFocus?.unfocus(); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnackChatScreenState._buildDurationOption:489 | onTap | InkWell | () => setState(() => _activeDurationHours = hours), child: AnimatedContainer( duration: const Duration(milliseconds: 160), constraints: BoxConstraints( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/create_snapshot_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _CreateSnapshotScreenState._chooseCameraMedia:696 | onTap | ListTile | () => Navigator.pop( sheetContext, SnapshotMediaType.photo, ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnapshotScreenState._chooseCameraMedia:705 | onTap | ListTile | () => Navigator.pop( sheetContext, SnapshotMediaType.video, ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnapshotScreenState._upload:1625 | onPressed | TextButton | () => Navigator.pop(dialogContext), child: Text(strings.confirm), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnapshotScreenState._confirmExit:1713 | onPressed | TextButton | () => Navigator.pop(sheetContext, false), child: Text(strings.cancel), ), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnapshotScreenState._confirmExit:1719 | onPressed | TextButton | () => Navigator.pop(sheetContext, true), style: TextButton.styleFrom( foregroundColor: const Color(0xFFB42318), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnapshotScreenState.build:1772 | onPressed | IconButton | _uploading ? null : () async { if (_step == 0 && _editingTextLayerId != null) { | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnapshotScreenState.build:1807 | onPressed | IconButton | _uploading ? null : _upload, tooltip: strings.upload, icon: _uploading ? const SizedBox.square( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _CreateSnapshotScreenState.build:1828 | onPressed | TextButton | _uploading ? null : _upload, icon: _uploading ? const SizedBox.square( dimension: 15, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _CreateSnapshotScreenState._buildTextLayer:1968 | onChanged | TextField | (text) => _handleOverlayTextChanged(layer.id, text), scrollPhysics: const NeverScrollableScrollPhysics(), onTapOutside: (_) => unawaited(_finishOverlayEditing()), textAlign: TextAl | input / text | intentionally_static | IME·선택·링크의 입력 State를 모션으로 재생성하지 않음 |
| _CreateSnapshotScreenState._buildTextLayer:2033 | onTap | GestureDetector | editing ? null : () => unawaited(_beginTextLayerEditing(layer.id)), onScaleStart: editing | staticGesture | intentionally_static | ID 기반 overlay 선택/trim; press transform 적용 안 함 |
| _CreateSnapshotScreenState._buildTextLayer:2036 | onScaleStart | GestureDetector | editing ? null : (details) => _startOverlayTransform(layer.id, details), onScaleUpdate: editing | staticGesture | intentionally_static | 기존 scroll·zoom·입력 해제·재생 gesture 보존 |
| _CreateSnapshotScreenState._buildTextLayer:2039 | onScaleUpdate | GestureDetector | editing ? null : (details) => _updateOverlayTransform( layer.id, | staticGesture | intentionally_static | 기존 scroll·zoom·입력 해제·재생 gesture 보존 |
| _CreateSnapshotScreenState._buildTextLayer:2073 | onPressed | IconButton | () => unawaited( _deleteTextLayer(layer.id), ), icon: const Icon( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnapshotScreenState._buildVideoTrimEditor:2113 | onPressed | IconButton | controller == null ? null : _toggleSourceVideoPreview, padding: const EdgeInsets.all(9), color: const Color(0xFF111827), disabledColor: const Color(0xFF98A2B3), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnapshotScreenState.beginDrag:2279 | onTapUp | GestureDetector | (details) { final pointerX = details.localPosition.dx; if (pointerX >= startX && pointerX <= endX) return; if ((pointerX - startX).abs() <= (pointerX - endX).abs()) { | staticGesture | intentionally_static | ID 기반 overlay 선택/trim; press transform 적용 안 함 |
| _CreateSnapshotScreenState.beginDrag:2288 | onHorizontalDragStart | GestureDetector | (details) => beginDrag( details.localPosition.dx, ), onHorizontalDragUpdate: (details) => updateActiveTarget( | staticGesture | intentionally_static | 기존 scroll·zoom·입력 해제·재생 gesture 보존 |
| _CreateSnapshotScreenState.beginDrag:2291 | onHorizontalDragUpdate | GestureDetector | (details) => updateActiveTarget( details.localPosition.dx, ), onHorizontalDragEnd: (_) => _trimDragTarget = null, | staticGesture | intentionally_static | 기존 scroll·zoom·입력 해제·재생 gesture 보존 |
| _CreateSnapshotScreenState.action:2387 | onPressed | IconButton | onPressed, icon: Icon( icon, size: iconSize, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _CreateSnapshotScreenState.action:2420 | onSelected | PopupMenuButton | (layerId) => unawaited(_selectTextLayer(layerId)), itemBuilder: (context) => _textLayers .asMap() .entries | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnapshotScreenState.action:2451 | onSelected | PopupMenuButton | (value) { if (value == 'front') { _bringSelectedTextLayerForward(); } else if (value == 'color') { | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnapshotScreenState._buildTextEditingToolbar:2509 | onPressed | IconButton | () => setState( () => layer.lightText = !layer.lightText, ), icon: const Icon( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnapshotScreenState._buildTextEditingToolbar:2529 | onChanged | Slider | (value) => _setTextLayerFontScale(layer.id, value), ), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnapshotScreenState._buildTextEditingToolbar:2538 | onPressed | IconButton | () => unawaited(_finishOverlayEditing()), icon: const Icon( Icons.check_rounded, color: Color(0xFF111827), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnapshotScreenState._buildEditor:2629 | onTap | GestureDetector | _handlePhotoTap, child: _mediaType == SnapshotMediaType.photo ? Image.file( | staticGesture | intentionally_static | 기존 scroll·zoom·입력 해제·재생 gesture 보존 |
| _CreateSnapshotScreenState._buildEditor:2720 | onPressed | IconButton | _textLayers.length < 5 && !_composing ? _addTextLayer : null, tooltip: | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnapshotScreenState._buildEditor:2729 | onPressed | TextButton | _textLayers.length < 5 && !_composing ? _addTextLayer : null, icon: const Icon(Icons.text_fields_rounded), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreateSnapshotScreenState._buildEditor:2752 | onPressed | FilledButton |  _composing ? null : _continueFromEditor, style: FilledButton.styleFrom( backgroundColor: AppColors.pointColor, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _RecentPhotoGallery.build:3071 | onPressed | OutlinedButton | selecting ? null : onGallery, icon: const Icon(Icons.photo_library_outlined, size: 19), label: Text(galleryLabel), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _RecentPhotoGallery.build:3077 | onPressed | OutlinedButton | selecting ? null : onVideo, icon: const Icon(Icons.video_library_outlined, size: 19), label: Text(videoLabel), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _RecentPhotoGallery.build:3098 | onPressed | TextButton | onRetry, child: Text(retryLabel)), const SizedBox(width: 4), TextButton( onPressed: onOpenSettings, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _RecentPhotoGallery.build:3101 | onPressed | TextButton | onOpenSettings, child: Text(settingsLabel), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _RecentPhotoGallery.build:3126 | onPressed | OutlinedButton | selecting ? null : onGallery, icon: const Icon(Icons.photo_library_outlined, size: 19), label: Text(galleryLabel), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _RecentPhotoGallery.build:3132 | onPressed | OutlinedButton | selecting ? null : onVideo, icon: const Icon(Icons.video_library_outlined, size: 19), label: Text(videoLabel), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _RecentPhotoGallery.build:3150 | onPressed | TextButton | onRetry, child: Text(retryLabel)), ], ), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _RecentPhotoGallery.build:3221 | onTap | InkWell | selecting ? null : () => onPhotoTap(photo), child: Image( image: AssetEntityImageProvider( photo, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PhotoActionCell.build:3274 | onTap | InkWell | enabled ? onPressed : null, child: Center( child: Column( mainAxisSize: MainAxisSize.min, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PhotoActionCell.build:3274 | onPressed | InkWell | null, child: Center( child: Column( mainAxisSize: MainAxisSize.min, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CameraButton.build:3328 | onTap | InkWell | enabled ? onPressed : null, customBorder: const CircleBorder(), child: SizedBox.square( dimension: context.rs(50).clamp(46, 56).toDouble(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CameraButton.build:3328 | onPressed | InkWell | null, customBorder: const CircleBorder(), child: SizedBox.square( dimension: context.rs(50).clamp(46, 56).toDouble(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _VisibilityRow.build:3371 | onTap | InkWell | onTap, child: ConstrainedBox( constraints: const BoxConstraints(minHeight: 70), child: Column( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CategoryRow.build:3460 | onTap | InkWell | onTap, child: ConstrainedBox( constraints: const BoxConstraints(minHeight: 46), child: Row( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/dm_chat_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _DMChatScreenState._buildDmTranslationControl:2404 | onPressed | TextButton | _translationModeReady ? _toggleDmTranslation : null, style: TextButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._buildDmTranslationControl:2458 | onPressed | IconButton | _openDmTranslationLanguageSettings, icon: const Icon(Icons.settings_outlined), color: foreground, iconSize: 15, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._buildDmTranslationControl:2518 | onPressed | IconButton | () => Navigator.pop(context), ), title: Row( children: [ | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._buildDmTranslationControl:2533 | onTap | GestureDetector | _isAnonymous \|\| _isPeerDeleted ? null : () => _openOtherUserProfile( nickname: resolvedName, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _DMChatScreenState._buildDmTranslationControl:2602 | onPressed | IconButton | () => Navigator.pop(context), ), title: Row( children: [ | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._buildDmTranslationControl:2669 | onSelected | PopupMenuButton | (value) { if (value == 'leave') { _confirmLeaveConversation(); } | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._buildDmTranslationControl:2784 | onPressed | IconButton | () => Navigator.pop(context), ), title: Row( children: [ | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._buildDmTranslationControl:2798 | onTap | GestureDetector | _isAnonymous \|\| isCachedDeleted ? null : () => _openOtherUserProfile( nickname: otherUserName, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _DMChatScreenState._buildDmTranslationControl:2959 | onSelected | PopupMenuButton | (value) { if (value == 'block') { _showBlockConfirmation(); } else if (value == 'delete') { | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._confirmLeaveConversation:3067 | onPressed | TextButton | () { HapticFeedback.lightImpact(); Navigator.of(dialogContext).pop(false); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._confirmLeaveConversation:3094 | onPressed | ElevatedButton | () { HapticFeedback.heavyImpact(); Navigator.of(dialogContext).pop(true); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._buildMessageList:3365 | onLongPress | GestureDetector | _canReplyToMessage(message) ? () => _showMessageActions(message) : message.type == 'file' ? () => _showPendingFileActions(message) | bubble .985 (자식 시각 영역만) | custom_applied | 원래 row long press 유지; 자식 bubble만 transform, 전체 행은 정적 |
| _DMChatScreenState.actionSlot:3633 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(14), child: Container( height: 48, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _DMChatScreenState._showPendingFileActions:3901 | onTap | ListTile | () => Navigator.of(sheetContext).pop(true), ), ), ); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._buildOutgoingPresentation:4151 | onTap | InkResponse | !_sendingIds.contains(message.id) ? () => _queueOutgoing(_activeConversationId, message) : null, radius: 20, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _DMChatScreenState._buildReplyQuote:4477 | onTap | InkWell | messageId.isEmpty \|\| unavailable ? null : () => _jumpToMessage(messageId), borderRadius: BorderRadius.circular(9), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._buildFileBubble:4582 | onTap | InkWell | _openingFileIds.contains(message.id) ? null : () => _openDmFile(message), borderRadius: BorderRadius.circular(10), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._buildPostContextCard:4735 | onTap | GestureDetector | postId.isEmpty ? null : () => _navigateToPost(postId), child: Container( decoration: BoxDecoration( color: isMine | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _DMChatScreenState._buildImageBubble:4867 | onTap | GestureDetector | () => _openImageViewer(imageUrl, heroTag: heroTag), child: ClipRRect( borderRadius: BorderRadius.circular(14), child: ConstrainedBox( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _DMChatScreenState._buildImageBubble:4899 | onPressed | TextButton | retry, style: TextButton.styleFrom( foregroundColor: isMine ? Colors.white70 | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _DMChatScreenState._buildComposer:5053 | onTap | InkWell | (peerDeleted \|\| _directInteractionRestricted) ? null : _showAttachmentOptions, customBorder: const CircleBorder(), | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _DMChatScreenState._buildComposer:5137 | onTap | InkWell | canSend ? _sendMessage : null, customBorder: const CircleBorder(), child: AnimatedContainer( duration: MotionTokens.reduceMotion(context) | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _DMChatScreenState._buildComposerReplyPreview:5268 | onPressed | IconButton | () => setState(() => _replyingTo = null), icon: const Icon(Icons.close_rounded, size: 19), color: const Color(0xFF667085), constraints: | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _DMChatScreenState._buildComposerPostContextPreview:5291 | onTap | GestureDetector | postId.isEmpty ? null : () => _navigateToPost(postId), child: Container( padding: const EdgeInsets.all(10), decoration: BoxDecoration( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _DMChatScreenState._buildComposerPostContextPreview:5376 | onTap | InkWell | () { setState(() { _composerPostContextDismissed = true; }); | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _DMChatScreenState._buildAttachmentPreview:5511 | onPressed | IconButton | () { setState(() { _pendingImage = null; _uploadProgress = null; | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._pickImage:5658 | onTap | ListTile | () async { Navigator.pop(context); await _pickImageFrom(ImageSource.gallery); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._pickImage:5670 | onTap | ListTile | () async { Navigator.pop(context); await _pickImageFrom(ImageSource.camera); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._showBlockConfirmation:6172 | onPressed | TextButton | () => Navigator.pop(context, false), child: Text(AppLocalizations.of(context)!.cancel ?? ""), ), TextButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._showBlockConfirmation:6176 | onPressed | TextButton | () => Navigator.pop(context, true), child: Text( AppLocalizations.of(context)!.block, style: const TextStyle(color: Colors.red), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMChatScreenState._buildPostNavigationBanner:6260 | onPressed | TextButton | () => _navigateToPost(_conversation!.postId!), style: TextButton.styleFrom( foregroundColor: DMColors.textPrimary, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/dm_image_send_preview_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| DMImageSendPreviewScreen.build:70 | onPressed | ElevatedButton | () => Navigator.pop(context, true), style: ElevatedButton.styleFrom( backgroundColor: const Color(0xFF4A90E2), foregroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/dm_list_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _DMListScreenState.build:240 | onPressed | FloatingActionButton | _openRecipientSelection, backgroundColor: const Color(0xFF344054), foregroundColor: Colors.white, elevation: 3, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMListScreenState._buildFilterBanners:576 | onTap | InkWell | () { if (_filter != DMFilter.friends) setState(() => _filter = DMFilter.friends); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMListScreenState._buildFilterBanners:600 | onTap | InkWell | () { if (_filter != DMFilter.anonymous) setState(() => _filter = DMFilter.anonymous); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMListScreenState._buildConversationCardContent:835 | onTap | InkWell | () => _openConversation(conversation), child: Container( height: 72, padding: EdgeInsets.symmetric( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DMListScreenState._buildConversationCardContent:864 | onTap | GestureDetector | canOpenProfile ? () => _openUserProfile( userId: otherUserId, nickname: displayName, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/screens/dm_recipient_selection_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _DmRecipientSelectionScreenState.build:269 | onPressed | IconButton | () => Navigator.of(context).maybePop(), icon: const Icon( Icons.arrow_back_ios_new_rounded, size: 20, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DmRecipientSelectionScreenState._buildSearchField:401 | onPressed | IconButton | _isDirectoryTab ? _submitSearch : null, icon: const Icon(Icons.search_rounded, size: 21), color: const Color(0xFF667085), disabledColor: const Color(0xFF667085), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DmRecipientSelectionScreenState._buildSearchField:410 | onPressed | IconButton | _searchController.clear, icon: const Icon(Icons.close_rounded, size: 19), ), filled: true, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _RecipientTile.build:563 | onTap | Semantics | onTap, excludeSemantics: true, child: Material( color: Colors.transparent, | semantics delegation | intentionally_static | 동일 액션의 접근성 위임; 별도 버튼으로 중복 집계하지 않음 |
| _RecipientTile.build:568 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(12), child: Container( decoration: const BoxDecoration( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _RecipientMessage.build:763 | onPressed | TextButton | onAction, style: TextButton.styleFrom( foregroundColor: const Color(0xFF344054), minimumSize: const Size(44, 44), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/edit_meetup_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _EditMeetupScreenState._showExitConfirmationDialog:529 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(false), style: _dialogActionStyle( const Color(0xFF667085), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EditMeetupScreenState._showExitConfirmationDialog:545 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(true), style: _dialogActionStyle( const Color(0xFF344054), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EditMeetupScreenState.build:616 | onPressed | IconButton | _isLoading ? null : () async { final shouldExit = await _showExitConfirmationDialog(); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EditMeetupScreenState._buildTextField:968 | onChanged | DropdownButton | onChanged, ), ), ); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EditMeetupScreenState._buildDateField:976 | onTap | InkWell | _selectDate, child: Container( constraints: BoxConstraints( minHeight: context.rh(48, min: 46, max: 52), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EditMeetupScreenState._buildImagePicker:1023 | onPressed | TextButton | _isLoading ? null : _pickImage, style: TextButton.styleFrom( foregroundColor: const Color(0xFF475467), padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EditMeetupScreenState._buildImagePicker:1076 | onTap | InkWell | _isLoading ? null : _removeImage, customBorder: const CircleBorder(), child: const Padding( padding: EdgeInsets.all(8), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EditMeetupScreenState._buildBottomActionButton:1127 | onTap | InkWell | disabled ? null : onPressed, borderRadius: BorderRadius.circular(12), child: Center( child: isLoading | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/edit_post_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _EditPostScreenState._buildExistingImages:292 | onTap | GestureDetector | _isSubmitting ? null : () => _removeExistingUrl(index), child: Container( padding: const EdgeInsets.all(5), decoration: const BoxDecoration( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _EditPostScreenState._buildNewImages:354 | onTap | GestureDetector | _isSubmitting ? null : () => _removeNewAsset(index), child: Container( padding: const EdgeInsets.all(5), decoration: const BoxDecoration( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _EditPostScreenState.build:387 | onPressed | IconButton | () => Navigator.pop(context), ), title: Text( l10n.editPost, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EditPostScreenState.build:401 | onPressed | TextButton | _canSubmit ? _submit : null, icon: _isSubmitting ? const SizedBox( width: 16, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EditPostScreenState.build:503 | onPressed | OutlinedButton | (_isSubmitting \|\| _isPollLocked) ? null : _selectImages, icon: const Icon(Icons.image_outlined), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/email_id_setup_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _EmailIdSetupScreenState.build:59 | onPressed | IconButton | () => Navigator.pop(context), icon: const Icon( Icons.arrow_back_ios_new_rounded, size: 22, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EmailIdSetupScreenState.build:146 | onPressed | TextButton | () { _emailController.text = widget.verifiedHanyangEmail; }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/email_login_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _EmailLoginScreenState.build:254 | onPressed | IconButton | () => Navigator.pop(context), ), title: Text( l10n.emailLoginTitle, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EmailLoginScreenState.build:404 | onPressed | IconButton | () { setState(() { _obscurePassword = !_obscurePassword; }); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EmailLoginScreenState.build:428 | onPressed | TextButton | _isLoading ? null : _openPasswordReset, style: TextButton.styleFrom( foregroundColor: AppColors.pointColor, padding: EdgeInsets.symmetric( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EmailLoginScreenState.build:489 | onPressed | FilledButton | _isLoading ? null : _handleLogin, style: FilledButton.styleFrom( backgroundColor: AppColors.pointColor, foregroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/email_signup_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _EmailSignUpScreenState.build:150 | onPressed | IconButton | _isLoading ? null : () => Navigator.pop(context), ), title: Text( l10n.emailSignUpTitle, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EmailSignUpScreenState.build:243 | onPressed | IconButton | () => setState( () => _obscurePassword = !_obscurePassword, ), icon: Icon( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EmailSignUpScreenState.build:280 | onPressed | IconButton | () => setState( () => _obscureConfirmPassword = !_obscureConfirmPassword, ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/friend_categories_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _FriendCategoriesScreenState._buildCreateCategoryRow:285 | onTap | InkWell | _handleCreateCategory, child: ListTile( minTileHeight: 76, minLeadingWidth: 40, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendCategoriesScreenState._buildGroupsEmptyState:452 | onPressed | FilledButton | _handleCreateCategory, icon: Icon( Icons.group_add_outlined, size: context.ri(19).clamp(18, 21).toDouble(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendCategoriesScreenState._buildCategoryCard:573 | onSelected | PopupMenuButton | (value) { switch (value) { case 'edit': _showEditCategoryDialog(category); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendCategoriesScreenState._buildCategoryCard:637 | onTap | ListTile | () { // 카테고리 상세 화면으로 이동 (친구 목록 표시) _navigateToCategoryDetail(category); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendCategoriesScreenState._showDeleteConfirmDialog:817 | onPressed | TextButton | () => Navigator.pop(dialogContext), style: TextButton.styleFrom( foregroundColor: const Color(0xFF667085), minimumSize: const Size(0, 44), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendCategoriesScreenState._showDeleteConfirmDialog:846 | onPressed | TextButton | () async { final success = await _categoryService .deleteCategory(category.id); if (!dialogContext.mounted) return; | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/friend_profile_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _FriendProfileScreenState.build:325 | onPressed | IconButton | () => Navigator.pop(context), ), ), backgroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendProfileScreenState._buildProfileLoadError:407 | onPressed | TextButton | _retryProfileLoad, icon: const Icon(Icons.refresh_rounded, size: 19), label: Text((isChineseUi(context) ? '重试' : isKo ? '다시 시도' : 'Retry')), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendProfileScreenState._buildProfileHeader:640 | onTap | GestureDetector | photoURL != null && photoURL.isNotEmpty ? () => _openProfileImageViewer(photoURL) : null, child: Hero( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _FriendProfileScreenState._buildProfileHeader:814 | onTap | InkWell | _navigateToFriendsList, borderRadius: BorderRadius.circular(8), child: _buildStatItemContent( AppLocalizations.of(context)!.friends, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendProfileScreenState._buildProfileHeader:848 | onPressed | ElevatedButton | (!canRequest \|\| _isRequestingFriend) ? null : _sendFriendRequestFromProfile, icon: _isRequestingFriend | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _FriendProfileScreenState._buildProfileHeader:894 | onPressed | ElevatedButton | _openDM, icon: const Icon(Icons.message, size: 20), label: Text( AppLocalizations.of(context)!.sendMessage, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _FriendProfileScreenState.tags:966 | onTap | InkWell | () => _openSocialTagPeople(id, kind), borderRadius: BorderRadius.circular(8), child: Padding( padding: const EdgeInsets.symmetric( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendProfileScreenState._buildFriendPreviewSection:1138 | onPressed | TextButton | _navigateToFriendsList, style: TextButton.styleFrom( foregroundColor: const Color(0xFF475569), padding: const EdgeInsets.symmetric(horizontal: 4), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendProfileScreenState._buildFriendPreviewMember:1206 | onTap | InkWell | () => _openFriendFromPreview(profile), borderRadius: BorderRadius.circular(10), child: SizedBox( width: 62, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendProfileScreenState._buildReviewPreviewItem:1328 | onTap | InkWell | () => Navigator.push( context, MaterialPageRoute(builder: (_) => ReviewDetailScreen(review: review)), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendProfileScreenState._buildReviewGridItem:1598 | onTap | GestureDetector | () { // 후기 상세 화면으로 이동 (댓글, 좋아요 기능 포함) Navigator.push( context, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/screens/friends_main_page.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _FriendsMainPageState.build:244 | onPressed | AppFab | () { // 검색 탭으로 포커스 이동 또는 검색 기능 실행 _tabController.animateTo(1); }, | AppFab | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/screens/friends_page.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _FriendsPageState._showConfirmDialog:512 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(false), style: TextButton.styleFrom( minimumSize: const Size(0, 48), foregroundColor: const Color(0xFF667085), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState._showConfirmDialog:537 | onPressed | ElevatedButton | () => Navigator.of(dialogContext).pop(true), style: ElevatedButton.styleFrom( minimumSize: const Size(0, 48), backgroundColor: const Color(0xFFD92D20), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState._showGroupSelectionDialog:764 | onPressed | IconButton | () => Navigator.pop(sheetContext), icon: const Icon( Icons.close_rounded, color: Color(0xFF667085), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState._showGroupSelectionDialog:799 | onPressed | TextButton | () { Navigator.pop(sheetContext); _openCreateGroup(); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState._showGroupSelectionDialog:828 | onTap | InkWell | () { setState(() { checked ? selected.remove(category.id) | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState._showGroupSelectionDialog:844 | onChanged | Checkbox | (value) { setState(() { value == true ? selected | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState._showGroupSelectionDialog:920 | onPressed | TextButton | () => Navigator.pop(sheetContext), style: TextButton.styleFrom( foregroundColor: const Color(0xFF667085), minimumSize: const Size(80, 44), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState._showGroupSelectionDialog:930 | onPressed | FilledButton | () async { Navigator.pop(sheetContext); await _applyCategorySelection( friend, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState._buildGroupBadges:1087 | onTap | InkWell | () => _showAllCategoriesSheet(categories), child: _OverflowBadge(label: '+$remaining'), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState.build:1141 | onTap | GestureDetector | () { // 빈 공간 터치시 키보드 닫기 FocusScope.of(context).unfocus(); }, | staticGesture | intentionally_static | 기존 scroll·zoom·입력 해제·재생 gesture 보존 |
| _FriendsPageState._buildSearchBar:1248 | onPressed | IconButton | () { _searchController.clear(); _onSearchChanged(''); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState._buildSearchBar:1270 | onChanged | TextField | _onSearchChanged, textInputAction: TextInputAction.search, ), ), | input / text | intentionally_static | IME·선택·링크의 입력 State를 모션으로 재생성하지 않음 |
| _FriendsPageState._buildTagFriendFinderShortcut:1298 | onTap | InkWell | _openTagFriendFinder, child: Center( child: ConstrainedBox( constraints: const BoxConstraints(maxWidth: 720), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState._buildFriendRequestsShortcut:1361 | onTap | InkWell | () { Navigator.push( context, MaterialPageRoute(builder: (_) => const RequestsPage()), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState._buildCreateGroupShortcut:1453 | onTap | InkWell | _openCreateGroup, child: Center( child: ConstrainedBox( constraints: const BoxConstraints(maxWidth: 720), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState._buildFriendsList:1536 | onTap | InkWell | () => _navigateToProfile(friend), onLongPress: () => _showFriendOptions(friend), child: Padding( padding: EdgeInsets.fromLTRB( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState._buildFriendsList:1537 | onLongPress | InkWell | () => _showFriendOptions(friend), child: Padding( padding: EdgeInsets.fromLTRB( horizontalPadding, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState._buildFriendsList:1665 | onPressed | IconButton | () => _showFriendOptions(friend), ), ], ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FriendsPageState._buildErrorState:1731 | onPressed | TextButton | () { final provider = context.read<RelationshipProvider>(); provider.clearError(); final query = _searchController.text.trim(); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ActionTile.build:1844 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(12), child: Padding( padding: const EdgeInsets.symmetric(vertical: 5), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/hanyang_email_verification_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _HanyangEmailVerificationScreenState.build:400 | onPressed | IconButton | _isLoading ? null : _leaveSignup, ), title: Text( _isProfileVerification | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _HanyangEmailVerificationScreenState.build:596 | onPressed | TextButton | _isLoading ? null : () { setState(() { | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/home_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| MeetupHomePageState._buildCalendarHeader:940 | onTap | InkWell | () { setState(() { _isCalendarExpanded = !_isCalendarExpanded; }); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| MeetupHomePageState._buildCalendarHeader:995 | onPressed | TextButton | _navigateToAllMeetups, style: TextButton.styleFrom( foregroundColor: const Color(0xFF475467), minimumSize: const Size(44, 44), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| MeetupHomePageState.build:1435 | onPressed | AppFab | _navigateToCreateMeetup, heroTag: 'meetup_home_create_fab', ), ), | AppFab | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _AllMeetupsScreenState._buildMeetupSkeleton:1583 | onPressed | IconButton | () => Navigator.pop(context), icon: const Icon( Icons.arrow_back_rounded, color: Color(0xFF111827), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AllMeetupsScreenState.build:1739 | onPressed | AppFab | widget.onCreateMeetup, heroTag: 'all_meetups_create_fab', ), ), | AppFab | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _CategoryTabItem.build:1853 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(4), child: AnimatedContainer( height: height, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/licenses_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| LicensesScreen.build:21 | onPressed | IconButton | () => Navigator.pop(context), ), title: Text( AppLocalizations.of(context)!.openSourceLicenses ?? "오픈소스 라이선스", | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| LicensesScreen._buildLicenseItem:148 | onTap | InkWell | () { Navigator.push( context, MaterialPageRoute( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| LicenseDetailScreen.build:265 | onPressed | IconButton | () => Navigator.pop(context), ), title: Text( packageName, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/login_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _LoginScreenState._showRegistrationRequiredDialog:129 | onPressed | IconButton | () => Navigator.of(dialogContext).pop(false), tooltip: l10n.close, visualDensity: VisualDensity.compact, icon: const Icon( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _LoginScreenState._showRegistrationRequiredDialog:175 | onPressed | AppButton | () => Navigator.of(dialogContext).pop(true), variant: AppButtonVariant.text, ), ], | AppButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _LoginScreenState._handleAppleLogin:765 | onPressed | TextButton | () => Navigator.pop(dialogContext), child: Text(AppLocalizations.of(context)!.confirm, style: TextStyle(fontSize: 16)), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _LoginMethodButton.build:864 | onPressed | FilledButton | onPressed, style: FilledButton.styleFrom( elevation: 0, shadowColor: Colors.transparent, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _LoginLanguageChoice.build:1002 | onTap | InkResponse | onTap, radius: 28, child: ConstrainedBox( constraints: BoxConstraints( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/main_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _MainScreenState._buildAppBarTitle:334 | onTap | GestureDetector | () { Navigator.push( context, MaterialPageRoute(builder: (context) => const AdShowcaseScreen()), | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _MainScreenState._buildAppBarTitle:372 | onPressed | AppIconButton | _navigateToSearchPage, semanticLabel: AppLocalizations.of(context)!.search, visualDensity: VisualDensity.compact, ), | AppIconButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _MainScreenState._buildAppBarTitle:382 | onPressed | AppIconButton | () => MyPageSettingsSheet.show(context), semanticLabel: AppLocalizations.of(context)!.settings, visualDensity: VisualDensity.compact, ), | AppIconButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _MainScreenState._buildAppBarTitle:396 | onPressed | AppIconButton | () { Navigator.push( context, MaterialPageRoute( | AppIconButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/screens/meetup_category_select_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _MeetupCategorySelectScreenState._buildCategoryChip:108 | onTap | InkWell | () { if (_selectedCategoryKey == key) return; setState(() { _selectedCategoryKey = key; | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupCategorySelectScreenState._buildPlaceItem:221 | onTap | InkWell | _selectedCategoryKey == null ? null : () { // 추천 장소를 누르면: 선택된 카테고리 + URL을 함께 반환해서 | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupCategorySelectScreenState.build:344 | onPressed | IconButton | () => Navigator.of(context).pop(), ), title: MediaQuery.withClampedTextScaling( maxScaleFactor: 1.2, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupCategorySelectScreenState.build:422 | onPressed | ElevatedButton | _selectedCategoryKey == null ? null : () => Navigator.of(context).pop( MeetupCategorySelectionResult( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/meetup_detail_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _MeetupDetailScreenState.build:579 | onPressed | IconButton | () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF111827)), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._buildAudienceMember:1140 | onTap | InkWell | () => _openAudienceMemberProfile(member), borderRadius: BorderRadius.circular(10), child: SizedBox( width: itemWidth, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._buildPrettyLinkText:1291 | onTap | GestureDetector | () => _openExternalLink(e.url), child: Text( e is UrlElement ? _displayUrlLabel(e.url) : e.text, style: linkStyle, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _MeetupDetailScreenState._buildMeetupImage:1522 | onTap | GestureDetector | () { showFullscreenImageViewer( context, imageUrls: gallery, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _MeetupDetailScreenState._buildMeetupImage:1584 | onTap | GestureDetector | () { showFullscreenImageViewer( context, imageUrls: gallery, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _MeetupDetailScreenState._buildHeaderButtonsContent:1746 | onPressed | IconButton | () => _showEditMeetup(), icon: const Icon( Icons.edit_outlined, size: DesignTokens.icon, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._buildHeaderButtonsContent:1843 | onSelected | PopupMenuButton | (value) => _handleUserMenuAction(value), );  return kebab; | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._confirmMeetup:2083 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(false), child: Text((isChineseUi(context) ? '暂不开启' : isKo | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._confirmMeetup:2091 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(true), style: TextButton.styleFrom( foregroundColor: const Color(0xFF111827), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._buildBottomButton:2298 | onPressed | TextButton | busy \|\| !enabled ? null : onPressed, style: TextButton.styleFrom( foregroundColor: foreground, shape: RoundedRectangleBorder( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _MeetupDetailScreenState._buildBottomButton:2313 | onPressed | FilledButton | busy \|\| !enabled ? null : onPressed, style: FilledButton.styleFrom( backgroundColor: const Color(0xFF111827), foregroundColor: foreground, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _MeetupDetailScreenState._buildHostActionButton:2625 | onPressed | ElevatedButton | _isLoading ? null : () { if (canComplete) { | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._buildHostActionButton:2660 | onPressed | ElevatedButton | _isLoading ? null : () => _navigateToCreateReview(), style: ElevatedButton.styleFrom( backgroundColor: Colors.blue, foregroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._buildHostActionButton:2684 | onPressed | ElevatedButton | _isLoading ? null : () => _navigateToEditReview(), style: ElevatedButton.styleFrom( backgroundColor: Colors.blue, foregroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._buildParticipantActionButton:2699 | onPressed | ElevatedButton | _isLoading ? null : () => _navigateToReviewApproval(), style: ElevatedButton.styleFrom( backgroundColor: Colors.green, foregroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._showReviewApprovalDialog:3094 | onPressed | OutlinedButton | () async { Navigator.pop(context); await _handleReviewResponse(requestId, false); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._showReviewApprovalDialog:3117 | onPressed | ElevatedButton | () async { Navigator.pop(context); await _handleReviewResponse(requestId, true); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._showReviewApprovalDialog:3142 | onPressed | ElevatedButton | () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.close ?? ""), style: ElevatedButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._showCompleteMeetupDialog:3278 | onPressed | ElevatedButton | () async { Navigator.pop(context); await _markMeetupAsCompleted(); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._showCompleteMeetupDialog:3315 | onPressed | OutlinedButton | () { Navigator.pop(context); _showCancelConfirmation(); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._showCompleteMeetupDialog:3354 | onPressed | TextButton | () => Navigator.pop(context), style: TextButton.styleFrom( foregroundColor: Colors.grey[600], shape: RoundedRectangleBorder( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._showDeleteReviewConfirmation:3513 | onPressed | TextButton | () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel ?? ""), ), ElevatedButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._showDeleteReviewConfirmation:3517 | onPressed | ElevatedButton | () async { Navigator.pop(context); await _deleteReview(); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._showCancelConfirmation:3702 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(false), style: TextButton.styleFrom( foregroundColor: const Color(0xFF667085), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._showCancelConfirmation:3724 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(true), style: TextButton.styleFrom( foregroundColor: const Color(0xFFB42318), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._buildSimpleParticipantItemContent:3978 | onTap | InkWell | canOpenProfile ? () => _openParticipantProfile(participant) : null, onLongPress: canKick ? () => _showKickActionSheet(participant) : null, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._buildSimpleParticipantItemContent:3981 | onLongPress | InkWell | canKick ? () => _showKickActionSheet(participant) : null, borderRadius: BorderRadius.circular(12), child: Row( children: [ | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._showKickActionSheet:4129 | onTap | ListTile | () => Navigator.pop(context, 'kick'), ), const SizedBox(height: 8), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._showKickActionSheet:4158 | onPressed | TextButton | () => Navigator.pop(context, false), child: Text((isChineseUi(context) ? '取消' : isKo | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupDetailScreenState._showKickActionSheet:4166 | onPressed | TextButton | () => Navigator.pop(context, true), child: Text( (isChineseUi(context) ? '移除' | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/meetup_favorite_editor_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _MeetupFavoriteEditorScreenState._selectTime:211 | onTap | ListTile | () => Navigator.of(sheetContext).pop('undecided'), ), ListTile( leading: const Icon(Icons.access_time_rounded, size: 21), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupFavoriteEditorScreenState._selectTime:224 | onTap | ListTile | () => Navigator.of(sheetContext).pop('pick'), ), ], ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupFavoriteEditorScreenState._visibilityOption:400 | onTap | InkWell | onTap, child: Container( constraints: const BoxConstraints(minHeight: 46), alignment: Alignment.center, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupFavoriteEditorScreenState._selectionRow:438 | onTap | InkWell | onTap, child: Container( constraints: const BoxConstraints(minHeight: 50), decoration: const BoxDecoration( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupFavoriteEditorScreenState.build:534 | onPressed | IconButton | () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded), color: const Color(0xFF111827), iconSize: 22, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupFavoriteEditorScreenState.build:659 | onTap | InkWell | _pickThumbnail, child: Container( constraints: const BoxConstraints(minHeight: 58), decoration: const BoxDecoration( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupFavoriteEditorScreenState.build:719 | onPressed | ElevatedButton | _isSaving ? null : _save, style: ElevatedButton.styleFrom( elevation: 0, backgroundColor: const Color(0xFF344054), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/meetup_favorites_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _MeetupFavoritesScreenState._confirmDelete:184 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(false), style: TextButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupFavoritesScreenState._confirmDelete:203 | onPressed | ElevatedButton | () => Navigator.of(dialogContext).pop(true), style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 12), backgroundColor: const Color(0xFFEF4444), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupFavoritesScreenState.build:251 | onPressed | IconButton | () => Navigator.of(context).pop(), ), title: Text( (isChineseUi(context) ? '收藏' : isKo ? '즐겨찾기' : 'Favorites'), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupFavoritesScreenState.build:278 | onTap | InkWell | () => _openEditor(), child: Container( constraints: const BoxConstraints(minHeight: 64), decoration: const BoxDecoration( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TemplateCard.build:427 | onTap | InkWell | onTap, child: Container( constraints: const BoxConstraints(minHeight: 74), padding: const EdgeInsets.symmetric(vertical: 12), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TemplateCard.build:483 | onSelected | PopupMenuButton | (value) { if (value == 'edit') onEdit(); if (value == 'delete') onDelete(); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TemplateNameDialogState.build:666 | onPressed | TextButton | () => Navigator.of(context).pop(), style: TextButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TemplateNameDialogState.build:685 | onPressed | ElevatedButton | !canSave ? null : () => Navigator.of(context).pop(value.text.trim()), style: ElevatedButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/meetup_participants_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _MeetupParticipantsScreenState._buildParticipantCard:272 | onTap | InkWell | participant.hasViewableProfile ? () => _openParticipantProfile(participant) : null, borderRadius: BorderRadius.circular(10), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupParticipantsScreenState._buildParticipantCard:407 | onPressed | ElevatedButton | () => _approveParticipant(participant), icon: const Icon(Icons.check, size: 16), label: const Text('승인'), style: ElevatedButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupParticipantsScreenState._buildParticipantCard:419 | onPressed | ElevatedButton | () => _rejectParticipant(participant), icon: const Icon(Icons.close, size: 16), label: const Text('거절'), style: ElevatedButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupParticipantsScreenState._buildParticipantCard:435 | onPressed | ElevatedButton | () => _removeParticipant(participant), icon: const Icon(Icons.person_remove, size: 16), label: const Text('참여 취소'), style: ElevatedButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupParticipantsScreenState._removeParticipant:514 | onPressed | TextButton | () => Navigator.pop(context, false), child: const Text('취소'), ), ElevatedButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupParticipantsScreenState._removeParticipant:518 | onPressed | ElevatedButton | () => Navigator.pop(context, true), style: ElevatedButton.styleFrom( backgroundColor: Colors.red, foregroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/meetup_search_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _MeetupSearchScreenState.build:130 | onPressed | IconButton | () => Navigator.pop(context), ), title: Text( (isChineseUi(context) ? '搜索动态' : Localizations.localeOf(context).languageCode == 'ko' | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupSearchScreenState.build:177 | onChanged | TextField | (_) { // 명시적 검색 버튼을 누르기 전에는 이전 검색어의 // 결과가 현재 입력의 결과처럼 보이지 않게 한다. _searchRequestGuard.invalidate(); | input / text | intentionally_static | IME·선택·링크의 입력 State를 모션으로 재생성하지 않음 |
| _MeetupSearchScreenState.build:196 | onPressed | IconButton | () { _searchRequestGuard.invalidate(); _searchController.clear(); setState(() { | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupSearchScreenState.build:209 | onPressed | IconButton | _performSearch, ), ], ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/meetup_visibility_group_select_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _MeetupVisibilityGroupSelectScreenState._buildGroupItem:120 | onTap | InkWell | () => _toggleSelection(category.id), child: ConstrainedBox( constraints: const BoxConstraints(minHeight: 48), child: Padding( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupVisibilityGroupSelectScreenState.build:206 | onPressed | IconButton | () => Navigator.of(context).pop(), ), title: MediaQuery.withClampedTextScaling( maxScaleFactor: 1.2, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MeetupVisibilityGroupSelectScreenState.build:299 | onPressed | ElevatedButton | widget.categories.isEmpty ? null : () { Navigator.of(context).pop(_selectedCategoryIds); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/mypage_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _MyPageScreenState._buildProfileHeader:419 | onTap | GestureDetector | photoUrl.isNotEmpty ? () => _openProfileImageViewer(photoUrl) : null, child: Hero( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _MyPageScreenState._buildProfileHeader:588 | onTap | InkWell | () async { await Navigator.push( context, MaterialPageRoute( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MyPageScreenState._socialTagLabel:711 | onTap | InkWell | () => _openSocialTagPeople(tagId, kind), borderRadius: BorderRadius.circular(8), child: Padding( padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MyPageScreenState._buildReviewGrid:866 | onTap | GestureDetector | () => _openReviewDetail(review), onLongPress: () => _showReviewOptions(review), child: Container( color: AppTheme.backgroundSecondary, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _MyPageScreenState._buildReviewGrid:867 | onLongPress | GestureDetector | () => _showReviewOptions(review), child: Container( color: AppTheme.backgroundSecondary, child: Stack( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _MyPageScreenState._buildPostCollectionControls:1163 | onPressed | TextButton | _navigateToSavedPosts, style: TextButton.styleFrom( foregroundColor: const Color(0xFF6B7280), padding: const EdgeInsets.symmetric( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MyPageScreenState._buildPostCollectionControls:1190 | onPressed | IconButton | () => setState(() => _showPostsAsGrid = true), iconSize: 19, padding: const EdgeInsets.all(6), constraints: const BoxConstraints.tightFor(width: 36, height: 36), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MyPageScreenState._buildPostCollectionControls:1204 | onPressed | IconButton | () => setState(() => _showPostsAsGrid = false), iconSize: 19, padding: const EdgeInsets.all(6), constraints: const BoxConstraints.tightFor(width: 36, height: 36), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MyPageScreenState._buildBorderlessPostRow:1250 | onTap | InkWell | () => _openPostDetail(post.id), child: Padding( padding: EdgeInsets.symmetric(vertical: metrics.verticalPadding), child: Row( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MyPageScreenState._buildBorderlessPostGrid:1392 | onTap | InkWell | () => _openPostDetail(post.id), child: _buildPostThumbnail(post), ), ); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MyPageScreenState._buildStatItem:1587 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(12), child: Container( padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MyPageScreenState._toggleReviewHidden:1733 | onPressed | TextButton | () => Navigator.pop(context, false), child: Text(l10n?.cancel ?? ""), ), TextButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MyPageScreenState._toggleReviewHidden:1737 | onPressed | TextButton | () => Navigator.pop(context, true), child: Text(l10n?.confirm ?? ""), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MyPageScreenState._deleteReview:1804 | onPressed | TextButton | () => Navigator.pop(context, false), child: Text(l10n?.cancel ?? ""), ), TextButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MyPageScreenState._deleteReview:1808 | onPressed | TextButton | () => Navigator.pop(context, true), style: TextButton.styleFrom( foregroundColor: BrandColors.error, ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MyPageScreenState._buildMenuItem:1965 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(12), child: Padding( padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MyPageScreenState._navigateToFriendsPage:2010 | onPressed | IconButton | () => Navigator.maybePop(context), icon: const Icon(Icons.arrow_back_rounded), iconSize: 22, tooltip: MaterialLocalizations.of(context).backButtonTooltip, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| MyPageSettingsSheet._showLogoutConfirmDialog:2205 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(12), child: Padding( padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/nickname_setup_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _NicknameSetupScreenState._showImageOptions:188 | onTap | ListTile | () { Navigator.pop(sheetContext); _pickImage(ImageSource.gallery); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _NicknameSetupScreenState._showImageOptions:196 | onTap | ListTile | () { Navigator.pop(sheetContext); _pickImage(ImageSource.camera); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _NicknameSetupScreenState._showImageOptions:205 | onTap | ListTile | () { Navigator.pop(sheetContext); setState(() => _selectedImage = null); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _NicknameSetupScreenState.build:628 | onPressed | IconButton | _leaveSignup, tooltip: MaterialLocalizations.of(context).backButtonTooltip, icon: Icon( Icons.arrow_back_rounded, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _NicknameSetupScreenState.build:637 | onPressed | IconButton | () => _moveTo(_currentStep - 1), tooltip: MaterialLocalizations.of(context).backButtonTooltip, icon: Icon( Icons.arrow_back_rounded, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _NicknameSetupScreenState.build:719 | onPressed | ElevatedButton | _isLoading ? null : _primaryAction, style: ElevatedButton.styleFrom( elevation: 0, backgroundColor: AppColors.pointColor, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _NicknameSetupScreenState._basicProfileStep:836 | onPressed | TextButton | _isCheckingNickname \|\| _isLoading \|\| _isComposingNickname ? null : () { _nicknameDebounce?.cancel(); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _NicknameSetupScreenState._basicProfileStep:874 | onTap | InkWell | () async { FocusScope.of(context).unfocus(); final selected = await _showNationalityPicker(); if (!mounted \|\| selected == null) return; | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _NicknameSetupScreenState._showNationalityPicker:1000 | onTap | InkWell | () => Navigator.pop(sheetContext, country.korean), child: Padding( padding: const EdgeInsets.symmetric(horizontal: 20), child: Row( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _NicknameSetupScreenState._profilePhotoPicker:1049 | onTap | InkWell | _showImageOptions, borderRadius: BorderRadius.circular(8), child: Padding( padding: const EdgeInsets.symmetric(vertical: 4), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/notification_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _NotificationScreenState.build:985 | onPressed | IconButton | () => Navigator.pop(context), ), actions: [ if (_isLoading) | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/notification_settings_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _NotificationSettingsScreenState.build:87 | onPressed | IconButton | () => Navigator.pop(context), ), title: Text( AppLocalizations.of(context)!.notificationSettings ?? "", | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _NotificationSettingsScreenState._buildMainToggleSection:214 | onChanged | Switch | (value) async { if (!value) { // 전체 알림 끄기 확인 final confirmed = await _showDisableAllConfirmDialog(); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _NotificationSettingsScreenState._showDisableAllConfirmDialog:283 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(false), child: Text( AppLocalizations.of(context)!.cancel, style: TextStyle( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _NotificationSettingsScreenState._showDisableAllConfirmDialog:294 | onPressed | ElevatedButton | () => Navigator.of(dialogContext).pop(true), style: ElevatedButton.styleFrom( backgroundColor: const Color(0xFFB91C1C), foregroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _NotificationSettingsScreenState._buildSettingItem:401 | onChanged | Switch |  disabled ? null : (value) { | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/organization_home_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _OrganizationHomeScreenState.build:62 | onPressed | IconButton | context.read<AuthProvider>().signOut, icon: const Icon(Icons.logout_rounded, size: 21), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationProfileBody.build:157 | onChanged | DropdownButton | (value) { if (value != null) onSelected(value); }, ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationProfileBody.build:277 | onPressed | OutlinedButton | () async { final updated = await Navigator.of(context).push<bool>( MaterialPageRoute<bool>( builder: (_) => OrganizationProfileEditScreen( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _Status.build:367 | onPressed | TextButton | onAction, child: Text(action)), ], ), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/organization_invite_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _OrganizationInviteScreenState._accept:63 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(false), child: Text(_copy('취소', 'Cancel', '取消')), ), FilledButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationInviteScreenState._accept:67 | onPressed | FilledButton | () => Navigator.of(dialogContext).pop(true), child: Text(_copy('연결', 'Link', '关联')), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationInviteScreenState._showEmailLogin:222 | onPressed | IconButton | () => setSheetState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationInviteScreenState._showEmailLogin:231 | onPressed | FilledButton | () async { if (email.text.trim().isEmpty \|\| password.text.isEmpty) { return; } | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationInviteScreenState._showEmailLogin:263 | onPressed | TextButton | () async { try { await OrganizationAccountService.instance .sendPasswordSetupEmail(); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationInviteScreenState.build:338 | onPressed | IconButton | _dismissInviteSafely, icon: const Icon(Icons.close_rounded), ), ) | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationInviteScreenState.build:369 | onPressed | TextButton | service.retryInvitation, child: Text(_copy('다시 시도', 'Retry', '重试')), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationInviteScreenState.build:393 | onPressed | IconButton | _authInFlight ? null : _dismissInviteSafely, icon: const Icon(Icons.close_rounded), ), title: Text( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationInviteScreenState.build:495 | onPressed | FilledButton | _authInFlight ? null : _finishInvitation, style: FilledButton.styleFrom( backgroundColor: AppColors.pointColor, minimumSize: const Size.fromHeight(50), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationInviteScreenState.build:512 | onPressed | FilledButton | _authInFlight ? null : _accept, style: FilledButton.styleFrom( backgroundColor: AppColors.pointColor, minimumSize: const Size.fromHeight(50), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationInviteScreenState.build:533 | onPressed | TextButton | _authInFlight ? null : _dismissInviteSafely, child: Text(_copy('나중에', 'Later', '稍后处理')), ), ] else if (signedIn) ...[ | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationInviteScreenState.build:538 | onPressed | FilledButton | _authInFlight ? null : _accept, style: FilledButton.styleFrom( backgroundColor: AppColors.pointColor, minimumSize: const Size.fromHeight(50), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationInviteScreenState.build:556 | onPressed | TextButton | _authInFlight ? null : _useDifferentAccount, child: Text(_copy( '다른 로그인 계정 사용', 'Use a different login account', | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ProviderButton.build:613 | onPressed | OutlinedButton | onPressed, icon: Icon(icon, size: 22), label: Text(label), style: OutlinedButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/organization_profile_edit_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _OrganizationProfileEditScreenState.build:188 | onPressed | TextButton | _saving ? null : _save, child: Text(_copy('저장', 'Save', '保存')), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationProfileEditScreenState.build:208 | onPressed | OutlinedButton |  _uploading ? null : () => _pickImage(cover: false), icon: const Icon(Icons.account_circle_outlined, size: 20), label: Text(_copy('로고', 'Logo', '标志')), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationProfileEditScreenState.build:217 | onPressed | OutlinedButton |  _uploading ? null : () => _pickImage(cover: true), icon: const Icon(Icons.image_outlined, size: 20), label: Text(_copy('커버', 'Cover', '封面')), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationProfileEditScreenState.build:274 | onPressed | FilledButton | _saving \|\| _uploading ? null : _save, style: FilledButton.styleFrom( backgroundColor: AppColors.pointColor, minimumSize: const Size.fromHeight(50), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/organization_profile_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| OrganizationProfileScreen.build:212 | onPressed | TextButton | () => _contact(organization.publicContact), icon: const Icon(Icons.mail_outline_rounded, size: 18), label: Text(_copy(context, '문의', 'Contact', '咨询')), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| OrganizationProfileScreen.build:218 | onPressed | TextButton | () => _open(organization.websiteUrl), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: Text( _copy(context, '웹사이트', 'Website', '网站'), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OrganizationFollowButton.build:251 | onPressed | OutlinedButton | () async { if (following) { await reference.delete(); } else { | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/password_reset_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _PasswordResetScreenState.build:227 | onPressed | IconButton | _isLoading ? null : () => Navigator.pop(context), ), title: Text( l10n.resetPassword, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PasswordResetScreenState._buildForm:320 | onPressed | TextButton | _resendSeconds == 0 && !_isLoading ? _sendCode : null, style: TextButton.styleFrom( foregroundColor: AppColors.pointColor, padding: const EdgeInsets.symmetric(horizontal: 0, vertic | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PasswordResetScreenState._buildForm:345 | onPressed | IconButton | () { setState(() => _obscurePassword = !_obscurePassword); }, icon: Icon( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PasswordResetScreenState._buildForm:376 | onPressed | IconButton | () { setState(() { _obscureConfirmPassword = !_obscureConfirmPassword; }); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/password_setup_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _PasswordSetupScreenState.build:184 | onPressed | IconButton | _isLoading ? null : _leaveSignup, icon: const Icon( Icons.arrow_back_ios_new_rounded, size: 22, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PasswordSetupScreenState.build:255 | onPressed | IconButton | () => setState( () => _obscurePassword = !_obscurePassword, ), icon: Icon( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PasswordSetupScreenState.build:290 | onPressed | IconButton | () => setState( () => _obscureConfirmPassword = !_obscureConfirmPassword, ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/post_category_feed_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _PostCategoryFeedScreenState.build:280 | onPressed | FloatingActionButton | _openCreatePost, backgroundColor: AppColors.pointColor, foregroundColor: Colors.white, child: const Icon(Icons.add_rounded), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostCategoryFeedScreenState.build:335 | onPressed | TextButton | () => _loadInitial(forceRefresh: true), icon: const Icon(Icons.refresh_rounded), label: Text(l10n.retryAction), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostCategoryFeedScreenState.build:370 | onPressed | FilledButton | _openCreatePost, child: Text(l10n.postCategoryCreateAction), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/post_detail_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _PostDetailScreenState._blockPostAuthor:611 | onPressed | TextButton | () => Navigator.of(context).pop(false), child: Text((isChineseUi(context) ? '取消' : isKo | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState._blockPostAuthor:619 | onPressed | ElevatedButton | () => Navigator.of(context).pop(true), child: Text((isChineseUi(context) ? '屏蔽' : isKo | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState._showPostLikesSheet:1090 | onTap | ListTile | u.isDeletedAccount ? null : () { Navigator.pop(context); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState._buildAudienceAvatarItem:1456 | onTap | GestureDetector | () => _openUserProfile( userId: user.uid, nickname: user.nickname, photoURL: user.photoURL, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _PostDetailScreenState._buildAudienceSection:1518 | onTap | InkWell | () { setState(() { _audienceExpanded = !_audienceExpanded; if (_audienceExpanded) { | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState._openPostActionsSheet:1742 | onTap | ListTile | () async { Navigator.pop(context); await _openEditPost(); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState._openPostActionsSheet:1767 | onTap | ListTile | () async { Navigator.pop(context); await _openDMFromDetail(); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState._openPostActionsSheet:1789 | onTap | ListTile | () async { Navigator.pop(context); await _openReportPostDialog(); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState._openPostActionsSheet:1809 | onTap | ListTile | () async { Navigator.pop(context); await _blockPostAuthor(); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState._openPostActionsSheet:1829 | onTap | ListTile | _isDeleting ? null : () { Navigator.pop(context); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState._deletePost:2021 | onPressed | TextButton | () => Navigator.of(sheetContext).pop(false), style: TextButton.styleFrom( foregroundColor: const Color(0xFF667085), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState._deletePost:2046 | onPressed | TextButton | () => Navigator.of(sheetContext).pop(true), style: TextButton.styleFrom( foregroundColor: const Color(0xFFD92D20), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState._buildRetryableImage:2599 | onPressed | ElevatedButton | () { CachedNetworkImage.evictFromCache( imageUrl, cacheManager: AppImageCacheManager.instance, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState._buildEditorialPostContent:2722 | onTap | GestureDetector | () { showFullscreenImageViewer( context, imageUrls: standaloneImageUrls, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _PostDetailScreenState._buildEditorialAuthorBlock:2889 | onTap | GestureDetector | canOpenProfile ? _openAuthorProfile : null, child: SizedBox.square( dimension: avatarSize, child: Center( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _PostDetailScreenState._buildEditorialAuthorBlock:2926 | onTap | GestureDetector | canOpenProfile ? _openAuthorProfile : null, child: Text( authorName, maxLines: 1, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _PostDetailScreenState.build:3031 | onPressed | IconButton | () => Navigator.pop(context), ), title: const SizedBox.shrink(), centerTitle: false, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState.build:3051 | onPressed | IconButton | () => Navigator.pop(context), ), title: const SizedBox.shrink(), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState.build:3080 | onPressed | IconButton | () => Navigator.pop(context), ), title: const SizedBox.shrink(), centerTitle: false, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState.build:3094 | onPressed | IconButton | _openPostActionsSheet, icon: const Icon( Icons.more_vert_rounded, size: 22, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState.buildCommentWidget:3345 | onTap | GestureDetector | _exitReplyMode, child: Container( padding: const EdgeInsets.all(4), child: Icon(Icons.close, size: 18, color: Colors.grey[600]), | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _PostDetailScreenState.buildCommentWidget:3368 | onPressed | IconButton | _isSubmittingComment ? null : () => setState(() { _commentGif = null; _commentGifId = null; _commentGifInputGeneration++; | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostDetailScreenState.buildCommentWidget:3472 | onTap | InkWell | _submitComment, customBorder: const CircleBorder(), child: Container( width: 36, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/privacy_policy_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| PrivacyPolicyScreen.build:22 | onPressed | IconButton | () => Navigator.pop(context), ), title: Text( AppLocalizations.of(context)!.privacyPolicy ?? "", | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/profile_edit_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _ProfileEditScreenState._confirmDiscardChanges:139 | onPressed | TextButton | () => Navigator.pop(dialogContext, false), child: Text((isChineseUi(context) ? '继续编辑' : isKorean ? '계속 수정' : 'Keep editing')), ), TextButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ProfileEditScreenState._confirmDiscardChanges:143 | onPressed | TextButton | () => Navigator.pop(dialogContext, true), child: Text( (isChineseUi(context) ? '放弃修改' : isKorean ? '저장 안 함' : 'Discard'), style: const TextStyle(color: Color(0xFFDC2626)), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ProfileEditScreenState._showImagePickerOptions:445 | onTap | ListTile | () { Navigator.pop(context); _selectImage(); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ProfileEditScreenState._showImagePickerOptions:453 | onTap | ListTile | () { Navigator.pop(context); _takePhoto(); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ProfileEditScreenState._showImagePickerOptions:461 | onTap | ListTile | () { Navigator.pop(context); setState(() { _selectedImage = null; | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ProfileEditScreenState._forceUpdateAllContent:739 | onPressed | TextButton | () => Navigator.pop(context, false), child: Text(AppLocalizations.of(context)!.cancel), ), ElevatedButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ProfileEditScreenState._forceUpdateAllContent:743 | onPressed | ElevatedButton | () => Navigator.pop(context, true), style: ElevatedButton.styleFrom( backgroundColor: Colors.orange, ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ProfileEditScreenState.build:861 | onPressed | IconButton | () => Navigator.maybePop(context), ), title: Text( AppLocalizations.of(context)!.profileEdit ?? "", | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ProfileEditScreenState.build:888 | onPressed | TextButton | _updateProfile, child: Text( AppLocalizations.of(context)!.save, style: TextStyle( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ProfileEditScreenState.build:932 | onTap | GestureDetector | _showImagePickerOptions, child: Stack( children: [ Container( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _ProfileEditScreenState.build:1112 | onChanged | TextFormField | (value) { _bio = value.trim(); }, ), | input / text | intentionally_static | IME·선택·링크의 입력 State를 모션으로 재생성하지 않음 |
| _ProfileEditScreenState.build:1169 | onChanged | DropdownButtonFormField | _nationalityLocked ? null : (value) { if (value != null) { | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ProfileEditScreenState.build:1214 | onTap | InkWell | () => setState(() => _studentType = type), borderRadius: BorderRadius.circular(10), child: AnimatedContainer( duration: const Duration(milliseconds: 150), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ProfileEditScreenState.build:1451 | onPressed | TextButton | status == HanyangVerificationStatus.unavailable ? () => authProvider .refreshHanyangVerificationStatus() | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ProfileEditScreenState.build:1503 | onChanged | SwitchListTile | (value) => setState(() => _showDepartment = value), ), TextFormField( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ProfileEditScreenState.build:1518 | onChanged | SwitchListTile | (value) => setState(() => _showGrade = value), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/profile_grid_screen.dart — 운영 진입 미발견</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _ProfileGridScreenState.build:462 | onPressed | IconButton | () { Navigator.push( context, MaterialPageRoute( | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _ProfileGridScreenState.build:490 | onPressed | IconButton | () => _handleMoreActions(), tooltip: '메뉴', ), ], | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _ProfileGridScreenState._confirmAction:727 | onPressed | TextButton | () => Navigator.of(context).pop(false), child: Text(cancelLabel ?? loc.cancel), ), TextButton( | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _ProfileGridScreenState._confirmAction:731 | onPressed | TextButton | () => Navigator.of(context).pop(true), child: Text(confirmLabel ?? loc.confirm), ), ], | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _ProfileGridScreenState._handleHighlightTap:884 | onPressed | TextButton | () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.confirm), ), ], | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |

</details>

<details>
<summary>lib/screens/requests_page.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _RequestsPageState._showConfirmDialog:164 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(false), style: TextButton.styleFrom( foregroundColor: const Color(0xFF667085), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _RequestsPageState._showConfirmDialog:171 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(true), style: TextButton.styleFrom( foregroundColor: const Color(0xFF111827), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _RequestsPageState.build:212 | onPressed | IconButton | () => Navigator.of(context).maybePop(), ), ), body: SafeArea( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _RequestsPageState._requestAction:549 | onPressed | RelationshipActionButton | onPressed, tone: secondary ? RelationshipActionButtonTone.neutral : RelationshipActionButtonTone.primary, | RelationshipActionButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _RequestsPageState._buildErrorState:675 | onPressed | TextButton | () { unawaited(_retryData()); }, style: TextButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/review_accept_screen.dart — 운영 진입 미발견</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _ReviewAcceptScreenState._showFeatureDisabledDialog:68 | onPressed | TextButton | () { Navigator.of(context).pop(); // 다이얼로그 닫기 Navigator.of(context).pop(); // 화면 닫기 }, | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _ReviewAcceptScreenState._showRejectConfirmDialog:159 | onPressed | TextButton | () => Navigator.of(context).pop(false), child: const Text('취소'), ), TextButton( | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _ReviewAcceptScreenState._showRejectConfirmDialog:163 | onPressed | TextButton | () => Navigator.of(context).pop(true), style: TextButton.styleFrom( foregroundColor: Colors.red, ), | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _ReviewAcceptScreenState.build:280 | onPressed | IconButton | () => Navigator.of(context).maybePop(), icon: Icon( Icons.arrow_back_rounded, color: const Color(0xFF111827), | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _ReviewAcceptScreenState._buildAttachedImages:476 | onTap | GestureDetector | () { // 이미지 확대 보기 (기존 이미지 뷰어 재사용) // _showImageDialog(widget.reviewRequest.imageUrls[index]); }, | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _ReviewAcceptScreenState._buildBottomButtons:641 | onPressed | TextButton | _isProcessing ? null : _rejectRequest, style: TextButton.styleFrom( foregroundColor: const Color(0xFF667085), shape: RoundedRectangleBorder( | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _ReviewAcceptScreenState._buildBottomButtons:677 | onPressed | FilledButton | _isProcessing ? null : _acceptRequest, style: FilledButton.styleFrom( backgroundColor: const Color(0xFF2E90FA), foregroundColor: Colors.white, | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _ReviewAcceptScreenState._buildExpiredScreen:763 | onPressed | FilledButton | () => Navigator.of(context).pop(), style: FilledButton.styleFrom( backgroundColor: const Color(0xFF2E90FA), shape: RoundedRectangleBorder( | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _ReviewAcceptScreenState._buildAlreadyRespondedScreen:852 | onPressed | FilledButton | () => Navigator.of(context).pop(), style: FilledButton.styleFrom( backgroundColor: const Color(0xFF2E90FA), foregroundColor: Colors.white, | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |

</details>

<details>
<summary>lib/screens/review_approval_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _ReviewApprovalScreenState.build:306 | onPressed | IconButton | () => Navigator.of(context).maybePop(), icon: Icon( Icons.arrow_back_rounded, color: const Color(0xFF111827), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ReviewApprovalScreenState._buildImageGallery:353 | onTap | GestureDetector | () => showFullscreenImageViewer( context, imageUrls: _imageUrls, initialIndex: index, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _ReviewApprovalScreenState._buildBottomActions:465 | onPressed | TextButton |  _isProcessing ? null : () => _handleResponse(false), style: TextButton.styleFrom( foregroundColor: const Color(0xFF667085), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ReviewApprovalScreenState._buildBottomActions:491 | onPressed | FilledButton |  _isProcessing ? null : () => _handleResponse(true), style: FilledButton.styleFrom( backgroundColor: const Color(0xFF2E90FA), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/review_comments_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _ReviewCommentsScreenState.build:54 | onTap | GestureDetector | () { // 키보드 밖을 탭하면 키보드 닫기 FocusScope.of(context).unfocus(); }, | staticGesture | intentionally_static | 기존 scroll·zoom·입력 해제·재생 gesture 보존 |
| _ReviewCommentsScreenState.build:70 | onPressed | IconButton | () => Navigator.pop(context), icon: Icon( Icons.arrow_back_rounded, size: context.ri(22).clamp(21, 24).toDouble(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ReviewCommentsScreenState._buildCommentInput:376 | onPressed | IconButton | canSubmit ? _handleSubmitComment : null, padding: EdgeInsets.zero, style: IconButton.styleFrom( backgroundColor: const Color(0xFF2E90FA), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/review_detail_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _ReviewDetailScreenState.build:255 | onPressed | IconButton | () => Navigator.pop(context), icon: Icon( Icons.arrow_back_rounded, size: context.ri(22).clamp(21, 24).toDouble(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ReviewDetailScreenState._buildImage:517 | onTap | GestureDetector | () { showFullscreenImageViewer( context, imageUrls: review.imageUrls, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _ReviewDetailScreenState._buildActionButtons:690 | onPressed | IconButton | currentUser != null && !_isLiking ? _handleLike : null, padding: EdgeInsets.zero, tooltip: l10n?.likes ?? '', icon: AnimatedSwitcher( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ReviewDetailScreenState._buildActionButtons:724 | onPressed | IconButton | () => _navigateToComments(review), padding: EdgeInsets.zero, tooltip: l10n?.comments ?? '', icon: Icon( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ReviewDetailScreenState._buildActionButtons:737 | onTap | InkWell | () => _navigateToComments(review), borderRadius: BorderRadius.circular(8), child: Row( children: [ | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/review_request_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _ReviewRequestScreenState._showFeatureDisabledDialog:79 | onPressed | TextButton | () { Navigator.of(context).pop(); // 다이얼로그 닫기 Navigator.of(context).pop(); // 화면 닫기 }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ReviewRequestScreenState.build:261 | onPressed | IconButton | () => Navigator.of(context).maybePop(), icon: Icon( Icons.arrow_back_rounded, color: const Color(0xFF111827), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ReviewRequestScreenState._buildImageAttachment:545 | onPressed | TextButton | _pickImages, style: TextButton.styleFrom( foregroundColor: const Color(0xFF475467), padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ReviewRequestScreenState._buildImageAttachment:593 | onPressed | IconButton | () => _removeImage(index), padding: EdgeInsets.zero, style: IconButton.styleFrom( backgroundColor: const Color(0xB3111827), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ReviewRequestScreenState._buildBottomButton:681 | onPressed | FilledButton | _isSubmitting ? null : _submitRequest, style: FilledButton.styleFrom( backgroundColor: const Color(0xFF2E90FA), foregroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/saved_posts_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SavedPostsScreenState.build:84 | onPressed | IconButton | () => Navigator.pop(context), tooltip: MaterialLocalizations.of(context).backButtonTooltip, ), title: MediaQuery.withClampedTextScaling( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SavedPostsScreenState._buildSavedPostItem:274 | onTap | InkWell | () => _openPostDetail(post.id), child: Padding( padding: EdgeInsets.symmetric( vertical: context.rs(14).clamp(12, 16).toDouble(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/search_result_page.dart — 운영 진입 미발견</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SearchResultPageState.build:164 | onPressed | AppIconButton | () => Navigator.pop(context), semanticLabel: '뒤로가기', ), title: Text( | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _SearchResultPageState.build:188 | onChanged | TextField | _onSearchChanged, onSubmitted: (query) { _debounceTimer?.cancel(); _searchRequestGuard.invalidate(); | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _SearchResultPageState.build:209 | onTap | GestureDetector | () { _debounceTimer?.cancel(); _searchRequestGuard.invalidate(); _searchController.clear(); | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _SearchResultPageState._buildMeetingResults:341 | onTap | InkWell | isHanyangLocked ? null : () => _showMeetupDetail(meetup), borderRadius: BorderRadius.circular(16), child: Container( decoration: BoxDecoration( | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _SearchResultPageState._buildInfoResults:502 | onTap | InkWell | isHanyangLocked ? null : () => _showPostDetail(post), child: Container( padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Row( | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |

</details>

<details>
<summary>lib/screens/search_users_page.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SearchUsersPageState._showConfirmDialog:290 | onPressed | TextButton | () => Navigator.of(context).pop(false), child: Text(l10n?.cancel ?? ""), ), ElevatedButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SearchUsersPageState._showConfirmDialog:294 | onPressed | ElevatedButton | () => Navigator.of(context).pop(true), style: ElevatedButton.styleFrom( backgroundColor: Colors.red, foregroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SearchUsersPageState.build:313 | onTap | GestureDetector | () { // 빈 공간 터치시 키보드 닫기 FocusScope.of(context).unfocus(); }, | staticGesture | intentionally_static | 기존 scroll·zoom·입력 해제·재생 gesture 보존 |
| _SearchUsersPageState._buildSearchBar:388 | onPressed | AppIconButton | () { _searchController.clear(); context.read<RelationshipProvider>().clearSearchResults(); }, | AppIconButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _SearchUsersPageState._buildSearchBar:407 | onChanged | TextField | _searchUsers, textInputAction: TextInputAction.search, ), ); | input / text | intentionally_static | IME·선택·링크의 입력 State를 모션으로 재생성하지 않음 |
| names._buildErrorState:521 | onPressed | ElevatedButton | () { final provider = context.read<RelationshipProvider>(); provider.clearError(); final query = _searchController.text.trim(); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/semester_todo_admin_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SemesterTodoAdminScreenState.build:68 | onPressed | FloatingActionButton | () => _editSemester(), backgroundColor: AppColors.pointColor, foregroundColor: Colors.white, child: const Icon(Icons.add_rounded), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoAdminScreenState.build:87 | onPressed | TextButton | _refresh, child: const Text('다시 시도'), ), ); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoAdminScreenState.build:127 | onTap | ListTile | () => Navigator.push<void>( context, MaterialPageRoute( builder: (_) => SemesterWeeksAdminScreen( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoAdminScreenState.build:136 | onSelected | PopupMenuButton | (value) { if (value == 'edit') _editSemester(semester); if (value == 'clone') _cloneSemester(semester); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoAdminScreenState._editSemester:225 | onTap | ListTile | () async { final value = await showDatePicker( context: context, initialDate: start, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoAdminScreenState._editSemester:238 | onTap | ListTile | () async { final value = await showDatePicker( context: context, initialDate: end, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoAdminScreenState._editSemester:258 | onChanged | DropdownButtonFormField | (value) => setSheetState(() => status = value ?? status), ), const SizedBox(height: 20), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoAdminScreenState._editSemester:266 | onPressed | ElevatedButton | () { if (ko.text.trim().isEmpty && en.text.trim().isEmpty) { ScaffoldMessenger.of(sheetContext).showSnackBar( const SnackBar(content: Text('학기명을 입력해 주세요.')), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoAdminScreenState._cloneSemester:362 | onTap | ListTile | () async { final value = await showDatePicker( context: context, initialDate: start, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoAdminScreenState._cloneSemester:374 | onChanged | CheckboxListTile | (value) => setSheetState(() => includeExchange = value == true)), CheckboxListTile( contentPadding: EdgeInsets.zero, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoAdminScreenState._cloneSemester:380 | onChanged | CheckboxListTile | (value) => setSheetState(() => includeKorean = value == true)), CheckboxListTile( contentPadding: EdgeInsets.zero, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoAdminScreenState._cloneSemester:386 | onChanged | CheckboxListTile | (value) => setSheetState(() => includeDue = value == true)), SizedBox( width: double.infinity, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoAdminScreenState._cloneSemester:391 | onPressed | ElevatedButton | includeExchange \|\| includeKorean ? () => Navigator.pop(sheetContext, true) : null, child: const Text('복제'))), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterWeeksAdminScreenState.build:465 | onTap | ListTile | () => Navigator.push<void>( context, MaterialPageRoute( builder: (_) => SemesterTasksAdminScreen( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterWeeksAdminScreenState.build:473 | onChanged | Switch | (value) async { await _service.setWeekPublished( widget.semester.id, week.id, value); _refresh(); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTasksAdminScreenState.build:531 | onSelected | PopupMenuButton | _preview, itemBuilder: (_) => const [ PopupMenuItem( value: StudentType.exchange, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTasksAdminScreenState.build:544 | onPressed | IconButton | () => _editTask(), icon: const Icon(Icons.add_rounded)), ], ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTasksAdminScreenState.build:617 | onTap | ListTile | () => _editTask(task), trailing: Icon(task.isActive ? Icons.chevron_right_rounded : Icons.visibility_off_outlined), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTasksAdminScreenState.showError:784 | onChanged | DropdownButtonFormField | (value) => setSheetState(() => type = value ?? type)), DropdownButtonFormField<StudentType>( initialValue: audience, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTasksAdminScreenState.showError:795 | onChanged | DropdownButtonFormField | existing == null ? (value) => setSheetState(() => audience = value ?? audience) : null), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTasksAdminScreenState.showError:803 | onChanged | CheckboxListTile | (value) => setSheetState(() => carryOver = value == true)), SwitchListTile( contentPadding: EdgeInsets.zero, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTasksAdminScreenState.showError:809 | onChanged | SwitchListTile | (value) => setSheetState(() => active = value)), TextField( controller: order, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTasksAdminScreenState.showError:844 | onPressed | TextButton | saving ? null : () async { final picked = await _imagePicker.pickImage( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTasksAdminScreenState.showError:864 | onPressed | TextButton | saving ? null : () => setSheetState(() { selectedImage = null; | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTasksAdminScreenState.showError:877 | onChanged | TextField | (_) => setSheetState(() {}), decoration: const InputDecoration( labelText: '이미지 URL 직접 입력 (선택)', hintText: 'https://...', | input / text | intentionally_static | IME·선택·링크의 입력 State를 모션으로 재생성하지 않음 |
| _SemesterTasksAdminScreenState.showError:894 | onPressed | IconButton | () => setSheetState(() => dueDate = null), icon: const Icon(Icons.close_rounded), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTasksAdminScreenState.showError:898 | onTap | ListTile | () async { final value = await showDatePicker( context: context, initialDate: dueDate ?? widget.week.endDate, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTasksAdminScreenState.showError:918 | onChanged | DropdownButtonFormField | (value) => setSheetState( () => actionType = value ?? actionType)), if (actionType != SemesterTodoActionType.none) TextField( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTasksAdminScreenState.showError:936 | onPressed | ElevatedButton | saving ? null : () async { if (titleKo.text.trim().isEmpty && | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/semester_todo_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SemesterTodoScreenState.build:301 | onPressed | IconButton | () => Navigator.maybePop(context), icon: const Icon(Icons.arrow_back_rounded, size: 22), ), title: Text( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState.build:318 | onPressed | IconButton | _changeStudentType, tooltip: (isChineseUi(context) ? '更改学生类型' : _isKorean | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState.build:372 | onPressed | TextButton | !controller.personalDataLoaded ? null : () => _editPersonalTodo(controller, initialWeekNumber: | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._weekPicker:433 | onTap | InkWell | () => _goToWeek(controller, index), borderRadius: BorderRadius.circular(8), child: AnimatedContainer( duration: const Duration(milliseconds: 180), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._weekSummary:549 | onPressed | TextButton | () => _goToWeek(controller, currentIndex), child: Text(_copy('이번 주로', 'Go to this week', '回到本周'))), ), ]), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._fold:559 | onPressed | TextButton | toggle, style: TextButton.styleFrom( foregroundColor: const Color(0xFF64748B), minimumSize: const Size(48, 48), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._loadFailure:586 | onPressed | TextButton | controller.load, child: Text(_copy('다시 시도', 'Retry', '重试'))), ]), ); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._sectionHeading:654 | onPressed | TextButton | controller.isPersonalBusy(entry.personal!.id) ? null : () => _moveTodo(controller, entry.personal!), child: Text( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._sectionHeading:660 | onPressed | TextButton | controller.isPersonalBusy(entry.personal!.id) ? null : () => _hideTodo(controller, entry.personal!, true), child: Text(_copy('그만 보기', 'Hide', '隐藏'))), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._sectionHeading:668 | onPressed | TextButton | () => setState(() { all ? _expandedPreviousWeeks.remove(weekNumber) : _expandedPreviousWeeks.add(weekNumber); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._sectionHeading:725 | onPressed | TextButton | controller.isPersonalBusy(todo.id) ? null : () => _hideTodo(controller, todo, false), child: Text(_copy('복구', 'Restore', '恢复'))), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._globalReminderRow:758 | onTap | InkWell | controller.personalTodoNotificationSaving ? null : () => _selectGlobalReminderTime(controller), borderRadius: BorderRadius.circular(8), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._globalReminderRow:812 | onChanged | Switch | (value) => _toggleGlobalReminders( controller, value, ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._entryRow:885 | onTap | InkResponse | busy ? null : () => todo != null ? _togglePersonalTodo(controller, todo) | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _SemesterTodoScreenState._entryRow:923 | onTap | InkWell | busy ? null : () => todo != null ? _editPersonalTodo(controller, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._entryRow:994 | onPressed | IconButton |  busy ? null : () => _toggleItemReminder(controller, todo), tooltip: todo.reminderEnabled ? _copy('알림 끄기', 'Turn reminder off', '关闭提醒') | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._guideDetails:1082 | onPressed | IconButton | () => Navigator.pop(sheetContext), tooltip: MaterialLocalizations.of(sheetContext) .closeButtonTooltip, icon: const Icon(Icons.close_rounded, size: 21), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._guideDetails:1128 | onPressed | TextButton | () => _openAction(task), icon: Icon( task.actionType == SemesterTodoActionType.externalUrl ? Icons.open_in_new_rounded | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._guideDetails:1147 | onPressed | TextButton | () async { await _toggleTask(controller, task); if (sheetContext.mounted) Navigator.pop(sheetContext); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._askToEnableGlobalReminders:1374 | onPressed | TextButton | () => Navigator.pop(dialogContext, false), child: Text((isChineseUi(context) ? '暂不开启' : _isKorean | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SemesterTodoScreenState._askToEnableGlobalReminders:1382 | onPressed | TextButton | () => Navigator.pop(dialogContext, true), child: Text((isChineseUi(context) ? '开启' : _isKorean | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PersonalTodoEditorPageState.build:1772 | onPressed | IconButton | () => Navigator.maybePop(context), icon: const Icon( Icons.arrow_back_rounded, color: const Color(0xFF0F172A), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PersonalTodoEditorPageState.build:1810 | onPressed | IconButton | () => Navigator.pop( context, const _PersonalTodoEditorResult.delete(), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PersonalTodoEditorPageState.build:1822 | onPressed | TextButton | canSave ? _save : null, style: TextButton.styleFrom( foregroundColor: AppColors.pointColor, disabledForegroundColor: const Color(0xFFCBD5E1), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PersonalTodoEditorPageState.build:1858 | onChanged | TextField | (_) => setState(() {}), onSubmitted: (_) { if (canSave) _save(); }, | input / text | intentionally_static | IME·선택·링크의 입력 State를 모션으로 재생성하지 않음 |
| _PersonalTodoEditorPageState.build:1883 | onPressed | IconButton | _canMoveFocusedMonth(-1) ? () => _moveFocusedMonth(-1) : null, icon: const Icon(Icons.chevron_left_rounded, size: 22), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PersonalTodoEditorPageState.build:1915 | onPressed | IconButton | _canMoveFocusedMonth(1) ? () => _moveFocusedMonth(1) : null, icon: const Icon(Icons.chevron_right_rounded, size: 22), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ReminderTimeSheetState.build:2185 | onPressed | IconButton | () => Navigator.pop(context), icon: const Icon(Icons.close_rounded), color: const Color(0xFF64748B), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ReminderTimeSheetState.build:2240 | onPressed | TextButton | () => Navigator.pop(context), style: TextButton.styleFrom( foregroundColor: const Color(0xFF64748B), minimumSize: const Size(72, 48), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ReminderTimeSheetState.build:2261 | onPressed | TextButton | () => Navigator.pop(context, _selectedTime), style: TextButton.styleFrom( foregroundColor: AppColors.pointColor, minimumSize: const Size(72, 48), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ErrorState.build:2343 | onPressed | TextButton | onRetry, child: Text((isChineseUi(context) ? '重试' : korean | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/signup_method_selection_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SignUpMethodSelectionScreenState.build:275 | onPressed | IconButton | _isLoading ? null : _leaveSignup, ), title: Text( l10n.signUpMethodSelectionTitle, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SignUpMethodSelectionScreenState.build:347 | onChanged | Checkbox | _isLoading ? null : (value) => setState( () => _agreedTerms = | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PolicyLink.build:492 | onPressed | TextButton | onPressed, style: TextButton.styleFrom( foregroundColor: const Color(0xFF475569), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SocialSignupButton.build:532 | onPressed | ElevatedButton | onPressed, style: ElevatedButton.styleFrom( elevation: 0, backgroundColor: backgroundColor, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/snack_chat_discovery_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SnackChatDiscoveryScreenState._photoResult:522 | onTap | InkWell | () => _openPhoto(row), child: Stack( fit: StackFit.expand, children: [ | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatDiscoveryScreenState._resultFooter:680 | onPressed | TextButton | () => _load(reset: _rows.isEmpty), child: Text(t('다시 시도', 'Retry', '重试')), ), if (!_loading && _error == null && _rows.isEmpty && !_hasMore) | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatDiscoveryScreenState._resultFooter:701 | onPressed | TextButton | _load, child: Text(t('더 보기', 'Load more', '加载更多')), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FileLibraryRow.build:863 | onTap | InkWell | expired ? null : onTap, borderRadius: BorderRadius.circular(8), child: Padding( padding: const EdgeInsets.symmetric(vertical: 10), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _LinkLibraryRow.build:941 | onTap | InkWell | () => onOpen(link), borderRadius: BorderRadius.circular(8), child: Padding( padding: const EdgeInsets.symmetric(vertical: 10), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/snack_chat_info_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SnackChatInfoScreenState._openInviteSheet:258 | onPressed | TextButton | selected.isEmpty ? null : () { FocusManager.instance.primaryFocus | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatInfoScreenState._leaveRoom:688 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(false), style: TextButton.styleFrom( foregroundColor: const Color(0xFF667085), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatInfoScreenState._leaveRoom:715 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(true), style: TextButton.styleFrom( foregroundColor: const Color(0xFFB42318), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatInfoScreenState._buildTopToggleAction:881 | onPressed | IconButton | busy ? null : onPressed, tooltip: tooltip, color: active ? AppColors.pointColor : const Color(0xFF475569), disabledColor: const Color(0xFF98A2B3), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatInfoScreenState._buildDiscoveryShortcut:921 | onTap | InkWell | () => _openDiscovery(initialKind: kind), borderRadius: BorderRadius.circular(10), child: ConstrainedBox( constraints: const BoxConstraints(minHeight: 58), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatInfoScreenState.build:997 | onPressed | TextButton | _retryRoomStream, icon: const Icon(Icons.refresh_rounded), label: Text((isChineseUi(context) ? '重试' | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatInfoScreenState.build:1030 | onPressed | IconButton | () => Navigator.maybePop(context), icon: Icon( Icons.arrow_back_rounded, size: context.ri(22).clamp(21, 24).toDouble(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatInfoScreenState.build:1131 | onPressed | TextButton | _isUpdatingTitle ? null : () => _changeRoomTitle(room), style: TextButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatInfoScreenState.build:1170 | onPressed | TextButton | _isSendingAnnouncement ? null : () => _createAnnouncement(room), style: TextButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatInfoScreenState.build:1266 | onPressed | IconButton | _isInviting ? null : () => _openInviteSheet(room), padding: EdgeInsets.zero, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatInfoScreenState.build:1344 | onPressed | TextButton | _leaveRoom, style: TextButton.styleFrom( foregroundColor: const Color(0xFF667085), padding: const EdgeInsets.symmetric( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreatorTextDialogState.build:1471 | onChanged | TextField | (value) { if (_isClosing) return; final next = value.trim().isNotEmpty; if (next != _canSubmit) setState(() => _canSubmit = next); | input / text | intentionally_static | IME·선택·링크의 입력 State를 모션으로 재생성하지 않음 |
| _CreatorTextDialogState.build:1505 | onPressed | TextButton | _cancel, child: Text((isChineseUi(context) ? '取消' : isKo | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CreatorTextDialogState.build:1513 | onPressed | TextButton | _canSubmit ? _submit : null, child: Text(widget.actionLabel), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _MemberTile.build:1540 | onTap | InkWell | canOpenProfile ? () { Navigator.push( context, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/snack_chat_poll_schedule_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SnackChatPollScheduleScreenState.build:181 | onPressed | IconButton | () => Navigator.of(context).pop(), tooltip: MaterialLocalizations.of(context).backButtonTooltip, icon: Icon( Icons.arrow_back_rounded, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatPollScheduleScreenState.build:217 | onPressed | IconButton | _canComplete ? _complete : null, tooltip: (isChineseUi(context) ? '完成' : _isKo ? '완료' : 'Done'), icon: const Icon(Icons.check_rounded, size: 22), color: const Color(0xFF111827), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatPollScheduleScreenState.build:226 | onPressed | TextButton | _canComplete ? _complete : null, style: TextButton.styleFrom( foregroundColor: const Color(0xFF111827), disabledForegroundColor: const Color(0xFFD1D5DB), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatPollScheduleScreenState._buildTimeWheels:291 | onChanged | Semantics | (value) => setState(() => _selectedHour = value), ), Padding( padding: EdgeInsets.symmetric(horizontal: 8), | semantics delegation | intentionally_static | 동일 액션의 접근성 위임; 별도 버튼으로 중복 집계하지 않음 |
| _SnackChatPollScheduleScreenState._buildTimeWheels:310 | onChanged | Semantics | (value) => setState(() => _selectedMinute = value), ), ], ), | semantics delegation | intentionally_static | 동일 액션의 접근성 위임; 별도 버튼으로 중복 집계하지 않음 |

</details>

<details>
<summary>lib/screens/snack_chat_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SnackChatScreenState._peopleLoadRetry:5810 | onPressed | TextButton | onRetry, icon: const Icon(Icons.refresh_rounded, size: 17), label: Text((isChineseUi(context) ? '重试' | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState._messageActionTile:6193 | onTap | InkWell | onTap, child: ConstrainedBox( constraints: const BoxConstraints(minHeight: 52), child: Padding( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _SnackChatScreenState.build:6424 | onPressed | TextButton | _retryRoomStream, icon: const Icon(Icons.refresh_rounded), label: Text((isChineseUi(context) ? '重试' | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState.build:6477 | onPressed | IconButton | _isLeavingRoom ? null : () => _openRoomInfo(room), icon: const Icon( Icons.more_vert_rounded, color: Color(0xFF344054), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState._buildTranslationControl:6673 | onPressed | TextButton |  _todaySummaryLoading ? null : _openTodaySummary, style: TextButton.styleFrom( foregroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState._buildTranslationActionControl:6773 | onPressed | TextButton | _translationModeReady ? _toggleSnackTranslation : null, style: TextButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState._buildTranslationActionControl:6827 | onPressed | IconButton | _openSnackTranslationLanguageSettings, icon: const Icon(Icons.settings_outlined), color: foreground, iconSize: 15, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState._buildMessageContent:6881 | onPressed | TextButton | _subscribeToMessages, icon: const Icon(Icons.refresh_rounded), label: Text((isChineseUi(context) ? '重试' | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState._buildMessageContent:6971 | onPressed | TextButton | _loadMoreMessages, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text((isChineseUi(context) ? '重新加载更早的消息' | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState._buildMessageContent:7055 | onTap | InkWell | _subscribeToMessages, borderRadius: BorderRadius.circular(20), child: Padding( padding: const EdgeInsets.symmetric( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState._buildMessageContent:7111 | onTap | InkWell | _scrollToLatest, borderRadius: BorderRadius.circular(22), child: Padding( padding: const EdgeInsets.symmetric( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState._buildMessageComposer:7216 | onPressed | IconButton | () => setState(_clearReplyState), tooltip: (isChineseUi(context) ? '取消回复' : isKo | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _SnackChatScreenState._buildComposerButton:7392 | onTap | InkWell | onPressed, child: SizedBox( width: width, height: height, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _SnackChatScreenState._buildMessageBubble:7631 | onTap | GestureDetector | hasFile ? () => _handleFileTap(message) : canOpenReadReceipt ? () => _showReadReceiptDetails(message) | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _SnackChatScreenState._buildMessageBubble:7636 | onLongPress | GestureDetector |  message.isPending ? null : () => _showMessageActions(message), child: Container( padding: bubblePadding, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _SnackChatScreenState._buildMessageBubble:7652 | onTap | GestureDetector | replyPreview.isDeleted ? null : () => _jumpToMessage( replyPreview.messageId, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _SnackChatScreenState._buildOutgoingMessageMeta:8273 | onPressed | IconButton | () => _retryMessage(message), icon: const Icon(Icons.schedule, size: 15, color: Color(0xFF667085)), ); } | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState._buildOutgoingMessageMeta:8291 | onTap | InkWell | () => _retryMessage(message), borderRadius: BorderRadius.circular(14), child: const SizedBox.square( dimension: 28, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState._buildOutgoingMessageMeta:8313 | onTap | InkWell | () => _showReadReceiptDetails(message), borderRadius: BorderRadius.circular(12), child: SizedBox( width: 28, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState.errorFrame:8438 | onTap | GestureDetector | message.isPending && imageUrl == null && storagePath == null ? null : () => _openImageViewer( imageUrl, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _SnackChatScreenState._imageError:8514 | onPressed | IconButton | onRetry, tooltip: (isChineseUi(context) ? '重新加载图片' : Localizations.localeOf(context).languageCode == 'ko' | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState._buildSummaryRunProgress:9019 | onPressed | TextButton | run.pause, style: TextButton.styleFrom( foregroundColor: const Color(0xFF334155), minimumSize: const Size(48, 44), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState._buildSummaryRunProgress:9029 | onPressed | TextButton | () async { await run.start(); if (mounted && _summaryRun == run && run.complete) { await _showSummaryRunResult(run); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState._buildSummaryRunProgress:9043 | onPressed | TextButton | () => _showSummaryRunResult(run), style: TextButton.styleFrom( foregroundColor: const Color(0xFF087BB5), minimumSize: const Size(48, 44)), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatScreenState._buildSummaryRunProgress:9054 | onPressed | IconButton | () { run.dispose(); setState(() => _summaryRun = null); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/snack_chat_tab_view.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SnackChatTabViewState.build:356 | onPressed | FloatingActionButton | () { HapticFeedback.lightImpact(); widget.onCreateSnackChat?.call(); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SnackChatEmptyState.build:611 | onPressed | FilledButton | onCreate, icon: Icon( Icons.add_comment_outlined, size: context.ri(19).clamp(18, 21).toDouble(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SectionError.build:820 | onPressed | TextButton | onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text( (isChineseUi(context) | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/snapshot_archive_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SnapshotArchiveScreenState._delete:45 | onPressed | TextButton | () => Navigator.pop(dialogContext, false), child: Text(strings.cancel), ), TextButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnapshotArchiveScreenState._delete:49 | onPressed | TextButton | () => Navigator.pop(dialogContext, true), child: Text(strings.delete), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnapshotArchiveScreenState.build:90 | onPressed | TextButton | () => setState(_reload), icon: const Icon(Icons.refresh_rounded), label: Text(strings.retry), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ArchiveTile.build:356 | onTap | ListTile | onTap, contentPadding: const EdgeInsets.symmetric(vertical: 4), leading: ClipRRect( borderRadius: BorderRadius.circular(10), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ArchiveTile.build:379 | onPressed | IconButton | onDelete, tooltip: SnapshotStrings.of(context).delete, icon: const Icon(Icons.delete_outline_rounded), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ArchiveVideoState.build:435 | onTap | GestureDetector | () { setState(() { if (_controller.value.isPlaying) { unawaited(_controller.pause()); | staticGesture | intentionally_static | 기존 scroll·zoom·입력 해제·재생 gesture 보존 |

</details>

<details>
<summary>lib/screens/snapshot_comment_letter_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SnapshotCommentLetterScreenState.build:224 | onPressed | IconButton | () => Navigator.maybePop(context), icon: Icon( Icons.arrow_back_rounded, size: context.ri(23).clamp(22, 25).toDouble(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnapshotCommentLetterScreenState._buildReplyComposer:504 | onChanged | TextField | (_) => setState(() {}), style: TextStyle( fontFamily: uiFontFamily(context, 'Inter'), fontFamilyFallback: const ['NotoSansKR'], | input / text | intentionally_static | IME·선택·링크의 입력 State를 모션으로 재생성하지 않음 |
| _SnapshotCommentLetterScreenState._buildReplyComposer:536 | onPressed | IconButton | !_isSending && _replyController.text.trim().isNotEmpty ? _sendReply : null, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnapshotCommentLetterScreenState._buildError:608 | onPressed | TextButton | _loadLetter, icon: const Icon(Icons.refresh_rounded, size: 20), label: Text((isChineseUi(context) ? '重试' : _isKorean ? '다시 시도' : 'Try again')), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SourceContext.build:654 | onTap | InkWell | onProfileTap, borderRadius: BorderRadius.circular(8), child: ConstrainedBox( constraints: const BoxConstraints(minHeight: 48), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PersonLine.build:856 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(8), child: ConstrainedBox( constraints: const BoxConstraints(minHeight: 48), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/snapshot_comments_sheet.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SnapshotCommentsSheetState._showActions:160 | onTap | ListTile | () => Navigator.pop(sheetContext, 'reply'), ), if (own) ListTile( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnapshotCommentsSheetState._showActions:166 | onTap | ListTile | () => Navigator.pop(sheetContext, 'delete'), ) else ...[ ListTile( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnapshotCommentsSheetState._showActions:172 | onTap | ListTile | () => Navigator.pop(sheetContext, 'report'), ), ListTile( leading: const Icon(Icons.block_outlined), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnapshotCommentsSheetState._showActions:177 | onTap | ListTile | () => Navigator.pop(sheetContext, 'block'), ), ], ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnapshotCommentsSheetState.build:277 | onPressed | IconButton | () => Navigator.pop(context), tooltip: MaterialLocalizations.of(context) .closeButtonTooltip, icon: Icon( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnapshotCommentsSheetState.build:419 | onPressed | IconButton | _sending ? null : () => setState(() { _selectedGif = null; _pendingRequestId = null; _gifInputGeneration++; | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnapshotCommentsSheetState.build:464 | onPressed | IconButton | () => setState(() => _replyingTo = null), tooltip: MaterialLocalizations.of(context) .cancelButtonLabel, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnapshotCommentsSheetState.build:564 | onTap | InkResponse | canSend ? _send : null, radius: buttonSize / 2, child: SizedBox.square( dimension: buttonSize, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _CommentRow.build:713 | onPressed | TextButton | onReply, style: TextButton.styleFrom( minimumSize: const Size(44, 32), padding: EdgeInsets.zero, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CommentRow.build:732 | onPressed | IconButton | onMore, tooltip: MaterialLocalizations.of(context).showMenuTooltip, color: const Color(0xFF667085), icon: const Icon(Icons.more_horiz_rounded, size: 20), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CommentGifState.build:787 | onPressed | TextButton | () => setState(_load), icon: const Icon(Icons.refresh_rounded), label: Text(SnapshotStrings.of(context).commentGifUnavailable), ); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/snapshot_detail_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SnapshotDetailScreenState.build:744 | onTapUp | GestureDetector | navigationEnabled ? (details) { final width = MediaQuery.sizeOf(context).width; if (details.localPosition.dx < width / 2) { | staticGesture | intentionally_static | 원래 미디어 탐색 tap/swipe 경계 보존 |
| _SnapshotDetailScreenState.build:754 | onHorizontalDragStart | GestureDetector |  navigationEnabled ? _handleHorizontalDragStart : null, onHorizontalDragUpdate: navigationEnabled ? _handleHorizontalDragUpdate : null, | staticGesture | intentionally_static | 기존 scroll·zoom·입력 해제·재생 gesture 보존 |
| _SnapshotDetailScreenState.build:756 | onHorizontalDragUpdate | GestureDetector |  navigationEnabled ? _handleHorizontalDragUpdate : null, onHorizontalDragEnd: navigationEnabled ? _handleHorizontalDragEnd : null, | staticGesture | intentionally_static | 기존 scroll·zoom·입력 해제·재생 gesture 보존 |
| _SnapshotCommentEntry.build:1227 | onTap | InkWell | onTap, child: SizedBox( width: width, height: 48, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _SnapshotBottomAction.build:1316 | onTap | InkResponse | onTap, radius: 26, child: ConstrainedBox( constraints: const BoxConstraints(minWidth: 52, minHeight: 48), | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _SnapshotLetterComposerSheetState.build:1577 | onPressed | IconButton | () => Navigator.of(context).pop(), tooltip: MaterialLocalizations.of( context, ).closeButtonTooltip, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnapshotLetterComposerSheetState.build:1645 | onPressed | IconButton | _sending ? null : _send, tooltip: strings.sendComment, icon: _sending ? const SizedBox.square( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnapshotTopRegion.build:1777 | onPressed | IconButton | onBack, icon: Icon( Icons.arrow_back_rounded, size: context.ri(22).clamp(21, 24).toDouble(), | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _SnapshotTopRegion.build:1799 | onTap | GestureDetector | onAuthorTap, child: Padding( padding: const EdgeInsets.symmetric(horizontal: 4), child: _SnapshotAuthorHeader( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _SnapshotTopRegion.build:1817 | onPressed | IconButton | onMore, icon: Icon( Icons.more_horiz_rounded, size: context.ri(23).clamp(21, 25).toDouble(), | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _SnapshotDeleteDialog.build:2002 | onPressed | TextButton | () => Navigator.pop(context, false), style: _snapshotDeleteActionStyle(secondaryText), child: Text( strings.cancel, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnapshotDeleteDialog.build:2015 | onPressed | TextButton | () { HapticFeedback.mediumImpact(); Navigator.pop(context, true); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ActionRow.build:2064 | onTap | InkWell | onTap, child: SizedBox( height: 52, child: Row( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/snapshot_viewers_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SnapshotViewersScreenState.build:77 | onPressed | IconButton | () => Navigator.of(context).maybePop(), tooltip: MaterialLocalizations.of(context).backButtonTooltip, icon: Icon( Icons.arrow_back_rounded, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ViewerRow.openProfile:243 | onTap | InkWell | canOpenProfile ? openProfile : null, borderRadius: BorderRadius.circular(10), child: Padding( padding: EdgeInsets.symmetric( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ViewerStatus.build:404 | onPressed | TextButton | onAction, style: TextButton.styleFrom( foregroundColor: const Color(0xFF344054), minimumSize: const Size(48, 44), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/social_tag_explorer_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| SocialTagExplorerScreen.build:47 | onPressed | IconButton | () => Navigator.of(context).pop(), tooltip: MaterialLocalizations.of(context).backButtonTooltip, icon: Icon( Icons.arrow_back_rounded, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TagSection.build:176 | onTap | InkWell | () => onPressed(option), child: Padding( padding: EdgeInsets.symmetric( horizontal: context.rs(12).clamp(10, 14).toDouble(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/social_tag_people_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SocialTagPeopleScreenState.build:242 | onPressed | IconButton | () => Navigator.of(context).pop(), tooltip: MaterialLocalizations.of(context).backButtonTooltip, icon: Icon( Icons.arrow_back_rounded, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SocialTagPeopleScreenState._buildContent:384 | onPressed | TextButton | _loadNextPage, child: Text((isChineseUi(context) ? '重试' : _isKorean ? '다시 시도' : 'Try again')), ), ); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TagPersonRow.build:438 | onTap | InkWell | isCurrentUser ? null : onTap, child: Padding( padding: EdgeInsets.fromLTRB( horizontalPadding, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TagPeopleMessage.build:576 | onPressed | TextButton | onAction, child: Text(actionLabel!)), ], ], ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/student_type_selection_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _StudentTypeSelectionScreenState.build:61 | onPressed | IconButton | () => Navigator.maybePop(context), icon: const Icon(Icons.arrow_back_rounded), ), title: Text( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _StudentTypeSelectionScreenState.build:127 | onPressed | ElevatedButton | _selected == null \|\| _saving ? null : _save, style: ElevatedButton.styleFrom( elevation: 0, backgroundColor: AppColors.pointColor, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _StudentTypeSelectionScreenState._option:173 | onTap | InkWell | () => setState(() => _selected = type), borderRadius: BorderRadius.circular(12), child: Padding( padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 2), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/terms_agreement_sheet.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _TermsAgreementSheetState.build:97 | onChanged | Checkbox | (value) => setState( () => _acceptedTerms = value ?? false, ), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TermsAgreementSheetState.build:125 | onPressed | TextButton | () => Navigator.push( context, MaterialPageRoute( builder: (_) => const TermsScreen(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TermsAgreementSheetState.build:134 | onPressed | TextButton | () => Navigator.push( context, MaterialPageRoute( builder: (_) => const PrivacyPolicyScreen(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/terms_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| TermsScreen.build:23 | onPressed | IconButton | () => Navigator.pop(context), ), title: Text( AppLocalizations.of(context)!.termsOfService ?? "", | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/unified_search_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _UnifiedSearchScreenState._rejectFriendRequest:418 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(false), child: Text(l10n.cancel), ), TextButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UnifiedSearchScreenState._rejectFriendRequest:422 | onPressed | TextButton | () => Navigator.of(dialogContext).pop(true), child: Text(l10n.confirm), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UnifiedSearchScreenState._unfriend:455 | onPressed | TextButton | () => Navigator.of(context).pop(false), child: Text(l10n?.cancel ?? ''), ), ElevatedButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UnifiedSearchScreenState._unfriend:459 | onPressed | ElevatedButton | () => Navigator.of(context).pop(true), style: ElevatedButton.styleFrom( backgroundColor: Colors.red, foregroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UnifiedSearchScreenState._unblockUser:494 | onPressed | TextButton | () => Navigator.of(context).pop(false), child: Text(l10n?.cancel ?? ''), ), ElevatedButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UnifiedSearchScreenState._unblockUser:498 | onPressed | ElevatedButton | () => Navigator.of(context).pop(true), style: ElevatedButton.styleFrom( backgroundColor: Colors.red, foregroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UnifiedSearchScreenState._buildSearchField:649 | onChanged | TextField | _onQueryChanged, ), ), SizedBox( | input / text | intentionally_static | IME·선택·링크의 입력 State를 모션으로 재생성하지 않음 |
| _UnifiedSearchScreenState._buildSearchField:658 | onTap | GestureDetector | () { _searchController.clear(); _clearAllResults(); FocusScope.of(context).unfocus(); | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _UnifiedSearchScreenState._buildEmptyPrompt:755 | onPressed | FilledButton | onAction, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(actionLabel), style: FilledButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UnifiedSearchScreenState.build:796 | onPressed | AppIconButton | () => Navigator.pop(context), semanticLabel: AppLocalizations.of(context)!.back, ), title: Text( | AppIconButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _UnifiedSearchScreenState._buildInlineUserSearchError:1025 | onPressed | TextButton | () => _searchUsers(query), icon: const Icon(Icons.refresh_rounded, size: 17), label: Text(l10n.retryAction), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UnifiedSearchScreenState._buildOrganizationTile:1082 | onTap | ListTile | () => Navigator.of(context).push(MaterialPageRoute<void>( builder: (_) => OrganizationProfileScreen( organization: organization, ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UnifiedSearchScreenState._buildInterestHeader:1231 | onSelected | ChoiceChip | (_) => _selectInterest(option.id), backgroundColor: const Color(0xFFF4F5F7), selectedColor: AppColors.pointColor, side: BorderSide.none, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UnifiedSearchScreenState._buildInterestHeader:1337 | onPressed | TextButton | provider.loadMoreInterestUsers, child: Text(l10n.retryAction), ), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UnifiedSearchScreenState._buildInterestStatus:1385 | onPressed | TextButton | onAction, child: Text(actionLabel), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UnifiedSearchScreenState._buildMeetupsTab:1521 | onTap | InkWell | isHanyangLocked ? null : () { Navigator.push( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/user_friends_list_screen.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _UserFriendsListScreenState.build:162 | onPressed | IconButton | () => Navigator.pop(context), ), title: Text( '${widget.userName}${AppLocalizations.of(context)!.friendsOfUser}', | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UserFriendsListScreenState._buildBody:215 | onPressed | TextButton | _loadFriends, style: TextButton.styleFrom( foregroundColor: const Color(0xFF344054), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UserFriendsListScreenState._buildSearchField:397 | onChanged | TextField | _onSearchChanged, textInputAction: TextInputAction.search, decoration: InputDecoration( hintText: (isChineseUi(context) ? '搜索昵称' : isKo ? '닉네임 검색' : 'Search by nickname'), | input / text | intentionally_static | IME·선택·링크의 입력 State를 모션으로 재생성하지 않음 |
| _UserFriendsListScreenState._buildSearchField:405 | onPressed | IconButton | () { _searchController.clear(); _onSearchChanged(''); setState(() {}); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UserFriendsListScreenState._buildFriendCard:451 | onTap | InkWell | () => _openProfile(friend), child: Padding( padding: EdgeInsets.fromLTRB( horizontalPadding, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _UserFriendsListScreenState._buildFriendCard:560 | onPressed | TextButton | (isRequesting \|\| isRequested) ? null : () => _sendFriendRequest(friend), style: TextButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/screens/user_meetups_screens.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _UserMeetupsViewState._buildErrorState:179 | onPressed | TextButton | () => setState(() {}), child: Text(l10n.retryAction), ), ], | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/snapshot/snapshot_storage_video.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SnapshotStorageVideoState.build:348 | onPressed | TextButton | _load, icon: const Icon(Icons.refresh_rounded, color: Colors.white), label: Text( SnapshotStrings.of(context).videoPlaybackFailed, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnapshotStorageVideoState.build:423 | onTap | InkResponse | _handlePlayRequested, radius: 32, child: const SizedBox.square( dimension: 56, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/snapshot/snapshot_today_section.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _MySnackTile.build:979 | onTap | GestureDetector | onAdd, child: SizedBox.square( dimension: 48, child: Center( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _SnackTileShell.build:1088 | onTap | Semantics | onTap, child: SizedBox( width: layout.cardWidth, height: layout.cardHeight, | semantics delegation | intentionally_static | 동일 액션의 접근성 위임; 별도 버튼으로 중복 집계하지 않음 |
| _SnackTileShell.build:1099 | onTap | InkWell | onTap, excludeFromSemantics: true, child: child, ), | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/ui/widgets/animated_button.dart — 운영 진입 미발견</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _AnimatedButtonState.build:200 | onTapUp | GestureDetector | _handleTapUp, onTapCancel: _handleTapCancel, onTap: widget.enabled ? widget.onPressed : null, child: AnimatedBuilder( | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _AnimatedButtonState.build:202 | onTap | GestureDetector | widget.enabled ? widget.onPressed : null, child: AnimatedBuilder( animation: _animationController, builder: (context, child) { | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _AnimatedButtonState.build:202 | onPressed | GestureDetector | null, child: AnimatedBuilder( animation: _animationController, builder: (context, child) { | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _AnimatedButtonState.build:233 | onTap | InkWell | widget.enabled ? widget.onPressed : null, child: Container( padding: const EdgeInsets.symmetric( horizontal: 24, | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _AnimatedButtonState.build:233 | onPressed | InkWell | null, child: Container( padding: const EdgeInsets.symmetric( horizontal: 24, | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _AnimatedOutlinedButtonState.build:372 | onTapUp | GestureDetector | _handleTapUp, onTapCancel: _handleTapCancel, onTap: widget.enabled ? widget.onPressed : null, child: AnimatedBuilder( | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _AnimatedOutlinedButtonState.build:374 | onTap | GestureDetector | widget.enabled ? widget.onPressed : null, child: AnimatedBuilder( animation: _animationController, builder: (context, child) { | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _AnimatedOutlinedButtonState.build:374 | onPressed | GestureDetector | null, child: AnimatedBuilder( animation: _animationController, builder: (context, child) { | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _AnimatedOutlinedButtonState.build:398 | onTap | InkWell | widget.enabled ? widget.onPressed : null, child: Container( padding: const EdgeInsets.symmetric( horizontal: 24, | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _AnimatedOutlinedButtonState.build:398 | onPressed | InkWell | null, child: Container( padding: const EdgeInsets.symmetric( horizontal: 24, | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |

</details>

<details>
<summary>lib/ui/widgets/app_button.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| AppButton.build:96 | onPressed | ElevatedButton | callback, style: compactStyle, child: content, ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| AppButton.build:106 | onPressed | OutlinedButton | callback, style: compactStyle, child: content, ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| AppButton.build:116 | onPressed | TextButton | callback, style: compactStyle, child: content, ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/app_fab.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| AppFab.build:65 | onPressed | AppFab | onPressed, semanticLabel: '새 글 작성하기', tooltip: '글쓰기', heroTag: heroTag ?? 'write_fab', | AppFab | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| AppFab.build:81 | onPressed | AppFab | onPressed, semanticLabel: '새 모임 만들기', tooltip: '모임 만들기', heroTag: heroTag ?? 'create_meetup_fab', | AppFab | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| AppFab.build:97 | onPressed | AppFab | onPressed, semanticLabel: '친구 추가하기', tooltip: '친구 추가', heroTag: heroTag ?? 'add_friend_fab', | AppFab | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| AppFab.build:117 | onPressed | AppFab | onPressed, semanticLabel: semanticLabel, heroTag: heroTag, enabled: enabled, | AppFab | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| AppFab.build:148 | onPressed | FloatingActionButton | effectiveEnabled ? _handleTap : null, icon: Icon( icon, size: DesignTokens.icon, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| AppFab.build:179 | onPressed | FloatingActionButton | effectiveEnabled ? _handleTap : null, backgroundColor: AppColors.pointColor, foregroundColor: Colors.white, elevation: DesignTokens.elevation3, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/ui/widgets/app_icon_button.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| AppIconButton.build:100 | onTap | InkWell | effectiveEnabled ? () { // 접근성 햅틱 피드백 context.accessibleFeedback(HapticFeedbackType.lightImpact); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _AppLikeButtonState.build:209 | onPressed | AppIconButton | _handleTap, iconColor: widget.isLiked ? colorScheme.secondary : null, semanticLabel: widget.isLiked ? '좋아요 취소 ${widget.likeCount != null ? ", ${widget.likeCount}개" : ""}' | unused | intentionally_static | 운영 호출 미발견; 미사용 controller 수정 안 함 |
| AppCommentButton.build:237 | onPressed | AppIconButton | onPressed, semanticLabel: '댓글 ${commentCount != null ? "$commentCount개" : ""}', tooltip: '댓글 보기', enabled: enabled, | AppIconButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| AppShareButton.build:256 | onPressed | AppIconButton | onPressed, semanticLabel: '공유하기', tooltip: '공유', enabled: enabled, | AppIconButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| AppMoreButton.build:275 | onPressed | AppIconButton | onPressed, semanticLabel: '더보기 옵션', tooltip: '옵션', enabled: enabled, | AppIconButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| AppBottomNavItem.build:369 | onTap | InkWell | enabled ? () { context.accessibleFeedback( HapticFeedbackType.selectionClick, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/board_meetup_card.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| BoardMeetupCard.build:101 | onTap | InkWell | isHanyangLocked ? null : onTap, child: Padding( padding: EdgeInsets.symmetric( horizontal: isHanyangLocked ? horizontal : 0, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| BoardMeetupCard.build:251 | onTap | InkWell | onLocationTap, ), ), const SizedBox(height: 7), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _InlineMeta.build:412 | onTap | GestureDetector | onTap, child: content, ), ); | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/ui/widgets/category_create_shortcut_bar.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _CategoryCreateShortcut.build:101 | onTap | InkWell | onTap, child: ConstrainedBox( constraints: const BoxConstraints(minHeight: 64), child: MediaQuery.withClampedTextScaling( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/chat_reaction_widgets.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| ChatReactionPickerRow.build:106 | onTap | InkResponse | () => onSelected(emoji), radius: 24, child: ConstrainedBox( constraints: const BoxConstraints( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| ChatReactionBar.build:197 | onTap | InkWell | () => onToggle(emoji), onLongPress: () => onShowUsers(emoji), borderRadius: BorderRadius.circular(14), child: ConstrainedBox( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| ChatReactionBar.build:198 | onLongPress | InkWell | () => onShowUsers(emoji), borderRadius: BorderRadius.circular(14), child: ConstrainedBox( constraints: const BoxConstraints(minHeight: 30), | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/ui/widgets/compact_header.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| CompactSearchBar.build:94 | onChanged | TextField | onChanged, enabled: enabled, style: theme.textTheme.bodyMedium?.copyWith( height: context.isLargeTextScale | input / text | intentionally_static | IME·선택·링크의 입력 State를 모션으로 재생성하지 않음 |
| CompactSearchBar.build:137 | onPressed | AppIconButton | onClearPressed, semanticLabel: '검색어 지우기', iconColor: colorScheme.onSurfaceVariant, ), | AppIconButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _CompactChip.build:363 | onTap | InkWell | onTap != null ? () { context.accessibleFeedback( HapticFeedbackType.selectionClick, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| CompactCard.build:450 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(DesignTokens.r16), child: Padding(padding: effectivePadding, child: child), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/dynamic_color_widget.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| DynamicColorCard.build:262 | onTap | InkWell | onTap, child: Padding( padding: padding ?? const EdgeInsets.all(20), child: child, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| DynamicColorFab.build:292 | onPressed | FloatingActionButton | onPressed, backgroundColor: Colors.transparent, elevation: 0, label: Container( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| DynamicColorFab.build:327 | onPressed | FloatingActionButton | onPressed, backgroundColor: Colors.transparent, elevation: 0, child: Container( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _DynamicColorToggleState.build:438 | onChanged | Switch | (value) { setState(() { _isDynamicEnabled = value; }); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/empty_state.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| AppEmptyState._buildActionButtons:302 | onPressed | ElevatedButton | onCtaPressed, icon: ctaIcon != null ? Icon(ctaIcon!, size: 20) : const SizedBox.shrink(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| AppEmptyState._buildActionButtons:320 | onPressed | OutlinedButton | onSecondaryCtaPressed, style: ComponentStyles.secondaryButton, child: Text(secondaryCtaText!), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| AppEmptyStateCompact.build:367 | onPressed | TextButton | onActionPressed, child: Text(actionText!)), ], ], ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| AppErrorState.build:450 | onPressed | FilledButton | onRetry, icon: const Icon(Icons.refresh, size: 20), label: Text(retryText!), style: FilledButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| AppPermissionState.build:544 | onPressed | FilledButton | onRequestPermission, icon: const Icon(Icons.check_circle, size: 20), label: Text(permissionText), style: FilledButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/enhanced_comment_widget.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _EnhancedCommentWidgetState._showReportDialog:384 | onPressed | TextButton | () => Navigator.pop(context, false), style: TextButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EnhancedCommentWidgetState._showReportDialog:408 | onPressed | ElevatedButton | () => Navigator.pop(context, true), style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 12), backgroundColor: const Color(0xFFEF4444), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EnhancedCommentWidgetState._showDeleteConfirmDialog:576 | onPressed | TextButton | () { HapticFeedback.lightImpact(); Navigator.pop(dialogContext, false); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EnhancedCommentWidgetState._showDeleteConfirmDialog:592 | onPressed | TextButton | () { HapticFeedback.mediumImpact(); Navigator.pop(dialogContext, true); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EnhancedCommentWidgetState._buildHiddenCommentPlaceholder:652 | onLongPress | GestureDetector | _confirmUnhideAnonymousComment, child: Container( margin: EdgeInsets.only( left: 16.0 + (widget.comment.depth * 20.0), | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _EnhancedCommentWidgetState._confirmUnhideAnonymousComment:760 | onPressed | TextButton | () => Navigator.of(context).pop(false), style: TextButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EnhancedCommentWidgetState._confirmUnhideAnonymousComment:785 | onPressed | ElevatedButton | () => Navigator.of(context).pop(true), style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 12), backgroundColor: const Color(0xFF6366F1), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EnhancedCommentWidgetState._toggleLike:915 | onTap | InkWell | () => setState(() => _showReplies = !_showReplies), child: Row( mainAxisSize: MainAxisSize.min, children: [ | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _EnhancedCommentWidgetState.buildContent:1098 | onLongPress | GestureDetector | () { // 길게 누르면: // - 내 댓글: 액션 시트 // - 익명 게시글의 타인 댓글: 신고/댓글차단 액션 시트 | 원래 댓글 long press | intentionally_static | 본문/전체 행 정적; 프로필 등 독립 액션만 로컬 motion |
| _EnhancedCommentWidgetState.buildContent:1136 | onTap | GestureDetector | isDeletedAccount \|\| widget.directInteractionBlocked ? null : _openCommentAuthorProfile, child: Container( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _EnhancedCommentWidgetState.buildContent:1193 | onTap | GestureDetector | isDeletedAccount \|\| widget.directInteractionBlocked ? null : _openCommentAuthorProfile, child: Text( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _EnhancedCommentWidgetState.buildContent:1298 | onTap | InkWell | widget.directInteractionBlocked && !isLiked ? null : _toggleLike, customBorder: const CircleBorder(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _ActionRow.build:1430 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(18), child: Padding( padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PostCommentGifState.build:1510 | onPressed | TextButton | () => setState(_load), icon: const Icon(Icons.refresh_rounded), label: Text(SnapshotStrings.of(context).commentGifUnavailable), ); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/enhanced_fab.dart — 운영 진입 미발견</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _EnhancedFabState.build:338 | onTapUp | GestureDetector | _handleTapUp, onTapCancel: _handleTapCancel, onTap: widget.enabled ? widget.onPressed : null, child: AnimatedBuilder( | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _EnhancedFabState.build:340 | onTap | GestureDetector | widget.enabled ? widget.onPressed : null, child: AnimatedBuilder( animation: Listenable.merge([ _pressAnimationController, | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _EnhancedFabState.build:340 | onPressed | GestureDetector | null, child: AnimatedBuilder( animation: Listenable.merge([ _pressAnimationController, | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _EnhancedFabState.build:393 | onTap | InkWell | widget.enabled ? widget.onPressed : null, child: Padding( padding: const EdgeInsets.symmetric(horizontal: 4), child: fabContent, | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _EnhancedFabState.build:393 | onPressed | InkWell | null, child: Padding( padding: const EdgeInsets.symmetric(horizontal: 4), child: fabContent, | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _SocialMediaFabState.build:533 | onTap | GestureDetector | () => widget.onToggle?.call(false), child: Container( color: Colors.black.withOpacity(0.3), ), | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |

</details>

<details>
<summary>lib/ui/widgets/fullscreen_file_image_viewer.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _FullscreenFileImageViewerState.build:172 | onDoubleTap | GestureDetector | () => _onDoubleTap(index), child: Center( child: Hero( tag: (widget.heroTag != null && index == widget.initialIndex) | staticGesture | intentionally_static | 기존 scroll·zoom·입력 해제·재생 gesture 보존 |
| _FullscreenFileImageViewerState.build:209 | onPressed | IconButton | () => Navigator.of(context).pop(false), icon: const Icon(Icons.close, color: Colors.white, size: 24), ), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FullscreenFileImageViewerState.build:256 | onPressed | ElevatedButton | () => Navigator.of(context).pop(true), style: ElevatedButton.styleFrom( backgroundColor: const Color(0xFF4A90E2), foregroundColor: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/fullscreen_image_viewer.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _FullscreenImageViewerState._imageAt:621 | onPressed | IconButton | () => _retryStorageImage(index), tooltip: (isChineseUi(context) ? '重新加载图片' : _isKorean | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FullscreenImageViewerState.build:683 | onDoubleTap | GestureDetector | () => _onDoubleTap(index), child: Center( child: Hero( // heroTag가 주어졌다면 "처음 열린 이미지"에서만 그대로 사용해 | staticGesture | intentionally_static | 기존 scroll·zoom·입력 해제·재생 gesture 보존 |
| _FullscreenImageViewerState.build:712 | onPressed | IconButton | () => Navigator.of(context).pop(), icon: const Icon( Icons.close, color: Colors.white, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _FullscreenImageViewerState.build:768 | onPressed | IconButton | _isSaving ? null : _saveCurrentImage, tooltip: (isChineseUi(context) ? '保存图片' : _isKorean | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/glassmorphism_container.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| GlassmorphismContainer.build:245 | onTap | InkWell | onTap, child: container, ), ); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/hanyang_verification_gate.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _VerificationButton.build:356 | onPressed | TextButton | onPressed, style: TextButton.styleFrom( foregroundColor: Colors.white, backgroundColor: AppColors.pointColor, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/instagram_embed_preview.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _InstagramEmbedPreviewState.build:331 | onTap | InkWell | _openInstagram, borderRadius: BorderRadius.circular(14), ), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _InstagramEmbedPreviewState._buildLocalImage:376 | onTap | InkWell | _openInstagram, borderRadius: BorderRadius.circular(14), ), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _InstagramEmbedPreviewState._removeButton:465 | onPressed | IconButton | widget.onRemove, visualDensity: VisualDensity.compact, tooltip: MaterialLocalizations.of(context).deleteButtonTooltip, icon: const Icon(Icons.close_rounded, size: 19, color: Colors | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/optimized_post_card.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _OptimizedPostCardState._showPostLikesSheet:485 | onTap | ListTile | u.isDeletedAccount ? null : () { Navigator.pop(context); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OptimizedPostCardState.build:706 | onTap | InkWell | isHanyangLocked ? null : widget.onTap, child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OptimizedPostCardState.content:1003 | onTap | GestureDetector | canOpenProfile ? () { _openProfileOrMyPage( userId: post.userId, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _OptimizedPostCardState.content:1076 | onTap | GestureDetector | canOpenProfile ? () => _openProfileOrMyPage( userId: post.userId, nickname: displayNickname, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _OptimizedPostCardState._buildPostCategoryTags:1259 | onTap | GestureDetector | widget.onCategoryTap == null ? null : () => widget.onCategoryTap!(category), child: Text( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _OptimizedPostCardState._openPostActionsSheet:1581 | onTap | ListTile | () async { Navigator.pop(sheetContext); await _openDM(post); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OptimizedPostCardState._openPostActionsSheet:1601 | onTap | ListTile | () async { Navigator.pop(sheetContext); final headline = post.displayText.split('\n').first.trim(); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OptimizedPostCardState._openPostActionsSheet:1629 | onTap | ListTile | () async { Navigator.pop(sheetContext); if (post.isAnonymous) { final isKo = | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OptimizedPostCardState._openPostActionsSheet:1648 | onPressed | TextButton | () => Navigator.of(context).pop(false), child: Text((isChineseUi(context) ? '取消' : isKo ? '취소' : 'Cancel')), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _OptimizedPostCardState._openPostActionsSheet:1653 | onPressed | ElevatedButton | () => Navigator.of(context).pop(true), child: Text((isChineseUi(context) ? '屏蔽' : isKo ? '차단' : 'Block')), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/poll_post_widget.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _PollPostWidgetState.contentForVote:193 | onTap | InkWell | user == null ? null : () { setState(() => _selectedOptionId = id); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PollPostWidgetState.contentForVote:239 | onPressed | ElevatedButton |  (user == null \|\| _selectedOptionId == null \|\| _isVoting) ? null : () async { | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/post_action_group.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| PostActionGroup.build:107 | onTapUp | GestureDetector | onLikeTapUp, child: _PostActionItem( icon: animateLike ? null : likeIcon, iconWidget: animateLike | 기존 likeAction MotionPress | custom_applied | likeButton 변수를 실제 likeAction wrapper로 전달; onTapUp/longPress 유지 |
| PostActionGroup.build:175 | onTap | GestureDetector | onCommentTap, child: _PostActionItem( icon: Icons.chat_bubble_outline_rounded, iconColor: actionColor, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| PostActionGroup.build:226 | onTap | GestureDetector | onDirectMessageTap, child: _PostActionItem( iconWidget: Transform.rotate( angle: -math.pi / 4, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| PostActionGroup.build:255 | onTap | GestureDetector | isSaving ? null : onSaveTap, child: _PostSelectionPulse( selected: isSaved, activePeak: 1.18, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/ui/widgets/post_category_explorer.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| PostCategoryTile.build:204 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(DesignTokens.r12), child: standardContent, ); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/post_category_selector.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| PostCategoryTagChip.build:146 | onTap | InkWell | enabled ? onTap : null, borderRadius: BorderRadius.circular(18), child: ConstrainedBox( constraints: BoxConstraints(minHeight: 40, maxWidth: maxWidth), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| PostCategoryTagChip.build:146 | onTap | InkWell | null, borderRadius: BorderRadius.circular(18), child: ConstrainedBox( constraints: BoxConstraints(minHeight: 40, maxWidth: maxWidth), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/post_friend_request_button.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _PostFriendRequestButtonState.build:117 | onPressed | RelationshipActionButton | _sending ? null : _sendRequest, ); }, ); | RelationshipActionButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/ui/widgets/profile_image_viewer.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _ProfileImageViewerState.build:184 | onDoubleTap | GestureDetector | _onDoubleTap, child: Hero( tag: widget.heroTag, child: ClipRRect( | staticGesture | intentionally_static | 기존 scroll·zoom·입력 해제·재생 gesture 보존 |
| _ProfileImageViewerState.build:253 | onTap | InkWell | () => Navigator.of(context).pop(), borderRadius: BorderRadius.circular(24), child: Container( padding: const EdgeInsets.all(8), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/shared_link_preview_card.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| SharedLinkPreviewCard.build:166 | onTap | InkWell | _openLink, borderRadius: BorderRadius.circular(14), child: Column( crossAxisAlignment: CrossAxisAlignment.start, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SharedLinkPreviewCard.build:300 | onPressed | IconButton | onRemove, visualDensity: VisualDensity.compact, tooltip: MaterialLocalizations.of(context) .deleteButtonTooltip, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SharedLinkPreviewCard._buildCompactInstagramMetadata:371 | onPressed | IconButton | onRemove, visualDensity: VisualDensity.compact, tooltip: MaterialLocalizations.of(context).deleteButtonTooltip, icon: const Icon( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SharedLinkPreviewCard._buildInstagramLinkCard:407 | onTap | InkWell | _openLink, child: Column( crossAxisAlignment: CrossAxisAlignment.stretch, children: [ | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SharedLinkPreviewCard._buildInstagramLinkCard:484 | onPressed | IconButton | onRemove, visualDensity: VisualDensity.compact, tooltip: MaterialLocalizations.of(context).deleteButtonTooltip, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/snack_chat_card.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| SnackChatCard.build:203 | onTap | InkWell | onTap, onLongPress: onLongPress, child: MediaQuery.withClampedTextScaling( maxScaleFactor: 1.3, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SnackChatCard.build:204 | onLongPress | InkWell | onLongPress, child: MediaQuery.withClampedTextScaling( maxScaleFactor: 1.3, child: Container( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SnackChatCard.build:383 | onTap | InkResponse | onToggleFavorite, radius: 22, child: Center( child: AnimatedSwitcher( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SnackChatCard._buildPastCard:448 | onTap | InkWell | onTap, child: Padding( padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SnackChatCard._buildPastCard:492 | onPressed | IconButton | onToggleFavorite, tooltip: (isChineseUi(context) ? '取消收藏' : isKo | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SnackChatCard._buildPastCard:503 | onPressed | OutlinedButton | onTap, style: OutlinedButton.styleFrom( foregroundColor: BrandColors.textPrimary, side: const BorderSide(color: BrandColors.divider), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/snack_chat_mention_picker.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SnackChatMentionPickerState.build:271 | onPressed | TextButton | () => _primeParticipants(forceRefresh: true), child: Text(_localized('다시 시도', '重试', 'Retry')), ), ); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatMentionPickerState.buildRow:303 | onTap | InkWell | () { widget.controller.insertMention(person.id, displayName); widget.focusNode.requestFocus(); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/snack_chat_message_extras.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SnackChatStorageImageState.build:220 | onPressed | IconButton | _retrying ? null : _retry, padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor( width: 32, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SnackChatReplyPreviewView.build:453 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(8), child: Padding( padding: const EdgeInsets.only(bottom: 7), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SnackChatPollCard._buildCard:640 | onTap | InkWell | !canVote ? null : () { final next = <String>{...myOptionIds}; | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SnackChatLinkPreviewCard.build:816 | onTap | InkWell | onOpen, borderRadius: BorderRadius.circular(8), child: Padding( padding: const EdgeInsets.symmetric(vertical: 3), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SnackChatLinkPreviewCard.build:885 | onPressed | IconButton | onRemove, tooltip: '미리보기 제거', visualDensity: VisualDensity.compact, constraints: const BoxConstraints.tightFor( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/snack_chat_participant_picker.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SnackChatParticipantPickerState.build:323 | onPressed | IconButton |  _tabController.index == 1 ? _submitSearch : null, padding: EdgeInsets.zero, icon: Icon( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatParticipantPickerState.build:342 | onPressed | IconButton | _searchController.clear, icon: Icon( Icons.close_rounded, size: context.ri(18).clamp(17, 20).toDouble(), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SnackChatParticipantPickerState._buildDirectoryResult:486 | onPressed | TextButton | () => _searchDirectory( _query, loadMore: true, ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SelectedParticipantStrip.build:592 | onTap | GestureDetector | () => onRemove(profile), child: SizedBox( width: itemWidth, child: Column( | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| _ParticipantTile.build:667 | onTap | Semantics | onTap, excludeSemantics: true, child: Material( color: Colors.transparent, | semantics delegation | intentionally_static | 동일 액션의 접근성 위임; 별도 버튼으로 중복 집계하지 않음 |
| _ParticipantTile.build:672 | onTap | InkWell | onTap, child: Padding( padding: EdgeInsets.symmetric( horizontal: 0, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _PickerMessage.build:866 | onPressed | TextButton | onAction, style: TextButton.styleFrom( foregroundColor: const Color(0xFF344054), minimumSize: const Size(44, 40), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/social_interactions.dart — 운영 진입 미발견</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SocialActionButtonState.build:231 | onTap | GestureDetector | _handleTap, child: AnimatedBuilder( animation: _animationController, builder: (context, child) { | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _SocialCommentInputState.build:612 | onTap | GestureDetector | _hasText ? _handleSend : null, child: Container( width: 36, height: 36, | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |

</details>

<details>
<summary>lib/ui/widgets/soft_translate_reveal.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SoftTranslateRevealState.build:193 | onTap | InkWell | widget.onRetry, borderRadius: BorderRadius.circular(8), child: Padding( padding: const EdgeInsets.only(top: 3, right: 4, bottom: 3), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/ui/widgets/story_categories.dart — 운영 진입 미발견</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _StoryCategoryItemState.build:272 | onTapUp | GestureDetector | _handleTapUp, onTapCancel: _handleTapCancel, onTap: widget.onTap, child: AnimatedBuilder( | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _StoryCategoryItemState.build:274 | onTap | GestureDetector | widget.onTap, child: AnimatedBuilder( animation: _animationController, builder: (context, child) { | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |

</details>

<details>
<summary>lib/ui/widgets/translatable_content.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _TranslatableContentState.build:406 | onTap | InkWell | canToggle ? () => _service.requestOrToggleScope(widget.scope) : retryAvailable ? () => unawaited(_retryManually()) | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TranslationScopeToggleState.build:573 | onPressed | TextButton | canToggle \|\| retryAvailable ? () => service.requestOrToggleScope(scope) : null, style: TextButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TranslationScopeToggleState.build:616 | onPressed | TextButton | retryAvailable ? () => service.retryOneFailedScopeItem(scope) : null, style: TextButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TranslationScopeToggleState.build:649 | onTap | InkWell | canToggle \|\| retryAvailable ? () => service.requestOrToggleScope(scope) : null, borderRadius: BorderRadius.circular(6), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TranslationScopeToggleState.build:711 | onTap | InkWell | retryAvailable ? () => service.retryOneFailedScopeItem(scope) : null, borderRadius: BorderRadius.circular(6), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TranslationScopeToggleState.build:758 | onTap | InkResponse | widget.onSettingsPressed, radius: 16, child: const SizedBox.square( dimension: 28, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TranslationScopeToggleState.build:781 | onPressed | TextButton | canToggle \|\| retryAvailable ? () => service.requestOrToggleScope(scope) : null, style: TextButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _TranslationScopeToggleState.build:803 | onPressed | TextButton | retryAvailable ? () => service.retryOneFailedScopeItem(scope) : null, style: TextButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/widgets/ad_banner_widget.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _AdBannerWidgetState._buildBannerContent:259 | onTap | GestureDetector | () { // 광고 목록 페이지에서 사용자가 누른 광고 위치로 바로 이동한다. Navigator.push( context, | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/widgets/adaptive_bottom_navigation.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| AdaptiveBottomNavigation._buildNavItem:196 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(12), splashColor: colorScheme.primary.withValues(alpha: 0.1), highlightColor: colorScheme.primary.withValues(alpha: 0.05), | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/widgets/date_selector.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| DateSelector.build:31 | onTap | InkWell | () => onDateSelected(index), borderRadius: BorderRadius.circular(12), child: AnimatedContainer( duration: const Duration(milliseconds: 150), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/widgets/day_meetup_list.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| DayMeetupList.build:43 | onPressed | ElevatedButton | () { // 부모 위젯으로부터 전달받은 콜백 함수 실행 onCreateMeetup(context); }, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/widgets/friend_category_selector.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| FriendCategorySelector.build:75 | onTap | InkWell | () { _toggle(category.id); }, borderRadius: BorderRadius.circular(24), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _CategoryListItem.build:160 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(12), child: AnimatedContainer( duration: const Duration(milliseconds: 180), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/widgets/highlight_reels.dart — 운영 진입 미발견</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| HighlightReels._buildHighlightItem:81 | onTap | GestureDetector | () => onHighlightTap?.call(highlight), child: Container( width: 64, height: 64, | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| HighlightReels._buildAddButton:161 | onTap | GestureDetector | onAddHighlight, child: Container( width: 64, height: 64, | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _CreateHighlightDialogState.build:243 | onPressed | TextButton | () => Navigator.pop(context), child: const Text('취소'), ), ElevatedButton( | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| _CreateHighlightDialogState.build:247 | onPressed | ElevatedButton | () { final title = _titleController.text.trim(); if (title.isNotEmpty) { widget.onCreateHighlight?.call(title); | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |

</details>

<details>
<summary>lib/widgets/meetup_card.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| MeetupCard.build:162 | onTap | InkWell | () async { // 모임 상세 화면 표시 final user = FirebaseAuth.instance.currentUser; if (user != null) { | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| MeetupCard._buildMeetupContent:352 | onPressed | ElevatedButton | isFull ? null : () async { final user = FirebaseAuth.instance.currentUser; | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/widgets/notification_list_item.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| NotificationListItem._buildContent:88 | onTap | InkWell | onTap, child: Padding( padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/widgets/post_grid.dart — 운영 진입 미발견</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _PostGridState._buildGridItem:172 | onTap | GestureDetector | () => widget.onPostTap?.call(post), child: Container( decoration: BoxDecoration( color: Colors.grey[100], | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |
| PostDisplayModeToggle._buildModeButton:396 | onTap | GestureDetector | () => onModeChanged(mode), child: Container( height: 44, decoration: BoxDecoration( | 운영 진입 미발견 | intentionally_static | 현재 production 외부 생성 호출 미발견; 보조/중복 화면을 활성 경로처럼 수정하지 않음 |

</details>

<details>
<summary>lib/widgets/post_search_card.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| PostSearchCard.build:54 | onTap | InkWell | isHanyangLocked ? null : () { Navigator.push( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/widgets/profile_action_buttons.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| ProfileActionButtons._buildActionButton:170 | onPressed | ElevatedButton | () { _handleButtonTap(onTap); }, style: ElevatedButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| ProfileActionButtons._buildActionButton:202 | onPressed | OutlinedButton | () { _handleButtonTap(onTap); }, style: OutlinedButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| ProfileActionButtons._buildIconButton:251 | onPressed | OutlinedButton | () { _handleButtonTap(onTap); }, style: OutlinedButton.styleFrom( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| ProfileMoreActionsSheet._buildActionItem:403 | onTap | ListTile | () { Navigator.pop(context); HapticFeedback.lightImpact(); onTap?.call(); | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/widgets/profile_header.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| ProfileHeader._buildActionButtons:214 | onPressed | OutlinedButton | onEditProfile, style: OutlinedButton.styleFrom( shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(18), // 18dp radius | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| ProfileHeader._buildActionButtons:252 | onPressed | ElevatedButton | isEnabled ? onRelationshipAction : null, style: ElevatedButton.styleFrom( backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| ProfileHeader._buildActionButtons:282 | onPressed | OutlinedButton | isEnabled ? onRelationshipAction : null, style: OutlinedButton.styleFrom( foregroundColor: colorScheme.onSurface, side: BorderSide( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| ProfileHeader._buildActionButtons:323 | onPressed | OutlinedButton | canSendMessage ? onMessage : null, style: OutlinedButton.styleFrom( shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(18), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/widgets/relationship_action_button.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| RelationshipActionButton.build:38 | onPressed | FilledButton | onPressed, style: FilledButton.styleFrom( backgroundColor: isPrimary ? AppColors.pointColor : const Color(0xFFF2F4F7), | MotionPress | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/widgets/semester_todo_app_bar_button.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| _SemesterTodoAppBarButtonState.build:82 | onPressed | AppIconButton | _open, semanticLabel: (isChineseUi(context) ? '学期待办' : korean ? '학기 To-do List' : 'Semester To-do List'), visualDensity: VisualDensity.compact, ), | AppIconButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |

</details>

<details>
<summary>lib/widgets/signup_flow_widgets.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| SignupPrimaryButton.build:240 | onPressed | ElevatedButton | onPressed, style: ElevatedButton.styleFrom( elevation: 0, backgroundColor: AppColors.pointColor, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SignupInlineError.showSignupExitConfirmation:327 | onPressed | TextButton | () => Navigator.pop(dialogContext, false), child: Text((isChineseUi(context) ? '继续注册' : isKorean ? '계속 가입' : 'Keep signing up')), ), TextButton( | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SignupInlineError.showSignupExitConfirmation:331 | onPressed | TextButton | () => Navigator.pop(dialogContext, true), style: TextButton.styleFrom( foregroundColor: const Color(0xFFDC2626), ), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/widgets/social_profile_fields.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| SocialProfileTagSelector.build:103 | onTap | InkWell | () { final next = List<String>.of(selectedIds); if (!selected) { if (next.length >= maxSelection) { | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| _SocialProfilePromptFieldState._optionRow:276 | onTap | InkWell | onTap, borderRadius: BorderRadius.circular(10), child: Padding( padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 11), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>

<details>
<summary>lib/widgets/user_tile.dart</summary>

| 파일:심볼:줄 | callback | 컨트롤/공통 | callback·조건 발췌 | profile | 분류 | 근거/이유 |
| --- | --- | --- | --- | --- | --- | --- |
| UserTile.build:56 | onTap | InkWell | onTilePressed, child: Padding( padding: EdgeInsets.fromLTRB( horizontalPadding, | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| UserTile.build:111 | onTap | InkWell | onTilePressed, borderRadius: BorderRadius.circular(12), child: Padding( padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| UserTile._buildActionButton:303 | onPressed | RelationshipActionButton | onRejectPressed, tone: RelationshipActionButtonTone.neutral, ); final acceptButton = RelationshipActionButton( | RelationshipActionButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| UserTile._buildActionButton:308 | onPressed | RelationshipActionButton | onActionPressed, );  if (!compact) { | RelationshipActionButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| UserTile._buildActionButton:341 | onPressed | RelationshipActionButton | relationshipStatus.isActionable ? onActionPressed : null, tone: isPrimaryAction ? RelationshipActionButtonTone.primary : RelationshipActionButtonTone.neutral, | RelationshipActionButton | custom_applied | callback을 기존 wrapper에 연결; 실제 서비스 결과는 별도 |
| UserTile._buildActionButton:349 | onPressed | ElevatedButton | relationshipStatus.isActionable ? onActionPressed : null, style: ElevatedButton.styleFrom( backgroundColor: Color(buttonStyle['color'] as int), foregroundColor: Color(buttonStyle[' | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |
| SimpleUserTile.build:465 | onTap | ListTile | onPressed, ); } } | native state layer / control | native_preserved | 기존 Flutter 컨트롤 피드백/callback 유지 |

</details>
