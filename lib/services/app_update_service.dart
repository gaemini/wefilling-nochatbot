import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update_policy.dart';
import 'navigation_service.dart';
import 'release_metadata_service.dart';
import 'firebase_app_check_service.dart';

class ReleaseDiagnostics {
  const ReleaseDiagnostics({
    this.platform = '',
    this.versionName = '',
    this.buildNumber = 0,
    this.applicationId = '',
    this.installerStore = '',
    this.releaseChannel = '',
    this.releaseId = '',
    this.policySource = 'safe_default',
    this.releaseState = 'paused',
    this.minimumBuild = 0,
    this.latestBuild = 0,
    this.storeVerified = false,
    this.decision = 'none',
    this.reason = 'not_initialized',
    this.lastErrorCode = '',
  });

  final String platform;
  final String versionName;
  final int buildNumber;
  final String applicationId;
  final String installerStore;
  final String releaseChannel;
  final String releaseId;
  final String policySource;
  final String releaseState;
  final int minimumBuild;
  final int latestBuild;
  final bool storeVerified;
  final String decision;
  final String reason;
  final String lastErrorCode;

  Map<String, String> toDisplayMap() => {
        'platform': platform,
        'installedVersion': versionName,
        'installedBuild': '$buildNumber',
        'applicationId': applicationId,
        'installerStore': installerStore.isEmpty ? 'unknown' : installerStore,
        'releaseChannel': releaseChannel,
        'releaseId': releaseId,
        'policySource': policySource,
        'releaseState': releaseState,
        'minimumBuild': '$minimumBuild',
        'latestBuild': '$latestBuild',
        'storeVerified': '$storeVerified',
        'decision': decision,
        'reason': reason,
        'lastErrorCode': lastErrorCode,
      };
}

/// Central update policy and prompt coordinator.
///
/// It never trusts Remote Config alone: prompts are only possible for an
/// App/Play Store-installed production artifact after store availability has
/// been verified. Network or store failures degrade to normal app entry.
class AppUpdateService with WidgetsBindingObserver {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static const _cachedPolicyKey = 'release.update_policy.last_good';
  static const _dismissedReleaseKey = 'release.update_optional.dismissed_id';
  static const _dismissedAtKey = 'release.update_optional.dismissed_at';
  static const _optionalCooldown = Duration(days: 3);

  Future<void>? _initialization;
  AppUpdatePolicy? _policy;
  AppUpdateEvaluation _evaluation = const AppUpdateEvaluation(
    decision: AppUpdateDecision.none,
    storeVerified: false,
    reason: 'not_initialized',
  );
  ReleaseDiagnostics _diagnostics = const ReleaseDiagnostics();
  AppUpdateInfo? _androidInfo;
  bool _flexibleReadyToInstall = false;
  Future<void>? _resumeCheck;
  bool _dialogVisible = false;
  bool _optionalShownThisSession = false;
  bool _observerRegistered = false;

  ReleaseDiagnostics get diagnostics => _diagnostics;
  AppUpdatePolicy? get policy => _policy;

  Future<void> initialize() {
    final existing = _initialization;
    if (existing != null) return existing;
    final request = _initializeOnce();
    _initialization = request;
    return request;
  }

  Future<void> _initializeOnce() async {
    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    }
    await ReleaseMetadataService.instance.initialize();
    final metadata = ReleaseMetadataService.instance.metadata;
    final installed = ReleaseMetadataService.instance.installed;
    if (metadata == null || installed == null || kIsWeb) {
      _setEvaluation('identity_unavailable');
      return;
    }

    final fallbackUrl =
        Platform.isIOS ? metadata.ios.storeUrl : metadata.android.storeUrl;
    _policy = await _loadPolicy(fallbackUrl);
    final policy = _policy!;

    if (!kReleaseMode ||
        metadata.releaseChannel != 'production' ||
        !ReleaseMetadataService.instance.identityMatchesManifest) {
      _setEvaluation('non_production_artifact');
      return;
    }
    if (!policy.canPrompt || installed.buildNumber >= policy.latestBuild) {
      _setEvaluation(policy.killSwitch ? 'kill_switch' : 'no_newer_build');
      return;
    }

