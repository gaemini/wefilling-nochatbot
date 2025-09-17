// lib/services/review_consensus_service.dart
// 리뷰 합의 기능의 핵심 비즈니스 로직
// Feature Flag로 보호되며, 기존 서비스들을 재사용

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/review_request.dart';
import '../models/review_consensus.dart';
import '../models/meetup.dart';
import 'feature_flag_service.dart';
import 'review_adapter_service.dart';

/// 리뷰 합의 기능의 메인 서비스
class ReviewConsensusService {
  static final ReviewConsensusService _instance = ReviewConsensusService._internal();
  factory ReviewConsensusService() => _instance;
  ReviewConsensusService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FeatureFlagService _featureFlag = FeatureFlagService();
  
  // 어댑터 서비스들
  final ReviewImageAdapter _imageAdapter = ReviewImageAdapter();
  final ReviewNotificationAdapter _notificationAdapter = ReviewNotificationAdapter();
  final ReviewUserAdapter _userAdapter = ReviewUserAdapter();
  final ReviewMeetupAdapter _meetupAdapter = ReviewMeetupAdapter();

  /// Feature Flag 확인 후 기능 실행
  Future<T?> _executeIfEnabled<T>(Future<T> Function() action) async {
    final isEnabled = await _featureFlag.isReviewConsensusEnabled;
    if (!isEnabled) {
      print('리뷰 합의 기능이 비활성화됨');
      return null;
    }
    return await action();
  }

  /// 리뷰 요청 생성
  Future<String?> createReviewRequest(CreateReviewRequestData data) async {
    return await _executeIfEnabled(() async {
      try {
        final user = _userAdapter.currentUser;
        if (user == null) {
          throw Exception('로그인이 필요합니다');
        }

        // 모임 정보 확인
        final meetup = await _meetupAdapter.getMeetup(data.meetupId);
        if (meetup == null) {
          throw Exception('모임을 찾을 수 없습니다');
        }

        // 모임이 완료되었는지 확인
        final isCompleted = await _meetupAdapter.isMeetupCompleted(data.meetupId);
        if (!isCompleted) {
          throw Exception('모임이 아직 완료되지 않았습니다');
        }

        // 요청자가 모임 참여자인지 확인
        final isParticipant = await _userAdapter.isParticipantOfMeetup(data.meetupId);
        if (!isParticipant) {
          throw Exception('모임 참여자만 리뷰를 요청할 수 있습니다');
        }

        // 사용자 프로필 정보 가져오기
        final requesterProfile = await _userAdapter.getCurrentUserProfile();
        final recipientProfile = await _userAdapter.getUserProfile(data.recipientId);
        
        if (requesterProfile == null || recipientProfile == null) {
          throw Exception('사용자 정보를 찾을 수 없습니다');
        }

        // 리뷰 요청 데이터 생성
        final reviewRequest = ReviewRequest(
          id: '', // Firestore에서 자동 생성
          meetupId: data.meetupId,
          requesterId: user.uid,
          requesterName: requesterProfile['nickname'] ?? '익명',
          recipientId: data.recipientId,
          recipientName: recipientProfile['nickname'] ?? '익명',
          meetupTitle: meetup.title,
          message: data.message,
          imageUrls: data.imageUrls,
          status: ReviewRequestStatus.pending,
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(data.actualExpirationDuration),
        );

        // Firestore에 저장
        final docRef = await _firestore
            .collection('meetings')
            .doc(data.meetupId)
            .collection('pendingReviews')
            .add(reviewRequest.toFirestore());

        // 알림 발송
        await _notificationAdapter.sendReviewRequestNotification(
          recipientUserId: data.recipientId,
          requesterName: requesterProfile['nickname'] ?? '익명',
          meetupTitle: meetup.title,
          meetupId: data.meetupId,
          reviewId: docRef.id,
        );

        print('리뷰 요청 생성 완료: ${docRef.id}');
        return docRef.id;

      } catch (e) {
        print('리뷰 요청 생성 오류: $e');
        return null;
      }
    });
  }

