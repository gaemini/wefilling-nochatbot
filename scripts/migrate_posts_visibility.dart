// scripts/migrate_posts_visibility.dart
// 기존 게시글에 visibility와 isAnonymous 필드 추가
// 모든 기존 게시글을 전체 공개, 아이디 공개로 설정

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  print('📋 게시글 마이그레이션 시작...');
  
  try {
    // Firebase 초기화
    await Firebase.initializeApp();
    print('✅ Firebase 초기화 완료');

    final firestore = FirebaseFirestore.instance;
    
    // 모든 게시글 가져오기
    final postsSnapshot = await firestore.collection('posts').get();
    print('📊 총 ${postsSnapshot.docs.length}개의 게시글 발견');

    int successCount = 0;
    int skipCount = 0;
    int errorCount = 0;

    for (final doc in postsSnapshot.docs) {
      try {
        final data = doc.data();
        
        // 이미 visibility 필드가 있는 경우 스킵
        if (data.containsKey('visibility')) {
          print('⏭️  ${doc.id}: 이미 마이그레이션됨');
          skipCount++;
          continue;
        }

        // visibility와 isAnonymous 필드 추가
        await doc.reference.update({
          'visibility': 'public',
          'isAnonymous': false,
          'visibleToCategoryIds': [],
        });

        print('✅ ${doc.id}: 마이그레이션 완료');
        successCount++;
      } catch (e) {
        print('❌ ${doc.id}: 마이그레이션 실패 - $e');
        errorCount++;
      }
    }

    print('\n📊 마이그레이션 결과:');
    print('  ✅ 성공: $successCount개');
    print('  ⏭️  스킵: $skipCount개');
    print('  ❌ 실패: $errorCount개');
    print('  📋 총합: ${postsSnapshot.docs.length}개');

  } catch (e) {
    print('❌ 마이그레이션 중 오류 발생: $e');
  }
}
