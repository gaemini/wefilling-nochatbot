// scripts/check_invalid_userids.dart
// 잘못된 userId 형식을 가진 게시글 확인 스크립트

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../lib/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  final firestore = FirebaseFirestore.instance;
  
  print('🔍 잘못된 userId를 가진 게시글 검사 시작...\n');
  
  try {
    // 모든 게시글 가져오기
    final postsSnapshot = await firestore.collection('posts').get();
    print('📊 전체 게시글 수: ${postsSnapshot.docs.length}개\n');
    
    // Firebase Auth UID 형식 검증 패턴 (20~30자 영숫자, 언더스코어 포함 가능)
    final validUidPattern = RegExp(r'^[a-zA-Z0-9_-]{20,30}$');
    
    var invalidCount = 0;
    var anonymousCount = 0;
    var deletedCount = 0;
    final invalidPosts = <Map<String, dynamic>>[];
    
    for (var doc in postsSnapshot.docs) {
      final data = doc.data();
      final userId = data['userId'] as String?;
      final isAnonymous = data['isAnonymous'] as bool? ?? false;
      
      if (userId == null || userId.isEmpty) {
        invalidCount++;
        invalidPosts.add({
          'id': doc.id,
          'title': data['title'] ?? '제목 없음',
          'userId': userId ?? 'null',
          'issue': '빈 userId',
          'isAnonymous': isAnonymous,
        });
      } else if (userId == 'deleted') {
        deletedCount++;
      } else if (!validUidPattern.hasMatch(userId)) {
        invalidCount++;
        invalidPosts.add({
          'id': doc.id,
          'title': data['title'] ?? '제목 없음',
          'userId': userId,
          'userIdLength': userId.length,
          'issue': '잘못된 형식 (${userId.length}자)',
          'isAnonymous': isAnonymous,
        });
      }
      
      if (isAnonymous) {
        anonymousCount++;
      }
    }
    
    print('✅ 검사 완료!\n');
    print('📈 결과 요약:');
    print('- 정상 게시글: ${postsSnapshot.docs.length - invalidCount - deletedCount}개');
    print('- 잘못된 userId: ${invalidCount}개');
    print('- 탈퇴한 사용자: ${deletedCount}개');
    print('- 익명 게시글: ${anonymousCount}개\n');
    
    if (invalidPosts.isNotEmpty) {
      print('❌ 문제가 있는 게시글 목록:');
      for (var post in invalidPosts) {
        print('\n게시글 ID: ${post['id']}');
        print('제목: ${post['title']}');
        print('userId: ${post['userId']}');
        print('문제: ${post['issue']}');
        print('익명 여부: ${post['isAnonymous']}');
        print('-' * 50);
      }
      
      print('\n💡 해결 방안:');
      print('1. 이미 구현된 클라이언트 검증으로 DM 기능 차단됨');
      print('2. 필요시 데이터 마이그레이션 스크립트 실행 가능');
      print('3. 게시글의 다른 기능(좋아요, 댓글)은 정상 작동');
    } else {
      print('✅ 모든 게시글의 userId가 정상입니다!');
    }
    
  } catch (e) {
    print('❌ 오류 발생: $e');
  }
  
  exit(0);
}
