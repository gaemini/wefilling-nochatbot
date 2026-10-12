import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/first_response_request.dart';

void main() {
  test('요청 id는 발신자→수신자 쌍당 하나다', () {
    expect(FirstResponseRequest.idFor('a', 'b'), 'a_b');
    expect(FirstResponseRequest.idFor('b', 'a'), 'b_a');
  });

  test('친구면 요청 대신 DM으로, 기존 요청 상태에 따라 재전송을 막는다', () {
    expect(
      firstResponsePrecheck(isSelf: true, isFriend: false, existingStatus: null),
      FirstResponseSendOutcome.failed,
    );
    expect(
      firstResponsePrecheck(isSelf: false, isFriend: true, existingStatus: null),
      FirstResponseSendOutcome.alreadyAccepted,
    );
    expect(
      firstResponsePrecheck(
          isSelf: false, isFriend: false, existingStatus: null),
      isNull,
    );
    expect(
      firstResponsePrecheck(
        isSelf: false,
        isFriend: false,
        existingStatus: FirstResponseStatus.pending,
      ),
      FirstResponseSendOutcome.alreadyPending,
    );
    for (final closed in [
      FirstResponseStatus.declined,
      FirstResponseStatus.blocked,
      FirstResponseStatus.canceled,
    ]) {
      expect(
        firstResponsePrecheck(
            isSelf: false, isFriend: false, existingStatus: closed),
        FirstResponseSendOutcome.closed,
      );
    }
  });

  test('fromMap은 상태·출처·전달 여부를 읽고 수락 후 미전달만 needsDelivery다', () {
    final pending = FirstResponseRequest.fromMap('s_r', <String, dynamic>{
      'senderId': 's',
      'recipientId': 'r',
      'message': '안녕',
      'sourceType': 'snapshot',
      'sourceId': 'snack-1',
      'status': 'pending',
    });
    expect(pending.isPending, isTrue);
    expect(pending.sourceType, FirstResponseSourceType.snapshot);
    expect(pending.needsDelivery, isFalse);
    expect(pending.hasTranslation, isFalse);

    final accepted = FirstResponseRequest.fromMap('s_r', <String, dynamic>{
      'senderId': 's',
      'recipientId': 'r',
      'message': '안녕',
      'sourceType': 'post',
      'sourceId': 'post-1',
      'status': 'accepted',
      'conversationId': 'r_s',
      'translatedMessage': 'Hello',
    });
    expect(accepted.needsDelivery, isTrue);
    expect(accepted.hasTranslation, isTrue);

    final delivered = FirstResponseRequest.fromMap('s_r', <String, dynamic>{
      'senderId': 's',
      'recipientId': 'r',
      'message': '안녕',
      'sourceType': 'post',
      'sourceId': 'post-1',
      'status': 'accepted',
      'conversationId': 'r_s',
      'deliveredMessageId': 'm1',
    });
    expect(delivered.needsDelivery, isFalse);
  });
}
