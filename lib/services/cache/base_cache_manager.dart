// lib/services/cache/base_cache_manager.dart
// 기본 캐시 매니저 (모든 캐시 매니저의 부모 클래스)

import 'package:hive/hive.dart';
import 'cache_policy.dart';
import '../../utils/logger.dart';

/// 기본 캐시 매니저
/// 3단계 캐싱 레이어 (Memory -> Disk -> Network) 구현
abstract class BaseCacheManager<T> {
  final Map<String, T> _memoryCache = {};
  final Map<String, DateTime> _cacheTime = {};
  
  /// Hive 박스 (디스크 캐시)
  Box<T>? get box;
  
  /// 캐시 정책
  CachePolicy get policy;
  
  /// 캐시 읽기 (Memory -> Disk)
  Future<T?> get(String key) async {
    try {
      // 1. Memory 캐시 확인
      if (_memoryCache.containsKey(key)) {
        if (!_isExpired(key)) {
          return _memoryCache[key];
        }
        // 만료된 경우 제거
        _memoryCache.remove(key);
        _cacheTime.remove(key);
      }
      
      // 2. Disk 캐시 확인
      final diskBox = box;
      if (diskBox != null && diskBox.isOpen) {
        final cached = diskBox.get(key);
        if (cached != null && !_isDiskExpired(cached)) {
          // 메모리에 캐시
          _memoryCache[key] = cached;
          _cacheTime[key] = DateTime.now();
          return cached;
        }
      }
    } catch (e) {
      Logger.error('캐시 읽기 오류 (폴백): $e');
    }
    
    return null;
  }
  
  /// 캐시 저장 (Memory + Disk)
  Future<void> put(String key, T value) async {
    try {
      // 1. Memory에 저장
      _memoryCache[key] = value;
      _cacheTime[key] = DateTime.now();
      
      // 2. Disk에 저장
      final diskBox = box;
      if (diskBox != null && diskBox.isOpen) {
        await diskBox.put(key, value);
      }
      
      // 3. 메모리 크기 제한 적용
      _enforceMemoryLimit();
    } catch (e) {
      Logger.error('캐시 저장 오류 (무시): $e');
    }
  }
  
  /// 캐시 무효화
  void invalidate({String? key}) {
    try {
      if (key != null) {
        // 특정 키만 무효화
        _memoryCache.remove(key);
        _cacheTime.remove(key);
        box?.delete(key);
      } else {
        // 전체 캐시 무효화
        _memoryCache.clear();
        _cacheTime.clear();
        box?.clear();
      }
    } catch (e) {
      Logger.error('캐시 무효화 오류 (무시): $e');
    }
  }
  
  /// 메모리 캐시 만료 확인
  bool _isExpired(String key) {
    final time = _cacheTime[key];
    if (time == null) return true;
    return DateTime.now().difference(time) > policy.ttl;
  }
  
  /// 디스크 캐시 만료 확인 (서브클래스에서 구현)
  bool _isDiskExpired(T value) {
    // 기본 구현: 만료되지 않음
    // 서브클래스에서 cachedAt 필드를 확인하여 구현
    return false;
  }
  
  /// 메모리 크기 제한 적용 (LRU 정책)
  void _enforceMemoryLimit() {
    if (_memoryCache.length > policy.maxMemoryItems) {
      // 가장 오래된 항목 제거
      final oldestKey = _cacheTime.entries
        .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
        .key;
      _memoryCache.remove(oldestKey);
      _cacheTime.remove(oldestKey);
    }
  }
  
  /// 캐시 통계
  Map<String, dynamic> getStats() {
    return {
      'memorySize': _memoryCache.length,
      'diskSize': box?.length ?? 0,
      'maxMemoryItems': policy.maxMemoryItems,
      'maxDiskItems': policy.maxDiskItems,
      'ttl': policy.ttl.toString(),
    };
  }
}

