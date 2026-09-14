import 'package:unorm_dart/unorm_dart.dart' as unorm;

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

  static const int version = 3;
  static const int minLength = 2;
  static const int maxLength = 20;

  static final RegExp _allowed = RegExp(r'^[A-Za-z가-힣]+$');
  // Match ECMAScript String.trim on the server (Dart also trims U+0085).
  static final RegExp _edgeWhitespace = RegExp(
    r'^[\u0009-\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+|[\u0009-\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+$',
  );
  static final RegExp _hasLetter = RegExp(r'[A-Za-z가-힣]');
  static const Set<String> _reservedKeys = <String>{
    '익명',
    'anonymous',
    'deleted_account',
    'deleted',
    '삭제된_계정',
    '탈퇴한_사용자',
  };

  static String normalizePreview(String? raw) {
    return unorm.nfc((raw ?? '').replaceAll(_edgeWhitespace, ''));
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
