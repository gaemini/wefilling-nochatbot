# 안드로이드 푸시 알림 시스템 문서

## 📱 개요

Wefilling 앱의 안드로이드 푸시 알림 시스템은 Firebase Cloud Messaging (FCM)과 Flutter Local Notifications를 사용하여 구현되었습니다.

## 🏗️ 아키텍처

### 1. 알림 흐름

```
서버 (Cloud Functions)
    ↓ FCM 메시지 전송
Firebase Cloud Messaging
    ↓
안드로이드 디바이스
    ↓
앱 상태에 따라 분기:
    ├─ 포그라운드 → FirebaseMessaging.onMessage → 로컬 알림 표시
    ├─ 백그라운드 → firebaseMessagingBackgroundHandler → 시스템 알림
    └─ 종료됨 → FCM 자동 처리 → 시스템 알림
```

### 2. 주요 컴포넌트

#### `fcm_service.dart`
- FCM 토큰 관리 (등록/갱신/삭제)
- 알림 권한 요청
- 메시지 수신 및 처리
- 로컬 알림 표시

#### `notification_service.dart`
- 앱 내 알림 생성 (Firestore)
- 알림 읽음/삭제 처리
- 알림 설정 확인

#### `AndroidManifest.xml`
- 알림 권한 선언
- FCM 기본 채널 설정

## 📢 알림 채널

안드로이드 8.0 (API 26) 이상에서는 알림 채널이 필수입니다.

