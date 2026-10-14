// lib/services/read_sync_service.dart
// 푸시 알림 ↔ 읽음 동기화(카카오톡 방식): 읽음은 서버 한 곳에서 정해지고,
// 알림센터·배지·앱 안 표시가 따라온다.
//
// 1) read_sync 푸시: 다른 기기(또는 서버)에서 읽음이 바뀌면 서버가 보내는
//    조용한 데이터 푸시. 해당 알림센터 항목을 지우고 배지를 맞춘다.
// 2) 복귀 정리: 앱을 열거나 돌아올 때 알림센터에 남은 항목을 서버 읽음
//    상태와 비교해 이미 읽은 것을 지운다(조용한 푸시가 늦거나 버려져도 보장).
//
// 정리 요청(Map)은 기존 FCMService의 removeDeliveredNotifications 요청과 같은
// 형식이다. 여기서 만든 요청은 'confirmed_push_reads::{uid}'에도 저장되어
// 다음 복귀 때 다시 적용된다.

import 'dart:convert';

import '../utils/notification_delivery_policy.dart';
import '../utils/snack_chat_notification_policy.dart';

/// 클라이언트 복귀 정리 스위치(기본 켜짐). `--dart-define=READ_SYNC_RECONCILE=false`.
const bool kReadSyncReconcileEnabled =
    bool.fromEnvironment('READ_SYNC_RECONCILE', defaultValue: true);

const String readSyncPushType = 'read_sync';

/// 알림센터에 남은 항목 하나(네이티브 listDeliveredNotifications 결과).
class DeliveredNotification {
  const DeliveredNotification({
    required this.type,
    this.notificationId = '',
    this.conversationId = '',
    this.snackChatId = '',
    this.messageSequence = 0,
    this.sentAtMillis = 0,
    this.deliveredAtMillis = 0,
  });

  factory DeliveredNotification.fromMap(Map<dynamic, dynamic> map) {
    int number(Object? value) =>
        value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;
    String text(Object? value) => (value ?? '').toString().trim();
    return DeliveredNotification(
      type: text(map['type']),
      notificationId: text(map['notificationId']),
      conversationId: text(map['conversationId']),
      snackChatId: text(map['snackChatId']),
      messageSequence: number(map['messageSequence']),
      sentAtMillis: number(map['sentAtMillis']),
      deliveredAtMillis: number(map['deliveredAtMillis']),
    );
  }

  final String type;
  final String notificationId;
  final String conversationId;
  final String snackChatId;
  final int messageSequence;
  final int sentAtMillis;
  final int deliveredAtMillis;

  bool get isDm => type == 'dm_received' && conversationId.isNotEmpty;
  bool get isSnackChat =>
      type == 'snack_chat_message' && snackChatId.isNotEmpty;
  bool get isApp =>
      !isDm &&
      !isSnackChat &&
      notificationId.isNotEmpty &&
      type != 'personalTodoReminder' &&
      type != 'ad_updates';
}

/// 서버의 현재 읽음 상태(복귀 정리 비교용).
class ServerReadState {
  const ServerReadState({
    this.readOrMissingNotificationIds = const <String>{},
    this.dmReadThroughMillis = const <String, int>{},
    this.snackReadThroughSequence = const <String, int>{},
  });

  /// isRead == true 이거나 문서가 없는 알림 id.
  final Set<String> readOrMissingNotificationIds;

  /// 대화 id → lastReadAtBy[uid] (밀리초).
  final Map<String, int> dmReadThroughMillis;

  /// 스낵챗 방 id → members/{uid}.lastReadSequence.
  final Map<String, int> snackReadThroughSequence;
}

class ReadSyncPlanner {
  ReadSyncPlanner._();

  /// 알림센터 항목과 서버 상태를 비교해 지울 요청 목록을 만든다.
  static List<Map<String, dynamic>> reconcileRequests({
    required String owner,
    required List<DeliveredNotification> delivered,
    required ServerReadState server,
  }) {
    final requests = <Map<String, dynamic>>[];
    final appIds = <String>{};
    final dmThrough = <String, int>{};
    final snackThrough = <String, int>{};
    for (final item in delivered) {
      if (item.isDm) {
        final readAt = server.dmReadThroughMillis[item.conversationId] ?? 0;
        if (readAt > 0 && item.sentAtMillis > 0 && item.sentAtMillis <= readAt) {
          dmThrough[item.conversationId] = readAt;
        }
      } else if (item.isSnackChat) {
        final through = server.snackReadThroughSequence[item.snackChatId] ?? 0;
        if (through > 0 &&
            item.messageSequence > 0 &&
            item.messageSequence <= through) {
          snackThrough[item.snackChatId] = through;
        }
      } else if (item.isApp &&
          server.readOrMissingNotificationIds.contains(item.notificationId)) {
        appIds.add(item.notificationId);
      }
    }
    if (appIds.isNotEmpty) {
      final ids = appIds.toList()..sort();
      requests.add(<String, dynamic>{
        'kind': 'app',
        'notificationIds': ids,
        'notificationId': 'batch:${appNotificationAndroidTag(ids.join(','))}',
        'androidTags': ids.map(appNotificationAndroidTag).toList(),
      });
    }
    dmThrough.forEach((room, readAt) {
      requests.add(dmRequest(owner: owner, room: room, throughMillis: readAt));
    });
    snackThrough.forEach((room, sequence) {
      requests.add(
          snackRequest(owner: owner, room: room, throughSequence: sequence));
    });
    return requests;
  }

