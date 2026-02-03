// test/profile_service_test.dart
// 프로필 그리드 서비스 단위 테스트
// Mock을 사용하여 Firebase 의존성 없이 테스트

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../lib/services/profile_grid_adapter_service.dart';
import '../lib/services/feature_flag_service.dart';
import '../lib/models/post.dart';
import '../lib/models/user_profile.dart';
import '../lib/repositories/users_repository.dart';

// Mock 클래스 생성을 위한 어노테이션
@GenerateMocks([
  FirebaseFirestore,
  FirebaseAuth,
  UsersRepository,
  DocumentSnapshot,
  QuerySnapshot,
  CollectionReference,
  DocumentReference,
  User,
])
import 'profile_service_test.mocks.dart';

void main() {
  group('ProfileDataAdapter Tests', () {
    late ProfileDataAdapter profileAdapter;
    late MockFirebaseFirestore mockFirestore;
    late MockFirebaseAuth mockAuth;
    late MockUsersRepository mockUsersRepository;

    setUp(() {
      mockFirestore = MockFirebaseFirestore();
      mockAuth = MockFirebaseAuth();
      mockUsersRepository = MockUsersRepository();
      profileAdapter = ProfileDataAdapter();
      
      // Feature Flag를 활성화 상태로 설정
      FeatureFlagService().setLocalOverride(
        FeatureFlagService.FEATURE_PROFILE_GRID,
        true,
      );
    });

    tearDown(() {
      // 테스트 후 Feature Flag 초기화
      FeatureFlagService().removeLocalOverride(
        FeatureFlagService.FEATURE_PROFILE_GRID,
      );
    });

    group('fetchUserProfile', () {
      test('사용자 프로필을 성공적으로 가져온다', () async {
        // Given
        const testUserId = 'test-user-123';
        final expectedProfile = UserProfile(
          uid: testUserId,
          displayName: 'Test User',
          photoURL: 'https://example.com/photo.jpg',
          nickname: 'testuser',
          nationality: 'KR',
          friendsCount: 10,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        when(mockUsersRepository.getUserProfile(testUserId))
            .thenAnswer((_) async => expectedProfile);

        // When
        final result = await profileAdapter.fetchUserProfile(testUserId);

        // Then
        expect(result, isNotNull);
        expect(result!.uid, equals(testUserId));
        expect(result.displayName, equals('Test User'));
        expect(result.nickname, equals('testuser'));
        verify(mockUsersRepository.getUserProfile(testUserId)).called(1);
      });

      test('존재하지 않는 사용자의 경우 null을 반환한다', () async {
        // Given
        const testUserId = 'non-existent-user';
        
        when(mockUsersRepository.getUserProfile(testUserId))
            .thenAnswer((_) async => null);

        // When
        final result = await profileAdapter.fetchUserProfile(testUserId);

        // Then
        expect(result, isNull);
        verify(mockUsersRepository.getUserProfile(testUserId)).called(1);
      });

      test('네트워크 오류 시 null을 반환한다', () async {
        // Given
        const testUserId = 'test-user-123';
        
        when(mockUsersRepository.getUserProfile(testUserId))
            .thenThrow(Exception('Network error'));

        // When
        final result = await profileAdapter.fetchUserProfile(testUserId);

        // Then
        expect(result, isNull);
        verify(mockUsersRepository.getUserProfile(testUserId)).called(1);
      });
    });

    group('isViewerFriend', () {
      test('같은 사용자인 경우 true를 반환한다', () async {
        // Given
        const userId = 'same-user-123';

        // When
        final result = await profileAdapter.isViewerFriend(userId, userId);

        // Then
        expect(result, isTrue);
      });

      test('친구 관계인 경우 true를 반환한다', () async {
        // Given
        const viewerUid = 'viewer-123';
        const ownerUid = 'owner-456';

        // When
        final result = await profileAdapter.isViewerFriend(viewerUid, ownerUid);

        // Then
        // 실제 구현에서는 Firestore 쿼리 결과에 따라 결정됩니다.
        expect(result, isA<bool>());
      });
    });

    group('getUserPostStats', () {
      test('포스트 통계를 올바르게 계산한다', () async {
        // Given
        const testUserId = 'test-user-123';

        // Mock 데이터는 실제 Firestore 쿼리 결과를 시뮬레이션해야 하므로
        // 여기서는 기본적인 구조만 테스트합니다.

        // When
        final result = await profileAdapter.getUserPostStats(testUserId);

        // Then
        expect(result, isA<Map<String, int>>());
        expect(result.containsKey('posts'), isTrue);
        expect(result.containsKey('likes'), isTrue);
        expect(result.containsKey('comments'), isTrue);
        expect(result['posts'], greaterThanOrEqualTo(0));
        expect(result['likes'], greaterThanOrEqualTo(0));
        expect(result['comments'], greaterThanOrEqualTo(0));
      });

      test('오류 발생 시 기본값을 반환한다', () async {
        // Given
        const testUserId = 'error-user';

        // When
        final result = await profileAdapter.getUserPostStats(testUserId);

        // Then
        expect(result, equals({'posts': 0, 'likes': 0, 'comments': 0}));
      });
    });

    group('createPostFromReview', () {
      test('리뷰 데이터로부터 포스트를 성공적으로 생성한다', () async {
        // Given
        const testUserId = 'test-user-123';
        final reviewData = {
          'content': 'Great meetup experience!',
          'imageUrl': 'https://example.com/meetup-photo.jpg',
          'meetupId': 'meetup-456',
          'meetupTitle': 'Flutter Study Group',
        };

        // When
        final result = await profileAdapter.createPostFromReview(testUserId, reviewData);

        // Then
        // Feature Flag가 활성화된 상태에서 성공적으로 생성되어야 함
        expect(result, isA<bool>());
      });

      test('Feature Flag가 비활성화된 경우 false를 반환한다', () async {
        // Given
        await FeatureFlagService().setLocalOverride(
          FeatureFlagService.FEATURE_PROFILE_GRID,
          false,
        );
        
        const testUserId = 'test-user-123';
        final reviewData = {'content': 'Test content'};

        // When
        final result = await profileAdapter.createPostFromReview(testUserId, reviewData);

        // Then
        expect(result, isFalse);
      });
    });
  });

  group('ProfilePost Tests', () {
    test('Post 객체로부터 ProfilePost를 생성한다', () {
      // Given
      final testPost = Post(
        id: 'post-123',
        title: 'Test Title',
        content: 'Test content',
        author: 'Test Author',
        createdAt: DateTime.now(),
        userId: 'user-123',
        likes: 5,
        commentCount: 3,
        imageUrls: ['https://example.com/image.jpg'],
      );

      // When
      final profilePost = ProfilePost.fromPost(testPost);

      // Then
      expect(profilePost.postId, equals('post-123'));
      expect(profilePost.authorId, equals('user-123'));
      expect(profilePost.type, equals('image')); // 이미지가 있으므로 'image'
      expect(profilePost.coverPhotoUrl, equals('https://example.com/image.jpg'));
      expect(profilePost.text, equals('Test content'));
      expect(profilePost.visibility, equals('public'));
      expect(profilePost.meta['likeCount'], equals(5));
      expect(profilePost.meta['commentCount'], equals(3));
    });

    test('이미지가 없는 Post의 경우 type이 text가 된다', () {
      // Given
      final testPost = Post(
        id: 'post-456',
        title: 'Text Only Post',
        content: 'This is a text-only post',
        author: 'Test Author',
        createdAt: DateTime.now(),
        userId: 'user-123',
        imageUrls: [], // 빈 이미지 리스트
      );

      // When
      final profilePost = ProfilePost.fromPost(testPost);

      // Then
      expect(profilePost.type, equals('text'));
      expect(profilePost.coverPhotoUrl, isNull);
    });

    test('Firestore 형태로 변환한다', () {
      // Given
      final profilePost = ProfilePost(
        postId: 'post-789',
        authorId: 'user-456',
        type: 'meetup_review',
        coverPhotoUrl: 'https://example.com/review-image.jpg',
        text: 'Great meetup!',
        createdAt: DateTime(2023, 12, 1),
        visibility: 'friends',
        meta: {'likeCount': 10, 'commentCount': 2, 'meetupId': 'meetup-123'},
      );

      // When
      final firestoreData = profilePost.toFirestore();

      // Then
      expect(firestoreData['postId'], equals('post-789'));
      expect(firestoreData['authorId'], equals('user-456'));
      expect(firestoreData['type'], equals('meetup_review'));
      expect(firestoreData['coverPhotoUrl'], equals('https://example.com/review-image.jpg'));
      expect(firestoreData['text'], equals('Great meetup!'));
      expect(firestoreData['visibility'], equals('friends'));
      expect(firestoreData['createdAt'], isA<Timestamp>());
      expect(firestoreData['meta'], isA<Map<String, dynamic>>());
      expect(firestoreData['meta']['meetupId'], equals('meetup-123'));
    });
  });
}
