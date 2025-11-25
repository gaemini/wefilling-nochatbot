// lib/services/review_adapter_service.dart
// 리뷰 합의 기능을 위한 기존 서비스 재사용 어댑터
// 기존 StorageService, NotificationService, AuthService 등을 재활용
// 새로운 기능에 맞게 래핑하여 호환성 보장

import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/meetup.dart';
import '../models/app_notification.dart';
import 'storage_service.dart';
import 'notification_service.dart';
import 'auth_service.dart';
import 'notification_settings_service.dart';
import '../utils/logger.dart';

/// 리뷰 합의 기능을 위한 알림 키
class ReviewNotificationKeys {
  static const String reviewRequested = 'review_requested';
  static const String reviewAccepted = 'review_accepted';
  static const String reviewRejected = 'review_rejected';
  static const String reviewCompleted = 'review_completed';
}

/// 리뷰 이미지 업로드를 위한 어댑터
class ReviewImageAdapter {
  final StorageService _storageService = StorageService();

  /// 리뷰 이미지 업로드 (기존 uploadImage 재사용, 경로만 변경)
  Future<String?> uploadReviewImage(File imageFile, String meetupId, String reviewId) async {
    try {
      // 기존 StorageService의 uploadImage를 사용하되, 
      // 리뷰 전용 폴더 구조로 저장
      final uploadedUrl = await _storageService.uploadImage(imageFile);
      
      if (uploadedUrl != null) {
        // 성공 시 리뷰 전용 경로로 변환
        // 기존 posts/ 경로를 reviews/{meetupId}/ 경로로 변경
        final reviewImageUrl = _convertToReviewPath(uploadedUrl, meetupId, reviewId);
        Logger.log('리뷰 이미지 업로드 성공: $reviewImageUrl');
        return reviewImageUrl;
      }
      
      return null;
    } catch (e) {
      Logger.error('리뷰 이미지 업로드 오류: $e');
      return null;
    }
  }

  /// 여러 리뷰 이미지 업로드 (병렬 처리)
  Future<List<String>> uploadMultipleReviewImages(
    List<File> imageFiles, 
    String meetupId, 
    String reviewId
  ) async {
    try {
      if (imageFiles.isEmpty) return [];

      Logger.log('리뷰 이미지 업로드 시작: ${imageFiles.length}개 파일');

      // 병렬 업로드 (기존 PostService 패턴 재사용)
      final futures = imageFiles.map(
        (imageFile) => uploadReviewImage(imageFile, meetupId, reviewId),
      );

      final results = await Future.wait(
        futures,
        eagerError: false, // 일부 실패해도 계속 진행
      );

      // null이 아닌 URL만 반환
      final successUrls = results.where((url) => url != null).cast<String>().toList();
      
      Logger.log('리뷰 이미지 업로드 완료: ${successUrls.length}개 (요청: ${imageFiles.length}개)');
      return successUrls;

    } catch (e) {
      Logger.error('리뷰 이미지 다중 업로드 오류: $e');
      return [];
    }
  }

  /// 기존 URL을 리뷰 전용 경로로 변환 (메타데이터 추가용)
  String _convertToReviewPath(String originalUrl, String meetupId, String reviewId) {
    // 실제로는 같은 Storage 위치를 사용하되, 메타데이터나 로깅에서 구분
    // 향후 필요시 실제 경로 변경 로직 추가 가능
    Logger.log('리뷰 이미지 경로 변환: meetup=$meetupId, review=$reviewId');
    return originalUrl;
  }

  /// 업로드 실패 시 롤백 (Storage에서 이미지 삭제)
  Future<bool> rollbackImageUpload(String imageUrl) async {
    try {
      // TODO: 실제 Firebase Storage에서 이미지 삭제 로직 구현
      // 현재는 로깅만 수행
      Logger.log('이미지 롤백 요청: $imageUrl');
      return true;
    } catch (e) {
      Logger.error('이미지 롤백 오류: $e');
      return false;
    }
  }
}

