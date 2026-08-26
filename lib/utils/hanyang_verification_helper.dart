/// 로그인 이메일 인증과 한양대학교 소속 인증은 서로 다른 상태입니다.
///
/// 서버가 관리하는 users/{uid}.hanyangEmailVerified 단일 필드와 실제
/// 한양메일 형식이 모두 유효할 때만 인증으로 판단합니다.
bool isHanyangEmailVerified(Map<String, dynamic>? data) {
  if (data == null) return false;

  final hanyangEmail =
      (data['hanyangEmail'] ?? '').toString().trim().toLowerCase();
  final validEmail =
      RegExp(r'^[^\s@]+@hanyang\.ac\.kr$').hasMatch(hanyangEmail);
  return validEmail && data['hanyangEmailVerified'] == true;
}
