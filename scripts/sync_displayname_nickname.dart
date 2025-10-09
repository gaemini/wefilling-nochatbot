// scripts/sync_displayname_nickname.dart
// Firestore users 컬렉션의 displayName을 nickname과 동기화하는 스크립트

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  print('🚀 displayName과 nickname 동기화 스크립트 시작');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  try {
    // Firebase 초기화
    await Firebase.initializeApp();
    print('✅ Firebase 초기화 완료\n');

    final firestore = FirebaseFirestore.instance;
    
    // 모든 사용자 문서 가져오기
    print('📋 사용자 데이터 조회 중...');
    final usersSnapshot = await firestore.collection('users').get();
    print('✅ 총 ${usersSnapshot.docs.length}명의 사용자 발견\n');

    int updatedCount = 0;
    int skippedCount = 0;
    int errorCount = 0;

    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔄 동기화 작업 시작');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    // 배치 처리를 위한 변수
    WriteBatch batch = firestore.batch();
    int batchCount = 0;
    const maxBatchSize = 500;

    for (final doc in usersSnapshot.docs) {
      try {
        final data = doc.data();
        final userId = doc.id;
        final nickname = data['nickname'];
        final displayName = data['displayName'];

        print('👤 사용자 ID: $userId');
        print('   현재 nickname: ${nickname ?? "(없음)"}');
        print('   현재 displayName: ${displayName ?? "(없음)"}');

        // nickname이 없으면 건너뛰기
        if (nickname == null || nickname.isEmpty) {
          print('   ⚠️  건너뜀: nickname이 없음\n');
          skippedCount++;
          continue;
        }

        // displayName이 이미 nickname과 같으면 건너뛰기
        if (displayName == nickname) {
          print('   ✅ 건너뜀: 이미 동기화됨\n');
          skippedCount++;
          continue;
        }

        // displayName을 nickname으로 업데이트
        batch.update(doc.reference, {
          'displayName': nickname,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        batchCount++;
        updatedCount++;
        print('   🔄 업데이트 예정: displayName = "$nickname"\n');

        // 배치가 가득 차면 커밋
        if (batchCount >= maxBatchSize) {
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          print('💾 배치 커밋 중... ($batchCount개 항목)');
          await batch.commit();
          print('✅ 배치 커밋 완료\n');
          
          // 새 배치 시작
          batch = firestore.batch();
          batchCount = 0;
        }
      } catch (e) {
        print('   ❌ 오류: $e\n');
        errorCount++;
      }
    }

    // 남은 배치 커밋
    if (batchCount > 0) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('💾 최종 배치 커밋 중... ($batchCount개 항목)');
      await batch.commit();
      print('✅ 최종 배치 커밋 완료\n');
    }

    // 최종 결과 출력
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🎉 동기화 작업 완료!');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📊 처리 결과:');
    print('   ✅ 업데이트됨: $updatedCount명');
    print('   ⏭️  건너뜀: $skippedCount명');
    print('   ❌ 오류: $errorCount명');
    print('   📋 총 사용자: ${usersSnapshot.docs.length}명');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  } catch (e) {
    print('❌ 스크립트 실행 오류: $e');
    exit(1);
  }

  exit(0);
}

