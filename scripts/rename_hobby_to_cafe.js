// Firebase에서 hobby 문서를 cafe로 변경
const admin = require('firebase-admin');
admin.initializeApp({ projectId: 'flutterproject3-af322' });
const db = admin.firestore();

async function renameHobbyToCafe() {
  try {
    console.log('🚀 hobby → cafe 변경 시작...\n');

    // 1. hobby 문서 데이터 가져오기
    const hobbyDoc = await db.collection('recommended_places').doc('hobby').get();
    
    if (!hobbyDoc.exists) {
      console.log('❌ hobby 문서가 존재하지 않습니다');
      process.exit(1);
    }

    const hobbyData = hobbyDoc.data();
    console.log('✅ hobby 문서 데이터 가져오기 완료');

    // 2. cafe 문서로 복사
    await db.collection('recommended_places').doc('cafe').set(hobbyData);
    console.log('✅ cafe 문서 생성 완료');

    // 3. hobby 문서 삭제
    await db.collection('recommended_places').doc('hobby').delete();
    console.log('✅ hobby 문서 삭제 완료');

    console.log('\n🎉 hobby → cafe 변경 완료!\n');
    
    // 확인
    const cafeDoc = await db.collection('recommended_places').doc('cafe').get();
    const cafeData = cafeDoc.data();
    console.log(`📋 cafe 문서 확인: ${cafeData.places.length}개의 장소`);

    process.exit(0);
  } catch (error) {
    console.error('❌ 오류 발생:', error);
    process.exit(1);
  }
}

renameHobbyToCafe();
