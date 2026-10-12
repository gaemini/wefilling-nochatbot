# 영상 첨부(포스트·스낵챗·DM) 설계 기록 (2026-10-07)

## 한도와 비용 근거

| 컨텍스트 | 길이 | 압축 | 결과 크기 상한 | 보관 |
|---|---|---|---|---|
| 포스트 | 60초 | 720p (`VideoQuality.Res1280x720Quality`), 30fps | 40MB | 게시글 삭제 시 서버 트리거가 삭제 |
| 스낵챗 | 60초 | 540p (`Res960x540Quality`) | 20MB (기존 파일 한도) | 24h/영구 방 정책 그대로(`snack_chat_files/{mode}/…` 기존 만료·정리 트리거) |
| DM | 60초 | 540p | 20MB | 메시지 문서 삭제 시 서버 트리거가 객체 삭제(신규) |

Firebase Storage(서울) 보관 $0.026/GB·월, 다운로드 $0.12/GB 기준. 60초·720p 클립은 보통 10~25MB다.
보관보다 재생 다운로드 비용이 지배적이라 (1) 길이·해상도로 파일 크기를 묶고, (2) 기기별로 한 번만 내려받아
`AppVideoCacheManager`(30개·400MB·7일 LRU)에서 재생하며, (3) 피드에서는 카드가 60% 이상 보이고 250ms 머문
뒤에만 내려받아 빠른 스크롤에는 다운로드하지 않는다. 채팅 영상은 자동 재생하지 않고 탭할 때만 내려받는다.

값은 한 곳에서 바꾼다: `lib/services/media/video_upload_policy.dart`(클라이언트)와 `functions/src/video_policy.ts`,
`functions/src/snack_chat.ts`(`mp4`, `SNACK_CHAT_VIDEO_MAX_DURATION_MS`), Rules의 크기 상수.

## 데이터 흐름

### 포스트
1. 작성 화면에서 사진·영상을 한 피커로 고른다(Android `pickMultipleMedia`, iOS `AssetPicker` common).
   영상은 1개만, `VideoPrepareService.prepare`가 길이·원본 크기 검사 → 압축 → 결과 크기 검사 → 썸네일.
2. 제출 시 `StorageService.uploadPostVideo`가 `post_videos/{uid}/{postId}/video.mp4`와 `thumbnail.jpg`를
   `ownerUid`/`postId` metadata와 함께 올린다(Storage 규칙: 본인 폴더, MP4 40MB, JPEG 2MB).
3. `createPostSecure`가 `video: {storagePath, thumbnailPath, storageBucket}`를 받아 존재·MIME·크기·소유자
   metadata를 확인하고 파일을 내려받아 mp4box로 길이(≤60초)를 검증한 뒤 다운로드 토큰을 발급해
   `posts.video = {url, storagePath, storageBucket, thumbnailUrl, thumbnailPath, durationMs, width, height, bytes}`로
   저장한다. 썸네일 URL은 `imageUrls[0]`에도 넣어 프로필 그리드·알림·저장함의 기존 썸네일 경로가 그대로 동작한다.
   검증 실패 시 올라온 객체를 지우고 거부한다. 작성자는 게시 후 `video` 필드를 바꿀 수 없다(Rules).
4. 피드 카드·상세는 `FeedVideoPlayer`로 렌더링한다: 화면의 60% 이상 보이면 무음 자동 재생, 30% 아래면 정지,
   한 번에 하나만 재생, 탭/스피커로 소리 켜기(세션 동안 유지). 영상이 있으면 이미지 슬라이더에서 썸네일을 뺀다.
5. 삭제: `onPostDeletedStorageCleanup`이 `post_videos/{uid}/{postId}/`, `post_link_previews/{uid}/{postId}/`,
   `posts/` 이미지(URL 경로)를 지운다. 수정으로 뺀 이미지는 `onPostUpdatedStorageCleanup`이 지운다.
   (이전에는 게시글 이미지가 삭제되지 않고 남았다.) 생성 실패 롤백은 게시글 문서가 없을 때만 업로더가
   `post_videos`를 직접 지울 수 있다.

