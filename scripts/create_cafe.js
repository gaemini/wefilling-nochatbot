// cafe 문서 생성
const admin = require('firebase-admin');
admin.initializeApp({ projectId: 'flutterproject3-af322' });
const db = admin.firestore();

async function createCafe() {
  try {
    console.log('🚀 cafe 문서 생성 시작...\n');

    // cafe 문서 생성 (기존 hobby 데이터 사용)
    await db.collection('recommended_places').doc('cafe').set({
      places: [
        {
          name: '스타벅스 안산한양대점 (Starbucks)',
          url: 'https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/33239471?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071901&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98',
          order: 1
        },
        {
          name: '더스크커피랩 (Dusk Coffee Lab)',
          url: 'https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/1182416697?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071902&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98',
          order: 2
        },
        {
          name: '카페 3',
          url: 'https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/1114967069?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071902&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98',
          order: 3
        }
      ]
    });
    console.log('✅ cafe 문서 생성 완료');

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

createCafe();