  /// 리뷰 요청에 응답 (수락/거절)
  Future<bool> respondToReviewRequest(
    String meetupId,
    String reviewRequestId,
    bool accept,
    {String? responseMessage}
  ) async {
    return await _executeIfEnabled(() async {
      try {
        final user = _userAdapter.currentUser;
        if (user == null) {
          throw Exception('로그인이 필요합니다');
        }

        // 트랜잭션으로 안전하게 처리
        await _firestore.runTransaction((transaction) async {
          final reviewRef = _firestore
              .collection('meetings')
              .doc(meetupId)
              .collection('pendingReviews')
              .doc(reviewRequestId);

          final snapshot = await transaction.get(reviewRef);
          if (!snapshot.exists) {
            throw Exception('리뷰 요청을 찾을 수 없습니다');
          }

          final reviewRequest = ReviewRequest.fromFirestore(snapshot);
          
          // 권한 확인
          if (reviewRequest.recipientId != user.uid) {
            throw Exception('응답 권한이 없습니다');
          }

          // 응답 가능한 상태인지 확인
          if (!reviewRequest.canRespond) {
            throw Exception('응답할 수 없는 상태입니다');
          }

          // 상태 업데이트
          final newStatus = accept ? ReviewRequestStatus.accepted : ReviewRequestStatus.rejected;
          transaction.update(reviewRef, {
            'status': newStatus.name,
            'respondedAt': FieldValue.serverTimestamp(),
            'responseMessage': responseMessage,
          });

          // 알림 발송
          final userProfile = await _userAdapter.getCurrentUserProfile();
          final userName = userProfile?['nickname'] ?? '익명';

          if (accept) {
            await _notificationAdapter.sendReviewAcceptedNotification(
              requesterUserId: reviewRequest.requesterId,
              reviewerName: userName,
              meetupTitle: reviewRequest.meetupTitle,
              meetupId: meetupId,
              reviewId: reviewRequestId,
            );
          } else {
            await _notificationAdapter.sendReviewRejectedNotification(
              requesterUserId: reviewRequest.requesterId,
              reviewerName: userName,
              meetupTitle: reviewRequest.meetupTitle,
              meetupId: meetupId,
              reviewId: reviewRequestId,
            );
          }
        });

        print('리뷰 요청 응답 완료: $reviewRequestId (수락: $accept)');
        return true;

      } catch (e) {
        print('리뷰 요청 응답 오류: $e');
        return false;
      }
    }) ?? false;
  }

  /// 리뷰 이미지 업로드
  Future<List<String>> uploadReviewImages(
    List<File> imageFiles,
    String meetupId,
    String reviewId,
  ) async {
    return await _executeIfEnabled(() async {
      return await _imageAdapter.uploadMultipleReviewImages(
        imageFiles,
        meetupId,
        reviewId,
      );
    }) ?? [];
  }

