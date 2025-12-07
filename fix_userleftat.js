// Firebase Admin SDK로 userLeftAt 필드 삭제 스크립트
// 사용법: node fix_userleftat.js

const admin = require('firebase-admin');

// Firebase Admin SDK 초기화 (serviceAccountKey.json 필요)
// admin.initializeApp({
//   credential: admin.credential.cert('./serviceAccountKey.json')
// });

const db = admin.firestore();

// 수정할 대화방 정보
const conversationId = 'CNAYONUHSVMUwowhnzrxIn82ELs2_TjZWjNW75dMqCG1j51QVD1GhXIP2';
const userId = 'CNAYONUHSVMUwowhnzrxIn82ELs2'; // 남태평양 계정 UID

async function fixUserLeftAt() {
  try {
    console.log('🔧 userLeftAt 필드 삭제 시작...');
    console.log(`  - conversationId: ${conversationId}`);
    console.log(`  - userId: ${userId}`);
    
    // userLeftAt 필드에서 해당 사용자 키 삭제
    await db.collection('conversations').doc(conversationId).update({
      [`userLeftAt.${userId}`]: admin.firestore.FieldValue.delete()
    });
    
    console.log('✅ userLeftAt 필드 삭제 완료!');
    console.log('이제 모든 메시지가 표시됩니다.');
    
  } catch (error) {
    console.error('❌ 오류 발생:', error);
  }
}

// 실행
fixUserLeftAt();









