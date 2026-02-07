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
  // 옵션 A: mainImageUrl(버튼 썸네일), mapImageUrl(선택 시 첨부)
  final String? mainImageUrl;
  final String? mapImageUrl;

  // 하위 호환: 기존 imageUrl(=mainImageUrl로 취급)
  final String? imageUrl;

  RecommendedPlace({
    required this.name,
    required this.url,
    required this.order,
    required this.mainImageUrl,
    required this.mapImageUrl,
    required this.imageUrl,
  });

  String? get thumbnailUrl {
    final m = mainImageUrl?.trim();
    if (m != null && m.isNotEmpty) return m;
    final legacy = imageUrl?.trim();
    if (legacy != null && legacy.isNotEmpty) return legacy;
    return null;
  }

  factory RecommendedPlace.fromMap(Map<String, dynamic> map) {
    final rawOrder = map['order'];
    int parsedOrder = 0;
    if (rawOrder is int) {
      parsedOrder = rawOrder;
    } else if (rawOrder is num) {
      parsedOrder = rawOrder.toInt();
    } else if (rawOrder is String) {
      parsedOrder = int.tryParse(rawOrder.trim()) ?? 0;
    }

    final mainUrl = (map['mainImageUrl'] as String?)?.trim();
    final mapUrl = (map['mapImageUrl'] as String?)?.trim();
    final legacyUrl = (map['imageUrl'] as String?)?.trim();

    return RecommendedPlace(
      name: (map['name'] ?? '').toString(),
      url: (map['url'] ?? '').toString(),
      order: parsedOrder,
      mainImageUrl: (mainUrl == null || mainUrl.isEmpty) ? null : mainUrl,
      mapImageUrl: (mapUrl == null || mapUrl.isEmpty) ? null : mapUrl,
      imageUrl: (legacyUrl == null || legacyUrl.isEmpty) ? null : legacyUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'url': url,
      'order': order,
      'mainImageUrl': mainImageUrl,
      'mapImageUrl': mapImageUrl,
      'imageUrl': imageUrl,
    };
  }
}

/// 추천 장소 서비스
class RecommendedPlacesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<String> _candidateDocIds(String category) {
    final raw = category.trim();
    if (raw.isEmpty) return const [];

    final candidates = <String>[raw];
    final lower = raw.toLowerCase();
    if (lower != raw) candidates.add(lower);

    // 하위 호환/운영 데이터 편차 대응
    // - drink: 콘솔에 'Drinks'로 저장된 경우가 있어 폴백
    if (lower == 'drink') {
      candidates.add('Drinks');
    }
    // - cafe: 과거 스크립트에서 'hobby'로 저장했던 흔적 폴백
    if (lower == 'cafe') {
      candidates.add('hobby');
    }

    // 중복 제거(순서 유지)
    final seen = <String>{};
    return candidates.where((id) => seen.add(id)).toList();
  }

  /// 카테고리별 추천 장소 가져오기
  /// 
  /// [category]: 카테고리 키 (study, meal, hobby, culture, other)
  /// 
  /// Returns: 추천 장소 리스트 (order 기준 정렬)
  Future<List<RecommendedPlace>> getRecommendedPlaces(String category) async {
    try {
      final docIds = _candidateDocIds(category);
      if (docIds.isEmpty) return [];

      DocumentSnapshot<Map<String, dynamic>>? found;
      String? foundId;

      for (final docId in docIds) {
        final doc = await _firestore
            .collection('recommended_places')
            .doc(docId)
            .get();
        if (doc.exists) {
          found = doc;
          foundId = docId;
          break;
        }
      }

      if (found == null || foundId == null) {
        Logger.log('추천 장소 문서 없음: $category (tried: ${docIds.join(", ")})');
        return [];
      }

      final data = found.data();
      if (data == null || !data.containsKey('places')) {
        Logger.log('추천 장소 데이터 없음: $foundId (requested: $category)');
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
      
      Logger.log('추천 장소 로드 성공: $foundId (requested: $category, ${places.length}개)');
      return places;
    } catch (e) {
      Logger.log('추천 장소 로드 실패: $e');
      return [];
    }
  }

  /// Firebase Console에서 관리하므로 추가/수정 메서드는 선택사항
  /// 필요시 Admin 기능으로 구현 가능
}
