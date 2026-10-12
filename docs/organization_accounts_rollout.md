# 단체 계정 운영 및 단계적 적용

이 문서는 소비자 앱에서 단체를 만들지 않고, Firebase Admin SDK CLI로만
단체와 비공개 초대를 발급하기 위한 운영 절차다. 단체는 Auth 사용자가 아니며
`users`에 가짜 단체 문서를 만들지 않는다.

## 데이터와 권한 경계

- 사람: `users/{uid}` + Firebase Auth
- 공개 단체: `organizations/{orgId}`
- 비공개 운영 정보: `organization_private/{orgId}`
- 담당자 권한: `organization_memberships/{orgId}_{uid}`
- 초대/프로비저닝: `organization_invites`, `organization_provisioning`
- 공용 검색 ID 점유: `identity_handles/{normalizedHandle}`
- 단체 검색 투영: `search_entities/organization_{orgId}`
- 감사/권한: `organization_audit_logs`, `organization_entitlements`
- 개인의 단체 팔로우: `organization_follows/{orgId}_{uid}`

클라이언트는 단체, 초대, membership, 검색 ID, 감사, 유료 권한을 직접
생성하거나 변경할 수 없다. 발급/정지/소유권/확인/파트너/유료 권한 작업은
Admin SDK 코드에서도 작업 시점에 운영자 Auth 계정의
`platformAdmin: true` Custom Claim을 다시 확인한다. 단체별 역할은 Custom
Claim이 아니라 membership의 `owner`, `manager`, `editor`, `viewer`로 관리한다.

## 안전한 적용 순서

공개 검색 플래그 `feature_organization_profiles`는 기본값이 `false`다. 다음
단계가 끝나기 전에는 켜지 않는다.

1. 현재 프로젝트/환경을 확인하고 Firestore 백업 또는 PITR 정책을 확인한다.
2. Functions를 빌드하고, 개인 닉네임을 `identity_handles`에도 원자적으로
   점유하는 호환 코드를 먼저 배포한다. 이 단계에는 실제 단체를 만들지 않는다.
3. 개인 ID 브리지 마이그레이션을 dry-run 후 적용한다. 충돌은 덮어쓰지 않고
   `conflict`, `reviewRequired`로 잠근다.
4. Firestore/Storage Rules를 dry-run으로 컴파일한 뒤 배포한다.
5. 비공개 초대 딥링크를 처리하는 호환 앱을 배포한다. 기존 개인 로그인 호출은
   기본 인자가 유지되어 기존 한양메일/개인 온보딩 경로가 그대로 동작한다.
6. Google, Apple, Email/Password 공급자와 이메일 발송 설정을 확인한다.
7. 운영자 claim을 발급하고 반드시 로그아웃/로그인 또는 ID 토큰 강제 갱신 후
   관리자 CLI dry-run을 실행한다.
8. 첫 단체 값과 공개 정책을 재확인한 뒤에만 `--apply`한다.
9. 초대 수락, 개인 계정 연결 동의, Apple relay 검토, 단체 전용 진입을 확인한다.
10. 호환 앱 보급 후 공개 단체 검색 플래그를 제한적으로 활성화한다.

개인 ID 마이그레이션 예시:

```bash
cd functions
npm run migrate:identity-handles -- \
  --project '<FIREBASE_PROJECT_ID>'

npm run migrate:identity-handles -- \
  --project '<FIREBASE_PROJECT_ID>' \
  --confirm-project '<FIREBASE_PROJECT_ID>' \
  --apply
```

스크립트는 재실행 가능하다. 기존 소유권을 덮어쓰지 않으며 충돌 보고에는 원문
검색 ID 대신 해시 지문만 출력한다.

## 최초 운영자 권한

대상 UID를 확인한 뒤 dry-run하고, 서버 셸에서 프로젝트 ID를 한 번 더 환경
변수로 확인한 경우에만 적용한다. 기존 Custom Claim은 병합된다.

```bash
cd functions
npm run organization:admin -- grant-platform-admin \
  --project '<FIREBASE_PROJECT_ID>' \
  --environment '<staging-or-production>' \
  --target-uid '<OPERATOR_AUTH_UID>'

ALLOW_PLATFORM_ADMIN_BOOTSTRAP='<FIREBASE_PROJECT_ID>' \
npm run organization:admin -- grant-platform-admin \
  --project '<FIREBASE_PROJECT_ID>' \
  --confirm-project '<FIREBASE_PROJECT_ID>' \
  --environment '<staging-or-production>' \
  --target-uid '<OPERATOR_AUTH_UID>' \
  --apply
```

## 단체 발급

실제 첫 단체를 만들기 전에 다음 값을 모두 사람이 확인한다.

- Firebase 프로젝트와 대상 환경
- 단체명과 전역 고유 `@검색ID`
- 대표 담당자 연락 이메일
- 허용 공급자(`google.com`, `apple.com`, `password`)
- 확인 상태와 초기 공개 여부

초기 공개 여부는 항상 `false`, lifecycle은 `awaiting_owner`다. 담당자 인증과
membership 트랜잭션이 완료되어야 `active`/검색 가능 상태가 된다.

```bash
cd functions
npm run organization:admin -- create-organization \
  --project '<FIREBASE_PROJECT_ID>' \
  --environment '<staging-or-production>' \
  --operator-uid '<PLATFORM_ADMIN_UID>' \
  --request-id '<UNIQUE_REQUEST_ID>' \
  --org-name '<ORG_NAME>' \
  --org-handle '<ORG_HANDLE>' \
  --org-type '<ORG_TYPE>' \
  --org-affiliation '<ORG_AFFILIATION>' \
  --org-description '<ORG_DESCRIPTION>' \
  --org-logo '<HTTPS_LOGO_URL>' \
  --org-contact-email '<PUBLIC_CONTACT_EMAIL>' \
  --owner-contact-email '<OWNER_CONTACT_EMAIL>' \
  --allowed-login-providers 'google.com,apple.com,password'
```

