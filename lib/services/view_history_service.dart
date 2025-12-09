// lib/services/view_history_service.dart
// 조회 이력 관리 서비스
// 세션 기반으로 게시글/모임 조회 이력을 메모리에 저장
// 앱 재시작 시 자동 초기화

import '../utils/logger.dart';

/// 조회 이력 관리 서비스 (싱글톤)
/// 
/// 세션 동안 사용자가 조회한 게시글/모임을 추적하여
/// 중복 조회수 카운트를 방지합니다.
/// 
/// 특징:
/// - 메모리 기반 (앱 재시작 시 초기화)
/// - 싱글톤 패턴으로 전역 상태 관리
/// - O(1) 조회 성능
class ViewHistoryService {
  // 싱글톤 인스턴스
  static final ViewHistoryService _instance = ViewHistoryService._internal();
  
  factory ViewHistoryService() {
    return _instance;
  }
  
  ViewHistoryService._internal() {
    Logger.log('🔍 ViewHistoryService 초기화됨');
  }
  
  // 조회 이력 저장소 (contentType_contentId 형식)
  final Set<String> _viewedItems = {};
  
  /// 조회 이력 키 생성
  /// 
  /// [contentType]: 'post' 또는 'meetup'
  /// [contentId]: 게시글/모임 ID
  String _makeKey(String contentType, String contentId) {
    return '${contentType}_$contentId';
  }
  
  /// 이미 조회한 항목인지 확인
  /// 
  /// [contentType]: 'post' 또는 'meetup'
  /// [contentId]: 게시글/모임 ID
  /// 
  /// Returns: 이미 조회한 경우 true, 처음 조회하는 경우 false
  bool hasViewed(String contentType, String contentId) {
    final key = _makeKey(contentType, contentId);
    final viewed = _viewedItems.contains(key);
    
    if (viewed) {
      Logger.log('🔍 [ViewHistory] 이미 조회한 항목: $contentType ($contentId)');
    } else {
      Logger.log('🔍 [ViewHistory] 처음 조회하는 항목: $contentType ($contentId)');
    }
    
    return viewed;
  }
  
  /// 조회 이력에 추가
  /// 
  /// [contentType]: 'post' 또는 'meetup'
  /// [contentId]: 게시글/모임 ID
  void markAsViewed(String contentType, String contentId) {
    final key = _makeKey(contentType, contentId);
    _viewedItems.add(key);
    
    Logger.log('✅ [ViewHistory] 조회 이력 추가: $contentType ($contentId)');
    Logger.log('📊 [ViewHistory] 현재 조회 이력 수: ${_viewedItems.length}개');
  }
  
  /// 조회 이력 초기화 (테스트 또는 로그아웃 시 사용)
  void clearHistory() {
    final count = _viewedItems.length;
    _viewedItems.clear();
    
    Logger.log('🗑️ [ViewHistory] 조회 이력 초기화: ${count}개 항목 삭제됨');
  }
  
  /// 현재 조회 이력 개수 반환 (디버깅용)
  int get historyCount => _viewedItems.length;
  
  /// 특정 타입의 조회 이력 개수 반환 (디버깅용)
  int getHistoryCountByType(String contentType) {
    return _viewedItems.where((key) => key.startsWith('${contentType}_')).length;
  }
}




