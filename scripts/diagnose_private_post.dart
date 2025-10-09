import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// 비공개 게시글 문제 진단 스크립트
Future<void> main() async {
  print('=== 🔍 비공개 게시글 진단 시작 ===\n');

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

    // "좀 작동해라" 게시글 찾기
    print('🔎 "좀 작동해라" 게시글 검색 중...\n');
    
    final postsSnapshot = await firestore
        .collection('posts')
        .where('title', isEqualTo: '좀 작동해라')
        .get();

    if (postsSnapshot.docs.isEmpty) {
      print('❌ "좀 작동해라" 게시글을 찾을 수 없습니다.');
      print('   모든 비공개 게시글을 조회합니다...\n');
      
      final categoryPosts = await firestore
          .collection('posts')
          .where('visibility', isEqualTo: 'category')
          .get();
      
      print('📊 총 ${categoryPosts.docs.length}개의 비공개 게시글 발견\n');
      
      for (final doc in categoryPosts.docs) {
        final data = doc.data();
        print('📝 게시글: ${data['title']}');
        print('   ID: ${doc.id}');
        print('   작성자: ${data['authorNickname']} (${data['userId']})');
        print('   허용된 사용자 수: ${(data['allowedUserIds'] as List).length}명');
        print('   허용된 사용자 ID: ${data['allowedUserIds']}');
        print('   카테고리 ID: ${data['visibleToCategoryIds']}');
        print('');
      }
    } else {
      for (final doc in postsSnapshot.docs) {
        final data = doc.data();
        print('✅ 게시글 발견!');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('📌 게시글 ID: ${doc.id}');
        print('📌 제목: ${data['title']}');
        print('📌 작성자: ${data['authorNickname']}');
        print('📌 작성자 ID: ${data['userId']}');
        print('📌 공개 범위: ${data['visibility']}');
        print('📌 익명 여부: ${data['isAnonymous'] ?? false}');
        print('');
        
        final allowedUserIds = List<String>.from(data['allowedUserIds'] ?? []);
        print('🔐 허용된 사용자 (${allowedUserIds.length}명):');
        for (int i = 0; i < allowedUserIds.length; i++) {
          print('   ${i + 1}. ${allowedUserIds[i]}');
        }
        print('');
        
        final categoryIds = List<String>.from(data['visibleToCategoryIds'] ?? []);
        print('📂 선택된 카테고리 (${categoryIds.length}개):');
        for (final categoryId in categoryIds) {
          final categoryDoc = await firestore
              .collection('friend_categories')
              .doc(categoryId)
              .get();
          
          if (categoryDoc.exists) {
            final categoryData = categoryDoc.data()!;
            final categoryName = categoryData['name'];
            final friendIds = List<String>.from(categoryData['friendIds'] ?? []);
            
            print('   📁 ${categoryName}:');
            print('      카테고리 ID: ${categoryId}');
            print('      친구 수: ${friendIds.length}명');
            print('      친구 ID 목록: ${friendIds}');
          } else {
            print('   ❌ 카테고리 ${categoryId}를 찾을 수 없음');
          }
        }
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      }
    }

    print('\n=== 완료 ===');
  } catch (e, stackTrace) {
    print('❌ 오류 발생: $e');
    print('스택 트레이스: $stackTrace');
  }
}

