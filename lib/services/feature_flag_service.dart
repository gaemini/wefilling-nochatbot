// lib/services/feature_flag_service.dart
// Feature Flag 관리 서비스
// 새로운 기능을 안전하게 출시하기 위한 토글 시스템
// 환경변수 및 Firebase Remote Config 지원

import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import '../utils/logger.dart';
import 'firebase_app_check_service.dart';

class FeatureFlagService {
  static final FeatureFlagService _instance = FeatureFlagService._internal();
  factory FeatureFlagService() => _instance;
  FeatureFlagService._internal();

  late SharedPreferences _prefs;
  late FirebaseRemoteConfig _remoteConfig;
  bool _isInitialized = false;

  // Feature Flag Keys
  static const String FEATURE_PROFILE_GRID = 'feature_profile_grid';
  static const String FEATURE_REVIEW_CONSENSUS = 'feature_review_consensus';

  /// 서비스 초기화
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // SharedPreferences 초기화
      _prefs = await SharedPreferences.getInstance();

      // Firebase Remote Config 초기화
      _remoteConfig = FirebaseRemoteConfig.instance;
      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 1),
      ));

      // 기본값 설정 (모든 feature flag는 기본적으로 false)
      await _remoteConfig.setDefaults({
        FEATURE_PROFILE_GRID: false,
        FEATURE_REVIEW_CONSENSUS: false,
      });

      // Placeholder/unavailable App Check 상태에서 Remote Config 요청을
      // 반복하지 않는다. 기능 플래그 기본값(false)은 그대로 안전하다.
      if (FirebaseAppCheckService.instance.isReady) {
        await _fetchRemoteConfig();
      }

      _isInitialized = true;
    } catch (e) {
      Logger.error('⚠️ FeatureFlagService 초기화 오류: $e');
      // 초기화 실패 시에도 로컬 설정은 사용할 수 있도록 함
      _isInitialized = true;
    }
  }

  /// Feature Flag 상태 확인
  bool isFeatureEnabled(String featureKey) {
    if (!_isInitialized) {
      if (Logger.isVerboseEnabled) Logger.log('⚠️ FeatureFlagService가 초기화되지 않음. 기본값(false) 반환');
      return false;
    }

    try {
      // 1. 환경변수 확인 (개발/테스트용)
      final envValue = _getEnvironmentValue(featureKey);
      if (envValue != null) {
        if (Logger.isVerboseEnabled) Logger.log('🚩 환경변수에서 $featureKey = $envValue');
        return envValue;
      }

      // 2. SharedPreferences 확인 (로컬 오버라이드)
      final localValue = _prefs.getBool('local_$featureKey');
      if (localValue != null) {
        if (Logger.isVerboseEnabled) Logger.log('🚩 로컬 설정에서 $featureKey = $localValue');
        return localValue;
      }

      // 3. Firebase Remote Config 확인
      final remoteValue = _remoteConfig.getBool(featureKey);
      return remoteValue;
    } catch (e) {
      Logger.error('⚠️ Feature Flag 확인 오류 ($featureKey): $e');
      return false; // 안전한 기본값
    }
  }

  // ---------------------------------------------------------------------------
  // Backward-compatible API (tests / legacy call sites)
  // ---------------------------------------------------------------------------
  /// (Legacy) 비동기 형태의 플래그 확인 API
  /// - 기존 테스트/코드가 `await isEnabled(...)` 형태를 기대하는 경우를 위해 제공한다.
  Future<bool> isEnabled(String featureKey) async {
    if (!_isInitialized) {
      // init 실패는 기능을 막지 않도록 흡수
      try {
        await init();
      } catch (_) {}
    }
    return isFeatureEnabled(featureKey);
  }

  /// (Legacy) 로컬 플래그 설정 API (setLocalOverride의 별칭)
  Future<void> setLocalFlag(String featureKey, bool value) async {
    if (!_isInitialized) {
      try {
        await init();
      } catch (_) {}
    }
    await setLocalOverride(featureKey, value);
  }

  /// (Legacy) 캐시 초기화 API
  /// - 현재 서비스는 별도의 in-memory 캐시를 두지 않지만, 테스트 호환을 위해 제공한다.
  void clearCache() {
    if (Logger.isVerboseEnabled) Logger.log('🚩 FeatureFlagService.clearCache() 호출됨 (no-op)');
  }

  /// 로컬에서 Feature Flag 오버라이드 (개발/테스트용)
  Future<void> setLocalOverride(String featureKey, bool value) async {
    if (!_isInitialized) {
      if (Logger.isVerboseEnabled) Logger.log('⚠️ FeatureFlagService가 초기화되지 않음');
      return;
    }

    try {
      await _prefs.setBool('local_$featureKey', value);
      if (Logger.isVerboseEnabled) Logger.log('🚩 로컬 오버라이드 설정: $featureKey = $value');
    } catch (e) {
      Logger.error('⚠️ 로컬 오버라이드 설정 오류: $e');
    }
  }

  /// 로컬 오버라이드 제거
  Future<void> removeLocalOverride(String featureKey) async {
    if (!_isInitialized) return;

    try {
      await _prefs.remove('local_$featureKey');
      if (Logger.isVerboseEnabled) Logger.log('🚩 로컬 오버라이드 제거: $featureKey');
    } catch (e) {
      Logger.error('⚠️ 로컬 오버라이드 제거 오류: $e');
    }
  }

  /// Remote Config에서 최신 설정 가져오기
  Future<void> _fetchRemoteConfig() async {
    try {
      await _remoteConfig.fetchAndActivate();
    } catch (e) {
      Logger.error('⚠️ Remote Config 가져오기 오류: $e');
      // 실패해도 캐시된 값 사용
    }
  }

  /// 환경변수에서 값 가져오기 (개발용)
  bool? _getEnvironmentValue(String featureKey) {
    // Flutter에서는 const String.fromEnvironment 사용
    // envKey는 동적으로 생성되므로 각 feature별로 하드코딩 필요
    // 지금은 기능을 비활성화
    return null;
  }

  /// Review Consensus 기능 활성화 여부
  bool get isReviewConsensusEnabled =>
      isFeatureEnabled(FEATURE_REVIEW_CONSENSUS);

  /// 모든 Feature Flag 상태 출력 (디버그용)
  void debugPrintAllFlags() {
    if (!_isInitialized) {
      if (Logger.isVerboseEnabled) Logger.log('⚠️ FeatureFlagService가 초기화되지 않음');
      return;
    }

    if (Logger.isVerboseEnabled) Logger.log('🚩 === Feature Flags 상태 ===');
    if (Logger.isVerboseEnabled) Logger.log(
        '🚩 FEATURE_PROFILE_GRID: ${isFeatureEnabled(FEATURE_PROFILE_GRID)}');
    if (Logger.isVerboseEnabled) Logger.log('🚩 FEATURE_REVIEW_CONSENSUS: ${isReviewConsensusEnabled}');
    if (Logger.isVerboseEnabled) Logger.log('🚩 ========================');
  }
}
