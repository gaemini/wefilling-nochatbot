// lib/models/comment.dart
// 댓글 데이터 모델 정의
// 댓글 관련 속성 포함(내용,작성자,작서일 등)
// Firestore데이터 변환 메서드 제공
// 번역 기능 추가

import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/settings_provider.dart';

class Comment {
  final String id;
  final String postId;
  final String userId;
  final String authorNickname;
  final String authorPhotoUrl;
  final String content;
  final DateTime createdAt;

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
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  // 작성 시간을 표시 형식으로 변환
  String getFormattedTime() {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
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
  }) {
    return Comment(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      userId: userId ?? this.userId,
      authorNickname: authorNickname ?? this.authorNickname,
      authorPhotoUrl: authorPhotoUrl ?? this.authorPhotoUrl,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}