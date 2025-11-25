// lib/services/participation_cache_service.dart
// 참여 상태 캐싱 서비스
// 모임 참여 상태를 메모리에 캐시하여 빠른 응답 제공

import '../utils/logger.dart';

/// 모임 참여 상태 캐싱 서비스
/// 사용자의 모임 참여 상태를 메모리에 캐시하여 반복적인 Firestore 쿼리를 줄입니다.
class ParticipationCacheService {
  static final ParticipationCacheService _instance = ParticipationCacheService._internal();
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
      Logger.log('📋 [CACHE] 캐시 없음: $key');
      return null;
    }
    
    final age = DateTime.now().difference(cachedTime);
    if (age >= _cacheExpiry) {
      Logger.log('⏰ [CACHE] 캐시 만료됨: $key (${age.inMinutes}분 경과)');
      // 만료된 캐시 정리
      _cache.remove(key);
      _cacheTime.remove(key);
      return null;
    }
    
    final result = _cache[key];
    Logger.log('✅ [CACHE] 캐시 히트: $key -> $result');
    return result;
  }

  /// 참여 상태 캐시 저장
  /// 
  /// [meetupId] 모임 ID
  /// [userId] 사용자 ID
  /// [isParticipating] 참여 상태
  void setCachedParticipation(String meetupId, String userId, bool isParticipating) {
    final key = _getCacheKey(meetupId, userId);
    _cache[key] = isParticipating;
    _cacheTime[key] = DateTime.now();
    
    Logger.log('💾 [CACHE] 캐시 저장: $key -> $isParticipating');
  }

  /// 특정 모임의 캐시 무효화
  /// 참여/탈퇴 시 호출하여 캐시를 갱신합니다.
  /// 
  /// [meetupId] 모임 ID
  /// [userId] 사용자 ID
  void invalidateCache(String meetupId, String userId) {
    final key = _getCacheKey(meetupId, userId);
    final wasPresent = _cache.containsKey(key);
    
    _cache.remove(key);
    _cacheTime.remove(key);
    
    if (wasPresent) {
      Logger.log('🗑️ [CACHE] 캐시 무효화: $key');
    }
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
    
    if (keysToRemove.isNotEmpty) {
      Logger.log('🗑️ [CACHE] 사용자 캐시 전체 무효화: $userId (${keysToRemove.length}개)');
    }
  }

  /// 모든 캐시 초기화
  void clearAllCache() {
    final count = _cache.length;
    _cache.clear();
    _cacheTime.clear();
    
    if (count > 0) {
      Logger.log('🗑️ [CACHE] 전체 캐시 초기화: ${count}개 항목 삭제');
    }
  }

  /// 캐시 통계 조회 (디버깅용)
  Map<String, dynamic> getCacheStats() {
    final now = DateTime.now();
    int validCount = 0;
    int expiredCount = 0;
    
    for (final entry in _cacheTime.entries) {
      final age = now.difference(entry.value);
      if (age < _cacheExpiry) {
        validCount++;
      } else {
        expiredCount++;
      }
    }
    
    return {
      'totalEntries': _cache.length,
      'validEntries': validCount,
      'expiredEntries': expiredCount,
      'cacheHitRate': validCount / (_cache.length > 0 ? _cache.length : 1),
    };
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
    
    if (keysToRemove.isNotEmpty) {
      Logger.log('🧹 [CACHE] 만료된 캐시 정리: ${keysToRemove.length}개 항목 삭제');
    }
  }
}