dry-run은 프로젝트/환경, 가린 이메일, 기존 Auth 공급자, ID 충돌, 같은 표시명
개수, 생성 예정 문서, `awaiting_owner`/비공개 상태를 보여준다. 실제 발급은 같은
명령에 다음을 추가한다.

```text
--confirm-project '<FIREBASE_PROJECT_ID>' --apply \
--invite-output '<GIT 밖의 새 파일 경로>'
```

초대 원문은 Firestore나 표준 출력에 남지 않고, 지정한 새 파일에만 권한 0600으로
한 번 기록된다. CLI는 이 새 파일을 서버 변경 전에 먼저 선점하므로 누락되거나
이미 존재하는 출력 경로 때문에 발급 후 토큰을 잃지 않는다. 같은 `REQUEST_ID`
재시도는 문서를 중복 생성하지 않으며 토큰을
다시 출력하지 않는다. 파일 저장 전에 프로세스가 종료됐다면 기존 토큰을
복구하려 하지 말고 새 request ID로 `resend-organization-invite`를 실행한다.

## 운영 명령

모든 명령은 기본 dry-run이며 실제 반영에는 정확한 `--confirm-project`와
`--apply`가 필요하다. CLI를 실행하는 서버/운영 셸에는 해당 프로젝트에만
권한을 가진 Application Default Credentials가 있어야 하며 서비스 계정 키를
저장소나 명령 인자에 넣지 않는다.

```text
invite-organization-owner       새 owner 초대
resend-organization-invite      기존 pending 초대 취소 후 새 토큰 발급
cancel-organization-invite      pending 초대 취소
update-organization             공개 프로필/확인/파트너 상태 수정
suspend-organization            검색 비공개 및 운영 정지
activate-organization           active owner가 있을 때만 재활성화
transfer-organization-owner     active membership 사이에서 원자적 이전
update-organization-entitlements 유료 권한과 boolean feature 수정
approve-organization-invite     Google/Apple 이메일 불일치 신원 수동 승인
```

프로필 확인 상태는 `--verification-status`, 파트너 상태는
`--partner-status`로 `update-organization`에서만 변경한다. 유료 권한은
`--entitlement-status`와 `--features-json`을 사용한다. 감사 로그에는 작업자,
요청 ID와 변경 필드만 기록하며 비밀번호·토큰·설정 링크는 기록하지 않는다.

## 공급자와 충돌 처리

- Password는 Firebase의 확인된 이메일이 초대 이메일과 일치해야 한다.
- Google 이메일이 초대 이메일과 다르면 자동 연결하지 않고, 확인된 Google
  계정의 정확한 Firebase UID를 운영자가 승인할 때까지
  `identity_pending_review`로 남긴다.
- Apple은 Firebase UID와 `apple.com` 공급자를 기준으로 한다. relay/이메일
  불일치는 자동 연결하지 않고 같은 운영자 검토 상태로 남긴다.
- 기존 개인 UID는 사용자 동의 후 membership만 추가한다. 개인 프로필, 친구,
  게시물, 채팅, 알림, 국적과 공개 설정은 변경하지 않는다.
- 초대로 처음 생성된 사용자만 `accountUsage: organization_only`이며 사람 검색과
  개인 온보딩에서 제외한다.
- 동일 이메일의 서로 다른 Auth UID를 자동 병합하지 않는다.
- 마지막 owner가 Auth 탈퇴하면 단체/콘텐츠를 삭제하지 않고 비공개
  `awaiting_owner`로 돌려 운영자가 새 owner를 발급할 수 있게 한다.

Email/Password 초대를 쓰려면 Firebase Auth Email/Password 공급자, 비밀번호
재설정 continue URL 도메인, Gmail 발송 설정을 먼저 확인한다. 메일 발송 실패는
초대 수락으로 처리되지 않는다. Google/Apple 공급자의 기존 개인 로그인 설정은
변경하지 않는다.

## 공개 콘텐츠와 복귀

단체 공개 검색은 feature flag가 꺼지면 즉시 기존 개인 검색만 사용한다. 단체
콘텐츠 작성은 레거시 앱이 `authorId -> users/{uid}`로 해석하는 동안 노출하지
않는다. 향후 활성화할 때는 `actorType`, `actorId`, `createdByUid`,
`lastEditedByUid`, `actorSnapshot`을 별도로 저장하고 서버에서 active membership
역할을 확인해야 한다. `actorType`이 없는 기존 콘텐츠는 개인 작성자로 유지한다.

문제가 생기면 검색 flag를 끄고, 해당 단체를 `suspend-organization`, 아직
사용하지 않은 초대를 `cancel-organization-invite`로 중지한다. 이 복귀 절차는
사용자 문서, membership, 읽음 상태, 채팅, 콘텐츠나 감사 로그를 삭제하지 않는다.

## 배포 전 미확인 항목

- 실제 운영자 UID와 claim 발급
- 첫 단체의 실데이터 및 공개 승인
- Google/Apple 콘솔과 Email/Password 공급자 운영 설정
- 비밀번호 설정 continue URL의 Auth 허용 도메인 및 실제 랜딩 동작
- 운영 SMTP 전달 성공
- Android/iOS 실기기의 cold/warm 딥링크와 공급자 인증
- Emulator Suite 기반 동시 수락/동시 재발급 테스트(Java 21 필요)
