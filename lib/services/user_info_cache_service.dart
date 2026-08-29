// lib/services/user_info_cache_service.dart
// 사용자 정보 캐싱 및 실시간 조회 서비스
// 하이브리드 DM 동기화를 위한 사용자 정보 관리

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import '../utils/account_status_helper.dart';
import '../utils/logger.dart';

/// 사용자 정보 데이터 클래스 (DM용)
class DMUserInfo {
  final String uid;
  final String nickname;
  final String photoURL;
  final int photoVersion;
  final String nationality;
  final bool isFromCache;
  final bool isDeletedAccount;

  DMUserInfo({
    required this.uid,
    required this.nickname,
    required this.photoURL,
    this.photoVersion = 0,
    this.nationality = '',
    this.isFromCache = false,
    this.isDeletedAccount = false,
  });

  @override
  String toString() =>
      'DMUserInfo(uid: $uid, nickname: $nickname, deleted: $isDeletedAccount)';
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
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _boxName = 'user_profiles_v2';
  Box<dynamic>? _box;
  Future<Box<dynamic>?>? _boxOpening;
  bool _persistentCacheDisabled = false;

  // 메모리 캐시
  final Map<String, DMUserInfo> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, Stream<DMUserInfo?>> _watchStreams = {};
  final Map<String, Future<DMUserInfo?>> _refreshFutures = {};

  String _cacheKey(String userId) =>
      '${_auth.currentUser?.uid ?? 'signed-out'}::$userId';

  Future<Box<dynamic>?> _ensureBox() async {
    if (_persistentCacheDisabled) return null;
    if (_box?.isOpen == true) return _box;
    final existing = _boxOpening;
    if (existing != null) return existing;
    final operation = _openBox();
    _boxOpening = operation;
    try {
      return await operation;
    } finally {
      if (identical(_boxOpening, operation)) _boxOpening = null;
    }
  }

  Future<Box<dynamic>?> _openBox() async {
    try {
      _box = await Hive.openBox<dynamic>(_boxName);
      return _box;
    } catch (error) {
      _persistentCacheDisabled = true;
      Logger.error('UserInfoCache: persistent cache disabled: $error');
      return null;
    }
  }

