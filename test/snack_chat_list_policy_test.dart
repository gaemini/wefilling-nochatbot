import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/snack_chat_list_policy.dart';

void main() {
  test('policy boundary is exactly 2026-07-24 00:00 KST', () {
    expect(snackChatListPolicyStartUtc, DateTime.utc(2026, 7, 23, 15));
    expect(
      isEligibleForCurrentSnackChatListPolicy(
        DateTime.utc(2026, 7, 23, 14, 59, 59, 999),
      ),
      isFalse,
    );
    expect(
      isEligibleForCurrentSnackChatListPolicy(
        DateTime.utc(2026, 7, 23, 15),
      ),
      isTrue,
    );
  });

  test('current and future rooms use the new list policy', () {
    expect(
      isEligibleForCurrentSnackChatListPolicy(DateTime.utc(2026, 7, 24)),
      isTrue,
    );
    expect(
      isEligibleForCurrentSnackChatListPolicy(DateTime.utc(2030, 1, 1)),
      isTrue,
    );
  });
}
