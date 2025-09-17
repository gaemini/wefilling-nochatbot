// lib/models/review_consensus.dart
// 리뷰 합의 결과 데이터 모델
// 최종 합의된 리뷰 정보와 통계

import 'package:cloud_firestore/cloud_firestore.dart';

/// 합의 타입
enum ConsensusType {
  positive,   // 긍정적 합의
  negative,   // 부정적 합의
  neutral,    // 중립적 합의
  mixed,      // 혼재된 의견
}

/// 리뷰 합의 결과 모델
class ReviewConsensus {
  final String id;
  final String meetupId;
  final String meetupTitle;
  final String hostId;
  final String hostName;
  final List<String> participantIds;
  final Map<String, ReviewParticipantData> participantReviews;
  final ConsensusType consensusType;
  final double averageRating;
  final String summary;
  final List<String> consensusImageUrls;
  final Map<String, int> tagCounts;
  final DateTime createdAt;
  final DateTime finalizedAt;
  final Map<String, dynamic> statistics;
  final Map<String, dynamic> metadata;

  const ReviewConsensus({
    required this.id,
    required this.meetupId,
    required this.meetupTitle,
    required this.hostId,
    required this.hostName,
    required this.participantIds,
    required this.participantReviews,
    required this.consensusType,
    required this.averageRating,
    required this.summary,
    required this.consensusImageUrls,
    required this.tagCounts,
    required this.createdAt,
    required this.finalizedAt,
    this.statistics = const {},
    this.metadata = const {},
  });

  /// Firestore 문서에서 ReviewConsensus 객체 생성
  factory ReviewConsensus.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return ReviewConsensus(
      id: doc.id,
      meetupId: data['meetupId'] ?? '',
      meetupTitle: data['meetupTitle'] ?? '',
      hostId: data['hostId'] ?? '',
      hostName: data['hostName'] ?? '',
      participantIds: List<String>.from(data['participantIds'] ?? []),
      participantReviews: _parseParticipantReviews(data['participantReviews']),
      consensusType: _parseConsensusType(data['consensusType']),
      averageRating: (data['averageRating'] ?? 0.0).toDouble(),
      summary: data['summary'] ?? '',
      consensusImageUrls: List<String>.from(data['consensusImageUrls'] ?? []),
      tagCounts: Map<String, int>.from(data['tagCounts'] ?? {}),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      finalizedAt: (data['finalizedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      statistics: Map<String, dynamic>.from(data['statistics'] ?? {}),
      metadata: Map<String, dynamic>.from(data['metadata'] ?? {}),
    );
  }

  /// Firestore에 저장할 데이터 맵 생성
  Map<String, dynamic> toFirestore() {
    return {
      'meetupId': meetupId,
      'meetupTitle': meetupTitle,
      'hostId': hostId,
      'hostName': hostName,
      'participantIds': participantIds,
      'participantReviews': _participantReviewsToMap(),
      'consensusType': consensusType.name,
      'averageRating': averageRating,
      'summary': summary,
      'consensusImageUrls': consensusImageUrls,
      'tagCounts': tagCounts,
      'createdAt': Timestamp.fromDate(createdAt),
      'finalizedAt': Timestamp.fromDate(finalizedAt),
      'statistics': statistics,
      'metadata': metadata,
    };
  }

  /// 참여자 리뷰 데이터를 맵으로 변환
  Map<String, dynamic> _participantReviewsToMap() {
    final Map<String, dynamic> result = {};
    participantReviews.forEach((key, value) {
      result[key] = value.toMap();
    });
    return result;
  }

  /// 참여자 리뷰 데이터 파싱
  static Map<String, ReviewParticipantData> _parseParticipantReviews(dynamic data) {
    if (data == null) return {};
    
    final Map<String, ReviewParticipantData> result = {};
    final reviewsMap = Map<String, dynamic>.from(data);
    
    reviewsMap.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        result[key] = ReviewParticipantData.fromMap(value);
      }
    });
    
    return result;
  }

  /// 합의 타입 파싱
  static ConsensusType _parseConsensusType(String? typeString) {
    switch (typeString) {
      case 'positive':
        return ConsensusType.positive;
      case 'negative':
        return ConsensusType.negative;
      case 'neutral':
        return ConsensusType.neutral;
      case 'mixed':
        return ConsensusType.mixed;
      default:
        return ConsensusType.neutral;
    }
  }

  /// 합의 완료 여부
  bool get isFinalized => finalizedAt.isBefore(DateTime.now().add(const Duration(seconds: 1)));

  /// 참여율 계산
  double get participationRate {
    if (participantIds.isEmpty) return 0.0;
    return participantReviews.length / participantIds.length;
  }

  /// 합의 점수 (0.0 ~ 1.0)
  double get consensusScore {
    if (participantReviews.isEmpty) return 0.0;
    
    final ratings = participantReviews.values.map((p) => p.rating).toList();
    if (ratings.isEmpty) return 0.0;
    
    // 표준편차를 이용한 합의 점수 계산 (낮을수록 합의가 잘됨)
    final mean = ratings.reduce((a, b) => a + b) / ratings.length;
    final variance = ratings.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) / ratings.length;
    final standardDeviation = variance > 0 ? variance : 0;
    
    // 표준편차를 0-1 범위로 정규화 (최대 표준편차를 2.0으로 가정)
    return 1.0 - (standardDeviation / 2.0).clamp(0.0, 1.0);
  }

  @override
  String toString() {
    return 'ReviewConsensus(id: $id, meetupId: $meetupId, consensusType: $consensusType, avgRating: $averageRating)';
  }
}

