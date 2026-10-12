import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/services/navigation_service.dart';

void main() {
  test('chat pushes share a destination per room, not per notification ID', () {
    expect(
      NavigationService.destinationKey({
        'type': 'dm_received', 'conversationId': 'a', 'notificationId': 'old',
      }),
      NavigationService.destinationKey({
        'type': 'dm_received', 'conversationId': 'a', 'notificationId': 'new',
      }),
    );
    expect(
      NavigationService.destinationKey({
        'type': 'snack_chat_message', 'snackChatId': 's',
      }),
      NavigationService.destinationKey({
        'type': 'snack_chat_invite', 'snackChatId': 's',
      }),
    );
    expect(
      NavigationService.destinationKey({
        'type': 'dm_received', 'conversationId': 'a',
      }),
      isNot(NavigationService.destinationKey({
        'type': 'dm_received', 'conversationId': 'b',
      })),
    );
  });

  test('content route deduplication does not conflate unrelated targets', () {
    expect(
      NavigationService.destinationKey({
        'type': 'new_comment', 'postId': 'p', 'notificationId': 'one',
      }),
      NavigationService.destinationKey({
        'type': 'new_like', 'postId': 'p', 'notificationId': 'two',
      }),
    );
    expect(
      NavigationService.destinationKey({
        'type': 'new_comment', 'postId': 'p',
      }),
      isNot(NavigationService.destinationKey({
        'type': 'new_comment', 'postId': 'q',
      })),
    );
  });
}
