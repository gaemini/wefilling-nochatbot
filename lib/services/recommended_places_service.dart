// lib/services/recommended_places_service.dart
// 카테고리별 추천 장소 관리 서비스
// Firebase에서 추천 장소 데이터 로드

import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/logger.dart';

/// 추천 장소 모델
class RecommendedPlace {
  final String name;
  final String url;
  final int order;

  RecommendedPlace({
    required this.name,
    required this.url,
    required this.order,
  });

  factory RecommendedPlace.fromMap(Map<String, dynamic> map) {
    return RecommendedPlace(
      name: map['name'] ?? '',
      url: map['url'] ?? '',
      order: map['order'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'url': url,
      'order': order,
    };
  }
}

/// 추천 장소 서비스
class RecommendedPlacesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 카테고리별 추천 장소 가져오기
  /// 
  /// [category]: 카테고리 키 (study, meal, hobby, culture, other)
  /// 
  /// Returns: 추천 장소 리스트 (order 기준 정렬)
  Future<List<RecommendedPlace>> getRecommendedPlaces(String category) async {
    try {
      final doc = await _firestore
          .collection('recommended_places')
          .doc(category)
          .get();

      if (!doc.exists) {
        Logger.log('추천 장소 문서 없음: $category');
        return [];
      }

      final data = doc.data();
      if (data == null || !data.containsKey('places')) {
        Logger.log('추천 장소 데이터 없음: $category');
        return [];
      }

      final places = (data['places'] as List<dynamic>?)
          ?.map((place) {
            try {
              return RecommendedPlace.fromMap(place as Map<String, dynamic>);
            } catch (e) {
              Logger.log('추천 장소 파싱 실패: $e');
              return null;
            }
          })
          .whereType<RecommendedPlace>()
          .toList() ?? [];

      // order 기준으로 정렬
      places.sort((a, b) => a.order.compareTo(b.order));
      
      Logger.log('추천 장소 로드 성공: $category (${places.length}개)');
      return places;
    } catch (e) {
      Logger.log('추천 장소 로드 실패: $e');
      return [];
    }
  }

  /// Firebase Console에서 관리하므로 추가/수정 메서드는 선택사항
  /// 필요시 Admin 기능으로 구현 가능
}
