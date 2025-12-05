// lib/services/cache/cache_feature_flags.dart
// 캐시 시스템 Feature Flag 관리

import '../feature_flag_service.dart';

/// 캐시 시스템 Feature Flag
/// Firebase Remote Config를 통해 캐시 기능을 동적으로 on/off 할 수 있습니다.
class CacheFeatureFlags {
  static final FeatureFlagService _flags = FeatureFlagService();
  
  /// 전체 캐시 시스템 활성화 여부
  static bool get isEnabled => 
    _flags.isFeatureEnabled('cache_system_enabled');
  
  /// 게시글 캐시 활성화 여부
  static bool get isPostCacheEnabled => 
    isEnabled && _flags.isFeatureEnabled('post_cache_enabled');
  
  /// 댓글 캐시 활성화 여부
  static bool get isCommentCacheEnabled => 
    isEnabled && _flags.isFeatureEnabled('comment_cache_enabled');
  
  /// 모임 캐시 활성화 여부
  static bool get isMeetupCacheEnabled => 
    isEnabled && _flags.isFeatureEnabled('meetup_cache_enabled');
  
  /// DM 캐시 활성화 여부
  static bool get isDMCacheEnabled => 
    isEnabled && _flags.isFeatureEnabled('dm_cache_enabled');
  
  /// 프로필 캐시 활성화 여부
  static bool get isProfileCacheEnabled => 
    isEnabled && _flags.isFeatureEnabled('profile_cache_enabled');
}





