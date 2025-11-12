// scripts/cleanup_category_ghost_friends.dart
// 친구 카테고리에서 유령 친구 제거 스크립트
// 실제 friendships에는 없지만 카테고리에 남아있는 친구들을 자동 제거

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../lib/firebase_options.dart';

Future<void> main() async {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('👻 친구 카테고리 유령 친구 클린업');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('');

  // Firebase 초기화
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print('✅ Firebase 초기화 완료');

  final auth = FirebaseAuth.instance;
  final currentUser = auth.currentUser;
  
  if (currentUser == null) {
    print('❌ 로그인된 사용자가 없습니다.');
    print('   앱을 실행한 상태에서 이 스크립트를 실행해주세요.');
    return;
  }
  
  print('👤 현재 사용자: ${currentUser.email}');
  print('   UID: ${currentUser.uid}');
  print('');

  await cleanupGhostFriends(currentUser.uid);
}

Future<void> cleanupGhostFriends(String userId) async {
  final firestore = FirebaseFirestore.instance;
  
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('1️⃣ 실제 친구 목록 확인');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  // 1. 실제 친구 목록 가져오기
  final friendshipsSnapshot = await firestore
      .collection('friendships')
      .where('uids', arrayContains: userId)
      .get();
  
  final realFriendIds = <String>{};
  for (var doc in friendshipsSnapshot.docs) {
    final uids = List<String>.from(doc.data()['uids']);
    final otherUid = uids.firstWhere((id) => id != userId);
    realFriendIds.add(otherUid);
  }
  
  print('📊 실제 친구 수: ${realFriendIds.length}명');
  if (realFriendIds.isNotEmpty) {
    print('   친구 UID 목록:');
    for (var id in realFriendIds) {
      print('     - $id');
    }
  }
  print('');
  
  // 2. 모든 카테고리 가져오기
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('2️⃣ 카테고리 검사');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  final categoriesSnapshot = await firestore
      .collection('friend_categories')
      .where('userId', isEqualTo: userId)
      .get();
  
  print('📂 총 카테고리 수: ${categoriesSnapshot.docs.length}개');
  print('');
  
  // 3. 각 카테고리 검사
  int totalGhosts = 0;
  final batch = firestore.batch();
  
  for (var categoryDoc in categoriesSnapshot.docs) {
    final categoryData = categoryDoc.data();
    final categoryName = categoryData['name'];
    final friendIds = List<String>.from(categoryData['friendIds'] ?? []);
    
    print('📁 카테고리: $categoryName');
    print('   전체 친구: ${friendIds.length}명');
    
    // 유령 친구 찾기 (카테고리에는 있지만 실제 친구가 아님)
    final ghostFriends = friendIds.where((id) => !realFriendIds.contains(id)).toList();
    
    if (ghostFriends.isNotEmpty) {
      print('   👻 유령 친구 발견: ${ghostFriends.length}명');
      print('   제거할 UID:');
      for (var ghostId in ghostFriends) {
        print('     - $ghostId');
      }
      
      // 배치에 제거 작업 추가
      batch.update(categoryDoc.reference, {
        'friendIds': FieldValue.arrayRemove(ghostFriends),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      totalGhosts += ghostFriends.length;
    } else {
      print('   ✅ 유령 친구 없음');
    }
    print('');
  }
  
  // 4. 배치 커밋
  if (totalGhosts > 0) {
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('3️⃣ Firestore 업데이트');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('💾 배치 업데이트 실행 중...');
    await batch.commit();
    print('✅ 배치 커밋 완료');
    print('');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🎉 클린업 완료!');
    print('   총 ${totalGhosts}명의 유령 친구 제거됨');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  } else {
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('✨ 유령 친구 없음');
    print('   모든 카테고리가 정상 상태입니다.');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }
}

