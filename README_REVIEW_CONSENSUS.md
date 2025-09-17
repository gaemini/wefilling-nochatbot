# 🎯 리뷰 합의 기능 - 안전한 배포 가이드

## 🚀 빠른 시작

### 1. 기능 활성화 (관리자용)
```javascript
// Firebase Console > Firestore > admin_settings > feature_flags 문서에서
{
  "FEATURE_REVIEW_CONSENSUS": true
}
```

### 2. 로컬 개발 환경
```dart
// lib/main.dart에서 (개발 중에만)
final featureFlag = FeatureFlagService();
await featureFlag.setLocalFlag('FEATURE_REVIEW_CONSENSUS', true);
```

### 3. 필수 인덱스 생성
```bash
# migration/firestore_indexes.txt 파일 참조하여 Firebase Console에서 인덱스 생성
```

## 📦 새로 추가된 파일들

### 핵심 서비스
- `lib/services/feature_flag_service.dart` - Feature Flag 관리
- `lib/services/review_consensus_service.dart` - 리뷰 합의 핵심 로직
- `lib/services/review_adapter_service.dart` - 기존 서비스 재사용 어댑터

### 데이터 모델
- `lib/models/review_request.dart` - 리뷰 요청 모델
- `lib/models/review_consensus.dart` - 리뷰 합의 모델

### UI 화면
- `lib/screens/review_request_screen.dart` - 리뷰 요청 화면
- `lib/screens/review_accept_screen.dart` - 리뷰 수락/거절 화면

### 테스트 & 도구
- `test/review_consensus_test.dart` - 단위 테스트
- `test/firestore_rules_test.dart` - 보안 규칙 테스트
- `scripts/compatibility_check.dart` - 호환성 검증 도구

### 문서
- `docs/reviews-consensus.md` - 상세 기술 문서
- `migration/firestore_indexes.txt` - 인덱스 생성 가이드

## 🔐 보안 강화 사항

### 새로운 Firestore 규칙
```javascript
// meetings/{meetupId}/pendingReviews - 모임 참여자만 접근
// meetings/{meetupId}/reviews - 참여자 읽기, 서버 쓰기만
// admin_settings - 관리자만 쓰기
```

### 데이터 보호
- 모임 참여자 검증
- 요청자/수신자 권한 확인
- 상태 전환 규칙 적용
- 중요 데이터 불변성 보장

## 🧪 배포 전 체크리스트

### 자동화된 검증
```bash
# 전체 호환성 테스트 실행
dart scripts/compatibility_check.dart

# Flutter 정적 분석
flutter analyze

# 단위 테스트 실행
flutter test

# 보안 규칙 테스트
dart test/firestore_rules_test.dart
```

### 수동 검증
- [ ] 기존 게시판 기능 정상 동작
- [ ] 기존 모임 생성/참여 정상 동작
- [ ] 기존 이미지 업로드 정상 동작
- [ ] 기존 알림 시스템 정상 동작
- [ ] 기존 프로필 관리 정상 동작

## 🎛️ Feature Flag 제어

### 개발/테스트 환경
```dart
// 로컬에서 기능 활성화
final featureFlag = FeatureFlagService();
await featureFlag.setLocalFlag('FEATURE_REVIEW_CONSENSUS', true);

// 상태 확인
final isEnabled = await featureFlag.isReviewConsensusEnabled;
print('Review Consensus Enabled: $isEnabled');
```

### 프로덕션 환경
```javascript
// Firebase Console > Firestore Database > admin_settings > feature_flags
{
  "FEATURE_REVIEW_CONSENSUS": false,  // 기본값: 비활성화
  "updatedAt": "2024-01-15T10:00:00Z",
  "updatedBy": "admin_user_id"
}
```

### 점진적 롤아웃
1. **단계 1**: 내부 테스터만 (베타 사용자)
2. **단계 2**: 10% 사용자에게 노출
3. **단계 3**: 50% 사용자에게 노출  
4. **단계 4**: 100% 사용자에게 노출

## 🚨 비상 롤백 방법

### 즉시 비활성화 (권장)
```javascript
// Firebase Console에서 즉시 변경
admin_settings/feature_flags: {
  "FEATURE_REVIEW_CONSENSUS": false
}
```

