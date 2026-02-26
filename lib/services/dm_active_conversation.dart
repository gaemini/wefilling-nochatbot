/// 앱에서 "현재 열려있는 DM 대화방"을 추적합니다.
///
/// 목적:
/// - 포그라운드에서 DM 푸시가 왔을 때, 사용자가 이미 해당 대화방을 보고 있다면
///   상단 배너/로컬 알림을 띄우지 않게 하기 위함.
/// - 동시에, 채팅 화면에서 들어오는 메시지를 즉시 읽음 처리하여
///   "미읽은 DM이 있을 때만 알림" UX를 유지합니다.
class DMActiveConversation {
  static String? _activeConversationId;

  static String? get activeConversationId => _activeConversationId;

  static void setActive(String? conversationId) {
    _activeConversationId = conversationId;
  }

  static bool isActive(String? conversationId) {
    if (conversationId == null || conversationId.isEmpty) return false;
    return _activeConversationId == conversationId;
  }
}

