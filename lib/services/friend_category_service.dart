// lib/services/friend_category_service.dart
// 친구 카테고리 관리 서비스

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/friend_category.dart';
import '../utils/logger.dart';

class FriendCategoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 사용자당 생성 가능한 최대 카테고리 수
  static const int maxCategoriesPerUser = 10;

  // 활성 스트림 구독 관리
  final List<StreamSubscription> _activeSubscriptions = [];

  // 모든 스트림 구독 정리
  void dispose() {
    for (final subscription in _activeSubscriptions) {
      subscription.cancel();
    }
    _activeSubscriptions.clear();
  }

  // 현재 사용자의 모든 카테고리 가져오기
  Stream<List<FriendCategory>> getCategoriesStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('friend_categories')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .handleError((error) {
      Logger.error('카테고리 스트림 오류: $error');
      return Stream.value([]);
    }).map((snapshot) {
      try {
        final categories = snapshot.docs
            .map((doc) {
              try {
                return FriendCategory.fromFirestore(doc);
              } catch (e) {
                Logger.error('카테고리 파싱 오류: $e, 문서 ID: ${doc.id}');
                return null;
              }
            })
            .where((category) => category != null)
            .cast<FriendCategory>()
            .toList();

        // 클라이언트에서 정렬 (인덱스 없이도 작동)
        categories.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return categories;
      } catch (e) {
        Logger.error('카테고리 리스트 처리 오류: $e');
        return <FriendCategory>[];
      }
    });
  }

  // 카테고리 생성
  Future<String?> createCategory({
    required String name,
    required String description,
    required String color,
    required String iconName,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      // 안전장치: 서버/다른 화면에서 호출되더라도 최대 개수 제한
      final existing = await _firestore
          .collection('friend_categories')
          .where('userId', isEqualTo: user.uid)
          .limit(maxCategoriesPerUser)
          .get();
      if (existing.docs.length >= maxCategoriesPerUser) {
        if (Logger.isVerboseEnabled) Logger.log('카테고리 생성 차단: 최대 개수($maxCategoriesPerUser개) 도달');
        return null;
      }

      final now = DateTime.now();
      final categoryData = {
        'name': name,
        'description': description,
        'color': color,
        'iconName': iconName,
        'userId': user.uid,
        'friendIds': <String>[],
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      };

      final docRef =
          await _firestore.collection('friend_categories').add(categoryData);

      return docRef.id;
    } catch (e) {
      Logger.error('카테고리 생성 오류: $e');
      return null;
    }
  }

  // 카테고리 수정
  Future<bool> updateCategory({
    required String categoryId,
    String? name,
    String? description,
    String? color,
    String? iconName,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final updateData = <String, dynamic>{
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      };

      if (name != null) updateData['name'] = name;
      if (description != null) updateData['description'] = description;
      if (color != null) updateData['color'] = color;
      if (iconName != null) updateData['iconName'] = iconName;

      await _firestore
          .collection('friend_categories')
          .doc(categoryId)
          .update(updateData);

      return true;
    } catch (e) {
      Logger.error('카테고리 수정 오류: $e');
      return false;
    }
  }

  // 카테고리 삭제
  Future<bool> deleteCategory(String categoryId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final categoryRef =
          _firestore.collection('friend_categories').doc(categoryId);
      await _firestore.runTransaction((transaction) async {
        final category = await transaction.get(categoryRef);
        if (!category.exists) return;
        if ((category.data()?['userId'] ?? '').toString() != user.uid) {
          throw StateError('본인의 그룹만 삭제할 수 있습니다.');
        }
        // 그룹은 표시·분류 단위일 뿐이므로 그룹을 삭제해도
        // 친구를 다른 그룹에 자동 편입하지 않는다.
        transaction.delete(categoryRef);
      });

      return true;
    } catch (e) {
      Logger.error('카테고리 삭제 오류: $e');
      return false;
    }
  }

  // 친구를 카테고리에 추가
  Future<bool> addFriendToCategory({
    required String categoryId,
    required String friendId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final categoryRef =
          _firestore.collection('friend_categories').doc(categoryId);
      await _firestore.runTransaction((transaction) async {
        final category = await transaction.get(categoryRef);
        if (!category.exists ||
            (category.data()?['userId'] ?? '').toString() != user.uid) {
          throw StateError('본인의 그룹만 수정할 수 있습니다.');
        }
        transaction.update(categoryRef, {
          'friendIds': FieldValue.arrayUnion([friendId]),
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      });

      return true;
    } catch (e) {
      Logger.error('친구 카테고리 추가 오류: $e');
      return false;
    }
  }

  // 카테고리의 친구 목록을 일괄 설정
  Future<bool> updateCategoryFriendIds({
    required String categoryId,
    required List<String> friendIds,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final normalizedFriendIds = friendIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty && id != user.uid)
          .toSet()
          .toList(growable: false);
      final categoryRef =
          _firestore.collection('friend_categories').doc(categoryId);
      await _firestore.runTransaction((transaction) async {
        final category = await transaction.get(categoryRef);
        if (!category.exists ||
            (category.data()?['userId'] ?? '').toString() != user.uid) {
          throw StateError('본인의 그룹만 수정할 수 있습니다.');
        }
        // 이 문서만 갱신한다. 다른 그룹의 friendIds는 읽거나 합치지 않는다.
        transaction.update(categoryRef, {
          'friendIds': normalizedFriendIds,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      });
      return true;
    } catch (e) {
      Logger.error('카테고리 친구 목록 업데이트 오류: $e');
      return false;
    }
  }

  // 친구를 카테고리에서 제거
  Future<bool> removeFriendFromCategory({
    required String categoryId,
    required String friendId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final categoryRef =
          _firestore.collection('friend_categories').doc(categoryId);
      await _firestore.runTransaction((transaction) async {
        final category = await transaction.get(categoryRef);
        if (!category.exists ||
            (category.data()?['userId'] ?? '').toString() != user.uid) {
          throw StateError('본인의 그룹만 수정할 수 있습니다.');
        }
        transaction.update(categoryRef, {
          'friendIds': FieldValue.arrayRemove([friendId]),
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      });

      return true;
    } catch (e) {
      Logger.error('친구 카테고리 제거 오류: $e');
      return false;
    }
  }

  // 기본 카테고리 생성 (처음 가입 시)
  Future<bool> createDefaultCategories() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.error('기본 카테고리 생성 실패: 사용자가 로그인되지 않음');
        return false;
      }

      // 이미 카테고리가 있는지 확인
      final existingCategories = await _firestore
          .collection('friend_categories')
          .where('userId', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (existingCategories.docs.isNotEmpty) {
        if (Logger.isVerboseEnabled) Logger.log('기본 카테고리 생성 건너뜀: 이미 카테고리가 존재함');
        return true;
      }

      final batch = _firestore.batch();
      final now = DateTime.now();

      for (final categoryData in DefaultFriendCategories.defaults) {
        final docRef = _firestore.collection('friend_categories').doc();
        batch.set(docRef, {
          ...categoryData,
          'userId': user.uid,
          'friendIds': <String>[],
          'createdAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        });
      }

      await batch.commit();
      if (Logger.isVerboseEnabled) Logger.log('기본 카테고리 ${DefaultFriendCategories.defaults.length}개 생성 완료');
      return true;
    } catch (e) {
      Logger.error('기본 카테고리 생성 오류: $e');
      return false;
    }
  }

  // 특정 친구가 속한 카테고리 찾기
  Future<FriendCategory?> getCategoryByFriendId(String friendId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final snapshot = await _firestore
          .collection('friend_categories')
          .where('userId', isEqualTo: user.uid)
          .where('friendIds', arrayContains: friendId)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return FriendCategory.fromFirestore(snapshot.docs.first);
      }

      return null;
    } catch (e) {
      Logger.error('친구 카테고리 검색 오류: $e');
      return null;
    }
  }

  // 친구를 모든 카테고리에서 제거
  Future<void> removeFriendFromAllCategories(String friendId) async {
    if (Logger.isVerboseEnabled) Logger.log('   ┌─────────────────────────────────');
    if (Logger.isVerboseEnabled) Logger.log('   │ removeFriendFromAllCategories 시작');
    if (Logger.isVerboseEnabled) Logger.log('   │ friendId: $friendId');

    final user = _auth.currentUser;
    if (user == null) {
      if (Logger.isVerboseEnabled) Logger.log('   │ ❌ 로그인된 사용자 없음');
      if (Logger.isVerboseEnabled) Logger.log('   └─────────────────────────────────');
      return;
    }
    if (Logger.isVerboseEnabled) Logger.log('   │ 현재 사용자: ${user.uid}');

    // 해당 친구를 포함하는 카테고리 찾기
    final snapshot = await _firestore
        .collection('friend_categories')
        .where('userId', isEqualTo: user.uid)
        .where('friendIds', arrayContains: friendId)
        .get();

    if (Logger.isVerboseEnabled) Logger.log('   │ 찾은 카테고리 수: ${snapshot.docs.length}');

    if (snapshot.docs.isEmpty) {
      if (Logger.isVerboseEnabled) Logger.log('   │ ℹ️ 해당 친구가 속한 카테고리 없음');
      if (Logger.isVerboseEnabled) Logger.log('   └─────────────────────────────────');
      return;
    }

    // 각 카테고리 정보 출력
    for (var doc in snapshot.docs) {
      final data = doc.data();
      if (Logger.isVerboseEnabled) Logger.log('   │ 카테고리: ${data['name']}');
      if (Logger.isVerboseEnabled) Logger.log('   │   - ID: ${doc.id}');
      if (Logger.isVerboseEnabled) Logger.log('   │   - 현재 친구 수: ${(data['friendIds'] as List).length}');
    }

    // 배치로 한 번에 업데이트
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'friendIds': FieldValue.arrayRemove([friendId]),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    }

    if (Logger.isVerboseEnabled) Logger.log('   │ Firestore 배치 업데이트 실행 중...');
    await batch.commit();
    if (Logger.isVerboseEnabled) Logger.log('   │ ✅ Firestore 배치 커밋 완료');
    if (Logger.isVerboseEnabled) Logger.log('   │ ${snapshot.docs.length}개 카테고리에서 제거됨');
    if (Logger.isVerboseEnabled) Logger.log('   └─────────────────────────────────');
  }
}
