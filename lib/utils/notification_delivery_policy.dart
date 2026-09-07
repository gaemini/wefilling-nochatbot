import 'dart:convert';

import 'package:crypto/crypto.dart';

const int androidRemoteNotificationId = 0;

String appNotificationAndroidTag(String notificationId) {
  final digest = sha256.convert(utf8.encode(notificationId.trim()));
  return 'notification_${digest.toString().substring(0, 40)}';
}

String dmNotificationAndroidTag({
  required String recipientUserId,
  required String conversationId,
}) {
  final digest = sha256.convert(
    utf8.encode('${recipientUserId.trim()}:${conversationId.trim()}'),
  );
  return 'dm_${digest.toString().substring(0, 40)}';
}
