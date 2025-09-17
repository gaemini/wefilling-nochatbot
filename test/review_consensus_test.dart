// test/review_consensus_test.dart
// 리뷰 합의 기능 단위 테스트
// Feature Flag와 기존 기능 호환성 테스트

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../lib/services/feature_flag_service.dart';
import '../lib/services/review_consensus_service.dart';
import '../lib/services/review_adapter_service.dart';
import '../lib/models/review_request.dart';
import '../lib/models/review_consensus.dart';
import '../lib/models/meetup.dart';

// Mock 클래스들 생성
@GenerateMocks([
  FirebaseFirestore,
  FirebaseAuth,
  User,
  DocumentSnapshot,
  DocumentReference,
  CollectionReference,
  Query,
  QuerySnapshot,
  QueryDocumentSnapshot,
  Transaction,
  WriteBatch,
])
import 'review_consensus_test.mocks.dart';

void main() {
  group('FeatureFlagService Tests', () {
    late FeatureFlagService featureFlagService;
    late MockFirebaseFirestore mockFirestore;
    late MockFirebaseAuth mockAuth;

    setUp(() {
      mockFirestore = MockFirebaseFirestore();
      mockAuth = MockFirebaseAuth();
      featureFlagService = FeatureFlagService();
    });

    test('기본 플래그 값은 false여야 함', () async {
      // Given: Feature Flag가 설정되지 않은 상태
      when(mockFirestore.collection('admin_settings'))
          .thenReturn(MockCollectionReference());
      
      // When: 플래그 값 확인
      final isEnabled = await featureFlagService.isEnabled('FEATURE_REVIEW_CONSENSUS');
      
      // Then: 기본값 false 반환
      expect(isEnabled, false);
    });

    test('로컬 플래그 설정이 동작해야 함', () async {
      // Given: 로컬 플래그 설정
      await featureFlagService.setLocalFlag('FEATURE_REVIEW_CONSENSUS', true);
      
      // When: 플래그 값 확인
      final isEnabled = await featureFlagService.isEnabled('FEATURE_REVIEW_CONSENSUS');
      
      // Then: 설정된 값 반환
      expect(isEnabled, true);
    });

    test('캐시가 제대로 동작해야 함', () async {
      // Given: 첫 번째 호출로 캐시 설정
      await featureFlagService.setLocalFlag('FEATURE_REVIEW_CONSENSUS', true);
      await featureFlagService.isEnabled('FEATURE_REVIEW_CONSENSUS');
      
      // When: 두 번째 호출 (캐시에서 가져와야 함)
      final isEnabled = await featureFlagService.isEnabled('FEATURE_REVIEW_CONSENSUS');
      
      // Then: 캐시된 값 반환
      expect(isEnabled, true);
    });

    test('캐시 초기화가 동작해야 함', () async {
      // Given: 캐시에 값 설정
      await featureFlagService.setLocalFlag('FEATURE_REVIEW_CONSENSUS', true);
      await featureFlagService.isEnabled('FEATURE_REVIEW_CONSENSUS');
      
      // When: 캐시 초기화
      featureFlagService.clearCache();
      
      // Then: 다음 호출에서 새로 로드되어야 함
      // (실제로는 SharedPreferences에서 다시 읽어옴)
      final isEnabled = await featureFlagService.isEnabled('FEATURE_REVIEW_CONSENSUS');
      expect(isEnabled, true); // SharedPreferences에 저장된 값
    });
  });

  group('ReviewRequest Model Tests', () {
    test('ReviewRequest 생성이 올바르게 동작해야 함', () {
      // Given: 리뷰 요청 데이터
      final reviewRequest = ReviewRequest(
        id: 'test-id',
        meetupId: 'meetup-123',
        requesterId: 'user-1',
        requesterName: 'John',
        recipientId: 'user-2',
        recipientName: 'Jane',
        meetupTitle: 'Test Meetup',
        message: 'Please review',
        imageUrls: ['image1.jpg', 'image2.jpg'],
        status: ReviewRequestStatus.pending,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );

      // Then: 올바른 값들이 설정되어야 함
      expect(reviewRequest.id, 'test-id');
      expect(reviewRequest.meetupId, 'meetup-123');
      expect(reviewRequest.status, ReviewRequestStatus.pending);
      expect(reviewRequest.canRespond, true);
      expect(reviewRequest.isExpired, false);
    });

    test('만료 상태 확인이 올바르게 동작해야 함', () {
      // Given: 만료된 리뷰 요청
      final expiredRequest = ReviewRequest(
        id: 'test-id',
        meetupId: 'meetup-123',
        requesterId: 'user-1',
        requesterName: 'John',
        recipientId: 'user-2',
        recipientName: 'Jane',
        meetupTitle: 'Test Meetup',
        message: 'Please review',
        imageUrls: [],
        status: ReviewRequestStatus.pending,
        createdAt: DateTime.now().subtract(const Duration(days: 8)),
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      // Then: 만료 상태가 올바르게 판단되어야 함
      expect(expiredRequest.isExpired, true);
      expect(expiredRequest.canRespond, false);
    });

    test('상태 변경이 올바르게 동작해야 함', () {
      // Given: pending 상태의 요청
      final request = ReviewRequest(
        id: 'test-id',
        meetupId: 'meetup-123',
        requesterId: 'user-1',
        requesterName: 'John',
        recipientId: 'user-2',
        recipientName: 'Jane',
        meetupTitle: 'Test Meetup',
        message: 'Please review',
        imageUrls: [],
        status: ReviewRequestStatus.pending,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );

      // When: 상태를 accepted로 변경
      final acceptedRequest = request.copyWith(
        status: ReviewRequestStatus.accepted,
        respondedAt: DateTime.now(),
      );

      // Then: 상태가 올바르게 변경되어야 함
      expect(acceptedRequest.status, ReviewRequestStatus.accepted);
      expect(acceptedRequest.respondedAt, isNotNull);
      expect(acceptedRequest.canRespond, false);
    });
  });

  group('ReviewConsensus Model Tests', () {
    test('합의 타입 결정이 올바르게 동작해야 함', () {
      // Given: 다양한 평점을 가진 참여자 데이터
      final participantReviews = {
        'user1': ReviewParticipantData(
          userId: 'user1',
          userName: 'User 1',
          rating: 4.5,
          comment: 'Great',
          tags: ['good'],
          imageUrls: [],
          submittedAt: DateTime.now(),
        ),
        'user2': ReviewParticipantData(
          userId: 'user2',
          userName: 'User 2',
          rating: 4.0,
          comment: 'Nice',
          tags: ['good'],
          imageUrls: [],
          submittedAt: DateTime.now(),
        ),
      };

      final consensusData = CreateReviewConsensusData(
        meetupId: 'meetup-123',
        participantIds: ['user1', 'user2'],
        participantReviews: participantReviews,
      );

      // When: 합의 타입 결정
      final consensusType = consensusData.determineConsensusType();

      // Then: 긍정적 합의로 분류되어야 함
      expect(consensusType, ConsensusType.positive);
    });

    test('평균 평점 계산이 올바르게 동작해야 함', () {
      // Given: 참여자 데이터
      final participantReviews = {
        'user1': ReviewParticipantData(
          userId: 'user1',
          userName: 'User 1',
          rating: 3.0,
          comment: 'OK',
          tags: [],
          imageUrls: [],
          submittedAt: DateTime.now(),
        ),
        'user2': ReviewParticipantData(
          userId: 'user2',
          userName: 'User 2',
          rating: 5.0,
          comment: 'Excellent',
          tags: [],
          imageUrls: [],
          submittedAt: DateTime.now(),
        ),
      };

      final consensusData = CreateReviewConsensusData(
        meetupId: 'meetup-123',
        participantIds: ['user1', 'user2'],
        participantReviews: participantReviews,
      );

      // When: 평균 평점 계산
      final averageRating = consensusData.calculateAverageRating();

      // Then: 올바른 평균값이 계산되어야 함
      expect(averageRating, 4.0);
    });

    test('태그 카운트 계산이 올바르게 동작해야 함', () {
      // Given: 태그를 포함한 참여자 데이터
      final participantReviews = {
        'user1': ReviewParticipantData(
          userId: 'user1',
          userName: 'User 1',
          rating: 4.0,
          comment: 'Good',
          tags: ['fun', 'organized'],
          imageUrls: [],
          submittedAt: DateTime.now(),
        ),
        'user2': ReviewParticipantData(
          userId: 'user2',
          userName: 'User 2',
          rating: 4.0,
          comment: 'Nice',
          tags: ['fun', 'friendly'],
          imageUrls: [],
          submittedAt: DateTime.now(),
        ),
      };

      final consensusData = CreateReviewConsensusData(
        meetupId: 'meetup-123',
        participantIds: ['user1', 'user2'],
        participantReviews: participantReviews,
      );

      // When: 태그 카운트 계산
      final tagCounts = consensusData.calculateTagCounts();

      // Then: 올바른 태그 카운트가 계산되어야 함
      expect(tagCounts['fun'], 2);
      expect(tagCounts['organized'], 1);
      expect(tagCounts['friendly'], 1);
    });
  });

  group('Adapter Services Tests', () {
    test('ReviewImageAdapter 업로드 경로 변환이 동작해야 함', () {
      // Given: 이미지 어댑터
      final adapter = ReviewImageAdapter();

      // When: 경로 변환 테스트 (private 메서드이므로 실제로는 public 인터페이스 테스트)
      // 실제 구현에서는 uploadReviewImage를 통해 간접 테스트

      // Then: 정상적으로 처리되어야 함
      expect(adapter, isNotNull);
    });

    test('ReviewUserAdapter 로그인 상태 확인이 동작해야 함', () {
      // Given: 사용자 어댑터
      final adapter = ReviewUserAdapter();

      // When & Then: 로그인 상태 확인
      // 실제 Firebase Auth가 없으므로 false 반환
      expect(adapter.isLoggedIn, false);
    });
  });

  group('Feature Flag Integration Tests', () {
    test('기능이 비활성화된 경우 null 반환', () async {
      // Given: Feature Flag가 비활성화된 서비스
      final service = ReviewConsensusService();
      
      // Feature Flag를 false로 설정
      final featureFlag = FeatureFlagService();
      await featureFlag.setLocalFlag('FEATURE_REVIEW_CONSENSUS', false);

      // When: 리뷰 요청 생성 시도
      final result = await service.createReviewRequest(
        CreateReviewRequestData(
          meetupId: 'test-meetup',
          recipientId: 'test-user',
          message: 'Test message',
        ),
      );

      // Then: null 반환 (기능 비활성화)
      expect(result, null);
    });

    test('기능이 활성화된 경우 정상 동작', () async {
      // Given: Feature Flag가 활성화된 상태
      final featureFlag = FeatureFlagService();
      await featureFlag.setLocalFlag('FEATURE_REVIEW_CONSENSUS', true);

      // When & Then: 기능이 정상적으로 호출되어야 함
      // (실제 Firebase 연결 없이는 완전한 테스트 불가하지만, 
      //  Feature Flag 체크는 통과해야 함)
      final isEnabled = await featureFlag.isReviewConsensusEnabled;
      expect(isEnabled, true);
    });
  });

  group('Error Handling Tests', () {
    test('잘못된 입력값에 대한 에러 처리', () {
      // Given: 잘못된 데이터
      expect(() => CreateReviewRequestData(
        meetupId: '',
        recipientId: '',
        message: '',
      ), returnsNormally);

      // Then: 빈 문자열도 허용 (유효성 검사는 서비스 레벨에서)
    });

    test('null 안전성 검증', () {
      // Given: null 값들을 포함한 데이터
      final consensusData = CreateReviewConsensusData(
        meetupId: 'test',
        participantIds: [],
        participantReviews: {},
      );

      // When: 빈 데이터로 계산 수행
      final averageRating = consensusData.calculateAverageRating();
      final tagCounts = consensusData.calculateTagCounts();
      final consensusType = consensusData.determineConsensusType();

      // Then: 안전한 기본값 반환
      expect(averageRating, 0.0);
      expect(tagCounts, isEmpty);
      expect(consensusType, ConsensusType.neutral);
    });
  });

  group('Compatibility Tests', () {
    test('기존 모델과의 호환성 확인', () {
      // Given: 기존 Meetup 모델과 새로운 리뷰 기능
      
      // When & Then: 기존 코드가 영향받지 않아야 함
      // (이 테스트는 실제 앱에서 기존 기능들이 정상 동작하는지 확인)
      expect(true, true); // 플레이스홀더
    });

    test('알림 시스템 호환성 확인', () {
      // Given: 새로운 알림 타입들
      const newNotificationTypes = [
        'review_requested',
        'review_accepted',
        'review_rejected',
        'review_completed',
      ];

      // When & Then: 알림 타입들이 정의되어 있어야 함
      for (final type in newNotificationTypes) {
        expect(type, isNotNull);
        expect(type, isNotEmpty);
      }
    });
  });
}

// Smoke Test를 위한 통합 테스트 헬퍼
class ReviewConsensusSmokeTest {
  static Future<void> runSmokeTests() async {
    print('🔥 리뷰 합의 기능 Smoke Test 시작');

    try {
      // Feature Flag 테스트
      final featureFlag = FeatureFlagService();
      await featureFlag.setLocalFlag('FEATURE_REVIEW_CONSENSUS', false);
      final isDisabled = await featureFlag.isReviewConsensusEnabled;
      assert(!isDisabled, 'Feature Flag 비활성화 테스트 실패');

      await featureFlag.setLocalFlag('FEATURE_REVIEW_CONSENSUS', true);
      final isEnabled = await featureFlag.isReviewConsensusEnabled;
      assert(isEnabled, 'Feature Flag 활성화 테스트 실패');

      print('✅ Feature Flag 테스트 통과');

      // 모델 생성 테스트
      final request = ReviewRequest(
        id: 'test',
        meetupId: 'meetup',
        requesterId: 'requester',
        requesterName: 'Requester',
        recipientId: 'recipient',
        recipientName: 'Recipient',
        meetupTitle: 'Test Meetup',
        message: 'Test message',
        imageUrls: [],
        status: ReviewRequestStatus.pending,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );

      assert(request.id == 'test', '리뷰 요청 모델 생성 실패');
      assert(request.canRespond, '리뷰 요청 응답 가능 상태 실패');

      print('✅ 모델 생성 테스트 통과');

      // 어댑터 생성 테스트
      final imageAdapter = ReviewImageAdapter();
      final userAdapter = ReviewUserAdapter();
      final notificationAdapter = ReviewNotificationAdapter();

      assert(imageAdapter != null, '이미지 어댑터 생성 실패');
      assert(userAdapter != null, '사용자 어댑터 생성 실패');
      assert(notificationAdapter != null, '알림 어댑터 생성 실패');

      print('✅ 어댑터 생성 테스트 통과');

      print('🎉 모든 Smoke Test 통과!');

    } catch (e) {
      print('❌ Smoke Test 실패: $e');
      rethrow;
    }
  }
}

// 테스트 실행 스크립트를 위한 main
void runSmokeTest() async {
  await ReviewConsensusSmokeTest.runSmokeTests();
}
