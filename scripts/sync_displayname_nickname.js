// scripts/sync_displayname_nickname.js
// Firebase Console에서 실행할 수 있는 displayName-nickname 동기화 스크립트
// 
// 실행 방법:
// 1. Firebase Console > Firestore > 데이터 탭으로 이동
// 2. 브라우저 개발자 도구 (F12) 열기
// 3. Console 탭으로 이동
// 4. 이 스크립트를 복사해서 붙여넣기
// 5. Enter 키를 눌러 실행

(async function syncDisplayNameWithNickname() {
  console.log('🚀 displayName과 nickname 동기화 스크립트 시작');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  try {
    // Firestore 참조 가져오기
    const db = firebase.firestore();
    
    // 모든 사용자 문서 가져오기
    console.log('📋 사용자 데이터 조회 중...');
    const usersSnapshot = await db.collection('users').get();
    console.log(`✅ 총 ${usersSnapshot.docs.length}명의 사용자 발견\n`);

    let updatedCount = 0;
    let skippedCount = 0;
    let errorCount = 0;

    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('🔄 동기화 작업 시작');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    // 배치 처리
    let batch = db.batch();
    let batchCount = 0;
    const maxBatchSize = 500;

    for (const doc of usersSnapshot.docs) {
      try {
        const data = doc.data();
        const userId = doc.id;
        const nickname = data.nickname;
        const displayName = data.displayName;

        console.log(`👤 사용자 ID: ${userId}`);
        console.log(`   현재 nickname: ${nickname || "(없음)"}`);
        console.log(`   현재 displayName: ${displayName || "(없음)"}`);

        // nickname이 없으면 건너뛰기
        if (!nickname || nickname === '') {
          console.log('   ⚠️  건너뜀: nickname이 없음\n');
          skippedCount++;
          continue;
        }

        // displayName이 이미 nickname과 같으면 건너뛰기
        if (displayName === nickname) {
          console.log('   ✅ 건너뜀: 이미 동기화됨\n');
          skippedCount++;
          continue;
        }

        // displayName을 nickname으로 업데이트
        batch.update(doc.ref, {
          displayName: nickname,
          updatedAt: firebase.firestore.FieldValue.serverTimestamp()
        });

        batchCount++;
        updatedCount++;
        console.log(`   🔄 업데이트 예정: displayName = "${nickname}"\n`);

        // 배치가 가득 차면 커밋
        if (batchCount >= maxBatchSize) {
          console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          console.log(`💾 배치 커밋 중... (${batchCount}개 항목)`);
          await batch.commit();
          console.log('✅ 배치 커밋 완료\n');
          
          // 새 배치 시작
          batch = db.batch();
          batchCount = 0;
        }
      } catch (e) {
        console.error(`   ❌ 오류: ${e}\n`);
        errorCount++;
      }
    }

    // 남은 배치 커밋
    if (batchCount > 0) {
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      console.log(`💾 최종 배치 커밋 중... (${batchCount}개 항목)`);
      await batch.commit();
      console.log('✅ 최종 배치 커밋 완료\n');
    }

    // 최종 결과 출력
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('🎉 동기화 작업 완료!');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('📊 처리 결과:');
    console.log(`   ✅ 업데이트됨: ${updatedCount}명`);
    console.log(`   ⏭️  건너뜀: ${skippedCount}명`);
    console.log(`   ❌ 오류: ${errorCount}명`);
    console.log(`   📋 총 사용자: ${usersSnapshot.docs.length}명`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  } catch (e) {
    console.error('❌ 스크립트 실행 오류:', e);
  }
})();

