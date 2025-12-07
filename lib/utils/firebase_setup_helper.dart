// lib/utils/firebase_setup_helper.dart
// Firebase 초기 데이터 설정 헬퍼
// 관리자용: 추천 장소 데이터 초기화

import 'package:cloud_firestore/cloud_firestore.dart';
import 'logger.dart';

class FirebaseSetupHelper {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 추천 장소 초기 데이터 설정
  /// 
  /// 주의: 이 메서드는 한 번만 실행하거나, 데이터를 초기화할 때만 사용하세요.
  /// Firebase Console에서 직접 수정하는 것을 권장합니다.
  static Future<void> setupRecommendedPlaces() async {
    try {
      Logger.log('추천 장소 데이터 설정 시작...');

      // 스터디 카테고리
      await _firestore.collection('recommended_places').doc('study').set({
        'places': [
          {
            'name': '스터디 카페 1',
            'url': 'https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/37762082?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071903&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98',
            'order': 1,
          },
          {
            'name': '스터디 카페 2',
            'url': 'https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/1083319174?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071903&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98',
            'order': 2,
          },
        ],
      });
      Logger.log('스터디 카테고리 설정 완료');

      // 식사 카테고리
      await _firestore.collection('recommended_places').doc('meal').set({
        'places': [
          {
            'name': '음식점 1',
            'url': 'https://map.naver.com/p/search/%EC%9D%8C%EC%8B%9D%EC%A0%90/place/1647183115?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071902&locale=ko&svcName=map_pcv5&searchText=%EC%9D%8C%EC%8B%9D%EC%A0%90',
            'order': 1,
          },
          {
            'name': '음식점 2',
            'url': 'https://map.naver.com/p/search/%EC%9D%8C%EC%8B%9D%EC%A0%90/place/2020521950?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071902&locale=ko&svcName=map_pcv5&searchText=%EC%9D%8C%EC%8B%9D%EC%A0%90',
            'order': 2,
          },
          {
            'name': '음식점 3',
            'url': 'https://map.naver.com/p/search/%EC%9D%8C%EC%8B%9D%EC%A0%90/place/33657511?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071902&locale=ko&svcName=map_pcv5&searchText=%EC%9D%8C%EC%8B%9D%EC%A0%90',
            'order': 3,
          },
        ],
      });
      Logger.log('식사 카테고리 설정 완료');

      // 카페 카테고리 (hobby)
      await _firestore.collection('recommended_places').doc('hobby').set({
        'places': [
          {
            'name': '카페 1',
            'url': 'https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/33239471?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071901&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98',
            'order': 1,
          },
          {
            'name': '카페 2',
            'url': 'https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/1182416697?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071902&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98',
            'order': 2,
          },
          {
            'name': '카페 3',
            'url': 'https://map.naver.com/p/search/%EC%B9%B4%ED%8E%98/place/1114967069?c=16.30,0,0,0,dh&placePath=/home?entry=bmp&from=map&fromPanelNum=2&timestamp=202512071902&locale=ko&svcName=map_pcv5&searchText=%EC%B9%B4%ED%8E%98',
            'order': 3,
          },
        ],
      });
      Logger.log('카페 카테고리 설정 완료');

      // 문화 카테고리
      await _firestore.collection('recommended_places').doc('culture').set({
        'places': [
          {
            'name': '보드게임 카페',
            'url': 'https://map.naver.com/p/search/%EB%B3%B4%EB%93%9C%EA%B2%8C%EC%9E%84/place/2078177472?c=13.66,0,0,0,dh&placePath=/home?from=map&fromPanelNum=2&timestamp=202512071903&locale=ko&svcName=map_pcv5&searchText=%EB%B3%B4%EB%93%9C%EA%B2%8C%EC%9E%84',
            'order': 1,
          },
          {
            'name': '노래방',
            'url': 'https://map.naver.com/p/search/%EB%85%B8%EB%9E%98%EB%B0%A9/place/1395923818?c=14.77,0,0,0,dh&placePath=/home?from=map&fromPanelNum=2&timestamp=202512071904&locale=ko&svcName=map_pcv5&searchText=%EB%85%B8%EB%9E%98%EB%B0%A9',
            'order': 2,
          },
        ],
      });
      Logger.log('문화 카테고리 설정 완료');

      // 기타 카테고리 (빈 배열)
      await _firestore.collection('recommended_places').doc('other').set({
        'places': [],
      });
      Logger.log('기타 카테고리 설정 완료');

      Logger.log('✅ 모든 추천 장소 데이터 설정 완료!');
    } catch (e) {
      Logger.log('❌ 추천 장소 데이터 설정 실패: $e');
      rethrow;
    }
  }

  /// 특정 카테고리의 추천 장소 업데이트
  /// 
  /// [category]: 카테고리 키 (study, meal, hobby, culture, other)
  /// [places]: 추천 장소 리스트
  static Future<void> updateCategoryPlaces(
    String category,
    List<Map<String, dynamic>> places,
  ) async {
    try {
      await _firestore.collection('recommended_places').doc(category).set({
        'places': places,
      });
      Logger.log('$category 카테고리 업데이트 완료');
    } catch (e) {
      Logger.log('$category 카테고리 업데이트 실패: $e');
      rethrow;
    }
  }
}