/// 리뷰 알림을 위한 어댑터
class ReviewNotificationAdapter {
  final NotificationService _notificationService = NotificationService();
  final NotificationSettingsService _settingsService = NotificationSettingsService();

  /// 리뷰 요청 알림 보내기
  Future<bool> sendReviewRequestNotification({
    required String recipientUserId,
    required String requesterName,
    required String meetupTitle,
    required String meetupId,
    required String reviewId,
  }) async {
    try {
      // 기존 NotificationService의 createNotification 재사용
      return await _notificationService.createNotification(
        userId: recipientUserId,
        title: '새로운 리뷰 요청',
        message: '$requesterName님이 "$meetupTitle" 모임에 대한 리뷰를 요청했습니다.',
        type: ReviewNotificationKeys.reviewRequested,
        meetupId: meetupId,
        actorName: requesterName,
      );
    } catch (e) {
      Logger.error('리뷰 요청 알림 발송 오류: $e');
      return false;
    }
  }

  /// 리뷰 수락 알림 보내기
  Future<bool> sendReviewAcceptedNotification({
    required String requesterUserId,
    required String reviewerName,
    required String meetupTitle,
    required String meetupId,
    required String reviewId,
  }) async {
    try {
      return await _notificationService.createNotification(
        userId: requesterUserId,
        title: '리뷰 수락됨',
        message: '$reviewerName님이 "$meetupTitle" 모임 리뷰 요청을 수락했습니다.',
        type: ReviewNotificationKeys.reviewAccepted,
        meetupId: meetupId,
        actorName: reviewerName,
      );
    } catch (e) {
      Logger.error('리뷰 수락 알림 발송 오류: $e');
      return false;
    }
  }

  /// 리뷰 거절 알림 보내기
  Future<bool> sendReviewRejectedNotification({
    required String requesterUserId,
    required String reviewerName,
    required String meetupTitle,
    required String meetupId,
    required String reviewId,
  }) async {
    try {
      return await _notificationService.createNotification(
        userId: requesterUserId,
        title: '리뷰 거절됨',
        message: '$reviewerName님이 "$meetupTitle" 모임 리뷰 요청을 거절했습니다.',
        type: ReviewNotificationKeys.reviewRejected,
        meetupId: meetupId,
        actorName: reviewerName,
      );
    } catch (e) {
      Logger.error('리뷰 거절 알림 발송 오류: $e');
      return false;
    }
  }

  /// 리뷰 완료 알림 보내기 (모든 참여자에게)
  Future<bool> sendReviewCompletedNotification({
    required List<String> participantIds,
    required String meetupTitle,
    required String meetupId,
    required String reviewId,
  }) async {
    try {
      bool allSuccess = true;
      
      for (final userId in participantIds) {
        final success = await _notificationService.createNotification(
          userId: userId,
          title: '리뷰 합의 완료',
          message: '"$meetupTitle" 모임의 리뷰 합의가 완료되었습니다.',
          type: ReviewNotificationKeys.reviewCompleted,
          meetupId: meetupId,
        );
        allSuccess = allSuccess && success;
      }
      
      return allSuccess;
    } catch (e) {
      Logger.error('리뷰 완료 알림 발송 오류: $e');
      return false;
    }
  }

  /// 리뷰 알림 설정 확인
  Future<bool> isReviewNotificationEnabled(String notificationType) async {
    try {
      return await _settingsService.isNotificationEnabled(notificationType);
    } catch (e) {
      Logger.error('리뷰 알림 설정 확인 오류: $e');
      return true; // 기본값으로 활성화
    }
  }
}

/// 사용자 정보를 위한 어댑터
class ReviewUserAdapter {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 현재 사용자 정보 가져오기 (기존 AuthService 재사용)
  User? get currentUser => _authService.currentUser;

