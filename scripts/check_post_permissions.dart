import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// 비공개 게시글의 권한 설정을 확인하고 수정하는 스크립트
Future<void> main() async {
  print('=== 비공개 게시글 권한 확인 시작 ===\n');

  try {
    // Firebase 초기화
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyAXFJfuBlXBTH6YvPPTBY28Hn8y_h5RvPA',
        appId: '1:598084693986:ios:00cbd5bbfda17cca75afa5',
        messagingSenderId: '598084693986',
        projectId: 'flutterproject3-af322',
        storageBucket: 'flutterproject3-af322.firebasestorage.app',
      ),
    );
    print('✅ Firebase 초기화 성공\n');

    final firestore = FirebaseFirestore.instance;

    // 모든 게시글 조회
    print('📋 모든 게시글 조회 중...\n');
    final postsSnapshot = await firestore
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .get();

    print('총 ${postsSnapshot.docs.length}개의 게시글 발견\n');

    int publicCount = 0;
    int categoryCount = 0;
    int fixedCount = 0;

    for (final doc in postsSnapshot.docs) {
      final data = doc.data();
      final postId = doc.id;
      final title = data['title'] ?? '제목 없음';
      final authorNickname = data['authorNickname'] ?? '알 수 없음';
      final visibility = data['visibility'] ?? 'public';
      final allowedUserIds = List<String>.from(data['allowedUserIds'] ?? []);
      final visibleToCategoryIds = List<String>.from(data['visibleToCategoryIds'] ?? []);

      if (visibility == 'public') {
        publicCount++;
      } else if (visibility == 'category') {
        categoryCount++;
        
        print('📝 비공개 게시글 발견:');
        print('   ID: $postId');
        print('   제목: $title');
        print('   작성자: $authorNickname');
        print('   공개 카테고리: $visibleToCategoryIds');
        print('   허용된 사용자 수: ${allowedUserIds.length}명');
        print('   허용된 사용자 ID: $allowedUserIds');
        
        // 카테고리 정보 확인
        if (visibleToCategoryIds.isNotEmpty) {
          print('\n   🔍 카테고리 상세 정보:');
          final Set<String> expectedFriendIds = {};
          
          for (final categoryId in visibleToCategoryIds) {
            try {
              final categoryDoc = await firestore
                  .collection('friend_categories')
                  .doc(categoryId)
                  .get();
              
              if (categoryDoc.exists) {
                final categoryData = categoryDoc.data();
                final categoryName = categoryData?['name'] ?? '알 수 없음';
                final friendIds = List<String>.from(categoryData?['friendIds'] ?? []);
                expectedFriendIds.addAll(friendIds);
                
                print('      - 카테고리: $categoryName (ID: $categoryId)');
                print('        친구 수: ${friendIds.length}명');
                print('        친구 ID: $friendIds');
              } else {
                print('      - ⚠️  카테고리 $categoryId를 찾을 수 없음');
              }
            } catch (e) {
              print('      - ❌ 카테고리 $categoryId 조회 오류: $e');
            }
          }
          
          // 작성자 추가
          expectedFriendIds.add(data['userId']);
          
          print('\n   예상 허용 사용자 수: ${expectedFriendIds.length}명');
          print('   예상 허용 사용자 ID: ${expectedFriendIds.toList()}');
          
          // allowedUserIds가 올바르지 않은 경우 수정
          if (allowedUserIds.toSet().difference(expectedFriendIds).isNotEmpty ||
              expectedFriendIds.difference(allowedUserIds.toSet()).isNotEmpty) {
            print('\n   ⚠️  allowedUserIds가 올바르지 않습니다. 수정이 필요합니다.');
            print('   수정하시겠습니까? (y/n)');
            
            final input = stdin.readLineSync();
            if (input?.toLowerCase() == 'y') {
              try {
                await firestore.collection('posts').doc(postId).update({
                  'allowedUserIds': expectedFriendIds.toList(),
                });
                print('   ✅ allowedUserIds 수정 완료');
                fixedCount++;
              } catch (e) {
                print('   ❌ 수정 실패: $e');
              }
            }
          } else {
            print('   ✅ allowedUserIds가 올바르게 설정되어 있습니다.');
          }
        }
        print('');
      }
    }

    print('\n=== 요약 ===');
    print('전체 공개 게시글: $publicCount개');
    print('카테고리별 비공개 게시글: $categoryCount개');
    print('수정된 게시글: $fixedCount개');
    print('\n=== 완료 ===');

    exit(0);
  } catch (e, stackTrace) {
    print('❌ 오류 발생: $e');
    print('스택 트레이스: $stackTrace');
    exit(1);
  }
}


