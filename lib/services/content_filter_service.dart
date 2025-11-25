// lib/services/content_filter_service.dart
// 차단된 사용자의 콘텐츠 필터링 서비스

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post.dart';
import '../models/meetup.dart';
import '../utils/logger.dart';

class ContentFilterService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // 차단된 사용자 목록 캐시 (성능 향상을 위해)
  static Set<String>? _blockedUserIds;
  static DateTime? _lastCacheUpdate;
  static const Duration _cacheExpiry = Duration(minutes: 5);

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
          .get();

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

  /// 캐시를 강제로 새로고침합니다
  static void refreshCache() {
    _blockedUserIds = null;
    _lastCacheUpdate = null;
  }

  /// 차단된 사용자 ID 목록을 가져옵니다 (public 메서드)
  static Future<Set<String>> getBlockedUserIds() async {
    return await _getBlockedUserIds();
  }

  /// 게시물 목록에서 차단된 사용자의 게시물을 필터링합니다
  static Future<List<Post>> filterPosts(List<Post> posts) async {
    final blockedUserIds = await _getBlockedUserIds();
    if (blockedUserIds.isEmpty) return posts;

    return posts.where((post) => 
      post.userId != null && 
      !blockedUserIds.contains(post.userId)
    ).toList();
  }

  /// 모임 목록에서 차단된 사용자의 모임을 필터링합니다
  static Future<List<Meetup>> filterMeetups(List<Meetup> meetups) async {
    final blockedUserIds = await _getBlockedUserIds();
    if (blockedUserIds.isEmpty) return meetups;

    return meetups.where((meetup) => 
      meetup.userId != null && 
      !blockedUserIds.contains(meetup.userId)
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
    if (blockedUserIds.isEmpty) return users;

    return users.where((user) => 
      user['uid'] != null && 
      !blockedUserIds.contains(user['uid'])
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
    if (blockedUserIds.isEmpty) return comments;

    return comments.where((comment) => 
      comment['userId'] != null && 
      !blockedUserIds.contains(comment['userId'])
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
    if (blockedUserIds.isEmpty) return notifications;

    return notifications.where((notification) {
      final fromUserId = notification['fromUserId'];
      return fromUserId == null || !blockedUserIds.contains(fromUserId);
    }).toList();
  }
}
