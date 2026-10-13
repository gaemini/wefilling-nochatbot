// lib/services/together_service.dart
// 같이하기(프로필 → 1:1 24시간 스낵챗 제안) callable 호출.

import 'package:cloud_functions/cloud_functions.dart';

import '../config/app_backend.dart';

enum TogetherProposeFailure {
  notFriends,
  activityMissing,
  blocked,
  tooMany,
  unknown,
}

class TogetherProposeException implements Exception {
  TogetherProposeException(this.reason);
  final TogetherProposeFailure reason;
}

class TogetherService {
  TogetherService({FirebaseFunctions? functions})
      : _functions = functions ?? AppFunctions.instance;

  static final TogetherService instance = TogetherService();

  final FirebaseFunctions _functions;

  /// 제안을 보내고 방 id를 돌려준다. 같은 쌍·활동의 열린 제안이 있으면 그 방이다.
  Future<String> propose({
    required String targetUid,
    required String activity,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('proposeTogetherSnackChat')
          .call(<String, dynamic>{
        'targetUid': targetUid,
        'activity': activity,
      }).timeout(const Duration(seconds: 20));
      final data = result.data;
      final id = data is Map ? (data['snackChatId'] ?? '').toString() : '';
      if (id.isEmpty) {
        throw TogetherProposeException(TogetherProposeFailure.unknown);
      }
      return id;
    } on FirebaseFunctionsException catch (error) {
      throw TogetherProposeException(switch (error.code) {
        'failed-precondition' =>
          (error.message ?? '').contains('friends')
              ? TogetherProposeFailure.notFriends
              : TogetherProposeFailure.activityMissing,
        'permission-denied' => TogetherProposeFailure.blocked,
        'resource-exhausted' => TogetherProposeFailure.tooMany,
        _ => TogetherProposeFailure.unknown,
      });
    }
  }

  /// `accept` 또는 `later`.
  Future<void> respond({
    required String roomId,
    required bool accept,
  }) async {
    await _functions
        .httpsCallable('respondTogetherProposal')
        .call(<String, dynamic>{
      'roomId': roomId,
      'response': accept ? 'accept' : 'later',
    }).timeout(const Duration(seconds: 20));
  }
}
