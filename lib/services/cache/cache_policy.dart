// lib/services/cache/cache_policy.dart
// 캐시 정책 정의 (TTL, 메모리/디스크 크기 제한)

/// 캐시 정책
/// TTL(Time To Live), 메모리 및 디스크 캐시 크기 제한을 정의합니다.
class CachePolicy {
  final Duration ttl;
  final int maxMemoryItems;
  final int maxDiskItems;
  
  const CachePolicy({
    required this.ttl,
    required this.maxMemoryItems,
    required this.maxDiskItems,
  });
  
  /// 게시글 캐시 정책
  /// TTL: 30분, 메모리: 50개, 디스크: 200개
  static const post = CachePolicy(
    ttl: Duration(minutes: 30),
    maxMemoryItems: 50,
    maxDiskItems: 200,
  );
  
  /// 댓글 캐시 정책
  /// TTL: 10분 (자주 변경됨), 메모리: 100개, 디스크: 500개
  static const comment = CachePolicy(
    ttl: Duration(minutes: 10),
    maxMemoryItems: 100,
    maxDiskItems: 500,
  );
  
  /// 모임 캐시 정책
  /// TTL: 15분, 메모리: 30개, 디스크: 100개
  static const meetup = CachePolicy(
    ttl: Duration(minutes: 15),
    maxMemoryItems: 30,
    maxDiskItems: 100,
  );
  
  /// DM 캐시 정책
  /// TTL: 1시간, 메모리: 10개 대화방, 디스크: 50개 대화방
  static const dm = CachePolicy(
    ttl: Duration(hours: 1),
    maxMemoryItems: 10,
    maxDiskItems: 50,
  );
  
  /// 프로필 캐시 정책
  /// TTL: 1시간 (자주 변경 안됨), 메모리: 20명, 디스크: 100명
  static const profile = CachePolicy(
    ttl: Duration(hours: 1),
    maxMemoryItems: 20,
    maxDiskItems: 100,
  );
}


