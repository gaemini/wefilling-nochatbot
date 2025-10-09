// scripts/migrate_allowed_users.dart
// 기존 게시글에 allowedUserIds 필드 추가 및 카테고리별 공개 게시글의 allowedUserIds 계산

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  // Firebase 초기화
  await Firebase.initializeApp();
  
  final firestore = FirebaseFirestore.instance;
  
  print('🚀 allowedUserIds 마이그레이션 시작...');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  try {
    // 1. 모든 게시글 가져오기
    final postsSnapshot = await firestore.collection('posts').get();
    print('📊 총 ${postsSnapshot.docs.length}개의 게시글 발견');
    
    int updatedCount = 0;
    int skippedCount = 0;
    int errorCount = 0;
    
    for (final postDoc in postsSnapshot.docs) {
      try {
        final data = postDoc.data();
        final postId = postDoc.id;
        final visibility = data['visibility'] ?? 'public';
        final visibleToCategoryIds = List<String>.from(data['visibleToCategoryIds'] ?? []);
        final userId = data['userId'] ?? '';
        
        // allowedUserIds 필드가 이미 있으면 스킵
        if (data.containsKey('allowedUserIds')) {
          print('⏭️  게시글 ${postId}: 이미 allowedUserIds 존재, 스킵');
          skippedCount++;
          continue;
        }
        
        List<String> allowedUserIds = [];
        
        // 카테고리별 공개인 경우 allowedUserIds 계산
        if (visibility == 'category' && visibleToCategoryIds.isNotEmpty) {
          print('🔍 게시글 ${postId}: 카테고리별 공개 게시글, allowedUserIds 계산 중...');
          
          final Set<String> uniqueFriendIds = {};
          
          for (final categoryId in visibleToCategoryIds) {
            final categoryDoc = await firestore
                .collection('friend_categories')
                .doc(categoryId)
                .get();
            
            if (categoryDoc.exists) {
              final categoryData = categoryDoc.data();
              final friendIds = List<String>.from(categoryData?['friendIds'] ?? []);
              uniqueFriendIds.addAll(friendIds);
              print('   📁 카테고리 ${categoryId}: ${friendIds.length}명의 친구');
            } else {
              print('   ⚠️  카테고리 ${categoryId}: 존재하지 않음');
            }
          }
          
          // 작성자 본인도 포함
          uniqueFriendIds.add(userId);
          allowedUserIds = uniqueFriendIds.toList();
          
          print('   ✅ 총 ${allowedUserIds.length}명에게 공개');
        } else {
          // 전체 공개인 경우 빈 배열
          print('🌐 게시글 ${postId}: 전체 공개 게시글');
          allowedUserIds = [];
        }
        
        // allowedUserIds 필드 추가
        await postDoc.reference.update({
          'allowedUserIds': allowedUserIds,
        });
        
        updatedCount++;
        print('✅ 게시글 ${postId} 업데이트 완료 (${updatedCount}/${postsSnapshot.docs.length})');
        
      } catch (e) {
        print('❌ 게시글 ${postDoc.id} 처리 중 오류: $e');
        errorCount++;
      }
    }
    
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🎉 마이그레이션 완료!');
    print('   ✅ 업데이트: $updatedCount개');
    print('   ⏭️  스킵: $skippedCount개');
    print('   ❌ 오류: $errorCount개');
    
  } catch (e) {
    print('❌ 마이그레이션 실패: $e');
  }
}