/// 참여자별 리뷰 데이터
class ReviewParticipantData {
  final String userId;
  final String userName;
  final double rating;
  final String comment;
  final List<String> tags;
  final List<String> imageUrls;
  final DateTime submittedAt;

  const ReviewParticipantData({
    required this.userId,
    required this.userName,
    required this.rating,
    required this.comment,
    required this.tags,
    required this.imageUrls,
    required this.submittedAt,
  });

  /// 맵에서 ReviewParticipantData 생성
  factory ReviewParticipantData.fromMap(Map<String, dynamic> data) {
    return ReviewParticipantData(
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      rating: (data['rating'] ?? 0.0).toDouble(),
      comment: data['comment'] ?? '',
      tags: List<String>.from(data['tags'] ?? []),
      imageUrls: List<String>.from(data['imageUrls'] ?? []),
      submittedAt: (data['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// 맵으로 변환
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'rating': rating,
      'comment': comment,
      'tags': tags,
      'imageUrls': imageUrls,
      'submittedAt': Timestamp.fromDate(submittedAt),
    };
  }
}

/// 리뷰 합의 생성을 위한 입력 데이터
class CreateReviewConsensusData {
  final String meetupId;
  final List<String> participantIds;
  final Map<String, ReviewParticipantData> participantReviews;

  const CreateReviewConsensusData({
    required this.meetupId,
    required this.participantIds,
    required this.participantReviews,
  });

  /// 평균 평점 계산
  double calculateAverageRating() {
    if (participantReviews.isEmpty) return 0.0;
    
    final ratings = participantReviews.values.map((p) => p.rating).toList();
    return ratings.reduce((a, b) => a + b) / ratings.length;
  }

  /// 태그 카운트 계산
  Map<String, int> calculateTagCounts() {
    final Map<String, int> tagCounts = {};
    
    for (final participant in participantReviews.values) {
      for (final tag in participant.tags) {
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
    }
    
    return tagCounts;
  }

  /// 합의 타입 결정
  ConsensusType determineConsensusType() {
    if (participantReviews.isEmpty) return ConsensusType.neutral;
    
    final ratings = participantReviews.values.map((p) => p.rating).toList();
    final averageRating = calculateAverageRating();
    
    // 평균이 4.0 이상이면 긍정적
    if (averageRating >= 4.0) return ConsensusType.positive;
    
    // 평균이 2.0 이하면 부정적
    if (averageRating <= 2.0) return ConsensusType.negative;
    
    // 표준편차가 크면 혼재
    final mean = averageRating;
    final variance = ratings.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) / ratings.length;
    
    if (variance > 1.0) return ConsensusType.mixed;
    
    return ConsensusType.neutral;
  }
}
