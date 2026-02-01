// lib/services/user_info_cache_service.dart
// 사용자 정보 캐싱 및 실시간 조회 서비스
// 하이브리드 DM 동기화를 위한 사용자 정보 관리

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/logger.dart';

/// 사용자 정보 데이터 클래스 (DM용)
class DMUserInfo {
  final String uid;
  final String nickname;
  final String photoURL;
  final int photoVersion;
  final bool isFromCache;
  
  DMUserInfo({
    required this.uid, 
    required this.nickname, 
    required this.photoURL,
    this.photoVersion = 0,
    this.isFromCache = false,
  });
  
  @override
  String toString() => 'DMUserInfo(uid: $uid, nickname: $nickname)';
}

/// 사용자 정보 캐싱 및 실시간 조회 서비스
/// 
/// 하이브리드 접근 방식:
/// 1. 메모리 캐시 우선 사용 (빠름)
/// 2. 캐시가 오래되면 서버에서 조회 (정확함)
/// 3. 조회 실패 시 오래된 캐시라도 반환 (안정성)
class UserInfoCacheService {
  // 싱글톤 패턴
  static final UserInfoCacheService _instance = UserInfoCacheService._();
  factory UserInfoCacheService() => _instance;
  UserInfoCacheService._();
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // 메모리 캐시
  final Map<String, DMUserInfo> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, Stream<DMUserInfo?>> _watchStreams = {};
  
  /// 사용자 정보 조회 (캐시 우선, 오래되면 서버 조회)
  /// 
  /// [userId]: 조회할 사용자 UID
  /// [cacheValidity]: 캐시 유효 기간 (기본 30분)
  /// [forceRefresh]: true면 캐시 무시하고 서버에서 조회
  Future<DMUserInfo?> getUserInfo(
    String userId, {
    Duration cacheValidity = const Duration(minutes: 30),
    bool forceRefresh = false,
  }) async {
    // 1단계: 캐시 확인
    if (!forceRefresh && _cache.containsKey(userId)) {
      final timestamp = _cacheTimestamps[userId];
      if (timestamp != null && 
          DateTime.now().difference(timestamp) < cacheValidity) {
        Logger.log('✅ 캐시에서 사용자 정보 반환: $userId');
        return _cache[userId];
      }
    }
    
    // 2단계: 서버에서 조회
    try {
      Logger.log('🌐 서버에서 사용자 정보 조회: $userId');
      
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .get(const GetOptions(source: Source.server)); // 강제로 서버에서 조회
      
      if (!doc.exists) {
        Logger.log('⚠️ 사용자 문서 없음: $userId');
        return null;
      }
      
      final data = doc.data()!;
      final userInfo = DMUserInfo(
        uid: userId,
        nickname: data['nickname'] ?? data['displayName'] ?? 'User',
        photoURL: data['photoURL'] ?? '',
        photoVersion: (data['photoVersion'] is int)
            ? (data['photoVersion'] as int)
            : int.tryParse('${data['photoVersion'] ?? 0}') ?? 0,
      );
      
      // 3단계: 캐시 업데이트
      _cache[userId] = userInfo;
      _cacheTimestamps[userId] = DateTime.now();
      
      Logger.log('✅ 사용자 정보 조회 완료: ${userInfo.nickname}');
      return userInfo;
      
    } catch (e) {
      Logger.error('❌ 사용자 정보 조회 실패: $e');
      
      // 4단계: 실패 시 오래된 캐시라도 반환 (Fallback)
      if (_cache.containsKey(userId)) {
        Logger.log('⚠️ 오래된 캐시 사용: $userId');
        return _cache[userId];
      }
      
      return null;
    }
  }