### 완전 제거 (최후 수단)
```bash
# 새로운 파일들 제거
rm -rf lib/services/review_*
rm -rf lib/models/review_*  
rm -rf lib/screens/review_*
rm -rf test/review_*

# 기존 파일에서 관련 코드 제거
# (Feature Flag 검색하여 제거)
```

## 📊 모니터링 포인트

### 성능 지표
- 앱 시작 시간 (기준: +50ms 이내)
- 메모리 사용량 (기준: +10MB 이내)
- API 응답 시간 (기준: +100ms 이내)

### 비즈니스 지표
- 크래시율 (기준: 0.1% 이하)
- 사용자 이탈률 모니터링
- 새 기능 사용률

### Firebase 지표
- Firestore 읽기/쓰기 횟수
- Storage 사용량
- Cloud Functions 실행 시간

## 🛠️ 개발 가이드

### 새 기능 확장 시
```dart
// 반드시 Feature Flag로 보호
final isEnabled = await _featureFlag.isReviewConsensusEnabled;
if (!isEnabled) return null;

// 기존 서비스 재사용
final imageUrls = await _reviewImageAdapter.uploadMultipleReviewImages(...);

// 에러 처리 필수
try {
  // 새 기능 로직
} catch (e) {
  print('Review feature error: $e');
  return fallbackValue;
}
```

### 테스트 작성
```dart
// Feature Flag 테스트 필수
test('기능 비활성화 시 null 반환', () async {
  await featureFlag.setLocalFlag('FEATURE_REVIEW_CONSENSUS', false);
  final result = await service.createReviewRequest(...);
  expect(result, null);
});
```

## 📱 사용자 가이드

### 리뷰 요청 흐름
1. 완료된 모임에서 "리뷰 요청" 버튼 클릭
2. 참여자 선택 및 메시지 작성
3. 이미지 첨부 (선택사항)
4. 요청 전송

### 리뷰 응답 흐름
1. 알림에서 리뷰 요청 확인
2. 요청 내용 검토
3. 수락/거절 선택
4. 응답 메시지 작성 (선택사항)

## 🔧 문제 해결

### 자주 발생하는 문제

#### 1. Feature Flag가 작동하지 않음
```dart
// 해결방법
final featureFlag = FeatureFlagService();
featureFlag.clearCache();
```

#### 2. 권한 오류
- Firestore 규칙 확인
- 사용자 권한 상태 확인
- 모임 참여자 여부 확인

#### 3. 이미지 업로드 실패
- 네트워크 연결 확인
- Firebase Storage 권한 확인
- 이미지 크기 제한 확인 (최대 10MB)

### 디버그 명령어
```dart
// Feature Flag 상태 확인
final flags = await FeatureFlagService().getAllFlags();

// Smoke Test 실행
await ReviewConsensusSmokeTest.runSmokeTests();

// 보안 규칙 테스트
runSecurityTests();
```

## 📞 지원

### 개발팀 연락처
- **긴급 문제**: [긴급 연락처]
- **기술 문의**: [기술 문의 채널]
- **버그 신고**: [이슈 트래커]

### 자가 진단 도구
```bash
# 전체 시스템 상태 확인
dart scripts/compatibility_check.dart

# 성능 영향도 측정
flutter drive --profile test_driver/performance_test.dart
```

## 📈 로드맵

### v1.1 (예정)
- [ ] 리뷰 템플릿 기능
- [ ] 자동 리뷰 요청
- [ ] 다국어 지원

### v1.2 (예정)  
- [ ] 음성 메모 첨부
- [ ] 리뷰 분석 대시보드
- [ ] API 개방

---

## ⚠️ 중요 참고사항

### 데이터 보존 정책
- **리뷰 요청**: 6개월 후 자동 아카이브
- **리뷰 합의**: 영구 보존
- **이미지 파일**: 1년 후 정리

### 프라이버시 고려사항
- 개인정보는 암호화 저장
- 사용자 동의 없이 데이터 공유 금지
- GDPR 준수 (삭제 요청 지원)

### 라이선스
이 기능은 기존 앱의 라이선스를 따릅니다.

---

**🔒 보안 알림**: 이 기능은 모임 참여자 간의 신뢰를 바탕으로 설계되었습니다. 악용 신고 시스템과 함께 운영하시기 바랍니다.
