// lib/models/comment.dart
// 댓글 데이터 모델 정의
// 댓글 관련 속성 포함(내용,작성자,작서일 등)
// Firestore데이터 변환 메서드 제공
// 번역 기능 추가

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/settings_provider.dart';
import '../l10n/app_localizations.dart';

class Comment {
  final String id;
  final String postId;
  final String userId;
  final String authorNickname;
  final String authorPhotoUrl;
  final String content;
  final DateTime createdAt;
  
  // 대댓글 관련 필드
  final String? parentCommentId; // 대댓글인 경우 부모 댓글 ID
  final int depth; // 댓글 깊이 (0: 원댓글, 1: 대댓글)
  final String? replyToUserId; // 답글 대상 사용자 ID
  final String? replyToUserNickname; // 답글 대상 사용자 닉네임
  
  // 좋아요 관련 필드
  final int likeCount; // 좋아요 수
  final List<String> likedBy; // 좋아요 누른 사용자 ID 목록

  // 캐시된 번역 결과
  String? _translatedContent;

  Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.authorNickname,
    required this.authorPhotoUrl,
    required this.content,
    required this.createdAt,
    this.parentCommentId,
    this.depth = 0,
    this.replyToUserId,
    this.replyToUserNickname,
    this.likeCount = 0,
    this.likedBy = const [],
  });

  // Firestore 데이터로부터 Comment 객체 생성
  factory Comment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Comment(
      id: doc.id,
      postId: data['postId'] ?? '',
      userId: data['userId'] ?? '',
      authorNickname: data['authorNickname'] ?? '익명',
      authorPhotoUrl: data['authorPhotoUrl'] ?? '',
      content: data['content'] ?? '',
      createdAt:
          data['createdAt'] != null
              ? (data['createdAt'] as Timestamp).toDate()
              : DateTime.now(),
      parentCommentId: data['parentCommentId'],
      depth: data['depth'] ?? 0,
      replyToUserId: data['replyToUserId'],
      replyToUserNickname: data['replyToUserNickname'],
      likeCount: data['likeCount'] ?? 0,
      likedBy: List<String>.from(data['likedBy'] ?? []),
    );
  }

  // 작성 시간을 표시 형식으로 변환
  String getFormattedTime(BuildContext context) {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    final locale = Localizations.localeOf(context).languageCode;

    if (difference.inDays > 0) {
      // 지역화 함수 호출 (숫자 전달)
      return AppLocalizations.of(context)!.daysAgo(difference.inDays);
    } else if (difference.inHours > 0) {
      return AppLocalizations.of(context)!.hoursAgo(difference.inHours);
    } else if (difference.inMinutes > 0) {
      return AppLocalizations.of(context)!.minutesAgo(difference.inMinutes);
    } else {
      return AppLocalizations.of(context)!.justNow;
    }
  }

  // Firestore에 저장할 데이터 맵 생성
  Map<String, dynamic> toMap() {
    return {
      'postId': postId,
      'userId': userId,
      'authorNickname': authorNickname,
      'authorPhotoUrl': authorPhotoUrl,
      'content': content,
      'createdAt': FieldValue.serverTimestamp(),
      'parentCommentId': parentCommentId,
      'depth': depth,
      'replyToUserId': replyToUserId,
      'replyToUserNickname': replyToUserNickname,
      'likeCount': likeCount,
      'likedBy': likedBy,
    };
  }

  // 본문 번역 메서드
  Future<String> getTranslatedContent(SettingsProvider settings) async {
    if (!settings.autoTranslate) return content;
    if (_translatedContent != null) return _translatedContent!;

    _translatedContent = await settings.translateText(content);
    return _translatedContent!;
  }

  // Comment 객체 복제 메서드
  Comment copyWith({
    String? id,
    String? postId,
    String? userId,
    String? authorNickname,
    String? authorPhotoUrl,
    String? content,
    DateTime? createdAt,
    String? parentCommentId,
    int? depth,
    String? replyToUserId,
    String? replyToUserNickname,
    int? likeCount,
    List<String>? likedBy,
  }) {
    return Comment(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      userId: userId ?? this.userId,
      authorNickname: authorNickname ?? this.authorNickname,
      authorPhotoUrl: authorPhotoUrl ?? this.authorPhotoUrl,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      parentCommentId: parentCommentId ?? this.parentCommentId,
      depth: depth ?? this.depth,
      replyToUserId: replyToUserId ?? this.replyToUserId,
      replyToUserNickname: replyToUserNickname ?? this.replyToUserNickname,
      likeCount: likeCount ?? this.likeCount,
      likedBy: likedBy ?? this.likedBy,
    );
  }

  // 유틸리티 메서드들
  bool get isReply => parentCommentId != null;
  bool get isTopLevel => parentCommentId == null;
  
  // 사용자가 이 댓글에 좋아요를 눌렀는지 확인
  bool isLikedBy(String userId) => likedBy.contains(userId);
}