### 스낵챗
- 첨부 시트의 "이미지" → `pickMedia`(사진·영상 함께). 영상이면 `_sendPickedVideo`: 압축 → 썸네일(16KB data URL)
  → `SnackChatFilePolicy.validatePath`(mp4 `ftyp` 서명) → 기존 파일 전송 큐 `enqueueFiles`.
- 서버 `commitSnackChatFileUpload`가 `videoMeta`(길이·해상도·썸네일)를 검증해 메시지에
  `videoDurationMs/videoWidth/videoHeight/videoThumbnail`로 저장하고, 미리보기는 `🎬 이름`.
  내용 검사는 MP4 `ftyp`만 허용. 만료·삭제는 기존 파일 트리거/스윕이 그대로 처리한다.
- 말풍선은 `ChatVideoTile`(썸네일·길이), 탭하면 `VideoPlaybackScreen`(인증 다운로드 1회, 캐시 재생).

### DM
- 갤러리 선택이 `pickMedia`로 바뀌어 사진·영상을 함께 고른다. 영상은 파일 메시지(`type: file`,
  `fileMimeType: video/mp4`)로 보내며 Rules `validDmVideoMeta`가 길이(≤60.5초)·해상도·썸네일(data URL 16KB)을
  검증한다. 문서 파일에는 영상 메타가 있을 수 없다.
- 신규 `onDMMessageDeletedStorageCleanup`: 메시지 문서가 지워지면 `dm_files/…`, `dm_images/…` 객체를 삭제한다.

## 키보드 겹침 수정
스낵챗·DM의 `_showAttachmentOptions`가 첨부 시트를 열기 전에 입력창 포커스를 내린다
(시트는 `requestFocus: false`라 스스로 키보드를 닫지 않았다).

## 저장공간·캐시
- 압축 임시 파일: `VideoPrepareService.cleanupCompressionCache()`(스낵챗·DM은 `stageForSend` 직후, 포스트는
  작성 화면 dispose 시).
- 기기 영상 캐시: `AppVideoCacheManager` 30개/400MB/7일 LRU, 재생 중 파일은 보호, 로그아웃 시 비움
  (`CacheManager.clearAll`).
- 서버: 포스트 미디어 삭제 트리거 2개, DM 첨부 삭제 트리거 1개 신규.

## 검증
- `functions`: tsc 빌드·eslint 통과.
- Firestore 에뮬레이터: `test_security_rules_emulator.js` 62건(DM 영상 메타 허용/거부 5건 추가),
  `test_chat_delivery_emulator.js`, `test_dm_read_boundary_emulator.js`, `test_notification_read_emulator.js` 통과.
  Storage 규칙 컴파일 통과.
- `flutter analyze` 변경 파일 오류 0, `snack_chat_attachment_sheet_test`, `snack_chat_file_policy_test` 통과.
- 실기기 미검증: 실제 압축 시간(기기별), 피커 동작(Android 포토 피커/iOS AssetPicker common), 자동 재생 전환,
  소리 토글, 캐시 적중. 배포 전 두 기기로 포스트 1개·스낵챗 1개·DM 1개 영상 왕복 확인 필요.

## iOS·Android 안정화 (2026-10-07 2차)

측정: iPhone 4K HEVC 원본 3개를 `avconvert`(앱과 같은 AVAssetExportSession 프리셋)로 변환한 결과 iOS
1280x720 7.7~7.9Mbps(60초 약 56MB), 960x540 5.1Mbps(약 36MB), 640x480 2.7Mbps(약 19MB, 실제 360x640),
Medium 1.0Mbps(320x568). Android Transcoder 0.10.5는 영상 0.14×가로×세로×30fps(720p 3.87Mbps)에 AAC 최대
약 0.96Mbps. 그래서 iOS 포스트 60초와 양쪽 채팅 60초가 한도를 넘었다.

