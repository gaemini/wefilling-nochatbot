// lib/models/cache/cached_comment.dart
// 댓글 캐시 모델

import 'package:hive/hive.dart';
import '../comment.dart';

part 'cached_comment.g.dart';

/// 댓글 캐시 모델
/// Hive에 저장되는 댓글 데이터
@HiveType(typeId: 1)
class CachedComment extends HiveObject {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final Map<String, dynamic> data;
  
  @HiveField(2)
  final DateTime cachedAt;
  
  CachedComment({
    required this.id,
    required this.data,
    required this.cachedAt,
  });
  
  /// Comment 객체로 변환
  Comment toComment() => Comment.fromMap(data, id);
  
  /// Comment 객체에서 생성
  factory CachedComment.fromComment(Comment comment) {
    return CachedComment(
      id: comment.id,
      data: comment.toMap(),
      cachedAt: DateTime.now(),
    );
  }
}






