/// 앱에서 "현재 열려있는 Snack Chat 방"을 추적합니다.
///
/// 포그라운드에서 스냅챗 푸시가 왔을 때, 사용자가 이미 해당 채팅방을 보고 있다면
/// 로컬 알림을 띄우지 않게 하기 위함.
class SnackChatActiveConversation {
  static String? _activeSnackChatId;

  static String? get activeSnackChatId => _activeSnackChatId;

  static void setActive(String? snackChatId) {
    _activeSnackChatId = snackChatId;
  }

  static bool isActive(String? snackChatId) {
    if (snackChatId == null || snackChatId.isEmpty) return false;
    return _activeSnackChatId == snackChatId;
  }
}
