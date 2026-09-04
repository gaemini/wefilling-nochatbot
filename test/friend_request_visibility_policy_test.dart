import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/friend_request.dart';
import 'package:wefilling/utils/friend_request_visibility_policy.dart';

void main() {
  FriendRequest request({
    required String id,
    required String fromUid,
    required String toUid,
  }) {
    final now = DateTime(2026, 9, 3);
    return FriendRequest(
      id: id,
      fromUid: fromUid,
      toUid: toUid,
      status: FriendRequestStatus.pending,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('received requests exclude senders whose account is unavailable', () {
    final requests = <FriendRequest>[
      request(id: 'active_me', fromUid: 'active', toUid: 'me'),
      request(id: 'deleted_me', fromUid: 'deleted', toUid: 'me'),
    ];

    final visible = FriendRequestVisibilityPolicy.retainAvailableCounterparts(
      requests,
      availableUserIds: const <String>{'active'},
      direction: FriendRequestDirection.incoming,
    );

    expect(visible.map((item) => item.id), <String>['active_me']);
  });

  test('sent requests exclude recipients whose account is unavailable', () {
    final requests = <FriendRequest>[
      request(id: 'me_active', fromUid: 'me', toUid: 'active'),
      request(id: 'me_deleted', fromUid: 'me', toUid: 'deleted'),
    ];

    final visible = FriendRequestVisibilityPolicy.retainAvailableCounterparts(
      requests,
      availableUserIds: const <String>{'active'},
      direction: FriendRequestDirection.outgoing,
    );

    expect(visible.map((item) => item.id), <String>['me_active']);
  });
}
