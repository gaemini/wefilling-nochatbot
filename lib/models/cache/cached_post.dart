// lib/models/cache/cached_post.dart
// 게시글 캐시 모델

import 'package:hive/hive.dart';
import '../post.dart';

part 'cached_post.g.dart';

/// 게시글 캐시 모델
/// Hive에 저장되는 게시글 데이터
@HiveType(typeId: 0)
class CachedPost extends HiveObject {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final Map<String, dynamic> data;
  
  @HiveField(2)
  final DateTime cachedAt;
  
  CachedPost({
    required this.id,
    required this.data,
    required this.cachedAt,
  });
  
  /// Post 객체로 변환
  Post toPost() => Post.fromMap(data, id);
  
  /// Post 객체에서 생성
  factory CachedPost.fromPost(Post post) {
    return CachedPost(
      id: post.id,
      data: post.toMap(),
      cachedAt: DateTime.now(),
    );
  }
}





