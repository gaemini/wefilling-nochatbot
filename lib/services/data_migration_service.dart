// lib/services/data_migration_service.dart
// Firebase 데이터 마이그레이션 서비스
// 기존 모임 데이터에 viewCount, commentCount 필드 추가

import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/logger.dart';

class DataMigrationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 모든 모임 데이터에 viewCount, commentCount 필드 추가
  Future<bool> migrateMeetupStatistics() async {
    try {
      Logger.log('🔄 모임 통계 필드 마이그레이션 시작...');
      
      // 모든 모임 문서 가져오기
      final QuerySnapshot meetupsSnapshot = await _firestore
          .collection('meetups')
          .get();
      
      Logger.log('📊 총 ${meetupsSnapshot.docs.length}개의 모임 발견');
      
      if (meetupsSnapshot.docs.isEmpty) {
        Logger.log('⚠️ 마이그레이션할 모임이 없습니다');
        return true;
      }

      // 배치 작업으로 효율적으로 업데이트
      WriteBatch batch = _firestore.batch();
      int updateCount = 0;
      int batchCount = 0;
      
      for (DocumentSnapshot doc in meetupsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;
        
        bool needsUpdate = false;
        Map<String, dynamic> updates = {};
        
        // viewCount 필드가 없으면 추가
        if (!data.containsKey('viewCount')) {
          updates['viewCount'] = 0;
          needsUpdate = true;
        }
        
        // commentCount 필드가 없으면 추가
        if (!data.containsKey('commentCount')) {
          // 실제 댓글 수 계산
          final commentCount = await _calculateCommentCount(doc.id);
          updates['commentCount'] = commentCount;
          needsUpdate = true;
          Logger.log('📝 ${doc.id}: 댓글 ${commentCount}개 발견');
        }
        
        if (needsUpdate) {
          updates['updatedAt'] = FieldValue.serverTimestamp();
          batch.update(doc.reference, updates);
          updateCount++;
          
          Logger.log('✏️ ${doc.id} (${data['title'] ?? 'Unknown'}) 업데이트 예정');
        }
        
        // 배치 크기 제한 (Firestore 배치는 최대 500개)
        batchCount++;
        if (batchCount >= 400) {
          Logger.log('📦 배치 실행 중... (${updateCount}개 업데이트)');
          await batch.commit();
          batch = _firestore.batch();
          batchCount = 0;
        }
      }
      
      // 남은 배치 실행
      if (batchCount > 0) {
        Logger.log('📦 최종 배치 실행 중... (${updateCount}개 업데이트)');
        await batch.commit();
      }
      
      Logger.log('✅ 모임 통계 필드 마이그레이션 완료!');
      Logger.log('📈 총 ${updateCount}개 모임이 업데이트되었습니다');
      
      return true;
      
    } catch (e) {
      Logger.error('❌ 모임 통계 필드 마이그레이션 실패: $e');
      return false;
    }
  }
  
  /// 특정 모임의 실제 댓글 수 계산
  Future<int> _calculateCommentCount(String meetupId) async {
    try {
      final QuerySnapshot commentsSnapshot = await _firestore
          .collection('comments')
          .where('postId', isEqualTo: meetupId)
          .get();
      
      return commentsSnapshot.docs.length;
    } catch (e) {
      Logger.error('❌ 댓글 수 계산 실패 ($meetupId): $e');
      return 0;
    }
  }
  
  /// 마이그레이션 상태 확인
  Future<Map<String, dynamic>> checkMigrationStatus() async {
    try {
      Logger.log('🔍 마이그레이션 상태 확인 중...');
      
      final QuerySnapshot meetupsSnapshot = await _firestore
          .collection('meetups')
          .limit(100) // 샘플링
          .get();
      
      int totalCount = meetupsSnapshot.docs.length;
      int withViewCount = 0;
      int withCommentCount = 0;
      
      for (DocumentSnapshot doc in meetupsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;
        
        if (data.containsKey('viewCount')) {
          withViewCount++;
        }
        
        if (data.containsKey('commentCount')) {
          withCommentCount++;
        }
      }
      
      final status = {
        'totalSampled': totalCount,
        'withViewCount': withViewCount,
        'withCommentCount': withCommentCount,
        'viewCountPercentage': totalCount > 0 ? (withViewCount / totalCount * 100).round() : 0,
        'commentCountPercentage': totalCount > 0 ? (withCommentCount / totalCount * 100).round() : 0,
        'needsMigration': withViewCount < totalCount || withCommentCount < totalCount,
      };
      
      Logger.log('📊 마이그레이션 상태:');
      Logger.log('   - 샘플 모임 수: ${status['totalSampled']}');
      Logger.log('   - viewCount 있음: ${status['withViewCount']} (${status['viewCountPercentage']}%)');
      Logger.log('   - commentCount 있음: ${status['withCommentCount']} (${status['commentCountPercentage']}%)');
      Logger.log('   - 마이그레이션 필요: ${status['needsMigration']}');
      
      return status;
      
    } catch (e) {
      Logger.error('❌ 마이그레이션 상태 확인 실패: $e');
      return {
        'error': e.toString(),
        'needsMigration': true,
      };
    }
  }
  
  /// 특정 모임 하나만 테스트 업데이트
  Future<bool> testUpdateSingleMeetup(String meetupId) async {
    try {
      Logger.log('🧪 테스트 업데이트 시작: $meetupId');
      
      final DocumentSnapshot doc = await _firestore
          .collection('meetups')
          .doc(meetupId)
          .get();
      
      if (!doc.exists) {
        Logger.error('❌ 모임을 찾을 수 없음: $meetupId');
        return false;
      }
      
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) {
        Logger.error('❌ 모임 데이터가 없음: $meetupId');
        return false;
      }
      
      // 댓글 수 계산
      final commentCount = await _calculateCommentCount(meetupId);
      
      // 업데이트
      await doc.reference.update({
        'viewCount': data['viewCount'] ?? 0,
        'commentCount': commentCount,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      Logger.log('✅ 테스트 업데이트 완료: $meetupId');
      Logger.log('   - 제목: ${data['title']}');
      Logger.log('   - 조회수: ${data['viewCount'] ?? 0}');
      Logger.log('   - 댓글수: $commentCount');
      
      return true;
      
    } catch (e) {
      Logger.error('❌ 테스트 업데이트 실패: $e');
      return false;
    }
  }
}







