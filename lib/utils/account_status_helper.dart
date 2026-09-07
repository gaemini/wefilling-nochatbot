/// 사용자 문서가 실제로 사용할 수 있는 계정인지 공통으로 판정합니다.
///
/// 탈퇴 처리 직후 지연된 FCM/프로필 merge가 빈 `users/{uid}` 문서를 다시
/// 만들 수 있으므로, 삭제 플래그뿐 아니라 계정 식별 정보가 모두 사라진
/// 빈 문서도 사용할 수 없는 계정으로 취급합니다.
bool isUnavailableUserAccountData(Map<String, dynamic>? data) {
  if (data == null) return true;

  final status = (data['status'] ?? data['accountStatus'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  final registrationStatus =
      (data['registrationStatus'] ?? '').toString().trim().toLowerCase();
  final nickname =
      (data['nickname'] ?? data['displayName'] ?? '').toString().trim();

  if (data['isDeleted'] == true ||
      data['deleted'] == true ||
      data['disabled'] == true ||
      data['isSuspended'] == true ||
      data['deletedAt'] != null ||
      status == 'deleted' ||
      status == 'suspended' ||
      registrationStatus == 'deleted' ||
      nickname == 'DELETED_ACCOUNT' ||
      nickname == 'Deleted') {
    return true;
  }

  final email = (data['email'] ?? '').toString().trim();
  final hanyangEmail = (data['hanyangEmail'] ?? '').toString().trim();

  // FCM 토큰 등의 지연된 merge로 다시 생긴 껍데기 문서를 정상 계정으로
  // 노출하지 않는다. uid만 다시 기록된 문서 역시 실제 프로필이 아니므로,
  // 레거시 정상 계정의 닉네임/이메일 중 하나가 있어야 활성 계정으로 본다.
  return nickname.isEmpty && email.isEmpty && hanyangEmail.isEmpty;
}

/// 이름/관심사/초대처럼 실제 사람을 찾는 화면의 엄격한 공개 조건입니다.
///
/// 콘텐츠의 익명 표시 정책과 분리되어 있으므로 이 함수는 `UserProfile`의
/// 표시용 fallback을 바꾸지 않습니다. 서버 callable이 최종 권한자이고 이
/// 판정은 순차 배포 중 사용하는 직접 Firestore 호환 경로의 fail-closed
/// 보호막입니다.
bool isSearchableUserAccountData(
  Map<String, dynamic>? data, {
  required String uid,
}) {
  if (data == null || uid.trim().isEmpty || uid.contains('/')) return false;
  if (isUnavailableUserAccountData(data)) return false;

  final normalizedUid = uid.trim().toLowerCase();
  if (const <String>{
    'anonymous',
    'deleted',
    'deleted_account',
    'unknown',
    'system',
  }.contains(normalizedUid)) {
    return false;
  }
  if (data['searchable'] == false ||
      data['isSearchable'] == false ||
      data['allowUserSearch'] == false ||
      data['isProfilePrivate'] == true ||
      data['deleting'] == true) {
    return false;
  }

  final registrationStatus =
      (data['registrationStatus'] ?? '').toString().trim().toLowerCase();
  final signupState =
      (data['signupState'] ?? '').toString().trim().toLowerCase();
  final completed = registrationStatus == 'complete' ||
      (registrationStatus.isEmpty &&
          data['emailVerified'] == true &&
          signupState != 'authcreated' &&
          signupState != 'profilepending');
  if (!completed) return false;

  final nickname = (data['nickname'] ?? '').toString().trim();
  if (nickname.length < 2 || nickname.length > 20) return false;
  if (const <String>{
    'anonymous',
    'deleted',
    'deleted_account',
    '익명',
    '탈퇴한 사용자',
  }.contains(nickname.toLowerCase())) {
    return false;
  }
  if (!RegExp(r'^[a-zA-Z0-9가-힣_.]+$').hasMatch(nickname)) return false;

  final normalizedNickname = nickname.toLowerCase();
  final nicknameKey = (data['nicknameKey'] ?? '').toString().trim();
  return nicknameKey.isEmpty || nicknameKey == normalizedNickname;
}
