const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkConversation() {
  try {
    // 모든 대화방 조회
    const snapshot = await db.collection('conversations').get();
    
    console.log('=== 전체 대화방 목록 ===');
    snapshot.forEach(doc => {
      const data = doc.data();
      console.log(`\nID: ${doc.id}`);
      console.log(`  participants: ${JSON.stringify(data.participants)}`);
      console.log(`  participantNames: ${JSON.stringify(data.participantNames)}`);
      console.log(`  lastMessage: ${data.lastMessage}`);
      
      // 남태평양 대화방 찾기
      if (data.participantNames) {
        const names = Object.values(data.participantNames);
        if (names.includes('남태평양')) {
          console.log('\n🔍 === 남태평양 대화방 발견! ===');
          console.log(JSON.stringify(data, null, 2));
        }
      }
    });
    
    process.exit(0);
  } catch (error) {
    console.error('오류:', error);
    process.exit(1);
  }
}

checkConversation();
