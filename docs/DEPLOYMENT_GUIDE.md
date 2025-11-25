# Wefilling 법적 문서 배포 가이드

## 📋 개요

이 가이드는 Wefilling 앱의 개인정보 처리방침과 서비스 이용약관을 웹에 호스팅하여 Play Store와 App Store 제출 시 필요한 URL을 확보하는 방법을 설명합니다.

## 🎯 필요한 이유

- **Play Store**: 개인정보 처리방침 URL 필수
- **App Store**: 개인정보 처리방침 URL 필수
- **법적 요구사항**: 공개적으로 접근 가능한 개인정보 처리방침 필요

## 📁 호스팅할 파일

현재 `docs/` 폴더에 준비된 파일:
- `index.html` - 개인정보 처리방침 (Privacy Policy)
- `terms.html` - 서비스 이용약관 (Terms of Service)
- `privacy_policy.md` - 마크다운 버전 (참고용)

## 🚀 방법 1: GitHub Pages (추천)

### 장점
- ✅ 완전 무료
- ✅ HTTPS 자동 지원
- ✅ 안정적이고 빠름
- ✅ GitHub 저장소와 자동 동기화

### 단계별 설정

#### 1. GitHub 저장소 생성 (이미 있다면 건너뛰기)

```bash
# 로컬 저장소 초기화 (아직 안 했다면)
cd /Users/chajaemin/Desktop/wefilling-nochatbot
git init

# GitHub에서 새 저장소 생성 후
git remote add origin https://github.com/[사용자명]/wefilling-nochatbot.git
```

#### 2. 코드 푸시

```bash
# 모든 파일 추가
git add .

# 커밋
git commit -m "Add legal documents for app store submission"

# GitHub에 푸시
git push -u origin main
```

#### 3. GitHub Pages 활성화

1. GitHub 저장소 페이지로 이동
2. **Settings** 클릭
3. 왼쪽 메뉴에서 **Pages** 클릭
4. **Source** 섹션에서:
   - Branch: `main` 선택
   - Folder: `/docs` 선택
5. **Save** 클릭

#### 4. URL 확인 (5-10분 소요)

배포가 완료되면 다음 URL로 접근 가능:

```
개인정보 처리방침:
https://[사용자명].github.io/wefilling-nochatbot/index.html

서비스 이용약관:
https://[사용자명].github.io/wefilling-nochatbot/terms.html
```

**예시:**
```
https://christopherwatson.github.io/wefilling-nochatbot/index.html
https://christopherwatson.github.io/wefilling-nochatbot/terms.html
```

## 🌐 방법 2: Netlify

### 장점
- ✅ 무료
- ✅ 드래그 앤 드롭으로 간단 배포
- ✅ 자동 HTTPS
- ✅ 빠른 CDN

### 단계별 설정

1. [netlify.com](https://netlify.com) 접속 및 가입
2. "Add new site" → "Deploy manually" 클릭
3. `docs` 폴더를 드래그 앤 드롭
4. 배포 완료 후 URL 확인

**생성되는 URL:**
```
https://[랜덤이름].netlify.app/index.html
https://[랜덤이름].netlify.app/terms.html
```

### 커스텀 도메인 설정 (선택사항)

1. Netlify 대시보드에서 "Domain settings" 클릭
2. "Add custom domain" 클릭
3. 원하는 도메인 입력 (예: wefilling.com)

## 🌍 방법 3: Vercel

### 장점
- ✅ 무료
- ✅ GitHub 연동 자동 배포
- ✅ 빠른 성능
- ✅ 자동 HTTPS

### 단계별 설정

1. [vercel.com](https://vercel.com) 접속 및 가입
2. "New Project" 클릭
3. GitHub 저장소 연결
4. Root Directory를 `docs`로 설정
5. Deploy 클릭

**생성되는 URL:**
```
https://wefilling-nochatbot.vercel.app/index.html
https://wefilling-nochatbot.vercel.app/terms.html
```

## 📱 스토어 등록

### Google Play Console

1. **앱 콘텐츠** → **개인정보 보호 정책** 클릭
2. **개인정보처리방침 URL** 입력:
   ```
   https://[사용자명].github.io/wefilling-nochatbot/index.html
   ```
3. **저장** 클릭

### App Store Connect

1. **앱 정보** → **일반 정보** 클릭
2. **개인정보 처리방침 URL** 입력:
   ```
   https://[사용자명].github.io/wefilling-nochatbot/index.html
   ```
3. **저장** 클릭

## ✅ 배포 확인 체크리스트

배포 후 다음 사항을 확인하세요:

- [ ] 개인정보 처리방침 URL이 브라우저에서 정상 작동
- [ ] 서비스 이용약관 URL이 브라우저에서 정상 작동
- [ ] HTTPS로 접속 가능 (자물쇠 아이콘 확인)
- [ ] 모바일에서도 정상 표시
- [ ] 한국어/영어 내용 모두 표시
- [ ] 회사명: Christopher Watson
- [ ] 이메일: wefilling@gmail.com
- [ ] 시행일: 2025년 11월 25일

## 🔄 문서 업데이트 방법

### GitHub Pages 사용 시

```bash
# 문서 수정 후
git add docs/
git commit -m "Update legal documents"
git push

# 5-10분 후 자동으로 반영됨
```

### Netlify/Vercel 사용 시

- GitHub 연동: 자동 배포
- 수동 배포: 파일 다시 업로드

## 📞 문의 정보

법적 문서에 포함된 연락처:
- **이메일**: wefilling@gmail.com
- **운영자**: Christopher Watson

## 🎉 완료!

이제 다음 URL을 스토어 등록 시 사용할 수 있습니다:

```
개인정보 처리방침: https://[사용자명].github.io/wefilling-nochatbot/index.html
서비스 이용약관: https://[사용자명].github.io/wefilling-nochatbot/terms.html
```

## 📝 추가 참고사항

### URL 단축 (선택사항)

긴 URL이 불편하다면 다음 서비스 사용:
- [bit.ly](https://bit.ly)
- [tinyurl.com](https://tinyurl.com)

### 커스텀 도메인 (선택사항)

본인 도메인이 있다면:
1. 도메인 구매 (예: wefilling.com)
2. GitHub Pages/Netlify/Vercel에 연결
3. 더 전문적인 URL 사용 가능

**예시:**
```
https://wefilling.com/privacy
https://wefilling.com/terms
```

## ⚠️ 주의사항

1. **URL 변경 금지**: 스토어에 등록한 URL은 가급적 변경하지 마세요
2. **정기 확인**: 월 1회 URL이 정상 작동하는지 확인
3. **백업**: 문서 파일은 항상 백업 보관
4. **법률 검토**: 실제 배포 전 법률 전문가 검토 권장

## 🆘 문제 해결

### GitHub Pages가 작동하지 않을 때

1. Settings → Pages에서 설정 확인
2. 저장소가 Public인지 확인
3. 5-10분 대기 후 재시도
4. 브라우저 캐시 삭제 후 재접속

### 404 에러가 발생할 때

1. 파일명 확인 (index.html, terms.html)
2. 대소문자 정확히 입력
3. docs 폴더 경로 확인

### HTTPS 인증서 오류

- GitHub Pages/Netlify/Vercel은 자동 HTTPS 제공
- 24시간 이내 자동 해결됨
- 그래도 안 되면 고객 지원 문의

---

**작성일**: 2025-11-25  
**버전**: 1.0  
**작성자**: Wefilling Development Team