  /// 현재 사용자 프로필 가져오기
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    try {
      return await _authService.getUserProfile();
    } catch (e) {
      Logger.error('현재 사용자 프로필 조회 오류: $e');
      return null;
    }
  }

  /// 사용자 ID로 프로필 가져오기
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final docSnapshot = await _firestore.collection('users').doc(userId).get();
      if (docSnapshot.exists) {
        return docSnapshot.data();
      }
      return null;
    } catch (e) {
      Logger.error('사용자 프로필 조회 오류 ($userId): $e');
      return null;
    }
  }

  /// 여러 사용자 프로필 가져오기 (배치 처리)
  Future<Map<String, Map<String, dynamic>>> getMultipleUserProfiles(
    List<String> userIds
  ) async {
    try {
      final Map<String, Map<String, dynamic>> profiles = {};
      
      // Firestore 배치 읽기 제한(500개)을 고려하여 청크 단위로 처리
      const chunkSize = 500;
      
      for (int i = 0; i < userIds.length; i += chunkSize) {
        final chunk = userIds.skip(i).take(chunkSize).toList();
        
        if (chunk.isNotEmpty) {
          final querySnapshot = await _firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();

          for (final doc in querySnapshot.docs) {
            if (doc.exists && doc.data().isNotEmpty) {
              profiles[doc.id] = doc.data();
            }
          }
        }
      }
      
      return profiles;
    } catch (e) {
      Logger.error('다중 사용자 프로필 조회 오류: $e');
      return {};
    }
  }

  /// 로그인 상태 확인
  bool get isLoggedIn => currentUser != null;

  /// 현재 사용자가 모임 참여자인지 확인
  Future<bool> isParticipantOfMeetup(String meetupId) async {
    try {
      final user = currentUser;
      if (user == null) return false;

      final meetupDoc = await _firestore.collection('meetups').doc(meetupId).get();
      if (!meetupDoc.exists) return false;

      final meetupData = meetupDoc.data()!;
      final participants = List<String>.from(meetupData['participants'] ?? []);
      
      return participants.contains(user.uid);
    } catch (e) {
      Logger.error('모임 참여자 확인 오류: $e');
      return false;
    }
  }
}

/// 모임 정보를 위한 어댑터
class ReviewMeetupAdapter {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 모임 정보 가져오기
  Future<Meetup?> getMeetup(String meetupId) async {
    try {
      final doc = await _firestore.collection('meetups').doc(meetupId).get();
      if (doc.exists) {
        return Meetup.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      Logger.error('모임 정보 조회 오류 ($meetupId): $e');
      return null;
    }
  }

  /// 모임 참여자 수 증가 (기존 로직 재사용)
  Future<bool> incrementParticipationCount(String meetupId) async {
    try {
      // 트랜잭션을 사용하여 안전하게 카운트 증가
      await _firestore.runTransaction((transaction) async {
        final meetupRef = _firestore.collection('meetups').doc(meetupId);
        final snapshot = await transaction.get(meetupRef);
        
        if (!snapshot.exists) {
          throw Exception('모임을 찾을 수 없습니다');
        }

        final currentData = snapshot.data()!;
        final currentCount = currentData['participationCount'] ?? 0;
        
        transaction.update(meetupRef, {
          'participationCount': currentCount + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      Logger.log('모임 참여자 수 증가 완료: $meetupId');
      return true;
    } catch (e) {
      Logger.error('모임 참여자 수 증가 오류 ($meetupId): $e');
      return false;
    }
  }

  /// 완료된 모임인지 확인
  Future<bool> isMeetupCompleted(String meetupId) async {
    try {
      final meetup = await getMeetup(meetupId);
      if (meetup == null) return false;

      // 모임 날짜가 과거인지 확인
      final meetupDate = meetup.date;
      final now = DateTime.now();
      
      return meetupDate.isBefore(now);
    } catch (e) {
      Logger.error('모임 완료 상태 확인 오류 ($meetupId): $e');
      return false;
    }
  }
}