### 채널 1: High Importance (기본)
- **ID**: `high_importance_channel`
- **이름**: High Importance Notifications
- **설명**: DM, 댓글, 좋아요 등 중요한 알림
- **중요도**: HIGH
- **사운드**: ✅
- **진동**: ✅
- **LED**: ✅ (인디고 #6366F1)

### 채널 2: Meetup
- **ID**: `meetup_notifications`
- **이름**: Meetup Notifications
- **설명**: 모임 참여, 취소, 정원 마감 등 모임 관련 알림
- **중요도**: HIGH
- **사운드**: ✅
- **진동**: ✅
- **LED**: ✅ (그린 #10B981)

## 🔐 권한 처리

### Android 13+ (API 33+)
- `POST_NOTIFICATIONS` 런타임 권한 필수
- 앱 초기화 시 자동으로 권한 요청
- 사용자가 거부한 경우 알림 미표시

### Android 12 이하
- 알림 권한이 자동으로 부여됨
- 사용자가 설정에서 수동으로 비활성화 가능

### 권한 요청 흐름

```dart
// fcm_service.dart
Future<void> initialize(String userId) async {
  // 1. 로컬 알림 초기화 (채널 생성)
  await _initializeLocalNotifications();
  
  // 2. Android 13+ 권한 요청
  if (Platform.isAndroid) {
    await _ensureAndroidPostNotificationsPermission();
  }
  
  // 3. iOS 권한 요청
  await _messaging.requestPermission(...);
  
  // 4. FCM 토큰 동기화
  _startTokenSync(userId);
  
  // 5. 메시지 리스너 등록
  FirebaseMessaging.onMessage.listen(...);
  FirebaseMessaging.onMessageOpenedApp.listen(...);
}
```

## 📨 알림 타입

### DM (Direct Message)
- **type**: `dm_received`
- **채널**: high_importance_channel
- **스타일**: MessagingStyle (Android)
- **그룹화**: conversationId 기반
- **특징**: 대화방 활성 시 알림 미표시

### 댓글
- **type**: `new_comment`
- **채널**: high_importance_channel
- **데이터**: postId, commenterName, postTitle

### 좋아요
- **type**: `new_like`
- **채널**: high_importance_channel
- **데이터**: postId, likerName, postTitle
- **특징**: 익명 게시글은 "익명"으로 표시

### 모임 참여
- **type**: `meetup_participant_joined`
- **채널**: meetup_notifications
- **데이터**: meetupId, meetupTitle, participantName

### 모임 나가기
- **type**: `meetup_participant_left`
- **채널**: meetup_notifications
- **데이터**: meetupId, meetupTitle, participantName

### 모임 정원 마감
- **type**: `meetup_full`
- **채널**: meetup_notifications
- **데이터**: meetupId, meetupTitle, maxParticipants

### 모임 취소
- **type**: `meetup_cancelled`
- **채널**: meetup_notifications
- **데이터**: meetupId, meetupTitle

### Snack Chat 초대
- **type**: `snack_chat_invite`
- **채널**: high_importance_channel
- **데이터**: snackChatId, snackChatName, creatorName

### 후기 관련
- **type**: `review_comment`, `review_approval_request`, `review_published`, `review_rejected`
- **채널**: meetup_notifications
- **데이터**: reviewId, userId, reviewTitle

## 🔄 중복 알림 방지

### 알림 ID 전략

```dart
// DM: 같은 대화의 알림을 하나로 그룹화
conversationId.hashCode

// 모임: 같은 모임의 같은 타입 알림 업데이트
'$meetupId-$type'.hashCode

// 기타: 개별 알림
message.hashCode
```

### UI 레벨 중복 제거

```dart
// notification_service.dart
List<AppNotification> _dedupeForUi(List<AppNotification> list) {
  // 90초 이내 같은 키의 알림은 중복으로 판단하여 제거
  // 키: type|meetupId|postId|actorId|actorName
}
```

## 🎯 백그라운드 처리

### 백그라운드 핸들러

```dart
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 1. Firebase 재초기화
  await Firebase.initializeApp(...);
  
  // 2. 알림 채널 생성
  await androidPlugin?.createNotificationChannel(...);
  
  // 3. data-only 메시지 처리
  if (message.notification == null) {
    await plugin.show(...);
  }
}
```

### 주의사항
- 백그라운드 핸들러는 별도 Isolate에서 실행
- Firebase 재초기화 필요
- 채널이 없으면 알림이 표시되지 않음
- `@pragma('vm:entry-point')` 필수 (트리 쉐이킹 방지)

## 🔧 설정 파일

### `AndroidManifest.xml`

```xml
<!-- 알림 권한 -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="com.google.android.c2dm.permission.RECEIVE" />

<!-- FCM 기본 채널 -->
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="high_importance_channel" />
```

### `pubspec.yaml`

```yaml
dependencies:
  firebase_messaging: ^16.0.2
  flutter_local_notifications: ^18.0.1
  permission_handler: ^11.3.1
  app_badge_plus: ^1.2.6
```

## 🐛 트러블슈팅

### 알림이 표시되지 않음

1. **권한 확인**
   ```dart
   final status = await Permission.notification.status;
   print('알림 권한: $status');
   ```

2. **채널 확인**
   - 설정 > 앱 > Wefilling > 알림
   - 채널이 생성되었는지 확인
   - 채널이 활성화되어 있는지 확인

3. **FCM 토큰 확인**
   ```dart
   final token = await FirebaseMessaging.instance.getToken();
   print('FCM 토큰: $token');
   ```

4. **로그 확인**
   ```bash
   adb logcat | grep -i "fcm\|notification"
   ```

### 중복 알림

- 알림 ID 전략 확인
- UI 레벨 중복 제거 로직 확인
- 서버에서 중복 전송하지 않는지 확인

### 백그라운드 알림 미표시

- `firebaseMessagingBackgroundHandler` 등록 확인
- 채널 생성 확인
- `@pragma('vm:entry-point')` 확인

## 📊 테스트

### FCM 테스트 메시지 전송

Firebase Console > Cloud Messaging > 새 알림 보내기

```json
{
  "notification": {
    "title": "테스트 제목",
    "body": "테스트 내용"
  },
  "data": {
    "type": "test",
    "click_action": "FLUTTER_NOTIFICATION_CLICK"
  },
  "android": {
    "notification": {
      "channel_id": "high_importance_channel"
    }
  }
}
```

### 로컬 테스트

```dart
// fcm_service.dart
await _localNotifications.show(
  0,
  '테스트 제목',
  '테스트 내용',
  NotificationDetails(
    android: AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.high,
      priority: Priority.high,
    ),
  ),
);
```

## 🔄 업데이트 이력

### 2025-03-30
- ✅ 알림 채널 최적화 (LED 색상 추가)
- ✅ 백그라운드 핸들러 채널 선택 로직 개선
- ✅ 중복 알림 방지 로직 개선 (알림 ID 전략)
- ✅ Android 13+ 권한 처리 로그 개선
- ✅ AndroidManifest.xml 주석 추가
- ✅ 시스템 문서화

## 📚 참고 자료

- [Firebase Cloud Messaging (Flutter)](https://firebase.flutter.dev/docs/messaging/overview)
- [Flutter Local Notifications](https://pub.dev/packages/flutter_local_notifications)
- [Android Notification Channels](https://developer.android.com/develop/ui/views/notifications/channels)
- [Android Runtime Permissions](https://developer.android.com/training/permissions/requesting)
