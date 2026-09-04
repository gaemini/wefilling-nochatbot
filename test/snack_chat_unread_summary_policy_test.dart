import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snack_chat_message.dart';
import 'package:wefilling/utils/snack_chat_unread_summary_policy.dart';

void main() {
  const currentUserId = 'me';

  SnackChatMessage message(
    int sequence,
    String text, {
    String senderId = 'friend',
    SnackChatMessageType type = SnackChatMessageType.text,
    bool isDeleted = false,
    List<String>? deliveryRecipientIds,
    String? originalFileName,
  }) {
    return SnackChatMessage(
      id: 'message-$sequence-$senderId',
      senderId: senderId,
      type: type,
      text: text,
      createdAt: DateTime.utc(2026, 9, 4, 12, sequence),
      sequence: sequence,
      isDeleted: isDeleted,
      deliveryRecipientIds: deliveryRecipientIds,
      originalFileName: originalFileName,
    );
  }

  SnackChatUnreadSummaryPlan plan(
    List<SnackChatMessage> messages, {
    int declaredUnreadCount = 6,
    int firstUnreadSequence = 10,
    int latestSequence = 30,
  }) {
    return buildSnackChatUnreadSummaryPlan(
      messages: messages,
      currentUserId: currentUserId,
      firstUnreadSequence: firstUnreadSequence,
      latestSequence: latestSequence,
      declaredUnreadCount: declaredUnreadCount,
    );
  }

  test('zero unread messages never expose the summary action', () {
    final result = plan(
      <SnackChatMessage>[],
      declaredUnreadCount: 0,
    );

    expect(result.shouldShowButton, isFalse);
    expect(result.messages, isEmpty);
  });

  test('one or two short reactions stay in the normal message list', () {
    final result = plan(
      <SnackChatMessage>[
        message(10, 'ㅋㅋ'),
        message(11, 'ok'),
      ],
      declaredUnreadCount: 2,
    );

    expect(result.shouldShowButton, isFalse);
    expect(result.useLocalSummary, isFalse);
  });

  test('three unread messages expose the on-demand server summary', () {
    final result = plan(
      <SnackChatMessage>[
        message(10, '내일 오후 7시에 중앙역에서 만날까?'),
        message(11, '좋아'),
        message(12, '화요일도 가능합니다.'),
      ],
      declaredUnreadCount: 3,
    );

    expect(result.shouldShowButton, isTrue);
    expect(result.useLocalSummary, isFalse);
  });

  test('three low-value messages still expose a concise server summary', () {
    final result = plan(
      <SnackChatMessage>[
        message(10, 'hello'),
        message(11, 'ㅋㅋㅋ'),
        message(12, 'thanks'),
      ],
      declaredUnreadCount: 3,
    );

    expect(result.shouldShowButton, isTrue);
    expect(result.useLocalSummary, isFalse);
  });

  test('six unread messages expose the on-demand server summary', () {
    final result = plan(<SnackChatMessage>[
      message(10, '식당 후보를 두 곳 찾았어요.'),
      message(11, '중앙역에서 만나서 같이 이동하면 좋겠어요.'),
      message(12, '예약 가능한 지 확인해 볼게요.'),
      message(13, '화요일과 수요일은 가능합니다.'),
      message(14, '개강 총회 일정도 공유해 주세요.'),
      message(15, '다음 주는 온라인으로 회의하겠습니다.'),
    ]);

    expect(result.shouldShowButton, isTrue);
    expect(result.useLocalSummary, isFalse);
  });

  test('only authoritative unread recipient messages become sources', () {
    final result = plan(
      <SnackChatMessage>[
        message(9, '범위 이전'),
        message(10, '내가 보낸 메시지', senderId: currentUserId),
        message(11, '삭제됨', isDeleted: true),
        message(12, '시스템', type: SnackChatMessageType.system),
        message(13, '다른 사용자만 받음', deliveryRecipientIds: const ['other']),
        message(14, '내일 일정을 확인해 주세요.',
            deliveryRecipientIds: const [currentUserId]),
        message(31, '범위 이후'),
      ],
      declaredUnreadCount: 6,
    );

    expect(result.messages.map((item) => item.sequence), <int?>[14]);
    expect(result.shouldShowButton, isTrue);
    expect(result.useLocalSummary, isFalse);
  });

  test('an attachment can use a local preview for a short unread range', () {
    final attachment = message(
      10,
      '',
      type: SnackChatMessageType.file,
      originalFileName: 'meeting-plan.pdf',
    );
    final result = plan(<SnackChatMessage>[attachment], declaredUnreadCount: 1);

    expect(result.shouldShowButton, isFalse);
    expect(result.useLocalSummary, isFalse);
    expect(
      snackChatLocalSummaryText(attachment, isKorean: true),
      contains('meeting-plan.pdf'),
    );
  });

  test('local fallback prioritizes scheduling details over greetings', () {
    final messages = <SnackChatMessage>[
      message(10, '안녕하세요'),
      message(11, '제 이름은 제빈이에요'),
      message(12, '오늘 같이 팀플하게 되었는데 반가워요'),
      message(13, '저희 매주 미팅 날짜를 정하려고 해요'),
      message(14, '월화수 전 가능합니다'),
      message(15, '혹시 괜찮은 시간 언제인지 알려주세요'),
      message(16, '개강 총회 일정도 공유해 주세요'),
      message(17, '다음 주는 온라인으로 회의하겠습니다'),
    ];

    final fallback = selectSnackChatLocalFallbackMessages(messages);

    expect(fallback, hasLength(5));
    expect(fallback.map((item) => item.sequence), <int?>[13, 14, 15, 16, 17]);
  });
}