- 압축 프리셋 사다리(`VideoUploadLimits.iosQualities/androidQualities`)와 `VideoUploadPolicy.qualitiesToTry`:
  길이로 결과 크기를 추정해 한도(95%) 안에 드는 첫 프리셋부터 압축하고, 실제 결과가 넘으면 다음 프리셋으로.
  iOS 포스트는 약 37초까지 720p, 그 뒤 540p/480p. 채팅 Android 60초는 640x480.
- `frameRate` 인자 제거: iOS 플러그인이 frameRate가 있으면 AVMutableVideoComposition을 붙이는 경로를 탄다.
- 원본 그대로 올리기(압축 생략)는 H.264 MP4일 때만(파일 양 끝 2MB에서 stsd 샘플 엔트리 확인). HEVC는 구형
  Android가 재생하지 못한다. 압축이 전부 실패해도 H.264 MP4가 아니면 거부한다.
- 가로·세로: video_compress의 MediaInfo는 Android에서 회전 판정이 뒤집혀 있고 iOS는 회전 적용 값이다.
  두 플랫폼 모두 회전이 적용되는 썸네일 방향으로 긴 변·짧은 변을 배치한다(채팅 videoMeta, 작성 화면).
- 서버 `inspectMp4`: tkhd 행렬이 90°/270°면 가로·세로를 바꾼다(Android MediaMuxer 출력은 회전 행렬).
  코덱이 avc1/avc3이 아니면 `createPostSecure`가 거부한다.
- 피드 플레이어: `mixWithOthers: true`(무음 자동 재생이 음악을 멈추지 않음), 화면에서 완전히 사라지면
  컨트롤러 해제(디코더 수 제한), 위젯 재사용 시 이전 로드 무효화, 시작 지연 500ms.
- 영상 캐시: `getApplicationCacheDirectory()`(iOS iCloud 백업 제외), 30일, 다운로드 전 폴더 재생성.
- iOS 갤러리에서 영상 파일을 못 가져오면(iCloud 전용·오프라인) 안내를 띄운다.
- 테스트: `test/video_upload_policy_test.dart`.

## 영상+사진 캐러셀 (2026-10-07 3차)

영상과 사진이 함께 있는 포스트는 카드·상세 모두 한 캐러셀에서 넘겨 본다. 영상이 첫 장이고
(`posts.video`는 위치 정보가 없고 썸네일이 `imageUrls[0]`), 캐러셀 높이는 영상 비율을 따른다
(`AdaptivePostImageFrame.knownAspectRatio`, 사진은 contain). 넘기면 영상은 화면 밖으로 나가 멈추고
컨트롤러가 해제되며, 돌아오면 캐시 파일로 다시 재생한다. 영상만 있거나 사진만 있는 포스트는 기존 경로 그대로다.
상세 화면의 페이지 번호는 `imageUrls` 순서(썸네일=영상)와 같아 기존 프리패치가 그대로 맞는다.
테스트: `test/adaptive_post_image_frame_test.dart`.

## 배포 순서
1. `firebase deploy --only storage` (post_videos 경로, mp4 MIME)
2. `firebase deploy --only firestore:rules` (DM 영상 메타, posts.video 보호)
3. Functions: `createPostSecure`, `prepareSnackChatFileUpload`, `commitSnackChatFileUpload`,
   `onSnackChatMessageCreatedSecure`(푸시 문구), `querySnackChatMessages`, `searchPostsSecure`,
   신규 `onPostDeletedStorageCleanup`, `onPostUpdatedStorageCleanup`, `onDMMessageDeletedStorageCleanup`
   — `bash scripts/deploy_functions_keep_existing.sh "functions:…"`로 us-central1 사본 삭제 프롬프트에 "아니오".
4. 앱 빌드(1.3.28+98). 구버전 앱은 영상 메시지를 일반 파일 말풍선(`📎`)으로 보여주고 탭하면 OS 플레이어로 연다.