  /// 사용자 정보 실시간 구독 (캐시 자동 갱신)
  ///
  /// - Firestore `users/{uid}` 문서를 구독하여 닉네임/프로필 사진이 바뀌면 즉시 반영
  /// - 스트림에서 받은 최신 값으로 메모리 캐시도 write-through 업데이트
  /// - 동일 uid에 대해 스트림을 재사용하여 불필요한 재구독/리스너 난립을 방지
  Stream<DMUserInfo?> watchUserInfo(String userId) {
    return _watchStreams.putIfAbsent(userId, () {
      return _firestore
          .collection('users')
          .doc(userId)
          .snapshots(includeMetadataChanges: true)
          .map((doc) {
        if (!doc.exists) {
          // 문서가 없으면(탈퇴 등) 캐시도 제거
          invalidateUser(userId);
          return null;
        }

        final data = doc.data()!;
        final fromCache = doc.metadata.isFromCache;
        
        // 🔍 디버그: Firestore에서 실제로 읽은 원본 데이터 로그
        if (kDebugMode) {
          Logger.log('🔥 watchUserInfo Firestore 스냅샷 (userId=$userId):');
          Logger.log('   - fromCache: $fromCache');
          Logger.log('   - nickname: "${data['nickname']}"');
          Logger.log('   - displayName: "${data['displayName']}"');
          Logger.log('   - photoURL: "${data['photoURL']}"');
          Logger.log('   - photoVersion: ${data['photoVersion']} (타입: ${data['photoVersion'].runtimeType})');
        }
        
        final userInfo = DMUserInfo(
          uid: userId,
          nickname: (data['nickname'] ?? data['displayName'] ?? 'User').toString(),
          photoURL: (data['photoURL'] ?? '').toString(),
          photoVersion: (data['photoVersion'] is int)
              ? (data['photoVersion'] as int)
              : int.tryParse('${data['photoVersion'] ?? 0}') ?? 0,
          isFromCache: fromCache,
        );
        
        if (kDebugMode) {
          Logger.log('   → DMUserInfo 생성: photoURL="${userInfo.photoURL}", photoVersion=${userInfo.photoVersion}');
        }

        // write-through 캐시 갱신
        _cache[userId] = userInfo;
        _cacheTimestamps[userId] = DateTime.now();
        return userInfo;
      }).distinct((prev, next) {
        // 객체 identity가 아니라 값 기준으로 중복 제거
        if (prev == null && next == null) return true;
        if (prev == null || next == null) return false;
        return prev.nickname == next.nickname &&
            prev.photoURL == next.photoURL &&
            prev.photoVersion == next.photoVersion &&
            prev.isFromCache == next.isFromCache;
      }).handleError((e) {
        Logger.error('❌ watchUserInfo 오류: userId=$userId, error=$e');
      });
    });
  }
  
  /// 캐시된 사용자 정보 즉시 반환 (비동기 없음)
  /// 
  /// - 캐시에 있으면 즉시 반환, 없으면 null
  /// - StreamBuilder의 initialData로 사용하기 위한 메서드
  DMUserInfo? getCachedUserInfo(String userId) {
    return _cache[userId];
  }
  
  /// 여러 사용자 정보 일괄 조회
  Future<Map<String, DMUserInfo?>> getUserInfoBatch(
    List<String> userIds, {
    Duration cacheValidity = const Duration(minutes: 30),
    bool forceRefresh = false,
  }) async {
    final result = <String, DMUserInfo?>{};
    
    for (final userId in userIds) {
      result[userId] = await getUserInfo(
        userId,
        cacheValidity: cacheValidity,
        forceRefresh: forceRefresh,
      );
    }
    
    return result;
  }
  
  /// 캐시 클리어
  void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
    _watchStreams.clear();
    Logger.log('🗑️ UserInfoCache 클리어 완료');
  }
  
  /// 특정 사용자 캐시 삭제
  void invalidateUser(String userId) {
    _cache.remove(userId);
    _cacheTimestamps.remove(userId);
    _watchStreams.remove(userId);
    Logger.log('🗑️ 사용자 캐시 삭제: $userId');
  }
  
  /// 캐시 통계
  Map<String, dynamic> getCacheStats() {
    return {
      'cachedUsers': _cache.length,
      'oldestCache': _cacheTimestamps.values.isEmpty 
          ? null 
          : _cacheTimestamps.values.reduce((a, b) => a.isBefore(b) ? a : b),
      'newestCache': _cacheTimestamps.values.isEmpty 
          ? null 
          : _cacheTimestamps.values.reduce((a, b) => a.isAfter(b) ? a : b),
    };
  }
}