  static Map<String, dynamic> dmRequest({
    required String owner,
    required String room,
    required int throughMillis,
    int throughSeconds = 0,
    int throughNanos = 0,
  }) =>
      <String, dynamic>{
        'kind': 'dm',
        'roomId': room,
        'throughSentAtMillis': throughMillis,
        'throughSeconds': throughSeconds,
        'throughNanos': throughNanos,
        'removeAllInRoom': false,
        'androidTag':
            dmNotificationAndroidTag(recipientUserId: owner, conversationId: room),
      };

  static Map<String, dynamic> snackRequest({
    required String owner,
    required String room,
    required int throughSequence,
  }) =>
      <String, dynamic>{
        'kind': 'snack_chat',
        'roomId': room,
        'throughSequence': throughSequence,
        'removeAllInRoom': false,
        'androidTag':
            snackChatNotificationGroupKey(recipientUserId: owner, snackChatId: room),
      };

  /// read_sync 푸시 데이터 → 정리 요청. 다른 계정 대상이면 빈 목록.
  ///
  /// 데이터 형식(모두 문자열): `type=read_sync`, `recipientUserId`,
  /// `targets`=JSON 배열 `[{k:'app', ids:[..]}, {k:'all_app', at:ms},
  /// {k:'dm', room, ms, s?, n?}, {k:'snack_chat', room, seq}]`, `badge`.
  static List<Map<String, dynamic>> requestsFromPush(
    Map<String, dynamic> data, {
    required String owner,
  }) {
    if ((data['type'] ?? '').toString() != readSyncPushType) return const [];
    final recipient = (data['recipientUserId'] ?? '').toString().trim();
    if (owner.isEmpty || recipient != owner) return const [];
    List<dynamic> targets;
    try {
      final decoded = jsonDecode((data['targets'] ?? '[]').toString());
      targets = decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
    int number(Object? value) =>
        value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;
    final requests = <Map<String, dynamic>>[];
    final appIds = <String>{};
    for (final raw in targets) {
      if (raw is! Map) continue;
      final kind = (raw['k'] ?? '').toString();
      final room = (raw['room'] ?? '').toString().trim();
      switch (kind) {
        case 'app':
          final ids = raw['ids'];
          if (ids is List) {
            appIds.addAll(
                ids.map((id) => id.toString().trim()).where((id) => id.isNotEmpty));
          }
        case 'all_app':
          requests.add(<String, dynamic>{
            'kind': 'all_app',
            'notificationId': 'all_app',
            'throughDeliveredAtMillis': number(raw['at']),
          });
        case 'dm':
          final through = number(raw['ms']);
          if (room.isEmpty || through <= 0) continue;
          requests.add(dmRequest(
            owner: owner,
            room: room,
            throughMillis: through,
            throughSeconds: number(raw['s']),
            throughNanos: number(raw['n']),
          ));
        case 'snack_chat':
          final sequence = number(raw['seq']);
          if (room.isEmpty || sequence <= 0) continue;
          requests.add(
              snackRequest(owner: owner, room: room, throughSequence: sequence));
      }
    }
    if (appIds.isNotEmpty) {
      final ids = appIds.toList()..sort();
      requests.insert(0, <String, dynamic>{
        'kind': 'app',
        'notificationIds': ids,
        'notificationId': 'batch:${appNotificationAndroidTag(ids.join(','))}',
        'androidTags': ids.map(appNotificationAndroidTag).toList(),
      });
    }
    return requests;
  }

  /// confirmed_push_reads에 저장할 항목들(앱 kind는 id별로 나눈다).
  static List<Map<String, dynamic>> receiptsFor(
    List<Map<String, dynamic>> requests, {
    required String owner,
    required int nowMillis,
  }) {
    final receipts = <Map<String, dynamic>>[];
    for (final request in requests) {
      if (request['kind'] == 'app') {
        for (final id in (request['notificationIds'] as List).cast<String>()) {
          receipts.add(<String, dynamic>{
            'kind': 'app',
            'notificationId': id,
            'androidTag': appNotificationAndroidTag(id),
            'ownerUserId': owner,
            'confirmedAt': nowMillis,
          });
        }
      } else {
        receipts.add(<String, dynamic>{
          ...request,
          'ownerUserId': owner,
          'confirmedAt': nowMillis,
        });
      }
    }
    return receipts;
  }

  static int? badgeFromPush(Map<String, dynamic> data) {
    final badge = int.tryParse((data['badge'] ?? '').toString());
    return badge != null && badge >= 0 ? badge : null;
  }

  static String receiptKey(Map<String, dynamic> entry) =>
      '${entry['ownerUserId']}:${entry['kind']}:'
      '${entry['notificationId'] ?? entry['roomId']}';

  /// 저장된 확인 목록에 새 항목을 합친다(같은 대상은 경계 값이 큰 쪽).
  /// 백그라운드 isolate가 SharedPreferences에 직접 쓸 때 쓴다.
  static List<Map<String, dynamic>> mergeReceipts(
    List<Map<String, dynamic>> existing,
    List<Map<String, dynamic>> incoming,
  ) {
    final merged = <String, Map<String, dynamic>>{
      for (final entry in existing) receiptKey(entry): entry,
    };
    for (final entry in incoming) {
      final key = receiptKey(entry);
      final previous = merged[key];
      final next = <String, dynamic>{...?previous, ...entry};
      if (previous != null) {
        for (final field in const [
          'throughSequence',
          'throughSentAtMillis',
          'throughSeconds',
          'throughDeliveredAtMillis',
          'confirmedAt',
        ]) {
          final old = (previous[field] as num?)?.toInt() ?? 0;
          if (old > ((entry[field] as num?)?.toInt() ?? 0)) next[field] = old;
        }
      }
      merged[key] = next;
    }
    return merged.values.toList();
  }
}
