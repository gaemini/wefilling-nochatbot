enum NicknameValidationIssue {
  empty,
  length,
  invalidCharacters,
  letterRequired,
  reserved,
}

class NicknameIdentity {
  const NicknameIdentity({
    required this.nickname,
    required this.nicknameKey,
  });

  final String nickname;
  final String nicknameKey;
}

/// Client mirror of the server nickname policy.
///
/// This provides immediate UX feedback only. The Cloud Function remains the
/// authority for normalization, availability and final ownership.
class NicknamePolicy {
  const NicknamePolicy._();

  static const int version = 2;
  static const int minLength = 2;
  static const int maxLength = 20;

  static final RegExp _controlAndInvisible = RegExp(
    r'[\u0000-\u001F\u007F-\u009F\u200B-\u200D\u2060\uFEFF]',
    unicode: true,
  );
  static final RegExp _whitespace = RegExp(r'\s+', unicode: true);
  static final RegExp _allowed = RegExp(r'^[A-Za-z0-9가-힣_]+$');
  static final RegExp _hasLetter = RegExp(r'[A-Za-z가-힣]');
  static const Set<String> _reservedKeys = <String>{
    '익명',
    'anonymous',
    'deleted_account',
    'deleted',
    '삭제된_계정',
    '탈퇴한_사용자',
  };

  /// Mirrors the compatibility characters users commonly enter from mobile
  /// keyboards. The server additionally performs full Unicode NFKC.
  static String _normalizeCompatibilityCharacters(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune == 0x3000) {
        buffer.write(' ');
      } else if (rune >= 0xff01 && rune <= 0xff5e) {
        buffer.writeCharCode(rune - 0xfee0);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  static String normalizePreview(String? raw) {
    final compatible = _normalizeCompatibilityCharacters(raw ?? '');
    return compatible
        .replaceAll(_controlAndInvisible, '')
        .trim()
        .replaceAll(_whitespace, '_');
  }

  static String canonicalKey(String? raw) =>
      normalizePreview(raw).toLowerCase();

  static NicknameValidationIssue? validate(String? raw) {
    final nickname = normalizePreview(raw);
    if (nickname.isEmpty) return NicknameValidationIssue.empty;
    if (nickname.length < minLength || nickname.length > maxLength) {
      return NicknameValidationIssue.length;
    }
    if (!_allowed.hasMatch(nickname)) {
      return NicknameValidationIssue.invalidCharacters;
    }
    if (!_hasLetter.hasMatch(nickname)) {
      return NicknameValidationIssue.letterRequired;
    }
    if (_reservedKeys.contains(nickname.toLowerCase())) {
      return NicknameValidationIssue.reserved;
    }
    return null;
  }

  static NicknameIdentity? identityOrNull(String? raw) {
    if (validate(raw) != null) return null;
    final nickname = normalizePreview(raw);
    return NicknameIdentity(
      nickname: nickname,
      nicknameKey: nickname.toLowerCase(),
    );
  }
}
