// functions/src/migration_add_emailverified.ts
// 기존 사용자들에게 emailVerified: true 추가 (HTTP 트리거, 한 번만 실행)

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

// HTTP 함수: /migrateEmailVerified?secret=YOUR_SECRET_KEY
export const migrateEmailVerified = functions.https.onRequest(async (req, res) => {
  // 보안: 비밀 키 확인 (환경변수로 설정하거나 직접 입력)
  const SECRET_KEY = 'wefilling_migration_2025'; // 변경 가능
  const providedSecret = req.query.secret || req.body.secret;
  
  if (providedSecret !== SECRET_KEY) {
    res.status(403).send('❌ Unauthorized: Invalid secret key');
    return;
  }
  
  console.log('🔧 마이그레이션 시작: emailVerified 필드 추가');
  
  try {
    const db = admin.firestore();
    
    // 모든 users 문서 가져오기
    const usersSnapshot = await db.collection('users').get();
    const totalUsers = usersSnapshot.docs.length;
    
    console.log(`📊 총 ${totalUsers}명의 사용자 찾음`);
    
    if (totalUsers === 0) {
      res.status(200).send('ℹ️ 업데이트할 사용자가 없습니다.');
      return;
    }
    
    // 배치 처리 (Firestore 배치는 최대 500개)
    const batches: admin.firestore.WriteBatch[] = [];
    let currentBatch = db.batch();
    let operationCount = 0;
    let batchCount = 0;
    
    let updatedCount = 0;
    let skippedCount = 0;
    const results: string[] = [];
    
    for (const doc of usersSnapshot.docs) {
      const data = doc.data();
      const uid = doc.id;
      const emailVerified = data.emailVerified;
      
      // 이미 emailVerified가 true면 스킵
      if (emailVerified === true) {
        skippedCount++;
        console.log(`⏭️  스킵: ${uid} (이미 emailVerified=true)`);
        continue;
      }
      
      // emailVerified: true 추가
      currentBatch.update(doc.ref, {
        emailVerified: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      operationCount++;
      updatedCount++;
      console.log(`✏️  업데이트: ${uid} (emailVerified=true 추가)`);
      results.push(`✅ ${uid}: emailVerified=true 추가`);
      
      // 500개마다 배치 교체
      if (operationCount >= 500) {
        batches.push(currentBatch);
        currentBatch = db.batch();
        batchCount++;
        operationCount = 0;
      }
    }
    
    // 마지막 배치 추가
    if (operationCount > 0) {
      batches.push(currentBatch);
      batchCount++;
    }
    
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('📊 업데이트 요약');
    console.log(`전체 사용자: ${totalUsers}명`);
    console.log(`업데이트할 사용자: ${updatedCount}명`);
    console.log(`스킵된 사용자: ${skippedCount}명`);
    console.log(`배치 개수: ${batchCount}개`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    if (updatedCount === 0) {
      res.status(200).send('ℹ️ 업데이트할 사용자가 없습니다. 모든 사용자가 이미 emailVerified=true입니다.');
      return;
    }
    
    // 모든 배치 커밋
    console.log('🔄 배치 실행 중...');
    let completedBatches = 0;
    for (const batch of batches) {
      await batch.commit();
      completedBatches++;
      console.log(`✅ 배치 ${completedBatches}/${batchCount} 완료`);
    }
    
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('✅ 마이그레이션 완료!');
    console.log(`업데이트된 사용자: ${updatedCount}명`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    res.status(200).json({
      success: true,
      message: '✅ 마이그레이션 완료!',
      totalUsers,
      updatedCount,
      skippedCount,
      batchCount,
      results: results.slice(0, 10), // 처음 10개만 반환
    });
    
  } catch (error) {
    console.error('❌ 마이그레이션 오류:', error);
    res.status(500).json({
      success: false,
      error: String(error),
    });
  }
});

