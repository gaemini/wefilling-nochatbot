import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/snack_chat_message.dart';
import 'firebase_app_check_service.dart';

const snackChatDiscoveryEnabled =
    bool.fromEnvironment('SNACK_CHAT_DISCOVERY', defaultValue: true);

/// Read-only callables. No subscription/cache/read-counter side effects.
class SnackChatDiscoveryService {
  Future<Map<String, dynamic>> call(
      String name, Map<String, dynamic> payload) async {
    final owner = FirebaseAuth.instance.currentUser?.uid;
    if (owner == null) throw StateError('Sign-in required');
    await FirebaseAppCheckService.instance.ensureReady();
    final result = await FirebaseFunctions.instance
        .httpsCallable(name)
        .call(payload)
        .timeout(const Duration(seconds: 35));
    if (FirebaseAuth.instance.currentUser?.uid != owner) {
      throw StateError('Account changed');
    }
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> query(
          String room, Map<String, dynamic> filters) =>
      call('querySnackChatMessages', {'snackChatId': room, ...filters});

  Future<List<Map<String, dynamic>>> participants(String room,
      {bool includeSelf = false}) async {
    final data = await call('getSnackChatMentionCandidates',
        {'snackChatId': room, 'includeSelf': includeSelf});
    return (data['participants'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static List<Map<String, dynamic>> rows(Map<String, dynamic> data) =>
      (data['results'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  static SnackChatMessage message(Map<String, dynamic> row) {
    final data = Map<String, dynamic>.from(row);
    for (final key in ['createdAt', 'expiresAt', 'deleteAt']) {
      final value = data[key];
      data[key] = value is num && value > 0
          ? Timestamp.fromMillisecondsSinceEpoch(value.toInt())
          : null;
    }
    return SnackChatMessage.fromMap(row['id'] as String, data);
  }
}
