// lib/services/ad_banner_service.dart
// Firebase Firestore에서 광고 배너를 관리하는 서비스

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ad_banner.dart';
import '../utils/logger.dart';

class AdBannerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collectionName = 'ad_banners';

  /// 모든 활성 광고 배너를 실시간으로 스트림
  /// 인덱스 불필요: 전체 조회 후 클라이언트에서 필터링 및 정렬
  Stream<List<AdBanner>> getActiveBannersStream() {
    return _firestore
        .collection(_collectionName)
        .snapshots()
        .map((snapshot) {
      final banners = snapshot.docs
          .map((doc) {
            try {
              return AdBanner.fromFirestore(doc);
            } catch (e) {
              Logger.error('❌ 배너 파싱 실패: ${doc.id} - $e');
              return null;
            }
          })
          .where((banner) => banner != null && banner.isActive)
          .cast<AdBanner>()
          .toList();
      
      // order 필드로 정렬
      banners.sort((a, b) => a.order.compareTo(b.order));
      
      return banners;
    });
  }

  /// 모든 활성 광고 배너를 한 번만 가져오기 (캐싱용)
  /// 인덱스 불필요: 전체 조회 후 클라이언트에서 필터링 및 정렬
  Future<List<AdBanner>> getActiveBanners() async {
    try {
      final snapshot = await _firestore
          .collection(_collectionName)
          .get();

      final banners = snapshot.docs
          .map((doc) {
            try {
              return AdBanner.fromFirestore(doc);
            } catch (e) {
              Logger.error('❌ 배너 파싱 실패: ${doc.id} - $e');
              return null;
            }
          })
          .where((banner) => banner != null && banner.isActive)
          .cast<AdBanner>()
          .toList();
      
      // order 필드로 정렬
      banners.sort((a, b) => a.order.compareTo(b.order));
      
      return banners;
    } catch (e) {
      Logger.error('❌ 광고 배너 가져오기 오류: $e');
      return [];
    }
  }

  /// 특정 광고 배너 가져오기
  Future<AdBanner?> getBannerById(String bannerId) async {
    try {
      final doc = await _firestore
          .collection(_collectionName)
          .doc(bannerId)
          .get();

      if (doc.exists) {
        return AdBanner.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      Logger.error('❌ 광고 배너 가져오기 오류: $e');
      return null;
    }
  }

  /// 새 광고 배너 추가 (관리자용)
  Future<String?> addBanner(AdBanner banner) async {
    try {
      final docRef = await _firestore
          .collection(_collectionName)
          .add(banner.toJson());
      Logger.log('✅ 광고 배너 추가 완료: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      Logger.error('❌ 광고 배너 추가 오류: $e');
      return null;
    }
  }

  /// 광고 배너 수정 (관리자용)
  Future<bool> updateBanner(String bannerId, Map<String, dynamic> updates) async {
    try {
      await _firestore
          .collection(_collectionName)
          .doc(bannerId)
          .update({
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      Logger.log('✅ 광고 배너 수정 완료: $bannerId');
      return true;
    } catch (e) {
      Logger.error('❌ 광고 배너 수정 오류: $e');
      return false;
    }
  }

  /// 광고 배너 삭제 (관리자용)
  Future<bool> deleteBanner(String bannerId) async {
    try {
      await _firestore
          .collection(_collectionName)
          .doc(bannerId)
          .delete();
      Logger.log('✅ 광고 배너 삭제 완료: $bannerId');
      return true;
    } catch (e) {
      Logger.error('❌ 광고 배너 삭제 오류: $e');
      return false;
    }
  }

  /// 광고 배너 활성화/비활성화 (관리자용)
  Future<bool> toggleBannerActive(String bannerId, bool isActive) async {
    return updateBanner(bannerId, {'isActive': isActive});
  }

  /// 광고 배너 순서 변경 (관리자용)
  Future<bool> updateBannerOrder(String bannerId, int order) async {
    return updateBanner(bannerId, {'order': order});
  }

  /// 초기 샘플 광고 데이터 생성
  Future<void> initializeSampleBanners() async {
    try {
      Logger.log('🔄 광고 배너 초기화 시작...');

      // 샘플 광고 데이터
      final sampleBanners = [
        AdBanner(
          id: 'banner_001',
          title: 'MCPC 중앙동아리',
          description: '외국인 유학생과 한국인 학생의 문화, 언어 교류 동아리',
          url: 'https://swift-graphs-363644.framer.app/',
          isActive: true,
          order: 1,
          createdAt: DateTime.now(),
        ),
        AdBanner(
          id: 'banner_002',
          title: 'ERICA 다솜채플',
          description: '한양대 에리카의 영원한 삶의 안식처',
          url: 'https://site.hanyang.ac.kr/web/dasom',
          isActive: true,
          order: 2,
          createdAt: DateTime.now(),
        ),
        AdBanner(
          id: 'banner_003',
          title: '이스턴문 카페',
          description: '예술가의 아지트, 한양대 숨은 명소 카페',
          url: 'https://map.naver.com/p/entry/place/1375980272',
          isActive: true,
          order: 3,
          createdAt: DateTime.now(),
        ),
        AdBanner(
          id: 'banner_004',
          title: '프로스콘스 안산',
          description: '한양대 학생들의 인기 맛집',
          url: 'https://map.naver.com/p/search/%ED%94%84%EB%A1%9C%EC%8A%A4%EC%BD%98%EC%8A%A4%20%EC%95%88%EC%82%B0/place/1114967069',
          isActive: true,
          order: 4,
          createdAt: DateTime.now(),
        ),
        AdBanner(
          id: 'banner_005',
          title: '한양대 근처 추천 장소',
          description: '학생들이 자주 찾는 주변 명소',
          url: 'https://map.naver.com/p/entry/place/1647183115',
          isActive: true,
          order: 5,
          createdAt: DateTime.now(),
        ),
      ];

      // 배너 추가 (덮어쓰기)
      for (final banner in sampleBanners) {
        await _firestore
            .collection(_collectionName)
            .doc(banner.id)
            .set(banner.toJson(), SetOptions(merge: false)); // 기존 데이터 덮어쓰기
        Logger.log('✅ 광고 배너 업데이트: ${banner.id} - ${banner.title}');
      }

      Logger.log('✅ 총 ${sampleBanners.length}개 광고 배너 업데이트 완료!');
    } catch (e) {
      Logger.error('❌ 초기 광고 배너 생성 오류: $e');
    }
  }
}