  Future<DMUserInfo?> getPersistedUserInfo(String userId) async {
    final ownerUid = _auth.currentUser?.uid;
    if (ownerUid == null || userId.isEmpty) return null;
    final key = '$ownerUid::$userId';
    final inMemory = _cache[key];
    if (inMemory != null) return inMemory;
    final box = await _ensureBox();
    if (_auth.currentUser?.uid != ownerUid) return null;
    Object? raw;
    try {
      raw = box?.get(key);
    } catch (_) {
      return null;
    }
    if (raw is! Map) return null;
    try {
      final nickname = (raw['nickname'] ?? '').toString().trim();
      if (nickname.isEmpty) return null;
      final info = DMUserInfo(
        uid: userId,
        nickname: nickname,
        photoURL: (raw['photoURL'] ?? '').toString(),
        photoVersion: raw['photoVersion'] is num
            ? (raw['photoVersion'] as num).toInt()
            : 0,
        nationality: (raw['nationality'] ?? '').toString(),
        isFromCache: true,
        isDeletedAccount: raw['isDeletedAccount'] == true,
      );
      _cache[key] = info;
      final savedAt = raw['savedAtMs'];
      _cacheTimestamps[key] = savedAt is num
          ? DateTime.fromMillisecondsSinceEpoch(savedAt.toInt())
          : DateTime.fromMillisecondsSinceEpoch(0);
      return info;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, DMUserInfo?>> hydrateUsers(
    Iterable<String> userIds,
  ) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    final entries = await Future.wait(
      ids.map((id) async => MapEntry(id, await getPersistedUserInfo(id))),
    );
    return Map<String, DMUserInfo?>.fromEntries(entries);
  }

  Future<void> _persistUser(String ownerUid, DMUserInfo info) async {
    final box = await _ensureBox();
    if (box == null) return;
    try {
      await box.put('$ownerUid::${info.uid}', <String, dynamic>{
        'nickname': info.nickname,
        'photoURL': info.photoURL,
        'photoVersion': info.photoVersion,
        'nationality': info.nationality,
        'isDeletedAccount': info.isDeletedAccount,
        'savedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (error) {
      Logger.error('UserInfoCache: persistent write failed: $error');
    }
  }

  void _refreshInBackground(String userId, String key) {
    if (_refreshFutures.containsKey(key)) return;
    final operation = getUserInfo(userId, forceRefresh: true);
    _refreshFutures[key] = operation;
    unawaited(operation.whenComplete(() {
      if (identical(_refreshFutures[key], operation)) {
        _refreshFutures.remove(key);
      }
    }));
  }

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
    final ownerUidAtStart = _auth.currentUser?.uid;
    if (ownerUidAtStart == null) return null;
    final key = '$ownerUidAtStart::$userId';
    if (!forceRefresh && !_cache.containsKey(key)) {
      await getPersistedUserInfo(userId);
    }
    final persisted = _cache[key];
    if (!forceRefresh && persisted?.isFromCache == true) {
      // Stale-while-revalidate: callers can paint the saved profile
      // immediately while a server-only refresh updates the shared cache.
      _refreshInBackground(userId, key);
      return persisted;
    }
    // 1단계: 캐시 확인
    if (!forceRefresh && _cache.containsKey(key)) {
      final timestamp = _cacheTimestamps[key];
      final cached = _cache[key];
      if (timestamp != null &&
          DateTime.now().difference(timestamp) < cacheValidity &&
          // ⚠️ Firestore 캐시 스냅샷(fromCache=true)로 들어온 값은
          // "최신"으로 간주하지 않는다. (앱 초기 진입 시 오래된 닉네임/사진 플리커 방지)
          (cached == null || cached.isFromCache == false)) {
        Logger.log('✅ 캐시에서 사용자 정보 반환: $userId');
        return _cache[key];
      }
    }

    // 2단계: 서버에서 조회
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .get(const GetOptions(source: Source.server)); // 강제로 서버에서 조회

      if (_auth.currentUser?.uid != ownerUidAtStart) return null;

      if (!doc.exists) {
        final deletedUser = DMUserInfo(
          uid: userId,
          nickname: 'DELETED_ACCOUNT',
          photoURL: '',
          isDeletedAccount: true,
        );
        _cache[key] = deletedUser;
        _cacheTimestamps[key] = DateTime.now();
        unawaited(_persistUser(ownerUidAtStart, deletedUser));
        return deletedUser;
      }

      final data = doc.data()!;
      if (isUnavailableUserAccountData(data)) {
        final deletedUser = DMUserInfo(
          uid: userId,
          nickname: 'DELETED_ACCOUNT',
          photoURL: '',
          isDeletedAccount: true,
        );
        _cache[key] = deletedUser;
        _cacheTimestamps[key] = DateTime.now();
        unawaited(_persistUser(ownerUidAtStart, deletedUser));
        return deletedUser;
      }
      final userInfo = DMUserInfo(
        uid: userId,
        nickname: (data['nickname'] ?? '').toString().trim().isNotEmpty
            ? (data['nickname'] ?? '').toString().trim()
            : 'User',
        photoURL: data['photoURL'] ?? '',
        photoVersion: (data['photoVersion'] is int)
            ? (data['photoVersion'] as int)
            : int.tryParse('${data['photoVersion'] ?? 0}') ?? 0,
        nationality:
            (data['nationality'] ?? data['country'] ?? '').toString().trim(),
      );

      // 3단계: 캐시 업데이트
      _cache[key] = userInfo;
      _cacheTimestamps[key] = DateTime.now();
      unawaited(_persistUser(ownerUidAtStart, userInfo));

      return userInfo;
    } catch (e) {
      Logger.error('❌ 사용자 정보 조회 실패: $e');

      // 4단계: 실패 시 오래된 캐시라도 반환 (Fallback)
      if (_cache.containsKey(key)) {
        Logger.log('⚠️ 오래된 캐시 사용: $userId');
        return _cache[key];
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
    final key = _cacheKey(userId);
    final ownerUid = _auth.currentUser?.uid;
    return _watchStreams.putIfAbsent(key, () {
      return _firestore
          .collection('users')
          .doc(userId)
          .snapshots(includeMetadataChanges: true)
          .map((doc) {
        if (!doc.exists) {
          // An empty local Firestore cache is not evidence of account
          // deletion. Keep the persisted label until the server confirms it.
          if (doc.metadata.isFromCache) return _cache[key];
          final deletedUser = DMUserInfo(
            uid: userId,
            nickname: 'DELETED_ACCOUNT',
            photoURL: '',
            isDeletedAccount: true,
          );
          _cache[key] = deletedUser;
          _cacheTimestamps[key] = DateTime.now();
          if (ownerUid != null) {
            unawaited(_persistUser(ownerUid, deletedUser));
          }
          return deletedUser;
        }

        final data = doc.data()!;
        final fromCache = doc.metadata.isFromCache;

        if (isUnavailableUserAccountData(data)) {
          final deletedUser = DMUserInfo(
            uid: userId,
            nickname: 'DELETED_ACCOUNT',
            photoURL: '',
            isFromCache: fromCache,
            isDeletedAccount: true,
          );
          _cache[key] = deletedUser;
          if (!fromCache) {
            _cacheTimestamps[key] = DateTime.now();
            if (ownerUid != null) {
              unawaited(_persistUser(ownerUid, deletedUser));
            }
          }
          return deletedUser;
        }

        final userInfo = DMUserInfo(
          uid: userId,
          nickname: (data['nickname'] ?? '').toString().trim().isNotEmpty
              ? (data['nickname'] ?? '').toString().trim()
              : 'User',
          photoURL: (data['photoURL'] ?? '').toString(),
          photoVersion: (data['photoVersion'] is int)
              ? (data['photoVersion'] as int)
              : int.tryParse('${data['photoVersion'] ?? 0}') ?? 0,
          nationality:
              (data['nationality'] ?? data['country'] ?? '').toString().trim(),
          isFromCache: fromCache,
        );

        // write-through 캐시 갱신
        _cache[key] = userInfo;
        // ⚠️ fromCache 스냅샷은 '신선한 캐시'로 취급하지 않도록 타임스탬프 갱신을 피한다.
        // (초기 진입 시 오래된 값이 cacheValidity 동안 유지되는 문제 방지)
        if (!fromCache) {
          _cacheTimestamps[key] = DateTime.now();
          if (ownerUid != null) unawaited(_persistUser(ownerUid, userInfo));
        }
        return userInfo;
      }).distinct((prev, next) {
        // 객체 identity가 아니라 값 기준으로 중복 제거
        if (prev == null && next == null) return true;
        if (prev == null || next == null) return false;
        return prev.nickname == next.nickname &&
            prev.photoURL == next.photoURL &&
            prev.photoVersion == next.photoVersion &&
            prev.nationality == next.nationality &&
            prev.isDeletedAccount == next.isDeletedAccount &&
            prev.isFromCache == next.isFromCache;
      }).handleError((e) {
        Logger.error('사용자 정보 스트림 오류', e);
      });
    });
  }

  /// 캐시된 사용자 정보 즉시 반환 (비동기 없음)
  ///
  /// - 캐시에 있으면 즉시 반환, 없으면 null
  /// - StreamBuilder의 initialData로 사용하기 위한 메서드
  DMUserInfo? getCachedUserInfo(String userId) {
    return _cache[_cacheKey(userId)];
  }

  /// Write through only the signed-in user's own profile after a successful
  /// server profile transaction. No other profile cache is cleared or fetched.
  Future<void> updateCurrentUserProfile({
    required String uid,
    required String nickname,
    required String photoURL,
    required int photoVersion,
    required String nationality,
  }) async {
    final ownerUid = _auth.currentUser?.uid;
    if (ownerUid == null || ownerUid != uid) return;
    final key = '$ownerUid::$uid';
    final info = DMUserInfo(
      uid: uid,
      nickname: nickname,
      photoURL: photoURL,
      photoVersion: photoVersion,
      nationality: nationality,
    );
    _cache[key] = info;
    _cacheTimestamps[key] = DateTime.now();
    await _persistUser(ownerUid, info);
  }

  /// 피드 카드용 휴대폰 캐시 전용 스트림입니다.
  ///
  /// 카드가 스크롤로 다시 생성될 때 Firestore listener를 열지 않고 메모리와
  /// Hive에 마지막으로 저장된 프로필만 전달합니다. 프로필/상세 화면을 여는
  /// 명시적 사용자 동작에서는 기존 [getUserInfo]/[watchUserInfo]가 최신 값을
  /// 조회하고 같은 캐시에 기록합니다.
  Stream<DMUserInfo?> watchCachedUserInfo(String userId) async* {
    final memory = getCachedUserInfo(userId);
    if (memory != null) yield memory;

    final persisted = await getPersistedUserInfo(userId);
    if (persisted == null || identical(persisted, memory)) return;
    yield persisted;
  }

  /// 여러 사용자 정보 일괄 조회
  Future<Map<String, DMUserInfo?>> getUserInfoBatch(
    List<String> userIds, {
    Duration cacheValidity = const Duration(minutes: 30),
    bool forceRefresh = false,
  }) async {
    final result = <String, DMUserInfo?>{};

    // Keep the existing per-user cache/fallback semantics, but avoid making a
    // read-receipt sheet wait for every profile request serially. A small
    // concurrency window is fast enough for group chats without producing an
    // unbounded burst for larger rooms.
    const concurrency = 8;
    for (var start = 0; start < userIds.length; start += concurrency) {
      final end = (start + concurrency).clamp(0, userIds.length).toInt();
      final batch = userIds.sublist(start, end);
      final entries = await Future.wait(
        batch.map((userId) async => MapEntry(
              userId,
              await getUserInfo(
                userId,
                cacheValidity: cacheValidity,
                forceRefresh: forceRefresh,
              ),
            )),
      );
      result.addEntries(entries);
    }

    return result;
  }

  /// 캐시 클리어
  void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
    _watchStreams.clear();
    _refreshFutures.clear();
    Logger.log('🗑️ UserInfoCache 클리어 완료');
  }

  /// 특정 사용자 캐시 삭제
  void invalidateUser(String userId) {
    final key = _cacheKey(userId);
    _cache.remove(key);
    _cacheTimestamps.remove(key);
    _watchStreams.remove(key);
    _refreshFutures.remove(key);
    unawaited(_deletePersistedUser(key));
    Logger.log('🗑️ 사용자 캐시 삭제: $userId');
  }

  Future<void> _deletePersistedUser(String key) async {
    final box = await _ensureBox();
    try {
      await box?.delete(key);
    } catch (_) {}
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
