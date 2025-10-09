// functions/src/initAds.ts
// 광고 배너 초기 데이터를 Firestore에 추가하는 Cloud Function

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

export const initializeAds = functions.https.onRequest(async (req, res) => {
  try {
    const db = admin.firestore();
    const adsCollection = db.collection('ad_banners');

    // 초기 광고 데이터
    const initialAds = [
      {
        id: 'banner_001',
        title: '한양대 에리카 국제처',
        description: '교환학생 프로그램 및 국제 교류 정보',
        url: 'https://oia.hanyang.ac.kr/',
        imageUrl: null,
        isActive: true,
        order: 1,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {
        id: 'banner_002',
        title: '한양대 에리카 중앙동아리',
        description: '다양한 동아리 활동과 학생 커뮤니티',
        url: 'https://esc.hanyang.ac.kr/-29',
        imageUrl: null,
        isActive: true,
        order: 2,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {
        id: 'banner_003',
        title: '이스턴문 - 예술가의 아지트 카페',
        description: '한양대 숨은 명소, 직접 만든 시그니처 디저트와 콜드브루',
        url: 'https://map.naver.com/p/entry/place/1375980272?lng=126.8398484&lat=37.3007216&placePath=%2Fhome&entry=plt&searchType=place',
        imageUrl: null,
        isActive: true,
        order: 3,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {
        id: 'banner_004',
        title: '프로스콘스',
        description: '한양대 근처 인기 맛집',
        url: 'https://map.naver.com/p/search/%ED%94%84%EB%A1%9C%EC%8A%A4%EC%BD%98%EC%8A%A4/place/1114967069',
        imageUrl: null,
        isActive: true,
        order: 4,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {
        id: 'banner_005',
        title: '한양대 주변 추천 장소',
        description: '학생들이 자주 찾는 핫플레이스',
        url: 'https://map.naver.com/p/entry/place/1647183115',
        imageUrl: null,
        isActive: true,
        order: 5,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    ];

    // Batch write로 한 번에 추가
    const batch = db.batch();
    
    for (const ad of initialAds) {
      const docRef = adsCollection.doc(ad.id);
      batch.set(docRef, ad, { merge: true }); // merge: true로 기존 데이터가 있으면 업데이트
    }

    await batch.commit();

    res.status(200).json({
      success: true,
      message: '광고 배너 데이터가 성공적으로 추가되었습니다!',
      count: initialAds.length,
      ads: initialAds.map(ad => ({ id: ad.id, title: ad.title })),
    });
  } catch (error) {
    console.error('광고 초기화 오류:', error);
    res.status(500).json({
      success: false,
      message: '광고 배너 초기화 중 오류가 발생했습니다.',
      error: String(error),
    });
  }
});


