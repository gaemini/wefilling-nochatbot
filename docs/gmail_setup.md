# Gmail 앱 비밀번호 설정 가이드

## 문제 원인
```
Error: Missing credentials for "PLAIN"
code: 'EAUTH'
```
Gmail SMTP 인증 정보가 없어서 이메일을 전송할 수 없습니다.

## 해결 방법

### 1. Gmail 앱 비밀번호 생성

1. https://myaccount.google.com/apppasswords 접속
2. Google 계정 로그인 (**wefilling@gmail.com**)
3. 2단계 인증이 활성화되어 있어야 합니다
   - 활성화 안 되어있으면: https://myaccount.google.com/security 에서 2단계 인증 활성화
4. "앱 비밀번호" 페이지에서:
   - 앱 선택: "메일"
   - 기기 선택: "기타 (맞춤 이름)"
   - 이름 입력: "Wefilling"
   - "생성" 클릭
5. **16자리 비밀번호 복사** (예: abcd efgh ijkl mnop)
   - 공백 제거: abcdefghijklmnop

### 2. Firebase Functions에 설정

터미널에서 실행:

```bash
cd /Users/chajaemin/Desktop/wefilling-nochatbot

# Gmail 비밀번호 설정 (공백 제거한 16자리 비밀번호 입력)
firebase functions:config:set gmail.password="여기에16자리비밀번호입력"
firebase functions:config:set gmail.user="wefilling@gmail.com"

# 설정 확인
firebase functions:config:get

# Functions 재배포
firebase deploy --only functions:sendEmailVerificationCode,functions:verifyEmailCode
```

### 3. 테스트

앱에서 다시 이메일 인증번호 전송 시도

## 예시

```bash
# 예시 (실제 비밀번호로 교체하세요)
firebase functions:config:set gmail.password="abcdefghijklmnop"

# 배포
firebase deploy --only functions:sendEmailVerificationCode,functions:verifyEmailCode
```

## 주의사항

- 앱 비밀번호는 한 번만 표시되므로 꼭 복사해두세요
- 공백은 제거하고 입력하세요 (abcdefghijklmnop)
- 16자리여야 합니다

## 문제 해결

만약 여전히 오류가 발생하면:

1. Functions 로그 확인:
```bash
firebase functions:log
```

2. 설정 확인:
```bash
firebase functions:config:get
```

3. Gmail 계정 보안 설정 확인:
   - https://myaccount.google.com/security
   - "보안 수준이 낮은 앱의 액세스" 활성화 (필요한 경우)