    if (Platform.isAndroid) {
      await _evaluateAndroid(policy, installed.installerStore);
    } else if (Platform.isIOS) {
      await _evaluateIos(policy, installed.installerStore);
    } else {
      _setEvaluation('unsupported_platform');
    }
  }

  Future<AppUpdatePolicy> _loadPolicy(String fallbackStoreUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _decodeCachedPolicy(prefs.getString(_cachedPolicyKey));
    if (!FirebaseAppCheckService.instance.isReady) {
      _diagnostics = _copyDiagnostics(lastErrorCode: 'app_check_unavailable');
      if (cached != null && cached.isSane) return cached;
      return AppUpdatePolicy(
        killSwitch: true,
        minimumBuild: 0,
        latestBuild: 0,
        latestVersionName: '',
        forceUpdate: false,
        storeUrl: fallbackStoreUrl,
        releaseState: StoreReleaseState.paused,
        releaseId: '',
        source: 'safe_default',
      );
    }
    try {
      final remote = FirebaseRemoteConfig.instance;
      await remote.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 8),
        minimumFetchInterval:
            kDebugMode ? Duration.zero : const Duration(hours: 1),
      ));
      await remote.setDefaults(_safeDefaults(fallbackStoreUrl));
      await remote.fetchAndActivate().timeout(const Duration(seconds: 9));
      final policy = _policyFromRemote(remote, source: 'remote');
      if (policy.isSane) {
        await prefs.setString(_cachedPolicyKey, jsonEncode(policy.toJson()));
        return policy;
      }
    } on TimeoutException {
      _diagnostics = _copyDiagnostics(lastErrorCode: 'policy_timeout');
    } catch (error) {
      _diagnostics = _copyDiagnostics(
        lastErrorCode: _firebaseErrorCode(error),
      );
    }
    if (cached != null && cached.isSane) return cached;
    return AppUpdatePolicy(
      killSwitch: true,
      minimumBuild: 0,
      latestBuild: 0,
      latestVersionName: '',
      forceUpdate: false,
      storeUrl: fallbackStoreUrl,
      releaseState: StoreReleaseState.paused,
      releaseId: '',
      source: 'safe_default',
    );
  }

  Map<String, dynamic> _safeDefaults(String storeUrl) => {
        'update_kill_switch': true,
        'android_minimum_build': 0,
        'android_latest_build': 0,
        'android_force_update': false,
        'android_store_url': storeUrl,
        'android_release_state': 'paused',
        'android_release_id': '',
        'ios_minimum_build': 0,
        'ios_latest_build': 0,
        'ios_latest_version_name': '',
        'ios_force_update': false,
        'ios_store_url': storeUrl,
        'ios_release_state': 'paused',
        'ios_release_id': '',
      };

  AppUpdatePolicy _policyFromRemote(
    FirebaseRemoteConfig remote, {
    required String source,
  }) {
    final prefix = Platform.isIOS ? 'ios' : 'android';
    return AppUpdatePolicy(
      killSwitch: remote.getBool('update_kill_switch'),
      minimumBuild: remote.getInt('${prefix}_minimum_build'),
      latestBuild: remote.getInt('${prefix}_latest_build'),
      latestVersionName:
          Platform.isIOS ? remote.getString('ios_latest_version_name') : '',
      forceUpdate: remote.getBool('${prefix}_force_update'),
      storeUrl: remote.getString('${prefix}_store_url'),
      releaseState:
          parseStoreReleaseState(remote.getString('${prefix}_release_state')),
      releaseId: remote.getString('${prefix}_release_id'),
      source: source,
    );
  }

  AppUpdatePolicy? _decodeCachedPolicy(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      return AppUpdatePolicy.fromJson(
        (jsonDecode(source) as Map).cast<String, dynamic>(),
        source: 'last_good_cache',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _evaluateAndroid(
    AppUpdatePolicy policy,
    String installerStore,
  ) async {
    if (installerStore != 'com.android.vending') {
      _setEvaluation('not_google_play_install');
      return;
    }
    try {
      final info = await InAppUpdate.checkForUpdate()
          .timeout(const Duration(seconds: 8));
      _androidInfo = info;
      _flexibleReadyToInstall = info.installStatus == InstallStatus.downloaded;
      final available =
          info.updateAvailability == UpdateAvailability.updateAvailable ||
              info.updateAvailability ==
                  UpdateAvailability.developerTriggeredUpdateInProgress;
      if ((!available && !_flexibleReadyToInstall) ||
          (info.availableVersionCode ?? 0) < policy.latestBuild) {
        _setEvaluation('play_update_not_available');
        return;
      }
      final installedBuild =
          ReleaseMetadataService.instance.installed?.buildNumber ?? 0;
      final mandatory = policy.releaseState == StoreReleaseState.active &&
          policy.source == 'remote' &&
          policy.forceUpdate &&
          installedBuild < policy.minimumBuild &&
          info.immediateUpdateAllowed;
      _evaluation = AppUpdateEvaluation(
        decision: mandatory
            ? AppUpdateDecision.mandatory
            : AppUpdateDecision.optional,
        storeVerified: true,
        reason: mandatory ? 'below_minimum_build' : 'newer_play_build',
      );
      _refreshDiagnostics();
    } catch (error) {
      _setEvaluation('play_check_failed', errorCode: _firebaseErrorCode(error));
    }
  }

  Future<void> _evaluateIos(
    AppUpdatePolicy policy,
    String installerStore,
  ) async {
    if (installerStore != 'com.apple') {
      _setEvaluation('not_app_store_install');
      return;
    }
    final metadata = ReleaseMetadataService.instance.metadata!;
    try {
      final uri = Uri.https('itunes.apple.com', '/lookup', {
        'id': metadata.ios.appStoreId,
        'country': 'kr',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        _setEvaluation('app_store_lookup_failed');
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = body['results'] as List? ?? const [];
      if (results.isEmpty) {
        _setEvaluation('app_store_listing_unavailable');
        return;
      }
      final listedVersion =
          ((results.first as Map)['version'] ?? '').toString().trim();
      if (policy.latestVersionName.isEmpty ||
          _compareVersions(listedVersion, policy.latestVersionName) < 0 ||
          _compareVersions(
                listedVersion,
                ReleaseMetadataService.instance.installed!.versionName,
              ) <=
              0) {
        _setEvaluation('app_store_version_not_ready');
        return;
      }
      final installedBuild =
          ReleaseMetadataService.instance.installed?.buildNumber ?? 0;
      final mandatory = policy.releaseState == StoreReleaseState.active &&
          policy.source == 'remote' &&
          policy.forceUpdate &&
          installedBuild < policy.minimumBuild;
      _evaluation = AppUpdateEvaluation(
        decision: mandatory
            ? AppUpdateDecision.mandatory
            : AppUpdateDecision.optional,
        storeVerified: true,
        reason: mandatory ? 'below_minimum_build' : 'newer_app_store_version',
      );
      _refreshDiagnostics();
    } catch (error) {
      _setEvaluation('app_store_check_failed',
          errorCode: _firebaseErrorCode(error));
    }
  }

  Future<void> presentIfNeeded() async {
    if (_dialogVisible || _evaluation.decision == AppUpdateDecision.none) {
      return;
    }
    final context = NavigationService.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    if (_evaluation.decision == AppUpdateDecision.optional) {
      if (!_flexibleReadyToInstall &&
          (_optionalShownThisSession || await _optionalDismissalActive())) {
        return;
      }
      _optionalShownThisSession = true;
    }
    if (!context.mounted) return;
    _dialogVisible = true;
    _logEvent(_evaluation.decision == AppUpdateDecision.mandatory
        ? 'mandatoryBlockStarted'
        : 'optionalPromptShown');
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: _evaluation.decision != AppUpdateDecision.mandatory,
        builder: (dialogContext) => PopScope(
          canPop: _evaluation.decision != AppUpdateDecision.mandatory,
          child: AlertDialog(
            title: Text(_isKorean(dialogContext)
                ? '새 버전이 준비됐어요'
                : 'A new version is ready'),
            content: Text(_isKorean(dialogContext)
                ? (_flexibleReadyToInstall
                    ? '업데이트 다운로드가 끝났어요. 앱을 다시 시작해 설치를 완료해 주세요.'
                    : _evaluation.decision == AppUpdateDecision.mandatory
                        ? '계속 사용하려면 최신 버전으로 업데이트해 주세요.'
                        : '더 안정적인 사용을 위해 최신 버전으로 업데이트할 수 있어요.')
                : (_flexibleReadyToInstall
                    ? 'The update is downloaded. Restart the app to finish installing.'
                    : _evaluation.decision == AppUpdateDecision.mandatory
                        ? 'Update to the latest version to continue.'
                        : 'Update now for the latest improvements.')),
            actions: [
              if (_evaluation.decision == AppUpdateDecision.optional)
                TextButton(
                  onPressed: () async {
                    await _rememberOptionalDismissal();
                    _logEvent('optionalPromptDismissed');
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: Text(_isKorean(dialogContext) ? '나중에' : 'Later'),
                ),
              FilledButton(
                onPressed: () => _startUpdate(dialogContext),
                child: Text(_isKorean(dialogContext)
                    ? (_flexibleReadyToInstall ? '설치' : '업데이트')
                    : (_flexibleReadyToInstall ? 'Install' : 'Update')),
              ),
            ],
          ),
        ),
      );
    } finally {
      _dialogVisible = false;
    }
  }

  Future<void> _startUpdate(BuildContext dialogContext) async {
    var handedOff = false;
    _logEvent('updateStarted');
    try {
      if (Platform.isAndroid && _androidInfo != null) {
        if (_flexibleReadyToInstall) {
          await InAppUpdate.completeFlexibleUpdate();
          handedOff = true;
        } else if (_evaluation.decision == AppUpdateDecision.mandatory &&
            _androidInfo!.immediateUpdateAllowed) {
          final result = await InAppUpdate.performImmediateUpdate();
          if (result == AppUpdateResult.success) {
            handedOff = true;
          } else if (result == AppUpdateResult.userDeniedUpdate) {
            // Keep the verified mandatory dialog in place.
            return;
          }
        } else if (_androidInfo!.flexibleUpdateAllowed) {
          final result = await InAppUpdate.startFlexibleUpdate();
          if (result == AppUpdateResult.success) {
            await InAppUpdate.completeFlexibleUpdate();
            handedOff = true;
          } else if (result == AppUpdateResult.userDeniedUpdate) {
            await _rememberOptionalDismissal();
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            return;
          }
        }
      }
      if (!handedOff) {
        final metadata = ReleaseMetadataService.instance.metadata;
        final url =
            Platform.isIOS && metadata?.ios.appStoreId.isNotEmpty == true
                ? Uri.parse(
                    'itms-apps://itunes.apple.com/app/id${metadata!.ios.appStoreId}',
                  )
                : Uri.tryParse(_policy?.storeUrl ?? '');
        if (url != null) {
          handedOff =
              await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      }
    } catch (_) {
      handedOff = false;
    }
    if (!handedOff) {
      // A mandatory prompt must never trap a user when the Store cannot open.
      _setEvaluation('store_handoff_failed');
      _logEvent('updateFailed');
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      return;
    }
    if (_evaluation.decision == AppUpdateDecision.optional &&
        dialogContext.mounted) {
      Navigator.pop(dialogContext);
    }
  }

  Future<bool> _optionalDismissalActive() async {
    final policy = _policy;
    if (policy == null) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_dismissedReleaseKey) != policy.releaseId) return false;
    final millis = prefs.getInt(_dismissedAtKey);
    if (millis == null) return false;
    return DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(millis),
        ) <
        _optionalCooldown;
  }

  Future<void> _rememberOptionalDismissal() async {
    final policy = _policy;
    if (policy == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedReleaseKey, policy.releaseId);
    await prefs.setInt(
      _dismissedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Re-read the installed version on the next process launch. During this
    // process, Play Core can resume an already-triggered immediate update.
    if (Platform.isAndroid &&
        _androidInfo?.updateAvailability ==
            UpdateAvailability.developerTriggeredUpdateInProgress) {
      unawaited(_resumeImmediateAndroidUpdate());
    }
    if (Platform.isAndroid && _policy?.canPrompt == true) {
      final active = _resumeCheck;
      if (active == null) {
        final request = _recheckAndroidOnResume();
        _resumeCheck = request;
        unawaited(request.whenComplete(() {
          if (identical(_resumeCheck, request)) _resumeCheck = null;
        }));
      }
    } else {
      unawaited(presentIfNeeded());
    }
  }

  Future<void> _recheckAndroidOnResume() async {
    final installed = ReleaseMetadataService.instance.installed;
    final policy = _policy;
    if (installed == null || policy == null) return;
    await _evaluateAndroid(policy, installed.installerStore);
    await presentIfNeeded();
  }

  Future<void> _resumeImmediateAndroidUpdate() async {
    try {
      await InAppUpdate.performImmediateUpdate();
    } catch (_) {
      // Play Core will be checked again on the next process launch/resume.
    }
  }

  void _setEvaluation(String reason, {String errorCode = ''}) {
    _evaluation = AppUpdateEvaluation(
      decision: AppUpdateDecision.none,
      storeVerified: false,
      reason: reason,
    );
    _refreshDiagnostics(lastErrorCode: errorCode);
    if (reason.contains('failed') || errorCode.isNotEmpty) {
      _logEvent('updateCheckFailed');
    }
  }

  void _refreshDiagnostics({String? lastErrorCode}) {
    final metadata = ReleaseMetadataService.instance.metadata;
    final installed = ReleaseMetadataService.instance.installed;
    final policy = _policy;
    _diagnostics = ReleaseDiagnostics(
      platform: kIsWeb ? 'web' : Platform.operatingSystem,
      versionName: installed?.versionName ?? '',
      buildNumber: installed?.buildNumber ?? 0,
      applicationId: installed?.applicationId ?? '',
      installerStore: installed?.installerStore ?? '',
      releaseChannel: metadata?.releaseChannel ?? '',
      releaseId: policy?.releaseId ?? metadata?.releaseId ?? '',
      policySource: policy?.source ?? 'safe_default',
      releaseState: policy?.releaseState.name ?? 'paused',
      minimumBuild: policy?.minimumBuild ?? 0,
      latestBuild: policy?.latestBuild ?? 0,
      storeVerified: _evaluation.storeVerified,
      decision: _evaluation.decision.name,
      reason: _evaluation.reason,
      lastErrorCode: lastErrorCode ?? _diagnostics.lastErrorCode,
    );
    if (kDebugMode) {
      debugPrint('[UpdatePolicy] platform=${_diagnostics.platform} '
          'build=${_diagnostics.buildNumber} state=${_diagnostics.releaseState} '
          'decision=${_diagnostics.decision} reason=${_diagnostics.reason} '
          'storeVerified=${_diagnostics.storeVerified}');
    }
    if (_evaluation.decision != AppUpdateDecision.none) {
      _logEvent('updateDetected');
    }
  }

  ReleaseDiagnostics _copyDiagnostics({required String lastErrorCode}) =>
      ReleaseDiagnostics(
        platform: _diagnostics.platform,
        versionName: _diagnostics.versionName,
        buildNumber: _diagnostics.buildNumber,
        applicationId: _diagnostics.applicationId,
        installerStore: _diagnostics.installerStore,
        releaseChannel: _diagnostics.releaseChannel,
        releaseId: _diagnostics.releaseId,
        policySource: _diagnostics.policySource,
        releaseState: _diagnostics.releaseState,
        minimumBuild: _diagnostics.minimumBuild,
        latestBuild: _diagnostics.latestBuild,
        storeVerified: _diagnostics.storeVerified,
        decision: _diagnostics.decision,
        reason: _diagnostics.reason,
        lastErrorCode: lastErrorCode,
      );

  static int _compareVersions(String left, String right) {
    final a = left.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final b = right.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  static bool _isKorean(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ko';

  static String _firebaseErrorCode(Object error) {
    final text = error.toString().toLowerCase();
    if (error is TimeoutException) return 'timeout';
    if (text.contains('app check')) return 'app_check';
    if (text.contains('network')) return 'network';
    if (text.contains('permission-denied')) return 'permission_denied';
    return 'unavailable';
  }

  void _logEvent(String event) {
    if (!kDebugMode) return;
    debugPrint('[ReleaseEvent] event=$event '
        'platform=${_diagnostics.platform} '
        'version=${_diagnostics.versionName} '
        'build=${_diagnostics.buildNumber} '
        'releaseState=${_diagnostics.releaseState} '
        'decision=${_diagnostics.decision} '
        'storeVerified=${_diagnostics.storeVerified} '
        'errorCode=${_diagnostics.lastErrorCode}');
  }
}
