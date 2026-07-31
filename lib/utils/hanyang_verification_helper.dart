/// 로그인 이메일 인증과 한양대학교 소속 인증은 서로 다른 상태입니다.
///
/// 신규 문서는 서버가 [hanyangEmailVerified]를 명시적으로 기록합니다. 배포 전
/// 문서는 가입 방식과 실제 한양메일 도메인을 함께 확인해 안전하게 호환합니다.
bool isHanyangEmailVerified(Map<String, dynamic>? data) {
  if (data == null) return false;

  final explicit = data['hanyangEmailVerified'];
  if (explicit is bool) return explicit;

  final hanyangEmail =
      (data['hanyangEmail'] ?? '').toString().trim().toLowerCase();
  if (!hanyangEmail.endsWith('@hanyang.ac.kr')) return false;

  final method =
      (data['schoolVerificationMethod'] ?? data['verificationMethod'] ?? '')
          .toString()
          .trim();
  if (method == 'social_en_bypass' || method == 'email_code') return false;

  return data['emailVerified'] == true &&
      (method.isEmpty || method == 'hanyang_email_code');
}
