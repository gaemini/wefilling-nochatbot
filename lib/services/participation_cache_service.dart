// lib/services/participation_cache_service.dart
// 참여 상태 캐싱 서비스
// 모임 참여 상태를 메모리에 캐시하여 빠른 응답 제공

/// 모임 참여 상태 캐싱 서비스
/// 사용자의 모임 참여 상태를 메모리에 캐시하여 반복적인 Firestore 쿼리를 줄입니다.
class ParticipationCacheService {
  static final ParticipationCacheService _instance =
      ParticipationCacheService._internal();
  factory ParticipationCacheService() => _instance;
  ParticipationCacheService._internal();

  /// 참여 상태 캐시 (meetupId_userId -> isParticipating)
  final Map<String, bool> _cache = {};

  /// 캐시 생성 시간 (meetupId_userId -> DateTime)
  final Map<String, DateTime> _cacheTime = {};

  /// 캐시 만료 시간 (5분)
  static const Duration _cacheExpiry = Duration(minutes: 5);

  /// 캐시 키 생성
  String _getCacheKey(String meetupId, String userId) {
    return '${meetupId}_$userId';
  }

  /// 캐시된 참여 상태 조회
  ///
  /// [meetupId] 모임 ID
  /// [userId] 사용자 ID
  ///
  /// Returns: 캐시된 참여 상태 (null이면 캐시 없음 또는 만료됨)
  bool? getCachedParticipation(String meetupId, String userId) {
    final key = _getCacheKey(meetupId, userId);
    final cachedTime = _cacheTime[key];

    // 캐시가 없거나 만료된 경우
    if (cachedTime == null) {
      return null;
    }

    final age = DateTime.now().difference(cachedTime);
    if (age >= _cacheExpiry) {
      // 만료된 캐시 정리
      _cache.remove(key);
      _cacheTime.remove(key);
      return null;
    }

    final result = _cache[key];
    return result;
  }

  /// 참여 상태 캐시 저장
  ///
  /// [meetupId] 모임 ID
  /// [userId] 사용자 ID
  /// [isParticipating] 참여 상태
  void setCachedParticipation(
      String meetupId, String userId, bool isParticipating) {
    final key = _getCacheKey(meetupId, userId);
    _cache[key] = isParticipating;
    _cacheTime[key] = DateTime.now();
  }

  /// 특정 모임의 캐시 무효화
  /// 참여/탈퇴 시 호출하여 캐시를 갱신합니다.
  ///
  /// [meetupId] 모임 ID
  /// [userId] 사용자 ID
  void invalidateCache(String meetupId, String userId) {
    final key = _getCacheKey(meetupId, userId);
    _cache.remove(key);
    _cacheTime.remove(key);
  }

  /// 특정 사용자의 모든 캐시 무효화
  /// 사용자 로그아웃 시 호출합니다.
  ///
  /// [userId] 사용자 ID
  void invalidateUserCache(String userId) {
    final keysToRemove = <String>[];

    for (final key in _cache.keys) {
      if (key.endsWith('_$userId')) {
        keysToRemove.add(key);
      }
    }

    for (final key in keysToRemove) {
      _cache.remove(key);
      _cacheTime.remove(key);
    }
  }

  /// 모든 캐시 초기화
  void clearAllCache() {
    _cache.clear();
    _cacheTime.clear();
  }

  /// 만료된 캐시 정리 (주기적으로 호출)
  void cleanupExpiredCache() {
    final now = DateTime.now();
    final keysToRemove = <String>[];

    for (final entry in _cacheTime.entries) {
      final age = now.difference(entry.value);
      if (age >= _cacheExpiry) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _cache.remove(key);
      _cacheTime.remove(key);
    }
  }
}
