// lib/models/review_post.dart
// Instagram 스타일 후기글 시스템 모델
// 모임 후기, 사진, 평점, 태그 기능 포함

import 'package:flutter/material.dart';

class ReviewPost {
  final String id;
  final String authorId;
  final String authorName;
  final String authorProfileImage;
  final String meetupId;
  final String meetupTitle;
  final List<String> imageUrls;
  final String content;
  final String category;
  final int rating;
  final List<String> taggedUserIds;
  final DateTime createdAt;
  final List<String> likedBy;
  final int commentCount;
  final PrivacyLevel privacyLevel;
  
  ReviewPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorProfileImage,
    required this.meetupId,
    required this.meetupTitle,
    required this.imageUrls,
    required this.content,
    required this.category,
    required this.rating,
    required this.taggedUserIds,
    required this.createdAt,
    required this.likedBy,
    required this.commentCount,
    required this.privacyLevel,
  });

  factory ReviewPost.fromJson(Map<String, dynamic> json) {
    return ReviewPost(
      id: json['id'] ?? '',
      authorId: json['authorId'] ?? '',
      authorName: json['authorName'] ?? '',
      authorProfileImage: json['authorProfileImage'] ?? '',
      meetupId: json['meetupId'] ?? '',
      meetupTitle: json['meetupTitle'] ?? '',
      imageUrls: List<String>.from(json['imageUrls'] ?? []),
      content: json['content'] ?? '',
      category: json['category'] ?? '',
      rating: json['rating'] ?? 5,
      taggedUserIds: List<String>.from(json['taggedUserIds'] ?? []),
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      likedBy: List<String>.from(json['likedBy'] ?? []),
      commentCount: json['commentCount'] ?? 0,
      privacyLevel: PrivacyLevel.values.firstWhere(
        (e) => e.toString() == 'PrivacyLevel.${json['privacyLevel']}',
        orElse: () => PrivacyLevel.friends,
      ),
    );
  }

  // Firestore 문서에서 생성하는 factory 메서드
  factory ReviewPost.fromMap(Map<String, dynamic> map) {
    return ReviewPost(
      id: map['id'] ?? '',
      authorId: map['authorId'] ?? '',
      authorName: map['authorName'] ?? '',
      authorProfileImage: map['authorProfileImage'] ?? '',
      meetupId: map['meetupId'] ?? '',
      meetupTitle: map['meetupTitle'] ?? '',
      imageUrls: List<String>.from(map['imageUrls'] ?? []),
      content: map['content'] ?? '',
      category: map['category'] ?? '',
      rating: map['rating'] ?? 5,
      taggedUserIds: List<String>.from(map['taggedUserIds'] ?? []),
      createdAt: map['createdAt'] is DateTime 
          ? map['createdAt'] 
          : (map['createdAt']?.toDate() ?? DateTime.now()),
      likedBy: List<String>.from(map['likedBy'] ?? []),
      commentCount: map['commentCount'] ?? 0,
      privacyLevel: PrivacyLevel.values.firstWhere(
        (e) => e.toString() == 'PrivacyLevel.${map['privacyLevel']}',
        orElse: () => PrivacyLevel.friends,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'authorId': authorId,
      'authorName': authorName,
      'authorProfileImage': authorProfileImage,
      'meetupId': meetupId,
      'meetupTitle': meetupTitle,
      'imageUrls': imageUrls,
      'content': content,
      'category': category,
      'rating': rating,
      'taggedUserIds': taggedUserIds,
      'createdAt': createdAt.toIso8601String(),
      'likedBy': likedBy,
      'commentCount': commentCount,
      'privacyLevel': privacyLevel.toString().split('.').last,
    };
  }

  // 좋아요 상태 확인
  bool isLikedByUser(String userId) {
    return likedBy.contains(userId);
  }

  // 좋아요 수 getter
  int get likeCount => likedBy.length;

  // 태그된 사용자 수 getter
  int get taggedUserCount => taggedUserIds.length;

  // 시간 표시용 포맷팅
  String getFormattedTime() {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 7) {
      return '${createdAt.year}.${createdAt.month.toString().padLeft(2, '0')}.${createdAt.day.toString().padLeft(2, '0')}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }

  // ReviewPost 복사 메서드
  ReviewPost copyWith({
    String? id,
    String? authorId,
    String? authorName,
    String? authorProfileImage,
    String? meetupId,
    String? meetupTitle,
    List<String>? imageUrls,
    String? content,
    String? category,
    int? rating,
    List<String>? taggedUserIds,
    DateTime? createdAt,
    List<String>? likedBy,
    int? commentCount,
    PrivacyLevel? privacyLevel,
  }) {
    return ReviewPost(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      authorProfileImage: authorProfileImage ?? this.authorProfileImage,
      meetupId: meetupId ?? this.meetupId,
      meetupTitle: meetupTitle ?? this.meetupTitle,
      imageUrls: imageUrls ?? this.imageUrls,
      content: content ?? this.content,
      category: category ?? this.category,
      rating: rating ?? this.rating,
      taggedUserIds: taggedUserIds ?? this.taggedUserIds,
      createdAt: createdAt ?? this.createdAt,
      likedBy: likedBy ?? this.likedBy,
      commentCount: commentCount ?? this.commentCount,
      privacyLevel: privacyLevel ?? this.privacyLevel,
    );
  }

  @override
  String toString() {
    return 'ReviewPost(id: $id, authorName: $authorName, meetupTitle: $meetupTitle, rating: $rating)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReviewPost && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

enum PrivacyLevel {
  private,   // 나만 보기
  friends,   // 친구만 보기
  school,    // 같은 학교만 보기
  public     // 전체 공개
}

// PrivacyLevel 확장 메서드
extension PrivacyLevelExtension on PrivacyLevel {
  String get displayName {
    switch (this) {
      case PrivacyLevel.private:
        return '나만 보기';
      case PrivacyLevel.friends:
        return '친구만 보기';
      case PrivacyLevel.school:
        return '같은 학교';
      case PrivacyLevel.public:
        return '전체 공개';
    }
  }

  String get description {
    switch (this) {
      case PrivacyLevel.private:
        return '본인만 볼 수 있습니다';
      case PrivacyLevel.friends:
        return '친구로 등록된 사용자만 볼 수 있습니다';
      case PrivacyLevel.school:
        return '같은 학교 사용자만 볼 수 있습니다';
      case PrivacyLevel.public:
        return '모든 사용자가 볼 수 있습니다';
    }
  }

  IconData get icon {
    switch (this) {
      case PrivacyLevel.private:
        return Icons.lock;
      case PrivacyLevel.friends:
        return Icons.people;
      case PrivacyLevel.school:
        return Icons.school;
      case PrivacyLevel.public:
        return Icons.public;
    }
  }
}