  /// 사용자의 대기 중인 리뷰 요청 목록 가져오기
  Stream<List<ReviewRequest>> getPendingReviewRequests() {
    final user = _userAdapter.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collectionGroup('pendingReviews')
        .where('recipientId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          // Feature Flag 확인
          final isEnabled = await _featureFlag.isReviewConsensusEnabled;
          if (!isEnabled) return <ReviewRequest>[];

          return snapshot.docs
              .map((doc) => ReviewRequest.fromFirestore(doc))
              .where((request) => !request.isExpired)
              .toList();
        });
  }

  /// 사용자가 보낸 리뷰 요청 목록 가져오기
  Stream<List<ReviewRequest>> getSentReviewRequests() {
    final user = _userAdapter.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collectionGroup('pendingReviews')
        .where('requesterId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          // Feature Flag 확인
          final isEnabled = await _featureFlag.isReviewConsensusEnabled;
          if (!isEnabled) return <ReviewRequest>[];

          return snapshot.docs
              .map((doc) => ReviewRequest.fromFirestore(doc))
              .toList();
        });
  }

  /// 특정 모임의 리뷰 합의 결과 가져오기
  Future<ReviewConsensus?> getReviewConsensus(String meetupId) async {
    return await _executeIfEnabled(() async {
      try {
        final doc = await _firestore
            .collection('meetings')
            .doc(meetupId)
            .collection('reviews')
            .doc('consensus')
            .get();

        if (doc.exists) {
          return ReviewConsensus.fromFirestore(doc);
        }
        return null;
      } catch (e) {
        print('리뷰 합의 조회 오류: $e');
        return null;
      }
    });
  }

  /// 리뷰 합의 최종화 (모든 참여자가 응답했을 때)
  Future<bool> finalizeReviewConsensus(
    String meetupId,
    CreateReviewConsensusData consensusData,
  ) async {
    return await _executeIfEnabled(() async {
      try {
        // 모임 정보 가져오기
        final meetup = await _meetupAdapter.getMeetup(meetupId);
        if (meetup == null) {
          throw Exception('모임을 찾을 수 없습니다');
        }

        // 합의 데이터 생성
        final consensus = ReviewConsensus(
          id: 'consensus',
          meetupId: meetupId,
          meetupTitle: meetup.title,
          hostId: meetup.host,
          hostName: meetup.hostNickname,
          participantIds: consensusData.participantIds,
          participantReviews: consensusData.participantReviews,
          consensusType: consensusData.determineConsensusType(),
          averageRating: consensusData.calculateAverageRating(),
          summary: _generateConsensusSummary(consensusData),
          consensusImageUrls: _extractConsensusImages(consensusData),
          tagCounts: consensusData.calculateTagCounts(),
          createdAt: DateTime.now(),
          finalizedAt: DateTime.now(),
          statistics: _calculateStatistics(consensusData),
        );

        // 트랜잭션으로 저장
        await _firestore.runTransaction((transaction) async {
          final consensusRef = _firestore
              .collection('meetings')
              .doc(meetupId)
              .collection('reviews')
              .doc('consensus');

          transaction.set(consensusRef, consensus.toFirestore());

          // 모임 참여 카운트 증가
          await _meetupAdapter.incrementParticipationCount(meetupId);
        });

        // 완료 알림 발송
        await _notificationAdapter.sendReviewCompletedNotification(
          participantIds: consensusData.participantIds,
          meetupTitle: meetup.title,
          meetupId: meetupId,
          reviewId: 'consensus',
        );

        print('리뷰 합의 최종화 완료: $meetupId');
        return true;

      } catch (e) {
        print('리뷰 합의 최종화 오류: $e');
        return false;
      }
    }) ?? false;
  }

  /// 합의 요약 생성
  String _generateConsensusSummary(CreateReviewConsensusData data) {
    final averageRating = data.calculateAverageRating();
    final participantCount = data.participantReviews.length;
    final consensusType = data.determineConsensusType();

    switch (consensusType) {
      case ConsensusType.positive:
        return '$participantCount명의 참여자가 평균 ${averageRating.toStringAsFixed(1)}점으로 긍정적인 평가를 했습니다.';
      case ConsensusType.negative:
        return '$participantCount명의 참여자가 평균 ${averageRating.toStringAsFixed(1)}점으로 부정적인 평가를 했습니다.';
      case ConsensusType.mixed:
        return '$participantCount명의 참여자가 평균 ${averageRating.toStringAsFixed(1)}점으로 다양한 의견을 보였습니다.';
      default:
        return '$participantCount명의 참여자가 평균 ${averageRating.toStringAsFixed(1)}점으로 중립적인 평가를 했습니다.';
    }
  }

  /// 합의 이미지 추출
  List<String> _extractConsensusImages(CreateReviewConsensusData data) {
    final allImages = <String>[];
    for (final participant in data.participantReviews.values) {
      allImages.addAll(participant.imageUrls);
    }
    // 중복 제거 및 최대 10개로 제한
    return allImages.toSet().take(10).toList();
  }

  /// 통계 계산
  Map<String, dynamic> _calculateStatistics(CreateReviewConsensusData data) {
    final ratings = data.participantReviews.values.map((p) => p.rating).toList();
    
    if (ratings.isEmpty) {
      return {'participantCount': 0};
    }

    final sum = ratings.reduce((a, b) => a + b);
    final mean = sum / ratings.length;
    final variance = ratings.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) / ratings.length;
    
    return {
      'participantCount': ratings.length,
      'averageRating': mean,
      'variance': variance,
      'standardDeviation': variance > 0 ? variance : 0,
      'minRating': ratings.reduce((a, b) => a < b ? a : b),
      'maxRating': ratings.reduce((a, b) => a > b ? a : b),
      'ratingDistribution': _calculateRatingDistribution(ratings),
    };
  }

  /// 평점 분포 계산
  Map<String, int> _calculateRatingDistribution(List<double> ratings) {
    final distribution = <String, int>{
      '1': 0, '2': 0, '3': 0, '4': 0, '5': 0,
    };

    for (final rating in ratings) {
      final rounded = rating.round().clamp(1, 5);
      distribution[rounded.toString()] = (distribution[rounded.toString()] ?? 0) + 1;
    }

    return distribution;
  }

  /// 만료된 리뷰 요청 정리 (배치 작업)
  Future<int> cleanupExpiredRequests() async {
    return await _executeIfEnabled(() async {
      try {
        final now = Timestamp.now();
        int cleanedCount = 0;

        // 만료된 요청들 찾기
        final expiredRequests = await _firestore
            .collectionGroup('pendingReviews')
            .where('status', isEqualTo: 'pending')
            .where('expiresAt', isLessThan: now)
            .get();

        // 배치로 상태 업데이트
        final batch = _firestore.batch();
        
        for (final doc in expiredRequests.docs) {
          batch.update(doc.reference, {
            'status': 'expired',
            'updatedAt': FieldValue.serverTimestamp(),
          });
          cleanedCount++;
        }

        if (cleanedCount > 0) {
          await batch.commit();
          print('만료된 리뷰 요청 정리 완료: ${cleanedCount}개');
        }

        return cleanedCount;
      } catch (e) {
        print('만료 요청 정리 오류: $e');
        return 0;
      }
    }) ?? 0;
  }
}
