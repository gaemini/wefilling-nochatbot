/// Version written to Snack Chat documents created under the current policy.
const int currentSnackChatListPolicyVersion = 2;

/// The current Snack Chat list policy started at 2026-07-24 00:00 KST.
///
/// Keeping this as an absolute UTC instant makes the migration boundary stable
/// even if a device changes locale or time zone later.
final DateTime snackChatListPolicyStartUtc = DateTime.utc(2026, 7, 23, 15);

/// Legacy rooms before the current policy are intentionally isolated from the
/// Today/All lists. They may contain fields that the current model no longer
/// supports and must not be allowed to break the complete stream.
bool isEligibleForCurrentSnackChatListPolicy(DateTime createdAt) {
  return !createdAt.toUtc().isBefore(snackChatListPolicyStartUtc);
}
