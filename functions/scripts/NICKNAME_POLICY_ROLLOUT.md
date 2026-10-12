# 회원 아이디 정책 v3 적용

대상은 `users.nickname`(표시값)과 `nicknameKey`(NFC + trim + 소문자) 및 기존 `nicknameClaims`뿐입니다. UID, 이메일, 문서 ID, 관계 데이터는 바꾸지 않습니다. 신규/변경 아이디는 조합이 완료된 한글 음절과 ASCII 영문 2–20자입니다. 새 Dart NFC 의존성은 [unorm_dart](https://pub.dev/packages/unorm_dart)입니다.

## 배포 순서 — 운영에 자동 적용되지 않음

1. Firestore 백업과 대상 Firebase project/관리자 ADC 권한을 확인합니다. 갱신된 앱을 먼저 배포하는 것을 권장합니다. 기존 아이디의 로그인/조회/사진·소개 수정에는 새 규칙을 적용하지 않습니다.
2. `functions`에서 `npm run build` 후 먼저 데이터 반영 미리보기를 실행합니다.

   ```sh
   npm run migrate:nicknames -- --project=PROJECT_ID
   ```

3. 기존 v2 서버 함수가 서비스 중인 상태에서 먼저 데이터 반영을 적용합니다. v2 함수는 게이트를 사용하지 않아 기존 사용자와 가입 흐름이 중단되지 않고, 전환 중 생성·변경되는 아이디도 기존 `nicknameClaims`에 계속 기록됩니다.

   ```sh
   npm run migrate:nicknames -- --project=PROJECT_ID --apply --run-id=nickname-v3-FIRST_RUN_ID
   ```

   이 단계가 성공해 `nicknamePolicyState/current`가 `{version: 3, status: "ready"}`가 된 것을 확인하기 전에는 v3 함수를 배포하지 마세요. 실패 시 기존 서버는 계속 동작합니다. 동일한 run-id로 재실행할 수 있습니다.

4. 데이터 반영 성공 직후 루트에서 관련 서버 함수와 규칙을 함께 배포합니다. 일부 함수만 새 버전으로 둔 채 장시간 운영하지 마세요.

   ```sh
   firebase deploy --project PROJECT_ID --only firestore:rules,functions:checkNicknameAvailability,functions:updateMyNicknameSecure,functions:finalizePendingRegistration,functions:finalizeHanyangEmailVerification,functions:finalizeEnglishSocialSignup,functions:verifyEmailCode,functions:discardIncompleteRegistration,functions:deleteAccountImmediately,functions:onDeletedAuthUserNicknameCleanup
   ```

   `nicknamePolicyState/current`가 `{version: 3, status: "ready"}`가 아니면 새 예약 트랜잭션은 `unavailable`로 실패합니다. 가입 완료와 아이디 변경은 잠시 재시도가 필요합니다. 로그인·기존 프로필 조회·채팅·아이디를 그대로 둔 프로필 수정은 이 게이트를 사용하지 않습니다. 클라이언트가 게이트나 예약을 직접 쓰는 것은 금지됩니다.

   스크립트는 게이트를 `migrating`으로 표시하고 200명씩 순회합니다. 각 트랜잭션에서 현재 사용자 문서를 다시 읽어 예약만 반영하며, 사용자 이름/검색 토큰/사용자 문서는 수정하지 않습니다. 비공개·정지 계정과 새 규칙에 맞지 않는 기존 이름도 예약합니다. 삭제 중/삭제된 계정은 제외합니다. 안전하지 않은 레거시 문서 키만 해시 ID를 사용합니다.

   완료 후에만 게이트를 `ready`로 엽니다. 오류 시 닫힌 상태로 남습니다. 실행 프로세스가 끝났는지 확인하고 **동일한 run-id**로 처음부터 재실행하면 됩니다. 이미 반영된 소유권을 덮어쓰지 않습니다. 나중에 재실행할 때도 잠시 같은 게이트를 닫습니다. 완료 전에 수동으로 `ready`를 설정하지 마세요.

5. 출력 `reviewClaimHashes`와 `nicknameClaims`의 `status == "conflict"` / `reviewRequired == true`를 확인합니다. 관련 UID는 `conflictMembers`에 기록됩니다. 기존 ownerUid와 표시 이름은 보존됩니다. 충돌 이름은 새 예약·해제 모두 차단되며, 기존 사용자는 현재 이름을 유지하거나 다른 정상 이름으로 변경할 수 있습니다. 탈퇴/재실행으로 충돌 잠금이 자동 해제되지 않습니다. 관리자가 실제 남은 계정을 확인하기 전에는 잠금을 삭제하거나 소유자를 바꾸지 마세요.

6. 세 언어 앱에서 가입·아이디 변경·기존 프로필 저장을 확인합니다. 새 복합 인덱스나 Firebase Auth 설정 변경은 필요 없습니다. `ownerUid` 단일 필드 인덱스는 기존 탈퇴 복구 쿼리에 사용하므로 유지합니다. Admin SDK/운영 스크립트도 새 아이디를 직접 쓰지 말고 동일한 예약 트랜잭션을 사용해야 합니다.

## 핵심 로컬 검증

```sh
# 프로젝트 루트
flutter test test/nickname_policy_test.dart test/nickname_availability_error_test.dart test/nickname_input_test.dart
# functions
npm run test:nickname-policy
node scripts/test_searchable_user_policy.js
# 현재 firestore.rules를 로드한 로컬 Firestore emulator에서만 실행
FIRESTORE_EMULATOR_HOST=127.0.0.1:8787 node scripts/test_nickname_claims_emulator.js
```

에뮬레이터 테스트는 `demo-nickname-policy` 프로젝트의 테스트 데이터만 초기화합니다. 동시 중복 요청, NFC/대소문자/레거시 충돌, 반복 마이그레이션, 프로필 유지, 직접 쓰기 차단, 트랜잭션 실패 복구, 변경 재시도/쿨다운, 탈퇴 후 재사용과 지연 해제를 확인합니다. 운영 배포 또는 실제 사용자 데이터 반영을 수행하는 테스트가 아닙니다.
