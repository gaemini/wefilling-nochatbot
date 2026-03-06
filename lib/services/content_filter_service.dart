// lib/services/content_filter_service.dart
// 차단된 사용자의 콘텐츠 필터링 서비스

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post.dart';
import '../models/meetup.dart';
import 'content_hide_service.dart';
import '../utils/logger.dart';

class ContentFilterService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const Duration _blockQueryTimeout = Duration(seconds: 2);
  
  // 차단된 사용자 목록 캐시 (성능 향상을 위해)
  static Set<String>? _blockedUserIds;
  static Set<String>? _blockedByUserIds;
  static DateTime? _lastCacheUpdate;
  static const Duration _cacheExpiry = Duration(minutes: 5);
  
  /// PostService의 blocks 스트림 결과로 캐시를 즉시 채웁니다.
  /// - 네트워크/쿼리 지연으로 피드가 멈추는 것을 방지
  /// - 차단/차단해제 직후 즉시 필터링(Apple 요구사항)에도 유리
  static void setBlockedUserIds(Set<String> ids) {
    _blockedUserIds = ids;
    _lastCacheUpdate = DateTime.now();
  }

  /// 차단 직후 "즉시 제거"를 위해 in-memory 캐시에 추가합니다.
  /// - Firestore snapshot 반영을 기다리지 않아도 필터가 즉시 적용되게 함
  static void addBlockedUserId(String userId) {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    final current = _blockedUserIds ?? <String>{};
    _blockedUserIds = {...current, uid};
    _lastCacheUpdate = DateTime.now();
  }

  /// 차단 해제 직후 in-memory 캐시에서 제거합니다.
  static void removeBlockedUserId(String userId) {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    if (_blockedUserIds == null) return;
    final next = {..._blockedUserIds!}..remove(uid);
    _blockedUserIds = next;
    _lastCacheUpdate = DateTime.now();
  }

  /// 네트워크 없이 현재 캐시값을 즉시 반환합니다 (optimistic UI 용도).
  static Set<String> getBlockedUserIdsCached() {
    final v = _blockedUserIds;
    if (v == null || v.isEmpty) return const <String>{};
    return Set<String>.unmodifiable(v);
  }

  /// 네트워크 없이 현재 캐시값을 즉시 반환합니다 (optimistic UI 용도).
  static Set<String> getBlockedByUserIdsCached() {
    final v = _blockedByUserIds;
    if (v == null || v.isEmpty) return const <String>{};
    return Set<String>.unmodifiable(v);
  }

  /// "나를 차단한 사용자" 캐시를 즉시 채웁니다.
  static void setBlockedByUserIds(Set<String> ids) {
    _blockedByUserIds = ids;
    _lastCacheUpdate = DateTime.now();
  }

  /// "나를 차단한 사용자"가 즉시 반영되도록 in-memory 캐시에 추가합니다.
  static void addBlockedByUserId(String userId) {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    final current = _blockedByUserIds ?? <String>{};
    _blockedByUserIds = {...current, uid};
    _lastCacheUpdate = DateTime.now();
  }

  /// "나를 차단한 사용자" 캐시에서 즉시 제거합니다.
  static void removeBlockedByUserId(String userId) {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    if (_blockedByUserIds == null) return;
    final next = {..._blockedByUserIds!}..remove(uid);
    _blockedByUserIds = next;
    _lastCacheUpdate = DateTime.now();
  }

  /// 차단된 사용자 목록을 가져오고 캐시합니다
  static Future<Set<String>> _getBlockedUserIds() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return {};

    // 캐시가 유효한 경우 캐시된 데이터 사용
    if (_blockedUserIds != null && 
        _lastCacheUpdate != null &&
        DateTime.now().difference(_lastCacheUpdate!) < _cacheExpiry) {
      return _blockedUserIds!;
    }

    try {
      final querySnapshot = await _firestore
          .collection('blocks')
          .where('blocker', isEqualTo: currentUser.uid)
          .get()
          .timeout(_blockQueryTimeout);

      _blockedUserIds = querySnapshot.docs
          .map((doc) => doc.data()['blocked'] as String)
          .toSet();
      _lastCacheUpdate = DateTime.now();

      return _blockedUserIds!;
    } catch (e) {
      Logger.error('차단 목록 조회 실패: $e');
      return {};
    }
  }

  /// 나를 차단한 사용자 목록을 가져오고 캐시합니다
  static Future<Set<String>> _getBlockedByUserIds() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return {};

    // 캐시가 유효한 경우 캐시된 데이터 사용
    if (_blockedByUserIds != null && 
        _lastCacheUpdate != null &&
        DateTime.now().difference(_lastCacheUpdate!) < _cacheExpiry) {
      return _blockedByUserIds!;
    }

    try {
      final querySnapshot = await _firestore
          .collection('blocks')
          .where('blocked', isEqualTo: currentUser.uid)
          .get()
          .timeout(_blockQueryTimeout);

      _blockedByUserIds = querySnapshot.docs
          .map((doc) => (doc.data()['blocker'] ?? '').toString())
          .where((v) => v.trim().isNotEmpty)
          .toSet();
      // blocked 목록과 동일하게 캐시 갱신 시간도 업데이트
      _lastCacheUpdate = DateTime.now();

      return _blockedByUserIds!;
    } catch (e) {
      Logger.error('차단당한 목록 조회 실패: $e');
      return {};
    }
  }

  /// 캐시를 강제로 새로고침합니다
  static void refreshCache() {
    _blockedUserIds = null;
    _blockedByUserIds = null;
    _lastCacheUpdate = null;
  }

  /// 차단된 사용자 ID 목록을 가져옵니다 (public 메서드)
  static Future<Set<String>> getBlockedUserIds() async {
    return await _getBlockedUserIds();
  }

  /// 나를 차단한 사용자 ID 목록을 가져옵니다 (public 메서드)
  static Future<Set<String>> getBlockedByUserIds() async {
    return await _getBlockedByUserIds();
  }

  /// 특정 사용자가 나를 차단했는지 확인합니다
  static Future<bool> isBlockedByUser(String userId) async {
    final blockedByUserIds = await _getBlockedByUserIds();
    return blockedByUserIds.contains(userId);
  }

  /// 게시물 목록에서 차단된 사용자의 게시물을 필터링합니다
  static Future<List<Post>> filterPosts(List<Post> posts) async {
    final blockedUserIds = await _getBlockedUserIds();
    final blockedByUserIds = await _getBlockedByUserIds();
    
    final hiddenApplied = ContentHideService.filterPostsSync(posts);

    if (blockedUserIds.isEmpty && blockedByUserIds.isEmpty) return hiddenApplied;

    return hiddenApplied.where((post) => 
      !blockedUserIds.contains(post.userId) &&
      !blockedByUserIds.contains(post.userId)
    ).toList();
  }

  /// 모임 목록에서 차단된 사용자의 모임을 필터링합니다
  static Future<List<Meetup>> filterMeetups(List<Meetup> meetups) async {
    final blockedUserIds = await _getBlockedUserIds();
    final blockedByUserIds = await _getBlockedByUserIds();
    
    final hiddenApplied = ContentHideService.filterMeetupsSync(meetups);

    if (blockedUserIds.isEmpty && blockedByUserIds.isEmpty) return hiddenApplied;

    return hiddenApplied.where((meetup) => 
      !blockedUserIds.contains(meetup.userId) &&
      !blockedByUserIds.contains(meetup.userId)
    ).toList();
  }

  /// 특정 사용자가 차단되었는지 확인합니다
  static Future<bool> isUserBlocked(String userId) async {
    final blockedUserIds = await _getBlockedUserIds();
    return blockedUserIds.contains(userId);
  }

  /// 사용자 목록에서 차단된 사용자를 필터링합니다
  static Future<List<Map<String, dynamic>>> filterUsers(
    List<Map<String, dynamic>> users
  ) async {
    final blockedUserIds = await _getBlockedUserIds();
    final blockedByUserIds = await _getBlockedByUserIds();
    
    if (blockedUserIds.isEmpty && blockedByUserIds.isEmpty) return users;

    return users.where((user) => 
      user['uid'] != null && 
      !ContentHideService.isHiddenUser((user['uid'] ?? '').toString()) &&
      !blockedUserIds.contains(user['uid']) &&
      !blockedByUserIds.contains(user['uid'])
    ).toList();
  }

  /// Firestore 쿼리에서 차단된 사용자를 제외하는 조건을 추가합니다
  static Future<Query<Map<String, dynamic>>> addBlockedUserFilter(
    Query<Map<String, dynamic>> query,
    String userIdField
  ) async {
    final blockedUserIds = await _getBlockedUserIds();
    if (blockedUserIds.isEmpty) return query;

    // Firestore의 whereNotIn은 최대 10개 제한이 있으므로, 
    // 차단된 사용자가 많은 경우 클라이언트에서 필터링해야 합니다
    if (blockedUserIds.length <= 10) {
      return query.where(userIdField, whereNotIn: blockedUserIds.toList());
    }
    
    return query; // 10개 초과시 클라이언트에서 필터링
  }

  /// 댓글 목록에서 차단된 사용자의 댓글을 필터링합니다
  static Future<List<Map<String, dynamic>>> filterComments(
    List<Map<String, dynamic>> comments
  ) async {
    final blockedUserIds = await _getBlockedUserIds();
    final blockedByUserIds = await _getBlockedByUserIds();
    
    if (blockedUserIds.isEmpty && blockedByUserIds.isEmpty) return comments;

    return comments.where((comment) => 
      comment['userId'] != null && 
      !blockedUserIds.contains(comment['userId']) &&
      !blockedByUserIds.contains(comment['userId'])
    ).toList();
  }

  /// 검색 결과에서 차단된 사용자의 콘텐츠를 필터링합니다
  static Future<Map<String, List<dynamic>>> filterSearchResults(
    Map<String, List<dynamic>> searchResults
  ) async {
    final filteredResults = <String, List<dynamic>>{};

    // 게시물 필터링
    if (searchResults.containsKey('posts')) {
      final posts = searchResults['posts']?.cast<Post>() ?? [];
      filteredResults['posts'] = await filterPosts(posts);
    }

    // 모임 필터링
    if (searchResults.containsKey('meetups')) {
      final meetups = searchResults['meetups']?.cast<Meetup>() ?? [];
      filteredResults['meetups'] = await filterMeetups(meetups);
    }

    // 사용자 필터링
    if (searchResults.containsKey('users')) {
      final users = searchResults['users']?.cast<Map<String, dynamic>>() ?? [];
      filteredResults['users'] = await filterUsers(users);
    }

    return filteredResults;
  }

  /// 알림에서 차단된 사용자의 알림을 필터링합니다
  static Future<List<Map<String, dynamic>>> filterNotifications(
    List<Map<String, dynamic>> notifications
  ) async {
    final blockedUserIds = await _getBlockedUserIds();
    final blockedByUserIds = await _getBlockedByUserIds();
    
    if (blockedUserIds.isEmpty && blockedByUserIds.isEmpty) return notifications;

    return notifications.where((notification) {
      final fromUserId = notification['fromUserId'];
      return fromUserId == null || 
             (!ContentHideService.isHiddenUser(fromUserId.toString()) &&
              !blockedUserIds.contains(fromUserId) && 
              !blockedByUserIds.contains(fromUserId));
    }).toList();
  }
}
