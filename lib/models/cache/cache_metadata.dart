// lib/models/cache/cache_metadata.dart
// 캐시 메타데이터 모델

import 'package:hive/hive.dart';

part 'cache_metadata.g.dart';

/// 캐시 메타데이터
/// 캐시된 데이터의 생성 시간, 버전 정보 등을 저장합니다.
@HiveType(typeId: 99)
class CacheMetadata extends HiveObject {
  @HiveField(0)
  final String key;
  
  @HiveField(1)
  final DateTime cachedAt;
  
  @HiveField(2)
  final String version;
  
  @HiveField(3)
  final int? dataSize;
  
  CacheMetadata({
    required this.key,
    required this.cachedAt,
    this.version = '1.0.0',
    this.dataSize,
  });
  
  /// 캐시가 만료되었는지 확인
  bool isExpired(Duration ttl) {
    return DateTime.now().difference(cachedAt) > ttl;
  }
  
  /// 캐시 생성 후 경과 시간
  Duration get age => DateTime.now().difference(cachedAt);
}





