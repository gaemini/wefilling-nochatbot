/// 회원가입 화면 사이에서만 유지되는 임시 정보입니다.
///
/// SharedPreferences/Firestore에는 저장하지 않습니다. 마지막 프로필 단계가
/// 성공한 뒤에만 서버의 정식 사용자 문서가 생성됩니다.
enum PendingSignupKind {
  generalEmail,
  hanyangEmail,
  englishSocial,
  hanyangSocial,
}

class PendingSignupSession {
  const PendingSignupSession({
    required this.kind,
    this.loginEmail = '',
    this.password = '',
    this.verifiedEmail = '',
    this.verificationToken = '',
  });

  final PendingSignupKind kind;
  final String loginEmail;
  final String password;
  final String verifiedEmail;
  final String verificationToken;

  bool get isEmailPassword =>
      kind == PendingSignupKind.generalEmail ||
      kind == PendingSignupKind.hanyangEmail;

  bool get isHanyang =>
      kind == PendingSignupKind.hanyangEmail ||
      kind == PendingSignupKind.hanyangSocial;
}
