// Firebase CLI 인증을 사용하여 Firestore에 데이터 추가
const admin = require('firebase-admin');

// Firebase CLI의 인증 정보 사용
admin.initializeApp({
  projectId: 'flutterproject3-af322'
});

const db = admin.firestore();

async function setupRecommendedPlaces() {
  try {
    console.log('🚀 추천 장소 데이터 설정 시작...\n');

    // 스터디 카테고리
    await db.collection('recommended_places').doc('study').set({
      places: [
        {
          name: '스터디 카페 1',
          url: 'https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/37762082?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071903&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98',
          order: 1
        },
        {
          name: '스터디 카페 2',
          url: 'https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/1083319174?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071903&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98',
          order: 2
        }
      ]
    });
    console.log('✅ 스터디 카테고리 설정 완료');

    // 식사 카테고리
    await db.collection('recommended_places').doc('meal').set({
      places: [
        {
          name: '음식점 1',
          url: 'https://map.naver.com/p/search/%EC%9D%8C%EC%8B%9D%EC%A0%90/place/1647183115?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071902&locale=ko&svcName=map_pcv5&searchText=%EC%9D%8C%EC%8B%9D%EC%A0%90',
          order: 1
        },
        {
          name: '음식점 2',
          url: 'https://map.naver.com/p/search/%EC%9D%8C%EC%8B%9D%EC%A0%90/place/2020521950?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071902&locale=ko&svcName=map_pcv5&searchText=%EC%9D%8C%EC%8B%9D%EC%A0%90',
          order: 2
        },
        {
          name: '음식점 3',
          url: 'https://map.naver.com/p/search/%EC%9D%8C%EC%8B%9D%EC%A0%90/place/33657511?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071902&locale=ko&svcName=map_pcv5&searchText=%EC%9D%8C%EC%8B%9D%EC%A0%90',
          order: 3
        }
      ]
    });
    console.log('✅ 식사 카테고리 설정 완료');

    // 카페 카테고리 (hobby)
    await db.collection('recommended_places').doc('hobby').set({
      places: [
        {
          name: '카페 1',
          url: 'https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/33239471?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071901&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98',
          order: 1
        },
        {
          name: '카페 2',
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
    console.log('✅ 카페 카테고리 설정 완료');

    // 문화 카테고리
    await db.collection('recommended_places').doc('culture').set({
      places: [
        {
          name: '보드게임 카페',
          url: 'https://map.naver.com/p/search/%EB%B3%B4%EB%93%9C%EA%B2%8C%EC%9E%84/place/2078177472?c=13.66,0,0,0,dh&placePath=/home?from=map&fromPanelNum=2&timestamp=202512071903&locale=ko&svcName=map_pcv5&searchText=%EB%B3%B4%EB%93%9C%EA%B2%8C%EC%9E%84',
          order: 1
        },
        {
          name: '노래방',
          url: 'https://map.naver.com/p/search/%EB%85%B8%EB%9E%98%EB%B0%A9/place/1395923818?c=14.77,0,0,0,dh&placePath=/home?from=map&fromPanelNum=2&timestamp=202512071904&locale=ko&svcName=map_pcv5&searchText=%EB%85%B8%EB%9E%98%EB%B0%A9',
          order: 2
        }
      ]
    });
    console.log('✅ 문화 카테고리 설정 완료');

    // 기타 카테고리 (빈 배열)
    await db.collection('recommended_places').doc('other').set({
      places: []
    });
    console.log('✅ 기타 카테고리 설정 완료');

    console.log('\n🎉 모든 추천 장소 데이터 설정 완료!\n');
    
    // 설정된 데이터 확인
    console.log('📋 설정된 데이터 확인:\n');
    const categories = ['study', 'meal', 'hobby', 'culture', 'other'];
    for (const category of categories) {
      const doc = await db.collection('recommended_places').doc(category).get();
      const data = doc.data();
      console.log(`${category}: ${data.places.length}개의 장소`);
    }

    process.exit(0);
  } catch (error) {
    console.error('❌ 오류 발생:', error);
    process.exit(1);
  }
}

setupRecommendedPlaces();
