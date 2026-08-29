/// 현재 사용자 화면에서 번역할 수 있는 스낵챗 메시지인지 판단할 때 쓰는
/// 작은 공통 정책입니다. 사용자 이름이나 프로필이 아닌 불변 uid만 비교합니다.
bool isOwnSnackChatMessage({
  required String senderId,
  required String? currentUserId,
}) {
  return currentUserId != null &&
      currentUserId.isNotEmpty &&
      senderId == currentUserId;
}

final RegExp _urlOnlyTokenPattern = RegExp(
  r'(?:(?:https?://|www\.)[^\s]+)'
  r'|(?:\b[\p{L}\p{N}](?:[\p{L}\p{N}-]{0,62}\.)+'
  r'[a-z]{2,63}(?:/[^\s]*)?\b)',
  caseSensitive: false,
  unicode: true,
);
final RegExp _translationLetterPattern = RegExp(r'\p{L}', unicode: true);

/// 공백·이모지·URL만 있는 값은 번역 상태나 캐시를 만들 필요가 없습니다.
/// URL과 함께 실제 문장이 있으면 문장 부분은 정상적으로 번역 대상이 됩니다.
bool hasTranslatableSnackChatText(String value) {
  final withoutUrls = value.replaceAll(_urlOnlyTokenPattern, ' ').trim();
  return withoutUrls.isNotEmpty &&
      _translationLetterPattern.hasMatch(withoutUrls);
}
